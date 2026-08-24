output "node_iam_role_name" {
  description = "IAM role name assigned to Karpenter-managed nodes"
  value       = module.karpenter.node_iam_role_name
}

output "node_iam_role_arn" {
  description = "IAM role ARN assigned to Karpenter-managed nodes"
  value       = module.karpenter.node_iam_role_arn
}

output "queue_name" {
  description = "SQS interruption queue consumed by the Karpenter controller"
  value       = module.karpenter.queue_name
}

output "controller_iam_role_arn" {
  description = "IAM role ARN used by the Karpenter controller via Pod Identity"
  value       = module.karpenter.iam_role_arn
}
