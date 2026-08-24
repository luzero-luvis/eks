variable "name" {
  description = "Name prefix for the VPC and all subnets"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name — used for the karpenter.sh/discovery subnet tag"
  type        = string
}

variable "cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "azs" {
  description = "Availability zones to spread the subnets across"
  type        = list(string)
}

variable "private_subnets" {
  description = "CIDR blocks for the private subnets (nodes and pods)"
  type        = list(string)
}

variable "public_subnets" {
  description = "CIDR blocks for the public subnets (NAT gateways, internet-facing ALBs)"
  type        = list(string)
}

variable "intra_subnets" {
  description = "CIDR blocks for the intra subnets (EKS control-plane ENIs, no internet route)"
  type        = list(string)
}

variable "one_nat_gateway_per_az" {
  description = "One NAT gateway per AZ — avoids cross-AZ data charges and removes the single-NAT SPOF"
  type        = bool
  default     = true
}

variable "enable_flow_log" {
  description = "Send VPC Flow Logs to a CloudWatch log group"
  type        = bool
  default     = true
}

variable "flow_log_max_aggregation_interval" {
  description = "Seconds a flow is aggregated before being published (60 or 600)"
  type        = number
  default     = 60
}

variable "enable_s3_endpoint" {
  description = "S3 gateway endpoint — free, and keeps ECR image layer traffic off the NAT gateway"
  type        = bool
  default     = true
}

variable "interface_endpoints" {
  description = "AWS services to reach over interface endpoints, e.g. [\"ecr.api\", \"ecr.dkr\", \"sts\"]. Each costs ~$7.30/month per AZ"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to all resources created by this module"
  type        = map(string)
  default     = {}
}
