output "arn" {
  description = "ARN of the IAM role — annotate the service account with this"
  value       = module.irsa.arn
}

output "name" {
  description = "Name of the IAM role"
  value       = module.irsa.name
}
