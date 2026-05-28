# MySQL Integration Context Bundle

## Metadata
- **Technology:** MySQL
- **Deployment:** self-hosted
- **Environment:** prod
- **Persona:** SRE Dev and ops
- **Telemetry preference:** mixed (OTel receiver primary; Prometheus mysqld_exporter secondary)
- **Integration scope:** core service only
- **Primary use-case:** reliability and performance

---

## How to use this bundle
- `01_mysql_metrics.csv` — Source of truth for all metrics: names, units, types, safe aggregations, group-by fields. Start here to understand what is measurable.
- `02_mysql_dashboard_plan.yaml` — Dashboard blueprint: sections, widgets, derived signals, explanation notes, triage chains, and playbooks. Stage 3 reads this to build dashboards.
- `03_mysql_state.yaml` — Machine-readable state: stage status, inferred prefixes, assumptions, unknowns (with gating language and verification steps).
- `04_mysql_memory.md` — Human-readable Stage 1 summary: key assumptions, open unknowns, Stage 2 priority checks.
- Stage 2 will generate `05_mysql_metric_catalog.csv` — the discovered metric inventory with curated attribute keys and descriptions. Cross-reference with `01` to confirm names, temporality, and available attribute keys.
- Stage 4 should read `## Log intelligence (Stage 4 handoff)` in this file and `log_intel` in `03_mysql_state.yaml` before designing log routes.

---

## What it is and what "good" looks like

MySQL is a widely deployed open-source relational database. In Kubernetes and self-hosted environments, it underpins application data persistence for web, e-commerce, SaaS, and analytics workloads.

**What "good" looks like:**
- Uptime is sustained (no unexpected restarts).
- Thread utilization (running/connected) stays below 80%.
- InnoDB buffer pool hit rate is above 99% — nearly all reads come from memory, not disk.
- Query rate is stable or tracking expected traffic patterns.
- Slow queries are rare (<0.1% of total queries) and not trending upward.
- Row lock waits are near-zero; no long-running blocking transactions.
- Replica lag is zero or single-digit seconds; both IO and SQL threads are running.
- Tmp disk tables ratio is below 10%; sorts do not overflow to merge passes.

**Top 3 incident shapes:**

| Incident | First dashboard section to open |
|---|---|
| Sudden spike in response time / app latency | `performance-io-latency` → table I/O wait time, then `locks-contention` |
| Connection exhaustion (`too many connections`) | `availability-health` → thread counts, then `throughput-query-rate` |
| Replication lag alarm | `replication` → lag trend, then `storage-operations` (log writes) |

**Confirmed by sources:**
- OTel MySQL receiver metrics confirmed via opentelemetry-collector-contrib `metadata.yaml` and `documentation.md` (https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/mysqlreceiver/documentation.md)
- MySQL 8.0 status variables confirmed via https://dev.mysql.com/doc/refman/8.0/en/server-status-variables.html

**Best-practice inference:**
- Buffer pool hit rate >99% is a generally accepted SRE target for production MySQL. Exact threshold is workload-dependent.
- Thread utilization thresholds are organizational conventions; paging rules vary.

---

## Key concepts

### Glossary

| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| InnoDB buffer pool | In-memory cache for InnoDB data and index pages | Primary performance lever — low hit rate means disk I/O bottleneck | buffer-pool-memory |
| Buffer pool hit rate | (read_requests - physical_reads) / read_requests | Values below 99% indicate working set exceeds buffer pool size | buffer-pool-memory |
| Dirty pages | Buffer pool pages modified but not yet flushed to disk | High dirty page count increases crash recovery time | buffer-pool-memory |
| Threads_running | Threads actively executing a query right now | High value = server is under query load; spikes = slow queries piling up | availability-health |
| Threads_connected | Total open connections to MySQL | Approaching max_connections = imminent connection exhaustion | availability-health |
| Handler operations | Low-level storage engine row access operations | Handler_read_rnd_next high = full-table scans; handler_write = mutation rate | throughput-query-rate |
| Slow query log | Queries exceeding long_query_time threshold | Leading indicator of performance degradation; drives index optimization | performance-io-latency |
| InnoDB row lock | Lock on individual rows for concurrent write isolation | Lock waits = blocking; high wait time = potential deadlock risk | locks-contention |
| Table lock | Lock on entire table (MyISAM or DDL operations) | InnoDB minimizes table locks; high waited count = DDL or MyISAM activity | locks-contention |
| Replication | Asynchronous or semi-sync log shipping from source to replica | Seconds_Behind_Source = lag; both IO and SQL threads must run | replication |
| Binary log (binlog) | Sequential log of all DDL/DML changes | Feeds replication; enables point-in-time recovery | replication, storage-operations |
| Relay log | Replica-side copy of source's binlog events | Size grows when SQL thread falls behind IO thread | replication |
| Seconds_Behind_Source | Replica SQL thread lag vs source timestamp | Zero = healthy; growing = replica cannot keep up; can be misleading on idle source | replication |
| InnoDB doublewrite buffer | Two-phase write to prevent partial-page corruption on crash | Adds ~5-10% write overhead; disabling unsafe except on battery-backed storage | storage-operations |
| Sort merge passes | Extra sort passes when sort_buffer_size is too small | Each merge pass = extra disk I/O; leading indicator to tune sort_buffer_size | performance-io-latency |
| Tmp disk tables | Temporary tables that spill to disk from memory | High ratio = undersized tmp_table_size / max_heap_table_size | throughput-query-rate |
| Performance Schema | MySQL subsystem for query-level instrumentation | Provides per-digest statement metrics; disabled or limited by default | performance-io-latency |
| GTID | Global Transaction Identifier | Enables consistent replica positioning; required for safe failover | replication |
| max_connections | Maximum simultaneous client connections (config) | Hard limit; not exposed as OTel metric; infer saturation from threads_connected | availability-health |
| innodb_buffer_pool_size | Configured InnoDB buffer pool size (config) | Must be >50-70% of RAM for database servers; exposed as mysql.buffer_pool.limit | buffer-pool-memory |
| Connection errors | Failed connection attempts (per error type) | Aborted_connects = auth failures; Connection_errors_max_connections = saturation | availability-health |
| Opened tables | Tables opened since startup (or from table cache) | High opened_tables rate = table_open_cache too small; cache thrashing | storage-operations |
| InnoDB log | Redo log files used for crash recovery | Log waits = redo log too small; log write volume = write workload intensity | storage-operations |

### Concept Map

```
Client application -> sends queries -> MySQL connection handler
MySQL connection handler -> uses -> Thread (per connection or thread pool)
Thread -> executes query -> InnoDB storage engine
InnoDB storage engine -> checks -> InnoDB buffer pool (in-memory cache)
InnoDB buffer pool -> hit: returns data from memory -> Thread
InnoDB buffer pool -> miss: reads page from disk -> InnoDB data files -> Thread
InnoDB buffer pool -> dirty pages -> background flush -> InnoDB data files
Thread -> modifies row -> acquires -> InnoDB row lock
InnoDB row lock -> conflict: waits -> blocking transaction -> lock waits increase
Thread -> creates temp result -> tmp_table_size check -> memory temp table (fast)
tmp_table_size exceeded -> spills to disk temp table -> Created_tmp_disk_tables increases
Thread -> runs sort -> sort_buffer_size check -> in-memory sort (fast)
sort_buffer_size exceeded -> Sort_merge_passes increases -> disk I/O for sort
MySQL source -> writes changes to -> Binary log (binlog)
Binary log -> replicated to -> Replica IO thread -> Relay log
Relay log -> applied by -> Replica SQL thread -> Replica data files
Replica SQL thread -> lags -> Seconds_Behind_Source increases
max_connections reached -> new connections rejected -> Connection_errors_max_connections
InnoDB buffer pool limit -> set by -> innodb_buffer_pool_size configuration
Low buffer pool hit rate -> indicates -> working set > buffer pool size -> scale up RAM
High Threads_running -> indicates -> slow queries or lock waits piling up -> check locks
```

### Entities and dimensions

| Entity/Dimension | Why useful | Cardinality risk | Safe top-N | Do NOT group-by |
|---|---|---|---|---|
| MySQL instance (context.scope) | Per-instance breakdown for multi-instance deployments | Low-medium (1-50 instances) | 10 | - |
| k8s cluster (context.k8s.cluster.name) | Cross-cluster comparison | Low | 10 | - |
| k8s namespace (context.k8s.namespace.name) | Namespace-level ownership | Low-medium | 10 | - |
| Schema / Database (context.schema) | Per-database breakdown for slow queries and I/O | Medium (tens of schemas) | 20 | - |
| Table name (context.table) | Top tables by I/O wait and lock waits | HIGH — potentially thousands | 20 | Avoid in timeseries |
| Index name (context.index) | Hot index I/O analysis | HIGH — potentially thousands | 20 | Avoid in timeseries |
| Operation kind (context.kind / filter) | Read vs write breakdown | Bounded (4-10 enum values) | All | - |
| Thread status (kind=running/connected) | Utilization ratio | Bounded (4 values) | All | - |
| Row operation type | INSERT/UPDATE/DELETE/READ mix | Bounded (4 values) | All | - |
| Statement digest (context.digest_text) | Top slow query patterns | VERY HIGH — per unique SQL | 20 | Avoid in timeseries |
| Error type (connection_error) | Connection failure breakdown | Bounded (5-8 enum values) | All | - |
| Table size type (table_size_type) | Data vs index size split | Bounded (2 values) | All | - |
| Environment (context.env) | Env comparison (prod vs staging) | Bounded | 5 | - |

### Tsuga field mapping

| Vendor/exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| service.name (OTel resource) | context.scope | Must-exist (instance identifier) |
| mysql.instance.endpoint (receiver label) | context.mysql.instance.endpoint | Optional (useful for host:port disambiguation) |
| k8s.cluster.name | context.k8s.cluster.name | Optional (k8s deployments) |
| k8s.namespace.name | context.k8s.namespace.name | Optional (k8s deployments) |
| schema (metric attribute) | context.schema | Optional (table/index metrics only) |
| table_name (metric attribute) | context.table | Optional (table/index metrics only) |
| index_name (metric attribute) | context.index | Optional (index metrics only) |
| digest / digest_text (metric attribute) | context.digest / context.digest_text | Optional (statement_event metrics only) |
| read_lock_type / write_lock_type | context.lock_type | Optional (table lock metrics only) |
| env (resource/span) | context.env | Must-exist |
| team | context.team | Must-exist |

**Confirmed by sources:** live Tsuga discovery shows MySQL metrics keyed by `context.scope` and `context.mysql.instance.endpoint` for instance identity.

**Best-practice inference:** schema/table_name/index_name attribute mapping to context.* is inferred from OTel semantic conventions and needs Stage 2 verification.

---

## Golden signals

### Traffic (Query Throughput)
- **What it means for MySQL:** `mysql.query.count` rate — total queries per second hitting the database. `mysql.handlers` (especially `handler=write` and `handler=read_rnd_next`) provide lower-level workload signal.
- **Typical causes when it degrades:** App-level connection pooling failure, shard routing breakdown, batch job runaway.
- **Best telemetry sources:** `mysql.query.count` (optional metric), `mysql.handlers` (default), `mysql.row_operations` (default).
- **What people page on:** Sudden 10x spike in QPS with no traffic increase upstream; QPS drops to zero (MySQL unreachable).
- **Section questions:** Is MySQL receiving the expected number of queries? Is the read/write mix healthy?

### Errors (Query Failures & Connection Failures)
- **What it means for MySQL:** `mysql.connection.errors` (auth failures, max-connection rejections), `mysql.query.slow.count` (slow = degraded not failed, but precursor), `mysql.locks` waited (lock contention = implicit error path).
- **Typical causes when it degrades:** max_connections exhaustion, authentication misconfiguration, long-running transactions blocking others.
- **Best telemetry sources:** `mysql.connection.errors` (optional), `mysql.query.slow.count` (optional), `mysql.row_locks` kind=waits (default).
- **What people page on:** Applications report connection refused; slow query count spikes; deadlock rate increases.
- **Section questions:** Are connection attempts failing? Are slow queries increasing?

### Latency (Query Performance)
- **What it means for MySQL:** Table and index I/O wait time (`mysql.table.io.wait.time`, `mysql.index.io.wait.time`) are the primary indicators. `mysql.statement_event.wait.time` (optional, Performance Schema) provides per-digest latency.
- **Typical causes when it degrades:** Buffer pool too small (disk I/O), missing indexes (full table scans), lock contention, tmp disk table spills, sort buffer overflows.
- **Best telemetry sources:** `mysql.table.io.wait.time` + `mysql.table.io.wait.count` (derive avg wait), `mysql.statement_event.wait.time` (optional).
- **What people page on:** p95 app-level DB query latency SLO breach; slow query count trending up.
- **Section questions:** Is table I/O wait time increasing? Which tables/indexes are hottest?

### Saturation (Buffer Pool, Connections, Locks)
- **What it means for MySQL:** Buffer pool utilization (`mysql.buffer_pool.usage` / `mysql.buffer_pool.limit`), thread utilization (`threads_running` / `threads_connected`), lock wait rates (`mysql.row_locks` kind=waits). For MySQL, **buffer pool saturation is more critical than CPU** — when the working set exceeds available RAM, disk I/O becomes the bottleneck and latency spikes dramatically.
- **Typical causes when it degrades:** Working set growth outpacing buffer pool, connection leaks, long-running transactions holding locks.
- **Best telemetry sources:** `mysql.buffer_pool.usage` + `mysql.buffer_pool.limit` (default), `mysql.threads` (default), `mysql.row_locks` (default).
- **What people page on:** Buffer pool > 95% utilized and I/O reads increasing; thread count approaching max_connections; row lock waits spiking.
- **Section questions:** Is the buffer pool large enough? Are connections nearing the limit?

**Confirmed by sources:** Golden signal mapping derived from https://dev.mysql.com/doc/refman/8.0/en/server-status-variables.html and OTel receiver docs.
**Best-practice inference:** Threshold values (99% buffer pool hit rate, 80% thread utilization) are industry conventions, not MySQL documentation.

---

## Telemetry sources

| Source | How collected | What it provides | Pros | Cons | Common pitfalls |
|---|---|---|---|---|---|
| OTel MySQL receiver | Connects to MySQL and queries `SHOW GLOBAL STATUS` and Performance Schema tables | 25 default metrics + 23 optional metrics; covers buffer pool, handlers, locks, I/O waits, threads, replication | Official OpenTelemetry support; actively maintained; structured OTel format | All metrics are cumulative Sum (not delta) — post-functions must be `rate` or `increase`, not `per-second` | Wrong temporality = nonsense charts. Optional metrics require explicit `initial_delay` and configuration. Performance Schema metrics need PS enabled. |
| Prometheus mysqld_exporter | Prometheus scrape of `mysqld_exporter` binary | Broader metric coverage than OTel receiver; native Prometheus histograms for latency; includes InnoDB mutex/semaphore metrics | More metrics than OTel receiver; used in many existing stacks | Separate binary to deploy; Prometheus namespace (`mysql_*` not `mysql.*`) | Metric names differ from OTel receiver — do not mix namespaces in the same dashboard. Cardinality explosion from per-table metrics (`collect.info_schema.tables` flag). |
| MySQL Performance Schema | SQL queries on `performance_schema.*` tables | Per-digest statement latency, per-thread wait events, table/index I/O histograms | Most granular query-level data | Enabled by default in MySQL 8.0 but consumers may be disabled; overhead depends on instrumentation level | Many consumers are disabled by default. Statement digest table truncates if `performance_schema_digests_size` is too small. |
| MySQL slow query log | File or table output when `slow_query_log=ON` | Human-readable slow query records with SQL text, execution time, rows examined | Easy to enable; no schema changes | Not structured; hard to aggregate; leaks SQL text (potential PII) | Disabled by default. `long_query_time` default = 10s is too high for most apps; set to 1s or less. Extended fields require `log_slow_extra=ON` (MySQL 8.0.14+). |
| MySQL error log | File or JSON sink | Server errors, warnings, InnoDB recovery events, replication errors | Always on | Mostly startup/crash events; low volume during normal operation | Mix of formats (traditional vs JSON) depending on `log_error_services`. JSON format requires `log_sink_json` plugin. |
| Binary log (binlog) | `mysqlbinlog` or replication monitoring | DDL/DML event stream; replication lag; GTID position | Complete change history | Not a metrics source; requires log parsing or dedicated tooling | Not directly available as OTel metrics; use `mysql.replica.*` metrics for lag, not binlog parsing. |

**Confirmed by sources:** OTel receiver details from https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/mysqlreceiver/documentation.md.
**Best-practice inference:** mysqld_exporter comparison and Performance Schema caveats are inference from broad community knowledge.

---

## Log intelligence (Stage 4 handoff)

### Confirmed by sources

**Log sources matrix:**

| Source | Access path | Typical format | Structured | Evidence |
|---|---|---|---|---|
| Error log | `/var/log/mysql/error.log` or `log_error` sysvar | Traditional: `time thread [label] [err_code] [subsystem] msg` or JSON | Traditional: semi-structured; JSON: fully structured | https://dev.mysql.com/doc/refman/8.0/en/error-log-format.html |
| Slow query log | `/var/log/mysql/slow.log` or `slow_query_log_file` sysvar | Multi-line: timestamp header + stats line + SQL line | Unstructured (multi-line) | https://dev.mysql.com/doc/refman/8.0/en/slow-query-log.html |
| General query log | `/var/log/mysql/general.log` or `general_log_file` sysvar | `timestamp thread_id command_type argument` | Unstructured | https://dev.mysql.com/doc/refman/8.0/en/query-log.html |
| Binary log | Binary file; read via `mysqlbinlog` | Binary (not a text log) | N/A | N/A |

**Known log formats:**

*Error log (traditional — most common):*
```
2020-08-06T14:25:02.835618Z 0 [Note] [MY-012487] [InnoDB] DDL log recovery : begin
2020-08-06T14:25:02.936146Z 0 [Warning] [MY-010068] [Server] CA certificate /var/mysql/sslinfo/cacert.pem is self signed.
2020-08-06T14:25:03.109022Z 5 [Note] [MY-010051] [Server] Event Scheduler: scheduler thread started with id 5
```
- Timestamp: ISO 8601 (`YYYY-MM-DDThh:mm:ss.uuuuuuZ`)
- Thread ID: integer (0 = server process, >0 = connection thread)
- Label: `Note` | `Warning` | `Error` | `System`
- Error code: `MY-NNNNNN` (6-digit)
- Subsystem: `InnoDB` | `Server` | `Repl` | etc.
- Message: free text

*Error log (JSON — MySQL 8.0+, `log_sink_json` plugin):*
```json
{"prio":3,"err_code":10051,"msg":"Event Scheduler: scheduler thread started","time":"2020-08-06T14:25:03.109022Z","ts":1596724012005,"thread":5,"label":"Note","subsystem":"Server"}
```

*Slow query log (multi-line, FILE output):*
```
# Time: 2023-05-15T10:23:45.123456Z
# User@Host: app_user[app_user] @ app-server [10.0.1.42]  Id:  1234
# Query_time: 3.456789  Lock_time: 0.000123  Rows_sent: 150  Rows_examined: 125000
SET timestamp=1684146225;
SELECT * FROM orders WHERE status = 'pending' AND created_at < NOW() - INTERVAL 7 DAY;
```
With `log_slow_extra=ON` (MySQL 8.0.14+), adds: `Thread_id`, `Errno`, `Bytes_received`, `Bytes_sent`, `Read_*` counters, `Sort_*` counters, `Created_tmp_*`, `Start`, `End`.

**Candidate query filters for Stage 4:**

| Filter | Rationale | Risk |
|---|---|---|
| Precise: `service.name:<mysql-instance-name>` | Targets specific MySQL instance logs | Requires knowing the exact service name label |
| Fallback: `source.type:mysql OR service.name:*mysql*` | Broad MySQL capture | May catch unrelated processes with mysql in name |
| Error log only: `mysql.log_type:error` | Focuses on actionable error/warning events | Depends on log_type attribute being populated by parser |

**Attribute mapping hints:**

| Raw field | Suggested Tsuga key | Confidence | Notes |
|---|---|---|---|
| timestamp (ISO 8601) | `@timestamp` | High | Standard OTel log timestamp |
| thread (integer) | `mysql.thread_id` | High | Confirmed from error log format |
| label (Note/Warning/Error) | `severity` (mapped to log level) | High | Needs map-level processor |
| err_code (MY-NNNNNN) | `mysql.error_code` | High | Confirmed format |
| subsystem (InnoDB/Server) | `mysql.subsystem` | High | Confirmed from format |
| msg | `body` | High | Standard OTel log body |
| Query_time | `mysql.query_time_s` | High | Slow query log specific |
| Lock_time | `mysql.lock_time_s` | High | Slow query log specific |
| Rows_sent | `mysql.rows_sent` | High | Slow query log specific |
| Rows_examined | `mysql.rows_examined` | High | Slow query log specific |
| User@Host | `mysql.user`, `mysql.client_host` | Medium | Requires regex split |
| Id (connection ID) | `mysql.connection_id` | High | Slow query log specific |

**Parsing risks:**
1. **Multi-line slow query log** — Grok must match across multiple lines. Each query spans 4-5 lines. Boundary detection is the hardest part.
2. **Mixed log formats in the same file** — Error log may contain both traditional and pre-GA format lines if MySQL was upgraded.
3. **SQL text contains sensitive data** — Slow query log includes raw SQL with potential PII/credentials. Consider a `replace` or `redact` processor.
4. **Timestamp timezone** — `log_timestamps=SYSTEM` produces local-time timestamps; `UTC` produces `Z` suffix. Parser must handle both.
5. **Optional extended fields** — Slow query log with `log_slow_extra=ON` has more fields; parser must be resilient to their absence.
6. **General query log volume** — Can be extremely high volume. Not recommended for production log routing unless filtered aggressively.
7. **JSON error log** — If `log_sink_json` is used, format is fully different. Stage 4 should check which sink is active before designing parser.

### Best-practice inference
- Most teams route the **error log** (highest signal, lowest volume) and optionally the **slow query log** (highest diagnostic value).
- The general query log is rarely routed in production due to volume and SQL exposure.
- Binary log is not a text log and cannot be routed via standard log processors.

---

## Caveats and footguns

- **[buffer-pool-memory]** All OTel MySQL receiver metrics are **cumulative Sum** type — not delta, not gauge. Use `rate` post-function for event counters, not `per-second`. Using `per-second` on cumulative counters produces nonsense values. (Confirmed — OTel receiver metadata.yaml)
- **[buffer-pool-memory]** `mysql.buffer_pool.limit` and `mysql.buffer_pool.usage` are non-monotonic Sums that behave like gauges. Do NOT apply `rate` to these — use `max` aggregation with no post-function. (Confirmed)
- **[buffer-pool-memory]** `mysql.buffer_pool.operations` does NOT directly expose `Innodb_buffer_pool_reads` (physical disk reads). The buffer pool hit ratio requires approximation via `read_requests` vs `read_ahead` + `pages_created`, which is not exactly equivalent. This is a known gap in OTel MySQL receiver coverage. Mark the buffer pool hit ratio widget as approximate. (Inference — based on metadata.yaml attribute enum values)
- **[availability-health]** `mysql.threads` attribute `kind=connected` maps to `Threads_connected` (active connections), NOT max_connections. You cannot derive connection saturation % from OTel metrics alone — max_connections is a config value, not a metric. Use threads_running/threads_connected as a proxy for saturation. (Confirmed)
- **[availability-health]** `mysql.connection.count` is an optional metric (disabled by default). Do not gate the entire availability section on it. Use `mysql.threads` (default) as the primary availability signal. (Confirmed)
- **[throughput-query-rate]** `mysql.query.count` and `mysql.query.slow.count` are **optional metrics** that must be explicitly enabled in the OTel collector config. Without them, the slow query ratio derived signal cannot be computed. (Confirmed)
- **[throughput-query-rate]** `mysql.handlers` has many handler attribute values (20+). Plotting all of them in a single timeseries creates unreadable charts. Filter to 3-5 most informative: `write`, `read_rnd_next` (full table scan indicator), `read_key` (index lookup), `update`, `delete`. (Inference)
- **[throughput-query-rate]** `handler=read_rnd_next` rate is a strong indicator of **full table scans**. A high rate relative to `read_key` means missing indexes. This is a key operational signal, not just a curiosity. (Confirmed — MySQL docs)
- **[performance-io-latency]** `mysql.table.io.wait.time` and `mysql.index.io.wait.time` require **Performance Schema** to be enabled (it is by default in MySQL 8.0, but individual consumers can be disabled). If metrics are absent, Performance Schema instrumentation is likely off. (Confirmed)
- **[performance-io-latency]** `mysql.statement_event.count` and `.wait.time` are optional metrics requiring `performance_schema` consumer `events_statements_summary_by_digest` to be enabled. Absence means Performance Schema statement digests are off, not that queries are fast. (Confirmed)
- **[performance-io-latency]** Average wait time derived signals (table.io.wait.time / table.io.wait.count) use cumulative counters with `rate`. If the rate of operations is very low, the average can appear artificially high due to sampling windows. Use with a minimum count threshold in interpretation. (Inference)
- **[throughput-query-rate]** `mysql.tmp_resources` counts temporary tables and files created **since MySQL startup**. High ratio of `disk_tables/tables` is meaningful only when both counters are increasing. If MySQL is idle, the ratio reflects historical data. Always look at rates, not absolute values. (Inference)
- **[replication]** `mysql.replica.time_behind_source` and `mysql.replica.sql_delay` are **optional metrics** (disabled by default). They also only produce data on replica nodes — the source does not emit them. Dashboard sections should be gated accordingly. (Confirmed)
- **[replication]** `mysql.replica.time_behind_source` can read 0 even when the replica is genuinely behind if the source is idle (no new binlog events). This is a known MySQL quirk — zero lag on an idle source does not guarantee data is current. (Confirmed — MySQL docs)
- **[locks-contention]** `mysql.locks` kind=waited refers to **table-level locks** (MyISAM or DDL). For InnoDB row-level lock waits, use `mysql.row_locks` kind=waits instead. These are different signals. (Confirmed — MySQL status variable docs)
- **[locks-contention]** `mysql.row_locks` kind=time tracks **total accumulated lock wait time in ms** since startup — it is a cumulative counter, not a gauge. Use `rate` to get lock time trend. Do NOT interpret the raw value as "current lock wait time." (Confirmed)
- **[storage-operations]** `mysql.operations` kind=reads/writes/fsyncs tracks **InnoDB data file I/O operations** — these are OS-level file operations, not SQL operations. A high fsync rate indicates sync-heavy configuration (`innodb_flush_log_at_trx_commit=1`). (Confirmed)
- **[storage-operations]** `mysql.double_writes` reflects InnoDB's doublewrite buffer mechanism (crash-safety). High `pages_written/writes` ratio (ideally close to 1) means large write batches. Very high absolute rate indicates heavy write workload. (Confirmed)
- **[availability-health]** `mysql.uptime` is a **monotonically increasing cumulative Sum** measuring seconds since MySQL started. Do not apply `rate` — it would always return approximately 1.0. Show `max` of the raw value for the selected time range and use a duration normalizer to display as HH:MM:SS or days. (Inference — behavior of cumulative sum for level-like metrics)
- **[throughput-query-rate, performance-io-latency]** `mysql.sorts` kind=merge_passes is a **leading indicator** of sort buffer exhaustion — each merge pass = extra disk I/O. Even a small rate (>0) is noteworthy. (Confirmed — MySQL docs)
- **[storage-operations]** `mysql.opened_resources` kind=table counts total tables opened since startup. A high **rate** (not absolute) indicates the table_open_cache is undersized. (Confirmed)
- **[buffer-pool-memory]** InnoDB supports multiple buffer pool instances (`innodb_buffer_pool_instances`). The OTel receiver aggregates across all instances. Per-instance breakdown is not available via OTel metrics. (Inference)

---

## Confirmed Tsuga prefixes

- `mysql.*` — **CONFIRMED** (25/25 live metrics found in Tsuga over the last 24h; Stage 1 optional metrics remain disabled/not emitted)

---

## Discovery status

Discovery: completed on 2026-03-06.

- Prefix validated: `mysql.*` (25 metrics discovered)
- Reconciliation result: 25 confirmed, 23 missing (all optional/collector-config dependent), 0 unexpected
- Context key corrections from live Tsuga: `context.scope` (not `context.scope.name`), `context.kind/status/operation/resource/table/index`
- Temporality corrections: most active counters are `delta` and should use `per-second`; a small subset are `cumulative` and stay on `rate` or `none` depending on chart intent

---

## Top sources

1. https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/mysqlreceiver/documentation.md — OTel MySQL receiver metric list (names, units, types, default vs optional)
2. https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector-contrib/main/receiver/mysqlreceiver/metadata.yaml — Authoritative metric schema: all 48 metrics with attribute enums and enabled status
3. https://dev.mysql.com/doc/refman/8.0/en/server-status-variables.html — MySQL 8.0 SHOW GLOBAL STATUS variable reference (maps to OTel metric attributes)
4. https://dev.mysql.com/doc/refman/8.0/en/innodb-buffer-pool.html — InnoDB buffer pool internals (basis for buffer pool KPIs)
5. https://dev.mysql.com/doc/refman/8.0/en/slow-query-log.html — Slow query log format specification (Stage 4 log parsing)
6. https://dev.mysql.com/doc/refman/8.0/en/error-log-format.html — Error log format specification including JSON format (Stage 4 log parsing)
7. https://dev.mysql.com/doc/refman/8.0/en/replication-administration-status.html — Replication status variables (Seconds_Behind_Source, IO/SQL thread status)
8. https://dev.mysql.com/doc/refman/8.0/en/performance-schema-statement-tables.html — Performance Schema statement event tables (statement digest metrics)
9. https://dev.mysql.com/doc/refman/8.0/en/query-log.html — General query log format (Stage 4 context)
10. https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/mysqlreceiver — MySQL receiver source directory (config schema, scraper implementation context)
