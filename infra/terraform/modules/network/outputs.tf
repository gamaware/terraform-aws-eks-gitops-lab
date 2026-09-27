output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs, one per AZ. Nodes and pods run here."
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs, one per AZ. Only internet-facing load balancers and NAT gateways use them."
  value       = aws_subnet.public[*].id
}

output "nat_gateway_count" {
  description = "Number of NAT gateways created."
  value       = length(aws_nat_gateway.this)
}
