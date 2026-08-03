data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_eip" "onprem_router" {
  domain = "vpc"
  tags   = { Name = "${var.name}-onprem-router" }
}

# The Customer Gateway represents the "on-prem" device's public IP to AWS.
# It has to exist before the instance does, so AWS can hand back the
# tunnel's outside IP + pre-shared key for the instance's user_data to
# configure strongSwan with — this is the piece that makes the ordering
# here matter: EIP -> Customer Gateway -> VPN Connection -> EC2 instance.
resource "aws_customer_gateway" "onprem" {
  bgp_asn    = var.customer_gateway_bgp_asn
  ip_address = aws_eip.onprem_router.public_ip
  type       = "ipsec.1"

  tags = { Name = "${var.name}-onprem" }
}

# Attached directly to the Transit Gateway (not a per-VPC VPN Gateway) —
# this is what lets the on-prem side reach both spoke VPCs through the
# hub's routing, instead of only the one VPC a VGW would be attached to.
resource "aws_vpn_connection" "onprem" {
  customer_gateway_id = aws_customer_gateway.onprem.id
  transit_gateway_id  = var.transit_gateway_id
  type                = "ipsec.1"
  static_routes_only  = true

  tags = { Name = "${var.name}-onprem" }
}

resource "aws_vpn_connection_route" "onprem_private" {
  vpn_connection_id      = aws_vpn_connection.onprem.id
  destination_cidr_block = var.onprem_private_cidr
}

resource "aws_security_group" "onprem_router" {
  name   = "${var.name}-onprem-router"
  vpc_id = var.onprem_vpc_id

  ingress {
    description = "IPsec IKE"
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "IPsec NAT-T"
    from_port   = 4500
    to_port     = 4500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "From the on-prem private subnet this instance routes for"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.onprem_private_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-onprem-router" }
}

resource "aws_iam_role" "onprem_router" {
  name = "${var.name}-onprem-router-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# SSM instead of a key pair + open SSH port — matches the least-privilege
# access pattern used across the other repos, and one less inbound rule
# to justify.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.onprem_router.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "onprem_router" {
  name = "${var.name}-onprem-router"
  role = aws_iam_role.onprem_router.name
}

resource "aws_instance" "onprem_router" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = var.onprem_public_subnet_id
  vpc_security_group_ids = [aws_security_group.onprem_router.id]
  iam_instance_profile   = aws_iam_instance_profile.onprem_router.name
  source_dest_check      = false # this instance routes traffic that isn't addressed to itself

  user_data = templatefile("${path.module}/templates/strongswan-setup.sh.tftpl", {
    onprem_public_ip      = aws_eip.onprem_router.public_ip
    onprem_private_cidr   = var.onprem_private_cidr
    aws_tunnel_outside_ip = aws_vpn_connection.onprem.tunnel1_address
    aws_side_cidr         = var.aws_side_cidr_aggregate
    preshared_key         = aws_vpn_connection.onprem.tunnel1_preshared_key
  })

  tags = { Name = "${var.name}-onprem-router" }
}

resource "aws_eip_association" "onprem_router" {
  instance_id   = aws_instance.onprem_router.id
  allocation_id = aws_eip.onprem_router.id
}

# The on-prem private subnet's route table sends AWS-bound traffic through
# this instance's ENI — it's acting as that subnet's default gateway for
# anything not local.
resource "aws_route" "onprem_private_to_router" {
  route_table_id         = var.onprem_private_route_table_id
  destination_cidr_block = var.aws_side_cidr_aggregate
  network_interface_id   = aws_instance.onprem_router.primary_network_interface_id
}
