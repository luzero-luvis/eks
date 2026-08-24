variable "name" {
  description = "Name of the managed node group"
  type        = string
}

variable "cluster_name" {
  description = "Cluster the node group joins"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the nodes. null tracks the control-plane version"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Subnets the nodes are launched in — private subnets"
  type        = list(string)
}

variable "cluster_primary_security_group_id" {
  description = "Cluster primary security group, from the control-plane module"
  type        = string
}

variable "vpc_security_group_ids" {
  description = "Security groups attached to the nodes — normally the shared node security group"
  type        = list(string)
}

variable "cluster_service_cidr" {
  description = "Service CIDR of the cluster, used by the node bootstrap"
  type        = string
}

variable "cluster_ip_family" {
  description = "IP family of the cluster (ipv4 / ipv6)"
  type        = string
  default     = "ipv4"
}

variable "instance_types" {
  description = "Instance types the node group may launch"
  type        = list(string)
}

variable "capacity_type" {
  description = "ON_DEMAND or SPOT"
  type        = string
  default     = "ON_DEMAND"
}

variable "ami_type" {
  description = "EKS AMI type"
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "min_size" {
  description = "Minimum number of nodes"
  type        = number
}

variable "max_size" {
  description = "Maximum number of nodes"
  type        = number
}

variable "desired_size" {
  description = "Desired number of nodes at creation. Ignored on later applies if changed out of band"
  type        = number
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB"
  type        = number
  default     = 50
}

variable "root_volume_type" {
  description = "Root EBS volume type"
  type        = string
  default     = "gp3"
}

variable "root_volume_encrypted" {
  description = "Encrypt the root volume with the AWS-managed EBS key"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Kubernetes labels applied to the nodes"
  type        = map(string)
  default     = null
}

variable "taints" {
  description = "Kubernetes taints applied to the nodes"
  type = map(object({
    key    = string
    value  = optional(string)
    effect = string
  }))
  default = null
}

variable "enable_node_repair" {
  description = "Let EKS auto-replace nodes reported unhealthy by the node monitoring agent"
  type        = bool
  default     = false
}

variable "iam_role_additional_policies" {
  description = "Extra IAM policies attached to the node role, keyed by a stable name"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to all resources created by this module"
  type        = map(string)
  default     = {}
}
