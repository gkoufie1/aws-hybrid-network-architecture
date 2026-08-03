# Default route table with auto-associate/auto-propagate enabled — every
# attachment (both spoke VPCs, and the VPN attachment created in the vpn
# module) joins the same table automatically. That's what makes HQ, Branch,
# and the simulated on-prem site all reach each other through the hub
# without any manual TGW route table wiring — appropriate for a demo with
# one flat trust zone; a real enterprise deployment would likely segment
# route tables per environment instead of using the default for everything.
resource "aws_ec2_transit_gateway" "this" {
  description                     = var.name
  amazon_side_asn                 = var.amazon_side_asn
  auto_accept_shared_attachments  = "disable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = { Name = var.name }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "spoke" {
  for_each = var.spoke_attachments

  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = each.value.vpc_id
  subnet_ids         = [each.value.subnet_id]

  tags = { Name = "${var.name}-${each.key}" }
}

# Each spoke's private route table gets a route back through the TGW for
# every other spoke's CIDR — the TGW attachment alone doesn't make a VPC's
# own route table know to send traffic there.
resource "aws_route" "spoke_to_tgw" {
  for_each = var.spoke_attachments

  route_table_id         = each.value.route_table_id
  destination_cidr_block = "0.0.0.0/0" # simplified for a demo: send all non-local traffic to the hub
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.spoke]
}
