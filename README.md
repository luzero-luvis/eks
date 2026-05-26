# EKS Production Cluster

> Production-grade Amazon EKS cluster provisioned with Terraform, following the [AWS EKS Best Practices Guide](https://docs.aws.amazon.com/eks/latest/best-practices/introduction.html).

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Components](#components)
4. [Directory Structure](#directory-structure)
5. [Prerequisites](#prerequisites)
6. [Deployment Guide](#deployment-guide)
7. [Best Practices](#best-practices)
   - [Security](#security)
   - [Networking](#networking)
   - [Reliability](#reliability)
   - [Karpenter — Node Autoscaling](#karpenter--node-autoscaling)
   - [Storage](#storage)
   - [Cost Optimisation](#cost-optimisation)
   - [Cluster Upgrades](#cluster-upgrades)
8. [Day-2 Operations](#day-2-operations)
9. [Adding Storage Later](#adding-storage-later)
10. [Estimated Cost](#estimated-cost)
11. [References](#references)

---

## Overview

This repository provisions a production-ready Amazon EKS cluster using Terraform. Every design decision follows the official AWS EKS Best Practices Guide. The cluster is built for:

- **Security** — encrypted secrets, private nodes, IRSA, IMDSv2, network policies
- **Reliability** — multi-AZ, dedicated system nodes, CoreDNS HA, auto node repair
- **Scalability** — Karpenter dynamically provisions nodes in seconds based on pod demand
- **Cost efficiency** — Spot instances for application workloads, gp3 storage, no unnecessary resources

The repository is split into two independent Terraform roots:

| Directory | Purpose |
|---|---|
| `bootstrap/` | Creates the S3 state bucket. Run once before anything else. |
| `terraform/` | Provisions the full EKS cluster. |

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                            AWS Account                               │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │                      VPC  10.0.0.0/16                         │  │
│  │                                                                │  │
│  │         AZ-1                 AZ-2                 AZ-3         │  │
│  │  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │  │
│  │  │    Public    │    │    Public    │    │    Public    │      │  │
│  │  │ 10.0.48.0/24 │    │ 10.0.49.0/24 │    │ 10.0.50.0/24 │      │  │
│  │  │  NAT Gateway │    │  NAT Gateway │    │  NAT Gateway │      │  │
│  │  │  Internet LB │    │  Internet LB │    │  Internet LB │      │  │
│  │  └──────────────┘    └──────────────┘    └──────────────┘      │  │
│  │         │                   │                   │              │  │
│  │  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │  │
│  │  │   Private    │    │   Private    │    │   Private    │      │  │
│  │  │  10.0.0.0/20 │    │ 10.0.16.0/20 │    │ 10.0.32.0/20 │      │  │
│  │  │ Worker nodes │    │ Worker nodes │    │ Worker nodes │      │  │
│  │  │  Pod IPs     │    │  Pod IPs     │    │  Pod IPs     │      │  │
│  │  └──────────────┘    └──────────────┘    └──────────────┘      │  │
│  │  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │  │
│  │  │    Intra     │    │    Intra     │    │    Intra     │      │  │
│  │  │ 10.0.52.0/28 │    │ 10.0.53.0/28 │    │ 10.0.54.0/28 │      │  │
│  │  │  Ctrl ENIs   │    │  Ctrl ENIs   │    │  Ctrl ENIs   │      │  │
│  │  └──────────────┘    └──────────────┘    └──────────────┘      │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │          EKS Control Plane  (AWS managed across 3 AZs)        │  │
│  │         API Server  │  etcd  │  Controller Manager            │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌─────────────────────────────┐  ┌──────────────────────────────┐  │
│  │     System Node Group       │  │     Karpenter Node Pool      │  │
│  │  2–4 × m5.large  ON_DEMAND  │  │  c/m/r gen3+  Spot→On-Demand │  │
│  │  Karpenter  CoreDNS         │  │  Application workloads       │  │
│  │  ALB Controller  EBS CSI    │  │  0 → unlimited (capped)      │  │
│  └─────────────────────────────┘  └──────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
```

### Traffic Flow

```
Internet
   │
   ▼
ALB / NLB  (public subnet — provisioned by AWS Load Balancer Controller)
   │  HTTPS / TCP
   ▼
Pod  (private subnet — no public IP, no direct inbound access)
   │  internal VPC IP
   ▼
Other Pods / Services  (all traffic stays on private IPs inside the VPC)
```

### Node Communication

All node-to-node and pod-to-pod traffic uses **private VPC IPs only**. Nodes have no public IP addresses. Outbound internet access (image pulls, AWS API calls) routes through NAT Gateways. Nothing outside the VPC can reach nodes or pods directly.

---

## Components

| Component | Version | Role |
|---|---|---|
| **EKS Control Plane** | Kubernetes 1.35 | Managed API server, etcd, scheduler — AWS operated |
| **VPC** | — | 3-AZ network with public / private / intra subnet tiers |
| **System Node Group** | AL2023, m5.large | Fixed ON_DEMAND nodes for cluster infrastructure |
| **Karpenter** | 1.12.1 | Dynamically provisions application nodes on demand |
| **AWS Load Balancer Controller** | 3.3.0 | Creates ALB/NLB resources from Kubernetes Ingress/Service |
| **EBS CSI Driver** | latest | Block storage persistent volumes for stateful workloads |
| **VPC CNI** | latest | Native AWS pod networking with prefix delegation |
| **CoreDNS** | latest | Cluster DNS with lameduck shutdown and proportional autoscaling |
| **Node Monitoring Agent** | latest | Detects fatal node conditions and triggers auto-repair |
| **KMS (×2)** | — | Customer-managed encryption for Secrets and EBS volumes |
| **Network Policies** | — | Default-deny with explicit allow rules per namespace |

---

## Directory Structure

```
eks/
│
├── bootstrap/                    # Step 1 — run once to create state bucket
│   ├── main.tf                   # S3 bucket + KMS key
│   ├── variables.tf
│   ├── outputs.tf                # Prints backend.tf snippet after apply
│   ├── providers.tf
│   ├── versions.tf
│   └── terraform.tfvars.example  # Copy to terraform.tfvars and edit
│
└── terraform/                    # Step 2 — main cluster
    ├── backend.tf                # Created manually from bootstrap output (gitignored)
    ├── versions.tf               # Pinned provider versions
    ├── providers.tf              # AWS, Kubernetes, Helm, kubectl providers
    ├── locals.tf                 # Computed values: AZs, CIDRs, common tags
    ├── variables.tf              # All input variables with documented defaults
    ├── data.tf                   # AWS data sources (AZs, caller identity, partition)
    ├── kms.tf                    # KMS key for Secrets encryption + KMS key for EBS
    ├── vpc.tf                    # VPC, subnets, NAT GW, flow logs, subnet tags
    ├── eks.tf                    # EKS cluster, managed add-ons, system node group
    ├── irsa.tf                   # IRSA roles for EBS CSI driver and ALB Controller
    ├── karpenter.tf              # Karpenter IAM, Helm release, NodeClass, NodePool
    ├── alb_controller.tf         # AWS Load Balancer Controller Helm release
    ├── storage.tf                # gp3 default StorageClass, demote gp2
    ├── network_policies.tf       # Default-deny NetworkPolicy + CoreDNS autoscaler
    ├── outputs.tf                # Cluster endpoint, kubeconfig command, subnet IDs
    └── terraform.tfvars.example  # Example values — copy to terraform.tfvars
```

---

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Terraform | >= 1.10 | Infrastructure provisioning |
| AWS CLI | >= 2.0 | AWS authentication and API access |
| kubectl | >= 1.29 | Kubernetes cluster management |
| helm | >= 3.0 | Kubernetes package management |

**AWS permissions required:**

The IAM user or role running Terraform needs permissions to create EKS clusters, VPCs, IAM roles, KMS keys, S3 buckets, EC2 instances, and associated resources. In most organisations this is a dedicated `terraform-deployer` role.

---

## Deployment Guide

### Step 1 — Bootstrap the state bucket

The state bucket must exist before the main cluster can be deployed. This step is run once per AWS account.

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region  = "us-east-1"
project     = "luvis"
bucket_name = "luvis-terraform-state-eks-2026"  # must be globally unique
```

```bash
terraform init
terraform apply
```

After apply, copy the printed backend config:

```bash
terraform output backend_config
```

---

### Step 2 — Configure the remote backend

Create `terraform/backend.tf` using the output from Step 1:

```hcl
terraform {
  backend "s3" {
    bucket       = "luvis-terraform-state-eks-2026"
    key          = "prod/eks/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    kms_key_id   = "arn:aws:kms:us-east-1:xxxxxxxxxxxx:key/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    use_lockfile = true
  }
}
```

> `backend.tf` is gitignored — it contains account-specific values that differ per environment.

---

### Step 3 — Configure cluster variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
aws_region   = "us-east-1"
cluster_name = "prod-eks"
project      = "luvis"
environment  = "prod"
owner        = "platform"

cluster_version = "1.35"
vpc_cidr        = "10.0.0.0/16"

# Restrict to your VPN or office IP range — never leave as 0.0.0.0/0 in prod
cluster_endpoint_public_access_cidrs = ["203.0.113.0/24"]

system_node_instance_types = ["m5.large", "m5a.large", "m6i.large"]
system_node_min_size       = 2
system_node_max_size       = 4
system_node_desired_size   = 2

karpenter_version      = "1.12.1"
alb_controller_version = "3.3.0"
```

---

### Step 4 — Deploy the cluster

```bash
terraform init
terraform plan   # review what will be created
terraform apply  # takes approximately 20–25 minutes
```

The EKS control plane takes 10–15 minutes. This is an AWS-side operation — nothing can speed it up.

---

### Step 5 — Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name prod-eks
kubectl get nodes
```

Expected output — 2 system nodes in `Ready` state:

```
NAME                          STATUS   ROLES    AGE   VERSION
ip-10-0-1-x.ec2.internal      Ready    <none>   2m    v1.35.x
ip-10-0-17-x.ec2.internal     Ready    <none>   2m    v1.35.x
```

---

### Destroy

```bash
# Destroy the cluster first
cd terraform
terraform destroy

# Then destroy the state bucket if no longer needed
cd ../bootstrap
terraform destroy
```

> The KMS key has a 7-day deletion window enforced by AWS. It will not be fully deleted for 7 days after destroy.

---

## Best Practices

### Security

#### 1. Encryption at Rest — Kubernetes Secrets

All Kubernetes Secrets are envelope-encrypted using a customer-managed KMS key. Without this, Secrets are stored as base64 in etcd — readable by anyone with etcd access.

```hcl
# eks.tf
encryption_config = {
  provider_key_arn = aws_kms_key.eks.arn
  resources        = ["secrets"]
}
```

#### 2. Encryption at Rest — EBS Volumes

All node root volumes and persistent volumes created from the default StorageClass are encrypted using a dedicated customer-managed KMS key with automatic annual rotation.

```hcl
# kms.tf
resource "aws_kms_key" "ebs" {
  enable_key_rotation = true
}
```

#### 3. IMDSv2 — Prevent Credential Theft

IMDSv2 requires an HTTP `PUT` request with a session token before the metadata endpoint responds. This blocks Server-Side Request Forgery (SSRF) attacks where a compromised application fetches `http://169.254.169.254/latest/meta-data/iam/security-credentials/` to steal node IAM credentials.

```hcl
# Enforced on system nodes (eks.tf) and Karpenter nodes (karpenter.tf)
metadata_options = {
  http_tokens                 = "required"
  http_put_response_hop_limit = 1   # prevents containers from reaching IMDS via hop
}
```

#### 4. IRSA — IAM Roles for Service Accounts

Every component that needs AWS access (EBS CSI driver, ALB Controller) gets its own dedicated IAM role with least-privilege policies. The role is bound to the component's Kubernetes ServiceAccount via OIDC federation. No long-lived credentials are stored anywhere — pods receive short-lived STS tokens automatically.

```hcl
# irsa.tf
module "ebs_csi_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  name                  = "${local.name}-ebs-csi"
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}
```

#### 5. EKS Access Entries — No aws-auth ConfigMap

Cluster access is managed through EKS Access Entries — IAM principals are mapped to cluster permissions via the EKS API. This replaces the `aws-auth` ConfigMap which is error-prone, must be edited carefully with `kubectl`, and can lock you out of the cluster if misconfigured.

```hcl
enable_cluster_creator_admin_permissions = true
```

#### 6. Control Plane Audit Logging

All five control plane log types are enabled and sent to CloudWatch Logs. These are mandatory for security auditing, incident response, and compliance.

| Log Type | What It Records |
|---|---|
| `api` | Every request to the Kubernetes API server |
| `audit` | Who performed what action and when — required for compliance |
| `authenticator` | All IAM authentication attempts against the cluster |
| `controllerManager` | Reconciliation loops, garbage collection, replica management |
| `scheduler` | Pod placement decisions and scheduling failures |

#### 7. Network Policies — Default Deny

All pod traffic is denied by default in `kube-system`. Explicit allow rules are added only for what is required. Apply this pattern to every application namespace.

```yaml
# Deny everything
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: kube-system
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
```

VPC CNI network policy enforcement is activated via `ENABLE_NETWORK_POLICY=true`, which runs an eBPF-based policy engine directly in the Linux kernel on every node — no additional CNI plugin required.

#### 8. Private Worker Nodes

All worker nodes are placed in private subnets and have no public IP addresses. The only inbound path into the cluster is through an ALB or NLB provisioned by the Load Balancer Controller. Nodes reach the internet for outbound traffic (image pulls, AWS API calls) only through NAT Gateways.

#### 9. AL2023 Node Operating System

Amazon Linux 2023 provides:

- **SELinux** enforcing mode by default — mandatory access control at the OS level
- **Minimal footprint** — fewer installed packages means a smaller attack surface
- **rpm-ostree** immutable updates — the OS is updated atomically, not package by package, eliminating configuration drift between nodes
- Regular AWS security patches and CVE fixes

#### 10. AMI Version Pinning

```yaml
amiSelectorTerms:
  - alias: al2023@v20260501   # pinned — never @latest in production
```

Using `@latest` risks an untested AMI rolling out to production nodes the moment AWS publishes it. The correct workflow is: validate new AMI in dev → update alias in prod → nodes rotate via `expireAfter`.

---

### Networking

#### 1. Three-Tier Subnet Design

The VPC uses three subnet tiers, each with a distinct purpose and security posture:

| Tier | CIDR | Purpose | Internet Route |
|---|---|---|---|
| **Public** `/24` | `10.0.48–50.0/24` | NAT Gateways and internet-facing ALBs | Yes — via IGW |
| **Private** `/20` | `10.0.0–32.0/20` | Worker nodes and pod IPs (~4,000 IPs per AZ) | Outbound only — via NAT GW |
| **Intra** `/28` | `10.0.52–54.0/28` | EKS control plane ENIs | None |

The intra subnets have no route table entry for the internet. The control plane ENIs live here — they reach the API server entirely within the VPC.

#### 2. One NAT Gateway Per Availability Zone

```hcl
one_nat_gateway_per_az = true
```

A single NAT Gateway means that if its AZ goes down, all nodes in other AZs lose internet connectivity. With one per AZ, each AZ is completely self-sufficient. At scale, a single NAT GW also creates a cross-AZ traffic charge of `$0.01/GB` for every node in AZ-2 and AZ-3 routing through AZ-1. One per AZ eliminates this charge entirely.

#### 3. VPC CNI Prefix Delegation

Without prefix delegation, the maximum number of pod IPs on an `m5.large` is:

```
3 ENIs × 10 secondary IPs = 29 pod IPs
```

With prefix delegation enabled (`ENABLE_PREFIX_DELEGATION=true`), each ENI receives a `/28` prefix:

```
3 ENIs × 10 prefixes × 16 IPs = 480 pod IPs
```

This prevents IP address exhaustion in dense clusters and is the AWS-recommended configuration for all production EKS clusters.

#### 4. Subnet Tagging for Auto-Discovery

The ALB Controller and Karpenter discover their target subnets by tag — no hardcoded subnet IDs anywhere.

```hcl
public_subnet_tags = {
  "kubernetes.io/role/elb"  = 1   # ALB controller places internet-facing ALBs here
  "karpenter.sh/discovery"  = local.name
}
private_subnet_tags = {
  "kubernetes.io/role/internal-elb" = 1   # ALB controller places internal ALBs here
  "karpenter.sh/discovery"          = local.name
}
```

#### 5. VPC Flow Logs

All VPC traffic metadata is captured to CloudWatch Logs. Flow logs record source and destination IP, port, protocol, and accept/drop status. Used for security analysis, detecting lateral movement, and debugging connectivity issues.

---

### Reliability

#### 1. Multi-AZ Control Plane

AWS automatically runs the EKS API server and etcd across all three Availability Zones. A full AZ failure does not affect the control plane. This is managed entirely by AWS — there is nothing to configure.

#### 2. Multi-AZ Worker Nodes

The system node group is configured across all three private subnets. Karpenter's NodePool restricts provisioning to the three known AZs and spreads nodes using topology spread constraints. If one AZ fails, workloads reschedule onto nodes in the remaining two AZs.

#### 3. Dedicated System Nodes — Taint-Based Isolation

The system node group is tainted with `CriticalAddonsOnly=true:NoSchedule`. This prevents application pods from landing on system nodes — application pods must explicitly tolerate the taint to schedule there (none should).

This ensures:
- Karpenter is never resource-starved by application workloads
- CoreDNS always has capacity to serve DNS queries
- System nodes are `ON_DEMAND` — they are never reclaimed by AWS as Spot instances

#### 4. CoreDNS — Lameduck Duration

```
health {
  lameduck 5s
}
```

When a CoreDNS pod begins shutting down — triggered by Karpenter draining a node — it waits 5 seconds before stopping its DNS listener. During this window, pods that have the terminating CoreDNS pod cached in their resolver continue to receive responses. This prevents DNS query failures during rapid node turnover.

#### 5. CoreDNS — Cluster-Proportional Autoscaling

CoreDNS replicas scale automatically with the size of the cluster:

```yaml
linear: |
  {
    "coresPerReplica": 256,
    "nodesPerReplica": 8,
    "min": 2,
    "preventSinglePointOfFailure": true
  }
```

Without autoscaling, a 100-node cluster still has 2 CoreDNS pods — DNS becomes a bottleneck. With proportional autoscaling, CoreDNS grows with the cluster and is always spread across multiple nodes for high availability.

#### 6. Node Monitoring Agent

The Node Monitoring Agent runs as a DaemonSet on every node. It detects fatal conditions such as kernel panics, kubelet failures, OOM events, and disk pressure. These are surfaced as Kubernetes Node conditions. Karpenter reads these conditions and automatically provisions a replacement node without manual intervention.

#### 7. EBS Volume AZ Binding

```hcl
volume_binding_mode = "WaitForFirstConsumer"
```

EBS volumes are AZ-specific — a volume in `us-east-1a` cannot be attached to a node in `us-east-1b`. `WaitForFirstConsumer` delays volume creation until a pod is scheduled on a node. The volume is then created in the same AZ as the node. Without this setting, a volume might be created in the wrong AZ and the pod will stay in `Pending` indefinitely.

#### 8. Pod Disruption Budgets

Karpenter itself has a PDB ensuring at least one replica is always available during node consolidation or rolling updates. Apply the same pattern to all stateful application workloads:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-app-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: my-app
```

---

### Karpenter — Node Autoscaling

#### How Karpenter Works

1. A pod is created but cannot be scheduled — no node has sufficient resources
2. Karpenter reads the pod's resource requests, node selectors, tolerations, topology spread constraints, and affinity rules
3. Karpenter selects the most cost-effective EC2 instance type that satisfies all constraints
4. Karpenter launches the instance via EC2 Fleet and registers it directly with the cluster
5. The pod schedules onto the new node — typically within 60 seconds
6. When a node is empty or its pods can be packed onto fewer nodes, Karpenter drains and terminates it

This is fundamentally faster and more flexible than the Cluster Autoscaler, which works indirectly through Auto Scaling Groups and requires pre-defined node group configurations.

#### EC2NodeClass — Node Configuration

The `EC2NodeClass` defines the AWS-level properties applied to every node Karpenter provisions:

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiSelectorTerms:
    - alias: al2023@v20260501     # pinned AMI — never @latest in production
  role: <karpenter-node-iam-role>
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: prod-eks   # auto-discovers private subnets by tag
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: prod-eks   # auto-discovers node security group by tag
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 50Gi
        volumeType: gp3
        encrypted: true
  instanceMetadataOptions:
    httpTokens: required             # IMDSv2 enforced on all Karpenter nodes
    httpPutResponseHopLimit: 1
```

#### NodePool — Scheduling Constraints and Limits

The `NodePool` defines which types of instances Karpenter may provision and the hard limits on total cluster size:

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]      # Spot preferred, On-Demand fallback
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m", "r"]            # compute / general / memory families
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["2"]                      # generation 3 and newer only
      expireAfter: 720h                      # force node replacement every 30 days
  limits:
    cpu: 1000
    memory: 2000Gi
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 5m
    budgets:
      - nodes: "10%"                         # max 10% of nodes disrupted simultaneously
```

#### Why Broad Instance Selection Matters for Spot

Each EC2 instance type in each Availability Zone is a separate Spot capacity pool. When AWS reclaims Spot capacity, it reclaims from a specific pool. By allowing many instance types across three AZs, Karpenter spreads nodes across many pools. The probability that all pools are reclaimed simultaneously is extremely low.

Restricting to only 2–3 instance types means all Spot nodes could be in the same pool — a single reclamation event could take down all your application nodes at once.

#### Spot Interruption Handling

```hcl
settings = {
  interruptionQueue = module.karpenter.queue_name
}
```

AWS sends a 2-minute warning before reclaiming a Spot instance. Karpenter receives this notification via an SQS queue, immediately taints the node `NoSchedule`, drains all pods, and launches a replacement node — all before the instance is terminated. Pods are moved gracefully rather than killed abruptly.

#### Node Expiry — Automatic AMI Rotation

```yaml
expireAfter: 720h
```

Every Karpenter-managed node is replaced after 30 days regardless of utilisation. This ensures all nodes regularly run a recently patched AMI without requiring any manual intervention. Node replacement is gradual — Karpenter drains one node at a time respecting Pod Disruption Budgets.

**AMI update workflow:**

```
1. New AMI released by AWS
2. Test new AMI alias in dev cluster
3. Update alias in karpenter.tf: al2023@v20260601
4. terraform apply
5. Over the next 30 days, nodes expire and Karpenter recreates them with the new AMI
```

#### Consolidation — Bin Packing

When cluster demand decreases, Karpenter identifies nodes whose pods can be rescheduled onto fewer nodes. It drains those nodes and terminates them, reducing cost automatically. The `10%` budget prevents more than 10% of nodes from being disrupted at the same time.

#### Resource Limits — Cost Guard Rail

```yaml
limits:
  cpu: 1000
  memory: 2000Gi
```

Karpenter stops provisioning new nodes when these limits are reached. Without limits, a misconfigured deployment requesting thousands of replicas would provision hundreds of nodes and generate an enormous unexpected bill. Always pair resource limits with a CloudWatch billing alarm.

---

### Storage

#### Default StorageClass — gp3

All `PersistentVolumeClaims` that do not specify a StorageClass use gp3 by default. The legacy gp2 StorageClass is demoted (its `is-default-class` annotation is set to `false`).

| | gp2 | gp3 |
|---|---|---|
| Price | $0.10/GB/month | $0.08/GB/month |
| Baseline IOPS | 3 IOPS/GB (min 100) | 3,000 always |
| Baseline throughput | 128–250 MB/s | 125 MB/s |
| Independent scaling | No | Yes — IOPS and throughput separately |

All volumes are encrypted by default using the EBS KMS key.

#### Adding More Storage

| Workload Type | Recommended Solution | Characteristics |
|---|---|---|
| Multiple pods reading the same files | **Amazon EFS** | ReadWriteMany, NFS protocol, elastic capacity |
| High-performance database | **EBS io2** | Up to 64,000 IOPS, consistent low latency |
| Cold archive data | **EBS sc1** | $0.015/GB/month — lowest cost block storage |
| Large datasets, ML model weights | **Mountpoint for S3** | Mount S3 buckets as filesystem paths in pods |
| ML training, HPC, batch jobs | **FSx for Lustre** | Hundreds of GB/s parallel throughput |

---

### Cost Optimisation

#### Spot Instances for Application Workloads

Karpenter defaults to Spot instances with automatic On-Demand fallback. Spot instances are typically **60–90% cheaper** than On-Demand.

Spot instances are appropriate for:
- Stateless web services and APIs
- Background processing and batch jobs
- Any workload that can be safely restarted within 2 minutes

Spot instances are **not** appropriate for:
- Karpenter itself — runs on system ON_DEMAND nodes
- CoreDNS — runs on system ON_DEMAND nodes
- Databases and other stateful workloads that cannot tolerate interruption

#### One NAT Gateway Per AZ vs One Total

| Configuration | Monthly cost | Risk |
|---|---|---|
| 1 NAT Gateway total | ~$32 | Cross-AZ traffic charges; single point of failure |
| 1 per AZ (used here) | ~$97 | No cross-AZ charges; AZ-resilient |

At any significant egress volume, the cross-AZ data transfer cost (`$0.01/GB`) of routing all AZ-2 and AZ-3 traffic through a single NAT GW in AZ-1 exceeds the saving. One per AZ is the correct production configuration.

#### S3 Native State Locking

```hcl
use_lockfile = true
```

Terraform 1.10+ uses a `.tflock` file in S3 instead of a DynamoDB table for state locking. Eliminates the DynamoDB table entirely — one fewer resource to manage, and the associated cost.

#### Karpenter Consolidation

Karpenter's `WhenEmptyOrUnderutilized` consolidation policy automatically moves pods off underutilised nodes and terminates them. During low-traffic periods, the cluster shrinks automatically without any manual intervention.

#### Billing Alarm

Set a CloudWatch billing alarm before deploying — Karpenter can scale fast:

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "eks-monthly-spend" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --threshold 500 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions <your-sns-topic-arn>
```

---

### Cluster Upgrades

#### Kubernetes Version Support

Amazon EKS supports each Kubernetes minor version for 14 months (standard support) followed by 12 months of paid extended support. Always run a version in standard support to avoid the extended support surcharge.

| Version | Status | Ends Standard Support |
|---|---|---|
| 1.35 | Standard | March 2027 |
| 1.34 | Standard | December 2026 |
| 1.33 | Standard | July 2026 |
| 1.32 | Extended (extra cost) | March 2026 |

Check current versions:

```bash
aws eks describe-cluster-versions \
  --query 'clusterVersions[*].{Version:clusterVersion,Status:status,EndStandard:endOfStandardSupportDate}' \
  --output table
```

#### Upgrading the Kubernetes Version

> Never skip a minor version. Upgrade 1.33 → 1.34 → 1.35, not 1.33 → 1.35.

```bash
# 1. Update the version variable
# terraform.tfvars
cluster_version = "1.36"

# 2. Apply — EKS upgrades the control plane (~15 min, zero downtime)
terraform apply

# 3. Update the system node group AMI type if needed
# eks.tf: ami_type = "AL2023_x86_64_STANDARD"
# Then: terraform apply — nodes are drained and replaced rolling

# 4. Karpenter nodes rotate automatically over 30 days via expireAfter
# To force immediate rotation: kubectl delete node <name>
```

#### Upgrading Karpenter

```bash
# 1. Check for new releases
# https://github.com/aws/karpenter-provider-aws/releases

# 2. Update the version
# terraform.tfvars
karpenter_version = "1.13.0"

# 3. Apply — Helm performs a rolling upgrade
terraform apply
```

#### Rotating Node AMIs

```bash
# Find available AL2023 AMI aliases for your cluster version
aws ssm get-parameters-by-path \
  --path /aws/service/eks/optimized-ami/1.35/amazon-linux-2023/ \
  --query 'Parameters[*].Name' \
  --output table

# Update karpenter.tf
#   amiSelectorTerms:
#     - alias: al2023@v20260601

# Apply — new nodes use the new AMI, old nodes expire over 30 days
terraform apply
```

---

## Day-2 Operations

### Verify Cluster Health

```bash
# All nodes ready
kubectl get nodes -o wide

# System pods running
kubectl get pods -n kube-system

# Karpenter controller logs
kubectl logs -n karpenter \
  -l app.kubernetes.io/name=karpenter \
  --tail=100 --follow

# Recent Karpenter provisioning events
kubectl get events -A --field-selector reason=ProvisionedNodes
```

### Inspect Karpenter Scaling

```bash
# NodePools and their current usage vs limits
kubectl get nodepools -o wide

# All nodes Karpenter is managing
kubectl get nodeclaims

# Why a pod is not scheduling
kubectl describe pod <pending-pod-name> -n <namespace>

# Karpenter's view of pending pods
kubectl get pods -A --field-selector status.phase=Pending
```

### Check Add-on Versions

```bash
# Compare installed vs latest available
aws eks describe-addon-versions \
  --kubernetes-version 1.35 \
  --query 'addons[*].{Name:addonName,Latest:addonVersions[0].addonVersion}'
```

### Refresh kubeconfig

```bash
aws eks update-kubeconfig --region us-east-1 --name prod-eks
```

### Access Node via Session Manager

No SSH key or bastion host needed — nodes have SSM agent installed:

```bash
# Find the node's EC2 instance ID
kubectl get node <node-name> -o jsonpath='{.spec.providerID}' | cut -d'/' -f5

# Start a session
aws ssm start-session --target <instance-id>
```

---

## Adding Storage Later

All storage solutions are addable by writing a new `.tf` file and running `terraform apply`. No cluster rebuild required.

| Need | File to create | Resources |
|---|---|---|
| Shared files (ReadWriteMany) | `efs.tf` | `aws_efs_file_system`, mount targets, EFS CSI addon |
| High-IOPS database volumes | `storage.tf` (add to existing) | `kubernetes_storage_class_v1` with `io2` type |
| S3 buckets as pod filesystem | `s3_csi.tf` | Mountpoint for S3 CSI driver addon, IRSA role |
| ML / HPC parallel storage | `fsx.tf` | `aws_fsx_lustre_file_system`, FSx CSI addon |

---

## Estimated Cost

The following are minimum costs with no application workloads running.

| Resource | Quantity | $/month |
|---|---|---|
| EKS control plane | 1 cluster | ~$72 |
| m5.large system nodes | 2 × ON_DEMAND | ~$138 |
| NAT Gateway | 3 × (one per AZ) | ~$97 |
| EBS root volumes (50GB gp3) | 2 nodes | ~$8 |
| KMS keys | 2 keys | ~$2 |
| CloudWatch Logs (flow logs + control plane) | Variable | ~$10 |
| **Minimum total** | | **~$327/month** |

Application node costs are additional and proportional to traffic. Karpenter Spot instances reduce application node costs by 60–90% compared to On-Demand.

---

## References

| Resource | URL |
|---|---|
| AWS EKS Best Practices Guide | https://docs.aws.amazon.com/eks/latest/best-practices/introduction.html |
| Karpenter Documentation | https://karpenter.sh/docs/ |
| EKS Kubernetes Version Lifecycle | https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html |
| EKS Managed Add-ons | https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html |
| VPC CNI — Prefix Delegation | https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html |
| AWS Load Balancer Controller | https://kubernetes-sigs.github.io/aws-load-balancer-controller/ |
| Terraform AWS EKS Module | https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest |
| Terraform AWS VPC Module | https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest |
