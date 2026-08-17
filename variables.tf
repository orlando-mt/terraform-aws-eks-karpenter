variable "cluster_name" {
  description = "Name of the EKS cluster Karpenter provisions nodes for"
  type        = string
}

variable "cluster_endpoint" {
  description = "API endpoint of the cluster, passed to the controller settings"
  type        = string
}

# --- IRSA ------------------------------------------------------------------

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC issuer URL of the cluster (with or without the https:// prefix)"
  type        = string
}

variable "controller_role_name" {
  description = "Name of the controller IRSA role (defaults to <cluster_name>-karpenter-controller)"
  type        = string
  default     = null
}

# --- Node role -------------------------------------------------------------

variable "node_role_name" {
  description = "Name of the role assumed by provisioned nodes (defaults to <cluster_name>-karpenter-node)"
  type        = string
  default     = null
}

variable "enable_node_ssm" {
  description = "Attach AmazonSSMManagedInstanceCore so nodes can be reached through Session Manager"
  type        = bool
  default     = true
}

variable "node_additional_policy_arns" {
  description = "Extra policies attached to the node role"
  type        = list(string)
  default     = []
}

variable "create_node_access_entry" {
  description = "Register the node role with the cluster through an access entry. Required with API authentication mode; disable it if the cluster still uses the aws-auth ConfigMap"
  type        = bool
  default     = true
}

# --- Interruption queue ----------------------------------------------------

variable "interruption_queue_name" {
  description = "Name of the interruption queue (defaults to <cluster_name>-karpenter)"
  type        = string
  default     = null
}

variable "interruption_queue_kms_key_id" {
  description = "Customer managed key for the interruption queue. When null, SQS-managed encryption is used"
  type        = string
  default     = null
}

# --- Helm release ----------------------------------------------------------

variable "install_controller" {
  description = "Install the Karpenter controller with Helm. Set false to manage the release elsewhere and keep only the AWS resources"
  type        = bool
  default     = true
}

variable "release_name" {
  description = "Name of the Helm release"
  type        = string
  default     = "karpenter"
}

variable "chart_version" {
  description = "Version of the Karpenter chart. Pin it: Karpenter minor releases have changed CRDs in the past"
  type        = string
  default     = null
}

variable "namespace" {
  description = "Namespace where the controller runs"
  type        = string
  default     = "kube-system"
}

variable "create_namespace" {
  description = "Create the namespace"
  type        = bool
  default     = false
}

variable "replica_count" {
  description = "Number of controller replicas. Two spreads the leader election across AZs"
  type        = number
  default     = 2
}

variable "controller_node_selector" {
  description = <<-EOT
    Node selector pinning the controller to nodes it does not manage, such as
    a small managed node group. Karpenter must not run on the capacity it
    provisions: terminating that node would take the controller with it.
  EOT
  type        = map(string)
  default     = {}
}

variable "timeout" {
  description = "Helm release timeout in seconds"
  type        = number
  default     = 600
}

variable "helm_values" {
  description = "Additional Helm values as a flat map of key to value"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to all AWS resources"
  type        = map(string)
  default     = {}
}
