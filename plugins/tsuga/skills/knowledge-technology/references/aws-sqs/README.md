# AWS SQS Integration Context Bundle

## Metadata
**Technology:** AWS SQS  
**Deployment:** managed  
**Environment:** prod  
**Persona:** SRE Dev and ops  
**Telemetry preference:** mixed  
**Integration scope:** core service only  
**Primary use-case:** reliability and performance

## How to use this bundle
- Use `01_aws-sqs_metrics.csv` as the source of truth for queue metrics, safe aggregations, and bounded drilldowns.
- Use `02_aws-sqs_dashboard_plan.yaml` for the dashboard structure, derived signals, gating rules, notes, and coverage map.
- Use `03_aws-sqs_state.yaml` for machine-readable unknowns, field-mapping status, and Stage 2 verification priorities.
- Use `04_aws-sqs_memory.md` for the human-readable Stage 1 handoff and implementation tradeoffs.
- Stage 2 will create `05_aws-sqs_metric_catalog.csv` as the discovered Tsuga inventory used for reconciliation, description curation, and coverage checks.
- Stage 4 should read this file's `Log intelligence (Stage 4 handoff)` section and `03_aws-sqs_state.yaml` `log_intel` first before attempting any log route.

## What it is and what "good" looks like
### Confirmed by sources
Amazon SQS is AWS's managed pull-based messaging service. Producers enqueue work, consumers poll and process it, and queue health is inferred from backlog depth, message age, receive/delete activity, and visibility behavior rather than CPU or host metrics. For standard queues, "good" means visible backlog stays bounded for the workload, oldest-message age does not grow persistently, delayed messages remain intentional, and consumers delete messages at roughly the pace they receive them. For FIFO queues, good also means deduplication is low unless retries are expected and message-group parallelism is high enough that one hot group does not serialize the whole queue. AWS documents queue-depth, age, throughput, deduplication, and fair-queue metrics directly in the CloudWatch metrics guide, and it describes how long polling, visibility timeout, dead-letter handling, and FIFO delivery logic shape incident response.

Paging intent for dashboards: first determine whether the incident is backlog growth, consumer inefficiency, or queue-shape skew. For backlog growth, start with `backlog-health`. For slow or wasteful polling, start with `consumer-polling`. For ordering or noisy-neighbor issues in FIFO or fair queues, start with `fifo-fairness`. For redrive or poison-message suspicion, use `backlog-health` first, then verify DLQ configuration outside this bundle because DLQ depth is a separate queue surface.

### Best-practice inference
- Incident shape 1: queue depth and oldest age rise together. Start with `backlog-health`, then compare send, receive, and delete rates.
- Incident shape 2: backlog is low but empty receives surge. Start with `consumer-polling`; this usually points to short polling, over-provisioned pollers, or consumers hitting mostly empty shards of a standard queue.
- Incident shape 3: only some tenants or message groups degrade. Start with `fifo-fairness`; noisy groups or too-few in-flight groups usually indicate poor grouping strategy or one blocked ordered lane.

## Key concepts
### Glossary
| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| Queue | Durable SQS buffer for messages | Main isolation boundary for backlog and throughput | backlog-health |
| Standard queue | SQS queue with best-effort ordering and at-least-once delivery | Backlog and age matter more than strict ordering | backlog-health |
| FIFO queue | SQS queue with ordered processing within message groups and deduplication support | Group-level skew and dedup behavior become first-class signals | fifo-fairness |
| Visible message | Message available to be received | Immediate work waiting on consumers | backlog-health |
| In-flight message | Received but not yet deleted message | Consumer concurrency and visibility-timeout pressure | backlog-health |
| Delayed message | Message hidden until delay expires | Scheduled backlog that can mask true ready work | backlog-health |
| Oldest message age | Approximate age of the oldest non-deleted message | Direct user-visible latency proxy for queue drain health | backlog-health |
| Receive | Consumer poll that returns one or more messages | Core consumption activity | throughput-balance |
| Delete | Consumer acknowledgement that removes a message | Completion signal; lagging deletes imply retries or failures | throughput-balance |
| Empty receive | Receive call that returns no messages | Poll inefficiency or false-empty behavior | consumer-polling |
| Long polling | Receive mode that waits for messages before returning | Reduces empty receives and polling waste | consumer-polling |
| Short polling | Receive mode that samples servers and may return empty sooner | Can inflate empty receives and hide residual backlog | consumer-polling |
| Visibility timeout | Period after receive during which the message is hidden | Too short causes duplicates; too long stalls retries | backlog-health |
| DLQ | Dead-letter queue for repeatedly failed messages | Required context when oldest age rises due to poison messages | backlog-health |
| Poison message | Message that repeatedly fails processing | Creates age growth and repeated receives without matching deletes | backlog-health |
| Message group | Ordered lane inside a FIFO queue | Throughput and head-of-line blocking are group-dependent | fifo-fairness |
| Deduplication | FIFO suppression of duplicate sends within a dedup window | Rising deduplicated sends usually mean producer retry churn | fifo-fairness |
| Fair queue | Standard queue behavior that isolates noisy tenants using `MessageGroupId` | Quiet-group backlog metrics reveal tenant skew | fifo-fairness |
| Noisy group | Tenant or message group dominating queue work | Explains partial degradation while overall queue looks acceptable | fifo-fairness |
| Quiet group | Non-noisy groups in a fair queue | Useful baseline for whether only some tenants are hurt | fifo-fairness |
| Sent message size | Payload size of sent messages | Large payload shifts throughput and cost; can slow consumers | throughput-balance |
| Approximate metric | SQS CloudWatch metric based on distributed queue internals | Trends matter more than exact single-point values | backlog-health |

### Concept Map
```text
Producer -> sends -> SQS queue (why: all downstream work begins as queued backlog)
SQS queue -> exposes -> visible messages (why: this is immediate ready work)
SQS queue -> exposes -> delayed messages (why: scheduled work should not be mistaken for consumer lag)
Consumer -> receives -> messages (why: receive rate shows pull demand)
Receive -> starts -> visibility timeout (why: in-flight work can block ordered progress)
Consumer -> deletes -> message (why: delete is the completion acknowledgement)
Missing delete -> leaves -> message eligible for redelivery (why: duplicate processing risk rises)
Poison message -> causes -> repeated receives without delete (why: age and in-flight counts grow)
Visibility timeout too short -> causes -> duplicate work (why: the same message reappears before processing finishes)
Visibility timeout too long -> delays -> retry and redrive (why: failed work stays hidden too long)
Oldest visible message age -> represents -> user-visible waiting time (why: backlog latency matters more than raw queue size alone)
Send rate -> competes with -> receive and delete rate (why: imbalance creates persistent backlog)
Long polling -> reduces -> empty receives (why: consumers wait instead of hammering the queue)
Short polling -> increases -> false empty responses (why: consumers may miss available messages)
FIFO queue -> partitions ordering by -> message group ID (why: concurrency depends on group distribution)
Message group ID -> bounds -> in-flight parallelism per group (why: one hot group can serialize throughput)
Deduplication ID -> suppresses -> duplicate send attempts (why: retries may be acknowledged but not enqueued)
Fair queue -> classifies -> noisy and quiet groups (why: dashboards can separate tenant-local from global pain)
Noisy group -> inflates -> quiet-group age or depth imbalance (why: some tenants are starved before the whole queue fails)
DLQ policy -> removes -> repeatedly failing messages from source queue (why: source age can recover once poison work is isolated)
context.queuename -> maps -> operational ownership (why: queue is the primary drilldown)
context.cloud.region -> maps -> blast radius (why: regional incidents can affect many queues)
context.cloud.account.id -> maps -> account boundary (why: multi-account estates need separate filtering)
context.env + context.team -> map -> runtime ownership (why: dashboards must support environment and team pivots)
```

### Entities and dimensions
#### Confirmed by sources
| Entity/Dimension | Why useful | Cardinality risk | Safe top-N | Do NOT group-by guidance |
|---|---|---|---|---|
| `context.queuename` | Primary queue drilldown and likely first global filter | Low to medium | 20 | Use this before any exporter ARN split |
| `context.cloud.region` | Regional blast radius for AWS outages or queue concentration | Low | 12 | Prefer as a global filter in single-region deployments |
| `context.cloud.account.id` | Separates prod accounts and shared-platform accounts | Low | 10 | Use for estate views, not every chart |
| `context.env` | Environment segmentation | Low | 5 | Global filter only |
| `context.team` | Ownership routing | Low | 10 | Global filter only |
| `context.cloud.provider` | Confirms AWS-only surface | Very low | 3 | Not worth chart space |
| `context.aws.exporter.arn` | Can distinguish exporter instances or source ARNs | Medium | 10 | Keep out of headline widgets; debug use only |
| Queue type (standard or FIFO) | Changes interpretation of dedup and group metrics | Very low | 2 | Derive from queue naming/config, not as a discovered field |
| Message group ID | Explains FIFO parallelism and fairness | High if available | 20 | Do not assume Tsuga exports it on metrics |
| Noisy group | Explains tenant-local saturation in fair queues | Medium | 10 | Treat as concept until Stage 2 confirms fields |
| Quiet group | Baseline for non-noisy tenants | Medium | 10 | Use conceptually; do not invent group fields |
| Delay configuration | Distinguishes intentional scheduling from consumer lag | Low | 5 | Usually note text, not widget grouping |
| DLQ name | Critical for poison-message triage | Medium | 10 | Separate queue family, likely not on source-queue metrics |
| Message size bucket | Helps explain throughput limits and slow consumers | Medium | 10 | Prefer aggregate size metrics over per-message identifiers |

### Tsuga field mapping
#### Confirmed by sources
| Vendor/exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| QueueName | `context.queuename` | Must-exist |
| AWS Region | `context.cloud.region` | Must-exist |
| AWS Account ID | `context.cloud.account.id` | Optional but preferred |
| Cloud provider | `context.cloud.provider` | Optional |
| Team tag | `context.team` | Must-exist |
| Environment tag | `context.env` | Must-exist |
| Exporter source ARN | `context.aws.exporter.arn` | Optional |

#### Best-practice inference
| Vendor/exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| Queue type | `Unknown` | Optional; infer from queue config or `.fifo` naming if absent |
| Message group ID | `Unknown` | Optional; useful for FIFO deep dive if ever exposed |
| Fair-queue tenant or noisy-group key | `Unknown` | Optional; verify in Stage 2 before planning any tenant top-list |
| DLQ target queue | `Unknown` | Optional; may require config APIs rather than metrics |

## Golden signals
### Confirmed by sources
| Signal | SQS meaning | Typical degradations | Best telemetry sources | What people page on | Section questions |
|---|---|---|---|---|---|
| Traffic | Enqueue, receive, and delete activity moving through the queue | send spike, receive collapse, delete lag | `NumberOfMessagesSent`, `NumberOfMessagesReceived`, `NumberOfMessagesDeleted` | send rate rising without drain, or traffic dropping unexpectedly | Are producers and consumers balanced? Is work completing? |
| Errors | SQS queueing issues rarely appear as explicit error metrics; failure is inferred from retry churn, DLQ movement, and age growth | poison messages, duplicate retries, misconfigured polling | `NumberOfEmptyReceives`, DLQ depth on companion queue, CloudTrail API failures | backlog aging, duplicate suppression spikes, or repeated empty receives under expected load | Is the queue unhealthy or are consumers ineffective? |
| Latency | Time work waits before a successful receive/delete | oldest age growth, delayed-message accumulation | `ApproximateAgeOfOldestMessage`, delayed and visible backlog counts | oldest message age rising for sustained periods | How long is work waiting? Is delay intentional or pathological? |
| Saturation | Queue backlog and in-flight occupancy relative to drain capacity | visible depth growth, in-flight stalls, hot message groups | `ApproximateNumberOfMessagesVisible`, `ApproximateNumberOfMessagesNotVisible`, fair/FIFO group metrics | queue depth climbing or ordered groups blocking progress | Is backlog building faster than consumers can clear it? |

### Best-practice inference
For SQS, oldest-message age is usually more actionable than raw queue depth because a deep queue can be healthy during bursts while an aging queue almost always reflects unmet processing demand or poison work.

## Telemetry sources
### Confirmed by sources
| Source type | How collected | What it provides | Pros/cons | Common pitfalls |
|---|---|---|---|---|
| CloudWatch SQS service metrics | Native AWS/SQS namespace exported from SQS to CloudWatch | Queue depth, age, send/receive/delete counts, empty receives, FIFO/fair-queue signals | Canonical and low-friction; metrics are approximate and queue-level | Exact counts should not be assumed from single samples |
| CloudTrail management/data events | AWS API logging for SQS actions | Audit trail for send, receive, delete, queue config changes | Good for who-did-what context; not a queue-health metric surface | Often disabled or not ingested into Tsuga logs |
| Consumer application logs | App or worker runtime logs | Actual processing failures, retries, payload errors, DLQ reasons | Best for root cause; not native to SQS | Not a service log stream and may span many runtimes |
| Queue configuration APIs | `GetQueueAttributes`, console config, IaC state | Visibility timeout, redrive policy, FIFO mode, long-poll settings | Essential for interpreting metrics | Not visible in metric streams directly |

### Best-practice inference
Treat CloudWatch SQS metrics as the primary dashboard contract and use logs only to explain why consumers fail to delete messages. Do not try to infer consumer correctness from service metrics alone.

## Log intelligence (Stage 4 handoff)
### Confirmed by sources
**Log sources matrix**

| Source | Access path | Typical format | Structured vs unstructured | Evidence |
|---|---|---|---|---|
| CloudTrail SQS API events | CloudTrail event history, CloudWatch Logs, or S3 delivery | JSON management/data events for `SendMessage`, `ReceiveMessage`, `DeleteMessage`, queue config changes | Structured | https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-logging-using-cloudtrail.html |
| Consumer application logs | Worker runtime logs outside SQS | Runtime-specific text or JSON with queue URL/name, receipt handle, error reason | Mixed | Consumer-owned, not documented by SQS |
| DLQ inspection tooling | Queue receive/delete history or consumer logs | Queue-specific operational records | Mixed | Derived from app/process usage, not a native SQS log |

**Known log formats**

1. CloudTrail SQS API events  
   Sample shape: JSON event envelope with `eventSource: "sqs.amazonaws.com"`, `eventName`, `awsRegion`, request parameters, and identity metadata.  
   Shape notes: structured JSON, timestamp embedded, no multiline concerns, field set varies by API and whether data events are enabled.  
   Evidence: https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-logging-using-cloudtrail.html

2. Consumer failure logs  
   Sample shape: service-defined application log line or JSON object containing queue name, receive attempt, processing error, and delete outcome.  
   Shape notes: not standardized by SQS; likely multiple formats across runtimes.  
   Evidence: Unknown from vendor docs; infer only after Stage 4 live log search.

**Candidate query filters for Stage 4**
- Precise: `context.service.name:* AND message:*sqs.amazonaws.com*`  
  Rationale: catches CloudTrail-style SQS API events if AWS audit logs are ingested.  
  Risk: depends on CloudTrail forwarding and log preservation in Tsuga.
- Broader fallback: `(message:*ReceiveMessage* OR message:*DeleteMessage* OR message:*ChangeMessageVisibility* OR message:*SendMessage*)`  
  Rationale: catches both audit and app logs that mention the core queue verbs.  
  Risk: high false-positive rate across unrelated components.

**Attribute mapping hints**

| Raw field | Suggested Tsuga key | Confidence | Notes |
|---|---|---|---|
| `requestParameters.queueUrl` or queue name | `context.queuename` | Medium | Prefer the discovered metric field name if log enrichment already extracts queue name |
| `awsRegion` | `context.cloud.region` | High | Stable in CloudTrail events |
| `recipientAccountId` or account context | `context.cloud.account.id` | Medium | Field names vary by event family |
| `eventName` | `context.aws.sqs.event_name` | High | Useful to separate send, receive, delete, and visibility changes |
| consumer error string | `context.error.message` | Low | App-specific, not SQS-native |
| receipt handle or message ID | `context.aws.sqs.message_id` | Low | High-cardinality; do not index aggressively |

**Parsing risks**
- SQS itself does not emit a rich service-runtime log stream like a proxy or database.
- CloudTrail may be disabled, filtered, or routed outside Tsuga.
- Consumer logs are owned by the application and can use many incompatible formats.
- Message IDs and receipt handles are high-cardinality and should not become default group-bys.
- A useful Stage 4 route may need to target consumer services rather than SQS-native logs.

### Best-practice inference
Stage 4 may be inapplicable if there is no centralized CloudTrail ingestion and no consistent consumer log shape. Prefer skipping log-route creation rather than inventing an SQS parser for logs that do not exist.

## Caveats and footguns
- **[backlog-health]** SQS backlog metrics are approximate and should be trended, not treated as exact queue inventory. (https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-available-cloudwatch-metrics.html)
- **[backlog-health]** `ApproximateAgeOfOldestMessage` is a better incident signal than raw depth when you need to decide whether users are actually waiting. (Inference)
- **[backlog-health]** `ApproximateNumberOfMessagesVisible` can stay low even while specific FIFO groups stall if only one ordered lane is blocked. (https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/FIFO-queues-understanding-logic.html)
- **[backlog-health]** `ApproximateNumberOfMessagesNotVisible` rising can mean healthy high concurrency or stuck consumers; do not read it as failure alone. (https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-visibility-timeout.html)
- **[backlog-health]** Delayed messages are intentional hidden work, not necessarily consumer lag. (https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-available-cloudwatch-metrics.html)
- **[backlog-health, throughput-balance]** Missing deletes after healthy receives usually indicate consumer failure, timeout expiration, or missing acknowledgement logic. (https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-using-receive-delete-message.html)
- **[backlog-health]** A poison message can keep oldest age elevated even when most consumers are healthy; confirm DLQ policy before scaling blindly. (https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-dead-letter-queues.html)
- **[backlog-health]** When confirming a queue is empty, AWS recommends watching visible, not visible, and delayed counts together for several minutes rather than trusting one zero datapoint. (https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/confirm-queue-is-empty.html)
- **[throughput-balance]** `NumberOfMessagesDeleted` can exceed received counts because the same message may be received more than once before deletion. (https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-available-cloudwatch-metrics.html)
- **[throughput-balance]** `NumberOfMessagesReceived` is not equivalent to unique business work completed; retries and duplicates inflate it. (https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-available-cloudwatch-metrics.html)
- **[throughput-balance]** `SentMessageSize` should usually be viewed as an average or max trend, not summed across queues as a headline. (Inference)
- **[throughput-balance]** Queue-depth growth after a producer burst can be healthy if receive and delete rates catch up quickly; sustained age is the tie-breaker. (Inference)
- **[consumer-polling]** Empty receives can rise from short polling even when messages still exist; this is not always a zero-traffic state. (https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-short-and-long-polling.html)
- **[consumer-polling]** Over-scaling pollers can make empty-receive counts look alarming without any customer impact. (Inference)
- **[consumer-polling]** Never group SQS queue widgets by receipt handle or message ID if such fields appear later; the cardinality is pathological. (Inference)
- **[fifo-fairness]** `NumberOfDeduplicatedSentMessages` is only meaningful for FIFO queues and can remain zero on healthy standard queues. (https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/FIFO-queues-exactly-once-processing.html)
- **[fifo-fairness]** `ApproximateNumberOfGroupsWithInflightMessages` matters because too few active groups limit FIFO concurrency even when total backlog is large. (https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/FIFO-queues-understanding-logic.html)
- **[fifo-fairness]** Quiet-group metrics and noisy-group counts are specific to fair queues; do not show them as universal SQS backlog KPIs. (https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-available-cloudwatch-metrics.html)
- **[fifo-fairness]** One large message group can serialize FIFO progress; adding more consumers does not help if the grouping strategy is wrong. (https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/interleaving-multiple-ordered-message-groups.html)
- **[fifo-fairness]** High deduplication can be healthy during producer retry storms if exactly-once guarantees are working; it is a symptom to investigate, not immediate queue damage. (Inference)
- **[backlog-health, fifo-fairness]** Queue names often encode workload and environment, so `context.queuename` is valuable; exporter ARN is usually a lower-signal debug field. (Inference)

## Confirmed Tsuga prefixes
- `aws_sqs*` — **CONFIRMED** (16 metrics present in Tsuga from `python3 tools/tsuga_search_metrics.py '^aws_sqs.*'`)

## Discovery status
- Discovery: completed in Stage 2.
- Metrics found in Tsuga: 16
- Reconciliation result: 16 confirmed from `01`, 0 missing, 0 unexpected.
- Confirmed common attributes on all 16 metrics: `context.queuename`, `context.cloud.region`, `context.cloud.account.id`, `context.env`, `context.team`, `context.cloud.provider`, `context.aws.exporter.arn`, `context.source`, `context.unit`
- Confirmed capabilities on all 16 metrics: `avg`, `sum`, `count`, `min`, `max`
- Remaining gaps: recent-data scalar spot-checks returned Tsuga `500 INTERNAL_ERROR`, and no queue-type or tenant field beyond `context.queuename` was discovered.

## Top sources
- https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-available-cloudwatch-metrics.html - Canonical source for SQS queue, FIFO, and fair-queue metrics.
- https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-short-and-long-polling.html - Explains empty receives and polling efficiency.
- https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-visibility-timeout.html - Defines in-flight semantics and visibility-timeout tradeoffs.
- https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-dead-letter-queues.html - Grounds poison-message and redrive reasoning.
- https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/FIFO-queues-exactly-once-processing.html - Defines FIFO deduplication behavior.
- https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/FIFO-queues-understanding-logic.html - Explains message-group ordering and parallelism.
- https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-fair-queues.html - Defines quiet-group and noisy-group semantics.
- https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-logging-using-cloudtrail.html - Only reliable SQS-native logging reference for Stage 4.
- https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/confirm-queue-is-empty.html - Useful operational guidance for interpreting backlog metrics together.
- https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/interleaving-multiple-ordered-message-groups.html - Practical explanation of FIFO concurrency through message groups.
