# AWS Lambda

Serverless compute, billed per-invocation + duration. Healthy: low error rate, duration within SLO, low throttle rate, concurrency under limits.

## Incident shapes

- **Error spike** — `aws_lambda_errors / aws_lambda_invocations` rises → code defect, deploy regression, or dependency failure
- **Throttling** — `aws_lambda_throttles` nonzero → reserved concurrency too low or account ceiling hit
- **aws_lambda_duration regression** — p95 `aws_lambda_duration` doubles → dependency slow, cold-start surge, or algorithmic regression
- **Async queue growth** — `aws_lambda_async_event_age` climbs → async invocations backing up
- **Stream consumer lag** — `aws_lambda_iterator_age` / `aws_lambda_offset_lag` climb on Kinesis / DDB-streams / MSK triggers
- **Dead-letter drop** — `aws_lambda_dead_letter_errors > 0` → retries exhausted, messages lost

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `aws_lambda_invocations` | count | Baseline rate |
| `aws_lambda_errors` | count | Handler errors |
| `aws_lambda_throttles` | count | Any nonzero = concurrency-ceiling hit |
| `aws_lambda_duration` | ms | Use p50/p95/p99, not avg |
| `aws_lambda_concurrent_executions` | count | Peak concurrency |
| `aws_lambda_claimed_account_concurrency` | count | Account-level ceiling usage |
| `aws_lambda_async_event_age` | ms | Oldest pending async event |
| `aws_lambda_async_events_dropped` | count | Nonzero = async retry exhaustion, lost |
| `aws_lambda_dead_letter_errors` | count | DLQ delivery failure |
| `aws_lambda_destination_delivery_failures` | count | Destination-config failure |
| `aws_lambda_iterator_age` | ms | Kinesis/DDB stream-trigger lag |
| `aws_lambda_offset_lag` | records | Kafka/MSK trigger lag |
| `aws_lambda_oversized_record_count` | count | Records exceeding batch-size limit (dropped) |
| `aws_lambda_provisioned_concurrency_utilization` | % | Pre-warmed pool usage |
| `aws_lambda_provisioned_concurrency_spillover_invocations` | count | Spilled to on-demand; cold-start hit |

## Derived signals

- `aws_lambda_errors / aws_lambda_invocations` — error rate. Baseline < 0.01.
- `aws_lambda_throttles / (aws_lambda_invocations + aws_lambda_throttles)` — throttle rate. Any sustained = capacity.
- `p95 aws_lambda_duration / function timeout` — saturation. > 0.8 = timeout regression risk.
- `ReservedConcurrency - max(aws_lambda_concurrent_executions)` — headroom. < 5 sustained = imminent throttle.

## Log patterns

- `Task timed out after N seconds` — timeout hit
- `Process exited before completing request` — unhandled crash / OOM
- `REPORT RequestId: ... aws_lambda_duration: X Max Memory Used: Y MB` — invocation report
- `Unable to import module` / `Runtime.ImportModuleError` — bad deploy
- `Rate Exceeded` — account throttle
- `connect ETIMEDOUT` — downstream timeout
- `Init aws_lambda_duration: X ms` — cold start marker

## Gotchas

- `aws_lambda_duration` is billable; use p95/p99. Average hides long-tail users feel.
- Metrics are 1-minute granular. 30-second outages may not record.
- `aws_lambda_concurrent_executions` is max-over-minute; sub-minute spikes that throttled can be invisible.
- `aws_lambda_errors` excludes throttles (counted separately).
- Stream-trigger functions that throttle accumulate `aws_lambda_iterator_age` / `aws_lambda_offset_lag` without raising `aws_lambda_errors`.
- `aws_lambda_async_events_dropped` = messages gone unless DLQ/destination configured.
