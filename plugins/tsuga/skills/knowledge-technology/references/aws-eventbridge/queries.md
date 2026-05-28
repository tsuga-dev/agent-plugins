# AWS EventBridge

Event bus. Events → matched rules → invoked targets. Healthy: events matched and invoked with low failure, bounded latency.

## Incident shapes

- **Failed invocations** — target sick, IAM wrong, or target-side throttling
- **Invocation latency** — `aws_events_ingestion_to_invocation_complete_latency` p95 climbs
- **No matches** — `aws_events_matched_events` drops to zero on a previously busy rule → upstream stopped OR rule drifted
- **Rule-config drift** — `aws_events_triggered_rules` changes without a deploy → check audit trail
- **Account throttling** — PutEvents throttled; producers retry, effective rate drops

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `aws_events_matched_events` | count | Events matching at least one rule |
| `aws_events_triggered_rules` | count | Rule fires |
| `aws_events_invocations_created` | count | Target invocations queued |
| `aws_events_invocation_attempts` | count | Tries including retries |
| `aws_events_successful_invocation_attempts` | count | Successes |
| `aws_events_failed_invocations` | count | Terminal failures |
| `aws_events_ingestion_to_invocation_start_latency` | ms | Ingest → first attempt |
| `aws_events_ingestion_to_invocation_complete_latency` | ms | Ingest → success |

## Derived signals

- `aws_events_successful_invocation_attempts / aws_events_invocation_attempts` — success rate. Baseline > 0.99.
- `(aws_events_invocation_attempts - aws_events_invocations_created) / aws_events_invocations_created` — retry rate. High = target rejecting.
- `aws_events_triggered_rules / aws_events_matched_events` — fan-out ratio. Sudden shift = rule config changed.

## Log patterns

- CloudTrail `PutRule` / `PutTargets` / `DeleteRule` / `DisableRule` — config changes
- Target Lambda: `Task timed out` — invocation timed out target-side
- Target SQS DLQ depth growing = terminal failures
- Schema registry errors on PutEvents — schema enforcement (if enabled)
- `ValidationException` on PutEvents — malformed event JSON

## Gotchas

- Not exactly-once: targets can be invoked multiple times. Targets must be idempotent.
- `aws_events_failed_invocations` increments only after retries exhausted. Flaky targets show as elevated `aws_events_invocation_attempts` before failures appear.
- Rule patterns: AND within a field, OR within `anything_but`. Subtle changes can silently match zero events.
- Archive-and-replay can inflate `aws_events_matched_events` without real traffic change.
- Cross-region / cross-account (global endpoints) has separate throttling.
