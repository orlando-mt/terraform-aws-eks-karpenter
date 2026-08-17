# terraform-aws-karpenter

Terraform module to install [Karpenter](https://karpenter.sh) on an EKS cluster, with its IRSA role, node role, interruption queue and EventBridge rules.

## Design

**The module covers the AWS side and the controller install; NodePools are not created here.** A `NodePool` and an `EC2NodeClass` describe what capacity a workload needs — instance families, architectures, disruption budgets — and change as the workloads do. They belong with the applications, in GitOps or in the team's manifests, not in the module that sets up the platform. It also avoids the chicken-and-egg problem of Terraform planning custom resources whose CRDs the same apply is about to install.

**Karpenter must not run on the capacity it manages.** If the controller sits on a node it provisioned, consolidating or reclaiming that node takes the controller down with it, and nothing brings the cluster back. Use `controller_node_selector` to pin it to a small managed node group.

## Features

- Controller installed from the official OCI chart, with the IRSA role scoped to its service account
- **Node role with an EKS access entry**, which is how nodes register with a cluster using API authentication mode — the `aws-auth` ConfigMap is no longer involved
- **Interruption queue and EventBridge rules** for Spot reclaims, rebalance recommendations, instance state changes and scheduled maintenance, so nodes drain gracefully instead of disappearing under running pods
- **Controller policy scoped by cluster ownership tags**: it can only terminate and retag instances tagged for this cluster, and `iam:PassRole` is limited to the node role, so a compromised controller cannot attach an arbitrary role to an instance
- SSM access on nodes by default, for Session Manager instead of SSH

## Usage

```hcl
module "karpenter" {
  source = "github.com/orlando-mt/terraform-aws-karpenter?ref=v1.0.0"

  cluster_name     = module.eks.cluster_name
  cluster_endpoint = module.eks.cluster_endpoint

  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  chart_version = "1.6.0"

  controller_node_selector = {
    "eks.amazonaws.com/nodegroup" = "my-cluster-general"
  }

  tags = {
    Project   = "my-project"
    ManagedBy = "terraform"
  }
}
```

## Discovery tags are required

Karpenter finds subnets and security groups by tag. Without them it provisions nothing and logs a discovery error that is easy to misread as a permissions problem.

```hcl
# On every subnet Karpenter may launch nodes into
tags = {
  "karpenter.sh/discovery" = "my-cluster"
}
```

[terraform-aws-eks](https://github.com/orlando-mt/terraform-aws-eks) already tags the cluster and node security groups this way; the subnets come from your VPC, so tag them there.

## Creating a NodePool

Nothing scales until a NodePool exists. A reasonable starting pair:

```yaml
apiVersion: karpenter.sh/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  role: my-cluster-karpenter-node        # node_role_name output
  amiSelectorTerms:
    - alias: al2023@latest
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: my-cluster
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: my-cluster
---
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64", "amd64"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m", "r"]
  limits:
    cpu: "1000"
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
```

> **Consolidation moves pods.** `WhenEmptyOrUnderutilized` repacks workloads onto fewer nodes, which is where most of the savings come from — and it will evict pods to do it. Give anything that cannot tolerate a restart a `PodDisruptionBudget`, or use `WhenEmpty` for that NodePool.

> **Pin the chart version.** Karpenter has changed CRD versions between minor releases; upgrading the chart without reading the release notes can leave existing NodePools unreadable.

## Examples

- [Complete](./examples/complete)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.9.0 |
| aws | >= 5.0 |
| helm | >= 2.12, < 3.0 |

## Resources

| Name | Type |
|------|------|
| helm_release.this | resource |
| aws_iam_role.controller | resource |
| aws_iam_role_policy.controller | resource |
| aws_iam_role.node | resource |
| aws_iam_role_policy_attachment.node | resource |
| aws_eks_access_entry.node | resource |
| aws_sqs_queue.interruption | resource |
| aws_sqs_queue_policy.interruption | resource |
| aws_cloudwatch_event_rule.interruption | resource |
| aws_cloudwatch_event_target.interruption | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cluster_name | EKS cluster name | `string` | n/a | yes |
| cluster_endpoint | Cluster API endpoint | `string` | n/a | yes |
| oidc_provider_arn | Cluster OIDC provider ARN | `string` | n/a | yes |
| oidc_provider_url | Cluster OIDC issuer URL | `string` | n/a | yes |
| controller_role_name | Controller role name | `string` | `null` (derived) | no |
| node_role_name | Node role name | `string` | `null` (derived) | no |
| enable_node_ssm | Attach SSM policy to nodes | `bool` | `true` | no |
| node_additional_policy_arns | Extra node policies | `list(string)` | `[]` | no |
| create_node_access_entry | Register the node role | `bool` | `true` | no |
| interruption_queue_name | Queue name | `string` | `null` (derived) | no |
| interruption_queue_kms_key_id | Queue KMS key | `string` | `null` | no |
| install_controller | Install the Helm release | `bool` | `true` | no |
| release_name | Helm release name | `string` | `"karpenter"` | no |
| chart_version | Chart version | `string` | `null` (latest) | no |
| namespace / create_namespace | Controller namespace | `string` / `bool` | `"kube-system"` / `false` | no |
| replica_count | Controller replicas | `number` | `2` | no |
| controller_node_selector | Pin the controller | `map(string)` | `{}` | no |
| timeout | Helm timeout (seconds) | `number` | `600` | no |
| helm_values | Extra Helm values | `map(string)` | `{}` | no |
| tags | Tags for AWS resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| controller_role_arn | Controller IRSA role |
| node_role_arn / node_role_name | Node role, for the EC2NodeClass |
| interruption_queue_name / _arn | Interruption queue |
| service_account_name / namespace | Controller location |
| chart_version | Installed chart version |
<!-- END_TF_DOCS -->

## License

MIT. See [LICENSE](./LICENSE).
