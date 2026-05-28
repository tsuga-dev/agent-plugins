# RabbitMQ Integration Context Bundle

## Metadata
**Technology:** RabbitMQ  
**Deployment:** self-hosted  
**Environment:** prod  
**Persona:** SRE Dev and ops  
**Telemetry preference:** mixed  
**Integration scope:** core service only  
**Primary use-case:** reliability and performance

## How to use this bundle
- Use `01_rabbitmq_metrics.csv` as the source of truth for metric semantics, units, temporality assumptions, and safe query math.
- Use `02_rabbitmq_dashboard_plan.yaml` for dashboard structure: sections, widgets, derived signals, explanation notes, triage chains, and playbooks.
- Use `03_rabbitmq_state.yaml` for machine-readable status, assumptions, and unknowns that Stage 2 must verify.
- Use `04_rabbitmq_memory.md` for the human-readable Stage 1 rationale and Stage 2 handoff priorities.
- Stage 2 will create `05_rabbitmq_metric_catalog.csv` as the discovered Tsuga metric inventory for reconciliation and coverage checks.
- Stage 4 should read this file's `Log intelligence (Stage 4 handoff)` section and `03_rabbitmq_state.yaml` `log_intel` block before designing log routes.

## What it is and what "good" looks like

### Confirmed by sources
- RabbitMQ is a message broker that routes, stores, and delivers messages through exchanges, queues, and bindings ([RabbitMQ Queues](https://www.rabbitmq.com/docs/queues), [RabbitMQ Monitoring](https://www.rabbitmq.com/docs/monitoring)).
- Healthy posture means publish and delivery flow stay balanced, queue depth is controlled, and resource alarms (disk/memory) do not trigger flow control ([RabbitMQ Alarms](https://www.rabbitmq.com/docs/alarms)).
- RabbitMQ observability is typically built from management API and Prometheus-exported broker metrics ([RabbitMQ Management](https://www.rabbitmq.com/docs/management), [RabbitMQ Prometheus](https://www.rabbitmq.com/docs/prometheus)).
- Incident shape 1: backlog accumulation (publish outpaces deliver/ack); start with `queue-backlog`.
- Incident shape 2: delivery integrity regression (redeliveries rise, confirms/acks fall); start with `delivery-integrity`.
- Incident shape 3: broker saturation (disk/file descriptor/process pressure); start with `resource-saturation`.

### Best-practice inference
- For on-call triage, queue backlog growth is often a stronger early signal than total throughput because it reveals when the system cannot keep up.
- Consumer utilisation and queue-level consumer counts are high-value ownership signals for deciding whether pressure is broker-side or consumer-side.
- RabbitMQ incidents often propagate as "slow consumer -> queue growth -> redelivery churn -> publisher-side impact"; dashboard flow should follow this progression.

## Key concepts

### Glossary

| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| Exchange | Routing component that receives publishes and routes to queues | Routing failures or misbindings can create message black holes | throughput-flow |
| Queue | Ordered storage for messages waiting for consumption | Queue growth indicates processing lag | queue-backlog |
| Binding | Rule connecting exchange to queue | Misconfiguration explains missing deliveries | throughput-flow |
| Virtual Host (vhost) | Logical namespace in RabbitMQ | Useful blast-radius boundary for multi-tenant clusters | availability-health |
| Channel | Lightweight connection within a TCP connection | Channel exhaustion causes protocol errors and publish/consume failures | availability-health |
| Connection | TCP session between client and broker | Connection spikes can indicate churn or load balancer instability | availability-health |
| Consumer | Client subscription reading from queues | Consumer drop or slowdown drives backlog growth | consumer-health |
| Consumer utilisation | Fraction of time consumers are actively able to take messages | Low utilisation + high backlog points to consumer bottlenecks | consumer-health |
| Message ready | Messages in queue available for delivery | Rising ready count is immediate backlog warning | queue-backlog |
| Message unacknowledged | Delivered but not yet acked messages | High unacked suggests slow handlers or ack issues | queue-backlog |
| Acknowledgement (ack) | Consumer confirmation that processing succeeded | Falling ack efficiency indicates downstream processing trouble | delivery-integrity |
| Publisher confirm | Broker acknowledgement to publisher for durability/acceptance | Confirm degradation can affect producer latency and retries | delivery-integrity |
| Redelivery | Message delivery retry after prior failure/non-ack | Redelivery growth implies processing failures or timeout churn | delivery-integrity |
| Flow control | Broker throttling publishers under resource pressure | Indicates broker saturation before hard failure | resource-saturation |
| Memory alarm | Alarm raised when memory threshold crossed | Triggers publisher blocking and ingest slowdown | resource-saturation |
| Disk alarm | Alarm raised when free disk drops below limit | Blocks publishers to protect durability | resource-saturation |
| File descriptors | OS descriptors used by sockets/files | Near-limit values precede connection failures | resource-saturation |
| Socket descriptors | Descriptor subset for network sockets | Saturation can cause dropped/new connection failures | resource-saturation |
| Erlang processes | Lightweight runtime processes RabbitMQ uses internally | Near-limit values indicate broker runtime pressure | resource-saturation |
| Dead lettering | Rerouting of negatively acknowledged/expired/rejected messages | Explains hidden failure queues and retry loops | delivery-integrity |
| Prefetch | Consumer-side in-flight message window | Too high prefetch can inflate unacked backlog | consumer-health |
| Management API | HTTP API exposing broker and queue stats | Core source for queue-ready/unacked and message_stats fields | queue-backlog |

### Concept Map

```text
Producer -> publishes -> Exchange (why: ingress point for traffic)
Exchange -> routes via bindings -> Queue (why: determines where work lands)
Queue -> feeds -> Consumer (why: downstream processing throughput)
Consumer -> sends -> Acknowledgement (why: completes successful processing)
Missing acknowledgements -> increases -> Unacked messages (why: in-flight accumulation)
Publish rate > Deliver rate -> increases -> Queue backlog (why: processing deficit)
Queue backlog -> increases -> End-to-end latency (why: longer wait before consume)
Consumer failures -> increase -> Redeliveries (why: messages retried)
Redeliveries -> increase -> Broker and consumer work (why: duplicated processing cost)
Publisher confirms -> represent -> Broker acceptance/durability signal (why: producer reliability)
Confirm slowdown -> triggers -> Publisher retries/timeouts (why: upstream impact)
Disk free below limit -> raises -> Disk alarm (why: protect node from exhaustion)
Memory high-watermark -> raises -> Memory alarm (why: avoid node instability)
Alarms -> activate -> Flow control/publisher blocking (why: protective throttling)
Channel count near max -> risks -> Protocol/channel open failures (why: per-connection limits)
Connection count near max -> risks -> Admission failures (why: broker connection ceiling)
File descriptor usage near limit -> risks -> Socket/open file failures (why: OS resource cap)
Socket descriptor usage near limit -> degrades -> client connectivity (why: networking resources exhausted)
Erlang process usage near limit -> risks -> broker instability (why: runtime scheduler/resource pressure)
Queue count growth -> amplifies -> metadata and scheduler load (why: broker housekeeping overhead)
Node-level throughput -> decomposes into -> queue/vhost dimensions (why: ownership triage)
Tenant/vhost dimension -> maps to -> team ownership (why: faster incident routing)
Environment/team filters -> scope -> blast radius during incidents (why: reduce noise and isolate impacted services)
```

### Entities and dimensions

| Entity/Dimension | Why useful | Cardinality risk | Safe top-N | Do NOT group-by guidance |
|---|---|---|---|---|
| `context.env` | Environment isolation | Low | 5 | Keep as global filter |
| `context.team` | Ownership isolation | Low | 10 | Keep as global filter |
| `context.rabbitmq.node.name` | Broker node hotspot detection | Medium | 10 | Avoid stacking with queue and vhost simultaneously |
| `context.rabbitmq.queue.name` | Queue-level backlog and delivery triage | High | 15 | Never unbounded in overview |
| `context.rabbitmq.vhost.name` | Multi-tenant partitioning | Medium | 10 | Avoid 3-level group-by with queue+node |
| `context.service.name` | Upstream/downstream service correlation | Medium | 15 | Use in investigation, not every KPI |
| `context.service.instance.id` | Instance-level producer/consumer troubleshooting | High | 10 | Avoid in high-level dashboards |
| `context.rabbitmq.message.state` | Ready vs unacked breakdown | Low | 3 | Use only on message depth metrics |
| `context.cloud.region` | Regional blast radius (if present) | Low | 10 | Optional unless multi-region |
| `context.k8s.cluster.name` | Cluster split for k8s deployments | Medium | 10 | Use with env filter to limit scope |
| `context.k8s.namespace.name` | Namespace ownership segmentation | Medium | 15 | Avoid with high-card queue names |
| `context.host` | Legacy host identity fallback | Medium | 10 | Prefer node.name when available |
| `context.scope.name` | Instrumentation scope fallback | Low | 10 | Use only when RabbitMQ-specific keys are missing |

### Tsuga field mapping

#### Confirmed by sources
| Vendor/exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| RabbitMQ scrape host/node | `context.net.host.name` | Optional (present on discovered RabbitMQ metrics) |
| RabbitMQ cluster | `context.rabbitmq.cluster` | Optional (present on discovered RabbitMQ metrics) |
| Protocol family | `context.protocol` | Optional (present on global message counters) |
| Queue type | `context.queue_type` | Optional (present on selected global message counters) |
| Message state (`ready`/`unacked`) | Separate metrics (`rabbitmq_queue_messages_ready`, `rabbitmq_queue_messages_unacked`) | Optional (state label not observed) |
| Environment | `context.env` | Must-exist |
| Team | `context.team` | Must-exist |

#### Best-practice inference
| Vendor/exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| Service identity | `context.service.name` | Optional |
| Service instance identity | `context.service.instance.id` | Optional |
| Scope fallback | `context.scope` | Optional fallback |
| Kubernetes cluster | `context.k8s.cluster.name` | Optional |
| Kubernetes namespace | `context.k8s.namespace.name` | Optional |

## Golden signals

### Confirmed by sources
| Signal | Meaning for RabbitMQ | Typical degradations | Best telemetry sources | What people page on | Section questions |
|---|---|---|---|---|---|
| Traffic | Publish and deliver throughput through broker and queues | Producer surges, routing bottlenecks, consumer lag | `rabbitmq.message.published`, `rabbitmq.message.delivered`, node message rates ([OTel rabbitmqreceiver metadata](https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector-contrib/main/receiver/rabbitmqreceiver/metadata.yaml)) | Publish rate sustained above deliver rate with rising queue depth | Is ingress balanced with egress? Which queues are hottest? |
| Errors | Delivery retries and processing failures | Consumer crashes, nack/requeue loops, downstream timeouts | `rabbitmq.node.message.redelivered`, ack/confirm counters ([RabbitMQ Confirms](https://www.rabbitmq.com/docs/confirms), [OTel rabbitmqreceiver metadata](https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector-contrib/main/receiver/rabbitmqreceiver/metadata.yaml)) | Redelivery share climbing and ack efficiency dropping | Are messages being successfully processed once? |
| Latency | Time spent waiting in queue plus processing/ack roundtrip effects | Slow consumers, constrained prefetch, resource alarms | Queue depth + consumer utilisation + deliver/ack balance ([RabbitMQ Consumers](https://www.rabbitmq.com/docs/consumers)) | Depth grows while utilisation falls or stays low | Is queue wait time risk increasing? |
| Saturation | Proximity to broker hard/soft limits | Disk/memory alarms, fd/socket/process exhaustion, channel/connection ceilings | Disk free vs limits, descriptor/process/channel/connection metrics ([RabbitMQ Alarms](https://www.rabbitmq.com/docs/alarms), [OTel rabbitmqreceiver metadata](https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector-contrib/main/receiver/rabbitmqreceiver/metadata.yaml)) | Headroom collapsing toward alarms or hard limits | Are we nearing broker protection/blocking conditions? |

### Best-practice inference
- Queue backlog pressure should be interpreted jointly with consumer counts/utilisation; depth alone is not enough for ownership.
- Confirm and ack efficiency ratios are practical SRE indicators for end-to-end reliability even when full trace context is missing.
- For RabbitMQ, "saturation" is often the earliest actionable alerting surface before outright availability failure.

## Telemetry sources

### Confirmed by sources
| Source type | How collected | What it provides | Pros/cons | Common pitfalls |
|---|---|---|---|---|
| RabbitMQ Prometheus endpoint | `rabbitmq_prometheus` plugin exposes metrics endpoints ([RabbitMQ Prometheus](https://www.rabbitmq.com/docs/prometheus)) | Broker/node/queue metric surface consumable by Prometheus or OTel collectors | Broad coverage; standard scrape model / Requires plugin enablement and scrape config | Missing metrics may mean plugin disabled, not healthy zero |
| RabbitMQ Management API | HTTP API from management plugin ([RabbitMQ HTTP API Reference](https://www.rabbitmq.com/docs/http-api-reference), [RabbitMQ Management](https://www.rabbitmq.com/docs/management)) | Queue depth (`messages_ready`, `messages_unacknowledged`), `message_stats`, object metadata | Rich operational context / Polling overhead and pagination complexity | Over-polling large fleets can cause management pressure |
| OTel rabbitmqreceiver | Collector receiver polling management stats ([OTel rabbitmqreceiver package](https://pkg.go.dev/github.com/open-telemetry/opentelemetry-collector-contrib/receiver/rabbitmqreceiver)) | Normalized `rabbitmq.*` metrics with queue/node attributes | Standardized naming and collector integration / Optional dimensions may vary by deployment | Temporality and exact context-key mapping must be verified in Tsuga |
| RabbitMQ logs | Node/container logs in text or JSON formats ([RabbitMQ Logging](https://www.rabbitmq.com/docs/logging), [RabbitMQ Logs](https://www.rabbitmq.com/docs/logs)) | Connection churn, auth failures, alarm events, cluster warnings | High incident context / Parsing variability by formatter and deployment target | Mixed formats and multiline entries can break naive parsers |

### Best-practice inference
- "No data" for queue-level dimensions often means ingestion lacks queue tags, not necessarily no traffic.
- If node-level counters exist but queue-level slices do not, keep overview broker-centric and gate queue-centric deep-dive widgets.
- Logs are critical to explain alarm causes and auth/network churn when metrics only show symptoms.

## Log intelligence (Stage 4 handoff)

### Confirmed by sources

#### Log sources matrix
| Source | Access path | Typical format | Structured vs unstructured | Evidence |
|---|---|---|---|---|
| RabbitMQ node log file | `/var/log/rabbitmq/rabbit@<hostname>.log` (package installs) | Text with timestamp, level, pid, message | Unstructured text | [RabbitMQ Logs](https://www.rabbitmq.com/docs/logs), [RabbitMQ Logging](https://www.rabbitmq.com/docs/logging) |
| Container stdout/stderr | Docker/Kubernetes logs | Text or JSON depending on `log.console.formatter` | Either | [RabbitMQ Logging](https://www.rabbitmq.com/docs/logging) |
| RabbitMQ JSON formatter output | Configured formatter emits JSON objects with metadata | JSON lines | Structured JSON | [RabbitMQ Logging](https://www.rabbitmq.com/docs/logging) |

#### Known log formats
1. Text log format (default-like):
   - Sample: `2024-06-15 03:42:20.119222+00:00 [warning] <0.746.0> closing AMQP connection <0.746.0> (10.42.0.12:54122 -> 10.42.1.5:5672, vhost: '/', user: 'checkout')`
   - Delimiter/shape notes: timestamp then level in brackets, Erlang pid token (`<0.x.0>`), free-form message body.
   - Timestamp pattern: `YYYY-MM-DD HH:MM:SS.microseconds+TZ`.
   - Quoting behavior: message body often contains quoted vhost/user values and parenthesized connection tuples.
   - Optional fields: client IP/port, vhost, user may be absent for internal events.
2. JSON log format:
   - Sample: `{ "time": "2024-05-30 08:11:33.765208+00:00", "level": "warning", "pid": "<0.1328.0>", "msg": "Mnesia node rabbit@rabbitmq-0 failed to connect to rabbit@rabbitmq-2" }`
   - Delimiter/shape notes: one JSON object per log line.
   - Timestamp pattern: string timestamp in `time` field.
   - Quoting behavior: JSON escaped strings.
   - Optional fields: keys vary by event type and formatter options.

#### Candidate query filters for Stage 4
- Precise: `context.service.name:rabbitmq AND (message:*connection* OR message:*alarm* OR message:*memory* OR message:*disk*)`
  - Rationale: targets high-value operational events (connection churn and resource alarms).
  - Risk: may miss logs if service name mapping differs (`rabbit`, `rabbitmq-server`, etc.).
- Fallback: `message:*rabbit* AND (message:*warning* OR message:*error* OR message:*alarm*)`
  - Rationale: broad capture when structured service attributes are missing.
  - Risk: higher noise and false positives from unrelated components containing "rabbit".

#### Attribute mapping hints
| Raw field | Suggested Tsuga key | Confidence | Notes |
|---|---|---|---|
| `time` or leading timestamp | `timestamp` | High | Normalize timezone to UTC where possible |
| `level` or `[warning]` token | `severity_text` | High | Map to Tsuga log level processor |
| `pid` (`<0.x.0>`) | `context.process.pid` | Medium | Keep as string if not numeric |
| vhost segment (`vhost: '/'`) | `context.rabbitmq.vhost.name` | Medium | Regex parse from text logs |
| user segment (`user: 'name'`) | `context.user.name` | Medium | Sensitive field; verify masking policy |
| client endpoint tuple | `context.client.address` | Medium | Parse into IP/port when possible |
| node name in cluster logs | `context.rabbitmq.node.name` | Medium | Useful for multi-node triage |
| message body | `message` | High | Preserve full raw message |

#### Parsing risks
- Mixed formatter deployments (text on one node, JSON on another) require split processors.
- Erlang pid and connection tuple tokens use angle brackets and parentheses that can break naive grok patterns.
- Variable message bodies mean optional capture groups are mandatory.
- Multi-line crash reports can appear in some environments; route should account for continuation patterns.
- Timezone offsets in timestamps vary and must be normalized.

### Best-practice inference
- Prefer direct extraction to final Tsuga keys instead of multi-step remapping when logs are consistent.
- For mixed formats, start with JSON parse branch first, then text grok fallback branch to reduce false parses.
- Keep Stage 4 route focused on warning/error/alarm classes first; add info-level breadth only after initial parser quality is validated.

## Caveats and footguns
- **[availability-health]** Connection counts can spike during deploys without indicating broker failure; correlate with churn and sustained failures before escalation. (Inference)
- **[availability-health]** Channel saturation can occur even when connection counts look normal because channels are multiplexed per connection. (Inference)
- **[throughput-flow]** Comparing raw publish and deliver totals without consistent counter temporality can produce wrong rate conclusions. (Inference)
- **[throughput-flow]** Delivery rate drops can be caused by consumer-side throttling, not broker routing faults. (Inference)
- **[queue-backlog]** Queue depth can look stable while unacked grows; watch state split, not only total depth. ([RabbitMQ HTTP API Reference](https://www.rabbitmq.com/docs/http-api-reference))
- **[queue-backlog]** High-cardinality queue names can overwhelm charts; always bound with Top-N. (Inference)
- **[queue-backlog, consumer-health]** Prefetch misconfiguration can inflate unacked messages while consumer counts remain unchanged. ([RabbitMQ Consumers](https://www.rabbitmq.com/docs/consumers))
- **[consumer-health]** Consumer count alone is weak; low utilisation is often the stronger signal of slow processing. ([RabbitMQ Consumers](https://www.rabbitmq.com/docs/consumers))
- **[consumer-health]** Queue consumer utilisation metrics may be absent for some queue types or telemetry paths; gate widgets accordingly. (Inference)
- **[resource-saturation]** Disk free near limit can trigger publisher blocking before queue metrics obviously degrade. ([RabbitMQ Alarms](https://www.rabbitmq.com/docs/alarms))
- **[resource-saturation]** Memory alarms can appear as throughput collapse rather than immediate broker down state. ([RabbitMQ Alarms](https://www.rabbitmq.com/docs/alarms))
- **[resource-saturation]** File descriptor usage near limit can manifest as random connection issues first. (Inference)
- **[resource-saturation]** Socket descriptor and file descriptor limits are related but not identical; monitor both. (Inference)
- **[resource-saturation]** Erlang process saturation can degrade scheduling before hard failures occur. (Inference)
- **[resource-saturation]** Disk I/O throughput spikes are not inherently bad; evaluate with queue growth and confirms. (Inference)
- **[delivery-integrity]** Redelivery growth can be expected during rolling restarts; verify persistence vs sustained trend. (Inference)
- **[delivery-integrity]** Confirm rate dips can be producer-side timeout/retry artifacts, not always broker durability loss. ([RabbitMQ Confirms](https://www.rabbitmq.com/docs/confirms))
- **[delivery-integrity]** Ack efficiency ratios can be misleading if deliveries include transient retries across the window. (Inference)
- **[availability-health, throughput-flow]** Missing queue/vhost dimensions may indicate collector mapping gaps, not zero queue activity. (Inference)
- **[queue-backlog, delivery-integrity]** Dead-lettered or retry queues can hide failure volume from primary queue dashboards if not included in filters. (Inference)
- **[throughput-flow]** Management API polling too aggressively can add load and skew perceived broker health in large clusters. ([RabbitMQ Management](https://www.rabbitmq.com/docs/management))
- **[availability-health]** Environment/team filters are mandatory for multi-tenant RabbitMQ; cross-tenant aggregation can hide localized incidents. (Inference)

## Confirmed Tsuga prefixes
- `rabbitmq_*` — **CONFIRMED** (MCP `list-metrics` full sweep `offset=0..600` found active RabbitMQ metrics across connection, queue, channel, alarm, auth, and IO families)
- `erlang_vm_*` — **CONFIRMED (supporting runtime namespace)** (Erlang VM runtime metrics are present and useful for RabbitMQ process saturation context)

## Discovery status
Discovery: completed on 2026-02-24 via MCP (`list-metrics` sweep + targeted `get-metric` validation); dotted `rabbitmq.*` names were reconciled to live underscore namespaces.

## Top sources
1. https://pkg.go.dev/github.com/open-telemetry/opentelemetry-collector-contrib/receiver/rabbitmqreceiver  
   Why: canonical receiver contract, requirements, and exported metric families.
2. https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector-contrib/main/receiver/rabbitmqreceiver/metadata.yaml  
   Why: exact `rabbitmq.*` metric names, types, and units used for Stage 1 inventory.
3. https://www.rabbitmq.com/docs/monitoring  
   Why: official monitoring model and operational observability guidance.
4. https://www.rabbitmq.com/docs/prometheus  
   Why: authoritative Prometheus metrics exposure and scrape guidance.
5. https://www.rabbitmq.com/docs/management  
   Why: management plugin behavior and operational caveats.
6. https://www.rabbitmq.com/docs/http-api-reference  
   Why: queue/message stats fields and API-backed telemetry semantics.
7. https://www.rabbitmq.com/docs/queues  
   Why: queue behavior, durability semantics, and lifecycle constraints.
8. https://www.rabbitmq.com/docs/consumers  
   Why: consumer capacity/utilisation semantics and prefetch implications.
9. https://www.rabbitmq.com/docs/alarms  
   Why: memory/disk alarm and flow control behavior under pressure.
10. https://www.rabbitmq.com/docs/logging  
    Why: log format options (text/json), sample lines, and formatter settings.
