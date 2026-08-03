variable "name" {
  type = string
}

variable "transit_gateway_id" {
  type = string
}

variable "onprem_vpc_id" {
  type = string
}

variable "onprem_public_subnet_id" {
  type = string
}

variable "onprem_private_subnet_id" {
  type = string
}

variable "onprem_private_route_table_id" {
  type = string
}

variable "onprem_private_cidr" {
  description = "CIDR of the simulated on-prem private subnet — this is what gets advertised as reachable through the tunnel"
  type        = string
}

variable "aws_side_cidr_aggregate" {
  description = "Aggregate CIDR covering the AWS-side spoke VPCs, used as the IPsec right-hand subnet (e.g. 10.0.0.0/8 covers both 10.1.0.0/16 and 10.2.0.0/16)"
  type        = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "customer_gateway_bgp_asn" {
  type    = number
  default = 65000
}
