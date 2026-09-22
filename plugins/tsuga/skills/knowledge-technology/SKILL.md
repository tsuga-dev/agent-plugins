---
name: knowledge-technology
description: "Per-technology reference bundles with exact Tsuga metric names, incident shapes, derived signals, and log patterns for ~35 techs (postgres, mysql, redis, kafka, rabbitmq, cassandra, kubernetes, nginx, haproxy, envoy, istio, jvm, otel-collector, quickwit, aws-rds, aws-lambda, aws-ecs, aws-sqs, aws-dynamodb, aws-elasticache, gcp-pubsub, gcp-storage, …). Trigger before composing any Tsuga aggregation, logs, or traces query, or when an incident scope, error log, or monitor name mentions a covered tech or a classic symptom (OOMKilled, CrashLoopBackOff, connection pool, deadlock, queue lag, compaction, throttle, replication lag, cold start, 5xx). Source-system metric names (CloudWatch CPUUtilization, etc.) do NOT work in Tsuga: use the `tsuga_metric_name` column of a bundle's metrics page."
---

# Knowledge — Technology

Three pages per technology, served by Tsuga and fetched by exact path:

```
references/technologies/<tech>/overview   ← overview, concepts, glossary
references/technologies/<tech>/metrics    ← CSV; column `tsuga_metric_name` = exact string to query in Tsuga
references/technologies/<tech>/queries    ← incident shapes, derived signals, log patterns, gotchas
```

A log-first technology has no `metrics` page. `airflow`, `aws-vpc-flow-logs`, and `gcp-vpc-flow-logs` are examples: each `overview` says so, and a fetch of the missing path fails rather than returning an empty catalog.

Fetch with `tsuga docs get <path>`, which prints `{path, title, content}` JSON. Pipe through `jq -r .content` to get the raw page. These pages are path-addressed only and never appear in `tsuga docs search`, so use the covered-technologies list below to pick a path.

**Always use `tsuga_metric_name` from the `metrics` page in actual `tsuga` queries.** Source-system names (e.g. CloudWatch `CPUUtilization`) do NOT work - Tsuga registers AWS metrics as `aws_rds_cpu_utilization`, etc.

## Generic investigation rule

Compare the **bad window** (incident) against a **good control window** (same weekday + hour, 7 days earlier) for every non-trivial metric. Metric value alone is noise; metric value vs control is signal.

## Covered technologies

**Databases / stores:** `postgres` · `mysql` · `cassandra` · `redis` · `elasticsearch`

**Message brokers:** `kafka` · `rabbitmq` · `aws-sqs` · `gcp-pubsub` · `aws-eventbridge` · `aws-firehose`

**Web servers / proxies / mesh:** `nginx` · `apache` · `caddy` · `litespeed` · `haproxy` · `envoy` · `istio`

**Cloud infra:** `kubernetes` · `aws-ecs` · `aws-lambda` · `aws-rds` · `aws-docdb` · `aws-dynamodb` · `aws-elasticache` · `aws-efs` · `aws-api-gateway` · `aws-elb` · `aws-nat-gateway` · `aws-privatelink` · `aws-vpc-flow-logs` · `gcp-storage` · `gcp-vpc-flow-logs`

**Runtime / platform:** `airflow` · `jvm` · `nvidia-gpu` · `openai` · `otel-collector` · `quickwit`

Not listed? Fall back to a generic sweep via `$incident-investigation`.

## Shell commands - finding the right metrics

Fetch a page once into a variable, then filter locally. Do not re-fetch per lookup.

```bash
# Grab a tech's metric catalog (CSV) once
RDS=$(tsuga docs get references/technologies/aws-rds/metrics | jq -r .content)

# List every tsuga_metric_name (exact strings for Tsuga queries)
printf '%s\n' "$RDS" | python3 -c 'import csv,sys; [print(r[6]) for r in list(csv.reader(sys.stdin))[1:] if len(r)>6]' | sort -u

# Filter metrics by theme (Availability/Health, Capacity/Saturation, Performance/Latency, Errors/Failures, Throughput/Usage)
printf '%s\n' "$RDS" | python3 -c 'import csv,sys; [print(r[6]) for r in list(csv.reader(sys.stdin))[1:] if len(r)>6 and r[0]=="Capacity/Saturation"]'

# Look up a metric's definition + aggregation + group_by
printf '%s\n' "$RDS" | python3 -c 'import csv,sys
for r in list(csv.reader(sys.stdin))[1:]:
    if len(r) > 10 and r[1] == "FreeStorageSpace":
        print(f"def:{r[3]}\nagg:{r[8]}\npost:{r[9]}\ngroup_by:{r[10]}")'

# Source-name to tsuga-name lookup (critical for AWS)
printf '%s\n' "$RDS" | python3 -c 'import csv,sys; [print(f"{r[1]} -> {r[6]}") for r in list(csv.reader(sys.stdin))[1:] if len(r)>6]' | grep -i cpu

# Incident shapes and query recipes for a tech (fastest read)
tsuga docs get references/technologies/postgres/queries | jq -r .content

# Glossary / concept lookup inside a tech's overview
tsuga docs get references/technologies/cassandra/overview | jq -r .content | grep -B1 -A3 -i "bloom filter"
```

Cross-tech search ("which techs expose a replication metric?") needs one fetch per tech, so it is expensive. Narrow to two or three candidates from the covered-technologies list first, then fetch only those.

## Shell commands - composing a Tsuga query

Once you have the exact `tsuga_metric_name`, compose via `$tsuga-cli`. Aggregation body uses `timeRange` + `dataSource` + `queries` (see `$tsuga-cli/SKILL.md` for the full schema). GNU `date -d` works on the container (Linux); avoid BSD-only flags like `-v-2H`.

```bash
METRIC=$(printf '%s\n' "$RDS" | python3 -c 'import csv,sys
for r in list(csv.reader(sys.stdin))[1:]:
    if len(r) > 6 and r[1] == "FreeStorageSpace":
        print(r[6]); break')
echo "$METRIC"   # -> aws_rds_free_storage_space

FROM_EPOCH=$(date -u -d '-2 hours' +%s)
TO_EPOCH=$(date -u +%s)

tsuga aggregation scalar -d "$(jq -n \
  --arg metric "$METRIC" \
  --argjson from "$FROM_EPOCH" \
  --argjson to "$TO_EPOCH" \
  '{
    timeRange: {from: $from, to: $to},
    dataSource: "metrics",
    queries: [{aggregate: {type: "min", field: $metric}}]
  }')"
```

## Boundary

- **This skill** - _where to look, what to query, exact metric names_.
- **`$tsuga-cli`** - _how to drive the CLI_ (aggregation body syntax, flags).
- **`references/incident-response/playbooks/`** (via `tsuga docs get`) - _how to reason_ (disambiguation traps).

## Anti-patterns

- Do not guess metric names. Always pull from the `tsuga_metric_name` column of the `metrics` page.
- Do not paste CloudWatch / OTel source names directly into `tsuga` - Tsuga registers them under different strings (see the CSV).
- Do not dump a whole catalog into context. Capture it in a shell variable and `awk` it down by theme or incident shape; a raw `jq -r .content` on a large `metrics` page can blow 20k tokens.
- Do not re-fetch the same page. One `tsuga docs get` per tech per session, held in a variable.
- Metric missing ≠ value zero. Receiver scope / permission issues look like absence. Say so explicitly.
