output "controller_role_arn" {
  description = "ARN of the controller IRSA role"
  value       = aws_iam_role.controller.arn
}

output "node_role_arn" {
  description = "ARN of the role assumed by provisioned nodes"
  value       = aws_iam_role.node.arn
}

output "node_role_name" {
  description = "Name of the node role. Reference it in the EC2NodeClass role field"
  value       = aws_iam_role.node.name
}

output "interruption_queue_name" {
  description = "Name of the interruption queue"
  value       = aws_sqs_queue.interruption.name
}

output "interruption_queue_arn" {
  description = "ARN of the interruption queue"
  value       = aws_sqs_queue.interruption.arn
}

output "service_account_name" {
  description = "Service account used by the controller"
  value       = local.service_account_name
}

output "namespace" {
  description = "Namespace where the controller runs"
  value       = var.namespace
}

output "chart_version" {
  description = "Chart version installed (null when the release is managed elsewhere)"
  value       = var.install_controller ? helm_release.this[0].version : null
}
