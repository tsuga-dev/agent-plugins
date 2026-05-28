# AWS EventBridge Integration Context Bundle

## Metadata
**Technology:** AWS EventBridge
**Deployment:** managed
**Environment:** prod
**Persona:** SRE Dev and ops
**Telemetry preference:** mixed
**Integration scope:** core service only
**Primary use-case:** reliability and performance

## How to use this bundle
- Use `01_aws-eventbridge_metrics.csv` as the source of truth for metric names, units, safe aggregations, and expected Tsuga mappings.
- Use `02_aws-eventbridge_dashboard_plan.yaml` as the implementation blueprint for sections, widgets, derived signals, note copy, triage chains, and playbooks.
- Use `03_aws-eventbridge_state.yaml` for machine-readable state, assumptions, log intelligence status, and unresolved unknowns.
- Use `04_aws-eventbridge_memory.md` for the readable Stage 1 handoff narrative and Stage 2 priority checks.
- Stage 2 will create `05_aws-eventbridge_metric_catalog.csv` for discovered metric inventory, attribute-key reconciliation, and description curation.
- Stage 4 should read this file's `Log intelligence (Stage 4 handoff)` section and `03_aws-eventbridge_state.yaml` `log_intel` block before authoring any log route payloads.

## What it is and what "good" looks like

### Confirmed by sources
- EventBridge is AWS's serverless event router. It receives events from AWS services, SaaS partners, and custom applications, matches them against rules on an event bus, and invokes one or more targets. [S1][S2]
- AWS exposes `AWS/Events` CloudWatch metrics for the rule-matching and target-invocation path, including `MatchedEvents`, `TriggeredRules`, `InvocationsCreated`, `InvocationAttempts`, `SuccessfulInvocationAttempts`, `Invocations`, `FailedInvocations`, and ingestion-to-invocation latency metrics. [S1]
- AWS guidance for EventBridge operations is to watch invocation failures, retry behavior, dead-letter-queue flow, and throttle limits because EventBridge can retry for up to 24 hours and up to 185 times before giving up. [S2][S7][S8]
- "Good" for EventBridge is not host health. Good means expected events are being matched, the intended number of targets are being invoked, failures are rare, retries are low, and end-to-end delivery latency stays close to baseline. [S1][S2]
- The current Tsuga namespace spot check found 10 live `aws_events_*` metrics, which is a compact surface. That makes a single dashboard more appropriate than separate overview and deep-dive dashboards for this integration. [Tsuga preflight]

### Best-practice inference
- Incident shape 1: **routing looks normal but delivery fails**. `Matched Events` and `Triggered Rules` stay flat while `Permanent Failure Rate (%)` rises. Start in `delivery-reliability`.
- Incident shape 2: **fanout explosion**. `Average Invocations Per Matched Event` jumps while `Successful Attempt Rate (%)` falls or latencies climb. Start in `fanout-capacity`.
- Incident shape 3: **managed service delay without obvious hard failure**. `Matched Events` and `Successful Invocation Attempts` keep moving, but ingestion-to-success latency widens. Start in `latency-path`.
- Dashboard success criteria: one surface should show whether events are getting matched, whether targets are keeping up, whether failures are durable or retryable, and whether routing fanout changed enough to threaten quotas or downstream systems.

## Key concepts

### Glossary
| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| Event bus | The logical router that receives events and evaluates rules. | Primary blast-radius boundary for EventBridge incidents. | routing-volume |
| Rule | A pattern plus target set that defines when EventBridge should act. | Most useful ownership and fanout dimension after bus name. | routing-volume |
| Target | The downstream AWS service or endpoint invoked by a matched rule. | Determines latency, retry, and failure behavior. | delivery-reliability |
| Matched event | An event that matched at least one rule. | Best traffic proxy for routed work entering the rule engine. | routing-volume |
| Triggered rule | A rule that matched and fired for an event. | Shows how much rule evaluation is producing actionable work. | routing-volume |
| Invocation created | A target invocation that EventBridge scheduled from a rule match. | Primary fanout signal because one event can create multiple invocations. | fanout-capacity |
| Invocation attempt | An attempt to deliver work to a target, including retries. | Higher than invocations indicates retries or repeated delivery pressure. | delivery-reliability |
| Successful invocation attempt | A target delivery attempt that succeeded. | Best success numerator for delivery quality. | delivery-reliability |
| Invocation | A completed target invocation accounting line item in AWS metrics. | Useful denominator for permanent-failure ratio. | delivery-reliability |
| Failed invocation | A target invocation that exhausted retries or otherwise failed permanently. | Non-zero is the strongest failure signal in the current namespace. | delivery-reliability |
| Ingestion-to-invocation start latency | Time from event ingestion until EventBridge begins target delivery. | Captures routing and queueing delay before the first attempt. | latency-path |
| Ingestion-to-invocation complete latency | Time from ingestion until an invocation attempt completes. | Helps separate queue/start delay from attempt completion time. | latency-path |
| Ingestion-to-invocation success latency | Time from ingestion until EventBridge records a successful delivery. | Best end-to-end latency signal for healthy successful paths. | latency-path |
| Retry policy | EventBridge's retry window and attempt policy for failed deliveries. | Explains why attempts can rise without immediate permanent failures. | delivery-reliability |
| Dead-letter queue (DLQ) | Optional SQS queue for undelivered target events. | Critical for post-failure capture, but DLQ metrics are absent from the current namespace. | delivery-reliability |
| Invocation throttle limit | Service quota limiting target invocations per Region. | Exceeding it produces delay and throttling symptoms before total failure. | fanout-capacity |
| Event bus logs | Structured execution logs emitted by EventBridge to CloudWatch Logs, Firehose, or S3. | Best Stage 4 source for tracing individual event routing steps. | all |
| CloudTrail management event | API audit record for EventBridge control-plane actions. | Best source for config-change correlation when routing behavior changes suddenly. | routing-volume |
| Schema discovery | EventBridge feature that infers event schemas into a registry. | Useful for producer/event-shape debugging, but not a delivery SLI by itself. | routing-volume |
| Archive and replay | EventBridge feature for storing and replaying past events. | Important remediation tool when rules were wrong or targets were unavailable. | delivery-reliability |
| Custom event | Application-published event typically sent via `PutEvents`. | If publish-side signals are missing, CloudTrail or producer metrics may be needed. | routing-volume |
| Managed rule fanout | The ratio of rules and targets generated from each matched event. | Sudden increases can create cost, latency, and quota pressure. | fanout-capacity |

### Concept Map
Event producer -> sends -> Event bus (why: EventBridge starts all routing from bus ingestion)
AWS service event -> lands on -> Event bus (why: managed AWS sources bypass custom producer code)
Custom application -> calls -> PutEvents (why: producer-side event publishing path)
Event bus -> evaluates -> Rule (why: rules decide whether downstream work is created)
Rule -> matches -> Event (why: only matching events generate delivery work)
Matched event -> can trigger -> multiple rules (why: one event can fan out across several rule patterns)
Triggered rule -> creates -> one or more target invocations (why: each rule may have multiple targets)
Invocations created -> become -> invocation attempts (why: EventBridge must actually deliver to targets)
Invocation attempt -> succeeds -> successful invocation attempt (why: downstream target accepted delivery)
Invocation attempt -> fails transiently -> retry policy (why: EventBridge retries before marking durable failure)
Retry policy -> increases -> invocation attempts (why: retries consume attempt budget and time)
Retry exhaustion -> produces -> failed invocation (why: EventBridge gives up after retry policy completes)
Target unavailability -> increases -> ingestion-to-success latency (why: retries extend end-to-end completion time)
Rule explosion -> increases -> invocations created (why: more rules or more targets per rule multiply delivery work)
Higher fanout -> consumes -> invocation throttle quota (why: each created invocation counts against regional capacity)
Quota pressure -> delays -> invocation start (why: throttling shows up before end-to-end success)
Event bus logs -> record -> execution steps (why: they show where the pipeline stalled)
CloudTrail -> records -> configuration changes (why: rule edits or target edits can explain sudden behavior shifts)
DLQ -> captures -> undelivered events (why: preserves payloads for remediation after delivery failure)
Archive -> stores -> historical events (why: replay can recover from bad rules or temporary outages)
Replay -> re-enters -> event bus (why: EventBridge reruns matching and invocation logic)
Schema discovery -> describes -> event structure (why: helps validate producers and event patterns)
Account and Region -> scope -> quotas and metrics (why: EventBridge limits and CloudWatch metrics are regional)
Team ownership -> maps to -> rule and bus boundaries (why: routing incidents are usually owned at those layers)
Managed service health -> is observed through -> routing, attempts, failures, and latency (why: there is no host-level EventBridge dashboard)

### Entities and dimensions
| Entity or dimension | Why useful | Cardinality risk | Safe top-N suggestion | Do NOT group-by guidance |
|---|---|---|---|---|
| `context.env` | Environment boundary for prod and non-prod routing differences. | Low | 5 | Keep as dashboard filter, not a chart legend default. |
| `context.team` | Ownership split for event buses or rule sets. | Low | 10 | Use for filtering, not primary triage. |
| `context.cloud.region` | Quotas and EventBridge behavior are regional. | Low | 10 | Avoid mixing Region with per-rule groupings in the same chart. |
| `context.cloud.account.id` | Multi-account organizations often isolate buses by account. | Low | 10 | Use for filtering before deeper breakdowns. |
| `context.rulename` | Best confirmed dimension for rule explosion or broken patterns. | Medium | 20 | Prefer top-lists before dense multi-line charts. |
| `context.source` | Best confirmed source-family dimension across all 10 metrics. | Medium | 12 | Do not pair with too many secondary labels by default. |
| `context.cloud.region` | Primary fallback for `aws_events_invocations_created`, which lacks `context.rulename`. | Low | 10 | Use after rule and source views if the issue is regional. |
| Event bus name | Operationally important concept, but not present as a confirmed metric attribute in the current namespace. | N/A | N/A | Use logs or config inventory, not metric group-by. |
| Target id | Operationally important concept, but not present as a confirmed metric attribute in the current namespace. | N/A | N/A | Use logs or downstream service telemetry instead. |
| `context.eventsourcename` | Distinguishes AWS source, partner source, or custom app source when available outside the current metric set. | Medium | 12 | Not confirmed in the current namespace. |
| `context.detailtype` | Helps spot one noisy event family. | Medium-High | 12 | Avoid as first-line dashboard split if producers emit many types. |
| `context.replayname` | Important only when archives or replays are active. | Low | 10 | Gate or hide when replay is unused. |
| `context.endpointname` | Relevant if API destinations are used. | Low-Medium | 10 | Keep out of default widgets unless API destinations are confirmed. |
| `context.schemaregistry` | Useful only for schema-discovery troubleshooting. | Low | 10 | Not a routing SLI dimension. |

### Tsuga field mapping
| Vendor or exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| RuleName | `context.rulename` | Confirmed optional field on 9 of 10 metrics |
| Source | `context.source` | Confirmed optional field on all 10 metrics |
| EventBusName | Unknown in current metric catalog | Not present in confirmed metric attributes |
| TargetId | Unknown in current metric catalog | Not present in confirmed metric attributes |
| TargetArn | Unknown in current metric catalog | Not present in confirmed metric attributes |
| EventSourceName | `context.eventsourcename` | Optional |
| DetailType | `context.detailtype` | Optional |
| ReplayName | `context.replayname` | Optional |
| API destination or connection identifier | `context.endpointname` | Optional |
| Region | `context.cloud.region` | Confirmed optional field |
| Account | `context.cloud.account.id` | Confirmed optional field |
| Environment | `context.env` | Must-exist |
| Team | `context.team` | Must-exist |

### Confirmed by sources
- AWS documents EventBridge metrics with dimensions around event buses, rules, and the invocation pipeline. [S1]
- Tsuga metadata confirms `context.rulename`, `context.source`, `context.cloud.account.id`, `context.cloud.region`, `context.env`, and `context.team` on the live `aws_events_*` namespace. [Tsuga Stage 2]
- Event bus logs include execution-step metadata such as event bus, rules, targets, timestamps, and details blocks, which supports mapping several routing dimensions into Tsuga log fields even when the metric catalog does not expose them. [S5][S6]

### Best-practice inference
- Stage 2 confirmed that the current metric catalog does not carry event-bus or target identifiers, so those pivots must come from logs or other telemetry.
- The namespace likely comes from a CloudWatch-style exporter because keys are lowercased and normalized in the same style as other AWS integrations in this repo.

## Golden signals

### Confirmed by sources
| Signal | What it means for EventBridge | Typical causes when it degrades | Best telemetry sources | What people page on | Section questions |
|---|---|---|---|---|---|
| Traffic | How many events are matching rules and how much delivery work gets created. | Producer outage, rule edits, event pattern drift, event storms. | `MatchedEvents`, `TriggeredRules`, `InvocationsCreated` [S1] | Expected event volume disappears or fanout spikes unexpectedly. | Are events still matching? Did rule or target fanout change? |
| Errors | Whether delivery attempts are failing durably instead of succeeding after retries. | Broken target IAM, deleted target resources, downstream endpoint failures, exhausted retries. | `FailedInvocations`, `InvocationAttempts`, `SuccessfulInvocationAttempts` [S1][S2][S7][S8] | Persistent non-zero failure rate or falling success rate. | Are failures transient, retryable, or permanent? |
| Latency | Time from event ingestion to target delivery start, completion, and success. | Invocation throttling, target latency, retry backoff, service-side queueing. | `IngestiontoInvocationStartLatency`, `IngestiontoInvocationCompleteLatency`, `IngestiontoInvocationSuccessLatency` [S1] | Success latency grows materially above start latency baseline. | Where is delay entering: before attempts, during attempts, or across retries? |
| Saturation | Pressure from fanout growth or regional invocation limits. | Too many rules per event, too many targets per rule, downstream slowdown, quota exhaustion. | `InvocationsCreated`, `InvocationAttempts`, quotas and throttle guidance [S1][S2][S7] | Attempts rise much faster than invocations created or latency rises with steady traffic. | Are we creating more work than the service or targets can drain? |

### Best-practice inference
- For EventBridge, `consumer lag`-style thinking maps to end-to-end invocation latency rather than host CPU. Managed service incidents usually surface first as routing delay or retry amplification, not infrastructure gauges.
- `FailedInvocations` matters more than raw `Invocations` because it reflects events that never made it to the target even after EventBridge exhausted retries.

## Telemetry sources

### Confirmed by sources
| Source type | How collected | What it provides | Pros and cons | Common pitfalls |
|---|---|---|---|---|
| `AWS/Events` CloudWatch metrics | Native AWS service metrics, typically exported into Tsuga from CloudWatch | Counts for matches, rules, invocations, attempts, failures, and latency | Best coarse operational SLI surface; low implementation effort. Limited per-payload context. | Missing publisher-side `PutEvents*` or DLQ metrics means the namespace can look healthier than the full pipeline. [S1] |
| Event bus logs | EventBridge emits structured logs to CloudWatch Logs, Firehose, or S3 | Per-event execution steps, rule matches, target attempts, and outcomes | Best source for Stage 4 parsing and root-cause drill-down. Requires logging to be enabled and costs extra. | Log volume can be high on busy buses; logs can contain sensitive event data and need careful scope selection. [S5][S6] |
| CloudTrail management events | AWS CloudTrail captures EventBridge API activity | Configuration changes such as rule edits, bus policy changes, target changes | Excellent for correlating behavior shifts to config drift. Does not explain per-event delivery outcome. | Easy to overuse for runtime debugging even though it is control-plane only. [S4] |
| SQS dead-letter queues | Optional EventBridge rule target DLQ | Original undelivered event payloads plus failure context | Best evidence for post-failure triage and replay workflows. | DLQ metrics are absent from the current `aws_events_*` namespace, so dashboards must call out this blind spot. [S8] |
| Schema discovery and registry | Optional EventBridge schemas feature | Event structure inventory for producers and consumers | Useful for understanding event shape drift. Not itself a health signal. | Customer managed keys are not supported for discovered schema sources. [S9] |

### Best-practice inference
- "No data" in `aws_events_*` often means the EventBridge path is idle, logging is disabled, or an exporter omitted certain AWS metrics. It does not automatically mean healthy zero.
- Pair EventBridge metrics with one log source and one control-plane source. Metrics alone cannot tell whether a failure came from IAM, target deletion, payload shape drift, or quota pressure.

## Log intelligence (Stage 4 handoff)

### Confirmed by sources
1. **Log sources matrix**

| Source | Access path | Typical format | Structured vs unstructured | Evidence |
|---|---|---|---|---|
| Event bus logs | CloudWatch Logs log group, Kinesis Data Firehose, or Amazon S3 destination configured on an event bus | JSON record with metadata, execution step, and details block | Structured | [S5][S6] |
| CloudTrail management events | CloudTrail event history, S3 trail, or CloudWatch Logs trail integration | JSON audit event | Structured | [S4] |
| SQS dead-letter queue payloads | SQS queue configured as EventBridge DLQ | JSON event payload plus queue envelope fields | Structured | [S8] |

2. **Known log formats**
- **Event bus log record**
  - Sample line: `{"resource_arn":"arn:aws:events:REGION:ACCOUNT:event-bus/default","message_type":"EVENT_RECEIPT","log_level":"INFO","details":{"event_bus_name":"default","source":"my.app","detail_type":"order.created"}}`
  - Shape notes: single JSON object per event-processing step; top-level metadata plus nested `details`.
  - Timestamp pattern: epoch-millis style timestamps plus step-specific timestamps inside `details`. [S6]
  - Quoting behavior: standard JSON quoting.
  - Optional fields: rule, target, error, replay, trace headers vary by execution step.
- **CloudTrail management event**
  - Sample line: `{"eventSource":"events.amazonaws.com","eventName":"PutRule","awsRegion":"eu-west-1","requestParameters":{"name":"my-rule"}}`
  - Shape notes: standard CloudTrail JSON envelope with nested request and response blocks. [S4]

3. **Candidate query filters for Stage 4**
- Precise: `resource_arn:*event-bus/* AND message_type:*INVOCATION*`
  - Rationale: targets the EventBridge delivery path and filters out unrelated control-plane noise.
  - Risk: depends on Stage 4 confirming exact field names in emitted logs.
- Fallback: `"events.amazonaws.com" OR "event-bus" OR "FailedInvocations"`
  - Rationale: broader catch-all when the exact structured fields are unknown.
  - Risk: will pull CloudTrail and operational noise together and need post-filtering.

4. **Attribute mapping hints**

| Raw field | Suggested Tsuga key | Confidence | Notes |
|---|---|---|---|
| `resource_arn` | `context.resource.arn` | Medium | Stable top-level field in event bus logs. |
| `details.event_bus_name` | `context.eventbusname` | Medium | Preferred bus dimension if present. |
| `details.rule_name` | `context.rulename` | Medium | Key field for rule explosion or misconfiguration. |
| `details.target_id` | `context.targetid` | Medium | Useful for target-specific failure attribution. |
| `details.source` | `context.source` | Medium | Maps event producer namespace. |
| `details.detail_type` | `context.detailtype` | Medium | Good for high-level event family filtering. |
| `log_level` | `context.log.level` | High | Straightforward log attribute. |
| `message_type` | `context.message.type` | Medium | Distinguishes execution phases. |
| `eventName` | `context.aws.api.action` | High | CloudTrail control-plane action. |
| `awsRegion` | `context.cloud.region` | High | Shared between CloudTrail and AWS resource context. |

5. **Parsing risks**
- Different event bus execution steps emit different `details` shapes. [S6]
- Log volume can be very high if all steps are logged for a busy bus. [S5]
- Event payload fields may be large or sensitive; avoid exploding them into top-level attributes without need. [S5]
- CloudTrail records config changes, not runtime delivery outcomes, so mixing both streams can blur meaning. [S4]
- DLQ messages wrap the original event with SQS delivery metadata, which can create dual-format parsing requirements. [S8]

### Best-practice inference
- Start Stage 4 with event bus logs if they are enabled. They have the best chance of linking a failed metric spike back to a specific rule or target.
- If event bus logs are disabled, CloudTrail plus DLQ ingestion is the next-best combination, but it will not cover transient retry behavior as clearly.

## Caveats and footguns
- **[routing-volume]** `MatchedEvents` means events that matched at least one rule, not events published to the bus. A producer outage and a rule-pattern mistake can look similar if you only watch this metric. (S1)
- **[routing-volume]** `TriggeredRules` can exceed `MatchedEvents` because one matched event can trigger multiple rules. Treat the ratio as a fanout signal, not a health regression by itself. (S1)
- **[fanout-capacity]** `InvocationsCreated` can exceed both `MatchedEvents` and `TriggeredRules` if triggered rules have multiple targets. A sudden jump often reflects configuration drift. (S1)
- **[delivery-reliability]** `InvocationAttempts` includes retries, so rising attempts do not automatically mean more unique business events. (S1, S7)
- **[delivery-reliability]** `SuccessfulInvocationAttempts` can stay high while `FailedInvocations` rises if EventBridge is succeeding eventually for some targets but exhausting retries for others. (Inference)
- **[delivery-reliability]** `FailedInvocations` is a durable-failure signal after retry behavior, not an immediate first-attempt error counter. (S1, S2, S7)
- **[delivery-reliability]** The current namespace lacks explicit retry counters and DLQ counters, so retry amplification must be inferred from ratios between attempts and successes. (Tsuga preflight)
- **[latency-path]** `IngestiontoInvocationStartLatency` widening with stable success latency delta usually indicates service-side queueing or throttling before delivery even begins. (Inference)
- **[latency-path]** `IngestiontoInvocationSuccessLatency` includes both queueing and retry delay, so it is not directly comparable to downstream target runtime alone. (S1)
- **[latency-path]** Latency metrics in the current Tsuga namespace are typed as summaries; Stage 2 must verify whether `average`, `max`, or percentile aggregations are safe in Tsuga. (Tsuga preflight)
- **[fanout-capacity]** Regional invocation throttle limits can create delay before you see obvious permanent failures. Watch latency and attempts together. (S2, S7)
- **[fanout-capacity]** A new rule with broad event patterns can multiply target work without any producer-side traffic increase. (S2)
- **[routing-volume, fanout-capacity]** Archive and replay operations can legitimately spike matched events and invocations. Treat replay windows separately from live traffic. (S5)
- **[routing-volume]** Schema discovery is useful for payload understanding but is not a routing success metric. Do not place schema counts in the main health surface. (S9)
- **[delivery-reliability]** DLQ absence is not proof of health. If DLQs are not configured, failures may still happen but only surface as `FailedInvocations` or logs. (S8)
- **[delivery-reliability]** Target IAM failures, deleted targets, and target throttling can all collapse into delivery-failure symptoms. Metrics alone will not disambiguate them. (S8)
- **[routing-volume]** Event bus logs can contain full event data. Turning them on broadly may create privacy or cost issues and should be scoped deliberately. (S5)
- **[routing-volume]** CloudTrail is control-plane only. A clean CloudTrail timeline does not prove runtime delivery is healthy. (S4)
- **[fanout-capacity]** Grouping by raw target ARN in charts can become noisy if rules target many unique resources. Prefer top-lists and stage gated views. (Inference)
- **[routing-volume, delivery-reliability, latency-path, fanout-capacity]** The current `aws_events_*` namespace contains only 10 metrics, so dashboards must call out blind spots instead of inventing absent publisher, retry, or DLQ signals. (Tsuga preflight)

## Confirmed Tsuga prefixes
- `aws_events*` — **CONFIRMED** (10/10 metrics present after Stage 2 catalog bootstrap and MCP metadata checks on 2026-03-18; exact names: `aws_events_failed_invocations`, `aws_events_ingestion_to_invocation_complete_latency`, `aws_events_ingestion_to_invocation_start_latency`, `aws_events_ingestion_to_invocation_success_latency`, `aws_events_invocation_attempts`, `aws_events_invocations`, `aws_events_invocations_created`, `aws_events_matched_events`, `aws_events_successful_invocation_attempts`, `aws_events_triggered_rules`).

## Discovery status
- Discovery: Stage 2 reconciliation completed.
- `METRICS_FOUND`: 10 `aws_events_*` metrics in Tsuga, all of which match the operational metrics already documented in `01_aws-eventbridge_metrics.csv`.
- Confirmed context field registry: `context.rulename` on 9 metrics, `context.source` on all 10 metrics, plus `context.cloud.account.id`, `context.cloud.region`, `context.env`, and `context.team`.
- Confirmed metric metadata: all 10 metrics are `summary` with `cumulative` temporality and support `avg|count|max|min|sum`.
- Notable gap: a broader catalog search did not find AWS-documented `PutEvents*`, retry, or DLQ metric families for EventBridge in this environment.
- Spot-check note: MCP scalar aggregation returned an internal server error, so recent-data verification was inconclusive even though the catalog and metadata reconciliation succeeded.

## Top sources
1. https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-monitoring.html
   Why: canonical CloudWatch metric names, latency metrics, and operational dimensions for `AWS/Events`.
2. https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-monitoring-events-best-practices.html
   Why: AWS's own guidance on what to watch for failures, DLQs, retries, and throttling.
3. https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-event-bus-logs.html
   Why: authoritative description of event bus logging destinations, controls, and tradeoffs.
4. https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-event-logs-schema.html
   Why: schema for EventBridge event bus log records used in Stage 4 parsing.
5. https://docs.aws.amazon.com/eventbridge/latest/userguide/logging-using-cloudtrail.html
   Why: confirms EventBridge control-plane coverage in CloudTrail and the audit-event model.
6. https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-quota.html
   Why: quota context for invocation throttle behavior and capacity interpretation.
7. https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-rule-retry-policy.html
   Why: retry window and attempt semantics that explain attempt amplification.
8. https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-rule-dlq.html
   Why: DLQ behavior, failure scenarios, and why DLQ metrics or messages matter for triage.
9. https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-schemas-infer.html
   Why: schema discovery behavior and constraints for event-shape debugging.
10. https://aws.amazon.com/eventbridge/pricing/
    Why: cost model reference when using event volume and invocation volume as cost proxies.

**Citation key**
- [S1] https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-monitoring.html
- [S2] https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-monitoring-events-best-practices.html
- [S3] https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-event-bus-logs.html
- [S4] https://docs.aws.amazon.com/eventbridge/latest/userguide/logging-using-cloudtrail.html
- [S5] https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-event-bus-logs.html
- [S6] https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-event-logs-schema.html
- [S7] https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-quota.html
- [S8] https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-rule-dlq.html
- [S9] https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-schemas-infer.html
