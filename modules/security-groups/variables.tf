variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "allowed_cidrs" {
  description = "CIDRs allowed to ping and curl this workload — the other sites' subnets, not the internet"
  type        = list(string)
}
