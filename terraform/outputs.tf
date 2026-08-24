output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks_control_plane.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = module.eks_control_plane.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the cluster"
  value       = module.eks_control_plane.cluster_version
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate"
  value       = module.eks_control_plane.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL — use to create additional IRSA roles"
  value       = module.eks_control_plane.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN"
  value       = module.eks_control_plane.oidc_provider_arn
}

output "node_security_group_id" {
  description = "Shared node security group ID"
  value       = module.eks_control_plane.node_security_group_id
}

output "system_node_group_iam_role_arn" {
  description = "IAM role ARN used by the system node group"
  value       = module.eks_system_node_group.iam_role_arn
}

output "addon_versions" {
  description = "Installed EKS add-on versions"
  value       = merge(module.eks_addons_bootstrap.addon_versions, module.eks_addons.addon_versions)
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.network.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (nodes + pods)"
  value       = module.network.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs (NAT GW + internet-facing ALBs)"
  value       = module.network.public_subnets
}

output "karpenter_node_iam_role_name" {
  description = "IAM role name assigned to Karpenter-managed nodes"
  value       = module.karpenter.node_iam_role_name
}

output "karpenter_node_iam_role_arn" {
  description = "IAM role ARN assigned to Karpenter-managed nodes"
  value       = module.karpenter.node_iam_role_arn
}

output "vpc_endpoint_ids" {
  description = "VPC endpoint IDs keyed by service"
  value       = module.network.vpc_endpoint_ids
}

output "api_gateway_endpoint" {
  description = "Invoke URL of the HTTP API, null when API Gateway is disabled"
  value       = try(module.api_gateway[0].api_endpoint, null)
}

output "api_gateway_target_group_arn" {
  description = "Target group to bind workloads to, null when API Gateway is disabled"
  value       = try(module.api_gateway[0].target_group_arn, null)
}

output "api_gateway_target_group_binding" {
  description = "TargetGroupBinding manifest — edit namespace/service and apply it"
  value       = try(module.api_gateway[0].target_group_binding_manifest, null)
}

output "configure_kubectl" {
  description = "Run this command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks_control_plane.cluster_name}"
}
