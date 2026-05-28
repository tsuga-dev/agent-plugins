# AWS ELB (NLB / ALB / GLB / CLB)

NLB = L4, ALB = L7, GLB = GENEVE, CLB = legacy. Metric names below skew NLB. ALB has its own (`HTTPCode_Target_2XX_Count`, `TargetResponseTime`, etc.) but reasoning is the same.

## Incident shapes

- **Target fleet unhealthy** — `aws_networkelb_un_healthy_host_count > 0` → backend problem, not LB
- **Flow rejections** — `aws_networkelb_rejected_flow_count` spikes → per-LB connection limits or AZ capacity
- **TLS handshake failures** — `aws_networkelb_client_tls_negotiation_error_count` climbs → cert / SNI / TLS-version mismatch
- **TCP resets** — target / ELB / client reset counts spike → abrupt close
- **Zonal imbalance** — `aws_networkelb_zonal_health_status = 0` on one AZ → traffic shifts, overloads peers
- **LCU ceiling** — `aws_networkelb_consumed_lc_us` climbs → cost spike, potential throttling

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `aws_networkelb_active_flow_count` | flows | Concurrent connections |
| `aws_networkelb_new_flow_count` | flows/min | New-connection rate |
| `aws_networkelb_processed_bytes` | bytes | Traffic volume |
| `aws_networkelb_healthy_host_count` | count | Per-target-group healthy |
| `aws_networkelb_un_healthy_host_count` | count | Per-target-group unhealthy |
| `aws_networkelb_rejected_flow_count` | count | Connection rejections |
| `aws_networkelb_unhealthy_routing_flow_count` | count | Flows to unhealthy target (AZ failover) |
| `aws_networkelb_tcp_elb_reset_count` | count | LB-initiated resets |
| `aws_networkelb_tcp_target_reset_count` | count | Target-initiated resets |
| `aws_networkelb_tcp_client_reset_count` | count | Client-initiated resets |
| `aws_networkelb_client_tls_negotiation_error_count` | count | TLS handshake failures |
| `SecurityGroupBlockedFlowCount_*` | count | SG denies |
| `aws_networkelb_port_allocation_error_count` | count | NLB source-NAT port exhaustion |
| `aws_networkelb_zonal_health_status` | 0/1 | Per-AZ health |
| `aws_networkelb_consumed_lc_us` | units | Cost / sizing |

## Derived signals

- `aws_networkelb_healthy_host_count / (aws_networkelb_healthy_host_count + aws_networkelb_un_healthy_host_count)` — fleet health. < 1 = partial outage.
- `(ELB + Target + Client resets) / aws_networkelb_new_flow_count` — reset ratio. Spike = instability.
- `aws_networkelb_rejected_flow_count / (aws_networkelb_new_flow_count + aws_networkelb_rejected_flow_count)` — rejection rate. Any sustained = capacity or SG problem.
- Per-AZ `aws_networkelb_new_flow_count` skew > 2× with other AZs `aws_networkelb_zonal_health_status=1` = client routing issue.

## Log patterns

ALB access logs (S3-delivered):

- `request_processing_time=-1` — connection failure to target
- `target_processing_time=-1` — target didn't respond
- `elb_status_code=504` — gateway timeout
- `elb_status_code=502` — bad gateway (malformed backend response)
- `elb_status_code=503` — service unavailable (often health-check failure)
- `target_status_code="-"` — no target response received

## Gotchas

- `aws_networkelb_un_healthy_host_count` lags real health by one or two health-check intervals (~30s). Brief outages may not show.
- `aws_networkelb_rejected_flow_count` can be zero during overload if rejections happen at target (target returns 503).
- NLB `aws_networkelb_port_allocation_error_count` = source-NAT exhaustion on ENI; add subnets or switch to client-IP preservation.
- ALB 5xx with no target-metric correlation = LB couldn't reach target (DNS, routing, SG). Check `aws_networkelb_healthy_host_count` at that timestamp.
