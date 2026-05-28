# kafka Integration Context Bundle

## Metadata
**Technology:** kafka  
**Deployment:** self-hosted  
**Environment:** prod  
**Persona:** SRE Dev and ops  
**Telemetry preference:** mixed  
**Integration scope:** core service only  
**Primary use-case:** reliability and performance

## How to use this bundle
- Use `01_kafka_metrics.csv` as the source of truth for metric semantics, units, and provisional counter math.
- Use `02_kafka_dashboard_plan.yaml` for dashboard structure: sections, widgets, derived signals, gating, and triage content.
- Use `03_kafka_state.yaml` for machine-readable status, assumptions, discovery unknowns, and Stage 2 priorities.
- Use `04_kafka_memory.md` for the human-readable handoff narrative and rationale.
- Stage 2 will create `05_kafka_metric_catalog.csv` as the discovered Tsuga inventory used for reconciliation and deep-dive coverage checks.
- Stage 4 should read this file's `Log intelligence (Stage 4 handoff)` section and `03_kafka_state.yaml` `log_intel` block before designing route processors.

## What it is and what "good" looks like

### Confirmed by sources
- Kafka is a distributed log platform where producers write records to topic partitions and consumers read by offset; broker health depends on partition leadership, replication, and request handling ([Kafka design docs](https://kafka.apache.org/documentation/#design), [Kafka monitoring docs](https://kafka.apache.org/36/documentation/#monitoring)).
- For this environment, live Tsuga metrics confirm rich `kafka.consumer.*` client telemetry plus broker and partition health metrics (`kafka.partition.*`, `kafka.request.*`, `kafka.controller.*`) and workload counters (`kafka_workload_*`) from recent ingestion scans (Tsuga metric search, 2026-02-27).
- "Good" means consumer lag stays bounded, consume throughput tracks produce throughput, rebalance churn remains low, request failures remain low versus total request volume, and partition replication risk (`underReplicated`/`offline`) remains near zero.
- Incident shape 1: consumer lag growth while consume rate drops; start with `consumer-lag-and-progress`.
- Incident shape 2: rebalance/auth churn causing unstable consumption; start with `rebalance-and-coordination`.
- Incident shape 3: broker/partition health regression (offline or under-replicated partitions); start with `broker-and-partition-health`.

### Best-practice inference
- For Kafka operations, consumer lag is usually a higher-value reliability signal than CPU because lag is directly tied to delay and possible retention-window risk.
- In mixed telemetry setups, client-side consumer metrics can be available even when some broker-side dimensions are sparse; section gating should prevent false confidence.
- First responder flow should be: verify lag and throughput balance, then test coordination stability, then confirm broker replication safety.

## Key concepts

### Glossary

| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| Broker | Kafka server node handling partitions and requests | Broker availability and request behavior gate platform reliability | broker-and-partition-health |
| Topic | Named stream of records | Ownership and workload boundaries are usually topic-scoped | request-path-and-workload |
| Partition | Ordered append-only shard of a topic | Lag and replica safety are partition-level phenomena | broker-and-partition-health |
| Leader partition | Replica currently serving reads/writes | Leader instability drives request failures and lag spikes | broker-and-partition-health |
| ISR (in-sync replicas) | Replica set considered caught up to leader | Shrinking ISR raises data-loss/failover risk | broker-and-partition-health |
| Under-replicated partition | Partition with ISR smaller than replication factor | Primary replication-risk signal for paging | broker-and-partition-health |
| Offline partition | Partition lacking an available leader | Direct availability incident indicator | broker-and-partition-health |
| Controller | Broker managing cluster metadata transitions | Controller churn often correlates with instability | broker-and-partition-health |
| Consumer group | Coordinated set of consumers sharing partitions | Group churn and lag determine processing timeliness | consumer-lag-and-progress |
| Consumer lag | Offset difference between latest and committed/processed records | Core user-visible delay signal | consumer-lag-and-progress |
| Rebalance | Partition ownership redistribution among group members | Frequent failed rebalances reduce effective throughput | rebalance-and-coordination |
| Commit | Consumer checkpoint write of processed offset | Commit latency/failure affects replay and duplicate risk | rebalance-and-coordination |
| Fetch | Consumer poll operation for records | Fetch latency/size indicates broker-network and batching health | throughput-and-fetch |
| Throttle | Broker-imposed backpressure delay | Sustained throttling means contention or quota pressure | throughput-and-fetch |
| Request path | End-to-end Kafka protocol request handling | Request failures and latency show broker/client health | request-path-and-workload |
| Produce rate | Records/messages entering Kafka | Compared with consume rate to detect backlog trajectory | request-path-and-workload |
| Consume rate | Records/messages read from Kafka | Falling consume rate with steady produce rate predicts lag growth | consumer-lag-and-progress |
| Retention window | Time/size policy for topic data retention | High lag near retention bounds risks data unavailability for consumers | consumer-lag-and-progress |
| Flush | Log flush behavior to durable storage | Flush latency spikes can precede broker request latency increases | broker-and-partition-health |
| Client ID | Kafka client identity tag | Useful bounded breakdown for noisy or lagging consumers | rebalance-and-coordination |
| Service instance | Runtime instance emitting telemetry | Fast blast-radius pivot when one deployment regresses | availability-health |
| Node ID | Broker numeric identity in client metrics | Useful for routing failures to broker owners | broker-and-partition-health |

### Concept Map

```text
Producer -> writes records to -> Topic partition (why: establishes ingress workload)
Topic partition -> assigns one -> Leader replica (why: serial write/read authority)
Leader replica -> replicates to -> ISR followers (why: durability and failover safety)
ISR shrink -> increases -> under-replicated partitions (why: resilience degradation)
Leader unavailable -> creates -> offline partition (why: direct read/write outage)
Consumer group -> owns -> partition assignments (why: controls parallel processing)
Rebalance -> reassigns -> partitions between consumers (why: keeps group membership coherent)
Failed rebalance -> delays -> steady consumption (why: assignment churn stalls progress)
Commit operation -> advances -> group offset (why: confirms processed progress)
Commit slowdown -> increases -> duplicate/replay exposure (why: checkpoint staleness)
Fetch request -> returns -> record batches (why: governs consumer throughput)
Fetch throttle -> reduces -> effective consume rate (why: quota/backpressure control)
Produce rate > consume rate -> grows -> lag (why: backlog accumulation)
Lag growth -> increases -> end-to-end message delay (why: users see stale processing)
Lag near retention boundary -> risks -> missed processing window (why: old data may expire)
Request failures -> correlate with -> broker/controller instability (why: control/data plane faults)
Controller activity changes -> coincide with -> leadership movement (why: metadata plane churn)
Flush latency increase -> raises -> request latency tail (why: storage pressure propagation)
Client-id skew -> exposes -> bad actor consumers (why: one client can dominate failures)
Service instance dimension -> maps -> deploy rollout impact (why: regressions often version-scoped)
Environment/team filters -> reduce -> incident blast radius ambiguity (why: faster ownership routing)
Partition health + lag + throughput -> form -> triage chain backbone (why: covers correctness and timeliness)
```

### Entities and dimensions

| Entity/Dimension | Why useful | Cardinality risk | Safe top-N | Do NOT group-by guidance |
|---|---|---|---|---|
| `context.env` | Environment scoping | Low | 5 | Keep as dashboard global filter |
| `context.team` | Ownership scoping | Low | 10 | Keep as dashboard global filter |
| `context.service.name` | Service boundary for producer/consumer apps | Medium | 15 | Avoid combining with pod and client-id in same chart |
| `context.service.instance.id` | Pinpoint bad instances quickly | High | 12 | Do not use unbounded in overview |
| `context.client-id` | Consumer/client hot-spot detection | Medium | 12 | Avoid stacking with pod + instance |
| `context.k8s.cluster.name` | Cluster blast radius split | Medium | 8 | Use with env filter |
| `context.k8s.namespace.name` | Namespace ownership split | Medium | 12 | Avoid together with pod and client-id |
| `context.k8s.pod.name` | Pod-level regressions after rollout | High | 10 | Deep dive only |
| `context.host.name` | Host/node affinity checks | Medium | 10 | Prefer service instance when possible |
| `context.node-id` | Broker-specific request path diagnosis | Medium | 10 | Verify availability in Stage 2 before enforcing |
| `context.topic` | Topic-level lag and throughput ownership | High | 15 | Never leave unbounded |
| `context.status` | Success/failure slicing for request path | Low | 6 | Use only where metric supports status |
| `context.scope` | Instrumentation fallback dimension | Low | 10 | Use only as fallback dimension |

### Tsuga field mapping

#### Confirmed by sources
| Vendor/exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| Environment | `context.env` | Must-exist |
| Team | `context.team` | Must-exist |
| Kafka consumer client id | `context.client-id` | Optional but present on many `kafka.consumer.*` metrics (Tsuga metric scan) |
| Service identity | `context.service.name` | Optional but present on many `kafka.consumer.*` and workload metrics (Tsuga metric scan) |
| Service instance | `context.service.instance.id` | Optional but present on many `kafka.consumer.*` metrics (Tsuga metric scan) |
| Topic (workload producer/consumer counters) | `context.topic` | Optional (confirmed on `kafka_workload_*`) |
| Broker node id (some request-size metrics) | `context.node-id` | Optional (observed on selected consumer request metrics) |

#### Best-practice inference
| Vendor/exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| Consumer group id | `context.consumer.group` | Optional; Unknown in current scan |
| Partition id | `context.partition` | Optional; confirmed on consumer lag metrics in Stage 2 discovery |
| Broker id (broker-side namespace) | `context.kafka.broker.id` | Optional; Unknown in current scan |
| Topic (broker-side namespaces) | `context.topic` | Optional; confirmed on consumer lag and workload metrics in Stage 2 discovery |

## Golden signals

### Confirmed by sources
| Signal | Meaning for kafka | Typical degradations | Best telemetry sources | What people page on | Section questions |
|---|---|---|---|---|---|
| Traffic | Balance of produce/consume and request throughput | Producer surge, consumer slowdown, throttling | `kafka_workload_messages_produced_total`, `kafka_workload_messages_consumed_total`, `kafka.request.count`, `kafka.consumer.records_consumed_total` | Produced keeps rising while consumed stalls and lag grows | Are we keeping up with incoming workload? |
| Errors | Request and auth/coordination failure pressure | Broker errors, auth drift, rebalance failures | `kafka.request.failed`, `kafka.consumer.failed_authentication_total`, `kafka.consumer.failed_rebalance_total` | Error ratio climbs or auth failures spike after rollout | Are failures transient noise or systemic? |
| Latency | Commit/fetch/request tails that drive processing delay | Storage pressure, throttling, broker contention | `kafka.consumer.fetch_latency_max`, `kafka.consumer.commit_latency_max`, `kafka.request.time.99p`, `kafka.logs.flush.time.99p` | P99 latency spikes sustained across multiple clients/groups | Is delay from client coordination or broker path? |
| Saturation | Replication and partition health risk surfaces | Under-replicated or offline partitions, controller churn | `kafka.partition.underReplicated`, `kafka.partition.offline`, `kafka.controller.active.count`, `kafka.partition.count` | Non-zero offline partitions or rising under-replication | Are we at risk of availability or durability events? |

### Best-practice inference
- Lag trend is usually the best user-impact proxy, while request counters are leading indicators for platform stress.
- Rebalance failure share is a practical early warning for consumer instability even before large lag appears.
- Combining partition health and request failure ratio reduces false positives from short-lived deploy turbulence.

## Telemetry sources

### Confirmed by sources
| Source type | How collected | What it provides | Pros/cons | Common pitfalls |
|---|---|---|---|---|
| Kafka broker JMX / broker monitoring | Kafka broker exposes operational metrics via JMX integrations ([Kafka monitoring docs](https://kafka.apache.org/36/documentation/#monitoring), [Confluent Kafka monitoring](https://docs.confluent.io/platform/current/kafka/monitoring.html)) | Partition health, request stats, controller metrics | Rich broker-level state / requires broker-side collection and naming normalization | Missing broker metrics often means collection gap, not healthy-zero |
| Kafka client metrics (producer/consumer) via OTel Java instrumentation | OTel Java kafka-clients common instrumentation exports standardized `kafka.consumer.*` / `kafka.producer.*` metrics ([OTel Java kafka metrics README](https://raw.githubusercontent.com/open-telemetry/opentelemetry-java-instrumentation/main/instrumentation/kafka/kafka-clients/kafka-clients-common/library/README.md)) | Lag, rebalance, commit/fetch/request behavior on clients | Strong app-facing signal / may miss broker-only failures |
| OTel Collector Kafka metrics receiver | Collector integration maps Kafka JMX broker metrics to semantic names ([OTel kafkametricsreceiver metadata](https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector-contrib/main/receiver/kafkametricsreceiver/metadata.yaml)) | Broker and partition metrics in OTel model | Good for fleet-standard ingestion / optional metrics may require config |
| Synthetic workload counters | Local workload emitter produces `kafka_workload_*` counters and latency histogram | Produce/consume balance and synthetic latency | Simple balance signal / can diverge from real production traffic |
| Kafka logs | Broker and controller logs from Kafka process/log4j stack ([Confluent platform logging](https://docs.confluent.io/platform/current/monitor/cp-logging.html), [Kafka ops docs](https://kafka.apache.org/36/documentation/#ops)) | Leader election, replication, controller, auth failures | High-fidelity incident context / format varies by deployment |

### Best-practice inference
- "No data" for workload counters often means workload job paused or sandbox profile changed, not broker outage.
- Client-side metrics can remain healthy while broker replication deteriorates; keep broker section independent from client section.
- Counter temporality (delta vs cumulative) must be validated in Stage 2 before final post-function selection.

## Log intelligence (Stage 4 handoff)

### Confirmed by sources

#### Log sources matrix
| Source | Access path | Typical format | Structured vs unstructured | Evidence |
|---|---|---|---|---|
| Broker server log | Kafka broker log file path configured via log4j | Timestamp + level + logger + message text | Unstructured text by default | [Confluent platform logging](https://docs.confluent.io/platform/current/monitor/cp-logging.html), [Kafka ops docs](https://kafka.apache.org/36/documentation/#ops) |
| Controller / broker process stdout | Container stdout/stderr (Kubernetes, Docker) | log4j text unless JSON layout configured | Usually unstructured | [Confluent platform logging](https://docs.confluent.io/platform/current/monitor/cp-logging.html) |
| Optional JSON log layout | log4j2 JSON template layout when enabled | JSON line/object logs | Structured JSON | [Confluent platform logging](https://docs.confluent.io/platform/current/monitor/cp-logging.html) |

#### Known log formats
1. Broker text log (common default):
   - Sample line: `[2026-02-27 00:15:12,771] INFO [ReplicaFetcherManager on broker 2] Removed fetcher for partitions Set(topicA-3) (kafka.server.ReplicaFetcherManager)`
   - Delimiter/shape notes: bracketed timestamp, level token, free-form component section, trailing logger name in parentheses.
   - Timestamp pattern: `YYYY-MM-DD HH:MM:SS,mmm`.
   - Quoting behavior: quoted topic/group names appear inline without fixed JSON keys.
   - Optional fields: broker id, partition list, correlation ids vary by logger.
2. Client/consumer log (application side):
   - Sample line: `2026-02-27 00:16:03.412 WARN  [Consumer clientId=orders-consumer, groupId=orders] Attempt to heartbeat failed since group is rebalancing`
   - Delimiter/shape notes: timestamp + level + context block + message.
   - Timestamp pattern: `YYYY-MM-DD HH:MM:SS.mmm`.
   - Optional fields: `clientId`, `groupId`, `topic`, `partition` may be absent.

#### Candidate query filters for Stage 4
- Precise: `context.service.name:kafka AND (message:*ERROR* OR message:*WARN* OR message:*under-replicated* OR message:*leader election* OR message:*rebalance*)`
  - Rationale: targets high-value reliability events.
  - Risk: depends on consistent `context.service.name` mapping.
- Fallback: `(message:*kafka* OR message:*consumer*) AND (message:*error* OR message:*warn* OR message:*rebalance* OR message:*timeout*)`
  - Rationale: broad capture when structured labels are sparse.
  - Risk: noisier and may capture non-Kafka app logs.

#### Attribute mapping hints
| Raw field | Suggested Tsuga key | Confidence | Notes |
|---|---|---|---|
| timestamp token | `timestamp` | High | Preserve timezone and normalize to UTC |
| log level | `severity_text` | High | Map WARN/ERROR/INFO consistently |
| logger name/class | `context.logger.name` | Medium | Useful for controller vs replica modules |
| broker id (`broker 2`) | `context.node-id` | Medium | Prefer numeric extraction |
| topic-partition token (`topicA-3`) | `context.topic` + `context.partition` | Medium | Requires regex split |
| client id (`clientId=...`) | `context.client-id` | High | Aligns with metric dimension |
| group id (`groupId=...`) | `context.consumer.group` | Medium | Verify availability and naming |
| message body | `message` | High | Keep full text for secondary parsing |

#### Parsing risks
- Broker and app consumer logs can mix formats in the same stream.
- Partition notation (`topic-12`) is ambiguous if topic names contain dashes.
- Multiline Java stack traces require continuation handling.
- Some logs only embed structured fields in message text, not fixed keys.
- Locale/timezone differences across hosts can skew temporal correlation.

### Best-practice inference
- Start with a split route: JSON parse branch first, then text grok fallback.
- Keep initial parser focused on WARN/ERROR/controller/replication patterns, then expand once false positives are controlled.
- Preserve raw message in all branches to allow iterative parser tuning.

## Caveats and footguns
- **[availability-health]** `kafka.controller.active.count` can be non-intuitive in single-controller mode; interpret trend and correlated error signals, not raw value alone. (Inference)
- **[availability-health]** `kafka.brokers` may reflect registration state and can lag real network reachability during controller churn. (Inference)
- **[consumer-lag-and-progress]** Lag metrics can drop during rebalance pauses without true recovery; verify consume rate after rebalance settles. (Inference)
- **[consumer-lag-and-progress]** `records_lag_max` is a tail metric and may spike from one partition while average behavior remains stable. (Inference)
- **[consumer-lag-and-progress]** Lag alone does not indicate data loss risk unless compared to retention window. (Inference)
- **[throughput-and-fetch]** Fetch latency spikes without throughput drop may reflect temporary broker throttling, not sustained outage. (Inference)
- **[throughput-and-fetch]** `fetch_size_avg` can rise during healthy batching optimization; pair with `fetch_latency_max` and lag. (Inference)
- **[throughput-and-fetch]** Request size changes after producer config rollouts can alter throughput interpretation without reliability regression. (Inference)
- **[throughput-and-fetch]** Counter metrics must not be shown as raw cumulative values; use rate/per-second after temporality confirmation. (Inference)
- **[rebalance-and-coordination]** Rebalance frequency can increase during deploys and autoscaling events without lasting incident impact. (Inference)
- **[rebalance-and-coordination]** Failed authentication bursts are often configuration drift and can be localized to one client-id. (Inference)
- **[rebalance-and-coordination]** Commit latency max is a tail signal; use with commit total for stability context. (Inference)
- **[rebalance-and-coordination]** `last_poll_seconds_ago` spikes can indicate stalled consumers but can also appear during controlled maintenance windows. (Inference)
- **[broker-and-partition-health]** `underReplicated` and `offline` values are high-severity even when traffic appears normal. ([Kafka monitoring docs](https://kafka.apache.org/36/documentation/#monitoring))
- **[broker-and-partition-health]** `partition.count` changes during topic lifecycle events can invalidate naive ratio baselines. (Inference)
- **[broker-and-partition-health]** Flush time percentile metrics may be sparse depending on collection config and scrape interval. (Inference)
- **[broker-and-partition-health]** `leaderElection.unclean.count` increments indicate riskier failover behavior and should be treated as exceptional. ([Kafka monitoring docs](https://kafka.apache.org/36/documentation/#monitoring))
- **[request-path-and-workload]** Workload counters (`kafka_workload_*`) may represent test traffic, not all production traffic. (Inference)
- **[request-path-and-workload]** `request.failed` ratio can be skewed by transient retries at startup; inspect sustained windows. (Inference)
- **[request-path-and-workload]** Histogram latency (`kafka_workload_operation_latency_ms`) requires consistent percentile handling; avoid mixing with max-only gauges without labeling. (Inference)
- **[request-path-and-workload]** Topic-level grouping can explode cardinality; keep top-N bounded and use service/team filters first. (Inference)
- **[consumer-lag-and-progress, request-path-and-workload]** Produce-consume imbalance should be interpreted with lag direction, not in isolation, to avoid false alarms during planned backfills. (Inference)

## Confirmed Tsuga prefixes
- `kafka.*` — **CONFIRMED** (119 metrics found in Tsuga scan over 24h, 2026-02-27)
- `kafka.consumer.*` — **CONFIRMED** (86 metrics found in Tsuga scan over 24h, 2026-02-27)
- `kafka.consumer_group.*` — **CONFIRMED** (5 metrics found in Tsuga scan over 24h, 2026-02-27)
- `kafka.partition.*` — **CONFIRMED** (7 metrics found in Tsuga scan over 24h, 2026-02-27)
- `kafka.request.*` — **CONFIRMED** (6 metrics found in Tsuga scan over 24h, 2026-02-27)
- `kafka.logs.flush.*` — **CONFIRMED** (3 metrics found in Tsuga scan over 24h, 2026-02-27)
- `kafka.controller.*` — **CONFIRMED** (1 metric found in Tsuga scan over 24h, 2026-02-27)
- `kafka.isr.*` — **CONFIRMED** (1 metric found in Tsuga scan over 24h, 2026-02-27)
- `kafka.leaderElection.*` — **CONFIRMED** (1 metric found in Tsuga scan over 24h, 2026-02-27)
- `kafka.topic.*` — **CONFIRMED** (1 metric found in Tsuga scan over 24h, 2026-02-27)
- `kafka_workload_*` — **CONFIRMED** (3 metrics found in Tsuga scan over 24h, 2026-02-27)

## Discovery status
- Stage 2 reconciliation complete: 33/33 metrics from `01_kafka_metrics.csv` were confirmed in Tsuga with no missing rows.
- Unexpected discovered metrics: 86 additional Kafka metrics were cataloged in `05_kafka_metric_catalog.csv` and curated for later deep-dive enrichment decisions.
- Counter temporality was reconciled against live metadata: mixed delta and cumulative counters are now represented with exact post-function guidance in `01` and `02`.
- Context field registry was validated from live attributes and `05` was pruned to integration-general keys (`context.env`, `context.team`, `context.service.*`, `context.client-id`, `context.topic`, `context.partition`, `context.node-id`, `context.k8s.*`).
- Producer-side `kafka.producer.*` metrics were still not observed and remain an open verification item.

## Top sources
- https://kafka.apache.org/documentation/#design — Kafka architecture model and core semantics used for concept map and glossary.
- https://kafka.apache.org/36/documentation/#monitoring — Official monitoring guidance and broker health signal semantics.
- https://kafka.apache.org/36/documentation/#ops — Operational practices and logging/cluster operation context.
- https://docs.confluent.io/platform/current/kafka/monitoring.html — Broker monitoring/JMX operational interpretations.
- https://docs.confluent.io/platform/current/monitor/monitor-consumer-lag.html — Consumer lag operational meaning and troubleshooting patterns.
- https://docs.confluent.io/platform/current/monitor/cp-logging.html — Kafka/Confluent logging configuration and collection context.
- https://raw.githubusercontent.com/open-telemetry/opentelemetry-java-instrumentation/main/instrumentation/kafka/kafka-clients/kafka-clients-common/library/README.md — Authoritative OTel kafka client metric names and definitions.
- https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector-contrib/main/receiver/kafkametricsreceiver/metadata.yaml — OTel collector Kafka broker metric names and metadata mappings.
- https://pkg.go.dev/github.com/open-telemetry/opentelemetry-collector-contrib/receiver/kafkametricsreceiver — Receiver behavior and scope confirmation.
- https://kafka.apache.org/documentation/#consumerconfigs — Consumer-side behavior and config context used for lag/rebalance interpretation guardrails.
- Internal Tsuga metric search (`tools/tsuga_search_metrics.py`, 2026-02-27) — Live evidence for confirmed prefixes and available metric families in this environment.
