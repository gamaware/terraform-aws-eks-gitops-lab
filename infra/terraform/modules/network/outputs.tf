output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs, one per AZ. Nodes and pods run here."
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs, one per AZ. Only internet-facing load balancers and NAT gateways use them; empty when private_only is true."
  value       = aws_subnet.public[*].id
}

output "nat_gateway_count" {
  description = "Number of NAT gateways created."
  value       = length(aws_nat_gateway.this)
}

output "interface_endpoint_services" {
  description = "Services reached through interface VPC endpoints; empty unless private_only is true."
  value       = sort(keys(aws_vpc_endpoint.interface))
}
