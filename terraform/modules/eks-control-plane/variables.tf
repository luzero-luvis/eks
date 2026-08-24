variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the control plane"
  type        = string
}

variable "vpc_id" {
  description = "VPC the cluster is created in"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets the cluster can place worker node ENIs in — private subnets"
  type        = list(string)
}

variable "control_plane_subnet_ids" {
  description = "Subnets for the control-plane cross-account ENIs — intra subnets"
  type        = list(string)
}

variable "endpoint_public_access" {
  description = "Expose the Kubernetes API on a public endpoint"
  type        = bool
  default     = true
}

variable "endpoint_private_access" {
  description = "Expose the Kubernetes API inside the VPC — required for nodes to reach the API privately"
  type        = bool
  default     = true
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "encryption_config" {
  description = "Secrets envelope encryption config. null disables it and prevents the module creating a KMS key"
  type = object({
    provider_key_arn = optional(string)
    resources        = optional(list(string), ["secrets"])
  })
  default = null
}

variable "enabled_log_types" {
  description = "Control-plane log types shipped to CloudWatch"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "enable_cluster_creator_admin_permissions" {
  description = "Give the identity running Terraform cluster-admin via an EKS access entry"
  type        = bool
  default     = true
}

variable "node_security_group_additional_rules" {
  description = "Extra rules added to the shared node security group"
  type = map(object({
    protocol                      = optional(string, "tcp")
    from_port                     = number
    to_port                       = number
    type                          = optional(string, "ingress")
    description                   = optional(string)
    cidr_blocks                   = optional(list(string))
    ipv6_cidr_blocks              = optional(list(string))
    prefix_list_ids               = optional(list(string))
    self                          = optional(bool)
    source_cluster_security_group = optional(bool, false)
    source_security_group_id      = optional(string)
  }))
  default = {}
}

variable "tags" {
  description = "Tags applied to all resources created by this module"
  type        = map(string)
  default     = {}
}
