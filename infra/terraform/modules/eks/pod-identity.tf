# AWS access for in-cluster controllers through EKS Pod Identity: one role per controller,
# each bound to exactly one namespace and service account. The Helm charts need no role ARN
# annotations, so the GitOps values stay free of account-specific identifiers.

locals {
  pod_identities = {
    aws-load-balancer-controller = {
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
      managed_policy  = null
    }
    ebs-csi-driver = {
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
      managed_policy  = "service-role/AmazonEBSCSIDriverPolicy"
    }
    cloudwatch-observability = {
      namespace       = "amazon-cloudwatch"
      service_account = "cloudwatch-agent"
      managed_policy  = "CloudWatchAgentServerPolicy"
    }
  }
}

data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    # Confused-deputy guard: only this cluster, in this account, can assume the role.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_eks_cluster.this.arn]
    }
  }
}

resource "aws_iam_role" "pod_identity" {
  for_each = local.pod_identities

  name               = "${var.cluster_name}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "pod_identity_managed" {
  for_each = { for k, v in local.pod_identities : k => v if v.managed_policy != null }

  role       = aws_iam_role.pod_identity[each.key].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/${each.value.managed_policy}"
}

# Upstream policy for the AWS Load Balancer Controller, vendored unchanged and pinned to the
# controller version in gitops/applications/aws-load-balancer-controller.yaml. Refresh both
# together.
resource "aws_iam_policy" "load_balancer_controller" {
  name        = "${var.cluster_name}-aws-load-balancer-controller"
  description = "AWS Load Balancer Controller v3.5.0 upstream policy"
  policy      = file("${path.module}/policies/aws-load-balancer-controller-v3.5.0.json")

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "load_balancer_controller" {
  role       = aws_iam_role.pod_identity["aws-load-balancer-controller"].name
  policy_arn = aws_iam_policy.load_balancer_controller.arn
}

# The two EKS add-ons bind their own associations through aws_eks_addon; the load balancer
# controller is installed by Argo CD, so its association is created here.
resource "aws_eks_pod_identity_association" "load_balancer_controller" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = local.pod_identities["aws-load-balancer-controller"].namespace
  service_account = local.pod_identities["aws-load-balancer-controller"].service_account
  role_arn        = aws_iam_role.pod_identity["aws-load-balancer-controller"].arn

  tags = var.tags
}
