data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# --- Spoke VPCs -------------------------------------------------------------

module "vpc_hq" {
  source              = "./modules/vpc"
  name                = "hybrid-hq"
  vpc_cidr            = "10.1.0.0/16"
  private_subnet_cidr = "10.1.1.0/24"
  availability_zone   = var.availability_zone
}

module "vpc_branch" {
  source              = "./modules/vpc"
  name                = "hybrid-branch"
  vpc_cidr            = "10.2.0.0/16"
  private_subnet_cidr = "10.2.1.0/24"
  availability_zone   = var.availability_zone
}

module "vpc_onprem" {
  source              = "./modules/vpc"
  name                = "hybrid-onprem-sim"
  vpc_cidr            = "10.3.0.0/16"
  private_subnet_cidr = "10.3.1.0/24"
  public_subnet_cidr  = "10.3.0.0/24" # only VPC that needs one — the strongSwan router's EIP lives here
  availability_zone   = var.availability_zone
}

# --- Transit Gateway hub, connecting the two spoke VPCs ---------------------

module "transit_gateway" {
  source = "./modules/transit-gateway"
  name   = "hybrid-network-tgw"

  spoke_attachments = {
    hq = {
      vpc_id         = module.vpc_hq.vpc_id
      subnet_id      = module.vpc_hq.private_subnet_id
      route_table_id = module.vpc_hq.private_route_table_id
    }
    branch = {
      vpc_id         = module.vpc_branch.vpc_id
      subnet_id      = module.vpc_branch.private_subnet_id
      route_table_id = module.vpc_branch.private_route_table_id
    }
  }
}

# --- Site-to-Site VPN, simulating a secure tunnel to a physical facility ----

module "vpn" {
  source = "./modules/vpn"
  name   = "hybrid-network"

  transit_gateway_id            = module.transit_gateway.transit_gateway_id
  onprem_vpc_id                 = module.vpc_onprem.vpc_id
  onprem_public_subnet_id       = module.vpc_onprem.public_subnet_id
  onprem_private_subnet_id      = module.vpc_onprem.private_subnet_id
  onprem_private_route_table_id = module.vpc_onprem.private_route_table_id
  onprem_private_cidr           = "10.3.1.0/24"
  aws_side_cidr_aggregate       = "10.0.0.0/8" # covers both 10.1.0.0/16 (HQ) and 10.2.0.0/16 (Branch)
}

# The VPN connection's static route has to be added to the Transit
# Gateway's own route table, not via aws_vpn_connection_route (that
# resource only works for VGW-attached VPNs).
resource "aws_ec2_transit_gateway_route" "onprem" {
  destination_cidr_block         = "10.3.1.0/24"
  transit_gateway_route_table_id = module.transit_gateway.default_route_table_id
  transit_gateway_attachment_id  = module.vpn.transit_gateway_attachment_id
}

# --- SSM VPC endpoints — private-subnet instances have no other way to be
# reachable for management, since none of these VPCs have a NAT gateway or
# internet gateway on the private side. ---

module "vpc_endpoints_hq" {
  source    = "./modules/vpc-endpoints"
  name      = "hybrid-hq"
  vpc_id    = module.vpc_hq.vpc_id
  vpc_cidr  = "10.1.0.0/16"
  subnet_id = module.vpc_hq.private_subnet_id
  region    = var.aws_region
}

module "vpc_endpoints_branch" {
  source    = "./modules/vpc-endpoints"
  name      = "hybrid-branch"
  vpc_id    = module.vpc_branch.vpc_id
  vpc_cidr  = "10.2.0.0/16"
  subnet_id = module.vpc_branch.private_subnet_id
  region    = var.aws_region
}

module "vpc_endpoints_onprem" {
  source    = "./modules/vpc-endpoints"
  name      = "hybrid-onprem"
  vpc_id    = module.vpc_onprem.vpc_id
  vpc_cidr  = "10.3.0.0/16"
  subnet_id = module.vpc_onprem.private_subnet_id
  region    = var.aws_region
}

# --- Security groups for the test workloads used to verify connectivity ----

module "sg_hq" {
  source        = "./modules/security-groups"
  name          = "hybrid-hq-workload"
  vpc_id        = module.vpc_hq.vpc_id
  allowed_cidrs = ["10.2.1.0/24", "10.3.1.0/24"] # Branch + on-prem private subnets
}

module "sg_branch" {
  source        = "./modules/security-groups"
  name          = "hybrid-branch-workload"
  vpc_id        = module.vpc_branch.vpc_id
  allowed_cidrs = ["10.1.1.0/24", "10.3.1.0/24"] # HQ + on-prem private subnets
}

module "sg_onprem" {
  source        = "./modules/security-groups"
  name          = "hybrid-onprem-workload"
  vpc_id        = module.vpc_onprem.vpc_id
  allowed_cidrs = ["10.1.1.0/24", "10.2.1.0/24"] # HQ + Branch private subnets
}

# --- Shared SSM access for the three test workloads -------------------------
# One role, not three — these are identical, low-privilege, debug-only test
# instances, unlike the VPN module's router which has its own tighter
# purpose-specific role.

resource "aws_iam_role" "test_workload" {
  name = "hybrid-network-test-workload-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "test_workload_ssm" {
  role       = aws_iam_role.test_workload.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "test_workload" {
  name = "hybrid-network-test-workload"
  role = aws_iam_role.test_workload.name
}

locals {
  test_server_user_data = <<-EOF
    #!/bin/bash
    echo "Hello from $(hostname)" > /tmp/index.html
    cd /tmp && nohup python3 -m http.server 80 &
  EOF
}

resource "aws_instance" "test_hq" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = module.vpc_hq.private_subnet_id
  vpc_security_group_ids      = [module.sg_hq.security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.test_workload.name
  associate_public_ip_address = false # private subnet, no default route to an IGW anyway — explicit for clarity
  user_data                   = local.test_server_user_data

  tags = { Name = "hybrid-hq-test" }
}

resource "aws_instance" "test_branch" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = module.vpc_branch.private_subnet_id
  vpc_security_group_ids      = [module.sg_branch.security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.test_workload.name
  associate_public_ip_address = false # private subnet, no default route to an IGW anyway — explicit for clarity
  user_data                   = local.test_server_user_data

  tags = { Name = "hybrid-branch-test" }
}

resource "aws_instance" "test_onprem" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = module.vpc_onprem.private_subnet_id
  vpc_security_group_ids      = [module.sg_onprem.security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.test_workload.name
  associate_public_ip_address = false # private subnet, no default route to an IGW anyway — explicit for clarity
  user_data                   = local.test_server_user_data

  tags = { Name = "hybrid-onprem-test" }
}
