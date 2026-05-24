variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "prod-eks"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.35"
}

variable "project" {
  description = "Project name used in tags"
  type        = string
  default     = "luvis"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "owner" {
  description = "Team or person owning this cluster"
  type        = string
  default     = "platform"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# Restrict public API endpoint to specific CIDRs (your corporate/VPN ranges).
# Set to ["0.0.0.0/0"] only temporarily — always lock down in prod.
variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "system_node_instance_types" {
  description = "Instance types for the system (Karpenter + add-ons) node group"
  type        = list(string)
  default     = ["m5.large", "m5a.large", "m6i.large"]
}

variable "system_node_min_size" {
  type    = number
  default = 2
}

variable "system_node_max_size" {
  type    = number
  default = 4
}

variable "system_node_desired_size" {
  type    = number
  default = 2
}

# Karpenter Helm chart version — check https://gallery.ecr.aws/karpenter/karpenter
variable "karpenter_version" {
  description = "Karpenter Helm chart version"
  type        = string
  default     = "1.12.1"
}

# ALB controller Helm chart version — check https://github.com/aws/eks-charts/blob/master/stable/aws-load-balancer-controller/Chart.yaml
variable "alb_controller_version" {
  description = "AWS Load Balancer Controller Helm chart version"
  type        = string
  default     = "3.3.0"
}
