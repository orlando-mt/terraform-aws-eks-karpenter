provider "aws" {
  region = var.region
}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
    }
  }
}

module "karpenter" {
  source = "../../"

  cluster_name     = var.cluster_name
  cluster_endpoint = data.aws_eks_cluster.this.endpoint

  oidc_provider_arn = var.oidc_provider_arn
  oidc_provider_url = var.oidc_provider_url

  chart_version = var.chart_version
  replica_count = var.replica_count

  # Keep the controller off the capacity it manages
  controller_node_selector = var.controller_node_selector

  tags = var.tags
}
