variable "name" {
  description = "Name prefix for this VPC and its resources"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet (workloads live here)"
  type        = string
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet. Only the on-prem-simulation VPC needs one, for the strongSwan router's public IP — spoke VPCs pass null and get no public subnet."
  type        = string
  default     = null
}

variable "availability_zone" {
  description = "Single AZ is enough for a demo — real multi-AZ HA isn't the point of this project"
  type        = string
}
