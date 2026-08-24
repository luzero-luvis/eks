data "aws_partition" "current" {}

# ── Karpenter IAM + SQS interruption queue ──────────────────────────────────
# Uses the official EKS module sub-module for Karpenter IAM resources.
# Pod Identity is used (preferred over IRSA for Karpenter v1+).
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.25"

  cluster_name = var.cluster_name

  # Pod Identity association — no OIDC token projection needed
  create_pod_identity_association = true

  # SSM access lets nodes fetch AMI IDs and be managed via Session Manager
  node_iam_role_additional_policies = merge(
    {
      AmazonSSMManagedInstanceCore = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
    },
    var.node_iam_role_additional_policies,
  )

  tags = var.tags
}

# ── Karpenter Helm release ───────────────────────────────────────────────────
resource "helm_release" "karpenter" {
  namespace        = var.namespace
  create_namespace = true

  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.chart_version

  # wait=false: Karpenter itself needs nodes to schedule on; the system node group
  # provides those. Helm wait would deadlock if nodes aren't ready yet.
  wait = false

  values = [
    jsonencode({
      settings = {
        clusterName       = var.cluster_name
        clusterEndpoint   = var.cluster_endpoint
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
      replicas = var.replicas
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
}

# ── EC2NodeClass — describes how to build nodes ──────────────────────────────
resource "kubectl_manifest" "node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      # Pin a tested AMI version in production — never use @latest in prod.
      # Test a new version in dev/staging, then update this alias here.
      # Find versions: aws ssm get-parameters-by-path \
      #   --path /aws/service/eks/optimized-ami/<k8s-version>/amazon-linux-2023/
      amiSelectorTerms:
        - alias: ${var.ami_alias}
      role: ${module.karpenter.node_iam_role_name}
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${var.discovery_tag_value}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${var.discovery_tag_value}
      blockDeviceMappings:
        - deviceName: /dev/xvda
          ebs:
            volumeSize: ${var.node_volume_size}Gi
            volumeType: ${var.node_volume_type}
            encrypted: true
            deleteOnTermination: true
      # IMDSv2 required on all Karpenter-managed nodes
      instanceMetadataOptions:
        httpTokens: required
        httpPutResponseHopLimit: 1
  YAML

  depends_on = [helm_release.karpenter]
}

# ── NodePool — scheduling constraints and limits ─────────────────────────────
resource "kubectl_manifest" "node_pool" {
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
              values: ${jsonencode(var.capacity_types)}
            - key: kubernetes.io/arch
              operator: In
              values: ${jsonencode(var.architectures)}
            # Broad family selection improves Spot availability — AWS best
            # practice is to avoid over-constraining instance types for Spot
            - key: karpenter.k8s.aws/instance-category
              operator: In
              values: ${jsonencode(var.instance_categories)}
            # Exclude only the very oldest generation; allow gen4+ for more pool depth
            - key: karpenter.k8s.aws/instance-generation
              operator: Gt
              values: ["${var.min_instance_generation}"]
            # Spread across all AZs the cluster runs in
            - key: topology.kubernetes.io/zone
              operator: In
              values: ${jsonencode(var.availability_zones)}
          # Expire nodes after this long — forces AMI refresh and acts as a
          # rolling-upgrade mechanism; Karpenter replaces them gracefully
          expireAfter: ${var.expire_after}
      # Hard cap to prevent runaway scaling; set billing alarm alongside this
      limits:
        cpu: ${var.cpu_limit}
        memory: ${var.memory_limit}
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: ${var.consolidate_after}
        budgets:
          # Never disrupt more than this share of nodes at once
          - nodes: "${var.disruption_budget_nodes}"
  YAML

  depends_on = [kubectl_manifest.node_class]
}
