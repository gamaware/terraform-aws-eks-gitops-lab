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
