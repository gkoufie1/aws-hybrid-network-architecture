output "onprem_router_public_ip" {
  value = aws_eip.onprem_router.public_ip
}

output "onprem_router_instance_id" {
  value = aws_instance.onprem_router.id
}

output "vpn_connection_id" {
  value = aws_vpn_connection.onprem.id
}

output "transit_gateway_attachment_id" {
  value = aws_vpn_connection.onprem.transit_gateway_attachment_id
}
