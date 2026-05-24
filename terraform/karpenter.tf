# ── Karpenter IAM + SQS interruption queue ──────────────────────────────────
# Uses the official EKS module sub-module for Karpenter IAM resources.
# Pod Identity is used (preferred over IRSA for Karpenter v1+).
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"

  cluster_name = module.eks.cluster_name

  # v1 permissions schema (Karpenter >= 1.0)
  enable_v1_permissions = true

  # Pod Identity association — no OIDC token projection needed
  enable_pod_identity             = true
  create_pod_identity_association = true

  # SSM access lets nodes fetch AMI IDs and be managed via Session Manager
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = local.common_tags
}

# ── Karpenter Helm release ───────────────────────────────────────────────────
resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true

  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_version

  # wait=false: Karpenter itself needs nodes to schedule on; the system node group
  # provides those. Helm wait would deadlock if nodes aren't ready yet.
  wait = false

  values = [
    jsonencode({
      settings = {
        clusterName       = module.eks.cluster_name
        clusterEndpoint   = module.eks.cluster_endpoint
        interruptionQueue = module.karpenter.queue_name
      }
      tolerations = [
        {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
        }
      ]
      affinity = {
        nodeAffinity = {
          requiredDuringSchedulingIgnoredDuringExecution = {
            nodeSelectorTerms = [
              {
                matchExpressions = [
                  {
                    key      = "node-role"
                    operator = "In"
                    values   = ["system"]
                  }
                ]
              }
            ]
          }
        }
      }
      podDisruptionBudget = {
        minAvailable = 1
      }
      replicas = 2
      topologySpreadConstraints = [
        {
          maxSkew           = 1
          topologyKey       = "topology.kubernetes.io/zone"
          whenUnsatisfiable = "DoNotSchedule"
          labelSelector = {
            matchLabels = {
              "app.kubernetes.io/name" = "karpenter"
            }
          }
        }
      ]
    })
  ]

  depends_on = [module.eks]
}

# ── EC2NodeClass — describes how to build nodes ──────────────────────────────
resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      # Pin a tested AMI version in production — never use @latest in prod.
      # Test a new version in dev/staging, then update this alias here.
      # Find versions: aws ssm get-parameters-by-path \
      #   --path /aws/service/eks/optimized-ami/${var.cluster_version}/amazon-linux-2023/
      amiSelectorTerms:
        - alias: al2023@v20260501
      role: ${module.karpenter.node_iam_role_name}
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      blockDeviceMappings:
        - deviceName: /dev/xvda
          ebs:
            volumeSize: 50Gi
            volumeType: gp3
            encrypted: true
            kmsKeyID: ${aws_kms_key.ebs.arn}
            deleteOnTermination: true
      # IMDSv2 required on all Karpenter-managed nodes
      instanceMetadataOptions:
        httpTokens: required
        httpPutResponseHopLimit: 1
  YAML

  depends_on = [helm_release.karpenter]
}

# ── NodePool — scheduling constraints and limits ─────────────────────────────
resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: default
    spec:
      template:
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
          requirements:
            # Prefer Spot; fall back to On-Demand automatically
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["spot", "on-demand"]
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]
            # Broad family selection improves Spot availability — AWS best
            # practice is to avoid over-constraining instance types for Spot
            - key: karpenter.k8s.aws/instance-category
              operator: In
              values: ["c", "m", "r"]
            # Exclude only the very oldest generation; allow gen4+ for more pool depth
            - key: karpenter.k8s.aws/instance-generation
              operator: Gt
              values: ["2"]
            # Spread across all 3 AZs
            - key: topology.kubernetes.io/zone
              operator: In
              values: ${jsonencode(local.azs)}
          # Expire nodes after 30 days — forces AMI refresh and acts as a
          # rolling-upgrade mechanism; Karpenter replaces them gracefully
          expireAfter: 720h
      # Hard cap to prevent runaway scaling; set billing alarm alongside this
      limits:
        cpu: 1000
        memory: 2000Gi
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 5m
        budgets:
          # Never disrupt more than 10% of nodes at once during consolidation
          - nodes: "10%"
  YAML

  depends_on = [kubectl_manifest.karpenter_node_class]
}
