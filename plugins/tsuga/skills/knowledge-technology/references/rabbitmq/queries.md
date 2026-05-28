# RabbitMQ

AMQP broker with queues, exchanges, bindings. Healthy: publish ≈ deliver, depth bounded, consumer utilisation ≈ 1, low unacked pile-up, disk / FD headroom.

## Incident shapes

- **Queue depth growth** — `message.current` climbs → consumers slower than publishers
- **Consumer stalled** — `consumer.utilisation` → 0 → unacked messages sit
- **Memory alarm** — publishers blocked; check memory + disk counters
- **Disk alarm** — `node.disk.free` near limit → publishers blocked
- **FD exhaustion** — `node.file_descriptors` near limit → accept errors
- **Mirroring / quorum issues** — leader election churn or split-brain

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `rabbitmq.connection.current` | count | Active connections |
| `rabbitmq.channel.current` | count | Several per connection typical |
| `rabbitmq.message.published` | msgs/s | Publish rate |
| `rabbitmq.message.delivered` | msgs/s | Consumer delivery rate |
| `rabbitmq.message.current` | count | In-queue depth |
| `rabbitmq.consumer.count` | count | Registered consumers |
| `rabbitmq.queue.consumer.utilisation` | ratio | Fraction of time consumer busy |
| `rabbitmq.node.message.redelivered` | msgs/s | Rising = consumer instability |
| `rabbitmq.node.disk.free` / `disk.free.limit` | bytes | Ratio → 1 = alarm imminent |
| `rabbitmq.node.file_descriptors` / `file_descriptors.limit` | count | Ratio > 0.9 = accept errors soon |

## Derived signals

- `message.delivered / message.published` — flow ratio. < 1.0 sustained = queue will grow.
- `node.message.redelivered / node.message.delivered` — redelivery rate. > 0.05 = consumer instability.
- `queue.consumer.utilisation` — low with depth growing = idle consumer, likely prefetch misconfig.

## Log patterns

- `memory resource limit alarm set` / `cleared` — memory alarm toggling
- `disk resource limit alarm set` — disk alarm; publishers blocked
- `accepting AMQP connection ... channel_max reached` — connection-level limit
- `Missed heartbeat` — network or client freeze
- `heartbeat_timeout` — consumer heartbeat timeout (often GC pause client-side)
- `Discarding message` — TTL or max-length policy dropping (often intentional)

## Gotchas

- Sampled metrics lag up to a minute; for real-time triage, query the management API directly.
- Memory alarm blocks publishers but doesn't drop existing messages; a fire-and-clear in one minute is pressure, not outage.
- Classic mirrored queues have split-brain risk on partitions. Quorum queues solve it but perform differently.
- `consumer_utilisation = 1.0` is NOT bad. Bad signal is utilisation < 0.5 while depth grows (idle consumer, prefetch misconfig).
- `message.redelivered` includes NACKs, channel drops, and crashes. Rising rate needs client-side attribution.
