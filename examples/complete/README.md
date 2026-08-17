# Complete example

Installs Karpenter on an existing cluster, together with:

- The controller IRSA role and its IAM policy
- The node role and its access entry
- The interruption queue and EventBridge rules

The controller is pinned to the managed node group through
`controller_node_selector`, so it never runs on the capacity it provisions.

Replace the cluster name and OIDC values in
[`terraform.tfvars`](./terraform.tfvars) with your own.

## Usage

```bash
terraform init
terraform plan
terraform apply
```

## Then create a NodePool

Karpenter provisions nothing until a `NodePool` and an `EC2NodeClass` exist.
Apply them with kubectl or through GitOps — see the module README for a
ready-to-adapt pair.

```bash
kubectl get nodepools
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -f
```
