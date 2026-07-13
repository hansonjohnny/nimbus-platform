# ─────────────────────────────────────────
# ARGOCD
# Installed via the official Helm chart.
# After apply, retrieve the initial admin
# password and port-forward to access the UI:
#
#   kubectl get secret argocd-initial-admin-secret \
#     -n argocd -o jsonpath="{.data.password}" | base64 -d
#
#   kubectl port-forward svc/argocd-server -n argocd 8080:443
# ─────────────────────────────────────────
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.3.4"
  namespace        = "argocd"
  create_namespace = true

  set {
    name  = "server.service.type"
    value = "ClusterIP" # expose via kubectl port-forward or an Ingress
  }

  depends_on = [aws_eks_node_group.main]
}


# ─────────────────────────────────────────
# KUBERNETES NAMESPACES
# ─────────────────────────────────────────
resource "kubernetes_namespace" "nimbus_prod" {
  metadata {
    name = "nimbus-prod"

    labels = {
      managed_by  = "terraform"
      environment = "production"
    }
  }

  depends_on = [aws_eks_node_group.main]
}


# ─────────────────────────────────────────
# STRIMZI KAFKA OPERATOR
# Watches nimbus-prod and manages Kafka
# clusters declared as Kubernetes CRs
# (see kafka/kafka-cluster.yaml).
# ─────────────────────────────────────────
resource "helm_release" "strimzi" {
  name             = "strimzi-cluster-operator"
  repository       = "https://strimzi.io/charts/"
  chart            = "strimzi-kafka-operator"
  version          = "0.43.0"
  namespace        = "strimzi-system"
  create_namespace = true

  # Limit operator scope to the nimbus-prod namespace only
  set {
    name  = "watchNamespaces"
    value = "{nimbus-prod}"
  }

  depends_on = [kubernetes_namespace.nimbus_prod]
}
