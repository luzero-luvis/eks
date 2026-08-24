variable "name" {
  description = "Name of the IAM role"
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN of the cluster, from the control-plane module"
  type        = string
}

variable "namespace_service_accounts" {
  description = "Service accounts allowed to assume the role, as \"namespace:serviceaccount\""
  type        = list(string)
}

variable "attach_ebs_csi_policy" {
  description = "Attach the AWS-managed policy set for the EBS CSI driver"
  type        = bool
  default     = false
}

variable "attach_load_balancer_controller_policy" {
  description = "Attach the AWS-managed policy set for the AWS Load Balancer Controller"
  type        = bool
  default     = false
}

variable "policies" {
  description = "Additional managed policy ARNs to attach, keyed by a stable name"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to the IAM role"
  type        = map(string)
  default     = {}
}
