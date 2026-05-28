# AWS NAT Gateway

Managed NAT for private-subnet egress. Healthy: traffic flows both ways, no drops, no port-allocation errors, active connections under 55k per (dest IP, dest port).

## Incident shapes

- **Port allocation exhaustion** — `aws_natgateway_error_port_allocation > 0` → many connections to same (dest IP, dest port) tuple exhaust ephemeral ports
- **Packet drops** — `aws_natgateway_packets_drop_count` climbs → malformed, SG denies, or NAT degraded
- **Connection-rate cap** — active connections near 55k per destination → new connections fail
- **Idle timeout storms** — `aws_natgateway_idle_timeout_count` spikes → long-lived connections without keepalives
- **Bandwidth ceiling** — peak-bandwidth saturates → throughput capped
- **Asymmetric traffic** — in/out byte mismatch → one-way connectivity failure

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `aws_natgateway_active_connection_count` | count | Current connections |
| `aws_natgateway_connection_attempt_count` | count | New-connection attempts |
| `aws_natgateway_connection_established_count` | count | Established |
| `aws_natgateway_error_port_allocation` | count | Any > 0 = incident |
| `aws_natgateway_packets_drop_count` | count | Drops |
| `aws_natgateway_idle_timeout_count` | count | Idle-timed-out connections (default 350s) |
| `aws_natgateway_bytes_in_from_source` / `aws_natgateway_bytes_out_to_source` | bytes | VPC ↔ internet direction |
| `aws_natgateway_bytes_in_from_destination` / `aws_natgateway_bytes_out_to_destination` | bytes | Return direction |
| `aws_natgateway_packets_in_from_source` / `aws_natgateway_packets_out_to_source` | packets | Same, packets |
| `aws_natgateway_peak_bytes_per_second` / `aws_natgateway_peak_packets_per_second` | max | Sub-interval peaks |

## Derived signals

- `aws_natgateway_connection_established_count / aws_natgateway_connection_attempt_count` — success rate. < 0.99 sustained = outbound connectivity problem (DNS, SG, remote host).
- `aws_natgateway_packets_drop_count / (aws_natgateway_packets_in_from_source + aws_natgateway_packets_in_from_destination)` — drop rate. Any sustained positive = issue.
- `aws_natgateway_bytes_in_from_source / aws_natgateway_bytes_out_to_source` — asymmetry. Extremes either way = one-way failure.

## Log patterns

NAT GW has no logs. Use VPC flow logs + app logs:

- Flow logs with `REJECT` action on NAT GW ENI
- App: `connect() failed: Cannot assign requested address` — ephemeral-port exhaustion (consumer side)
- App: `connection timed out` — egress failure
- App: `DNS resolution failed` — VPC DNS or upstream resolver issue

## Gotchas

- Port-allocation is per (dest IP, dest port). Many consumers to the same upstream on the same port hit 55k fast. Mitigate: more NAT GWs, VPC endpoints (skip NAT), or HTTP/2 reuse upstream.
- `aws_natgateway_idle_timeout_count` on long-lived connections (DB, gRPC) can cause silent failures if client doesn't send keepalives within 350s.
- NAT GW doesn't log drop causes. Distinguish SG / NACL / NAT-internal via flow logs.
- 100 Gbps peak per NAT GW; consistent near-peak = scale horizontally.
- Cross-AZ NAT traffic charges twice. Cost spikes can reveal misconfigured routing tables.
