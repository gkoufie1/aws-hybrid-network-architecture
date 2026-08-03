variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "availability_zone" {
  description = "Single AZ for every subnet — this project is about routing/connectivity, not HA, so multi-AZ would add cost and complexity without teaching anything new over the other repos"
  type        = string
  default     = "eu-west-2a"
}
