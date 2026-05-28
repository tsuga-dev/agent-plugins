# AWS Kinesis Data Firehose

Managed streaming delivery: producers → buffer → transform → destination (S3 / Redshift / OpenSearch / HTTP / Splunk). Healthy: incoming within limits, no throttling, bounded freshness, no KMS / destination errors.

## Incident shapes

- **Throttling** — `ThrottledRecords` nonzero → `MISSING` / `IncomingRecords` quota hit
- **Delivery lag** — `DeliveryTo*.DataFreshness` climbs → data in Firehose but not delivered
- **Destination errors** — `MISSING < 1.0` → buffer grows, eventually backup / DLQ
- **Transform failures** — `MISSING < 1.0` → Lambda transform sick
- **KMS errors** — access_denied / disabled / invalid_state / not_found → key rotation
- **Validation failures** — `aws_firehose_failed_validation_records` → schema rejects

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `aws_firehose_incoming_records` | count | Inbound rate |
| `MISSING` | bytes | Volume vs `MISSING` |
| `aws_firehose_throttled_records` | count | Throttling |
| `MISSING` / `MISSING` | limit | Current ceilings |
| `MISSING` | seconds | Oldest undelivered age |
| `MISSING` | ratio | Successful batch fraction |
| `MISSING` / `Records` | count | Delivered volume |
| `MISSING` | ms | Transform Lambda duration |
| `MISSING` | ratio | Transform success |
| `aws_firehose_kms_key_*` | count | KMS error counters |
| `aws_firehose_failed_validation_records` | count | Schema rejects |
| `aws_firehose_put_record_batch_latency` | ms | Producer API latency |

## Derived signals

- `throttled_records / (incoming_records + throttled_records)` — throttle rate. Any sustained positive = capacity issue.
- `DataFreshness` — linear growth = delivery stuck; sawtooth = normal buffer-flush cycles.
- `MISSING` — drop = transform broken.
- `MISSING / MISSING` — quota headroom. > 0.8 sustained = request increase.

## Log patterns

Firehose error CloudWatch log group:

- `KMS key ... is in invalid state` — rotation issue
- `AccessDenied` — role lacks destination permissions
- `Invalid data format` — doesn't match destination format
- `Connection refused` / `reset` — HTTP endpoint unreachable
- `HTTP 4xx` / `5xx` on HTTP endpoint
- `ProcessingFailed` — transform Lambda errored
- Backup-to-S3 entries — delivery failed, records in backup bucket

## Gotchas

- Firehose buffers before delivery (size or time). Low freshness = "would be delivered at next flush," not "delivered now."
- Destination failures don't produce producer errors immediately; internal retry loop (default 24h) before backup.
- Transform Lambda can return `Dropped` status intentionally — looks like loss but is by design.
- Dynamic partition keys can create millions of small S3 objects; healthy in Firehose metrics but blows up downstream.
- Quotas are region + account level; multiple streams share.
