# AWS side of Karpenter: the node role, the controller role (bound through EKS Pod Identity) and
# the interruption queue. The controller itself, its NodePool and EC2NodeClass are installed by
# Argo CD from gitops/. Policies follow the upstream Karpenter v1.14 CloudFormation reference.

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  partition   = data.aws_partition.current.partition
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.region
  cluster_tag = "kubernetes.io/cluster/${var.cluster_name}"

  # EC2 resource types Karpenter creates and must tag with the cluster ownership tag.
  taggable_types = ["fleet", "instance", "volume", "network-interface", "launch-template", "spot-instances-request"]

  interruption_events = {
    scheduled-change      = { source = "aws.health", detail_type = "AWS Health Event" }
    spot-interruption     = { source = "aws.ec2", detail_type = "EC2 Spot Instance Interruption Warning" }
    rebalance             = { source = "aws.ec2", detail_type = "EC2 Instance Rebalance Recommendation" }
    instance-state-change = { source = "aws.ec2", detail_type = "EC2 Instance State-change Notification" }
    capacity-reservation  = { source = "aws.ec2", detail_type = "EC2 Capacity Reservation Instance Interruption Warning" }
  }
}

# ---------------------------------------------------------------------------------------------
# Node role: what Karpenter-launched instances run as.
# ---------------------------------------------------------------------------------------------

data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.cluster_name}-karpenter-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    "AmazonEC2ContainerRegistryPullOnly",
    "AmazonSSMManagedInstanceCore",
  ])

  role       = aws_iam_role.node.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/${each.value}"
}

# Lets instances with the node role join the cluster without the aws-auth ConfigMap.
resource "aws_eks_access_entry" "node" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.node.arn
  type          = "EC2_LINUX"

  tags = var.tags
}

# ---------------------------------------------------------------------------------------------
# Interruption queue: Spot warnings, rebalance hints, health events and state changes.
# ---------------------------------------------------------------------------------------------

resource "aws_sqs_queue" "interruption" {
  name                      = "${var.cluster_name}-karpenter"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = var.tags
}

data "aws_iam_policy_document" "interruption_queue" {
  statement {
    sid       = "EventBridgeWrite"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.interruption.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    # Only this cluster's rules may write, so no other account can inject fake interruptions.
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [for r in aws_cloudwatch_event_rule.interruption : r.arn]
    }
  }

  statement {
    sid       = "DenyHTTP"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.interruption.arn]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "interruption" {
  queue_url = aws_sqs_queue.interruption.url
  policy    = data.aws_iam_policy_document.interruption_queue.json
}

resource "aws_cloudwatch_event_rule" "interruption" {
  for_each = local.interruption_events

  name        = "${var.cluster_name}-karpenter-${each.key}"
  description = "Karpenter interruption handling: ${each.value.detail_type}"
  event_pattern = jsonencode({
    source      = [each.value.source]
    detail-type = [each.value.detail_type]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "interruption" {
  for_each = local.interruption_events

  rule      = aws_cloudwatch_event_rule.interruption[each.key].name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.interruption.arn
}
