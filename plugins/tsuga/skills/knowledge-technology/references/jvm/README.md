# JVM metrics Integration Context Bundle

## Metadata

- **Technology:** JVM metrics (OpenTelemetry `jvm.*` semantic conventions)
- **Deployment:** self-hosted (runtime embedded in Java applications)
- **Environment:** prod
- **Persona:** SRE Dev and ops
- **Telemetry preference:** mixed (OTel Java agent primary; JMX exporter fallback)
- **Integration scope:** core service only
- **Primary use-case:** reliability and performance
- **Confirmed namespace:** `jvm.` (Stage 2 verified — 12 metrics confirmed, 8 Development-status metrics absent)

---

## How to use this bundle

- `01_jvm-metrics_metrics.csv` — Source of truth for all metrics: names, types, units, safe aggregations, post-functions, and group-by dimensions.
- `02_jvm-metrics_dashboard_plan.yaml` — Dashboard structure: sections, widgets, derived signals (formulas), explanation notes, triage chains, and playbooks.
- `03_jvm-metrics_state.yaml` — Machine-readable stage status, assumptions, unknowns (especially OTel attribute field names in Tsuga), and open items Stage 2 must resolve.
- `04_jvm-metrics_memory.md` — Human-readable narrative of Stage 1 decisions, tradeoffs, and Stage 2 priorities.
- `05_jvm-metrics_metric_catalog.csv` — Stage 2 generated catalog: 12 confirmed metrics, pruned attribute keys, curated descriptions.
- Stage 4 should read the "Log intelligence (Stage 4 handoff)" section below and `03_jvm-metrics_state.yaml → log_intel` before creating log routes.

---

## What it is and what "good" looks like

The JVM (Java Virtual Machine) is the managed runtime environment that executes Java, Kotlin, Scala, and Clojure applications. Unlike service-level metrics (HTTP request rate, DB query latency), JVM metrics describe the **runtime health of the process itself**: memory pressure, garbage collection behavior, CPU time consumed, and thread utilization. Every Java service running on a JVM emits these metrics.

**What "good" looks like:**
- Heap utilization: 40–70% in steady state with a visible saw-tooth GC pattern (allocated then freed)
- Post-GC live set: stable over time; growing baseline = active memory leak
- GC pause p99: < 100 ms for G1/ZGC/Shenandoah minor GC; zero or near-zero major (full) GC events
- Blocked threads: < 2% of total threads; no sustained climbing trend
- JVM CPU utilization: < 80% sustained; spikes during GC are expected
- Metaspace: stable after JVM warmup (first 2–5 minutes); not approaching MaxMetaspaceSize limit

**Top 3 incident shapes:**
1. **Memory Leak / Heap Exhaustion** — Heap utilization climbs gradually, post-GC live set grows between restarts, GC rate increases but frees less each cycle → first section: `heap-memory` + `gc-pressure`
2. **GC Storm / Stop-the-World Freeze** — GC pause p99 spikes, major GC events appear, application latency jumps, CPU spikes during GC cycles → first section: `gc-pressure` + `cpu-utilization`
3. **Thread Contention / Deadlock** — Blocked thread count grows, runnable count flat, CPU low (threads waiting, not working), application throughput drops → first section: `threads`

**Confirmed by sources:** OTel semantic conventions define the exact metric names, types, and attributes. JVM MXBean API defines the pool name values. [https://opentelemetry.io/docs/specs/semconv/runtime/jvm-metrics/]

**Best-practice inference:** The "good" thresholds above are inferred from operational experience with G1 GC. ZGC and Shenandoah have sub-millisecond stop-the-world targets; adjust thresholds for those collectors accordingly.

---

## Key concepts

### Glossary

| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| Heap | JVM-managed memory region for object allocation; bounded by -Xmx | Primary memory resource; exhaustion = OOM | heap-memory |
| Non-Heap | JVM memory outside the heap: Metaspace, CodeCache, Compressed Class Space | Grows with class loading and JIT compilation | non-heap-buffers |
| GC (Garbage Collection) | Automatic reclamation of unreachable heap objects | Pauses application threads (STW) or runs concurrently | gc-pressure |
| Minor GC | GC event collecting the young generation (Eden + Survivor spaces) | Frequent, short; expected multiple times per minute | gc-pressure |
| Major GC / Full GC | GC event collecting the old generation (and sometimes the whole heap) | Infrequent, long; even one per hour for G1 is a warning sign | gc-pressure |
| Stop-the-World (STW) | GC phase during which all application threads are paused | Directly adds latency to all in-flight requests | gc-pressure |
| Eden Space | Young generation area where new objects are first allocated | High throughput here is normal; rapid exhaustion = high allocation rate | heap-memory |
| Survivor Space | Young generation holding objects that survived at least one minor GC | Growing survivors = objects living longer than expected | heap-memory |
| Old Gen | Long-lived objects promoted from young generation | Growing Old Gen after GC = live set growth or leak | heap-memory |
| Metaspace | Non-heap region holding class metadata (replaces PermGen since Java 8) | Unlimited by default; climbing = classloader leak | non-heap-buffers |
| CodeCache | Non-heap region holding JIT-compiled native code | Exhaustion disables JIT, causing severe CPU regression | non-heap-buffers |
| UpDownCounter | OTel instrument type representing a current value that can go up or down | Treated as gauge in Tsuga; do NOT apply per-second post-function | heap-memory, threads |
| Live Set | The actual amount of memory in use by live objects, measured post-GC | Best predictor of heap headroom; use jvm.memory.used_after_last_gc | heap-memory |
| G1 GC | Region-based garbage collector (default since Java 9); targets pause time goals | Separate minor (Young Gen) and major (Old Gen) GC events | gc-pressure |
| ZGC | Ultra-low-latency GC (Java 11+); sub-millisecond pauses for terabyte heaps | "Pause" metrics show very low values; "cycle" metrics show total concurrent work | gc-pressure |
| Shenandoah | Low-latency GC (Red Hat); concurrent evacuation | Similar to ZGC in pause profile; different pool names | gc-pressure |
| Direct Buffer | NIO ByteBuffer allocated outside heap via allocateDirect() | Off-heap; NOT visible in heap metrics; leaks cause native OOM | non-heap-buffers |
| Mapped Buffer | Memory-mapped files via FileChannel.map() | Used by RocksDB, Lucene, Chronicle Map; large allocations are expected | non-heap-buffers |
| Thread State | Java thread lifecycle state: runnable, blocked, waiting, timed_waiting, new, terminated | Blocked = contention; waiting = idle pool threads (normal) | threads |
| Platform Thread | OS-managed Java thread (1:1 with OS thread); counted by jvm.thread.count | Java 21+ virtual threads are NOT counted here | threads |
| Virtual Thread | Lightweight thread (Project Loom, Java 21+); NOT measured by jvm.thread.count | If your service uses virtual threads, jvm.thread.count is misleading | threads |
| Allocation Rate | Rate at which new objects are created in Eden Space | High allocation rate = frequent minor GC; not measured directly in OTel jvm.* | heap-memory |

### Concept Map

```
Client requests → Application threads (runnable) → allocate objects → Eden Space (heap)
Eden Space → fills up → triggers Minor GC → evacuates to Survivor Space or Old Gen
Survivor Space → fills beyond threshold → promotes to Old Gen
Old Gen → fills up → triggers Major GC → stop-the-world pause → application latency spikes
Major GC → if heap 100% full → OutOfMemoryError (heap) → JVM crash or OOM kill

JVM process → executes bytecode → JIT compiler → compiles hot paths → stores in CodeCache
CodeCache → fills up → JIT disabled → CPU spike (interpreted execution is 10-100x slower)

Class loader → loads new class definitions → stores metadata in Metaspace
Metaspace → grows with class count → if MaxMetaspaceSize hit → OutOfMemoryError (Metaspace)
Classloader leak → orphaned classloaders not GC'd → Metaspace climbs after each redeploy

Application threads → request JVM CPU time → jvm.cpu.recent_utilization rises
GC threads → also consume CPU → GC overhead = cpu time during STW + concurrent GC
GC overhead > 98% (GCOverheadLimitExceeded) → JVM throws OOM as safety valve

Netty/gRPC/Kafka → allocate direct ByteBuffers → off-heap (not in jvm.memory.used[heap])
Direct buffer leak → jvm.buffer.memory.used[direct] climbs → native OOM → crash without heap warning

Thread pool → creates platform threads → monitored by jvm.thread.count
Lock contention → threads block on synchronized → jvm.thread.count[blocked] rises
Blocked threads → CPU drops → throughput collapses → latency climbs
Thread deadlock → blocked count never recovers → requires thread dump analysis

service.name (OTel resource) → maps to context.service.name in Tsuga → primary group-by
deployment.environment → maps to context.env → global filter
k8s.namespace.name → maps to context.k8s.namespace.name → secondary filter
jvm.memory.pool.name → metric attribute → context.jvm.memory.pool.name in Tsuga (CONFIRMED Stage 2)
```

### Entities and dimensions

| Dimension | Why useful | Cardinality risk | Safe top-N | Do NOT group-by |
|---|---|---|---|---|
| `context.service.name` | Primary entity — one JVM per service instance | Medium (10s–100s of services) | top 10 | — |
| `context.env` | Separates prod vs staging JVM behavior | Low (2–5 values) | — (filter, not group-by) | — |
| `context.team` | Ownership routing | Low (10–30 teams) | top 10 | — |
| `context.k8s.cluster.name` | JVM behavior varies by cluster (node sizes, limits) | Low (2–10 clusters) | top 5 | — |
| `context.k8s.namespace.name` | Workload isolation boundary | Medium (10s–100s) | top 10 | — |
| `context.k8s.pod.name` | Individual pod JVM (noisy neighbors, OOM kills) | HIGH (1000s) | top 10 only in deep dive | Do NOT use in overview |
| `jvm.memory.pool.name` | Memory pool breakdown (Old Gen, Metaspace, etc.) | Low (5–8 values per GC) | all (< 10 values) | — |
| `jvm.memory.type` | Heap vs non-heap separation | Very low (2 values) | all | — |
| `jvm.gc.action` | Minor vs major GC distinction | Very low (2 values) | all | — |
| `jvm.gc.name` | Collector-specific GC event name | Low (2–3 values per JVM) | all | — |
| `jvm.gc.cause` | Why GC was triggered (Development status) | Low (3–10 values) | top 5 | — |
| `jvm.thread.state` | Thread lifecycle state | Very low (6 values) | all | — |
| `jvm.thread.daemon` | Daemon vs user thread split | Very low (2 values) | all | — |
| `jvm.buffer.pool.name` | Direct vs mapped buffer separation | Very low (2 values) | all | — |
| `process.pid` | Individual JVM process identity | HIGH (varies per pod restart) | — | Do NOT group-by — use service.name |

**Note:** `jvm.memory.pool.name`, `jvm.gc.action`, `jvm.gc.name`, `jvm.thread.state`, `jvm.buffer.pool.name` are OTel metric-level attributes, NOT OTel resource attributes. **Stage 2 confirmed** their Tsuga field names are prefixed with `context.jvm.` (e.g., `context.jvm.memory.pool.name`). All 02 dashboard plan filters and group-by fields have been updated accordingly.

### Tsuga field mapping

**OTel resource attributes → context.\* fields (used in global filters and group-by):**

| OTel resource attribute | Recommended context.\* key | Must-exist vs optional |
|---|---|---|
| `service.name` | `context.service.name` | Must-exist — primary JVM identity |
| `deployment.environment` | `context.env` | Must-exist (confirmed in .env) |
| `service.namespace` | `context.team` | Optional (confirmed in .env) |
| `k8s.cluster.name` | `context.k8s.cluster.name` | Optional (k8s deployments) |
| `k8s.namespace.name` | `context.k8s.namespace.name` | Optional (k8s deployments) |
| `k8s.pod.name` | `context.k8s.pod.name` | Optional (high cardinality — use carefully) |
| `k8s.node.name` | `context.k8s.node.name` | Optional (k8s deployments) |
| `host.name` | `context.host.name` | Optional (non-k8s deployments) |
| `process.pid` | Unknown — likely `context.process.pid` | Do NOT group-by (high cardinality) |

**OTel metric-level attributes → metric dimension filters (CONFIRMED Stage 2):**

| OTel metric attribute | OTel metric(s) | Tsuga field (confirmed) | Notes |
|---|---|---|---|
| `jvm.memory.pool.name` | jvm.memory.* | `context.jvm.memory.pool.name` | GC-specific values (G1 Eden Space, Metaspace, etc.) — pool names not yet enumerated |
| `jvm.memory.type` | jvm.memory.* | `context.jvm.memory.type` | `heap` or `non_heap` |
| `jvm.gc.action` | jvm.gc.duration | `context.jvm.gc.action` | `end of minor GC` or `end of major GC` |
| `jvm.gc.name` | jvm.gc.duration | `context.jvm.gc.name` | GC-specific (G1 Young Generation, etc.) |
| `jvm.gc.cause` | jvm.gc.duration | Not confirmed (Development status — metric absent) | Not enumerated |
| `jvm.thread.state` | jvm.thread.count | `context.jvm.thread.state` | runnable, blocked, waiting, timed_waiting, new, terminated |
| `jvm.thread.daemon` | jvm.thread.count | `context.jvm.thread.daemon` | `true` or `false` |
| `jvm.buffer.pool.name` | jvm.buffer.* | `context.jvm.buffer.pool.name` | `direct` or `mapped` (Development-status metrics — absent in this env) |

**Confirmed Stage 2:** All metric attribute field names confirmed via `tsuga_build_metric_catalog.py` discovery. `context.service.name` confirmed present on all 12 metrics. `context.k8s.*` fields confirmed present. All 02 dashboard plan filters/group-by fields updated to use `context.jvm.*` prefix.

---

## Golden signals

### Traffic (proxy: active thread count + class loading rate)

JVM metrics do not directly measure application traffic (HTTP requests, DB queries — those are application-layer). The best traffic proxies are:
- **Runnable thread count** (`jvm.thread.count[runnable]`): threads actively doing work scale with load
- **Class load rate** (`jvm.class.loaded` rate): spikes during deployments or hot-reload events

**Typical causes of degradation:** thread pool exhaustion under load, class loading storms (dynamic proxies, CGLIB), blocked threads reducing effective throughput.

**What people escalate on:** "API is timing out but CPU looks normal" = likely blocked threads stealing capacity from runnable threads.

**Section questions this answers:** Threads by State, Total Threads trend.

**Confirmed by sources:** Thread state semantics from JVM ThreadMXBean [https://docs.oracle.com/en/java/docs/api/java.management/java/lang/management/ThreadMXBean.html]
**Best-practice inference:** Using runnable thread count as a traffic proxy is an industry convention for JVM observability.

### Errors (heap OOM, metaspace OOM, GC overhead exceeded)

JVM "errors" are resource exhaustion events, not application errors:
- **Heap OOM**: `jvm.memory.used[heap]` ≈ `jvm.memory.limit[heap]` AND GC rate maxing out with no relief
- **Metaspace OOM**: `jvm.memory.used[Metaspace]` ≈ `jvm.memory.committed[Metaspace]` climbing without bound
- **GC Overhead Limit Exceeded**: JVM safety valve — throws OOM when > 98% of CPU time is spent in GC; hard to detect before the crash

**Typical causes:** Memory leaks (retained references), classloader leaks (redeploy without full GC), direct buffer leaks (Netty), unbounded cache growth.

**What people escalate on:** "JVM OOM killed" alerts from k8s; these dashboards help identify which exhaustion type caused the kill.

**Section questions this answers:** Heap Utilization (%), Old Gen Pressure (%), Metaspace Pressure (%), GC Pause p95.

**Confirmed by sources:** Java OOM error types [https://docs.oracle.com/en/java/docs/api/java.base/java/lang/OutOfMemoryError.html]
**Best-practice inference:** GC overhead threshold of 98% is a JVM default; actual OOM timing depends on heap size and allocation rate.

### Latency (GC pause duration)

GC stop-the-world pauses are direct application latency additions. During a major GC pause, ALL application threads are frozen. A 500ms full GC = 500ms added to every in-flight request's latency.

- **Primary signal:** `jvm.gc.duration` percentile(p95/p99) filtered to `jvm.gc.action=end of major GC`
- **Secondary:** p95 of ALL GC pauses (including minor) for latency baseline

**What people escalate on:** p99 latency SLO breach coinciding with GC pause spikes (correlation usually visible with 1–2min time alignment).

**Section questions this answers:** GC Pause p95, Major GC Time Ratio (%), GC Duration by Collector.

**Confirmed by sources:** OTel jvm.gc.duration semantics [https://opentelemetry.io/docs/specs/semconv/runtime/jvm-metrics/]
**Best-practice inference:** The correlation between GC pauses and application latency SLOs is documented in G1 GC tuning guides [https://www.oracle.com/technical-resources/articles/java/g1gc.html]

### Saturation (memory %, threads, CPU, file descriptors)

JVM saturation is multi-dimensional:
- **Heap saturation**: Heap Utilization (%) approaching 85–90% after GC = imminent OOM
- **Thread saturation**: Blocked Thread Ratio (%) > 5% sustained = lock contention
- **CPU saturation**: JVM CPU Utilization > 80% sustained (especially if driven by GC)
- **File descriptor saturation**: File Descriptor Utilization (%) > 80% = risk of "Too many open files"
- **Direct buffer saturation**: Direct Buffer Utilization (%) > 80% = risk of native OOM

**Typical causes:** Undersized heap, insufficient thread pools, CPU-intensive computation without parallelism limits, FD leaks in frameworks.

**What people escalate on:** k8s OOM kills (heap or native), application 503s from thread exhaustion.

**Section questions this answers:** All sections — saturation is cross-cutting.

**Confirmed by sources:** JVM tuning literature; OTel jvm.cpu.recent_utilization semantics.
**Best-practice inference:** Thresholds are industry conventions; tune per workload.

---

## Telemetry sources

| Source type | How collected | What it provides | Pros | Cons | Common pitfalls |
|---|---|---|---|---|---|
| OTel Java Agent (automatic) | Attach `-javaagent:opentelemetry-javaagent.jar` | All `jvm.*` semconv metrics auto-collected from MXBeans | Zero code change; covers full jvm.* namespace; actively maintained | Requires agent attachment; small overhead (~1% CPU) | Agent version matters: `jvm.*` namespace only available in agent >= 2.0 (semconv 1.21+). Older agents emit `process.runtime.jvm.*` — check version! |
| OTel Java SDK (manual) | Instrument code with OTel SDK; call JvmObservabilityInstrumenter | Same metrics as agent but with manual control | Fine-grained control | Developer effort; easy to miss metrics | Development-stability metrics (buffer, file_descriptor) may not be enabled by default in SDK |
| JMX Exporter (Prometheus) | Run as javaagent or separate process; scrape /metrics | JVM MXBean metrics but with Prometheus naming | Widely used; good k8s support | Different metric names (`process_runtime_jvm_*`); requires prometheus_jmx_exporter | Metric names differ from OTel semconv — dashboards built for `jvm.*` will not find JMX exporter data |
| OTel JMX Metrics Receiver | OTEL Collector JMX receiver; scrapes JVM MXBeans | `jvm.*` namespace compliant | Works with OTel Collector pipelines | Requires JMX port exposure; additional config | JMX port exposure is a security concern in some environments |
| Spring Boot Actuator + Micrometer | Spring apps; exposes /actuator/metrics | JVM metrics via Micrometer (mapped to OTel on export) | Native to Spring; no agent needed | Micrometer ↔ OTel name mapping may introduce drift | Some Micrometer metric names differ from OTel semconv; verify `jvm.*` naming in your OTel exporter |
| "No data" diagnosis | — | — | — | — | Check: (1) agent version (need >= 2.0), (2) OTEL_METRICS_EXPORTER env var set, (3) correct namespace in collector routing, (4) Development-status metrics may be disabled by feature flag |

**Confirmed by sources:** Agent capabilities [https://github.com/open-telemetry/opentelemetry-java-instrumentation/blob/main/instrumentation/runtime-telemetry/runtime-telemetry-java8/library/README.md]
**Best-practice inference:** JMX Exporter as fallback, feature flag status for Development metrics.

---

## Log intelligence (Stage 4 handoff)

### Confirmed by sources

The JVM itself produces several distinct log streams. Java application logs are app-specific (format defined by the application), but JVM-generated logs have known formats.

**Log sources matrix:**

| Source | Access path | Typical format | Structured vs unstructured | Evidence |
|---|---|---|---|---|
| GC Logs | `-Xlog:gc*:file=gc.log` JVM flag | GC-specific structured text | Semi-structured (GC-specific fields) | [https://openjdk.org/jeps/271] |
| JVM crash logs | `hs_err_pid<PID>.log` in working dir | Fixed-section free text | Unstructured | OpenJDK crash report format |
| Application logs | Application-defined (log4j, logback, slf4j) | JSON, logfmt, or plain text | Varies by framework config | — |
| k8s stdout/stderr | Pod stdout captured by container runtime | Application-dependent | Depends on logger config | — |

**Known log formats:**

**GC Log (Unified Logging, Java 9+, -Xlog:gc*):**
```
[2024-01-15T10:23:45.123+0000][gc] GC(42) Pause Young (Normal) (G1 Evacuation Pause) 512M->256M(2048M) 45.234ms
[2024-01-15T10:23:50.456+0000][gc,heap] GC(42) Heap before GC invocations=42 (full 0):
[2024-01-15T10:24:00.789+0000][gc] GC(43) Pause Full (System.gc()) 1024M->512M(2048M) 1234.567ms
```
- Timestamp: ISO 8601 with timezone offset
- GC number in parentheses: `GC(N)`
- Action: `Pause Young`, `Pause Full`, `Pause Remark`, etc.
- Memory: `before->after(max)` in MB
- Duration: milliseconds at end

**Application Log (Logback JSON layout, common Spring Boot):**
```json
{"timestamp":"2024-01-15T10:23:45.123Z","level":"ERROR","logger":"c.e.MyService","message":"Connection pool exhausted","service":"my-service","trace":"abc123"}
```

### Best-practice inference

Most Java services in k8s log to stdout as JSON (Spring Boot + Logback JSON encoder is the de facto standard). GC logs are usually written to a separate file and may not be in the k8s log stream unless explicitly redirected.

**Candidate query filters for Stage 4:**
1. **Precise:** `context.service.name:<service-slug> AND source:stdout` — captures application logs for a specific service; rationale: JVM app logs go to stdout in k8s
2. **Broader fallback:** `context.k8s.namespace.name:<namespace>` — captures all services in a namespace; risk: high volume, may include non-Java services

**Attribute mapping hints:**

| Raw field (logback JSON) | Suggested Tsuga key | Confidence | Notes |
|---|---|---|---|
| `timestamp` | `timestamp` | High | ISO 8601; parse as timestamp |
| `level` | `log.level` | High | Standard log level field |
| `logger` | `log.logger` | Medium | Logger class name |
| `message` | `message` | High | Log message body |
| `service` | `context.service.name` | Medium | May be `service.name` in OTel-enriched logs |
| `trace` | `trace.id` | Medium | Trace correlation ID |
| `thread` | `thread.name` | Medium | Thread name (logback default) |

**Parsing risks:**
- Multiline: GC logs span multiple lines per GC event; application stack traces are multiline
- Format variability: Different Java frameworks use different JSON keys (`@timestamp` vs `timestamp`, `msg` vs `message`)
- No canonical log format: JVM metrics use OTel but logs use application-specific frameworks
- GC log rotation: GC log files are rotated separately from application logs; may not appear in k8s log stream

---

## Caveats and footguns

- **[heap-memory]** `jvm.memory.used` aggregated across ALL pools includes both heap and non-heap. Always filter by `jvm.memory.type:heap` for heap-specific widgets; without this filter, values are inflated. (Confirmed — OTel semconv attribute definition)

- **[heap-memory]** `jvm.memory.limit` is the JVM-configured max heap (`-Xmx`), not total host memory. Heap Utilization (%) must compare `used[heap]` to `limit[heap]`, not to available RAM. (Confirmed — OTel semconv)

- **[heap-memory]** Instantaneous `jvm.memory.used[heap]` oscillates naturally in a saw-tooth pattern between GC cycles. Point-in-time snapshots are noisy. Use a 5-minute average or look at the trend. The peak of each saw-tooth cycle should be your alert baseline. (Best-practice inference)

- **[heap-memory]** `jvm.memory.used_after_last_gc` is the ground truth for live object size. Use it for leak detection, not `jvm.memory.used`. A service where `used_after_last_gc` grows monotonically between restarts has a memory leak. (Confirmed — OTel semconv: "Measure of memory used, after the most recent garbage collection event on this pool")

- **[heap-memory]** Memory pool names are GC-specific and differ between collectors (G1: `G1 Eden Space`, `G1 Old Gen`; Parallel: `PS Eden Space`, `PS Old Gen`; ZGC: `ZHeap`). Widgets that filter by a specific pool name will show no data for services using a different GC. Gate accordingly or group-by pool name. (Confirmed — JVM MXBean API docs)

- **[heap-memory, gc-pressure]** `jvm.memory.*` instruments are UpDownCounter (semantically a gauge). Do NOT apply `per-second` or `rate` post-functions to these metrics — they will produce nonsensical values. Use `sum` or `average` aggregation with `none` post-function. (Confirmed — OTel semconv instrument type)

- **[gc-pressure]** `jvm.gc.duration` is a histogram. Percentile aggregations (`percentile(p95)`) require Tsuga histogram support. Verify in Stage 2 whether this metric appears with histogram bucket data or only as a scalar sum/count. (Best-practice inference — Tsuga-specific)

- **[gc-pressure]** Minor GC (young generation) pauses are expected and frequent (every 1–30 seconds under normal load for G1). Do NOT alert on minor GC frequency alone. Alert on MAJOR GC pause duration and rate. (Confirmed — G1 GC tuning guide)

- **[gc-pressure]** For ZGC and Shenandoah, "major GC" events (`jvm.gc.action=end of major GC`) represent concurrent cycles, not stop-the-world freezes. Their "major GC" pause times target < 1ms. Apply different alert thresholds for these collectors vs G1. (Confirmed — ZGC and Shenandoah documentation)

- **[gc-pressure]** `jvm.gc.cause` attribute has Development stability status and may not be emitted by default in all OTel agent versions. Widgets that filter or group by GC cause must be gated on this attribute's availability. (Confirmed — OTel semconv stability marker)

- **[gc-pressure]** A single G1 Full GC event (not G1 Young Generation — those are normal) is almost always a signal worth investigating. Even 1 per hour is unusual in healthy production systems. (Best-practice inference)

- **[threads]** `jvm.thread.count` measures **platform threads only**. Java 21+ applications using virtual threads (Project Loom) will appear to have very low thread counts. If the service uses virtual threads, this metric significantly underrepresents concurrency. (Confirmed — OTel semconv: "Number of executing platform threads")

- **[threads]** `waiting` thread state is normal for idle thread pool workers. A spike in `waiting` alone is not concerning. Only alert when `waiting` increases while `runnable` decreases — that indicates threads are waiting for work that isn't arriving (possible upstream starvation). (Best-practice inference)

- **[threads]** Thread state is a snapshot taken at the OTel scrape interval (default 1 minute). Blocked threads that resolve within one scrape interval will not appear. Short-lived contention spikes are invisible unless scrape interval is reduced. (Best-practice inference)

- **[cpu-utilization]** `jvm.cpu.recent_utilization` is a ratio from 0.0 to 1.0 relative to all available CPUs. A value of 1.0 on a 4-CPU pod means 400% in top(1) notation. Always display this with `context.jvm.cpu.count` for interpretation. (Confirmed — OTel semconv: "Recent CPU utilization for the process ... 1.0 means maximum usage of all CPUs")

- **[cpu-utilization]** High `jvm.cpu.recent_utilization` during high GC rate = GC consuming CPU. High CPU during low GC rate = computation work. These require different remediation. Look at GC rate in tandem. (Best-practice inference)

- **[cpu-utilization]** `jvm.system.cpu.utilization` and `jvm.system.cpu.load_1m` have Development stability status and may not be available in all OTel agent versions (requires the runtime-telemetry-java17 module). Gate these widgets. (Confirmed — OTel semconv stability marker)

- **[non-heap-buffers]** Direct buffer memory (`jvm.buffer.memory.used[direct]`) is **entirely off-heap** and does NOT appear in `jvm.memory.used[heap]`. A JVM can look perfectly healthy on heap metrics while native memory is close to OOM. Always monitor direct buffers for Netty, gRPC, Kafka client, and NIO-heavy services. (Confirmed — JVM BufferPoolMXBean docs)

- **[non-heap-buffers]** Metaspace has no hard limit by default (`-XX:MaxMetaspaceSize` not set). `jvm.memory.limit[Metaspace]` may be 0 or very large. Use `jvm.memory.committed[Metaspace]` as the denominator for Metaspace pressure calculation. (Confirmed — Java 8+ Metaspace behavior)

- **[non-heap-buffers]** `jvm.buffer.*` metrics have Development stability status and may not be enabled by default. Check OTel agent configuration for `otel.instrumentation.jvm.enabled` or equivalent feature flags. (Confirmed — OTel semconv stability marker)

- **[class-loading]** `jvm.class.count` has Development stability status in OTel semconv but is **confirmed present** in this Tsuga environment (Stage 2 verified). Used directly in dashboards. If absent in other environments, fall back to tracking `jvm.class.loaded` minus `jvm.class.unloaded` as a class count proxy. (Stage 2 confirmed — present in 05 catalog)

- **[class-loading]** Class count grows during JVM startup and stabilizes after warmup (typically 2–5 minutes). A class count that keeps growing after warmup = classloader leak. Each redeploy that doesn't restart the JVM compounds the leak. (Best-practice inference)

---

## Confirmed Tsuga prefixes

- `jvm.` — **CONFIRMED** (Stage 2 verified via `tsuga_build_metric_catalog.py`; 12 metrics present; 8 Development-status metrics absent — see 05 catalog)

---

## Discovery status

Discovery: **Stage 2 complete** (2026-02-24). Access method: Tsuga CLI v1.0.2 via `tsuga_search_metrics.py` + `tsuga_build_metric_catalog.py`.

**Results:**
- Prefix `jvm.`: **12 metrics confirmed**
- Metrics absent (all Development-status): `jvm.memory.init`, `jvm.system.cpu.utilization`, `jvm.system.cpu.load_1m`, `jvm.buffer.memory.used`, `jvm.buffer.memory.limit`, `jvm.buffer.count`, `jvm.file_descriptor.count`, `jvm.file_descriptor.limit`
- OTel metric attribute field naming confirmed: `jvm.*` attributes accessed as `context.jvm.*` in Tsuga
- `context.service.name` confirmed on all 12 metrics
- Histogram support for `jvm.gc.duration`: inconclusive (spot-check API returned 500 errors; handled gracefully in Stage 3)
- GC pool names (u02): not yet enumerated — Old Gen Pressure widget filter uses `context.jvm.memory.pool.name:G1 Old Gen` (G1 assumed); validate in Tsuga dashboards

## Dashboard status

**Stage 3 complete** (2026-02-24).

| Dashboard | Tsuga ID | Widgets |
|---|---|---|
| [Integration] JVM metrics - Overview | `f0hj-26a5t-72pw` | 45 |
| [Integration] JVM metrics - Deep Dive | `58c5-6jb6q-mw3j` | 51 |

---

## Top sources

1. **https://opentelemetry.io/docs/specs/semconv/runtime/jvm-metrics/** — OTel canonical reference for all `jvm.*` metric names, types, units, attributes, and stability status. Primary source for all metric definitions in this bundle.

2. **https://opentelemetry.io/docs/specs/semconv/attributes-registry/jvm/** — OTel attribute registry for jvm.* attribute names and values (pool names, thread states, GC actions). Primary source for all dimension values.

3. **https://github.com/open-telemetry/opentelemetry-java-instrumentation/blob/main/instrumentation/runtime-telemetry/runtime-telemetry-java8/library/README.md** — Java 8+ OTel runtime telemetry library; defines which metrics are collected and their MXBean sources.

4. **https://github.com/open-telemetry/opentelemetry-java-instrumentation/blob/main/instrumentation/runtime-telemetry/runtime-telemetry-java17/library/README.md** — Java 17+ telemetry library; defines Development-status JFR-based metrics (cpu.context_switch, memory.allocation, network.io).

5. **https://docs.oracle.com/en/java/docs/api/java.management/java/lang/management/MemoryPoolMXBean.html** — JVM MemoryPoolMXBean API; canonical source for pool name values and their semantics.

6. **https://docs.oracle.com/en/java/docs/api/java.management/java/lang/management/GarbageCollectorMXBean.html** — JVM GarbageCollectorMXBean API; GC notification info for GC name/action values.

7. **https://www.oracle.com/technical-resources/articles/java/g1gc.html** — Oracle G1 GC tuning guide; defines minor vs major GC semantics, pause time goals, and operational thresholds.

8. **https://openjdk.org/jeps/318** — ZGC design JEP; explains ultra-low-latency GC architecture and why ZGC "major GC" events are concurrent, not stop-the-world.

9. **https://openjdk.org/jeps/271** — Unified JVM logging (JEP 271); defines GC log format used in Java 9+ (-Xlog:gc* flag).

10. **https://grafana.com/grafana/dashboards/18812-jvm-overview-opentelemetry/** — Grafana Labs JVM Overview OTel dashboard; reference for industry-standard widget groupings and derived signals for jvm.* metrics.
