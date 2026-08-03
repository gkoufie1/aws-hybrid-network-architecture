# Postmortem: getting the tunnel to actually pass traffic

`terraform apply` succeeding is not the same claim as "the network works."
This project's Terraform ran clean on the very first attempt — 42 resources
created, zero errors — and the VPN tunnel showed `STATE_MAIN_I4 (IKE SA
established)` a few minutes later. By every infrastructure-as-code metric,
it was done.

It didn't pass a single packet. Getting from "IKE SA established" to an
actual `ping` and `curl` succeeding end-to-end took finding and fixing 8
real, separate issues — none of them visible from reading the Terraform or
the shell script in isolation.

| # | Bug | Symptom | Fix |
|---|---|---|---|
| 1 | `strongswan` package doesn't exist on Amazon Linux 2023 | `dnf install -y strongswan` → "Unable to find a match" | Switched to Libreswan — which is what AWS's own official customer-gateway sample configs use for Amazon Linux, for exactly this reason |
| 2 | `nat_traversal` / `oe` are removed config options in this Libreswan version | `ipsec.conf:3: syntax error [nat_traversal]` — the daemon refused to start at all | Deleted both; NAT-T is auto-detected in modern Libreswan, no config needed |
| 3 | Libreswan attempts IKEv2 by default; AWS's static-route tunnels expect IKEv1 | Connection loaded but `ipsec auto --up` reported "no connection named" — a misleading error for what was actually a version mismatch | Added `ikev2=no` |
| 4 | This Libreswan build doesn't support the `modp1024` DH group | Buried in `journalctl`, not in `ipsec status`: `"tunnel1": failed to add connection: IKE DH algorithm 'modp1024' is not supported` | Switched to `modp2048` — supported, and stronger anyway |
| 5 | `aws_vpn_connection_route` only works for the older VGW-attached VPN style | `InvalidVpnConnection.InvalidType: Static routes ... must be added through the Transit Gateway API` | Used `aws_ec2_transit_gateway_route` instead, in the root module where both the TGW and VPN outputs are available |
| 6 | Private-subnet test instances have no internet egress at all (by design — no NAT gateway) | SSM couldn't reach them: `describe-instance-information` returned an empty list, `send-command` failed with "Instances not in a valid state" | Added VPC Interface Endpoints (PrivateLink) for `ssm`, `ssmmessages`, `ec2messages` in all three VPCs — the standard enterprise pattern for managing instances with no internet path |
| 7 | The router's security group had no ingress rule for traffic *arriving decrypted through the tunnel* | Tunnel showed a healthy IKE/ESP SA; `tcpdump` on the router showed the decrypted ping requests arriving correctly on `ens5` — but they went nowhere | Added an ingress rule from the AWS-side CIDR aggregate; the existing rules only covered the outer IPsec ports and the on-prem-subnet-to-router direction |
| 8 | The Amazon Linux 2023 AMI ships with Docker's iptables rules pre-installed, which set the `FORWARD` chain's default policy to `DROP` | The most misleading one: `xfrm_stat` showed zero decryption errors, the packet visibly arrived on the router's interface via `tcpdump` — and still never reached the destination. `iptables -L FORWARD` showed `policy DROP`, with packets already counted against it | Added explicit `ACCEPT` rules for the tunnel traffic in both directions |

## How each was actually found

Every one of these required a different diagnostic technique — none were
visible from `terraform plan`, `terraform apply` output, or reading the
code:

- **#1–#4** surfaced from `journalctl -u ipsec`, not from `ipsec status` —
  the daemon's own log had the real error; the status command just said
  "not running" or "no connection."
- **#5** surfaced from actually running `terraform apply` and reading the
  AWS API's rejection message.
- **#6** surfaced from `aws ssm describe-instance-information` returning an
  empty list where 4 instances were expected.
- **#7 and #8** required `tcpdump` running *simultaneously* on both the
  router and the destination instance during a live `ping`, to see exactly
  where in the path the packet stopped being visible. CloudWatch's
  `TunnelDataOut` metric — which stayed flat except for AWS's own periodic
  keepalives — was the first clue that the problem was downstream of the
  tunnel itself, not the tunnel.

## What "verified" actually means here

This wasn't fixed once and left running. After all 8 fixes:

1. Full `terraform destroy` — 54 resources, clean.
2. Fresh `terraform apply` from the corrected code, from empty state — 54
   resources, clean, zero manual intervention.
3. The moment the VPN telemetry showed `Status: UP` (entirely from
   `user_data`, no live patching), a `ping` and `curl` from both spoke VPCs
   to the on-prem simulation succeeded with 0% packet loss on the first try.

That sequence — destroy, reapply from git, verify cold — is what actually
distinguishes "I fixed it on the running instance" from "the code in this
repository works." Only the second claim is backed by evidence here.

## Takeaway

`terraform apply` finishing without error, and even the VPN tunnel's IKE
SA reporting "established," were both necessary but nowhere near sufficient
conditions for "this network works." The gap between those two claims was
8 distinct bugs deep, spanning package availability, protocol version
negotiation, cryptographic algorithm support, an AWS API quirk specific to
Transit-Gateway-attached VPNs, a networking blind spot (private subnets
with no path to SSM), and a security-group/iptables interaction that
looked, at every layer above the packet capture, like it should have
worked.
