# EKS Production Cluster

Production-grade EKS cluster built with Terraform following the [AWS EKS Best Practices Guide](https://docs.aws.amazon.com/eks/latest/best-practices/introduction.html).

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS Account                             │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    VPC (10.0.0.0/16)                      │  │
│  │                                                           │  │
│  │        AZ-1              AZ-2              AZ-3           │  │
│  │  ┌────────────┐    ┌────────────┐    ┌────────────┐       │  │
│  │  │   Public   │    │   Public   │    │   Public   │       │  │
│  │  │ 10.0.48/24 │    │ 10.0.49/24 │    │ 10.0.50/24 │       │  │
│  │  │  (NAT GW)  │    │  (NAT GW)  │    │  (NAT GW)  │       │  │
│  │  └────────────┘    └────────────┘    └────────────┘       │  │
│  │  ┌────────────┐    ┌────────────┐    ┌────────────┐       │  │
│  │  │  Private   │    │  Private   │    │  Private   │       │  │
│  │  │  10.0.0/20 │    │ 10.0.16/20 │    │ 10.0.32/20 │       │  │
│  │  │   nodes    │    │   nodes    │    │   nodes    │       │  │
│  │  │   pods     │    │   pods     │    │   pods     │       │  │
│  │  └────────────┘    └────────────┘    └────────────┘       │  │
│  │  ┌────────────┐    ┌────────────┐    ┌────────────┐       │  │
│  │  │   Intra    │    │   Intra    │    │   Intra    │       │  │
│  │  │ 10.0.52/28 │    │ 10.0.53/28 │    │ 10.0.54/28 │       │  │
│  │  │ (ctrl ENI) │    │ (ctrl ENI) │    │ (ctrl ENI) │       │  │
│  │  └────────────┘    └────────────┘    └────────────┘       │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │        EKS Control Plane  (AWS managed, 3 AZs)          │    │
│  │   API Server  |  etcd  |  Controller Manager            │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  Worker Nodes                                                   │
│  ├── System MNG  2–4× m5.large  ON_DEMAND  AL2023              │
│  │   └── Karpenter  CoreDNS  ALB Controller  EBS CSI           │
│  └── Karpenter  c/m/r gen3+  Spot→On-Demand  dynamic          │
│      └── Application workloads                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## What's Included

| Component | Version | Purpose |
|---|---|---|
| EKS Control Plane | 1.35 | Managed Kubernetes — AWS runs and patches it |
| VPC | — | 3-AZ network with public/private/intra tiers |
| System Node Group | AL2023 | Fixed ON_DEMAND nodes for cluster infrastructure |
| Karpenter | 1.12.1 | Dynamic application node provisioning |
| AWS Load Balancer Controller | 3.3.0 | Creates ALB/NLB from Kubernetes Ingress/Service |
| EBS CSI Driver | latest | Persistent block storage for stateful workloads |
| VPC CNI | latest | Native AWS pod networking with prefix delegation |
| CoreDNS | latest | Cluster DNS with autoscaling and lameduck |
| Node Monitoring Agent | latest | Detects and repairs unhealthy nodes |
| KMS (×2) | — | Encryption for Secrets and EBS volumes |
| Network Policies | — | Default-deny with explicit allow rules |

---

## Directory Structure

```
eks/
├── bootstrap/                  # Run once — creates S3 state bucket
│   ├── main.tf                 # S3 bucket + KMS key
│   ├── variables.tf
│   ├── outputs.tf              # Prints backend.tf config to copy
│   ├── providers.tf
│   ├── versions.tf
│   └── terraform.tfvars.example
└── terraform/                  # Main EKS cluster
    ├── versions.tf             # Provider version pins
    ├── providers.tf            # AWS, Kubernetes, Helm, kubectl
    ├── locals.tf               # Computed values (AZs, subnet CIDRs, tags)
    ├── variables.tf            # All input variables with defaults
    ├── data.tf                 # AWS data sources
    ├── kms.tf                  # KMS key for Secrets + KMS key for EBS
    ├── vpc.tf                  # VPC, subnets, NAT GW, flow logs
    ├── eks.tf                  # EKS cluster, add-ons, system node group
    ├── irsa.tf                 # IRSA roles for EBS CSI + ALB Controller
    ├── karpenter.tf            # Karpenter IAM, Helm, NodeClass, NodePool
    ├── alb_controller.tf       # ALB Controller Helm release
    ├── storage.tf              # gp3 default StorageClass
    ├── network_policies.tf     # Default-deny + CoreDNS autoscaler
    ├── outputs.tf
    └── terraform.tfvars.example
```

---

## Prerequisites

- Terraform >= 1.10
- AWS CLI configured (`aws configure`)
- `kubectl`
- `helm`

---

## Deploy

### Step 1 — Bootstrap state bucket (one time only)

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set a globally unique bucket_name
terraform init
terraform apply

# Copy the printed backend config
terraform output backend_config
```

### Step 2 — Deploy the cluster

```bash
cd ../terraform

# Paste the backend config from Step 1 into a new file
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
terraform apply   # takes ~20–25 minutes
```

### Step 3 — Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name prod-eks
kubectl get nodes
```

---

## Destroy

```bash
# Destroy the cluster first
cd terraform
terraform destroy

# Then destroy the state bucket if needed
cd ../bootstrap
terraform destroy
```

---

## Best Practices

### 1. Security

#### Identity and Access Management (IAM)

**IRSA — IAM Roles for Service Accounts**

Every add-on (EBS CSI, ALB Controller) gets its own dedicated IAM role bound to its Kubernetes service account via OIDC federation. Pods assume the role automatically — no long-lived credentials stored anywhere, no node-level IAM permissions shared across all pods.

```hcl
# irsa.tf — each component gets its own least-privilege role
module "ebs_csi_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  name                  = "${local.name}-ebs-csi"
  attach_ebs_csi_policy = true
  oidc_providers        = { main = { provider_arn = module.eks.oidc_provider_arn ... } }
}
```

**EKS Access Entries (no aws-auth ConfigMap)**

Cluster access is managed through EKS Access Entries (IAM principal → cluster permission mapping). This avoids manual edits to the `aws-auth` ConfigMap which is error-prone and can lock you out.

```hcl
enable_cluster_creator_admin_permissions = true
```

**Least Privilege**
- Each IRSA role only has the permissions its specific add-on needs
- No `*` actions or `*` resources in any policy
- Node IAM role only has permissions needed to join the cluster and pull images

---

#### Encryption

**KMS Envelope Encryption for Kubernetes Secrets**

All Kubernetes Secrets are encrypted at rest using a customer-managed KMS key. Without this, Secrets are base64-encoded in etcd — readable by anyone with etcd access.

```hcl
# eks.tf
encryption_config = {
  provider_key_arn = aws_kms_key.eks.arn
  resources        = ["secrets"]
}
```

**KMS Encryption for EBS Volumes**

All node root volumes and persistent volumes are encrypted with a separate customer-managed KMS key with automatic rotation enabled. A separate KMS policy allows the Auto Scaling service to use the key when launching new nodes.

```hcl
# kms.tf — separate key for EBS
resource "aws_kms_key" "ebs" {
  enable_key_rotation = true
  ...
}
```

**S3 State Bucket Encryption**

The Terraform state bucket is encrypted with its own KMS key. State files can contain sensitive values — treat them like secrets.

---

#### IMDSv2 — Instance Metadata Service v2

IMDSv2 requires a session token to access the metadata endpoint. This blocks SSRF (Server-Side Request Forgery) attacks where a compromised application fetches `http://169.254.169.254` to steal node IAM credentials.

```hcl
# eks.tf — on system nodes
metadata_options = {
  http_endpoint               = "enabled"
  http_tokens                 = "required"   # enforces IMDSv2
  http_put_response_hop_limit = 1            # blocks containers from reaching IMDS via hop
}
```

```yaml
# karpenter.tf — on all Karpenter nodes
instanceMetadataOptions:
  httpTokens: required
  httpPutResponseHopLimit: 1
```

---

#### Control Plane Logging

All 5 control plane log types are enabled and sent to CloudWatch. These logs are essential for security auditing, incident response, and debugging cluster-level issues.

| Log type | What it captures |
|---|---|
| `api` | All Kubernetes API requests |
| `audit` | Who did what and when — required for compliance |
| `authenticator` | IAM authentication attempts |
| `controllerManager` | Reconciliation loops, scheduling decisions |
| `scheduler` | Pod placement decisions |

```hcl
enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
```

---

#### Network Security

**Default-Deny NetworkPolicy**

All pod-to-pod traffic is denied by default in `kube-system`. Explicit allow rules are added only for what is needed (CoreDNS DNS queries). Apply this same pattern to every application namespace.

```yaml
# network_policies.tf
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: kube-system
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
```

**VPC CNI Network Policy Engine**

`ENABLE_NETWORK_POLICY=true` activates eBPF-based policy enforcement directly in the Linux kernel on each node. This is the AWS-native policy engine — no third-party CNI replacement needed.

**VPC Flow Logs**

All VPC traffic metadata (source/dest IP, port, accept/drop) is captured to CloudWatch. Used for security analysis, detecting lateral movement, and debugging connectivity issues.

**Security Groups**

The EKS module creates a cluster security group that allows only the required traffic between the control plane and nodes. An additional rule allows node-to-node traffic for pod communication.

---

#### Node Security

**AL2023 AMI**

Amazon Linux 2023 replaces AL2 with:
- SELinux enforcing mode by default
- Minimal package footprint (smaller attack surface)
- rpm-ostree immutable OS updates — no package drift between nodes
- Regular AWS security patches

**Pinned AMI version**

```yaml
# karpenter.tf — never use @latest in production
amiSelectorTerms:
  - alias: al2023@v20260501
```

Using `@latest` risks an untested AMI rolling out to production nodes automatically. Test the new AMI version in a dev cluster first, then update the alias in production.

---

### 2. Networking

#### 3-Tier Subnet Design

| Tier | Subnet | Purpose |
|---|---|---|
| Public `/24` | `10.0.48-50.0/24` | NAT Gateways, internet-facing ALBs only |
| Private `/20` | `10.0.0-32.0/20` | Worker nodes and pod IPs (~4000 IPs per AZ) |
| Intra `/28` | `10.0.52-54.0/28` | EKS control plane ENIs only — no internet route |

The intra subnets have no route to the internet at all. The control plane ENIs live here — they communicate with the API server internally without ever touching the public internet.

**Why private subnets for nodes?**

Nodes have no public IP addresses. Inbound traffic is impossible — only the load balancer accepts inbound connections. Nodes reach the internet through NAT Gateways for outbound traffic (pulling images, AWS API calls) but nothing can reach them directly.

---

#### One NAT Gateway Per AZ

```hcl
# vpc.tf
single_nat_gateway     = false
one_nat_gateway_per_az = true
```

With a single NAT GW, if that AZ fails all nodes lose internet access. With one per AZ, each AZ is self-sufficient. This also eliminates cross-AZ data transfer charges for node egress traffic.

---

#### VPC CNI Prefix Delegation

```hcl
ENABLE_PREFIX_DELEGATION = "true"
WARM_PREFIX_TARGET       = "1"
```

Without prefix delegation, each ENI secondary IP provides one pod IP. A `m5.large` has 3 ENIs × 10 IPs = 29 pod IPs maximum.

With prefix delegation, each ENI gets a `/28` prefix = 16 IPs. The same `m5.large` supports 3 ENIs × 10 prefixes × 16 = 480 pod IPs. This prevents IP exhaustion in large clusters.

---

#### Subnet Tagging for Auto-Discovery

```hcl
# vpc.tf — ALB controller discovers subnets by these tags
public_subnet_tags = {
  "kubernetes.io/role/elb"  = 1   # internet-facing ALBs
  "karpenter.sh/discovery"  = local.name
}
private_subnet_tags = {
  "kubernetes.io/role/internal-elb" = 1   # internal ALBs
  "karpenter.sh/discovery"          = local.name
}
```

Without these tags, the ALB controller cannot find which subnets to place load balancers in. Karpenter uses the same tags to find which subnets to launch nodes into.

---

### 3. Reliability

#### Multi-AZ Everything

- EKS control plane: AWS spreads it across 3 AZs automatically
- System node group: spans all 3 private subnets
- Karpenter NodePool: restricted to the 3 known AZs
- CoreDNS autoscaler: `preventSinglePointOfFailure: true`

If an entire AZ goes down, the cluster continues operating on the remaining 2 AZs.

---

#### System Node Group — Dedicated Infrastructure Nodes

The system node group runs cluster infrastructure (Karpenter, CoreDNS, ALB controller) on dedicated ON_DEMAND nodes that are never managed by Karpenter.

```hcl
taints = {
  CriticalAddonsOnly = {
    key    = "CriticalAddonsOnly"
    value  = "true"
    effect = "NO_SCHEDULE"
  }
}
```

The taint prevents application pods from landing on system nodes. Karpenter and CoreDNS have tolerations for this taint. This means:
- Application pods can never starve cluster infrastructure of resources
- Karpenter is always running even when the cluster has zero application nodes
- System nodes are ON_DEMAND — they are never interrupted

---

#### CoreDNS Lameduck Duration

```
health {
  lameduck 5s
}
```

When a CoreDNS pod begins shutting down, it waits 5 seconds before stopping. During this window it continues serving DNS responses. This prevents DNS failures when Karpenter rapidly terminates nodes — pods that had the terminating CoreDNS pod in their resolver cache can still get responses for 5 seconds while switching to a healthy replica.

---

#### CoreDNS Cluster-Proportional Autoscaler

```yaml
# network_policies.tf
linear: |
  {
    "coresPerReplica": 256,
    "nodesPerReplica": 8,
    "min": 2,
    "preventSinglePointOfFailure": true
  }
```

CoreDNS scales automatically as the cluster grows — 1 replica per 8 nodes, minimum 2 replicas always. Without this, a large cluster has 2 CoreDNS pods serving thousands of nodes and DNS becomes a bottleneck.

---

#### Node Monitoring Agent

```hcl
eks-node-monitoring-agent = { most_recent = true }
```

The Node Monitoring Agent runs as a DaemonSet on every node. It detects fatal conditions (kernel panics, kubelet failures, disk pressure) and reports them as Kubernetes Node conditions. Karpenter reads these conditions and automatically replaces affected nodes without manual intervention.

---

#### Pod Disruption Budgets

Karpenter itself has a PDB ensuring at least 1 replica is always available during node consolidation or rolling updates:

```yaml
podDisruptionBudget:
  minAvailable: 1
```

Apply PDBs to your own applications too:
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-app
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: my-app
```

---

#### EBS Volume AZ Binding

```hcl
volume_binding_mode = "WaitForFirstConsumer"
```

EBS volumes can only be attached to nodes in the same AZ. `WaitForFirstConsumer` delays volume creation until a pod is scheduled — the volume is then created in the same AZ as the node. Without this, a volume might be created in AZ-1 but the pod schedules in AZ-2, causing it to stay in `Pending` forever.

---

### 4. Karpenter — Node Autoscaling

#### How Karpenter Works

1. A pod is created with no node to run on (insufficient resources)
2. Karpenter reads the pod's resource requests, node selectors, tolerations, and affinity rules
3. Karpenter picks the cheapest instance type that fits the pod
4. Karpenter launches the EC2 instance and registers it with the cluster
5. The pod schedules onto the new node
6. When the node is empty or underutilised, Karpenter terminates it

This happens in seconds — much faster than the Cluster Autoscaler which works through Auto Scaling Groups.

---

#### EC2NodeClass — Node Configuration

```yaml
# karpenter.tf
amiSelectorTerms:
  - alias: al2023@v20260501   # pinned — never @latest in prod
role: <karpenter-node-role>
subnetSelectorTerms:
  - tags:
      karpenter.sh/discovery: prod-eks
securityGroupSelectorTerms:
  - tags:
      karpenter.sh/discovery: prod-eks
instanceMetadataOptions:
  httpTokens: required          # IMDSv2 enforced
```

The NodeClass describes the AWS-level properties of nodes. The subnet and security group selectors use tags to auto-discover the right resources — no hardcoded IDs that break across environments.

---

#### NodePool — Scheduling Constraints

```yaml
# karpenter.tf
requirements:
  - key: karpenter.sh/capacity-type
    operator: In
    values: ["spot", "on-demand"]    # Spot preferred, On-Demand fallback
  - key: karpenter.k8s.aws/instance-category
    operator: In
    values: ["c", "m", "r"]          # compute, general, memory families
  - key: karpenter.k8s.aws/instance-generation
    operator: Gt
    values: ["2"]                    # gen3 and newer only
expireAfter: 720h                    # 30-day node rotation
```

**Why broad instance selection matters for Spot**

Spot instances come from EC2 capacity pools. Each instance type in each AZ is a separate pool. If you restrict to only 2–3 instance types, all your Spot nodes might be in the same pool — one Spot reclamation event takes down all your nodes at once. With many eligible instance types across 3 AZs, the probability of simultaneous interruption drops dramatically.

---

#### Spot Interruption Handling

```hcl
# karpenter.tf
settings = {
  interruptionQueue = module.karpenter.queue_name
}
```

AWS sends a 2-minute warning before reclaiming a Spot instance. Karpenter receives this via an SQS queue, immediately taints the node, drains its pods, and starts a replacement node — all before the instance is terminated. Without this, pods are killed without warning.

---

#### Node Expiry and AMI Rotation

```yaml
expireAfter: 720h
```

Every node is replaced after 30 days regardless of utilisation. This ensures:
- Nodes always run a recent, patched AMI
- No long-lived nodes accumulate configuration drift
- AMI updates are gradual and automatic — no big-bang replacement events

To update the AMI: test the new alias in dev, update `al2023@v20260501` in `karpenter.tf`, then `terraform apply`. Old nodes expire and are replaced over the next 30 days.

---

#### Consolidation

```yaml
disruption:
  consolidationPolicy: WhenEmptyOrUnderutilized
  consolidateAfter: 5m
  budgets:
    - nodes: "10%"
```

Karpenter monitors node utilisation. When pods can be rescheduled onto fewer nodes, Karpenter moves them and terminates the now-empty nodes. The 10% budget means no more than 10% of nodes are disrupted simultaneously — important for production availability.

---

#### Resource Limits — Cost Guard Rail

```yaml
limits:
  cpu: 1000
  memory: 2000Gi
```

Karpenter stops provisioning new nodes when these limits are hit. Without limits, a misconfigured deployment with 10,000 replicas would provision thousands of nodes and generate an enormous AWS bill. Set a CloudWatch billing alarm alongside this.

---

### 5. Storage

#### gp3 Default StorageClass

```hcl
# storage.tf
storage_provisioner = "ebs.csi.aws.com"
parameters = {
  type      = "gp3"
  encrypted = "true"
  kmsKeyId  = aws_kms_key.ebs.arn
}
```

gp3 is 20% cheaper than gp2 with better baseline performance (3000 IOPS, 125 MB/s included) and independent IOPS/throughput scaling. All volumes are encrypted by default with the EBS KMS key.

**`gp2` is demoted** — `storage.tf` removes its default annotation so new PVCs always use gp3.

#### Adding More Storage Later

| Workload | Solution | When to use |
|---|---|---|
| Multiple pods reading same files | EFS (NFS) | Shared config, media, ML datasets |
| High-IOPS database | EBS io2 | PostgreSQL, MySQL needing >3000 IOPS |
| Cold archive data | EBS sc1 | Cheap large volumes, infrequent access |
| Reading S3 in pods | Mountpoint for S3 | Model weights, large datasets |
| ML training / HPC | FSx for Lustre | Hundreds of GB/s parallel throughput |

---

### 6. Cost Optimisation

#### Spot Instances for Application Workloads

Karpenter defaults to Spot with On-Demand fallback. Spot instances are typically 60–90% cheaper than On-Demand. The Spot interruption handler ensures graceful draining so pods are not killed abruptly.

Never run these on Spot:
- Karpenter itself (runs on system ON_DEMAND nodes)
- CoreDNS (tolerated on system nodes)
- Stateful workloads that cannot be safely interrupted

---

#### NAT Gateway — One Per AZ Not One Total

A single NAT Gateway saves ~$65/month but routes all outbound traffic from AZ-2 and AZ-3 through AZ-1. AWS charges $0.01/GB for cross-AZ traffic. At any significant scale, the cross-AZ data transfer cost exceeds the saving. Three NAT Gateways keep traffic within each AZ.

---

#### S3 Native State Locking

```hcl
use_lockfile = true
```

Terraform 1.10+ writes a `.tflock` file in S3 instead of using a DynamoDB lock table. Eliminates the DynamoDB table cost (~$1–5/month small, more at scale) and one fewer resource to manage.

---

#### Monitor Costs with Karpenter Limits

Set a CloudWatch billing alarm when you deploy — Karpenter can scale fast and you want to know before your bill surprises you:

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name eks-spend-alert \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --threshold 500 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions <your-sns-arn>
```

---

### 7. Cluster Upgrades

#### Kubernetes Version — Stay on Standard Support

```hcl
# variables.tf
default = "1.35"
```

| Version | Support | Extra cost |
|---|---|---|
| 1.35, 1.34, 1.33 | Standard (free) | No |
| 1.32, 1.31, 1.30 | Extended | Yes — per cluster/hour surcharge |

Always run a standard-support version. Check the calendar:

```bash
aws eks describe-cluster-versions \
  --query 'clusterVersions[*].{Version:clusterVersion,Status:status,EndStandard:endOfStandardSupportDate}'
```

---

#### How to Upgrade the Cluster

1. **Check add-on compatibility** — AWS lists compatible add-on versions per Kubernetes version
2. **Update `cluster_version`** in `terraform.tfvars`
3. **Run `terraform apply`** — EKS upgrades the control plane (10–15 min, zero downtime)
4. **Update system node group AMI** — change `ami_type` if needed, drain and replace nodes
5. **Karpenter nodes rotate automatically** via `expireAfter: 720h` — new nodes use the new Kubernetes version

Never skip a minor version. Go 1.33 → 1.34 → 1.35, not 1.33 → 1.35 directly.

---

#### How to Upgrade Karpenter

```bash
# 1. Check latest version
open https://github.com/aws/karpenter-provider-aws/releases/latest

# 2. Update the variable
# terraform.tfvars
karpenter_version = "1.x.x"

# 3. Apply
terraform apply
```

Karpenter upgrades are rolling — the old pods are replaced one at a time. The PDB ensures at least 1 replica is always running.

---

#### How to Rotate Node AMIs

```bash
# 1. Find the latest AL2023 AMI alias for your cluster version
aws ssm get-parameters-by-path \
  --path /aws/service/eks/optimized-ami/1.35/amazon-linux-2023/ \
  --query 'Parameters[*].Name' --output table

# 2. Update karpenter.tf
#    amiSelectorTerms:
#      - alias: al2023@v20260601   ← new version

# 3. Apply
terraform apply

# Nodes rotate automatically over 30 days via expireAfter.
# To force immediate rotation: delete nodes manually and Karpenter recreates them.
```

---

### 8. Day-2 Operations

#### Check Cluster Health

```bash
# All nodes ready
kubectl get nodes

# All system pods running
kubectl get pods -n kube-system

# Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=50

# Karpenter node provisioning activity
kubectl get events --field-selector reason=ProvisionedNodes -A
```

#### Check Karpenter Scaling

```bash
# Current NodePools and their limits
kubectl get nodepools

# Nodes Karpenter is managing
kubectl get nodeclaims

# Why a pod is unschedulable
kubectl describe pod <pending-pod>
```

#### Check Add-on Versions

```bash
# See installed add-on versions vs latest available
aws eks describe-addon-versions --cluster-name prod-eks \
  --query 'addons[*].{Name:addonName,Current:addonVersions[0].addonVersion}'
```

#### Rotate kubeconfig

```bash
# Refresh your local kubeconfig
aws eks update-kubeconfig --region us-east-1 --name prod-eks
```

---

## Adding Storage Later

| Need | Action |
|---|---|
| Shared files across pods | Add EFS CSI driver + `aws_efs_file_system` to a new `efs.tf` |
| High IOPS databases | Add `io2` StorageClass to `storage.tf` |
| S3 as filesystem in pods | Add Mountpoint for S3 CSI driver |
| ML/HPC parallel storage | Add FSx for Lustre |

---

## Estimated Cost

| Resource | $/month |
|---|---|
| EKS control plane | ~$72 |
| 2× m5.large system nodes (ON_DEMAND) | ~$138 |
| 3× NAT Gateway | ~$97 |
| EBS volumes + KMS + CloudWatch | ~$15 |
| **Minimum total (no app workloads)** | **~$322** |

Application node costs scale with traffic. Spot instances reduce app node costs by 60–90%.

---

## References

- [AWS EKS Best Practices Guide](https://docs.aws.amazon.com/eks/latest/best-practices/introduction.html)
- [Karpenter Documentation](https://karpenter.sh/docs/)
- [EKS Add-ons](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html)
- [VPC CNI](https://github.com/aws/amazon-vpc-cni-k8s)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [EKS Kubernetes Version Lifecycle](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)
