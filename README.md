# EKS Production Cluster

Production-grade EKS cluster built with Terraform following [AWS EKS Best Practices](https://docs.aws.amazon.com/eks/latest/best-practices/introduction.html).

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    AWS Account                       │
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │                  VPC (10.0.0.0/16)           │   │
│  │                                              │   │
│  │   AZ-1            AZ-2            AZ-3       │   │
│  │ ┌────────┐      ┌────────┐      ┌────────┐  │   │
│  │ │Public  │      │Public  │      │Public  │  │   │
│  │ │subnet  │      │subnet  │      │subnet  │  │   │
│  │ │NAT GW  │      │NAT GW  │      │NAT GW  │  │   │
│  │ └────────┘      └────────┘      └────────┘  │   │
│  │ ┌────────┐      ┌────────┐      ┌────────┐  │   │
│  │ │Private │      │Private │      │Private │  │   │
│  │ │subnet  │      │subnet  │      │subnet  │  │   │
│  │ │(nodes) │      │(nodes) │      │(nodes) │  │   │
│  │ └────────┘      └────────┘      └────────┘  │   │
│  │ ┌────────┐      ┌────────┐      ┌────────┐  │   │
│  │ │ Intra  │      │ Intra  │      │ Intra  │  │   │
│  │ │subnet  │      │subnet  │      │subnet  │  │   │
│  │ │(ctrl)  │      │(ctrl)  │      │(ctrl)  │  │   │
│  │ └────────┘      └────────┘      └────────┘  │   │
│  └──────────────────────────────────────────────┘   │
│                                                     │
│  EKS Control Plane (AWS managed, 3 AZs)             │
│                                                     │
│  Worker Nodes:                                      │
│  ├── System MNG (2×m5.large, ON_DEMAND, fixed)      │
│  │     Karpenter + CoreDNS + ALB Controller         │
│  └── Karpenter nodes (dynamic, Spot+On-Demand)      │
│        Application workloads                        │
└─────────────────────────────────────────────────────┘
```

## What's included

| Component | Details |
|---|---|
| EKS Control Plane | v1.32, public+private endpoint, KMS encrypted secrets |
| VPC | 3 AZs, public/private/intra subnets, VPC flow logs |
| System Node Group | 2–4× m5.large, ON_DEMAND, AL2023, IMDSv2 |
| Karpenter | v1.0.6, Spot+On-Demand, 30-day node expiry |
| AWS Load Balancer Controller | ALB/NLB provisioning from Kubernetes resources |
| EBS CSI Driver | gp3 default StorageClass, KMS encrypted |
| VPC CNI | Prefix delegation, NetworkPolicy enabled |
| CoreDNS | Lameduck, readiness probe, cluster-proportional autoscaler |
| Node Monitoring Agent | Auto-repair fatal node conditions |
| KMS | Separate keys for EKS secrets and EBS volumes |
| Network Policies | Default-deny in kube-system |

## Directory structure

```
eks/
├── bootstrap/               # Run once — creates S3 state bucket
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── providers.tf
│   ├── versions.tf
│   └── terraform.tfvars.example
└── terraform/               # Main cluster
    ├── versions.tf
    ├── providers.tf
    ├── locals.tf
    ├── variables.tf
    ├── data.tf
    ├── kms.tf               # KMS keys for secrets + EBS
    ├── vpc.tf               # VPC, subnets, NAT GW, flow logs
    ├── eks.tf               # EKS cluster + managed add-ons + system node group
    ├── irsa.tf              # IAM Roles for Service Accounts
    ├── karpenter.tf         # Karpenter IAM, Helm, NodeClass, NodePool
    ├── alb_controller.tf    # AWS Load Balancer Controller
    ├── storage.tf           # gp3 StorageClass
    ├── network_policies.tf  # Default-deny + CoreDNS autoscaler
    ├── outputs.tf
    └── terraform.tfvars.example
```

## Prerequisites

- Terraform >= 1.10
- AWS CLI configured (`aws configure`)
- `kubectl` installed
- `helm` installed

## Deploy

### Step 1 — Bootstrap state bucket (one time only)

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set a globally unique bucket_name
terraform init
terraform apply

# Copy the backend config from the output
terraform output backend_config
```

### Step 2 — Deploy the cluster

```bash
cd ../terraform

# Create backend.tf with the output from step 1
cat > backend.tf << 'EOF'
terraform {
  backend "s3" {
    bucket       = "your-bucket-name"
    key          = "prod/eks/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    kms_key_id   = "arn:aws:kms:..."
    use_lockfile = true
  }
}
EOF

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform apply
```

### Step 3 — Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name prod-eks
kubectl get nodes
```

## Destroy

```bash
cd terraform
terraform destroy

cd ../bootstrap
terraform destroy  # only if you also want to remove the state bucket
```

## Adding storage later

| Need | Action |
|---|---|
| Shared files across pods | Add EFS CSI driver + `aws_efs_file_system` |
| High IOPS for databases | Add `io2` StorageClass to `storage.tf` |
| S3 as pod filesystem | Add Mountpoint for S3 CSI driver |
| ML / HPC workloads | Add FSx for Lustre |

## Estimated cost

| Resource | $/month |
|---|---|
| EKS control plane | ~$72 |
| 2× m5.large system nodes | ~$138 |
| 3× NAT Gateway | ~$97 |
| EBS + KMS + CloudWatch | ~$15 |
| **Minimum total** | **~$322** |

Application node costs are additional and scale with your traffic.
