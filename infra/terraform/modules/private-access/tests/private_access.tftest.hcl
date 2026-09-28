# Offline: the AWS provider is mocked, so no credentials or API calls are needed.
mock_provider "aws" {
  source = "../../tests/mocks"
}

variables {
  name                      = "harbor-goods-test"
  vpc_id                    = "vpc-0123456789abcdef0"
  vpc_cidr                  = "10.10.0.0/16"
  subnet_id                 = "subnet-0123456789abcdef0"
  cluster_security_group_id = "sg-0123456789abcdef0"
  node_role_names           = ["harbor-goods-test-node", "harbor-goods-test-karpenter-node"]
  karpenter_node_role_name  = "harbor-goods-test-karpenter-node"
}

run "relay_is_not_reachable_from_anywhere" {
  command = apply

  assert {
    condition     = aws_instance.access.associate_public_ip_address == false
    error_message = "The relay must never get a public IP address."
  }

  assert {
    condition     = length(aws_security_group.access.ingress) == 0
    error_message = "The relay accepts no inbound connections; Session Manager needs none."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.access_https.cidr_ipv4 == var.vpc_cidr && aws_vpc_security_group_egress_rule.access_https.from_port == 443
    error_message = "The relay may only open HTTPS connections inside the VPC."
  }

  assert {
    condition     = aws_instance.access.metadata_options[0].http_tokens == "required" && aws_instance.access.root_block_device[0].encrypted
    error_message = "The relay enforces IMDSv2 and encrypts its root volume."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.cluster_from_access.referenced_security_group_id == aws_security_group.access.id
    error_message = "The API endpoint accepts the relay by security group, not by address."
  }
}

run "nodes_pull_public_images_through_ecr" {
  command = apply

  assert {
    condition     = toset(values(aws_ecr_pull_through_cache_rule.this)[*].upstream_registry_url) == toset(["public.ecr.aws", "registry.k8s.io"])
    error_message = "Every upstream registry the cluster uses needs a pull-through cache rule."
  }

  assert {
    condition     = toset(keys(aws_iam_role_policy.pull_through)) == toset(var.node_role_names)
    error_message = "Every node role may fill the cache on first pull."
  }

  assert {
    condition     = aws_iam_instance_profile.karpenter_node.role == var.karpenter_node_role_name
    error_message = "Karpenter nodes use a pre-created instance profile; the VPC has no IAM endpoint."
  }
}
