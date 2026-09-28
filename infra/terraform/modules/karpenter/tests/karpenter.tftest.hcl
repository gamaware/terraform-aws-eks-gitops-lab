# Offline: the AWS provider is mocked, so no credentials or API calls are needed.
mock_provider "aws" {
  source = "../../tests/mocks"
}

variables {
  cluster_name = "harbor-goods-test"
  cluster_arn  = "arn:aws:eks:us-east-1:111122223333:cluster/harbor-goods-test"
}

run "controller_can_only_act_on_its_own_instances" {
  command = apply

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.controller.statement :
      anytrue([for c in s.condition : c.variable == "aws:ResourceTag/kubernetes.io/cluster/harbor-goods-test" || c.variable == "aws:RequestTag/kubernetes.io/cluster/harbor-goods-test"])
      if anytrue([for a in s.actions : contains(["ec2:TerminateInstances", "ec2:DeleteLaunchTemplate", "ec2:CreateTags", "ec2:CreateLaunchTemplate", "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile"], a)])
    ])
    error_message = "Every destructive or tagging statement must be conditioned on the cluster ownership tag."
  }

  assert {
    condition = one([
      for s in data.aws_iam_policy_document.controller.statement : s.resources
      if contains(s.actions, "iam:PassRole")
    ]) == toset([aws_iam_role.node.arn])
    error_message = "iam:PassRole must be limited to the Karpenter node role."
  }

  assert {
    condition = one([
      for s in data.aws_iam_policy_document.controller.statement : s.resources
      if contains(s.actions, "eks:DescribeCluster")
    ]) == toset([var.cluster_arn])
    error_message = "eks:DescribeCluster must be limited to this cluster."
  }
}

run "controller_role_binds_to_the_karpenter_service_account" {
  command = apply

  assert {
    condition     = aws_eks_pod_identity_association.controller.namespace == "kube-system" && aws_eks_pod_identity_association.controller.service_account == "karpenter"
    error_message = "The controller role must bind to exactly kube-system/karpenter."
  }

  assert {
    condition     = aws_eks_access_entry.node.type == "EC2_LINUX"
    error_message = "Karpenter nodes join through an EC2_LINUX access entry."
  }
}

run "interruption_queue_receives_all_five_event_types" {
  command = apply

  assert {
    condition     = length(aws_cloudwatch_event_target.interruption) == 5
    error_message = "Spot, rebalance, health, state-change and capacity-reservation events must all reach the queue."
  }

  assert {
    condition     = alltrue([for t in aws_cloudwatch_event_target.interruption : t.arn == aws_sqs_queue.interruption.arn])
    error_message = "Every interruption rule must target the Karpenter queue."
  }

  assert {
    condition     = aws_sqs_queue.interruption.sqs_managed_sse_enabled
    error_message = "The interruption queue must be encrypted at rest."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.interruption_queue.statement :
      anytrue([for c in s.condition : c.variable == "aws:SourceArn"]) if contains(s.actions, "sqs:SendMessage")
    ])
    error_message = "Only this cluster's EventBridge rules may send to the queue."
  }

  assert {
    condition     = anytrue([for s in data.aws_iam_policy_document.interruption_queue.statement : s.effect == "Deny" && contains(s.actions, "sqs:*")])
    error_message = "The queue policy must deny requests that do not use TLS."
  }
}

run "names_match_the_gitops_values" {
  command = apply

  assert {
    condition     = output.interruption_queue_name == "harbor-goods-test-karpenter"
    error_message = "gitops/ sets settings.interruptionQueue to <cluster>-karpenter; the names must agree."
  }

  assert {
    condition     = output.node_role_name == "harbor-goods-test-karpenter-node"
    error_message = "gitops/ sets the EC2NodeClass role to <cluster>-karpenter-node; the names must agree."
  }
}
