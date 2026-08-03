# Deliberately allows only ICMP and port 80 from the other sites' subnet
# CIDRs — enough to prove cross-site reachability (ping + a simple HTTP
# test server) without opening this workload to anything broader.
resource "aws_security_group" "workload" {
  name   = var.name
  vpc_id = var.vpc_id

  ingress {
    description = "Ping from other sites"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = var.allowed_cidrs
  }

  ingress {
    description = "Test HTTP server from other sites"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = var.name }
}
