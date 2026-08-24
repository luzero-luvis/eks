variable "cluster_name" {
  description = "Cluster Karpenter provisions nodes for"
  type        = string
}

variable "cluster_endpoint" {
  description = "Kubernetes API endpoint, passed to the Karpenter controller"
  type        = string
}

variable "discovery_tag_value" {
  description = "Value of the karpenter.sh/discovery tag on subnets and security groups"
  type        = string
}

variable "chart_version" {
  description = "Karpenter Helm chart version — https://gallery.ecr.aws/karpenter/karpenter"
  type        = string
}

variable "namespace" {
  description = "Namespace the Karpenter controller runs in"
  type        = string
  default     = "karpenter"
}

variable "replicas" {
  description = "Karpenter controller replicas — 2 for HA"
  type        = number
  default     = 2
}

variable "node_iam_role_additional_policies" {
  description = "Extra IAM policies for Karpenter-provisioned nodes, on top of SSM core"
  type        = map(string)
  default     = {}
}

# ── EC2NodeClass ─────────────────────────────────────────────────────────────

variable "ami_alias" {
  description = "EKS-optimized AMI alias. Pin an exact version in prod, never @latest"
  type        = string
  default     = "al2023@v20260501"
}

variable "node_volume_size" {
  description = "Root volume size in GiB for Karpenter-provisioned nodes"
  type        = number
  default     = 50
}

variable "node_volume_type" {
  description = "Root volume type for Karpenter-provisioned nodes"
  type        = string
  default     = "gp3"
}

# ── NodePool ─────────────────────────────────────────────────────────────────

variable "availability_zones" {
  description = "AZs Karpenter may launch nodes in"
  type        = list(string)
}

variable "capacity_types" {
  description = "Capacity types in preference order — Karpenter falls back automatically"
  type        = list(string)
  default     = ["spot", "on-demand"]
}

variable "architectures" {
  description = "CPU architectures Karpenter may launch"
  type        = list(string)
  default     = ["amd64"]
}

variable "instance_categories" {
  description = "Instance families Karpenter may pick from — keep broad for Spot depth"
  type        = list(string)
  default     = ["c", "m", "r"]
}

variable "min_instance_generation" {
  description = "Exclude instance generations at or below this number"
  type        = number
  default     = 2
}

variable "expire_after" {
  description = "Replace nodes after this duration — forces AMI refresh"
  type        = string
  default     = "720h"
}

variable "consolidate_after" {
  description = "How long a node must be empty or underutilized before consolidation"
  type        = string
  default     = "5m"
}

variable "disruption_budget_nodes" {
  description = "Maximum share of nodes disrupted at once during consolidation"
  type        = string
  default     = "10%"
}

variable "cpu_limit" {
  description = "Hard cap on total vCPUs Karpenter may provision"
  type        = number
  default     = 1000
}

variable "memory_limit" {
  description = "Hard cap on total memory Karpenter may provision"
  type        = string
  default     = "2000Gi"
}

variable "tags" {
  description = "Tags applied to Karpenter IAM and SQS resources"
  type        = map(string)
  default     = {}
}
