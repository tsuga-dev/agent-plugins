# `gcloud` → `tsuga` Translator

For projects wired to a Cloud Monitoring → Tsuga pipeline, most read-only GCP CLI/Monitoring queries have a `tsuga aggregation` equivalent.

Unlike AWS, **metric names are kept in their native form**: `<service>.googleapis.com/<path>` (with literal slashes).

- Inside an aggregation `field`, raw slashes work as-is.
- For `tsuga metrics get <name>`, slashes must be URL-encoded as `%2F` — otherwise the router returns `404 URL_NOT_FOUND`.

## What's queryable

What's **always** queryable: anything Cloud Monitoring publishes for the project, included in the export pipeline.

What's **not** ingested:

- GCP resource spec / configuration (everything `gcloud compute instances describe ...` returns).
- Cloud Logging log entries (project log buckets) — only ingested when shipped via OTel collector.
- IAM / Cloud Resource Manager. Refuse, point at `gcloud`.

To enumerate the GCP service prefixes ingested into your tenant:

```bash
tsuga metrics list --from -1h | jq -r '.[].name' \
  | grep 'googleapis.com' \
  | awk -F'.googleapis.com' '{print $1}' | sort -u
```

Common prefixes: `compute`, `cloudsql`, `pubsub`, `run`, `storage`, `loadbalancing`, `bigquery`, `router`, `serviceruntime`, `container`, `monitoring`, `artifactregistry`, `dns`, `logging`.

## Standard attributes (every GCP metric)

```
context.cloud.provider      "gcp"
context.cloud_account_id    GCP project id (also exposed as context.project_id)
context.project_id          GCP project id (canonical for scoping)
context.cloud.region        e.g. "europe-west1"
context.gcp.resource_type   monitored resource kind (e.g. "cloudsql_database", "gcs_bucket")
```

## Per-service resource-id dimensions

Confirm per metric with `tsuga metrics get '<name with slashes encoded as %2F>' | jq '.attributes'`. Common shapes:

| Service prefix | Resource dimension(s) |
|---|---|
| `cloudsql.googleapis.com/*` | `context.database_id` (`<project>:<instance>` form) |
| `compute.googleapis.com/instance/*` | `context.instance_id`, `context.instance_name` |
| `pubsub.googleapis.com/subscription/*` | `context.subscription_id` |
| `pubsub.googleapis.com/topic/*` | `context.topic_id` |
| `storage.googleapis.com/*` | `context.bucket_name`, `context.storage_class`, `context.location` |
| `loadbalancing.googleapis.com/*` | `context.backend_service_id`, `context.load_balancing_scheme`, `context.client_country`, `context.protocol`, `context.matcher_name` |
| `run.googleapis.com/*` | `context.faas.name`, `context.faas.instance`, `context.faas.version` |
| `bigquery.googleapis.com/*` | `context.project_id` (per-project metrics dominant) |

## Worked examples

### CloudSQL — CPU

```bash
NOW=$(date +%s); FROM=$((NOW - 1800))
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"max",field:"cloudsql.googleapis.com/database/cpu/utilization"}}],
  groupBy:[{fields:["context.database_id"],limit:10}]
}')"
```

`context.database_id` is `<project>:<instance>` — use `context.project_id` to scope to a single project.

### Pub/Sub — subscription backlog age

```bash
NOW=$(date +%s); FROM=$((NOW - 1800))
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"max",field:"pubsub.googleapis.com/subscription/oldest_unacked_message_age"}}],
  groupBy:[{fields:["context.subscription_id"],limit:5}]
}')"
```

Result is in **seconds**.

### Cloud Storage — bucket size

```bash
NOW=$(date +%s); FROM=$((NOW - 7200))   # GCS publishes hourly
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"max",field:"storage.googleapis.com/storage/total_bytes"}}],
  groupBy:[{fields:["context.bucket_name"],limit:5}]
}')"
```

### Compute Engine — instance CPU

```bash
NOW=$(date +%s); FROM=$((NOW - 600))
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"max",field:"compute.googleapis.com/instance/cpu/utilization"}}],
  groupBy:[{fields:["context.instance_name"],limit:5}]
}')"
```

### Cloud Run — request count / instance count

```bash
NOW=$(date +%s); FROM=$((NOW - 3600))
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"sum",field:"run.googleapis.com/request_count"}}],
  groupBy:[{fields:["context.faas.name"],limit:5}]
}')"
```

Related: `run.googleapis.com/container/cpu/utilizations` (gauge), `run.googleapis.com/container/instance_count`, `run.googleapis.com/request_latency/user_execution` (use `percentile` only after confirming the metric type is gauge or histogram).

## GKE — Kubernetes metrics

GKE clusters produce the standard OTel `k8s.*` metric family. Use the `kubectl` translator pattern with `context.k8s.cluster.name:<gke-cluster-name>`:

```bash
NOW=$(date +%s); FROM=$((NOW - 600))
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"max",field:"k8s.pod.cpu.usage"},filter:"context.k8s.cluster.name:<gke-cluster>"}],
  groupBy:[{fields:["context.k8s.pod.name"],limit:5}]
}')"
```

See `${CLAUDE_PLUGIN_ROOT}/skills/tsuga-cli/references/kubectl-translator.md` for the full pattern.

## Gotchas specific to GCP

1. **Slashes in metric names**.
   - Aggregation `field`: raw `cloudsql.googleapis.com/database/cpu/utilization` is correct.
   - `tsuga metrics get`: URL-encode (`%2F`).
2. **`context.database_id` format** is `<project>:<instance>`, not the bare instance name. Use `context.project_id` for project-only scoping.
3. **Cloud Run instance churn**: `context.faas.instance` is short-lived; use `context.faas.name` (service name) for stable scoping.
4. **Publish cadence is per-resource-type** — CloudSQL is 1m, GCS is hourly. Storage queries narrower than ~2h often return empty even when data exists.
5. **`gcp.resource_type` is your sanity check** when a metric is missing dimensions: `tsuga metrics get <name> | jq '.attributes'` includes `context.gcp.resource_type`, naming the monitored-resource kind.

## What's not coverable

| `gcloud` verb | Reason |
|---|---|
| `gcloud compute instances describe ...` / any `describe` | Spec data; not ingested |
| `gcloud sql instances describe ...` | Same |
| `gcloud logging read ...` | Cloud Logging not wired by default |
| `gcloud iam *` / `gcloud projects *` | Identity / IaC, out of scope |
| `gcloud pubsub subscriptions pull ...` | Data plane, by design |
| Anything that writes / mutates | By design |
