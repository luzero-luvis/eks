output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.eks.cluster_arn
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the control plane"
  value       = module.eks.cluster_version
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate"
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL — use to create additional IRSA roles"
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN backing IRSA"
  value       = module.eks.oidc_provider_arn
}

output "cluster_security_group_id" {
  description = "Security group created by EKS for the control plane"
  value       = module.eks.cluster_security_group_id
}

output "cluster_primary_security_group_id" {
  description = "Cluster primary security group — must be attached to nodes created outside this module"
  value       = module.eks.cluster_primary_security_group_id
}

output "node_security_group_id" {
  description = "Shared node security group — attach to every node group"
  value       = module.eks.node_security_group_id
}

output "cluster_service_cidr" {
  description = "Service CIDR of the cluster — required by node bootstrap"
  value       = module.eks.cluster_service_cidr
}

output "cluster_ip_family" {
  description = "IP family of the cluster (ipv4 / ipv6)"
  value       = module.eks.cluster_ip_family
}
