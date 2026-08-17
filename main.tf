data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  service_account_name = "karpenter"
  oidc_issuer          = replace(var.oidc_provider_url, "https://", "")
  queue_name           = coalesce(var.interruption_queue_name, "${var.cluster_name}-karpenter")
}

resource "helm_release" "this" {
  count = var.install_controller ? 1 : 0

  name       = var.release_name
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.chart_version
  namespace  = var.namespace

  create_namespace = var.create_namespace
  timeout          = var.timeout
  wait             = true
  cleanup_on_fail  = true

  set {
    name  = "settings.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "settings.clusterEndpoint"
    value = var.cluster_endpoint
  }

  # Karpenter watches this queue to drain nodes before they are reclaimed
  set {
    name  = "settings.interruptionQueue"
    value = aws_sqs_queue.interruption.name
  }

  set {
    name  = "serviceAccount.name"
    value = local.service_account_name
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.controller.arn
  }

  set {
    name  = "replicas"
    value = var.replica_count
  }

  # The controller cannot run on nodes it manages: if it did, terminating
  # that node would take the controller down with it.
  dynamic "set" {
    for_each = var.controller_node_selector
    content {
      name  = "nodeSelector.${replace(set.key, ".", "\\.")}"
      value = set.value
    }
  }

  dynamic "set" {
    for_each = var.helm_values
    content {
      name  = set.key
      value = set.value
    }
  }

  depends_on = [
    aws_iam_role_policy.controller,
    aws_eks_access_entry.node
  ]
}
