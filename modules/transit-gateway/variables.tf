variable "name" {
  type = string
}

variable "amazon_side_asn" {
  description = "BGP ASN for the AWS side of the Transit Gateway"
  type        = number
  default     = 64512
}

variable "spoke_attachments" {
  description = "Map of spoke VPCs to attach — key is a short name (e.g. \"hq\", \"branch\"), value is that VPC's id and the subnet the TGW ENI lands in"
  type = map(object({
    vpc_id         = string
    subnet_id      = string
    route_table_id = string
  }))
}
