variable "name" {
  description = "Name prefix for the API, VPC link, NLB, and target group"
  type        = string
}

variable "description" {
  description = "Description shown on the HTTP API"
  type        = string
  default     = "HTTP API fronting EKS workloads over a VPC Link"
}

variable "vpc_id" {
  description = "VPC holding the cluster"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR — the NLB is allowed to reach pod IPs in this range"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the NLB and the VPC Link ENIs"
  type        = list(string)
}

variable "listener_port" {
  description = "Port the NLB listens on for VPC Link traffic"
  type        = number
  default     = 80
}

variable "target_port" {
  description = "Container port the target group forwards to"
  type        = number
  default     = 8080
}

variable "health_check_protocol" {
  description = "Target group health check protocol — TCP, HTTP, or HTTPS"
  type        = string
  default     = "HTTP"
}

variable "health_check_path" {
  description = "Health check path, used for HTTP/HTTPS health checks"
  type        = string
  default     = "/healthz"
}

variable "deregistration_delay" {
  description = "Seconds to wait before removing a deregistered pod IP"
  type        = number
  default     = 30
}

variable "route_key" {
  description = "Route matched by the API. \"ANY /{proxy+}\" forwards everything to the cluster"
  type        = string
  default     = "ANY /{proxy+}"
}

variable "integration_timeout_milliseconds" {
  description = "Integration timeout. HTTP APIs cap this at 30000 ms"
  type        = number
  default     = 30000
}

variable "throttling_rate_limit" {
  description = "Steady-state request rate limit per second across the stage"
  type        = number
  default     = 1000
}

variable "throttling_burst_limit" {
  description = "Burst capacity for the stage"
  type        = number
  default     = 2000
}

variable "cors_configuration" {
  description = "Optional CORS configuration for browser clients"
  type = object({
    allow_origins = list(string)
    allow_methods = optional(list(string), ["GET", "POST", "OPTIONS"])
    allow_headers = optional(list(string), ["content-type", "authorization"])
    max_age       = optional(number, 300)
  })
  default = null
}

variable "jwt_authorizer" {
  description = "Optional JWT authorizer — rejects unauthenticated requests at the edge, before the VPC"
  type = object({
    issuer   = string
    audience = list(string)
  })
  default = null
}

variable "log_retention_in_days" {
  description = "Retention for the access log group"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to all resources created by this module"
  type        = map(string)
  default     = {}
}
