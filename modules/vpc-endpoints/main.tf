# Lets SSM manage instances in a private subnet with no internet egress at
# all (no NAT gateway, no IGW route) — discovered as a real gap when the
# test instances in the spoke VPCs turned out to be unreachable by SSM for
# exactly that reason. This is also the standard enterprise pattern for
# managing private instances: PrivateLink to AWS APIs, not a NAT gateway
# just so an agent can phone home.

resource "aws_security_group" "vpc_endpoints" {
  name   = "${var.name}-vpc-endpoints"
  vpc_id = var.vpc_id

  ingress {
    description = "HTTPS from within this VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-vpc-endpoints" }
}

locals {
  ssm_services = ["ssm", "ssmmessages", "ec2messages"]
}

resource "aws_vpc_endpoint" "ssm" {
  for_each = toset(local.ssm_services)

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [var.subnet_id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = { Name = "${var.name}-${each.value}" }
}
