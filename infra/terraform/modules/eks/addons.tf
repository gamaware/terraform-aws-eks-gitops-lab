# EKS managed add-ons. Each version is the default EKS publishes for the cluster's Kubernetes
# version, so a cluster upgrade moves the add-ons to their matching versions in the same plan.

locals {
  addons = {
    eks-pod-identity-agent = {
      configuration  = null
      pod_identity   = null
      before_compute = true
    }
    vpc-cni = {
      # Network policy enforcement in the VPC CNI, so the chart's NetworkPolicy is honoured.
      configuration  = jsonencode({ enableNetworkPolicy = "true" })
      pod_identity   = null
      before_compute = true
    }
    kube-proxy = {
      configuration  = null
      pod_identity   = null
      before_compute = true
    }
    coredns = {
      configuration  = null
      pod_identity   = null
      before_compute = false
    }
    aws-ebs-csi-driver = {
      configuration  = null
      pod_identity   = "ebs-csi-driver"
      before_compute = false
    }
    # Container Insights metrics plus Fluent Bit log shipping to CloudWatch Logs.
    amazon-cloudwatch-observability = {
      configuration  = null
      pod_identity   = "cloudwatch-observability"
      before_compute = false
    }
  }
}

data "aws_eks_addon_version" "this" {
  for_each = local.addons

  addon_name         = each.key
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = false
}

# Networking add-ons go in before the node group so the first nodes join with a working CNI.
resource "aws_eks_addon" "before_compute" {
  for_each = { for k, v in local.addons : k => v if v.before_compute }

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = data.aws_eks_addon_version.this[each.key].version
  configuration_values        = each.value.configuration
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = var.tags
}

resource "aws_eks_addon" "this" {
  for_each = { for k, v in local.addons : k => v if !v.before_compute }

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = data.aws_eks_addon_version.this[each.key].version
  configuration_values        = each.value.configuration
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  dynamic "pod_identity_association" {
    for_each = each.value.pod_identity == null ? [] : [local.pod_identities[each.value.pod_identity]]

    content {
      role_arn        = aws_iam_role.pod_identity[each.value.pod_identity].arn
      service_account = pod_identity_association.value.service_account
    }
  }

  tags = var.tags

  depends_on = [aws_eks_node_group.system]
}
