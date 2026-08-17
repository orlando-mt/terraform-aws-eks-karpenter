output "node_role_name" {
  description = "Use this in the EC2NodeClass role field"
  value       = module.karpenter.node_role_name
}

output "controller_role_arn" {
  description = "IRSA role used by the controller"
  value       = module.karpenter.controller_role_arn
}

output "interruption_queue_name" {
  description = "Queue Karpenter watches for interruption events"
  value       = module.karpenter.interruption_queue_name
}
