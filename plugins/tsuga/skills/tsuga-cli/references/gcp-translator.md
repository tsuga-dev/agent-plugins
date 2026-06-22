# `gcloud` -> `tsuga` Translator

Use this for read-only Cloud Monitoring metric equivalents in Tsuga. During skill execution, emit `tsuga` commands only. Do not add shell pipes, JSON processors, GCP CLI commands, or mutation commands.

## Metric Naming

GCP metric names keep their native form, including slashes:

```text
<service>.googleapis.com/<path>
```

Inside aggregation `field`, raw slashes work as-is. For `tsuga metrics get <name>`, URL-encode slashes as `%2F`; raw slash paths can route as nested URLs.

## What Is Queryable

Queryable: Cloud Monitoring metrics included in the export pipeline.

Not queryable:

- GCP resource spec/config from `gcloud * describe`
- Cloud Logging buckets unless shipped into Tsuga separately
- IAM / Cloud Resource Manager
- Data-plane reads or mutations

Discover available GCP metrics with:

```bash
tsuga metrics list --from <from> --to <to>
```

Manually inspect metric names containing `googleapis.com`, then confirm attributes with:

```bash
tsuga metrics get <metric-name> --from <from> --to <to>
```

## Standard Attributes

- `context.cloud.provider`
- `context.cloud_account_id`
- `context.project_id`
- `context.cloud_region`
- `context.gcp.resource_type`

## Common Dimensions

| Metric family | Common dimensions |
|---|---|
| `cloudsql.googleapis.com/*` | `context.database_id` |
| `compute.googleapis.com/instance/*` | `context.instance_id`, `context.instance_name` |
| `loadbalancing.googleapis.com/*` | `context.backend_service_id`, `context.load_balancing_scheme`, `context.client_country`, `context.protocol`, `context.matcher_name` |
| `pubsub.googleapis.com/subscription/*` | `context.subscription_id` |
| `pubsub.googleapis.com/topic/*` | `context.topic_id` |
| `storage.googleapis.com/*` | `context.bucket_name`, `context.storage_class`, `context.location` |
| `run.googleapis.com/*` | `context.faas.name`, `context.faas.instance`, `context.faas.version` |

## Aggregation Template

Use this shape with one row from the use-case map. Confirm metric presence and attributes with `tsuga metrics get <metric-name> --from <from> --to <to>` before relying on it.

```bash
tsuga aggregation scalar -d '{
  "timeRange": {"from": <from_unix>, "to": <to_unix>},
  "dataSource": "metrics",
  "queries": [
    {"aggregate": {"type": "<aggregate>", "field": "<metric>"}}
  ],
  "groupBy": [{"fields": ["<dimension>"], "limit": <limit>}],
  "formula": "q1"
}'
```

For filtered cases, add `"filter": "<filter>"` inside the query object.

## Use-Case Map

| Use case | Metric | Aggregate | Group by | Filter / notes |
|---|---|---|---|---|
| CloudSQL CPU | `cloudsql.googleapis.com/database/cpu/utilization` | `max` | `context.database_id` | `context.database_id` is usually `<project>:<instance>`. |
| Pub/Sub subscription backlog age | `pubsub.googleapis.com/subscription/oldest_unacked_message_age` | `max` | `context.subscription_id` | Backlog age by subscription. |
| Cloud Storage bucket size | `storage.googleapis.com/storage/total_bytes` | `max` | `context.bucket_name` | Storage is commonly hourly; use a long enough window. |
| Compute Engine CPU | `compute.googleapis.com/instance/cpu/utilization` | `max` | `context.instance_name` | Use `context.instance_id` if names collide. |
| Cloud Run request count | `run.googleapis.com/request_count` | `sum` | `context.faas.name` | Avoid grouping by short-lived `context.faas.instance`. |
| GKE pod CPU | `k8s.pod.cpu.usage` | `max` | `context.k8s.pod.name` | Filter `context.k8s.cluster.name:<gke-cluster>`; prefer standard Kubernetes metrics when present. |

## Gotchas

- For `tsuga metrics get`, URL-encode metric slashes as `%2F`. Use raw slashes only inside aggregation `field`.
- `context.database_id` is usually `<project>:<instance>`; use `context.project_id` for project scoping.
- Use `context.gcp.resource_type` from `tsuga metrics get <metric-name> --from <from> --to <to>` as the monitored-resource sanity check.
- Publish cadence varies by resource type; storage is commonly hourly, so narrow windows can look empty.
- Cloud Run `context.faas.instance` is short-lived; prefer `context.faas.name`. Confirm `run.googleapis.com/request_latency/user_execution` type before using `percentile`.

## Safety

- Use explicit `--from`/`--to` or Unix-second `timeRange`.
- Do not infer GCP resource inventory from metrics alone; idle resources may be absent.
- Refuse GCP spec/IAM/data-plane/mutation requests from this skill and point the user to GCP tooling.
