variable "region" {
  description = "AWS region"
  type        = string
}

variable "cluster_name" {
  description = "Name of an existing EKS cluster"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster OIDC provider"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC issuer URL of the cluster"
  type        = string
}

variable "chart_version" {
  description = "Karpenter chart version"
  type        = string
  default     = null
}

variable "replica_count" {
  description = "Controller replicas"
  type        = number
  default     = 2
}

variable "controller_node_selector" {
  description = "Node selector for the controller pods"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to all AWS resources"
  type        = map(string)
  default     = {}
}
