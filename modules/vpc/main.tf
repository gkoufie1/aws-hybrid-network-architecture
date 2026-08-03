resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.name }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone

  tags = { Name = "${var.name}-private" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-private" }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# --- Public subnet: only created when public_subnet_cidr is set ---
# Only the on-prem-simulation VPC needs this, for the strongSwan
# router's Elastic IP (the Customer Gateway's public-facing address).

resource "aws_subnet" "public" {
  count = var.public_subnet_cidr != null ? 1 : 0

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = { Name = "${var.name}-public" }
}

resource "aws_internet_gateway" "this" {
  count  = var.public_subnet_cidr != null ? 1 : 0
  vpc_id = aws_vpc.this.id
  tags   = { Name = var.name }
}

resource "aws_route_table" "public" {
  count  = var.public_subnet_cidr != null ? 1 : 0
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-public" }
}

resource "aws_route" "public_internet" {
  count                  = var.public_subnet_cidr != null ? 1 : 0
  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route_table_association" "public" {
  count          = var.public_subnet_cidr != null ? 1 : 0
  subnet_id      = aws_subnet.public[0].id
  route_table_id = aws_route_table.public[0].id
}
