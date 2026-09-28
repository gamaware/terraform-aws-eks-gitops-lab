# Offline: the AWS provider is mocked, so no credentials or API calls are needed.
mock_provider "aws" {
  source = "../../tests/mocks"
}

variables {
  name         = "harbor-goods-test"
  cluster_name = "harbor-goods-test"
  azs          = ["us-east-1a", "us-east-1b", "us-east-1c"]
  kms_key_arn  = "arn:aws:kms:us-east-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
}

run "subnets_are_tagged_for_load_balancers_and_karpenter" {
  command = apply

  assert {
    condition     = length(aws_subnet.private) == 3 && length(aws_subnet.public) == 3
    error_message = "Expected one public and one private subnet per AZ."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.private : s.tags["kubernetes.io/role/internal-elb"] == "1"])
    error_message = "Private subnets must carry the internal-elb role tag for the load balancer controller."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.tags["kubernetes.io/role/elb"] == "1"])
    error_message = "Public subnets must carry the elb role tag for internet-facing load balancers."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.private : s.tags["karpenter.sh/discovery"] == "harbor-goods-test"])
    error_message = "Karpenter discovers node subnets by the karpenter.sh/discovery tag."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.map_public_ip_on_launch == false])
    error_message = "Nothing launched in a public subnet may get a public IP by default."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.private : s.map_public_ip_on_launch == false])
    error_message = "Nodes launch in private subnets and must never get a public IP."
  }
}

run "subnet_ranges_do_not_overlap" {
  command = plan

  assert {
    condition     = [for s in aws_subnet.private : s.cidr_block] == ["10.0.0.0/19", "10.0.32.0/19", "10.0.64.0/19"]
    error_message = "Private subnets should be the first three /19 blocks of the VPC."
  }

  assert {
    condition     = [for s in aws_subnet.public : s.cidr_block] == ["10.0.224.0/24", "10.0.225.0/24", "10.0.226.0/24"]
    error_message = "Public subnets should sit in the top of the range, clear of the private /19 blocks."
  }
}

run "production_gets_one_nat_gateway_per_az" {
  command = apply

  variables {
    single_nat_gateway = false
  }

  assert {
    condition     = output.nat_gateway_count == 3
    error_message = "Without single_nat_gateway every AZ needs its own NAT gateway."
  }

  assert {
    condition     = alltrue([for i, r in aws_route.private_nat : r.nat_gateway_id == aws_nat_gateway.this[i].id])
    error_message = "Each private route table must route through the NAT gateway in its own AZ."
  }
}

run "dev_can_share_one_nat_gateway" {
  command = apply

  variables {
    single_nat_gateway = true
  }

  assert {
    condition     = output.nat_gateway_count == 1
    error_message = "single_nat_gateway should create exactly one NAT gateway."
  }

  assert {
    condition     = length(distinct([for r in aws_route.private_nat : r.nat_gateway_id])) == 1
    error_message = "All private route tables should share the single NAT gateway."
  }
}

run "private_only_has_no_internet_path" {
  command = apply

  variables {
    private_only = true
  }

  assert {
    condition     = length(aws_internet_gateway.this) == 0 && length(aws_subnet.public) == 0
    error_message = "A private-only VPC has no internet gateway and no public subnets."
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 0 && length(aws_eip.nat) == 0 && length(aws_route.private_nat) == 0
    error_message = "A private-only VPC has no NAT gateway, Elastic IP or default route."
  }

  assert {
    condition     = length(aws_route.public_internet) == 0
    error_message = "A private-only VPC has no route to an internet gateway."
  }

  assert {
    condition     = alltrue([for s in ["ec2", "ecr.api", "ecr.dkr", "eks", "eks-auth", "sts", "ssm", "ssmmessages", "ec2messages"] : contains(keys(aws_vpc_endpoint.interface), s)])
    error_message = "Nodes, controllers and Session Manager need interface endpoints for their AWS APIs."
  }

  assert {
    condition     = length(aws_vpc_endpoint.s3) == 1 && aws_vpc_endpoint.s3[0].vpc_endpoint_type == "Gateway"
    error_message = "ECR image layers come from S3 through a gateway endpoint."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.endpoints_https.cidr_ipv4 == var.cidr && aws_vpc_security_group_ingress_rule.endpoints_https.from_port == 443
    error_message = "Interface endpoints accept HTTPS from the VPC only."
  }
}

run "every_vpc_gets_session_manager_endpoints" {
  command = apply

  assert {
    condition     = toset(keys(aws_vpc_endpoint.interface)) == toset(["ssm", "ssmmessages", "ec2messages"]) && length(aws_vpc_endpoint.s3) == 0
    error_message = "Every VPC gets the Session Manager endpoints for the API relay; the rest exist only in private-only mode."
  }
}

run "flow_logs_capture_all_traffic_encrypted" {
  command = apply

  assert {
    condition     = aws_flow_log.this.traffic_type == "ALL"
    error_message = "Flow logs must capture accepted and rejected traffic."
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_logs.kms_key_id == var.kms_key_arn
    error_message = "The flow log group must be encrypted with the platform key."
  }
}

run "rejects_a_single_availability_zone" {
  command = plan

  variables {
    azs = ["us-east-1a"]
  }

  expect_failures = [var.azs]
}
