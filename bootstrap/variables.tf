variable "aws_region" {
  description = "AWS region for the state bucket"
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project name used in tags and bucket prefix"
  type        = string
  default     = "luvis"
}

variable "bucket_name" {
  description = "S3 bucket name for Terraform state (must be globally unique)"
  type        = string
}

