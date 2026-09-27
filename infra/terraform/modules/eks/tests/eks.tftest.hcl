# Offline: the AWS provider is mocked, so no credentials or API calls are needed.
mock_provider "aws" {
  source = "../../tests/mocks"
}

variables {
  cluster_name        = "harbor-goods-test"
  kubernetes_version  = "1.35"
  subnet_ids          = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1", "subnet-0123456789abcdef2"]
  public_access_cidrs = ["203.0.113.10/32"]
  admin_role_arns     = ["arn:aws:iam::111122223333:role/HarborGoodsPlatformAdmin"]
  logs_kms_key_arn    = "arn:aws:kms:us-east-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
}

run "control_plane_is_hardened" {
  command = apply

  assert {
    condition     = length(aws_eks_cluster.this.enabled_cluster_log_types) == 5
    error_message = "All five control plane log types must be enabled."
  }

  assert {
    condition     = aws_eks_cluster.this.encryption_config[0].resources == toset(["secrets"])
    error_message = "Kubernetes Secrets must be envelope-encrypted with KMS."
  }

  assert {
    condition     = aws_kms_key.secrets.enable_key_rotation
    error_message = "The secrets key must rotate."
  }

  assert {
    condition     = aws_eks_cluster.this.access_config[0].authentication_mode == "API"
    error_message = "The cluster must use access entries only, not the aws-auth ConfigMap."
  }

  assert {
    condition     = aws_eks_cluster.this.access_config[0].bootstrap_cluster_creator_admin_permissions == false
    error_message = "The Terraform caller must not receive a hidden cluster-admin grant."
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_private_access
    error_message = "Nodes must reach the API through the private endpoint."
  }
}

run "admins_come_only_from_the_explicit_list" {
  command = apply

  assert {
    condition     = keys(aws_eks_access_policy_association.admin) == ["arn:aws:iam::111122223333:role/HarborGoodsPlatformAdmin"]
    error_message = "Only the listed admin roles may get cluster-admin."
  }

  assert {
    condition     = aws_eks_access_policy_association.admin["arn:aws:iam::111122223333:role/HarborGoodsPlatformAdmin"].access_scope[0].type == "cluster"
    error_message = "The admin association should be cluster-scoped."
  }
}

run "nodes_block_pod_access_to_instance_credentials" {
  command = apply

  assert {
    condition     = aws_launch_template.system.metadata_options[0].http_tokens == "required"
    error_message = "Nodes must require IMDSv2."
  }

  assert {
    condition     = aws_launch_template.system.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "A hop limit of 1 keeps pods from reading the node role credentials."
  }

  assert {
    condition     = aws_launch_template.system.block_device_mappings[0].ebs[0].encrypted == "true"
    error_message = "Node root volumes must be encrypted."
  }
}

run "controllers_get_one_role_each_through_pod_identity" {
  command = apply

  assert {
    condition     = aws_eks_pod_identity_association.load_balancer_controller.namespace == "kube-system" && aws_eks_pod_identity_association.load_balancer_controller.service_account == "aws-load-balancer-controller"
    error_message = "The load balancer controller role must bind to exactly kube-system/aws-load-balancer-controller."
  }

  assert {
    condition     = [for a in aws_eks_addon.this["aws-ebs-csi-driver"].pod_identity_association : a.service_account] == ["ebs-csi-controller-sa"]
    error_message = "The EBS CSI driver add-on must use its own Pod Identity role."
  }

  assert {
    condition     = [for a in aws_eks_addon.this["amazon-cloudwatch-observability"].pod_identity_association : a.service_account] == ["cloudwatch-agent"]
    error_message = "The CloudWatch agent must use its own Pod Identity role."
  }

  assert {
    condition     = length(aws_iam_role.pod_identity) == 3
    error_message = "Expected one role per controller: load balancer controller, EBS CSI driver, CloudWatch agent."
  }
}

run "network_add_ons_install_before_nodes" {
  command = apply

  assert {
    condition     = toset(keys(aws_eks_addon.before_compute)) == toset(["vpc-cni", "kube-proxy", "eks-pod-identity-agent"])
    error_message = "CNI, kube-proxy and the Pod Identity agent must exist before the first node joins."
  }

  assert {
    condition     = jsondecode(aws_eks_addon.before_compute["vpc-cni"].configuration_values).enableNetworkPolicy == "true"
    error_message = "The VPC CNI must enforce NetworkPolicy objects."
  }
}

run "private_only_endpoint_when_no_cidrs" {
  command = plan

  variables {
    public_access_cidrs = []
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_public_access == false
    error_message = "With no allowed CIDRs the public endpoint must be off."
  }
}

run "rejects_an_endpoint_open_to_the_internet" {
  command = plan

  variables {
    public_access_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.public_access_cidrs]
}

run "rejects_a_broad_range_that_is_not_0_0_0_0" {
  command = plan

  variables {
    public_access_cidrs = ["0.0.0.0/1"]
  }

  expect_failures = [var.public_access_cidrs]
}

run "rejects_a_cluster_without_admins" {
  command = plan

  variables {
    admin_role_arns = []
  }

  expect_failures = [var.admin_role_arns]
}
