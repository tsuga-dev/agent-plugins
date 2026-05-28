# Google Cloud Storage Integration Context Bundle

**Technology:** Google Cloud Storage (GCS)
**Deployment:** Managed (GCP)
**Environment:** prod
**Persona:** SRE Dev and ops
**Telemetry preference:** mixed
**Integration scope:** core service only
**Primary use-case:** reliability and performance

---

## How to use this bundle

- **Dashboard plan:** Start with `07_google-cloud-storage_dashboard_plan.yaml` for section structure, widget specs, and coverage map.
- **Metric truth:** Use `05_google-cloud-storage_metric_inventory.csv` for exact metric names, units, aggregations, and post-functions.
- **Notes and playbooks:** Use `09_google-cloud-storage_section_notes_and_playbooks.md` for all note widget prose and operational runbooks.

---

## Confirmed Tsuga prefixes

- `storage.googleapis.com/*` — **CONFIRMED** (11/21 metrics present in Tsuga; 10 missing due to feature gating: replication, authn, authz, autoclass, v2/deleted_bytes)
- Naming convention: **original GCP slash notation** (e.g., `storage.googleapis.com/api/request_count`)

Discovery: performed 2026-02-10. 11 metrics confirmed, 4 unexpected (anywhere_cache/*, v2/total_byte_seconds, v2/total_count), 10 missing (feature-gated).

---

## Bundle files

| # | Filename | Purpose |
|---|---|---|
| 00 | `00_google-cloud-storage_cover.md` | This file — metadata, navigation, and Stage 2 handoff contract |
| 01 | `01_google-cloud-storage_executive_overview.md` | What GCS is, what "good" looks like, top incident shapes |
| 02 | `02_google-cloud-storage_key_concepts.md` | Glossary (22 terms), concept map (29 lines), entities/dimensions (13), Tsuga field mapping |
| 03 | `03_google-cloud-storage_golden_signals.md` | Traffic/Errors/Latency/Saturation mapped to GCS metrics and section questions |
| 04 | `04_google-cloud-storage_telemetry_sources.md` | Source matrix, feature gating table, sampling intervals |
| 05 | `05_google-cloud-storage_metric_inventory.csv` | 21 metrics (11 confirmed, 10 missing): names, types, units, Tsuga mapping, aggregations, group-bys |
| 06 | `06_google-cloud-storage_derived_signals.csv` | 14 derived signals with formulas, inputs, and interpretation |
| 07 | `07_google-cloud-storage_dashboard_plan.yaml` | 7 sections, 2 dashboards (overview + deep dive), 39 widgets, coverage map |
| 09 | `09_google-cloud-storage_section_notes_and_playbooks.md` | Mission note, 7 section notes, 22 triage chains, 7 playbooks |
| 10 | `10_google-cloud-storage_caveats_footguns.md` | 22 caveats tagged by section across 6 categories |
| 11 | `11_google-cloud-storage_unknowns_verify_next.yaml` | 3 remaining unknowns |
| 12 | `12_google-cloud-storage_discovery_reconciliation.md` | Discovery & reconciliation report |

---

## Top sources

1. [Google Cloud metrics reference (P-Z)](https://docs.cloud.google.com/monitoring/api/metrics_gcp_p_z) — Canonical metric definitions for all `storage.googleapis.com/*` metrics including types, units, and labels.
2. [Cloud Storage monitoring overview](https://docs.cloud.google.com/storage/docs/monitoring) — Official monitoring guidance including metric update frequencies and dashboard recommendations.
3. [Data storage SLI metrics](https://docs.cloud.google.com/stackdriver/docs/solutions/slo-monitoring/sli-metrics/data-storage-metrics) — Confirms absence of server-side latency metric; defines SLI-eligible metrics.
4. [Request rate and access distribution guidelines](https://docs.cloud.google.com/storage/docs/request-rate) — Per-bucket rate limits, auto-scaling behavior, sequential naming anti-pattern.
5. [Bandwidth usage overview](https://docs.cloud.google.com/storage/docs/bandwidth-usage) — Bandwidth quotas (200 Gbps default), quota metrics, CDN exemptions.
6. [Cloud Storage consistency](https://docs.cloud.google.com/storage/docs/consistency) — Strong consistency model, IAM eventual consistency (~1 min), HMAC key propagation.
7. [Managing turbo replication](https://docs.cloud.google.com/storage/docs/managing-turbo-replication) — RPO monitoring, turbo_max_delay metric, multi-hour reporting delay.
8. [Using uniform bucket-level access](https://docs.cloud.google.com/storage/docs/using-uniform-bucket-level-access) — ACL metrics, migration guidance, access_id cardinality warning.
9. [Cloud Storage troubleshooting](https://docs.cloud.google.com/storage/docs/troubleshooting) — Retry amplification, soft-delete retention, common error patterns.
10. [Cloud Storage quotas and limits](https://docs.cloud.google.com/storage/quotas) — Rate limits, object size limits, bucket creation limits.


---

# Google Cloud Storage — Executive Overview

## What it is
Google Cloud Storage (GCS) is GCP's fully managed object storage service. It stores blobs (files, media, backups, logs, data lake objects) in **buckets** across single-region, dual-region, and multi-region locations. Applications interact via JSON/gRPC APIs; GCS auto-scales reads and writes without provisioning.

## What "good" looks like
- `api/request_count` returns mostly `OK` responses; 5xx and `RESOURCE_EXHAUSTED` codes are near zero.
- `network/sent_bytes_count` and `network/received_bytes_count` track steady, predictable bandwidth aligned with application traffic patterns.
- `storage/total_bytes` grows linearly in line with data retention policy; no unexpected jumps (orphaned multipart uploads, versioning accumulation, soft-delete retention).
- Replication-enabled buckets show `replication/meeting_rpo = 1` consistently.

## Paging intent (symptom-level)
- Sustained 5xx error rate or `RESOURCE_EXHAUSTED` throttling on production buckets.
- Replication RPO violations on dual/multi-region buckets with turbo replication SLAs.
- Bandwidth quota usage approaching limits (>80% of project quota).

## Top 3 incident shapes and first dashboard section
| Incident shape | First section to check |
|---|---|
| Elevated API error rate (5xx spike or permission denied wave) | **Errors & Reliability** — break down by `response_code` and `method` |
| Unexpected storage growth (cost spike, quota risk) | **Storage Capacity & Growth** — check `total_bytes` by `storage_class` and object count trends |
| Bandwidth throttling / quota exhaustion | **Network & Bandwidth** — compare egress rate to quota limits |

---

### Confirmed by sources
- GCS returns gRPC status codes (`OK`, `PERMISSION_DENIED`, `RESOURCE_EXHAUSTED`, etc.) as the `response_code` label on `api/request_count` ([Google Cloud metrics reference](https://docs.cloud.google.com/monitoring/api/metrics_gcp_p_z)).
- GCS has no server-side latency metric; latency must be measured client-side ([Data storage SLI metrics](https://docs.cloud.google.com/stackdriver/docs/solutions/slo-monitoring/sli-metrics/data-storage-metrics)).
- Storage metrics (`total_bytes`, `object_count`) update once per 24 hours ([Cloud Storage monitoring](https://docs.cloud.google.com/storage/docs/monitoring)).

### Best-practice inference
- Bandwidth quota saturation at 80% as a leading indicator is an operational best practice, not a documented GCS threshold.
- Linear storage growth as "normal" assumes well-configured lifecycle rules; without them, growth can be super-linear due to versioning or soft-delete.


---

# Google Cloud Storage — Key Concepts

## Glossary (>= 20 terms)

| Term | Definition | Operational meaning | Dashboard section affected |
|---|---|---|---|
| **Bucket** | Top-level container for objects. Globally unique name, tied to a project and location. | Primary grouping dimension (`bucket_name`). All metrics are scoped per bucket. | All sections |
| **Object** | An immutable blob stored in a bucket, identified by name (key). | The unit of storage. Object count and size drive capacity metrics. | Storage Capacity & Growth |
| **Storage class** | Pricing/access tier: Standard, Nearline, Coldline, Archive. | Determines at-rest cost and retrieval fees. Group `total_bytes` by `storage_class` to see distribution. | Storage Capacity & Growth, Cost |
| **Location type** | Single-region, dual-region, or multi-region. Determines redundancy and latency. | Dual/multi-region buckets have replication metrics; single-region do not. | Replication & Durability |
| **Turbo replication** | Dual-region feature guaranteeing 15-minute RPO for cross-region sync. | Monitored via `turbo_max_delay` and `meeting_rpo`. Only exists on dual-region buckets with turbo enabled. | Replication & Durability |
| **RPO (Recovery Point Objective)** | Maximum acceptable data loss window during failover. | `meeting_rpo = 0` means the bucket has violated its replication target. | Replication & Durability |
| **API method** | The operation type: `ReadObject`, `WriteObject`, `ListObjects`, `DeleteObject`, `InsertObject`, `ComposeObject`, `CopyObject`, etc. | Label on `api/request_count`. Group by `method` to understand traffic profile. | Traffic & Request Volume |
| **Response code** | gRPC-style status code: `OK`, `NOT_FOUND`, `PERMISSION_DENIED`, `RESOURCE_EXHAUSTED`, `INTERNAL`, `UNAVAILABLE`, etc. | Label on `api/request_count`. Filter for non-OK to find errors. | Errors & Reliability |
| **Lifecycle rule** | Automated policy to delete objects or transition storage classes based on age, creation date, or custom time. | Missing or misconfigured rules cause unexpected storage growth. | Storage Capacity & Growth |
| **Object versioning** | Bucket setting that retains noncurrent versions of objects on overwrite/delete. | Noncurrent versions accumulate storage cost. Check `object_count` growth trends. | Storage Capacity & Growth |
| **Soft delete** | Default 90-day retention of deleted objects (recoverable). | Soft-deleted objects still appear in `storage/v2/total_bytes` with `type=soft-deleted`. | Storage Capacity & Growth |
| **Uniform bucket-level access** | Disables per-object ACLs; all access controlled via IAM only. | ACL metrics (`authz/*`) should be zero after migration. Non-zero = legacy access paths remain. | Access & Security |
| **IAM** | Identity and Access Management. Roles control who can read/write/admin buckets and objects. | `PERMISSION_DENIED` responses indicate IAM misconfigurations. | Errors & Reliability, Access & Security |
| **ACL** | Access Control List (legacy). Per-object or per-bucket access grants. | `authz/acl_operations_count` tracks ACL mutations; goal is to migrate to uniform access. | Access & Security |
| **Autoclass** | Automatic storage class transitions based on access patterns. | Tracked via `autoclass/transition_operation_count` and `transitioned_bytes_count`. Only present on autoclass-enabled buckets. | Cost & Storage Class |
| **Bandwidth quota** | Per-project, per-region limit on egress throughput (default 200 Gbps). | `quota/*/usage` vs `quota/*/limit` shows saturation. `RESOURCE_EXHAUSTED` = quota hit. | Network & Bandwidth |
| **Anywhere Cache** | Zone-level cache for hot object reads. Reduces latency and egress. | Tracked via `anywhere_cache/request_count` with `cache_hit` label. Only exists if enabled. | Network & Bandwidth |
| **Multipart upload** | Splitting large objects into parts for parallel upload. | Abandoned multipart uploads consume storage until cleaned up by lifecycle rules. | Storage Capacity & Growth |
| **Compose** | Server-side concatenation of up to 32 objects into one. | Counted as a Class A operation in `api/request_count` with method `ComposeObject`. | Traffic & Request Volume |
| **HMAC key** | Hash-based authentication key for S3-compatible access to GCS. | HMAC key state changes take up to 3 minutes to propagate (eventual consistency). | Access & Security |
| **Request rate scaling** | GCS auto-scales per-bucket from ~5K reads/s and ~1K writes/s baseline. | Scaling takes minutes. Ramp up gradually (double every 20 min). Fast ramp = `RESOURCE_EXHAUSTED`. | Traffic & Request Volume, Errors & Reliability |
| **Early deletion fee** | Charge for deleting objects before their storage class minimum duration (30/90/365 days). | Not directly metricked; inferred from `autoclass/transition_operation_count` and object age. | Cost & Storage Class |

---

## Concept Map (>= 25 lines)

```
Bucket -> contains -> Objects (all storage metrics scoped to bucket)
Bucket -> has -> Location type (determines replication metrics availability)
Bucket -> has -> Default storage class (affects new object placement)
Bucket -> may enable -> Object versioning (causes noncurrent version accumulation)
Bucket -> may enable -> Lifecycle rules (automates deletion and class transitions)
Bucket -> may enable -> Turbo replication (dual-region only; adds RPO monitoring)
Bucket -> may enable -> Autoclass (automatic storage class transitions)
Bucket -> may enable -> Anywhere Cache (zone-level cache for hot reads)
Bucket -> may enable -> Soft delete (default 90-day retention of deleted objects)
Bucket -> enforces -> Access control (IAM or legacy ACLs)
Object -> belongs to -> Storage class (Standard, Nearline, Coldline, Archive)
Object -> has -> Size in bytes (contributes to storage/total_bytes)
Object -> may have -> Noncurrent versions (if versioning enabled)
API request -> targets -> Bucket + Object (method + response_code labels)
API request -> counted by -> api/request_count metric
API request -> may fail with -> Response code (OK, NOT_FOUND, PERMISSION_DENIED, etc.)
API request -> transfers -> Network bytes (sent_bytes_count / received_bytes_count)
Network egress -> limited by -> Bandwidth quota (per-project, per-region)
Bandwidth quota -> triggers -> RESOURCE_EXHAUSTED when exceeded
Storage class -> determines -> At-rest cost + retrieval fees
Lifecycle rule -> transitions -> Objects between storage classes
Lifecycle rule -> deletes -> Objects after retention period
Autoclass -> transitions -> Objects based on access patterns (measured by transitions metric)
Replication -> syncs -> Objects across regions (dual/multi-region buckets)
Replication -> monitored by -> meeting_rpo + turbo_max_delay metrics
Anywhere Cache -> caches -> Hot reads in specific zones (cache_hit label)
Authentication -> tracked by -> authn/authentication_count metric
ACL operations -> tracked by -> authz/acl_operations_count metric
Quota usage -> approaching limit -> Leading indicator of throttling
```

---

## Entities and Dimensions (>= 12)

| Dimension | Source label | Tsuga field (recommended) | Why useful | Cardinality risk | Safe Top-N | Do NOT group-by |
|---|---|---|---|---|---|---|
| Project ID | `project_id` (resource label) | `context.cloud.account.id` | Scope to a single GCP project | Low (bounded by org) | 10 | — |
| Bucket name | `bucket_name` (resource label) | `context.gcp.bucket_name` | Primary entity for all GCS metrics | Medium — can be high in multi-project orgs | 25 | — |
| Location | `location` (resource label) | `context.cloud.region` | Region/multi-region grouping for latency and cost analysis | Low (bounded by GCP locations) | 10 | — |
| API method | `method` (metric label) | `context.method` | Distinguish read/write/list/delete patterns | Low (~20 distinct methods) | 15 | — |
| Response code | `response_code` (metric label) | `context.response_code` | Error breakdown; filter for non-OK | Low (~15 status codes) | 10 | — |
| Storage class | `storage_class` (metric label) | `context.storage_class` | Cost and capacity breakdown by tier | Very low (4 classes) | 5 | — |
| Authentication method | `authentication_method` (metric label) | `context.authn_method` | Security audit of auth patterns | Low | 5 | — |
| Access ID | `access_id` (metric label on authn) | `context.access_id` | Identify specific service accounts | **HIGH** — unbounded | — | Do NOT group-by without filter; use top-list only |
| ACL operation | `acl_operation` (metric label) | `context.acl_operation` | Track ACL usage for uniform-access migration | Very low | 5 | — |
| Cache hit | `cache_hit` (metric label, anywhere_cache) | `context.cache_hit` | Cache effectiveness breakdown | Very low (true/false) | 2 | — |
| Zone (anywhere cache) | `zone` (metric label, anywhere_cache) | `context.zone` | Per-zone cache performance | Low | 10 | — |
| RPO status | `rpo_status` (metric label, replication) | `context.rpo_status` | Distinguish met vs missed replications | Very low | 2 | — |
| Type (v2 storage) | `type` (metric label, storage/v2) | `context.storage_type` | Distinguish live vs soft-deleted objects | Very low | 3 | — |

---

## Tsuga Field Mapping Table (REQUIRED)

| Vendor/exporter dimension | Recommended `context.*` key | Must-exist | Notes |
|---|---|---|---|
| `project_id` | `context.cloud.account.id` | Yes | Standard GCP project mapping |
| `bucket_name` | `context.gcp.bucket_name` | Yes | Primary entity for GCS |
| `location` | `context.cloud.region` | Yes | Region or multi-region identifier |
| `method` | `context.method` | Yes | API method (ReadObject, WriteObject, etc.) |
| `response_code` | `context.response_code` | Yes | gRPC status code |
| `storage_class` | `context.storage_class` | Optional | Present only on storage metrics |
| `authentication_method` | `context.authn_method` | Optional | Present only on authn metrics |
| `access_id` | `context.access_id` | Optional | Present only on authn metrics; high cardinality |
| `acl_operation` | `context.acl_operation` | Optional | Present only on authz metrics |
| `cache_hit` | `context.cache_hit` | Optional | Present only on anywhere_cache metrics |
| `zone` | `context.zone` | Optional | Present only on anywhere_cache metrics |
| `rpo_status` | `context.rpo_status` | Optional | Present only on replication metrics |
| `type` | `context.storage_type` | Optional | Present only on storage/v2 metrics (live, soft-deleted, etc.) |
| `context.env` | `context.env` | **Unknown** | Standard Tsuga convention — must verify in Stage 2 |
| `context.team` | `context.team` | **Unknown** | Standard Tsuga convention — must verify in Stage 2 |

---

### Confirmed by sources
- Resource labels (`project_id`, `bucket_name`, `location`) confirmed in [Google Cloud metrics reference](https://docs.cloud.google.com/monitoring/api/metrics_gcp_p_z).
- Metric labels (`method`, `response_code`, `storage_class`) confirmed in [Cloud Storage monitoring](https://docs.cloud.google.com/storage/docs/monitoring).
- ~20 distinct API methods listed in [Cloud Storage JSON API reference](https://cloud.google.com/storage/docs/json_api/v1).
- `access_id` label high cardinality risk noted in [Authentication metrics docs](https://docs.cloud.google.com/storage/docs/using-uniform-bucket-level-access).

### Best-practice inference
- Tsuga `context.*` field names are inferred from common conventions (`context.cloud.account.id`, `context.cloud.region`). Exact field names must be verified in Stage 2 discovery.
- `context.env` and `context.team` are assumed Tsuga standard fields but may not be present on GCP cloud metrics (these are typically applied to agent-collected metrics, not cloud integrations).


---

# Google Cloud Storage — Golden Signals

## Traffic

### What it means for GCS
Request volume and data transfer rates across all bucket operations. GCS traffic is measured by API call count (`api/request_count`) and network bytes (`network/sent_bytes_count`, `network/received_bytes_count`). Traffic patterns reveal whether applications are reading, writing, listing, or deleting objects, and at what intensity.

### Typical causes when it degrades
- Application deployment changes (new batch jobs, migration scripts)
- Misconfigured retry loops amplifying requests (429 -> retry -> 429 loop)
- Upstream traffic shift (CDN cache purge driving reads back to origin)
- List operations increasing due to growing object counts or directory-style enumeration

### Best telemetry sources
- `api/request_count` grouped by `method` — primary traffic signal
- `network/sent_bytes_count` — egress bandwidth (cost driver)
- `network/received_bytes_count` — ingress bandwidth
- `anywhere_cache/request_count` — cache-layer traffic (if enabled)

### What people page on
- Unexpected drop in write traffic (data pipeline failure)
- Sustained spike in read traffic beyond capacity (auto-scaling lag)
- Request rate approaching per-bucket scaling limits (precursor to throttling)

### Section questions
1. **Is request volume within expected bounds?** → Traffic & Request Volume section
2. **Which operations dominate traffic?** → Traffic & Request Volume section (method breakdown)
3. **How much data is flowing in and out?** → Network & Bandwidth section

---

## Errors

### What it means for GCS
Failed API requests indicated by non-`OK` response codes. GCS errors fall into client errors (caller's fault: `PERMISSION_DENIED`, `NOT_FOUND`, `INVALID_ARGUMENT`) and server errors (GCS's fault: `INTERNAL`, `UNAVAILABLE`, `DEADLINE_EXCEEDED`). Throttling (`RESOURCE_EXHAUSTED`) sits between — it's GCS enforcing limits but the caller can mitigate.

### Typical causes when it degrades
- IAM policy changes causing `PERMISSION_DENIED` wave (propagation delay ~1 min)
- Bucket rate limit exceeded (`RESOURCE_EXHAUSTED` / 429)
- GCS regional incident (`INTERNAL`, `UNAVAILABLE`)
- Application bugs accessing non-existent objects (`NOT_FOUND`)
- Token expiration or rotation (`UNAUTHENTICATED`)

### Best telemetry sources
- `api/request_count` filtered by `response_code != OK` — primary error signal
- `api/request_count` where `response_code` in (`INTERNAL`, `UNAVAILABLE`, `DEADLINE_EXCEEDED`) — server-side errors
- `api/request_count` where `response_code = RESOURCE_EXHAUSTED` — throttling
- `api/request_count` where `response_code = PERMISSION_DENIED` — access control issues

### What people page on
- Server-error rate (5xx equivalent) rising above baseline for production buckets
- Throttling rate sustaining beyond transient burst
- Sudden `PERMISSION_DENIED` spike affecting production service accounts

### Section questions
1. **Are API requests succeeding?** → Errors & Reliability section
2. **Is GCS throttling our requests?** → Errors & Reliability section (RESOURCE_EXHAUSTED breakdown)
3. **Are there access control problems?** → Errors & Reliability section (PERMISSION_DENIED trend)

---

## Latency

### What it means for GCS
Time to complete API operations. **Critical caveat: GCS provides no server-side latency metric.** Latency can only be measured client-side — via gRPC client metrics (`client/grpc/client/attempt/duration`) or application-instrumented spans. Replication delay (`turbo_max_delay`) is the closest server-side "latency" signal, measuring how long until writes propagate across regions.

### Typical causes when it degrades
- GCS auto-scaling lag (bucket newly receiving high traffic)
- Sequential key naming causing hotspots on a single backend
- Geographic distance between client and bucket region
- Large object sizes increasing transfer time
- Client-side resource constraints (CPU, memory, network)

### Best telemetry sources
- `client/grpc/client/attempt/duration` — per-attempt latency (gRPC clients only)
- `client/grpc/client/call/duration` — end-to-end call latency including retries (gRPC clients only)
- `replication/turbo_max_delay` — max age of unsynced objects (dual-region turbo only)
- Application-instrumented spans (not available in GCS server-side metrics)

### What people page on
- Client-observed p99 latency exceeding SLO for critical paths
- Replication delay exceeding 15-minute RPO on turbo-enabled buckets
- Sustained latency degradation correlated with `RESOURCE_EXHAUSTED` responses

### Section questions
1. **Is replication keeping up?** → Replication & Durability section
2. **Are there signs of backend throttling affecting perceived latency?** → Errors & Reliability section (RESOURCE_EXHAUSTED as proxy)

---

## Saturation

### What it means for GCS
Resource utilization approaching hard limits. For a managed service like GCS, saturation manifests as bandwidth quota usage, per-bucket request rate limits, storage capacity growth, and cache pressure (if Anywhere Cache is enabled).

### Typical causes when it degrades
- Bandwidth quota approaching project limit (200 Gbps default)
- Per-bucket request rate exceeding auto-scale capacity
- Storage growing faster than lifecycle rules can clean up (versioning, soft-delete accumulation)
- Anywhere Cache eviction rate rising (cache undersized for working set)
- Object count growing into millions (slows listing operations)

### Best telemetry sources
- `quota/*/usage` vs `quota/*/limit` — bandwidth quota saturation
- `quota/*/exceeded` — any non-zero value = quota breach
- `api/request_count` where `response_code = RESOURCE_EXHAUSTED` — rate limit saturation
- `storage/total_bytes` by `storage_class` — capacity trends (daily granularity)
- `storage/object_count` — object count trends (daily granularity)
- `anywhere_cache_metering/eviction_byte_count` — cache pressure (if enabled)

### What people page on
- Bandwidth quota usage >80% of limit (leading indicator)
- `RESOURCE_EXHAUSTED` error count sustaining beyond transient burst
- Storage cost spike from unexpected `total_bytes` growth
- Object count crossing millions (listing performance degradation)

### Section questions
1. **Is storage growing as expected?** → Storage Capacity & Growth section
2. **Are we approaching bandwidth or request rate limits?** → Network & Bandwidth section
3. **Is the cache keeping up with demand?** → Network & Bandwidth section (if Anywhere Cache enabled)

---

### Confirmed by sources
- GCS does not expose a server-side latency metric ([Data storage SLI metrics](https://docs.cloud.google.com/stackdriver/docs/solutions/slo-monitoring/sli-metrics/data-storage-metrics)).
- gRPC client-side metrics (`client/grpc/client/attempt/duration`, `client/grpc/client/call/duration`) are the only latency signals ([gRPC client-side metrics](https://docs.cloud.google.com/storage/docs/client-side-metrics)).
- Default bandwidth quota is 200 Gbps per project per region ([Bandwidth usage overview](https://docs.cloud.google.com/storage/docs/bandwidth-usage)).
- Per-bucket baseline: ~5,000 reads/s, ~1,000 writes/s; auto-scales over minutes ([Request rate guidelines](https://docs.cloud.google.com/storage/docs/request-rate)).
- `RESOURCE_EXHAUSTED` response code indicates rate limit or quota exceeded ([Cloud Storage error responses](https://cloud.google.com/storage/docs/json_api/v1/status-codes)).
- Replication metrics (`meeting_rpo`, `turbo_max_delay`) only exist for dual/multi-region buckets with turbo replication ([Managing turbo replication](https://docs.cloud.google.com/storage/docs/managing-turbo-replication)).

### Best-practice inference
- Using bandwidth quota at >80% as a leading indicator is operational best practice, not a documented GCS threshold.
- Listing performance degradation at millions of objects is widely reported but not formally documented with a specific threshold.
- Cache eviction rate as a saturation signal is inferred from general caching principles applied to Anywhere Cache.


---

# Google Cloud Storage — Section Notes & Playbooks

---

## Part 1: Overview Mission Note

**Google Cloud Storage**
Fully managed object storage for blobs, backups, logs, and data lake objects across GCP regions.

**Scope:** All GCS buckets reporting via the GCP Cloud Storage integration. Covers API traffic, errors, network bandwidth, storage capacity, replication health, and access patterns. Does not cover client-side latency (requires gRPC client instrumentation) or Anywhere Cache.

**Links:**
- [Cloud Storage monitoring overview](https://docs.cloud.google.com/storage/docs/monitoring)
- [Request rate and access guidelines](https://docs.cloud.google.com/storage/docs/request-rate)
- [GCS Deep Dive dashboard](#) *(link to deep dive)*

---

## Part 2: Section Explanation Notes

### # Are GCS request rates and traffic patterns within expected bounds?

#### So what?
Healthy GCS traffic shows a **stable request rate** with a predictable read/write mix matching your application pattern. A sudden spike in `ReadObject` may mean a CDN cache purge is sending reads back to origin. A spike in `ListObjects` may indicate a misconfigured batch job enumerating large buckets. **Watch out:** client libraries automatically retry 429 and 5xx errors — the server-side `Total Request Rate` may be higher than your application intends due to **retry amplification**.

#### Now what?
Check **Request Rate by Method** to identify which operation type is driving the change → check **Top Buckets by Request Rate** to isolate the bucket → correlate with recent deployments or upstream traffic shifts.

---

### # Are API requests succeeding and is GCS throttling us?

#### So what?
GCS errors use gRPC status codes, not HTTP codes. **Server errors** (`INTERNAL`, `UNAVAILABLE`, `DEADLINE_EXCEEDED`) indicate GCS-side issues and are the only errors that count against the GCS SLA. **Client errors** (`PERMISSION_DENIED`, `NOT_FOUND`) are caller-side issues. **Throttling** (`RESOURCE_EXHAUSTED`) means the bucket is hitting per-bucket rate limits (~5K reads/s, ~1K writes/s baseline) or project bandwidth quotas. **Watch out:** a brief `PERMISSION_DENIED` spike after IAM policy changes is normal — IAM grants are eventually consistent (~1 min propagation).

#### Now what?
Check **Error Rate (%)** to assess severity → break down via **Errors by Response Code** to classify server vs client vs throttling → check **Top Buckets by Error Rate** to isolate the affected bucket → if throttling, reduce request rate or ramp up gradually (double every 20 min).

---

### # How much data is flowing in and out, and are we approaching bandwidth limits?

#### So what?
Egress bandwidth is the primary **cost driver** for GCS — ingress is free. Sustained high egress may approach the project bandwidth quota (200 Gbps default per region). **Watch out:** bandwidth metrics are in **bytes/s** but quota limits are in **bits/s** — multiply by 8 when comparing. A sudden egress spike on a bucket that normally has low traffic may indicate data exfiltration or a misconfigured data pipeline.

#### Now what?
Check **Egress Bandwidth (MB/s)** for overall rate → check **Top Buckets by Egress** to find the source → check **Egress by Method** to understand if it's `ReadObject` (normal reads) or `CopyObject`/`RewriteObject` (cross-bucket transfer) → compare with quota limits if approaching saturation.

---

### # How much data is stored and is storage growing as expected?

#### So what?
Storage metrics update **once per 24 hours** — don't panic over sudden step-changes, they're just the daily refresh catching up. Healthy storage shows linear growth matching your data retention policy. **Super-linear growth** usually means: (1) object versioning accumulating noncurrent versions, (2) lifecycle rules not firing (misconfigured conditions), (3) soft-delete retention preserving "deleted" objects for up to 90 days, or (4) abandoned multipart uploads. **Watch out:** `total_bytes` (v1) excludes soft-deleted objects — actual billed storage may be higher.

#### Now what?
Check **Storage by Class** to see tier distribution → check **Top Buckets by Storage** to find the largest consumers → check **Object Count** trends for unexpected growth → check **Deleted Bytes per Day** to verify lifecycle/cleanup is working → if growth is unexpected, verify lifecycle rules and object versioning settings.

---

### # Is cross-region replication healthy and meeting RPO targets?

#### So what?
Replication metrics **only exist for dual/multi-region buckets with turbo replication**. No data = feature not enabled, not a failure. `meeting_rpo = 1` means all objects are replicating within the 15-minute RPO target. `turbo_max_delay` shows the worst-case: the oldest unsynced object's age in seconds (threshold: 900s = 15 min). **Watch out:** replication metrics have a **multi-hour reporting delay** — an RPO violation happening right now may not appear for hours. Use `api/request_count` error patterns as a faster leading indicator of regional issues.

#### Now what?
Check **Meeting RPO** status → if 0, check **Max Replication Delay** to see how far behind → check **Missed RPO Minutes (last 30d)** for historical pattern → if delay is rising, check for high write throughput or large object uploads that may be overwhelming replication capacity.

---

### # Are authentication patterns normal and is ACL migration progressing?

#### So what?
Authentication metrics show who is accessing GCS and how. The goal for ACL metrics is **zero** — any non-zero `ACL Operations Rate` means legacy ACL-based access is still in use, blocking migration to uniform bucket-level access (the recommended state). **Watch out:** `access_id` is a high-cardinality label (one per service account). Never group by `access_id` without filtering to a specific bucket first. Use `authn_method` for broad auth pattern analysis.

#### Now what?
Check **Auth Requests by Method** for expected auth patterns → check **ACL Operations Rate** — if non-zero, identify which buckets still use ACLs → check **ACL-Based Object Access** — if non-zero, those objects are being accessed via ACL grants and need IAM migration before enabling uniform access.

---

### # Are objects in the right storage classes and is Autoclass optimizing costs?

#### So what?
Autoclass metrics only appear for buckets with Autoclass enabled. **High transition counts right after enabling Autoclass are normal** — it's reclassifying existing objects based on historical access. Counts should stabilize within days. Sustained high transitions after the initial period may indicate **thrashing** — objects being accessed just enough to trigger upward transitions, then cooling off and transitioning back down. **Watch out:** small objects (<1 MB) cost more to transition (Class A operation fees) than they save in storage, so high transition counts on small-object buckets may actually increase costs.

#### Now what?
Check **Autoclass Transitions Over Time** for stabilization pattern → check **Autoclass Transitioned Bytes** to see if transitions involve large or small objects → cross-reference with **Storage by Class** in the Capacity section to verify objects are landing in expected tiers.

---

## Part 3: Cause-Effect Triage Chains (>= 20 chains)

1. If **Error Rate (%)** rises above 1% → check **Errors by Response Code** to classify error type → if mostly `INTERNAL`/`UNAVAILABLE`, likely GCS regional incident → check GCS status page. (Confirmed)

2. If **Server Error Rate (%)** spikes → check **Errors by Response Code** for `INTERNAL` vs `UNAVAILABLE` → check **Top Buckets by Error Rate** to see if it's one bucket or all → likely regional GCS issue → check GCP status dashboard. (Confirmed)

3. If **Throttle Rate (%)** rises above 0 → check **Top Buckets by Request Rate** for the hottest bucket → check **Request Rate by Method** for the dominant operation → likely per-bucket rate limit hit → reduce request rate or ramp gradually. (Confirmed)

4. If **Total Request Rate** drops suddenly → check **Error Rate (%)** for correlated error spike → check **Errors by Response Code** for `UNAVAILABLE` → if errors are zero, upstream application stopped making requests → check application health. (Mixed)

5. If **Egress Bandwidth (MB/s)** spikes → check **Top Buckets by Egress** to identify source → check **Egress by Method** for operation type → if `ReadObject` spike, likely CDN cache purge or batch job → verify with application team. (Inference)

6. If **Egress Bandwidth (MB/s)** approaches project quota → check quota metrics if available → reduce read-heavy workloads or request quota increase → implement client-side caching. (Inference)

7. If **Ingress Bandwidth (MB/s)** drops to zero → check **Total Request Rate** for `WriteObject`/`InsertObject` methods → likely upstream data pipeline failure → check ingestion application health. (Mixed)

8. If **Total Storage (GiB)** grows faster than expected → check **Storage by Class** for which tier is growing → check **Top Buckets by Storage** for the growing bucket → check **Object Count** trends → likely versioning accumulation or lifecycle rules not firing. (Mixed)

9. If **Total Objects (count)** exceeds millions → listing operations will degrade → check **Request Rate by Method** for `ListObjects` latency symptoms (high count) → consider restructuring object naming or using prefix filters. (Inference)

10. If **Deleted Bytes per Day** is zero on buckets with lifecycle rules → lifecycle rules may be misconfigured → check rule conditions (age, creation date, storage class) match actual objects. (Inference)

11. If **Meeting RPO** drops to 0 → check **Max Replication Delay (s)** for current lag → check **Missed RPO Minutes (last 30d)** for historical context → if delay > 900s, turbo replication is actively failing → check for high write throughput. (Confirmed)

12. If **Max Replication Delay (s)** exceeds 900 → RPO is being violated → check **Total Request Rate** for write volume spike → check for large object uploads → if sustained, may need to reduce write rate to allow replication to catch up. (Confirmed)

13. If **Errors by Response Code** shows spike in `PERMISSION_DENIED` → check if IAM policy recently changed → if yes, wait ~1 minute for propagation → if persists, check IAM bindings for affected service accounts. (Confirmed)

14. If **Errors by Response Code** shows spike in `NOT_FOUND` → check recent deployments for changed object key patterns → check if a cache layer was flushed → usually a client-side bug, not a GCS issue. (Inference)

15. If **Auth Requests by Method** shows unexpected authentication method → security concern → check for unauthorized HMAC key usage or unexpected OAuth clients → review IAM audit logs. (Inference)

16. If **ACL Operations Rate** is non-zero → legacy ACL access is active → check **ACL-Based Object Access** for which buckets → plan migration to uniform bucket-level access. (Confirmed)

17. If **ACL-Based Object Access** is non-zero → objects are being accessed via ACL grants → identify dependent applications → update them to use IAM-based access → then enable uniform bucket-level access. (Confirmed)

18. If **Autoclass Transitions** remain high after initial stabilization → possible thrashing → check **Autoclass Transitioned Bytes** for object sizes → if small objects, Autoclass may not be cost-effective → consider manual storage class assignment. (Inference)

19. If **Request Rate by Method** shows `ListObjects` dominating → possible inefficient enumeration pattern → check application code for recursive listing → consider using prefix/delimiter parameters or hierarchical namespace buckets for better performance. (Inference)

20. If **Errors by Response Code** shows `RESOURCE_EXHAUSTED` AND **Egress Bandwidth** is near quota → project bandwidth quota hit → request quota increase via Cloud Console → implement backoff for 429 errors → consider CDN for read-heavy workloads. (Confirmed)

21. If **Total Storage (GiB)** grows but **Deleted Bytes per Day** is also high → storage is churning (high write + delete rate) → check **Storage by Class** for class distribution → verify this is expected behavior (log rotation, temp file patterns). (Inference)

22. If **Net Bandwidth (MB/s)** shows asymmetric pattern (high egress, low ingress) → read-heavy workload → candidate for Anywhere Cache or CDN to reduce origin egress and costs. (Inference)

---

## Part 4: Operational Playbooks (6-10 playbooks)

### Playbook 1: Elevated Server Error Rate
**Trigger:** **Server Error Rate (%)** > 0.1% sustained for 5+ minutes
**Decision rule:** If errors are bucket-specific, it's likely a hotspot or misconfig. If errors are project-wide, it's likely a GCS regional incident.
**Steps:**
1. Check **Server Error Rate (%)** to confirm the spike is sustained, not a single data point
2. Check **Errors by Response Code** to identify the specific error code (`INTERNAL` vs `UNAVAILABLE` vs `DEADLINE_EXCEEDED`)
3. Check **Top Buckets by Error Rate** to determine if errors are isolated to one bucket or widespread
4. Check **Request Rate by Method** to see if a specific operation type correlates with errors
5. If bucket-specific: check **Top Buckets by Request Rate** to see if the bucket is being overloaded
6. If project-wide: check [GCP Status Dashboard](https://status.cloud.google.com/) for known incidents
**Likely causes:**
- GCS regional incident or degradation
- Bucket rate limit exceeded (triggering `UNAVAILABLE` under load)
- Backend rebalancing after sudden traffic increase
**Next actions:**
- If GCS incident: wait for resolution, implement client-side retries with exponential backoff
- If overloaded bucket: reduce request rate, distribute across multiple buckets
- If new traffic pattern: ramp up gradually (double every 20 minutes)
**Label:** Mixed

### Playbook 2: Request Throttling (RESOURCE_EXHAUSTED)
**Trigger:** **Throttle Rate (%)** > 0 sustained for 2+ minutes
**Decision rule:** If per-bucket rate limit, reduce per-bucket request rate. If bandwidth quota, request quota increase.
**Steps:**
1. Check **Throttle Rate (%)** to quantify the impact
2. Check **Top Buckets by Request Rate** to identify the throttled bucket
3. Check **Request Rate by Method** to identify the dominant operation (reads vs writes)
4. Check **Egress Bandwidth (MB/s)** to see if bandwidth quota is also a factor
5. Check **Errors by Response Code** to confirm `RESOURCE_EXHAUSTED` is the error code
**Likely causes:**
- Per-bucket request rate exceeded (~5K reads/s, ~1K writes/s baseline)
- Project bandwidth quota exceeded (200 Gbps default)
- Sudden traffic ramp without gradual warm-up
- Sequential key naming causing backend hotspot
**Next actions:**
- Implement exponential backoff for 429 responses
- Ramp up traffic gradually (double every 20 minutes)
- Randomize object name prefixes to avoid hotspots
- Request bandwidth quota increase via Cloud Console if needed
**Label:** Confirmed

### Playbook 3: Unexpected Storage Growth
**Trigger:** **Total Storage (GiB)** daily growth exceeds expected baseline by 2x+
**Decision rule:** If growth is from noncurrent versions, review versioning policy. If from a specific bucket, check lifecycle rules.
**Steps:**
1. Check **Total Storage (GiB)** to confirm the growth magnitude
2. Check **Storage by Class** to identify which storage class is growing
3. Check **Top Buckets by Storage** to isolate the growing bucket
4. Check **Top Buckets by Object Count** to see if object count is also growing disproportionately
5. Check **Deleted Bytes per Day** to verify lifecycle cleanup is working
6. If soft-delete suspected: check v2/total_bytes with type label (not in default dashboard — may need ad-hoc query)
**Likely causes:**
- Object versioning accumulating noncurrent versions without lifecycle cleanup
- Soft-delete retention (default 90 days) preserving "deleted" objects
- Abandoned multipart uploads consuming storage
- Lifecycle rules misconfigured (wrong age/class conditions)
- Unexpected data pipeline producing more data than planned
**Next actions:**
- Verify lifecycle rules are correctly configured on the growing bucket
- Set `AbortIncompleteMultipartUpload` lifecycle rule if missing
- Reduce soft-delete retention period if 90 days is excessive
- Add noncurrent version deletion lifecycle rule
**Label:** Mixed

### Playbook 4: Replication RPO Violation
**Trigger:** **Meeting RPO** = 0 AND **Max Replication Delay (s)** > 900
**Decision rule:** If delay is growing, replication is falling further behind. If delay is stable near threshold, it may self-recover.
**Steps:**
1. Check **Meeting RPO** to confirm violation
2. Check **Max Replication Delay (s)** for current lag value
3. Check **Replication Delay Over Time** for trend (growing vs stabilizing)
4. Check **Missed RPO Minutes (last 30d)** for historical frequency
5. Check **Total Request Rate** and **Ingress Bandwidth** to see if high write volume is overwhelming replication
**Likely causes:**
- Sustained high write throughput exceeding replication bandwidth
- Very large object uploads taking longer to replicate
- GCS cross-region replication infrastructure degradation
**Next actions:**
- If write-driven: reduce write rate temporarily to allow replication to catch up
- If large objects: consider smaller chunk sizes for write-heavy workflows
- If GCS-side: check GCP status page for replication service issues
- Review RPO SLA requirements — brief violations may be acceptable
**Label:** Confirmed

### Playbook 5: Permission Denied Wave
**Trigger:** **Errors by Response Code** shows spike in `PERMISSION_DENIED`
**Decision rule:** If correlated with a recent IAM change, wait for propagation. If persistent, investigate IAM bindings.
**Steps:**
1. Check **Errors by Response Code** to confirm `PERMISSION_DENIED` is the dominant error
2. Check **Top Buckets by Error Rate** to identify affected buckets
3. Check **Errors by Method** to see which operations are failing
4. Check Cloud Audit Logs for recent IAM policy changes (not in this dashboard — requires log viewer)
5. Check **Auth Requests by Method** for unexpected authentication patterns
**Likely causes:**
- Recent IAM policy change with ~1 minute propagation delay
- Service account key rotation leaving a gap
- Uniform bucket-level access migration breaking ACL-dependent workflows
- Cross-project access misconfiguration
**Next actions:**
- If recent IAM change: wait 1-2 minutes for propagation, then recheck
- If persistent: verify IAM bindings on affected bucket using `gcloud storage buckets get-iam-policy`
- If service account issue: check key validity and rotation status
- Check if uniform bucket-level access was recently enabled on a bucket with ACL-dependent clients
**Label:** Mixed

### Playbook 6: Bandwidth Quota Approaching Limit
**Trigger:** **Egress Bandwidth (MB/s)** sustained high, approaching known project quota
**Decision rule:** If a single bucket drives most egress, optimize that bucket. If distributed, request quota increase.
**Steps:**
1. Check **Egress Bandwidth (MB/s)** to quantify current rate
2. Check **Top Buckets by Egress** to identify the top egress sources
3. Check **Egress by Method** to understand the operation pattern
4. Check **Request Rate by Method** for `ReadObject` volume
5. Check for `RESOURCE_EXHAUSTED` in **Errors by Response Code** (appears when quota is actually hit)
**Likely causes:**
- High-traffic read workload (analytics, data export, media serving)
- CDN cache purge driving reads back to GCS origin
- Data migration or cross-region copy job
- Batch processing reading large datasets
**Next actions:**
- Request bandwidth quota increase via Cloud Console (up to 1 Tbps self-service)
- Implement Cloud CDN or Media CDN for cacheable content
- Enable Anywhere Cache for zone-local hot reads
- Stagger batch workloads across time to reduce peak bandwidth
**Label:** Mixed

### Playbook 7: ACL Migration Assessment
**Trigger:** **ACL Operations Rate** or **ACL-Based Object Access** is non-zero
**Decision rule:** If ACL activity is declining, migration is progressing. If stable or growing, legacy workflows are still active.
**Steps:**
1. Check **ACL Operations Rate** to see current ACL activity level
2. Check **ACL-Based Object Access** to see if objects are being accessed via ACLs
3. Check **Auth Requests by Method** to understand the auth landscape
4. Identify buckets still using ACLs (not in this dashboard — requires per-bucket check)
5. Plan IAM-based access replacement for each ACL-dependent workflow
**Likely causes:**
- Legacy applications still using ACL-based access patterns
- Third-party integrations that set object ACLs
- Workflows that haven't been migrated to IAM after initial setup
**Next actions:**
- Audit which buckets have ACL activity using `authz/acl_operations_count` grouped by bucket
- For each bucket, identify clients using ACLs
- Migrate clients to IAM-based access
- Enable uniform bucket-level access on migrated buckets (irreversible after 90 days)
**Label:** Confirmed


---

# Google Cloud Storage — Caveats & Footguns

## High-cardinality dimensions to avoid

- **[traffic-request-volume, errors-reliability]** `access_id` on `authn/authentication_count` is unbounded (one per service account/HMAC key). Never group-by without filtering to a specific bucket first. Use `authn_method` instead for auth pattern analysis. (Confirmed: [Uniform bucket-level access docs](https://docs.cloud.google.com/storage/docs/using-uniform-bucket-level-access))

- **[traffic-request-volume, storage-capacity-growth]** `bucket_name` can be high-cardinality in large orgs with hundreds of buckets. Always use top-N limits (25 max) when grouping by bucket. Pre-filter by project/region in global filters. (Inference)

## Misleading metrics and wrong aggregations

- **[storage-capacity-growth]** `storage/total_bytes` and `storage/object_count` update **once per 24 hours**. Do NOT use `average` aggregation over short windows — the value will appear flat with step-changes at the daily refresh. Use `max` aggregation and view at 1d+ granularity. (Confirmed: [Cloud Storage monitoring](https://docs.cloud.google.com/storage/docs/monitoring))

- **[storage-capacity-growth]** `storage/total_bytes` (v1) excludes soft-deleted objects. If soft-delete retention is enabled (default: 90 days), actual billed storage is higher. Use `storage/v2/total_bytes` with `type` label to see the full picture. (Confirmed: [Cloud Storage troubleshooting](https://docs.cloud.google.com/storage/docs/troubleshooting))

- **[errors-reliability]** `NOT_FOUND` responses are client errors, not GCS failures. High `NOT_FOUND` rates usually mean application bugs (wrong object keys) or race conditions, not storage reliability issues. Do not include them in "server error rate" calculations. (Inference)

- **[errors-reliability]** `PERMISSION_DENIED` after an IAM policy change may persist for ~1 minute due to eventual consistency of IAM grants. A brief spike after policy changes is normal and not an outage. (Confirmed: [Cloud Storage consistency](https://docs.cloud.google.com/storage/docs/consistency))

- **[traffic-request-volume]** `api/request_count` counts server-side requests. Client libraries automatically retry 408, 429, and 5xx errors with exponential backoff. The client sees fewer errors than `api/request_count` shows because retries are transparent. Conversely, total request count may be higher than the application intends due to retry amplification. (Confirmed: [Cloud Storage troubleshooting](https://docs.cloud.google.com/storage/docs/troubleshooting))

## Unit pitfalls

- **[network-bandwidth]** `network/sent_bytes_count` and `network/received_bytes_count` are in **bytes**, not bits. Bandwidth quotas (`quota/*`) are in **bits/s**. When comparing egress rate to quota limits, convert: bytes/s * 8 = bits/s. (Confirmed: [Bandwidth usage overview](https://docs.cloud.google.com/storage/docs/bandwidth-usage))

- **[storage-capacity-growth]** `storage/total_byte_seconds` is in `By.s` (byte-seconds) — a billing unit, not a storage size. Do NOT display this as "bytes" or use it for capacity dashboards. Use `total_bytes` for capacity. (Confirmed: [Google Cloud metrics reference](https://docs.cloud.google.com/monitoring/api/metrics_gcp_p_z))

- **[replication-durability]** `replication/turbo_max_delay` is in seconds, but the RPO target is 15 minutes (900 seconds). Display the threshold line at 900s when building timeseries widgets to make RPO violations visually obvious. (Confirmed: [Managing turbo replication](https://docs.cloud.google.com/storage/docs/managing-turbo-replication))

## Sampling/temporality pitfalls

- **[traffic-request-volume, errors-reliability, network-bandwidth]** `api/request_count`, `network/sent_bytes_count`, and `network/received_bytes_count` are **DELTA** counters (GCP Cloud Monitoring type: `DELTA`). In Tsuga, use `per-second` (not `rate`) for delta counters. If the Tsuga integration reports them as cumulative, use `rate` instead. **Stage 2 discovery must confirm temporality.** (Confirmed: [Google Cloud metrics reference](https://docs.cloud.google.com/monitoring/api/metrics_gcp_p_z))

- **[storage-capacity-growth]** Storage metrics are **daily gauges**. Setting a dashboard time window shorter than 24 hours may show empty data or a single flat point. Use 7d+ windows for storage trends. (Confirmed: [Cloud Storage monitoring](https://docs.cloud.google.com/storage/docs/monitoring))

- **[replication-durability]** Replication metrics have a **multi-hour reporting delay**. An RPO violation happening now may not show in metrics for hours. Do not use these for real-time incident detection — use `api/request_count` error patterns as a leading indicator instead. (Confirmed: [Managing turbo replication](https://docs.cloud.google.com/storage/docs/managing-turbo-replication))

## "This looks bad but isn't"

- **[errors-reliability]** A spike in `NOT_FOUND` responses after a deployment is normal if the new code references objects that haven't been created yet, or if a cache layer was flushed. Check if the `NOT_FOUND` rate returns to baseline within minutes. (Inference)

- **[replication-durability]** `meeting_rpo = 0` with `turbo_max_delay < 900s` can happen briefly during metric calculation. The metrics update at different intervals. Only escalate if `turbo_max_delay` exceeds 900s for sustained periods. (Inference)

- **[cost-storage-class]** High Autoclass transition counts immediately after enabling Autoclass are expected — it's reclassifying existing objects based on historical access patterns. Counts should stabilize within days. (Confirmed: [Autoclass docs](https://docs.google.com/storage/docs/autoclass))

- **[storage-capacity-growth]** `object_count` appearing to jump suddenly is usually the daily refresh catching up with a day's worth of writes, not a sudden burst. Correlate with `api/request_count` method=InsertObject to confirm actual write rate. (Inference)

## Optional-feature traps (metrics absent unless X enabled)

- **[replication-durability]** Replication metrics (`meeting_rpo`, `turbo_max_delay`, `missing_rpo_minutes_last_30d`) are **only present** for dual/multi-region buckets with turbo replication. For single-region buckets, these metrics will never appear. Dashboard must show a gating note, not an error state. (Confirmed: [Managing turbo replication](https://docs.cloud.google.com/storage/docs/managing-turbo-replication))

- **[cost-storage-class]** Autoclass metrics (`transition_operation_count`, `transitioned_bytes_count`) are **only present** when Autoclass is enabled on a bucket. Absence = feature off, not a problem. (Confirmed: [Autoclass docs](https://docs.cloud.google.com/storage/docs/autoclass))

- **[access-security]** ACL metrics (`authz/*`) are **only present** for buckets that have NOT enabled uniform bucket-level access. If all buckets use uniform access (the recommended state), these metrics will be absent. Absence is the goal. (Confirmed: [Uniform bucket-level access](https://docs.cloud.google.com/storage/docs/using-uniform-bucket-level-access))

- **[access-security]** `authn/authentication_count` requires the GCP integration to collect `authn/*` metrics. Not all integration configurations include this metric family by default — it may need explicit opt-in. (Inference)

- **[traffic-request-volume, errors-reliability]** The `response_code` label uses gRPC status codes (`OK`, `PERMISSION_DENIED`, `RESOURCE_EXHAUSTED`), NOT HTTP status codes (200, 403, 429). Do not build filters using HTTP numeric codes. (Confirmed: [Google Cloud metrics reference](https://docs.cloud.google.com/monitoring/api/metrics_gcp_p_z))


---

