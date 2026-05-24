# KMS key for EKS envelope encryption of Kubernetes Secrets
resource "aws_kms_key" "eks" {
  description             = "EKS cluster secrets encryption — ${local.name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${local.name}-eks"
  }
}

resource "aws_kms_alias" "eks" {
  name          = "alias/eks/${local.name}"
  target_key_id = aws_kms_key.eks.key_id
}

# KMS key for EBS volume encryption on all nodes
resource "aws_kms_key" "ebs" {
  description             = "EBS volume encryption — ${local.name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  # Allow the EBS service and Auto Scaling to use this key for node group volumes
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow service-linked role use for EBS"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow attachment of persistent resources"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
        }
        Action   = "kms:CreateGrant"
        Resource = "*"
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = "true"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${local.name}-ebs"
  }
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/eks/${local.name}-ebs"
  target_key_id = aws_kms_key.ebs.key_id
}
