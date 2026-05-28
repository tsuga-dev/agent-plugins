# Google Cloud Pub/Sub

Managed pub/sub. Healthy: ack ≈ publish, bounded oldest-unacked-age, no undelivered backlog.

## Incident shapes

- **Subscription backlog growth** — `num_undelivered_messages` climbs → consumer slower than producer
- **Oldest-unacked-age rising linearly** — consumer stuck (sawtooth is normal processing lag)
- **Consumer stall** — `ack_message_count` drops, `sent_message_count` flat → consumer alive but not acking
- **Push-subscription failures** — push endpoint returning non-200 → undelivered climbs
- **Publish latency / throttling** — `send_request_latencies` p99 spikes → quota pressure
- **Retention runway** — `backlog_bytes` growing near retention limit → data-loss risk

## Key metrics

Prefixed `pubsub.googleapis.com/`:

| Metric | Unit | Signal |
|---|---|---|
| `topic/send_message_operation_count` | count | Publishes |
| `topic/send_request_latencies` | ms | Publish latency |
| `topic/message_sizes` | bytes | Message size distribution |
| `topic/oldest_unacked_message_age_by_region` | s | Topic-level backlog age |
| `subscription/sent_message_count` | count | Delivered to subscribers |
| `subscription/ack_message_count` | count | Acks received |
| `subscription/pull_request_count` | count | Pull calls |
| `subscription/streaming_pull_response_count` | count | Streaming pull |
| `subscription/num_undelivered_messages` | count | Backlog size |
| `subscription/oldest_unacked_message_age` | s | Oldest pending-ack age |
| `subscription/backlog_bytes` | bytes | Backlog volume |

## Derived signals

- `ack_message_count / sent_message_count` — processing ratio. < 1.0 sustained = consumer stuck.
- First-derivative of `num_undelivered_messages` — backlog trajectory.
- `retention_duration_seconds - oldest_unacked_message_age` — retention runway until message loss.

## Log patterns

Consumer-side + GCP audit logs:

- `DEADLINE_EXCEEDED` — ack deadline too short or consumer slow
- `RESOURCE_EXHAUSTED` — subscription throughput or quota hit
- `INVALID_ARGUMENT` — malformed ack ID; message redelivered
- `PERMISSION_DENIED` — IAM misconfig
- Audit log: `google.pubsub.v1.Publisher.Publish` — producer activity

## Gotchas

- Pulled-not-acked messages are redelivered after ack deadline (default 10s). Long processing must extend via `modifyAckDeadline`.
- `num_undelivered_messages` excludes leased-not-acked. True backlog = undelivered + in-flight.
- Retention defaults 7d (max 31d). Approaching without acking = data loss.
- Ordering keys serialize delivery per key; one slow key stalls its entire stream without affecting aggregates.
- Push subscriptions: HTTP 200 from endpoint acks the message even if the endpoint had side-effect errors internally.
- Dead-letter topic is per-subscription and opt-in. Subs without DLT can drop messages after max-delivery-attempts.
