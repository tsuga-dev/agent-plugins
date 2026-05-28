# Google Cloud Storage

Object storage. Metrics cover API calls, throughput, stored volume, replication, access. Healthy: low error rate, bounded request latency, RPO met, no unauthorized access shifts.

## Incident shapes

- **API error spike** — `api/request_count{response_code=~"5xx"}` climbs
- **Rate limiting / 429** — `api/request_count{response_code="429"}` rises → hot-partition throttle
- **Egress cost runaway** — `network/sent_bytes_count` spikes → unusual download pattern
- **Replication RPO drift** — `replication/meeting_rpo < 100%` → regional replication lagging
- **Auth anomalies** — `authn/authentication_count` pattern shift → credential rotation / IAM change

## Key metrics

Prefixed `storage.googleapis.com/`:

| Metric | Unit | Signal |
|---|---|---|
| `api/request_count` | count | API calls by method, response_code |
| `network/sent_bytes_count` | bytes | Egress |
| `network/received_bytes_count` | bytes | Ingress |
| `storage/total_bytes` | bytes | Bucket footprint |
| `storage/object_count` | count | Number of objects |
| `storage/total_byte_seconds` | byte-seconds | Storage billing unit |
| `replication/meeting_rpo` | % | Percent of objects meeting RPO |
| `replication/turbo_max_delay` | s | Turbo replication max delay |
| `replication/missing_rpo_minutes_last_30d` | minutes | Accumulated RPO-miss |
| `authn/authentication_count` | count | Auth attempts |
| `authz/acl_operations_count` | count | ACL operations |
| `authz/acl_based_object_access_count` | count | ACL-governed accesses |
| `autoclass/transition_operation_count` | count | Autoclass tier transitions |
| `autoclass/transitioned_bytes_count` | bytes | Data transitioned |
| `anywhere_cache/request_count` | count | Anywhere cache requests |

## Derived signals

- `request_count{5xx} / request_count` — error rate. Baseline < 0.01.
- `request_count{429} / request_count` — throttle rate. Any sustained positive = hot partition.
- Derivative of `network/sent_bytes_count` — egress trend. Spike = investigation target.
- Derivative of `storage/total_bytes` — growth rate. Rapid growth with stable usage = orphaned writes / versions.

## Log patterns

GCS Data Access audit logs (must be enabled):

- `storage.googleapis.com/GetObject` / `PutObject` / `DeleteObject` — per-op events
- `protoPayload.status.code=7` — PERMISSION_DENIED
- `protoPayload.status.code=13` — INTERNAL
- `protoPayload.status.code=8` — RESOURCE_EXHAUSTED (rate limit / quota)
- `principalEmail` + `callerIp` — who and where
- ListObjects spike from a new principal = cost-runaway or enumeration signal

## Gotchas

- Metric collection lag 1-5 min; sub-minute events don't show.
- `api/request_count` excludes frontend-rejected requests (DDoS protection). Totals can undercount real traffic.
- Rate limiting is per-object / per-prefix. Hot key throttles one pattern while bucket looks fine. Audit logs show per-op detail.
- Object versioning isn't visible in `object_count`; versioned buckets can have many hidden historical versions driving storage cost.
- Autoclass can move objects to colder tiers; retrieval from Coldline/Archive is minutes, not seconds. Latency spike on a mature bucket = autoclass.
- Uniform bucket-level access and object ACLs interact unpredictably; `acl_based_object_access_count > 0` on uniform-access = misconfiguration.
