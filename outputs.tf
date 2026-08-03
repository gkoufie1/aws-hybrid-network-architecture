output "transit_gateway_id" {
  value = module.transit_gateway.transit_gateway_id
}

output "onprem_router_public_ip" {
  value = module.vpn.onprem_router_public_ip
}

output "onprem_router_instance_id" {
  value = module.vpn.onprem_router_instance_id
}

output "vpn_connection_id" {
  value = module.vpn.vpn_connection_id
}

output "test_instance_ids" {
  value = {
    hq     = aws_instance.test_hq.id
    branch = aws_instance.test_branch.id
    onprem = aws_instance.test_onprem.id
  }
}

output "test_instance_private_ips" {
  value = {
    hq     = aws_instance.test_hq.private_ip
    branch = aws_instance.test_branch.private_ip
    onprem = aws_instance.test_onprem.private_ip
  }
}
