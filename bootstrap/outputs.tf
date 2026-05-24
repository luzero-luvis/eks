output "state_bucket_name" {
  description = "S3 bucket name — use as 'bucket' in your backend config"
  value       = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.state.arn
}

output "kms_key_arn" {
  description = "KMS key ARN used to encrypt state"
  value       = aws_kms_key.state.arn
}

output "backend_config" {
  description = "Paste this into terraform/backend.tf"
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket       = "${aws_s3_bucket.state.id}"
        key          = "prod/eks/terraform.tfstate"
        region       = "${var.aws_region}"
        encrypt      = true
        kms_key_id   = "${aws_kms_key.state.arn}"
        use_lockfile = true
      }
    }
  EOT
}
