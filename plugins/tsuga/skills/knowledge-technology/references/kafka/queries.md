# Kafka

Distributed log. Producers append to partitions, consumers read by offset. Healthy: consumer lag bounded, consume ≈ produce rate, low rebalance churn, zero under-replicated / offline partitions.

## Incident shapes

- **Consumer lag growth** — consume rate drops, produce flat → check per-partition lag
- **Rebalance churn** — frequent rebalances halve throughput → check rebalance_rate
- **Broker / partition regression** — under-replicated or offline partitions → check partition health
- **Poison message / stuck partition** — one partition stuck at one offset → drill per-partition lag

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `kafka.consumer.lag` | records | Per-partition delay. Primary user-visible signal |
| `kafka.consumer.records_consumed_rate` | rec/s | Falling while produce flat = consumer issue |
| `kafka.producer.record_send_rate` | rec/s | Produce baseline |
| `kafka.partition.under_replicated` | count | Any nonzero = replication risk |
| `kafka.partition.offline` | count | Any nonzero = availability incident |
| `kafka.controller.active_count` | count | Should be 1; churn = instability |
| `kafka.consumer.rebalance_rate` | events/s | Frequent rebalances = coordination problem |
| `kafka.consumer.commit_latency` | ms | Commit spikes = replay/duplicate risk |
| `kafka.consumer.fetch.latency` | ms | Poll latency |
| `kafka.request.failure_rate` | fail/s | Broker request failures |
| `kafka.request.throttle_rate` | 1/s | Sustained throttle = contention or quota |
| `kafka.broker.disk_usage` | bytes | Disk fill → writes throttle |
| `kafka.log.flush_time` | ms | Flush spikes precede request-latency climbs |

## Derived signals

- First-derivative of `consumer.lag` — lag trajectory. Positive sustained = backlog growing.
- `records_consumed_rate / record_send_rate` — consume-vs-produce ratio. Healthy ≈ 1.0.
- `partition.under_replicated + partition.offline` — partition risk. Any nonzero = active incident.
- Rebalances-per-hour / group-members — churn ratio. > 1 = pathological rebalancing.

## Log patterns

- `Shrinking ISR for partition` — replica falling behind
- `Partition [X-N] is under min ISR` — replication risk
- `Controller moved to another broker` — controller churn
- `Group [X] is rebalancing` / `Preparing to rebalance` — rebalance start
- `Marking the coordinator dead` — coordinator connection failure
- `Offset commit failed` — commit-latency / leadership change
- `Attempt to join group failed due to fatal error` — auth / ACL
- `Failed to send record` with back-offs — producer can't reach leader

## Gotchas

- Aggregate consumer lag hides stuck partitions. Drill per-partition before concluding "consumer is keeping up."
- Lag in records ≠ lag in time. 10k records at 1 msg/s is much worse than 100k at 100k msg/s. Compute time-to-catch-up.
- A queue "clearing" can be retention dropping records (data loss), not consumers catching up.
- `under_replicated = 0` at investigation time doesn't mean the incident didn't involve replication — check the timeseries.
- Producer retries mask broker degradation: steady produce rate + rising broker failures = silent degradation.
