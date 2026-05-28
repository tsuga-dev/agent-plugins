# AWS PrivateLink / VPC Endpoints

Private network path from VPC to AWS or partner services without public internet. Typically VPC Interface Endpoint (ENI) fronted by an NLB. Healthy: stable active connections, no drops, healthy backing NLB.

## Incident shapes

- **Backing NLB unhealthy** — `aws_networkelb_un_healthy_host_count > 0` → provider fleet sick
- **Packet drops** — `aws_privatelinkendpoints_packets_dropped` climbs (rare; capacity or IP conflict)
- **Reset packets** — `aws_privatelinkendpoints_rst_packets_received` climbs from either side closing abruptly
- **Connection churn** — `aws_privatelinkendpoints_new_connections` ≫ `aws_privatelinkendpoints_active_connections` → no connection reuse
- **Cost runaway** — `aws_privatelinkendpoints_bytes_processed` spike (cross-AZ PrivateLink is billed)

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `aws_privatelinkendpoints_active_connections` | count | Established through endpoint |
| `aws_privatelinkendpoints_new_connections` | count | New-connection rate |
| `aws_privatelinkendpoints_bytes_processed` | bytes | Volume |
| `aws_privatelinkendpoints_packets_dropped` | count | Drops |
| `aws_privatelinkendpoints_rst_packets_received` | count | RST from either side |
| `aws_privatelinkservices_endpoints_count` | count | Active endpoints on service |
| `aws_networkelb_healthy_host_count` | count | Provider healthy |
| `aws_networkelb_un_healthy_host_count` | count | Provider unhealthy |
| `Unknown` | count | Provider target connection errors |
| `aws_networkelb_processed_bytes` | bytes | Provider throughput |

## Derived signals

- `aws_privatelinkendpoints_bytes_processed / aws_privatelinkendpoints_new_connections` — connection reuse; low = new connection per request.
- `aws_networkelb_healthy_host_count / (Healthy + Unhealthy)` — provider health ratio.
- `aws_privatelinkendpoints_rst_packets_received / aws_privatelinkendpoints_active_connections` — reset rate. Any sustained = instability.

## Log patterns

PrivateLink has no logs. Use VPC flow logs + provider-service logs:

- Flow logs with `REJECT` on endpoint ENIs
- App: `connect() failed` / `connection refused` / `reset by peer` against endpoint DNS
- App: DNS resolution failures for `*.<service>.<region>.vpce.amazonaws.com`

## Gotchas

- Consumer resolves endpoint via private DNS (`vpce-xxxxx....vpce.amazonaws.com`). Resolving the public service endpoint bypasses PrivateLink entirely — endpoint metrics appear empty.
- Endpoint policies (IAM-like JSON) can silently deny calls. Looks like IAM errors but originates at the endpoint.
- Cross-AZ traffic via PrivateLink: data processing + inter-AZ charges both apply.
- Provider NLB health is only visible to the provider; consumer sees connection-level errors only.
- Some older HTTP clients treat RSTs as fatal and retry aggressively — can amplify incidents.
