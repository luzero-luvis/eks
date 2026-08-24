# ── Default-deny NetworkPolicy ────────────────────────────────────────────────
# AWS best practice: start with deny-all in every namespace, then add explicit
# allow rules per application. This limits blast radius if a pod is compromised.
#
# Apply this pattern to each application namespace. The kube-system namespace
# below protects cluster-internal traffic.

resource "kubectl_manifest" "default_deny_kube_system" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: default-deny-all
      namespace: kube-system
    spec:
      podSelector: {}
      policyTypes:
        - Ingress
        - Egress
  YAML

  depends_on = [module.eks_addons]
}

# Allow CoreDNS to answer DNS queries from any pod in any namespace
resource "kubectl_manifest" "allow_coredns_ingress" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-coredns-ingress
      namespace: kube-system
    spec:
      podSelector:
        matchLabels:
          k8s-app: kube-dns
      policyTypes:
        - Ingress
      ingress:
        - ports:
            - protocol: UDP
              port: 53
            - protocol: TCP
              port: 53
  YAML

  depends_on = [kubectl_manifest.default_deny_kube_system]
}

# Allow CoreDNS egress so it can forward upstream DNS queries
resource "kubectl_manifest" "allow_coredns_egress" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-coredns-egress
      namespace: kube-system
    spec:
      podSelector:
        matchLabels:
          k8s-app: kube-dns
      policyTypes:
        - Egress
      egress:
        - {}
  YAML

  depends_on = [kubectl_manifest.default_deny_kube_system]
}

# ── CoreDNS autoscaling ───────────────────────────────────────────────────────
# Scales CoreDNS replicas proportionally to node count + core count.
# AWS recommends this for clusters using Karpenter where node count is dynamic.
resource "kubectl_manifest" "coredns_autoscaler" {
  yaml_body = <<-YAML
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: coredns-autoscaler
      namespace: kube-system
      labels:
        k8s-app: coredns-autoscaler
    spec:
      selector:
        matchLabels:
          k8s-app: coredns-autoscaler
      template:
        metadata:
          labels:
            k8s-app: coredns-autoscaler
        spec:
          serviceAccountName: coredns-autoscaler
          tolerations:
            - key: CriticalAddonsOnly
              operator: Exists
          nodeSelector:
            node-role: system
          containers:
            - name: autoscaler
              image: registry.k8s.io/cpa/cluster-proportional-autoscaler:v1.8.4
              command:
                - /cluster-proportional-autoscaler
                - --namespace=kube-system
                - --configmap=coredns-autoscaler
                - --target=Deployment/coredns
                - --logtostderr=true
                - --v=2
              resources:
                requests:
                  cpu: 20m
                  memory: 10Mi
                limits:
                  memory: 70Mi
  YAML

  depends_on = [module.eks_addons]
}

resource "kubectl_manifest" "coredns_autoscaler_sa" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: coredns-autoscaler
      namespace: kube-system
  YAML

  depends_on = [module.eks_addons]
}

resource "kubectl_manifest" "coredns_autoscaler_clusterrole" {
  yaml_body = <<-YAML
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRole
    metadata:
      name: coredns-autoscaler
    rules:
      - apiGroups: [""]
        resources: ["nodes"]
        verbs: ["list", "watch"]
      - apiGroups: [""]
        resources: ["replicationcontrollers/scale"]
        verbs: ["get", "update"]
      - apiGroups: ["apps"]
        resources: ["deployments/scale", "replicasets/scale"]
        verbs: ["get", "update"]
      - apiGroups: [""]
        resources: ["configmaps"]
        verbs: ["get", "create", "update"]
  YAML

  depends_on = [module.eks_addons]
}

resource "kubectl_manifest" "coredns_autoscaler_clusterrolebinding" {
  yaml_body = <<-YAML
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRoleBinding
    metadata:
      name: coredns-autoscaler
    roleRef:
      apiGroup: rbac.authorization.k8s.io
      kind: ClusterRole
      name: coredns-autoscaler
    subjects:
      - kind: ServiceAccount
        name: coredns-autoscaler
        namespace: kube-system
  YAML

  depends_on = [kubectl_manifest.coredns_autoscaler_clusterrole]
}

resource "kubectl_manifest" "coredns_autoscaler_configmap" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: coredns-autoscaler
      namespace: kube-system
    data:
      # 1 CoreDNS replica per 8 nodes OR per 256 cores, whichever is higher.
      # Minimum 2 replicas for HA.
      linear: |
        {
          "coresPerReplica": 256,
          "nodesPerReplica": 8,
          "min": 2,
          "preventSinglePointOfFailure": true
        }
  YAML

  depends_on = [module.eks_addons]
}
