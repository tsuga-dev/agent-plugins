---
name: knowledge-technology
description: "Supplies per-technology reference pages for 47 technologies, fetched by exact path: an overview for every one, plus the exact Tsuga metric names, incident shapes, derived signals and log patterns where that technology has them. Use before composing any Tsuga aggregation, logs or traces query, and when an incident scope, error log or monitor name mentions a covered technology or a classic symptom such as OOMKilled, CrashLoopBackOff, connection pool, deadlock, queue lag, compaction, throttle, replication lag, cold start or 5xx. Covers databases, brokers, proxies and service mesh, the Kubernetes ecosystem, AWS and GCP services, and runtimes. Source-system metric names such as CloudWatch CPUUtilization do not work in Tsuga: use the `tsuga_metric_name` column of a bundle's metrics page."
---

# Knowledge — Technology

Per-technology reference pages, served by Tsuga and fetched by exact path:

```
references/technologies/<tech>/overview   ← concepts, glossary, what Tsuga collects
references/technologies/<tech>/metrics    ← CSV; column `tsuga_metric_name` = exact string to query
references/technologies/<tech>/queries    ← incident shapes, derived signals, log patterns, gotchas
```

Only `overview` is guaranteed. A fetch of a path a technology does not have returns a 404 on stderr, not an empty catalog. Two technologies carry an extra page: `references/technologies/aws-lambda/signals` (signal choice, REPORT-log parsing) and `references/technologies/kubernetes/runbooks`.

Fetch with `tsuga docs get <path> | jq -r .content`. These pages are path-addressed only — `tsuga docs search` cannot see them and there is no index page — so pick a path from the list below.

**Always use `tsuga_metric_name` from the `metrics` page in actual `tsuga` queries.** The `name` column holds the source-system name, `tsuga_metric_name` holds what Tsuga actually registered. For anything that arrives through a translation layer — CloudWatch, JMX — the two differ and the source name returns nothing: RDS `CPUUtilization` is `aws_rds_cpu_utilization`. For natively exported metrics the two are identical (`istio_requests_total`). You cannot tell which case you are in without reading the row, so read the row.

## Covered technologies

**Databases / stores:** `postgres` · `mysql` · `mongodb` · `cassandra` · `redis` · `elasticsearch` · `etcd`

**Message brokers:** `kafka` · `rabbitmq` · `aws-sqs` · `gcp-pubsub` · `aws-eventbridge` · `aws-firehose`

**Web servers / proxies / mesh:** `nginx` · `apache` · `caddy` · `litespeed` · `haproxy` · `traefik` · `envoy` · `istio`

**Kubernetes and its ecosystem:** `kubernetes` · `argocd` · `cert-manager` · `containerd` · `keda`

**Cloud infra:** `aws-ecs` · `aws-lambda` · `aws-rds` · `aws-docdb` · `aws-dynamodb` · `aws-elasticache` · `aws-efs` · `aws-api-gateway` · `aws-elb` · `aws-nat-gateway` · `aws-privatelink` · `aws-vpc-flow-logs` · `gcp-storage` · `gcp-vpc-flow-logs`

**Runtime / platform:** `airflow` · `jvm` · `nvidia-gpu` · `openai` · `otel-collector` · `quickwit` · `vault`

Coverage gaps worth knowing before you fetch: `cert-manager`, `containerd`, `etcd`, `mongodb` and `vault` have `overview` only. `airflow`, `aws-vpc-flow-logs` and `gcp-vpc-flow-logs` are log-first and have no `metrics`.

Not listed? Fall back to a generic sweep via `$incident-investigation`.

## Reading the metrics CSV

Fetch once into a variable, filter locally, never re-fetch. Select columns **by header name** — the column set is uniform across every `metrics.csv`, but positional indexing breaks silently if one is added.

```bash
RDS=$(tsuga docs get references/technologies/aws-rds/metrics | jq -r .content)

printf '%s\n' "$RDS" | python3 -c "
import csv, sys
for r in csv.DictReader(sys.stdin):
    if 'cpu' in r['name'].lower():
        print(r['name'], '->', r['tsuga_metric_name'], '|', r['aggregation'], r['post_function'], '| by', r['group_by'])
"
# CPUUtilization -> aws_rds_cpu_utilization | max none | by context.dbinstanceidentifier:20|...
```

Swap the `if` for whatever you are narrowing on. Available columns:

`theme` · `name` · `confirmed` · `definition` · `unit` · `type` · `tsuga_metric_name` · `widget_suggestions` · `aggregation` · `post_function` · `group_by` · `required_context_fields` · `optional_context_fields` · `absence_means` · `cardinality_footguns` · `variants` · `citations`

`theme` is free text, not an enum. Five values recur across most technologies — `Availability/Health`, `Capacity/Saturation`, `Performance/Latency`, `Errors/Failures`, `Throughput/Usage` — but many files add their own (`Cost` on most AWS pages, `Memcached Efficiency` on `aws-elasticache`, `Backlog` on `aws-sqs`). Read the values present in the file before filtering on one, or you will silently drop rows.

Parse with a CSV reader, not `grep`/`awk` — `definition`, `absence_means` and `cardinality_footguns` contain commas and quoted prose.

Cross-tech questions ("which techs expose a replication metric?") cost one fetch per tech. Narrow to two or three candidates from the list above first.

## Boundary

- **This skill** — _which page to fetch, and the exact metric string to put in a query_.
- **`$tsuga-cli`** — _how to drive the CLI_: aggregation body shape, Unix-seconds `timeRange`, counter math for the `aggregation` / `post_function` columns, flags.
- **`references/incident-response/branch-telemetry-sweep`** — _how to reason_: bad window vs control window, evidence discipline.

## Anti-patterns

- Do not guess a metric name, and do not paste a CloudWatch / JMX / Prometheus source name into `tsuga`. Pull the `tsuga_metric_name` column.
- Do not dump a whole catalog into context. A raw `jq -r .content` on a large `metrics` page can cost 20k tokens — hold it in a shell variable and filter.
- Do not re-fetch a page you already have in a variable.
- Metric missing ≠ value zero. Receiver scope and IAM gaps look identical to a healthy zero. Say which one you have evidence for; the row's `absence_means` column names the usual cause for that metric, but it is a hint, not a diagnosis.
