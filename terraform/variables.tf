variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-south-1"
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

# One NAT gateway per AZ costs ~$97/month and keeps each AZ self-sufficient for
# egress. A single NAT costs ~$33/month but makes one AZ a dependency for all
# outbound traffic, and adds ~$0.01/GB cross-AZ charges on egress from the other
# two AZs. Per-AZ becomes the cheaper option above roughly 4-5 TB/month of NAT
# egress. Set to true for dev/staging or any cluster with modest egress.
variable "single_nat_gateway" {
  description = "Route all egress through one NAT gateway instead of one per AZ"
  type        = bool
  default     = true
}

# Restrict public API endpoint to specific CIDRs (your corporate/VPN ranges).
# Set to ["0.0.0.0/0"] only temporarily — always lock down in prod.
variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ── VPC endpoints ────────────────────────────────────────────────────────────

variable "enable_s3_endpoint" {
  description = "S3 gateway endpoint. Free, and ECR image layers live in S3 — leave this on"
  type        = bool
  default     = true
}

# Recommended set when you want image pulls and IRSA to stop depending on the
# NAT gateway: ["ecr.api", "ecr.dkr", "sts"]. Budget ~$22/month per service
# across 3 AZs, versus $0.045/GB of NAT data processing saved.
variable "interface_endpoints" {
  description = "AWS services to reach over interface VPC endpoints"
  type        = list(string)
  default     = []
}

# ── API Gateway ──────────────────────────────────────────────────────────────

variable "enable_api_gateway" {
  description = "Create an HTTP API + VPC Link + internal NLB in front of cluster workloads"
  type        = bool
  default     = false
}

variable "api_gateway_target_port" {
  description = "Container port the API Gateway target group forwards to"
  type        = number
  default     = 8080
}

variable "api_gateway_health_check_path" {
  description = "HTTP health check path for the API Gateway target group"
  type        = string
  default     = "/healthz"
}

variable "api_gateway_throttling_rate_limit" {
  description = "Steady-state requests per second allowed through the API"
  type        = number
  default     = 1000
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
