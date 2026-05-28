# AWS SQS

Managed message queue. Healthy: bounded message age, consume ≈ send rate, no empty-receive storms, no in-flight backlog.

## Incident shapes

- **Consumer lag** — `aws_sqs_approximate_age_of_oldest_message` grows with visible messages → consumer slower than producer
- **Consumer crash / stuck** — visible climbs, delivered → 0
- **Poison message** — one message repeatedly received and not deleted → in-flight elevated
- **Producer burst / overload** — sends spike, age climbs
- **Empty-receive storm** — `aws_sqs_number_of_empty_receives` dominates → short-polling misconfig

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `aws_sqs_approximate_age_of_oldest_message` | seconds | User-visible lag |
| `aws_sqs_approximate_number_of_messages_visible` | count | Backlog depth |
| `aws_sqs_approximate_number_of_messages_not_visible` | count | In-flight; high sustained = consumers hanging |
| `aws_sqs_approximate_number_of_messages_delayed` | count | Delay-timer held |
| `aws_sqs_number_of_messages_sent` | count/min | Producer rate |
| `aws_sqs_number_of_messages_received` | count/min | Consumer poll results |
| `aws_sqs_number_of_messages_deleted` | count/min | Successful processing |
| `aws_sqs_number_of_empty_receives` | count/min | High = short-polling misconfig |
| `aws_sqs_sent_message_size` | bytes | Spikes can hit 256KB limit |
| `aws_sqs_approximate_number_of_groups_with_inflight_messages` | count | FIFO: groups in process |

## Derived signals

- First-derivative of visible messages — backlog trajectory. Positive sustained = bottleneck.
- `Deleted / Sent` — process ratio. < 1.0 = consumers behind.
- `NotVisible / (Visible + NotVisible)` — in-flight utilization. High + low delete rate = consumers stuck.
- `EmptyReceives / Received` — > 0.5 sustained = polling inefficiency.

## Log patterns

SQS has no logs; use consumer-side application logs:

- `Timeout on receiving message` — broker / network issue
- `VisibilityTimeout expired` — consumer too slow; message re-delivered
- `MessageNotInflightException` — double-delete attempt
- `ReceiptHandleIsInvalid` — handle expired
- `Message Group X has no available messages` — FIFO group head blocked

## Gotchas

- "Approximate" metrics lag up to ~5 minutes under load; short incidents are invisible.
- DLQ forms silently. Always check DLQ `MessagesVisible` separately.
- `aws_sqs_number_of_empty_receives` high with `ReceiveMessageWaitTimeSeconds=0` (short polling) → cost driver.
- FIFO queue lag is per-message-group. A single blocked group stalls many consumers without showing in aggregate.
- Visibility-timeout expiry inflates `Received` without inflating `Deleted`. Don't treat received as "processed."
