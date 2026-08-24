output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnets" {
  description = "Private subnet IDs — worker nodes and pods"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "Public subnet IDs — NAT gateways and internet-facing load balancers"
  value       = module.vpc.public_subnets
}

output "intra_subnets" {
  description = "Intra subnet IDs — EKS control-plane ENIs, no route to the internet"
  value       = module.vpc.intra_subnets
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs, one per AZ"
  value       = module.vpc.natgw_ids
}

output "private_route_table_ids" {
  description = "Private route table IDs — one per AZ"
  value       = module.vpc.private_route_table_ids
}

output "vpc_endpoint_ids" {
  description = "VPC endpoint IDs keyed by service"
  value       = module.vpc_endpoints.endpoints
}

output "vpc_endpoints_security_group_id" {
  description = "Security group attached to the interface endpoints, if any"
  value       = try(aws_security_group.vpc_endpoints[0].id, null)
}
