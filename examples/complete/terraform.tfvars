region       = "us-east-1"
cluster_name = "example-cluster"

# From the EKS module outputs
oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
oidc_provider_url = "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"

# Pin the chart: Karpenter has changed CRDs between minor versions
chart_version = "1.6.0"
replica_count = 2

# Run the controller on the managed node group, never on Karpenter capacity
controller_node_selector = {
  "eks.amazonaws.com/nodegroup" = "example-cluster-general"
}

tags = {
  Project   = "example"
  ManagedBy = "terraform"
}
