# Google Cloud Pub/Sub Integration Context Bundle

**Technology:** Google Cloud Pub/Sub
**Deployment:** Managed (GCP)
**Environment:** prod
**Persona:** SRE Dev and ops
**Telemetry preference:** mixed
**Integration scope:** core service only
**Primary use-case:** reliability and performance

## How to use this bundle
- **07** (`07_google-cloud-pub-sub_dashboard_plan.yaml`) — section structure, widget specs, and coverage map for building dashboards
- **05** (`05_google-cloud-pub-sub_metric_inventory.csv`) — source of truth for all metrics, types, units, aggregations, and group-bys
- **09** (`09_google-cloud-pub-sub_section_notes_and_playbooks.md`) — paste-ready note content for every section, plus triage chains and playbooks
- **06** (`06_google-cloud-pub-sub_derived_signals.csv`) — formula widgets: inputs, aliases, formulas, output units

## Confirmed Tsuga prefixes
- `pubsub.googleapis.com/*` — **CONFIRMED** via Tsuga API discovery. 43 metrics found matching prefix. 32 confirmed with data, 4 listed but not found in current environment (push, dead letter, health score). Metric names use GCP dot-separated format (e.g., `pubsub.googleapis.com/topic/send_request_count`).

## Discovery status
Discovery: completed (Stage 2, 2026-02-10)
- 43 metrics enumerated via `/v1/metrics/names-and-types`
- 17 counter metrics confirmed as delta temporality via `/v1/metrics/metadata`
- Context fields confirmed via `/v1/metrics/attributes` on 15 representative metrics
- See `12_google-cloud-pub-sub_discovery_reconciliation.md` for full details

## Bundle files

| # | Filename | Purpose |
|---|---|---|
| 00 | `00_google-cloud-pub-sub_cover.md` | This file. Metadata, navigation, top sources. |
| 01 | `01_google-cloud-pub-sub_executive_overview.md` | What Pub/Sub is, what "good" looks like, top incident shapes. |
| 02 | `02_google-cloud-pub-sub_key_concepts.md` | Glossary (24 terms), concept map, entities, Tsuga field mapping. |
| 03 | `03_google-cloud-pub-sub_golden_signals.md` | Traffic/Errors/Latency/Saturation mapped to Pub/Sub. |
| 04 | `04_google-cloud-pub-sub_telemetry_sources.md` | Source matrix, optional features, "no data" interpretation. |
| 05 | `05_google-cloud-pub-sub_metric_inventory.csv` | 37 metrics: names, types, units, agg, post_fn, group_by. (32 confirmed + 4 unconfirmed + 1 N/A) |
| 06 | `06_google-cloud-pub-sub_derived_signals.csv` | 9 derived signals with formulas and input specs. |
| 07 | `07_google-cloud-pub-sub_dashboard_plan.yaml` | 7 sections, 2 dashboards, ~40 widgets, coverage map. |
| 09 | `09_google-cloud-pub-sub_section_notes_and_playbooks.md` | Section notes, 21 triage chains, 7 playbooks. |
| 10 | `10_google-cloud-pub-sub_caveats_footguns.md` | 24 caveats tagged to sections. |
| 11 | `11_google-cloud-pub-sub_unknowns_verify_next.yaml` | 7 unknowns — all RESOLVED via Stage 2 discovery. |
| 12 | `12_google-cloud-pub-sub_discovery_reconciliation.md` | Stage 2 reconciliation report. |

## Top sources

1. [GCP Pub/Sub Metrics Reference](https://cloud.google.com/monitoring/api/metrics_gcp#gcp-pubsub) — Authoritative list of all pubsub.googleapis.com/* metrics with types, units, and labels.
2. [Pub/Sub Overview](https://cloud.google.com/pubsub/docs/overview) — Architecture, topic/subscription model, delivery modes.
3. [Pub/Sub Monitoring Guide](https://cloud.google.com/pubsub/docs/monitoring) — How to monitor Pub/Sub with Cloud Monitoring, key metrics to watch.
4. [Subscription Properties](https://cloud.google.com/pubsub/docs/subscription-properties) — Ack deadline, DLT, ordering, exactly-once, retention, retry policy.
5. [Topic Troubleshooting](https://cloud.google.com/pubsub/docs/topic-troubleshooting) — Publish errors, latency, schema issues, SMT failures.
6. [Push Troubleshooting](https://cloud.google.com/pubsub/docs/push-troubleshooting) — Push endpoint failures, response classes, push backoff.
7. [Pull Troubleshooting](https://cloud.google.com/pubsub/docs/pull-troubleshooting) — Streaming pull issues, backlog growth, ack deadline expiry.
8. [Metrics Autoscaling Best Practices](https://cloud.google.com/pubsub/docs/metrics-autoscaling-best-practices) — Using backlog metrics for autoscaling decisions.
9. [Push Subscriptions](https://cloud.google.com/pubsub/docs/push) — Push delivery mechanics, authentication, backoff behavior.
10. [Pub/Sub Architecture](https://cloud.google.com/pubsub/docs/overview) — Two-plane architecture, message lifecycle, regional storage.


---

# Google Cloud Pub/Sub - Executive Overview

## What it is
Google Cloud Pub/Sub is a fully managed, serverless messaging service that decouples event producers from consumers. It handles hundreds of millions of messages per second with at-least-once (or exactly-once) delivery, automatic scaling, and global reach across all GCP regions. Topics receive published messages; subscriptions deliver them to consumers via pull, push, BigQuery export, or Cloud Storage export.

## What "good" looks like
- Publish latency (p99) under 50ms; send request error rate near zero.
- Subscription backlog (`num_undelivered_messages`) stable or draining; `oldest_unacked_message_age` below the ack deadline.
- Push endpoints returning 2xx; no sustained push backoff.
- Dead-letter message count near zero (messages are being processed successfully).
- Streaming pull connections stable; no excessive `mod_ack_deadline` activity.

## Paging intent (high-level)
Page on: subscription backlog age growing unbounded, sustained publish errors, dead-letter escalation, push endpoint failures.

## Top 3 incident shapes

1. **Backlog growth / consumer lag** - `oldest_unacked_message_age` climbing, `num_undelivered_messages` rising. Start with: Subscription Health section.
2. **Publish failures / elevated latency** - `send_request_count` errors spike, `send_request_latencies` p95+ degrades. Start with: Publishing Performance section.
3. **Push endpoint failures** - `push_request_count` non-ack responses, push backoff engaged. Start with: Push Delivery section.

---

### Confirmed by sources
- Architecture and data flow: [Pub/Sub Architecture](https://cloud.google.com/pubsub/docs/overview)
- Metrics reference: [GCP Pub/Sub Metrics](https://cloud.google.com/monitoring/api/metrics_gcp#gcp-pubsub)
- Troubleshooting guides: [Topic Troubleshooting](https://cloud.google.com/pubsub/docs/topic-troubleshooting), [Pull Troubleshooting](https://cloud.google.com/pubsub/docs/pull-troubleshooting), [Push Troubleshooting](https://cloud.google.com/pubsub/docs/push-troubleshooting)

### Best-practice inference
- Latency thresholds (p99 < 50ms) based on GCP SLA and common production baselines.
- Dead-letter near zero as health indicator is standard messaging practice.


---

# Google Cloud Pub/Sub - Key Concepts

## Glossary (>= 20 terms)

| Term | Definition | Operational meaning | Dashboard section affected |
|---|---|---|---|
| **Topic** | Named resource to which publishers send messages. | Primary publish-side entity. Group metrics by topic_id. | Publishing Performance |
| **Subscription** | Named resource representing the stream of messages from a topic to a subscriber. | Primary consume-side entity. Most operational metrics are per-subscription. | Subscription Health, Push Delivery, Pull Delivery |
| **Publisher** | Client application that creates and sends messages to a topic. | Source of publish load. Monitor send_request_count and latency. | Publishing Performance |
| **Subscriber** | Client application that receives messages from a subscription. | Consumer of messages. Health reflected in ack rates and backlog. | Subscription Health |
| **Message** | Data + optional attributes published to a topic. Max 10 MB. | Unit of work. Size affects byte_cost and throughput metrics. | Publishing Performance, Throughput |
| **Acknowledge (Ack)** | Subscriber confirms message processing. Removes from backlog. | Core delivery guarantee. Failed acks cause redelivery. | Subscription Health |
| **Ack Deadline** | Time a subscriber has to ack before redelivery. Default 10s, max 600s. | Too short = spurious redelivery; too long = slow failure detection. | Subscription Health |
| **Backlog** | Undelivered messages waiting in a subscription. | Primary health signal. Growing backlog = consumer can't keep up. | Subscription Health |
| **Pull Delivery** | Subscriber actively requests messages via Pull or StreamingPull RPC. | Most common pattern for server-side consumers. | Pull Delivery |
| **Push Delivery** | Pub/Sub sends messages to a subscriber's HTTPS endpoint. | Used for serverless (Cloud Run, Cloud Functions). | Push Delivery |
| **Streaming Pull** | Long-lived bidirectional gRPC stream for low-latency pull delivery. | Preferred pull method. Connection stability matters. | Pull Delivery |
| **Dead Letter Topic (DLT)** | Topic where unprocessable messages are forwarded after max delivery attempts. | Safety net. Rising DLT count = processing failures. | Dead Letter & Errors |
| **Message Ordering** | Delivers messages with same ordering key in publish order. | Adds head-of-line blocking risk per ordering key. | Subscription Health |
| **Exactly-Once Delivery** | Guarantees each message delivered and acked exactly once (pull only). | Adds overhead; uses acknowledgment IDs for dedup. | Subscription Health |
| **Retained Acked Messages** | Acknowledged messages kept for replay via Seek. | Storage cost; enables replay/reprocessing. | Subscription Health |
| **Seek** | Rewind or fast-forward subscription to a timestamp or snapshot. | Operational tool for replaying or skipping messages. | Subscription Health |
| **Snapshot** | Point-in-time capture of subscription backlog state. | Used for seek operations. Has its own metrics. | Snapshots |
| **Flow Control** | Client-side mechanism to limit outstanding messages. | Prevents OOM on subscriber. Affects throughput. | Pull Delivery |
| **Push Backoff** | Exponential delay Pub/Sub applies when push endpoint returns errors. 100ms-60s. | Protects failing endpoints but delays delivery. | Push Delivery |
| **Subscription Filter** | Attribute-based filter; non-matching messages auto-acked. | Reduces processing load but still incurs publish cost. | Subscription Health |
| **Schema** | Protobuf or Avro schema associated with a topic for message validation. | Publish rejects on schema mismatch (INVALID_ARGUMENT). | Publishing Performance |
| **Single Message Transform (SMT)** | Lightweight message transformation before delivery. | Failures reject entire publish batch. | Publishing Performance |
| **BigQuery Subscription** | Writes messages directly to BigQuery table. | No subscriber code needed. Has unique delivery metrics. | Subscription Health |
| **Cloud Storage Subscription** | Writes messages to GCS as batched files. | Batch-oriented delivery. Has file-specific metrics. | Subscription Health |

## Concept Map (>= 25 lines)

```
Publisher -> publishes to -> Topic (topic is the entry point for all messages)
Topic -> fans out to -> Subscription(s) (1:N fan-out; each subscription gets all messages)
Subscription -> delivers to -> Subscriber (via pull, streaming pull, push, BigQuery, or GCS)
Subscription -> has -> Backlog (undelivered messages waiting for ack)
Subscription -> has -> Ack Deadline (time before message redelivery)
Subscription -> optionally has -> Dead Letter Topic (unprocessable messages forwarded here)
Subscription -> optionally has -> Filter (auto-acks non-matching messages)
Subscription -> optionally has -> Retry Policy (exponential backoff for nacks)
Subscription -> optionally has -> Message Ordering (ordered delivery per ordering key)
Subscription -> optionally has -> Exactly-Once Delivery (dedup for pull subscriptions)
Subscription -> can be -> Pull, Push, BigQuery, or Cloud Storage type
Pull Subscription -> uses -> StreamingPull RPC (preferred, long-lived gRPC stream)
Pull Subscription -> uses -> Pull RPC (legacy, polling-based)
Push Subscription -> sends to -> HTTPS Endpoint (must respond with 2xx to ack)
Push Subscription -> subject to -> Push Backoff (exponential delay on errors)
Topic -> optionally has -> Schema (Protobuf or Avro validation)
Topic -> optionally has -> Message Retention (retains messages 10min-31 days)
Topic -> optionally has -> SMT (transforms messages before delivery)
Message -> has -> Data + Attributes (attributes used for filtering/routing)
Message -> has -> Ordering Key (optional; enables ordered delivery)
Dead Letter Topic -> is a -> regular Topic (can have its own subscriptions for analysis)
Dead Letter Topic -> tracks -> max delivery attempts (5-100, default 5)
Backlog -> measured by -> num_undelivered_messages + oldest_unacked_message_age
Snapshot -> captures -> Subscription backlog state (for seek/replay)
Seek -> rewinds/fast-forwards -> Subscription position (timestamp or snapshot)
Topic metrics -> scoped by -> project_id, topic_id
Subscription metrics -> scoped by -> project_id, subscription_id
Push metrics -> additionally scoped by -> response_code, response_class
```

## Entities and Dimensions (>= 12)

| Dimension | Description | Why useful | Cardinality risk | Safe top-N | Do NOT group-by |
|---|---|---|---|---|---|
| `project_id` | GCP project containing the resource | Multi-project visibility | Low (bounded by org) | 10 | |
| `topic_id` | Topic name | Per-topic publish metrics | Medium (user-defined) | 20 | |
| `subscription_id` | Subscription name | Per-subscription consume metrics | Medium (user-defined) | 20 | |
| `response_code` | HTTP/gRPC response code on requests | Error breakdown (200, 400, 403, 429, 500, etc.) | Low (~20 codes) | 10 | |
| `response_class` | Response class (ack, deadline_exceeded, remote_server_4xx, etc.) | Push health categorization | Low (~8 classes) | 10 | |
| `delivery_type` | Pull, push, BigQuery, Cloud Storage | Subscription delivery mode | Very low (4 values) | 4 | |
| `ordering_key` | Message ordering key | Head-of-line blocking diagnosis | HIGH | | Yes - unbounded user-defined values |
| `message_id` | Unique message identifier | | EXTREME | | Yes - unique per message |
| `region` | GCP region where messages are stored | Regional health analysis | Low (~30 regions) | 10 | |
| `ack_type` | Type of ack operation | Ack behavior analysis | Very low | 5 | |
| `subtype` | Specific operation subtype (e.g., `throttled`, `sent`, `filtered`) | Fine-grained throughput analysis | Low | 5 | |
| `cloud_account_id` | GCP project number (numeric) | Cross-project correlation | Low | 10 | |
| `dead_letter_topic_id` | Dead letter destination topic | Dead letter routing | Low | 10 | |

## Tsuga Field Mapping Table

| Vendor / GCP Dimension | Recommended Tsuga context.* key | Must-exist vs Optional | Notes |
|---|---|---|---|
| `project_id` | `context.cloud.account.id` or `context.project_id` | Must-exist | Primary ownership boundary |
| `topic_id` | `context.topic_id` | Must-exist (topic metrics) | Core entity for publish metrics |
| `subscription_id` | `context.subscription_id` | Must-exist (subscription metrics) | Core entity for consume metrics |
| `response_code` | `context.response_code` | Optional | Present on request-count metrics |
| `response_class` | `context.response_class` | Optional | Present on push metrics |
| `delivery_type` | `context.delivery_type` | Optional | Differentiates pull/push/BQ/GCS |
| `region` | `context.cloud.region` | Optional | Regional breakdown |
| `subtype` | `context.subtype` | Optional | Operation subtypes |
| `env` | `context.env` | Must-exist (Tsuga convention) | Unknown if populated for GCP integrations |
| `team` | `context.team` | Must-exist (Tsuga convention) | Unknown if populated for GCP integrations |

**Unknown:** Exact Tsuga context field names for GCP integration dimensions. The GCP integration may map `project_id` -> `context.project_id` or `context.cloud.account.id`. Stage 2 discovery will resolve. Added to 11_unknowns.

---

### Confirmed by sources
- Topic/Subscription model: [Pub/Sub Overview](https://cloud.google.com/pubsub/docs/overview)
- Subscription properties (ack deadline, DLT, filters, ordering, exactly-once): [Subscription Properties](https://cloud.google.com/pubsub/docs/subscription-properties)
- Push delivery and backoff: [Push Subscriptions](https://cloud.google.com/pubsub/docs/push)
- Metric dimensions (response_code, response_class): [Pub/Sub Metrics](https://cloud.google.com/monitoring/api/metrics_gcp#gcp-pubsub)
- Schemas and SMT: [Topic Troubleshooting](https://cloud.google.com/pubsub/docs/topic-troubleshooting)

### Best-practice inference
- Tsuga context.* field mapping inferred from common GCP integration patterns.
- Cardinality assessments inferred from typical production environments.
- `context.env` and `context.team` as must-exist fields is Tsuga convention, not GCP-specific.


---

# Google Cloud Pub/Sub - Golden Signals

## Traffic

**What it means for Pub/Sub:**
Message throughput - both publish-side (messages/bytes into topics) and consume-side (messages delivered to subscribers). Traffic is the fundamental indicator of system utilization.

**Typical causes when it degrades:**
- Publisher application failures or deployments reducing publish rate
- Subscriber scaling down or crashing, reducing consumption rate
- Quota exhaustion throttling publish or subscribe operations
- Network issues between publishers/subscribers and GCP endpoints

**Best telemetry sources:**
- `topic/send_message_operation_count` (publish throughput)
- `topic/send_byte_count` (publish bytes)
- `subscription/sent_message_count` (delivery throughput)
- `subscription/byte_cost` (delivery bytes)
- `subscription/pull_message_operation_count` (pull operations)
- `subscription/streaming_pull_message_operation_count` (streaming pull operations)

**What people page on:**
- Sudden drop in publish rate with no planned maintenance
- Delivery rate dropping while backlog grows (consumers failing)
- Unexpected zero-traffic periods on critical topics

**Section questions:**
1. Is the expected volume of messages being published? (Publishing Performance)
2. Are subscribers consuming messages at the expected rate? (Subscription Health)
3. How does traffic distribute across topics and subscriptions? (Throughput)

---

## Errors

**What it means for Pub/Sub:**
Failed operations - publish rejections, delivery failures, dead-letter escalations, expired ack deadlines, and push endpoint errors.

**Typical causes when it degrades:**
- Schema validation failures rejecting publishes (INVALID_ARGUMENT)
- Push endpoint returning 4xx/5xx or timing out
- Subscriber nacking messages or letting ack deadlines expire
- Quota or permission errors (RESOURCE_EXHAUSTED, PERMISSION_DENIED)
- KMS key issues causing FAILED_PRECONDITION on encrypted topics
- Dead letter threshold reached on unprocessable messages

**Best telemetry sources:**
- `topic/send_request_count` grouped by `response_code` (publish errors)
- `subscription/push_request_count` grouped by `response_class` (push errors)
- `subscription/dead_letter_message_count` (unprocessable messages)
- `subscription/expired_ack_deadlines_count` (subscriber too slow or crashed)
- `subscription/exactly_once_warning_count` (exactly-once delivery issues)

**What people page on:**
- Sustained publish error rate above baseline
- Dead letter message count rising (messages cannot be processed)
- Push endpoint returning non-ack responses persistently
- Expired ack deadlines accelerating (subscriber health issue)

**Section questions:**
1. Are publishes succeeding without errors? (Publishing Performance)
2. Are push endpoints healthy and responding correctly? (Push Delivery)
3. Are messages being dead-lettered or failing delivery? (Dead Letter & Errors)

---

## Latency

**What it means for Pub/Sub:**
Time from publish to subscriber delivery, and the age of the oldest unprocessed message. For push subscriptions, also the endpoint response time.

**Typical causes when it degrades:**
- Consumer processing slower than publish rate (backlog age grows)
- Push endpoint slow to respond (high push_request_latencies)
- Publisher-side latency from client config issues (batch settings, network)
- Flow control throttling on subscriber side
- Message ordering causing head-of-line blocking
- Exactly-once delivery adding acknowledgment overhead

**Best telemetry sources:**
- `topic/send_request_latencies` (publish-side latency distribution)
- `subscription/oldest_unacked_message_age` (end-to-end delivery lag)
- `subscription/push_request_latencies` (push endpoint response time)
- `subscription/delivery_latency_health_score` (composite health 0-1)

**What people page on:**
- `oldest_unacked_message_age` exceeding SLO threshold (minutes to hours)
- Publish latency p95+ sustained above 100ms
- Push request latency exceeding ack deadline (causes redelivery)
- Delivery latency health score dropping below 0.5

**Section questions:**
1. Is publish latency within acceptable bounds? (Publishing Performance)
2. How old is the oldest unprocessed message per subscription? (Subscription Health)
3. Are push endpoints responding within the ack deadline? (Push Delivery)

---

## Saturation

**What it means for Pub/Sub:**
How close the system is to operational limits - backlog size, quota utilization, and resource constraints on the subscriber side.

**Typical causes when it degrades:**
- Subscriber throughput < publish throughput (backlog accumulation)
- Approaching Pub/Sub quotas (publish rate, subscription count, message size)
- Retained acknowledged messages consuming storage
- Too many outstanding messages per subscriber (flow control limits)

**Best telemetry sources:**
- `subscription/num_undelivered_messages` (backlog depth)
- `subscription/backlog_bytes` (backlog size)
- `subscription/num_outstanding_messages` (in-flight to subscriber)
- `subscription/num_retained_acked_messages` (retained for replay)
- `subscription/retained_acked_bytes` (retained storage)
- `topic/num_unacked_messages_by_region` (regional backlog)

**What people page on:**
- Backlog growing unbounded (consumer not keeping up)
- Backlog bytes approaching storage cost thresholds
- Outstanding messages near flow control limits

**Section questions:**
1. Is the subscription backlog stable or growing? (Subscription Health)
2. How much storage is consumed by retained messages? (Capacity & Retention)
3. Are any subscriptions approaching operational limits? (Capacity & Retention)

---

### Confirmed by sources
- Metrics and their meaning: [GCP Pub/Sub Metrics](https://cloud.google.com/monitoring/api/metrics_gcp#gcp-pubsub)
- Monitoring best practices: [Monitor Pub/Sub](https://cloud.google.com/pubsub/docs/monitoring)
- Push troubleshooting and response classes: [Push Troubleshooting](https://cloud.google.com/pubsub/docs/push-troubleshooting)
- Autoscaling signals (backlog): [Metrics Autoscaling Best Practices](https://cloud.google.com/pubsub/docs/metrics-autoscaling-best-practices)

### Best-practice inference
- Latency thresholds (p95 < 100ms publish) based on production experience.
- Delivery latency health score < 0.5 as page-worthy is inferred (score is 0-1).
- Flow control saturation signals inferred from client library documentation.


---

# Google Cloud Pub/Sub Section Notes & Playbooks

---

## Part 1: Overview Mission Note

**Google Cloud Pub/Sub**
Fully managed messaging service for event-driven architectures.
GCP integration, all topics and subscriptions.

[Pub/Sub Docs](https://cloud.google.com/pubsub/docs/overview) | [Monitoring Guide](https://cloud.google.com/pubsub/docs/monitoring) | [Deep Dive Dashboard](#)

---

## Part 2: Section Explanation Notes

### # Publishing - Are messages being published successfully?

### So what?
**Healthy:** Publish rate matches expected application throughput, error rate near zero, p95 latency under 50ms.
**Concerning:** Error rate rising AND latency spiking = likely quota exhaustion or backend issue. Error rate rising but latency normal = schema validation or permission failures (check response_code breakdown).
**Gotcha:** `send_request_latencies` is in **microseconds**, not milliseconds. A value of 50,000 = 50ms, which is fine.

### Now what?
- Check **Publish Requests by Response Code** for error type breakdown
- If RESOURCE_EXHAUSTED: check quota dashboard and consider requesting increase
- If INVALID_ARGUMENT: check schema configuration and recent topic changes

---

### # Subscription Health - Are subscribers keeping up with message delivery?

### So what?
**Healthy:** Backlog near zero or stable, oldest unacked message age under 60s, delivery health score near 1.0.
**Concerning:** Backlog growing AND oldest message age climbing = consumers falling behind. Backlog stable but oldest age high = some messages stuck (possibly ordering key head-of-line blocking or poison messages).
**Gotcha:** `num_undelivered_messages` is per-subscription, not per-topic. Two subscriptions on the same topic can have wildly different backlogs. Don't average `oldest_unacked_message_age`; use max to find the worst subscription.

### Now what?
- Check **Top Subscriptions by Backlog** to find the lagging subscription
- Check **Expired Ack Deadlines** to see if subscriber is crashing mid-processing
- If backlog is growing: verify subscriber instances are running and scaled appropriately

---

### # Push Delivery - Are push endpoints healthy and responding?

### So what?
**Healthy:** Push success rate >99%, push latency p95 under the ack deadline, response_class is overwhelmingly "ack".
**Concerning:** Success rate dropping = endpoint issues. `deadline_exceeded` responses = endpoint too slow. `remote_server_5xx` = endpoint errors. `unreachable` = connectivity failure or bad URL.
**Gotcha:** Push backoff (100ms-60s exponential) kicks in when endpoints return errors. During backoff, delivery rate drops dramatically even after the endpoint recovers. Recovery is gradual.

### Now what?
- Check **Push Requests by Response Class** for the error type
- If deadline_exceeded: verify endpoint can respond within ack deadline; consider increasing deadline
- If unreachable: verify endpoint URL and network connectivity

---

### # Pull Delivery - Are pull and streaming pull subscribers active?

### So what?
**Healthy:** Pull/streaming pull request rate stable, response codes predominantly success.
**Concerning:** Pull request rate dropping to zero = subscriber disconnected. Streaming pull errors increasing = connection instability (network issues, subscriber crashes).
**Gotcha:** Streaming pull connections can show occasional UNAVAILABLE or DEADLINE_EXCEEDED errors during normal operation. The client library handles reconnection automatically. Concern only when errors dominate and backlog grows.

### Now what?
- Check **Streaming Pull Responses by Code** for error patterns
- If subscriber appears disconnected: check application logs and deployment status
- If errors rising: check network connectivity between subscriber and Pub/Sub endpoint

---

### # Errors & Dead Letters - Are messages failing delivery permanently?

### So what?
**Healthy:** Dead letter rate zero, expired ack deadlines near zero, no exactly-once warnings.
**Concerning:** Dead letter rate > 0 sustained = messages permanently failing. Expired ack deadlines climbing = subscriber can't process fast enough or is crashing. Exactly-once warnings = potential duplicate delivery.
**Gotcha:** `dead_letter_message_count` requires DLT to be configured. Without it, unprocessable messages are redelivered forever (no metric signal). A small number of dead letters during deployments is expected.

### Now what?
- Check **Top Subscriptions by Dead Letters** to identify affected subscription
- Inspect dead letter topic for message patterns (malformed data, missing fields)
- If expired ack deadlines high: consider increasing ack deadline or optimizing processing

---

### # Capacity & Retention - How much storage is consumed and is backlog bounded?

### So what?
**Healthy:** Backlog bytes stable or decreasing, retained storage within budget, drain time under 10 minutes.
**Concerning:** Backlog bytes growing continuously = storage cost rising and consumer falling behind. Retained acked bytes growing = historical storage accumulating (charges after 24h).
**Gotcha:** Retained acked messages incur additional storage charges after 24 hours. If you enabled "retain acknowledged messages" for replay capability, monitor the storage cost.

### Now what?
- Check **Top Subscriptions by Backlog Bytes** for the largest consumers
- If drain time is high: scale up subscribers or investigate processing bottleneck
- If retained storage is growing: review retention policy and disable if replay not needed

---

### # Throughput - How are operations distributed across the system?

### So what?
**Healthy:** Ack rate tracks delivery rate, ModAck ratio under 50%, byte cost proportional to message volume.
**Concerning:** ModAck ratio very high (>80%) = subscribers consistently needing more time. Low ack rate relative to sent rate = redelivery loop (messages sent, not acked, resent).
**Gotcha:** ModAck (modify ack deadline) is normal and healthy. Client libraries extend deadlines automatically for messages being processed. A 10-30% ratio is typical.

### Now what?
- Check **ModAck to Sent Ratio** for trend
- If ModAck ratio climbing: increase ack deadline at the subscription level
- If ack rate << sent rate: investigate subscriber health (crashing, slow processing, nacking)

---

### # Snapshots - What is the state of subscription snapshots?

### So what?
**Healthy:** Snapshot message counts stable, oldest message age within retention period.
**Concerning:** Snapshot size growing large = potential seek operations will replay many messages. Oldest message age approaching retention limit = snapshot may become invalid.
**Gotcha:** Snapshots expire when the oldest message in the snapshot exceeds the message retention duration (default 7 days). An expired snapshot cannot be used for Seek.

### Now what?
- If snapshot is large and approaching age limit: decide whether to refresh or delete
- Snapshots are operational tools; they should not accumulate indefinitely

---

## Part 3: Cause-Effect Triage Chains (>= 20)

1. If **Backlog Messages (count)** is rising steadily -> check **Delivery Rate (msg/s)** -> if delivery rate is dropping, check subscriber health -> likely cause: subscriber pods crashing or scaled down -> scale up subscribers. (Confirmed)
2. If **Oldest Unacked Message Age (s)** is climbing -> check **Top Subscriptions by Backlog** -> identify the lagging subscription -> check **Expired Ack Deadlines (msg/s)** -> likely cause: subscriber too slow or crashing. (Confirmed)
3. If **Publish Error Rate (%)** spikes -> check **Publish Requests by Response Code** -> if RESOURCE_EXHAUSTED -> likely cause: quota limit hit -> request quota increase. (Confirmed)
4. If **Publish Error Rate (%)** shows INVALID_ARGUMENT -> check recent topic schema changes -> likely cause: schema mismatch between publisher and topic -> update publisher or schema. (Confirmed)
5. If **Push Success Rate (%)** drops below 99% -> check **Push Requests by Response Class** -> if deadline_exceeded -> check **Push Latency p95** -> likely cause: slow endpoint -> optimize endpoint or increase ack deadline. (Confirmed)
6. If **Push Requests by Response Class** shows `unreachable` -> check endpoint URL and network -> likely cause: endpoint down or misconfigured URL -> fix endpoint availability. (Confirmed)
7. If **Push Requests by Response Class** shows `remote_server_5xx` -> check endpoint application logs -> likely cause: endpoint application error -> fix application. (Confirmed)
8. If **Dead Letter Rate (msg/s)** > 0 sustained -> check **Top Subscriptions by Dead Letters** -> inspect dead letter topic messages -> likely cause: poison messages or downstream failure -> fix processing logic or downstream service. (Confirmed)
9. If **Expired Ack Deadlines (msg/s)** is climbing -> check subscriber CPU/memory -> check **ModAck Rate (msg/s)** -> if ModAck also high, subscriber is trying but too slow -> likely cause: processing bottleneck -> optimize processing or increase ack deadline. (Mixed)
10. If **Delivery Health Score** drops below 0.5 -> check **Oldest Unacked Message Age** and **Backlog Messages** -> identify contributing subscription -> likely cause: systemic delivery issues -> investigate subscriber and push endpoint health. (Confirmed)
11. If **Streaming Pull Responses by Code** shows persistent errors -> check network connectivity -> check subscriber application logs -> likely cause: network issues or subscriber misconfiguration -> fix connectivity. (Inference)
12. If **Publish Rate (msg/s)** drops to zero unexpectedly -> check publisher application health -> check GCP service status -> likely cause: publisher crash or GCP outage -> restart publisher or wait for GCP recovery. (Inference)
13. If **Backlog Messages** is zero but **Oldest Unacked Message Age** is non-zero -> check for stuck messages -> likely cause: ordering key head-of-line blocking or flow control -> investigate ordering key distribution or flow control settings. (Inference)
14. If **Backlog Size (bytes)** is growing but **Backlog Messages** is stable -> likely cause: message sizes increasing -> check **Publish Throughput (KB/s)** trend -> investigate why messages are larger. (Inference)
15. If **Total Retained Storage (MB)** is growing continuously -> check **Retained Acked Messages Over Time** -> likely cause: retain-acked-messages enabled without cleanup -> review retention policy. (Inference)
16. If **Est. Backlog Drain Time (s)** is increasing -> check **Ack Rate (msg/s)** trend -> if ack rate declining, subscriber throughput is dropping -> likely cause: subscriber degradation -> investigate subscriber health. (Inference)
17. If **ModAck to Sent Ratio (%)** exceeds 80% -> check message processing time -> likely cause: ack deadline too short for processing duration -> increase ack deadline. (Inference)
18. If **Pull Request Rate (req/s)** is high but **Backlog Messages** is growing -> check response codes on pull requests -> if errors present -> likely cause: pull errors preventing message delivery -> investigate error type. (Inference)
19. If **Publish Latency p95 (ms)** spikes -> check publisher client config -> check GCP region health -> likely cause: client-side batching issues or GCP regional degradation -> adjust batch settings or failover region. (Mixed)
20. If **Exactly-Once Warnings Over Time** is non-zero -> check subscriber ack patterns -> likely cause: slow acking causing redelivery attempts before ack processed -> optimize subscriber ack timing. (Inference)
21. If **Byte Cost Over Time** spikes -> check **Top Topics by Publish Rate** -> likely cause: burst traffic or new publisher -> verify traffic is expected. (Inference)

---

## Part 4: Operational Playbooks (6-10)

### Playbook 1: Growing Subscription Backlog
**Trigger:** **Backlog Messages (count)** trending upward, **Oldest Unacked Message Age (s)** > 300s
**Decision rule:** If backlog growth rate is positive for > 5 minutes, investigate subscriber capacity.
**Steps:**
1. Check **Top Subscriptions by Backlog** to identify affected subscriptions
2. Check **Delivery Rate (msg/s)** to confirm consumption rate has dropped
3. Check **Expired Ack Deadlines (msg/s)** for subscriber failure signals
4. Check **Ack Rate Over Time by Subscription** for the affected subscription
5. Check subscriber application logs and deployment status
6. If subscriber healthy but slow: check **ModAck to Sent Ratio** for processing time issues
7. Scale up subscribers or increase processing capacity
**Likely causes:**
- Subscriber deployment/rollback reduced instance count
- Downstream dependency failure causing slow processing
- Message volume spike exceeding subscriber capacity
- Subscriber crash loop
**Next actions:**
- Scale subscriber instances
- Check downstream service health
- If ordering enabled: check for stuck ordering keys
- Consider temporarily pausing non-critical subscriptions
**Label:** Confirmed

### Playbook 2: Publish Failures
**Trigger:** **Publish Error Rate (%)** > 0.1%, **Publish Requests by Response Code** shows non-success codes
**Decision rule:** Any sustained publish error rate warrants immediate investigation as it means data loss risk.
**Steps:**
1. Check **Publish Requests by Response Code** for error type breakdown
2. If RESOURCE_EXHAUSTED: check GCP quotas dashboard
3. If INVALID_ARGUMENT: check topic schema configuration and recent changes
4. If FAILED_PRECONDITION: check KMS key status for encrypted topics
5. Check **Top Topics by Publish Rate** to identify affected topics
6. Check publisher application logs for client-side errors
**Likely causes:**
- Quota exhaustion (publish rate, message size, topic count)
- Schema validation failure after schema update
- KMS key disabled or inaccessible
- Permission changes (IAM)
**Next actions:**
- Request quota increase if needed
- Roll back schema changes
- Re-enable KMS key
- Verify IAM permissions
**Label:** Confirmed

### Playbook 3: Push Endpoint Degradation
**Trigger:** **Push Success Rate (%)** < 99%, **Push Requests by Response Class** shows non-ack responses
**Decision rule:** Push success rate below 99% for > 2 minutes indicates endpoint health issue.
**Steps:**
1. Check **Push Requests by Response Class** for dominant error type
2. Check **Push Latency p95** to see if endpoint is slow (deadline_exceeded)
3. Check **Top Subscriptions by Push Errors** to identify affected subscriptions
4. Check **Backlog Messages** to assess impact on delivery
5. Verify endpoint availability and application health
6. Check **Oldest Unacked Message Age** to assess delivery lag
**Likely causes:**
- Endpoint application errors (5xx)
- Endpoint timeout (processing slower than ack deadline)
- Endpoint unreachable (network, DNS, URL misconfiguration)
- Authentication/permission failure (4xx)
**Next actions:**
- Fix endpoint application errors
- Increase ack deadline if endpoint needs more processing time
- Verify endpoint URL and network path
- Check endpoint authentication configuration
**Label:** Confirmed

### Playbook 4: Dead Letter Escalation
**Trigger:** **Dead Letter Rate (msg/s)** > 0 sustained for > 5 minutes
**Decision rule:** Any sustained dead lettering means messages are permanently failing and need investigation.
**Steps:**
1. Check **Top Subscriptions by Dead Letters** to identify affected subscriptions
2. Check **Expired Ack Deadlines (msg/s)** on same subscriptions
3. Check subscription's max delivery attempts configuration
4. Inspect messages in the dead letter topic for patterns
5. Check subscriber application logs for processing errors
**Likely causes:**
- Poison messages (malformed data, unexpected format)
- Downstream service failure causing consistent processing errors
- Bug in subscriber processing logic
- Max delivery attempts too low for transient errors
**Next actions:**
- Inspect dead letter messages for common patterns
- Fix subscriber processing logic or downstream dependency
- Consider increasing max delivery attempts for transient errors
- Set up alerting on dead letter topic
**Label:** Mixed

### Playbook 5: High Publish Latency
**Trigger:** **Publish Latency p95 (ms)** > 100ms sustained
**Decision rule:** p95 publish latency above 100ms for > 5 minutes indicates publisher or service issue.
**Steps:**
1. Check **Publish Latency Over Time** for pattern (gradual vs sudden)
2. Check **Publish Rate (msg/s)** for correlation with load changes
3. Check **Publish Requests by Response Code** for errors (errors inflate latency)
4. Check **Top Topics by Publish Rate** to see if specific topics are affected
5. Check publisher client configuration (batch settings, retry config)
**Likely causes:**
- Client-side batching configuration issues
- Publisher creating new clients per request instead of reusing
- GCP regional degradation
- High message sizes increasing network transfer time
**Next actions:**
- Review and optimize publisher batch settings
- Ensure single publisher client per topic per application
- Consider message compression for large payloads
- Check GCP status page for regional issues
**Label:** Mixed

### Playbook 6: Exactly-Once Delivery Issues
**Trigger:** **Exactly-Once Warnings Over Time** count rising
**Decision rule:** Investigate if warnings are sustained; occasional warnings during subscriber restarts are normal.
**Steps:**
1. Check which subscriptions have exactly-once enabled
2. Check **Expired Ack Deadlines** on those subscriptions
3. Check **Oldest Unacked Message Age** for the affected subscriptions
4. Check subscriber ack patterns and processing time
5. Verify subscriber is using the correct client library version for exactly-once support
**Likely causes:**
- Subscriber acking too slowly (ack deadline expiring before ack processed)
- Network issues causing ack delivery delays
- Client library version doesn't fully support exactly-once semantics
**Next actions:**
- Increase ack deadline
- Upgrade client library
- Verify network connectivity
- Consider if exactly-once is truly needed (at-least-once + idempotent processing may suffice)
**Label:** Inference

### Playbook 7: Storage Cost Growth
**Trigger:** **Total Retained Storage (MB)** or **Backlog Size (bytes)** growing continuously
**Decision rule:** If storage growth is unbounded over 24 hours, investigate cause and cost impact.
**Steps:**
1. Check **Top Subscriptions by Backlog Bytes** for largest consumers
2. Check **Retained Acked Messages Over Time** for retained storage growth
3. Check **Est. Backlog Drain Time** for affected subscriptions
4. Check subscription retention policy configuration
5. Check if any subscriptions are abandoned (no active subscribers)
6. Estimate cost impact based on GCP pricing
**Likely causes:**
- Subscriber not consuming (abandoned subscription)
- Consumer slower than publisher (growing backlog)
- Retained acked messages accumulating without cleanup
- Message retention period too long for use case
**Next actions:**
- Delete abandoned subscriptions
- Scale up consumers for active subscriptions
- Reduce retention period if full retention not needed
- Disable retain-acked-messages if replay not required
**Label:** Inference


---

# Google Cloud Pub/Sub - Caveats & Footguns

## High-cardinality dimensions to avoid

- **[publishing-performance, subscription-health]** Do NOT group-by `ordering_key`. Ordering keys are user-defined and can have unbounded cardinality (one per user, per session, etc.). Use `topic_id` or `subscription_id` instead. (Inference)
- **[publishing-performance]** Do NOT group-by `message_id`. Every message has a unique ID. Grouping by it produces one series per message with zero analytical value. ([Pub/Sub Docs](https://cloud.google.com/pubsub/docs/overview))
- **[subscription-health, pull-delivery]** Combining `subscription_id` and `response_code` group-bys on timeseries can produce high series counts in environments with many subscriptions. Use top-list instead, or group by only one dimension. (Inference)
- **[publishing-performance]** `topic_id` cardinality depends on the application. Some teams create topics dynamically (per-tenant, per-event-type). If topic count exceeds 100, use top-N=10 and rely on top-list for the full picture. (Inference)

## Misleading metrics and wrong aggregations

- **[subscription-health]** `num_undelivered_messages` is NOT the same as "messages in the topic." It counts only messages that have not been delivered to THIS subscription. Different subscriptions on the same topic can have different backlog sizes. Do not sum across subscriptions to get "total topic backlog." ([Pub/Sub Monitoring](https://cloud.google.com/pubsub/docs/monitoring))
- **[subscription-health]** `oldest_unacked_message_age` can spike briefly during Seek operations (rewinding sets the oldest message to the seek target). This is intentional, not an incident. ([Pub/Sub Docs](https://cloud.google.com/pubsub/docs/subscription-properties))
- **[subscription-health]** Do NOT average `oldest_unacked_message_age` across subscriptions. Use `max` to surface the worst-case subscription. Averaging hides the lagging subscription behind healthy ones. (Inference)
- **[throughput-operations]** `byte_cost` does NOT equal actual bytes transferred. It includes operation overhead (attributes, headers) and is used for billing purposes. Do not use it as a bandwidth metric; use `send_byte_count` for actual data volume. ([GCP Pub/Sub Metrics](https://cloud.google.com/monitoring/api/metrics_gcp#gcp-pubsub))
- **[subscription-health]** `sent_message_count` counts messages SENT to subscribers, not messages successfully processed. A message sent but not acked will be resent and counted again. High sent_message_count with low ack_message_count = redelivery storm. ([Pub/Sub Monitoring](https://cloud.google.com/pubsub/docs/monitoring))
- **[push-delivery]** Do NOT use `push_request_latencies` percentile as "message processing time." It measures the time Pub/Sub waits for the endpoint response, which includes network latency + endpoint processing. The metric is in **microseconds**, not milliseconds. ([Push Troubleshooting](https://cloud.google.com/pubsub/docs/push-troubleshooting))

## Unit pitfalls

- **[publishing-performance]** `send_request_latencies` is in **microseconds** (us), not milliseconds. Displaying as ms without conversion makes latency appear 1000x lower than reality. ([GCP Pub/Sub Metrics](https://cloud.google.com/monitoring/api/metrics_gcp#gcp-pubsub))
- **[push-delivery]** `push_request_latencies` is also in **microseconds** (us). Same pitfall as above. ([GCP Pub/Sub Metrics](https://cloud.google.com/monitoring/api/metrics_gcp#gcp-pubsub))
- **[subscription-health]** `oldest_unacked_message_age` is in **seconds**. For display, convert to minutes or hours for ages > 300s to improve readability. (Inference)
- **[capacity-retention]** `backlog_bytes` and `retained_acked_bytes` are in raw bytes. Use data normalizer (B -> KiB/MiB/GiB) for readability. (Inference)

## Sampling/temporality pitfalls

- **[publishing-performance, subscription-health, dead-letter-errors, pull-delivery, push-delivery]** Counter temporality (delta vs cumulative) depends on the Tsuga GCP integration. GCP Cloud Monitoring counters are delta by default (report increments per sampling interval). However, the Tsuga integration may transform them. Stage 2 discovery will confirm whether `per-second` or `rate` is correct. Both options listed in 05. (Inference)
- **[subscription-health]** GCP metrics have a minimum granularity of **60 seconds**. Short-lived backlog spikes (< 1 min) may not appear in the data. Do not expect sub-minute resolution. ([GCP Cloud Monitoring Docs](https://cloud.google.com/monitoring/api/v3/metrics-details))
- **[publishing-performance]** Publish metrics (`send_request_count`, `send_byte_count`) may show **1-3 minute delay** from real time. Do not page on "zero publishes" unless the gap exceeds 5 minutes. ([GCP Pub/Sub Monitoring](https://cloud.google.com/pubsub/docs/monitoring))

## "This looks bad but isn't"

- **[subscription-health]** `oldest_unacked_message_age` jumping from 0 to a few seconds during normal operation is expected. It reflects the processing window between delivery and ack. Concern only if it grows continuously. (Inference)
- **[subscription-health]** `num_outstanding_messages` spiking during a burst is normal. It means the subscriber has received messages and is processing them. Concern only if it stays high AND backlog grows (subscriber holding messages but not acking). (Inference)
- **[dead-letter-errors]** A small number of dead-lettered messages during deployments or schema changes is expected. The dead letter mechanism is working as designed. Concern only if the rate is sustained or increasing. (Inference)
- **[pull-delivery]** `streaming_pull_response_count` with occasional error codes (UNAVAILABLE, DEADLINE_EXCEEDED) is normal. The client library reconnects automatically. Concern only if error responses dominate and backlog grows. ([Pull Troubleshooting](https://cloud.google.com/pubsub/docs/pull-troubleshooting))
- **[throughput-operations]** `mod_ack_deadline_message_count` > 0 is expected and healthy. The client library automatically extends ack deadlines for messages being processed. It becomes concerning only if the ratio to sent messages is very high (>80%). (Inference)

## Optional-feature traps (metrics absent unless X enabled)

- **[dead-letter-errors]** `dead_letter_message_count` requires a dead letter topic to be configured on the subscription. Without DLT, this metric has no data, but messages that exhaust max delivery attempts are simply redelivered forever. ([Subscription Properties](https://cloud.google.com/pubsub/docs/subscription-properties))
- **[dead-letter-errors]** `exactly_once_warning_count` requires exactly-once delivery to be enabled on the subscription. Without it, this metric has no data. Exactly-once is only available for pull subscriptions. ([Subscription Properties](https://cloud.google.com/pubsub/docs/subscription-properties))
- **[push-delivery]** All `push_*` metrics require at least one push subscription. If the environment uses only pull subscriptions, the entire push delivery section will be empty. (Inference)
- **[publishing-performance]** `message_transform_latencies` requires Single Message Transforms (SMT) to be configured on at least one topic. Without SMT, this metric has no data. ([Topic Troubleshooting](https://cloud.google.com/pubsub/docs/topic-troubleshooting))
- **[snapshots]** All `snapshot/*` metrics require snapshots to exist. Snapshots are optional and relatively uncommon. The entire snapshots section may be empty. ([GCP Pub/Sub Metrics](https://cloud.google.com/monitoring/api/metrics_gcp#gcp-pubsub))
- **[capacity-retention]** `retained_acked_bytes` and `num_retained_acked_messages` require "retain acknowledged messages" to be enabled on the subscription. Without it, these metrics are zero. ([Subscription Properties](https://cloud.google.com/pubsub/docs/subscription-properties))


---

