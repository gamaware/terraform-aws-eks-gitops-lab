# VPC endpoints. Every VPC gets the Session Manager endpoints (ssm, ssmmessages, ec2messages),
# which carry the operator's port forwarding to the private API endpoint. A private-only VPC
# also gets the endpoints nodes need without an internet path: ECR (including pull-through
# cache repositories), EC2, STS, CloudWatch, SQS, EKS and S3.

data "aws_region" "current" {}

locals {
  session_manager_services = ["ssm", "ssmmessages", "ec2messages"]
  interface_endpoints      = toset(var.private_only ? concat(var.interface_endpoint_services, local.session_manager_services) : local.session_manager_services)
}

resource "aws_security_group" "endpoints" {
  name        = "${var.name}-vpc-endpoints"
  description = "HTTPS from inside the VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-vpc-endpoints" })
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  security_group_id = aws_security_group.endpoints.id
  description       = "HTTPS from the VPC"
  cidr_ipv4         = var.cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.name}-${each.value}" })
}

resource "aws_vpc_endpoint" "s3" {
  count = var.private_only ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = merge(var.tags, { Name = "${var.name}-s3" })
}
