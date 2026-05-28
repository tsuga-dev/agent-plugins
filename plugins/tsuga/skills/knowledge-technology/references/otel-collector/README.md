# OpenTelemetry Collector Integration Context Bundle

## Metadata

**Technology:** OpenTelemetry Collector
**Deployment:** self-hosted
**Environment:** prod
**Persona:** SRE Dev and ops
**Telemetry preference:** mixed (Prometheus scrape of :8888/metrics or OTLP self-export)
**Integration scope:** core service only (collector self-telemetry — otelcol_* and process-level metrics)
**Primary use-case:** reliability and performance

---

## How to use this bundle

- **`01_opentelemetry-collector_metrics.csv`** — Source of truth for all metrics: names, types, temporality, safe aggregations, group-by fields, cardinality warnings.
- **`02_opentelemetry-collector_dashboard_plan.yaml`** — Dashboard structure: sections, widgets, derived signals (drop rates, queue fill %, pipeline efficiency), triage chains, playbooks, and coverage map.
- **`03_opentelemetry-collector_state.yaml`** — Machine-readable stage status, inferred prefixes, assumptions, and unknowns to verify in Stage 2.
- **`04_opentelemetry-collector_memory.md`** — Human-readable handoff narrative for Stage 2 and 3.
- **`05_opentelemetry-collector_metric_catalog.csv`** — Stage 2 will generate this file: confirmed metric names, attribute keys, and AI-curated descriptions from live Tsuga discovery.

---

## What it is and what "good" looks like

The OpenTelemetry Collector is an open-source, vendor-agnostic telemetry pipeline. On Kubernetes it typically runs as a DaemonSet (one pod per node, collects local node/pod metrics and SDK traffic) and/or a Deployment-based gateway (centralized aggregation with tail sampling and multi-backend fan-out). This integration monitors the collector *itself* — its pipeline health, not the applications whose data it routes.

**What "good" looks like:**
- `exporter_send_failed_*` = 0/s for all signal types (no data loss)
- `receiver_refused_*` = 0/s (no backpressure to SDKs)
- `exporter_queue_size / queue_capacity` oscillates 0–40% and drains between bursts
- `exporter_sent_* ≈ receiver_accepted_*` (pipeline efficiency ≥ 98%)
- Process memory well below the `memory_limiter` threshold (< 60% of limit)
- Batch processor sends are size-driven (not timeout-dominated at normal traffic)

**Top 3 incident shapes and where to start:**

1. **Active data loss** (`send_failed` rising) → Start at the Data Loss & Errors section. Check which exporter is failing and whether the queue is full.
2. **Backpressure cascade** (`receiver_refused` rising) → Start at the Exporter Queue section. Determine whether queue is filling because a backend is slow or unreachable.
3. **Collector memory pressure / OOMKill** (process restarts, uptime resets) → Start at the Collector Resources section. Correlate memory spike with refused_* just before the restart.

**Confirmed by sources:** Incident shapes derived from live OTel Collector deployment data in the Tsuga environment (2026-02-16 discovery of otelcol_* metrics) and the OTel Collector internal telemetry documentation at https://opentelemetry.io/docs/collector/internal-telemetry/.

**Best-practice inference:** The queue-fill-then-data-loss cascade sequence and memory_limiter behavior descriptions are inferred from OTel Collector architecture documentation and general observability pipeline best practices.

---

## Key concepts

### Glossary

| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| Pipeline | The ordered chain of components: receivers → processors → exporters | The core processing unit; failure propagates left-to-right (exporter slow → queue fills → receiver refuses) | pipeline-health |
| Receiver | Component that accepts telemetry from external sources (SDK, scrape endpoint) | First point of failure for SDK connectivity issues | receiver-breakdown |
| Processor | Component that transforms, filters, or enriches telemetry in-flight | Middle tier; memory_limiter and batch are critical processors | batch-processor |
| Exporter | Component that sends telemetry to a backend (Tsuga, Jaeger, Prometheus, Loki) | Last point of failure; send_failed = permanent data loss | exporter-breakdown |
| Signal type | A telemetry category: spans (traces), metric points, or log records | Each signal type has its own set of counters; all three must be healthy | pipeline-health |
| Span | Single unit of distributed trace work (one RPC, one DB call, one function) | Count accepted/sent spans to measure trace pipeline throughput | pipeline-health |
| Metric point / data point | A single measurement of a metric at a point in time | OTel uses data points not "samples"; accepted_metric_points is the ingest rate | pipeline-health |
| Log record | A single structured or unstructured log entry | Third signal type; often orders-of-magnitude higher volume than spans | pipeline-health |
| Accepted | Items successfully ingested by the receiver and passed into the pipeline | Primary throughput signal; denominator for all drop rate calculations | pipeline-health |
| Refused | Items rejected by the receiver; collector sent backpressure to the SDK | Backpressure — NOT data loss. SDK buffers and retries. Non-zero = congestion | data-loss-errors |
| Failed (receiver) | Items that errored at the receiver layer (decode/parse error) before entering the pipeline | Hard data loss — malformed payload. Requires fixing the sending SDK. | data-loss-errors |
| Sent | Items successfully exported to the backend | Definitive "success" signal; should match accepted in a healthy pipeline | exporter-breakdown |
| Send Failed | Items that failed to export after all retries were exhausted | Permanent data loss. Any non-zero sustained rate is an alert condition. | data-loss-errors |
| Queue | Buffer between processor and exporter that absorbs transient backend slowness | Oscillating 0–40% is healthy; trending to 100% = backend struggling | exporter-queue |
| Queue capacity | Maximum configured number of items the exporter queue holds | Config-time constant; together with queue_size defines fill percentage | exporter-queue |
| Queue size | Current item count in the exporter queue | Gauge; use queue_size/queue_capacity to compute fill % | exporter-queue |
| Memory limiter | Processor that drops data when the collector process RSS exceeds a configured threshold | Protects from OOMKill; when active, receiver_refused rises with memory | collector-resources |
| Batch processor | Aggregates items into larger batches before sending, reducing backend request overhead | Batch size p95 near send_batch_size = healthy; timeout-dominated = tuning needed | batch-processor |
| Delta temporality | Counter semantic where each export reports only events since the last export (value does not accumulate) | Use `per-second` in Tsuga. Never use `rate` on delta counters — produces nonsense. | All sections |
| Cumulative temporality | Counter semantic where values accumulate since process start (Prometheus-style) | Use `rate` for per-second rate, `increase` for per-bucket total | collector-resources |
| DaemonSet mode | Kubernetes deployment with exactly one collector pod per node | Used for node-scoped collection; group by context.k8s.node.name | receiver-breakdown |
| Gateway mode | Centralized Deployment-based collector aggregating from agents | 2–5 replicas common; use context.k8s.deployment.name for identity | exporter-breakdown |
| Sidecar mode | Collector injected as a container into each application pod | High cardinality (one per pod); avoid context.k8s.pod.name in dashboards | receiver-breakdown |
| Transport | Protocol used to receive data: gRPC, http/protobuf, or http/json | context.transport has 2–3 values; safe to group-by without cardinality risk | receiver-breakdown |
| Backpressure | Mechanism by which downstream congestion (slow backend) is communicated upstream to slow ingest | Cascade: backend slow → queue fills → receiver refuses → SDK retries | data-loss-errors |
| Metadata cardinality | Number of distinct resource attribute combinations tracked by the batch processor | High cardinality (>100) indicates resource attribute explosion; causes memory pressure | batch-processor |

### Concept Map

```
SDK (application)         -> sends OTLP spans/metrics/logs -> Receiver (OTLP gRPC/HTTP on port 4317/4318)
Receiver                  -> ingests items                 -> Processor chain (pipeline ordered list)
Processor chain (1st)     -> memory_limiter                -> drops items if process RSS > limit_mib (protects from OOMKill)
Processor chain (2nd)     -> k8sattributes                 -> enriches with k8s pod/namespace/node metadata
Processor chain (3rd)     -> batch                         -> aggregates into larger batches for efficient backend delivery
Batch processor           -> flushes to                    -> Exporter (when batch fills or timeout fires)
Exporter                  -> sends to backend              -> Tsuga / Jaeger / Prometheus / Loki
Exporter                  -> on backend slowness           -> queues items in retry buffer (up to queue_capacity)
Queue filling             -> above capacity                -> new items dropped → send_failed counter rises (data loss)
Memory limiter trigger    -> refuses new items             -> propagates backpressure to Receiver
Receiver backpressure     -> sends RESOURCE_EXHAUSTED      -> to SDK (SDK buffers, retries with backoff)
DaemonSet agents          -> forward OTLP to               -> Gateway collector Deployment (cluster-level aggregation)
Gateway                   -> fans out telemetry            -> multiple backend exporters
Collector self-metrics    -> emitted via                   -> Prometheus endpoint (:8888/metrics) or OTLP self-export pipeline
context.receiver label    -> identifies                    -> which receiver component produced the metric (otlp, hostmetrics)
context.exporter label    -> identifies                    -> which exporter is reporting queue depth and send stats
context.processor label   -> identifies                    -> which processor is accepting/dropping items
context.transport label   -> distinguishes                 -> gRPC vs HTTP ingestion paths on receiver metrics
process RSS rising        -> triggers                      -> memory_limiter → receiver_refused_* rises simultaneously
queue_size at capacity    -> triggers                      -> send_failed_* to rise (data loss begins)
```

### Entities and dimensions

| Entity/Dimension | Why useful | Cardinality risk | Safe top-N | Notes |
|---|---|---|---|---|
| `context.receiver` | Identifies which receiver is contributing to ingest and backpressure | Very low (2–5 receivers typical) | 10 | Safe to group-by. Values: otlp, hostmetrics, kubeletstats, prometheus, filelog |
| `context.exporter` | Identifies which backend destination is failing or queueing | Very low (2–5 exporters typical) | 10 | Safe to group-by. Values: otlp, prometheusremotewrite, loki, debug |
| `context.processor` | Identifies which processor is accepting/dropping items | Very low (3–8 processors) | 10 | Safe to group-by. Values: batch, memory_limiter, k8sattributes, filter |
| `context.transport` | Distinguishes gRPC vs HTTP ingestion paths | Very low (2–3 values) | 3 | Always safe. Values: grpc, http/protobuf, http/json |
| `context.k8s.node.name` | Per-node breakdown for DaemonSet deployments | Medium (10–500 nodes) | 20 | Use for DaemonSet collectors; shows which nodes have collector issues |
| `context.k8s.deployment.name` | Identifies gateway collector deployment | Very low (1–3 deployments) | 5 | Use for Deployment-mode gateway collectors |
| `context.k8s.namespace.name` | Namespace where collector is deployed | Low (1–3 collector namespaces) | 10 | Safe to filter; rarely useful to group-by for collector self-metrics |
| `context.k8s.daemonset.name` | Identifies DaemonSet agent fleet | Very low (1–2 DaemonSets) | 5 | Useful to distinguish agent vs gateway in mixed deployments |
| `context.k8s.cluster.name` | Multi-cluster environments | Low (1–10 clusters) | 10 | Use as global filter in multi-cluster setups |
| `context.service.name` | Collector's own service name (e.g., "otelcol") | Very low (1–3) | 5 | Use to distinguish multiple collector types in one environment |
| `context.service.version` | Collector binary version | Very low | 5 | Useful for correlating regressions with version upgrades |
| `context.k8s.pod.name` | Specific collector pod instance | HIGH (ephemeral) | — | **Do NOT group-by in dashboards.** Use for incident drill-down only. High cardinality, pod names are ephemeral. |
| `context.env` | Environment filter (prod/staging) | Very low | 5 | Always include as global dashboard filter |
| `context.team` | Team ownership filter | Low | 10 | Always include as global dashboard filter |

### Tsuga field mapping

**Confirmed by sources** (from live Tsuga environment, OTel Demo discovery 2026-02-16):

| Vendor/exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| `receiver` (pipeline label on otelcol_receiver_* metrics) | `context.receiver` | Must-exist on receiver metrics |
| `exporter` (pipeline label on otelcol_exporter_* metrics) | `context.exporter` | Must-exist on exporter metrics |
| `processor` (pipeline label on otelcol_processor_* metrics) | `context.processor` | Must-exist on processor metrics |
| `transport` (pipeline label: grpc/http) | `context.transport` | Optional |
| `k8s.node.name` (resource attribute) | `context.k8s.node.name` | Optional (DaemonSet deployments) |
| `k8s.deployment.name` (resource attribute) | `context.k8s.deployment.name` | Optional (Gateway/Deployment mode) |
| `k8s.namespace.name` (resource attribute) | `context.k8s.namespace.name` | Optional |
| `k8s.daemonset.name` (resource attribute) | `context.k8s.daemonset.name` | Optional |
| `k8s.cluster.name` (resource attribute) | `context.k8s.cluster.name` | Optional |
| `k8s.pod.name` (resource attribute) | `context.k8s.pod.name` | Optional (avoid in group-by) |
| `service.name` (resource attribute) | `context.service.name` | Optional |
| `service.version` (resource attribute) | `context.service.version` | Optional |

**Best-practice inference:** The pipeline labels (`receiver`, `exporter`, `processor`, `transport`) are Prometheus-style labels attached to individual otelcol_* metrics. In Tsuga's context.* model, they map as `context.receiver`, `context.exporter`, etc. This is consistent with how the OTel Demo dashboards filter on `context.receiver` and `context.exporter` (confirmed in Tsuga codebase, `_build_otel_demo.py`).

---

## Golden signals

### Traffic / Throughput

**What it means for OTel Collector:** Volume of telemetry items flowing into the pipeline per second. Measured separately for each signal type (spans, metric points, log records).

**Why it matters:** `accepted_*` rate is the denominator for all drop rate calculations. A sudden drop in accepted rate means either the upstream SDKs stopped sending or the collector is refusing connections. A sudden spike may overwhelm queue and exporter capacity.

**Best telemetry:** `otelcol_receiver_accepted_spans_total`, `otelcol_receiver_accepted_metric_points_total`, `otelcol_receiver_accepted_log_records_total`

**What people page on:** "Trace ingest has dropped to zero" / "Log pipeline ingesting 10× normal volume"

**Section questions this becomes:**
- Is the collector receiving telemetry from all expected sources?
- Is the ingest rate consistent with historical baselines?

**Confirmed by sources:** Metric names confirmed live in Tsuga (2026-02-16). Semantics from https://opentelemetry.io/docs/collector/internal-telemetry/

### Errors / Failures

**What it means for OTel Collector:** Two distinct error modes with different severity:
- `send_failed_*`: Permanent data loss — items dropped after all retries. Any non-zero sustained rate is a critical event.
- `receiver_refused_*`: Backpressure — SDK is told to slow down. Recoverable; SDK retries. Non-zero is a warning, not an alert by itself.
- `receiver_failed_*`: Decode/parse errors at receiver — hard data loss, but rare and caused by malformed SDK payloads.

**Why it matters:** The critical distinction is refused ≠ data loss. Paging on refused without checking send_failed leads to false alarms. Failing to page on send_failed means permanent data loss goes undetected.

**Best telemetry:** `otelcol_exporter_send_failed_spans_total`, `otelcol_receiver_refused_spans_total`

**What people page on:** "Collector is dropping 2% of spans" / "exporter send_failed rate climbing"

**Section questions:**
- Is any telemetry being permanently lost (send_failed > 0)?
- Is the collector sending backpressure to SDKs (refused > 0 sustained)?

**Confirmed by sources:** Live environment confirmed both metrics and the refused-vs-failed semantic distinction (OTel Demo discovery). Authoritative source: https://opentelemetry.io/docs/collector/internal-telemetry/#data-flow-health

### Latency (Pipeline)

**What it means for OTel Collector:** The collector has no direct export latency metric. Pipeline latency is inferred from:
- Queue depth trend: items sitting in queue waiting for backend
- Batch send size distribution: low p50 = items waiting for timeout to flush

**Why it matters:** High queue depth is the leading indicator of downstream latency. If queue grows and backend does not recover, data loss follows.

**Best telemetry:** `otelcol_exporter_queue_size`, `otelcol_processor_batch_batch_send_size`

**What people page on:** "Queue depth climbing for 10+ minutes" / "Batch size p95 unexpectedly low"

**Section questions:**
- Is the exporter queue filling up (indicating backend is slow)?
- Are batches flushing on size (healthy) or only on timeout (under-utilized)?

**Best-practice inference:** Queue-depth-as-proxy-for-latency is a standard observability pipeline pattern.

### Saturation

**What it means for OTel Collector:** The collector's ability to handle current load. Primary saturation signals:
- `process.memory.usage` approaching memory_limiter threshold → limiter engages, refuses new items
- `process.cpu.utilization` sustained above 0.8 (80% of one core) → processing backlog builds
- `exporter_queue_size / queue_capacity` approaching 100% → items at risk of being dropped

**Why it matters:** Memory saturation causes the memory_limiter processor to refuse data, which propagates as backpressure to SDKs. CPU saturation means the collector cannot process ingest fast enough, causing queue buildup. Both lead to data loss if not addressed.

**Best telemetry:** `process.memory.usage`, `process.cpu.utilization`, `otelcol_exporter_queue_size`, `otelcol_exporter_queue_capacity`

**What people page on:** "Collector OOMKilled" / "Queue fill % sustained above 80% for 5 minutes"

**Section questions:**
- Is the collector process memory approaching its configured limit?
- Is CPU utilization saturated (is the collector keeping up with ingest)?

**Confirmed by sources:** Process metric semantics from OTel semantic conventions. Queue saturation semantics from OTel Collector source and documentation.

---

## Telemetry sources

| Source type | How collected | What it provides | Pros/cons | Common pitfalls |
|---|---|---|---|---|
| Collector Prometheus endpoint (:8888/metrics) | prometheus receiver scraping the collector pod's own port | All `otelcol_*` pipeline metrics (receiver/exporter/processor); counters have `_total` suffix | No additional config needed if telemetry level is set; pull-based, easy to scrape | Counter names have `_total` suffix only in Prometheus format; `telemetry.metrics.level: none` disables all metrics |
| Collector OTLP self-export | Collector configured to route its own metrics through an internal OTLP pipeline | Same `otelcol_*` metrics pushed directly to backend; counter names may lack `_total` suffix | Push-based, no scraper needed; counters use OTLP naming (no `_total`) | Complex config; easy to create circular pipeline; metric naming differs from Prometheus format |
| Kubelet Stats receiver (optional) | `kubeletstats` receiver on the collector pod's node | Container and pod CPU/memory for the collector's own container (context.k8s.container.name = "collector") | Provides resource usage from outside the process | Requires kubelet API access; pod name label is ephemeral (high cardinality); separate from `otelcol_*` namespace |
| No data at all | — | — | — | If `service.telemetry.metrics.level: none` is set in collector config, NO self-metrics are emitted. Absence = misconfiguration, not zero traffic. |

---

## Caveats and footguns

- **[data-loss-errors]** `receiver_refused_*` is NOT data loss — it is backpressure. The SDK buffers and retries with exponential backoff. Do not alert on refused the same way as `send_failed`. Page on `send_failed` > 0 sustained; investigate `refused` > 0 sustained as a warning. (Source: https://opentelemetry.io/docs/collector/internal-telemetry/)

- **[data-loss-errors]** `send_failed_*` IS permanent data loss — items exhausted all retry attempts. Any non-zero sustained rate after the initial warm-up period is a paging event. (Confirmed: live environment semantics.)

- **[pipeline-health]** Delta temporality — use `per-second`, NOT `rate`: The OTel Collector's own counters use delta temporality (each export interval reports only events since the last). In Tsuga, use `sum` + `per-second`. Using `rate` (which is for cumulative/Prometheus counters) on delta counters produces nonsense values. (Confirmed: live OTel Demo discovery 2026-02-16.)

- **[pipeline-health]** Prometheus endpoint gives counter names WITH `_total` suffix: If the collector exposes metrics via its Prometheus endpoint and those are scraped (via prometheus receiver), counters arrive as `otelcol_receiver_accepted_spans_total`. If the collector uses OTLP self-export, the `_total` suffix is absent. Verify which path is configured before building metric queries. (Inference from OTel Collector documentation.)

- **[exporter-queue]** `queue_size` is meaningless without `queue_capacity`: `queue_size = 500` may be fine (5% of 10000 capacity) or critical (100% of 500 capacity). Always compute `queue_fill_pct = queue_size / queue_capacity * 100`. Never alarm on raw `queue_size` alone. (Inference.)

- **[collector-resources]** Memory limiter is a failsafe, not a solution: The memory limiter drops data to prevent OOMKill. If `process.memory.usage` is high and `receiver_refused_*` is rising simultaneously, the limiter is active and data IS being lost. Fix the root cause (slow backend, excessive ingest volume), not the memory limit. (Confirmed: OTel memory_limiter documentation.)

- **[batch-processor]** Timeout-dominated batch sends are expected at low traffic: During off-peak hours, batches fill slowly and the batch timer fires before the batch is full. `batch_timeout_trigger_send_total` dominating is NORMAL at night. Only worry if this pattern persists at high ingest volumes. (Inference.)

- **[receiver-breakdown]** `context.transport` has only 2–3 values: `grpc`, `http/protobuf`, `http/json`. Safe to group-by without cardinality risk. Do not confuse with `context.receiver` which is the component name. (Inference.)

- **[pipeline-health]** Queue filling does NOT mean data loss yet: Queue growing = backend slower than ingest. Data loss only begins when queue reaches capacity AND new items arrive. Monitor the trend and ETA to 100%, not just the point-in-time value. (Confirmed: OTel Collector queue semantics.)

- **[data-loss-errors]** `receiver_failed_*` (decode/parse errors) is rare and hard to fix: These are malformed payloads from the SDK. If non-zero, the problem is in the sending instrumentation, not the collector config. (Confirmed: OTel internal telemetry semantics.)

- **[collector-resources]** `process.cpu.utilization` is per-core, not per-pod: A value of 0.9 means 90% of ONE logical CPU core. On a pod with 2 CPU limit, the pod could be using nearly all its CPU budget (0.9 of 1 core) or only half (0.9 of 2 cores). Cross-reference with pod CPU limit for correct interpretation. (Inference from OTel process semantic conventions.)

- **[receiver-breakdown]** `context.receiver` value encodes the component type and instance name: In the pipeline, `otlp/traces` and `otlp/metrics` are distinct receiver instances even though both use the OTLP protocol. Group-by `context.receiver` will show both separately. (Inference from OTel Collector pipeline config semantics.)

- **[exporter-breakdown]** `queue_size` and `queue_capacity` are per-exporter, not global: Each exporter has its own independent queue. A full queue on the OTLP exporter does NOT affect the Prometheus exporter's queue. (Confirmed: OTel Collector architecture documentation.)

- **[batch-processor]** `batch_metadata_cardinality` explosion causes unbounded memory growth: The batch processor maintains a separate batch bucket per distinct resource attribute combination. If applications send many unique combinations (e.g., unique pod UIDs in resource attributes), this creates hundreds of buckets. Set `max_in_flight_size_mib` to cap this. (Confirmed: OTel batch processor documentation.)

- **[pipeline-health]** "No data" for `otelcol_*` metrics means self-telemetry is disabled: If no collector metrics appear in Tsuga, the most common cause is `service.telemetry.metrics.level: none` in the collector config, or the Prometheus endpoint is not being scraped. Not a collector failure — a configuration gap. (Inference from OTel Collector config reference.)

- **[exporter-breakdown]** `send_failed` may count per-batch, not per-item for some exporters: A single backend timeout that rejects a 1000-item batch counts as 1000 `send_failed` items, even though it was one network error. Interpret send_failed as a proxy for batch-level failures multiplied by batch size. (Inference.)

- **[pipeline-health]** Multiple gateway replicas each emit their own `otelcol_*` metrics: With a 3-replica gateway Deployment, Tsuga receives 3× the metric series. Summing across replicas is correct for throughput. Use `context.k8s.pod.name` only when drilling into a specific replica during an incident. (Inference from k8s multi-replica semantics.)

- **[collector-resources]** `otelcol_process_uptime` reset indicates a pod restart: A sudden drop in the uptime counter to near zero means the collector pod restarted. Correlate with spikes in `send_failed_*` and `receiver_refused_*` just before the reset. (Inference from process uptime semantics.)

- **[pipeline-health]** `accepted ≠ sent` due to intentional processors: Filter processors and sampling processors intentionally drop items. If `exporter_sent_*` < `receiver_accepted_*`, check whether the gap is expected (filter/sampler is configured) or accidental (memory_limiter is dropping). Use `processor_incoming_items_total` vs `processor_outgoing_items_total` to find which processor is responsible. (Inference from OTel pipeline model.)

- **[data-loss-errors]** `receiver_refused_*` followed by `send_failed_*` is the cascade failure pattern: First `receiver_refused` rises (backpressure from queue filling). If the backend does not recover, `queue_size` hits capacity and `send_failed` starts climbing. Watch for this sequence — the first signal is `refused`, the lagging signal is `send_failed`. (Confirmed: OTel pipeline architecture.)

- **[exporter-queue]** Default `queue_size` in OTLP exporter config is 1000 items: If the exporter is not explicitly configured, the default queue is small and may fill quickly during brief backend outages. Check `otelcol_exporter_queue_capacity` in Tsuga to see the actual configured limit. (Inference from OTel OTLP exporter defaults.)

- **[batch-processor]** `batch_timeout_trigger_send_total` dominates at night: During low-traffic periods, batches never fill to `send_batch_size` and always flush on the timeout. This naturally inverts ratio of size-triggered vs timeout-triggered sends. Normal variation — do not tune aggressively based on off-peak behavior alone. (Inference.)

- **[collector-resources]** Go heap allocation may grow during trace tail-sampling: If the collector is configured with `tail_sampling` processor, it holds entire traces in memory for the decision window (30–60s typical). `otelcol_process_runtime_heap_alloc_bytes` will be higher and more volatile than a stateless pipeline. (Inference from tail sampling architecture.)

---

## Confirmed Tsuga prefixes

- `otelcol_receiver_*` — **CONFIRMED** (15 metric series, 9 primary `_total` variants + 6 non-_total duplicates from a second deployment; all 9 pipeline metrics confirmed)
- `otelcol_exporter_*` — **CONFIRMED** (17 metric series, 8 core pipeline metrics + 2 new `enqueue_failed_*` metrics + histogram `queue_batch_send_size` + 6 non-_total duplicates)
- `otelcol_processor_*` — **CONFIRMED** (21 metric series: 8 original + 9 new metrics: dropped×3, inserted×3, refused×3 + 1 non-_total duplicate for batch_timeout_trigger_send)
- `otelcol_process_*` — **CONFIRMED** (10 metrics: cpu_seconds/cpu_seconds_total, memory_rss/memory_rss_bytes, runtime_heap_alloc_bytes, runtime_total_sys_memory_bytes, runtime_total_alloc_bytes/runtime_total_alloc_bytes_total, uptime/uptime_seconds_total)
- `process.*` — **NOT COLLECTOR METRICS** (process.cpu.utilization, process.memory.usage etc. exist in Tsuga but are emitted by Python/other application services — NOT by the OTel Collector itself, which uses otelcol_process_* namespace)

**Note on dual naming:** Both `_total` and non-`_total` variants exist for most counters (two different collector deployments or versions scraping into Tsuga). The `_total` variants have richer k8s context (`context.k8s.cluster.name`, `context.cloud.platform`). Always prefer `_total` variants for dashboard widgets.

**Note on `_total` suffix:** All `otelcol_*` counter metrics confirmed WITH `_total` suffix in the Tsuga environment (Prometheus scrape path). Stage 2 discovery confirmed delta temporality for all counters.

---

## Discovery status

**Stage 3 dashboard creation completed: 2026-02-19**

- **Overview dashboard:** ID `q3zk-2az23-8jer` — 58 widgets, 7 sections
- **Deep Dive dashboard:** ID `4jbh-5j0qt-kzfw` — 59 widgets, 7 sections
- All quality gates passed (0 errors, 0 warnings, deep coverage gate passed)
- Build script: `_build_opentelemetry-collector.py` (project root)

---

**Stage 2 discovery completed: 2026-02-19**

- 63 metrics discovered across 4 confirmed prefixes
- 25 core pipeline metrics: all confirmed
- 10 process metrics: all confirmed (using otelcol_process_* namespace, not process.*)
- 28 additional metrics: new unexpected metrics documented (enqueue_failed, dropped, inserted, refused at processor layer) + non-_total duplicates
- Context fields confirmed: `context.receiver`, `context.exporter`, `context.processor`, `context.transport`, `context.k8s.cluster.name`
- Context fields NOT present: `context.k8s.node.name`, `context.k8s.deployment.name`, `context.k8s.namespace.name` (removed from dashboard plan)
- Temporality: all counters confirmed delta → use `sum + per-second` (not `rate`)
- Process uptime: `otelcol_process_uptime_seconds_total` confirmed delta; use `sum + per-second` (not `max`)

Stage 2 priority targets:
1. Confirm `otelcol_*` metric presence with actual counts (expected: 25 metrics)
2. Verify `_total` suffix convention for this specific collector deployment
3. Confirm `context.receiver`, `context.exporter`, `context.processor` field names
4. Verify process-level metric namespace (`process.*` vs `otelcol_process_*`)
5. Confirm which k8s resource attributes are attached to otelcol_* metrics

---

## Top sources

1. **https://opentelemetry.io/docs/collector/internal-telemetry/** — Authoritative reference for all `otelcol_*` metric names, types, labels, and telemetry level configurations. Primary source for metric definitions.
2. **https://github.com/open-telemetry/opentelemetry-collector/blob/main/docs/observability.md** — Deep-dive on OTel Collector observability design, including the receiver/processor/exporter metric contract and the refused-vs-failed semantic distinction.
3. **https://opentelemetry.io/docs/collector/configuration/#telemetry** — Collector telemetry configuration: how to enable/disable self-metrics, metric levels (none/basic/normal/detailed), and OTLP self-export setup.
4. **https://opentelemetry.io/docs/collector/deployment/** — Deployment patterns (DaemonSet agent, gateway Deployment, sidecar), Kubernetes-specific resource attributes, and when to use each pattern.
5. **https://github.com/open-telemetry/opentelemetry-collector/tree/main/processor/memorylimiterprocessor** — Memory limiter processor: how it triggers, what it drops, and why refused_* rises with high memory usage.
6. **https://github.com/open-telemetry/opentelemetry-collector/tree/main/processor/batchprocessor** — Batch processor: send_batch_size, timeout configuration, metadata_cardinality, and the memory implications of high cardinality resource attributes.
7. **https://opentelemetry.io/docs/specs/otel/metrics/data-model/#temporality** — OTel metrics temporality specification: why OTel SDK defaults to delta and why Tsuga queries need `per-second` (not `rate`) for otelcol_* counters.
8. **https://opentelemetry.io/docs/kubernetes/helm/collector/** — OTel Collector Helm chart documentation for Kubernetes deployments: default configuration, resource attribute mapping, and common deployment patterns.
9. **https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/k8sattributesprocessor** — k8sattributes processor: how k8s.pod.name, k8s.node.name, k8s.namespace.name, k8s.deployment.name get attached to collector self-metrics via resource detection.
10. **https://opentelemetry.io/docs/collector/scaling/** — Scaling guide for OTel Collector on Kubernetes: horizontal scaling, HPA, tail sampling constraints, and gateway architecture patterns.
