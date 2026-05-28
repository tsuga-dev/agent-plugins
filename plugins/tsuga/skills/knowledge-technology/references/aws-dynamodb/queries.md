# AWS DynamoDB

Managed NoSQL KV + document store. Provisioned or On-Demand capacity. Healthy: no throttling, bounded read/write latency, no hot-partition skew, GSI in sync.

## Incident shapes

- **Throttling** — `aws_dynamodb_throttled_requests` spikes → capacity-mode limit hit
- **Hot partition / key range** — `aws_dynamodb_read_key_range_throughput_throttle_events` ≠ aggregate throttles → skew onto one partition
- **On-demand scaling lag** — sudden 5-10x burst exceeds adaptive rate; brief throttles during scale
- **Provisioned under-sizing** — `aws_dynamodb_account_provisioned_read_capacity_utilization → 1.0`
- **System errors** — `aws_dynamodb_system_errors > 0` → DynamoDB-side failure (rare)
- **GSI divergence** — GSI throttled while base table fine → GSI reads stale

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `aws_dynamodb_consumed_read_capacity_units` / `aws_dynamodb_consumed_write_capacity_units` | RCU / WCU | Capacity used |
| `aws_dynamodb_provisioned_read_capacity_units` / `WriteCapacityUnits` | RCU / WCU | Ceiling (provisioned) |
| `aws_dynamodb_throttled_requests` | count | Total throttled |
| `aws_dynamodb_read_throttle_events` / `aws_dynamodb_write_throttle_events` | count | Per-op throttling |
| `aws_dynamodb_read_key_range_throughput_throttle_events` | count | Hot-partition signal |
| `aws_dynamodb_write_key_range_throughput_throttle_events` | count | Hot-partition on write |
| `aws_dynamodb_read_provisioned_throughput_throttle_events` | count | Provisioned-mode throttling |
| `aws_dynamodb_read_max_on_demand_throughput_throttle_events` | count | On-demand ceiling throttling |
| `aws_dynamodb_successful_request_latency` (operation) | ms | Per-op latency |
| `aws_dynamodb_system_errors` | count | Provider 5xx |
| `aws_dynamodb_user_errors` | count | 4xx (validation, condition-check-failed) |
| `aws_dynamodb_account_provisioned_read_capacity_utilization` | % | Account utilization |
| `aws_dynamodb_max_provisioned_table_read_capacity_utilization` | % | Hottest table |

## Derived signals

- `aws_dynamodb_throttled_requests / (aws_dynamodb_throttled_requests + Consumed)` — throttle rate. Any sustained = capacity issue.
- `aws_dynamodb_read_key_range_throughput_throttle_events > 0` while account util < 0.8 = hot partition (skew, not saturation).
- p99 / p50 Latency divergence per operation under stable rate = hot keys or GSI pressure.
- GSI `ConsumedWriteCapacity` / base-table write capacity — fan-out projection ratio.

## Log patterns

DynamoDB has no direct logs; SDK-side exceptions:

- `ProvisionedThroughputExceededException` — throttling
- `ThrottlingException` — rate-limit
- `ConditionalCheckFailedException` — optimistic-concurrency conflict (often intentional)
- `ResourceNotFoundException` — table/index missing (config bug)
- `ValidationException` — bad query shape
- `InternalServerError` — provider-side failure
- `TransactionCanceledException: Reason: aws_dynamodb_transaction_conflict` — txn contention

## Gotchas

- Eventually consistent reads = 0.5 RCU; strongly consistent = 1 RCU. `Consumed` aggregates both.
- `aws_dynamodb_throttled_requests = 0` can hide hot-partition throttling on individual keys. Always check `*KeyRangeThroughputThrottleEvents`.
- GSI throttling silently stales reads from GSI while base table is healthy. Your app returns old data with no error.
- Auto-scaling alarms are separate from throttling alarms; auto-scaling lags by minutes. During a burst, throttling is the fast signal.
- DynamoDB Streams / DAX throttling aren't in this metric set; check their own namespaces.
