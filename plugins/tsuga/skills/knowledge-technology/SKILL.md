---
name: knowledge-technology
description: "Per-technology reference bundles with exact Tsuga metric names, incident shapes, derived signals, and log patterns for ~35 techs (postgres, mysql, redis, kafka, rabbitmq, cassandra, kubernetes, nginx, haproxy, envoy, istio, jvm, otel-collector, quickwit, aws-rds, aws-lambda, aws-ecs, aws-sqs, aws-dynamodb, aws-elasticache, gcp-pubsub, gcp-storage, …). Trigger before composing any `tsuga aggregation / tsuga logs / tsuga traces` query, or when an incident scope / error log / monitor name mentions a covered tech or a classic symptom (OOMKilled, CrashLoopBackOff, connection pool, deadlock, queue lag, compaction, throttle, replication lag, cold start, 5xx). Source-system metric names (CloudWatch CPUUtilization, etc.) do NOT work in Tsuga — use the `tsuga_metric_name` column in each tech's `metrics.csv` (AWS metrics register as `aws_rds_cpu_utilization`, `aws_lambda_errors`, …)."
---

# Knowledge — Technology

One folder per technology under `references/`. Each folder contains:

```
references/<tech>/
├── README.md       ← upstream integration bundle README (overview, concepts, glossary)
├── metrics.csv     ← full metric inventory; column `tsuga_metric_name` = exact string to query in Tsuga
└── queries.md      ← incident shapes, derived signals, log patterns, gotchas
```

**Always use `tsuga_metric_name` from `metrics.csv` in actual `tsuga` queries.** Source-system names (e.g. CloudWatch `CPUUtilization`) do NOT work - Tsuga registers AWS metrics as `aws_rds_cpu_utilization`, etc. When in doubt, grep the CSV.

## Tool note — use `rtk` for scans

The container ships `rtk` (https://github.com/rtk-ai/rtk), a CLI proxy that compresses `ls` / `read` / `grep` / `find` output to save tokens. Prefer `ls`, `cat`, `grep`, `find` over the bare commands when browsing this tree — the `references/` folder is big enough that raw `cat` / `ls -R` will eat context. `awk` / `sed` / `sort` / `jq` are not wrapped; keep them as-is.

## Generic investigation rule

Compare the **bad window** (incident) against a **good control window** (same weekday + hour, 7 days earlier) for every non-trivial metric. Metric value alone is noise; metric value vs control is signal.

## Covered technologies

**Databases / stores:** `postgres` · `mysql` · `cassandra` · `redis`

**Message brokers:** `kafka` · `rabbitmq` · `aws-sqs` · `gcp-pubsub` · `aws-eventbridge` · `aws-firehose`

**Web servers / proxies / mesh:** `nginx` · `apache` · `caddy` · `litespeed` · `haproxy` · `envoy` · `istio`

**Cloud infra:** `kubernetes` · `aws-ecs` · `aws-lambda` · `aws-rds` · `aws-docdb` · `aws-dynamodb` · `aws-elasticache` · `aws-efs` · `aws-api-gateway` · `aws-elb` · `aws-nat-gateway` · `aws-privatelink` · `gcp-storage`

**Runtime / platform:** `jvm` · `nvidia-gpu` · `openai` · `otel-collector` · `quickwit`

Not listed? Fall back to a generic sweep via `$incident-investigation`.

## Shell commands - finding the right tech + metrics

From the container shell (`${CLAUDE_PLUGIN_ROOT}/skills/knowledge-technology/` is `$TK` below):

```bash
TK=${CLAUDE_PLUGIN_ROOT}/skills/knowledge-technology/references

# Which techs are covered?
ls "$TK"

# Does this repo have a reference for <keyword>?
ls "$TK" | grep -i redis
grep -l -r -i "connection pool" "$TK"/*/README.md

# Show the queries file (fastest read)
cat "$TK/postgres/queries.md"

# List every tsuga_metric_name for a tech (exact strings for Tsuga queries)
awk -F, 'NR>1 {print $7}' "$TK/aws-rds/metrics.csv" | sort -u

# Filter metrics by theme (Availability/Health, Capacity/Saturation, Performance/Latency, Errors/Failures, Throughput/Usage)
awk -F, 'NR>1 && $1=="Capacity/Saturation" {print $7}' "$TK/postgres/metrics.csv"

# Look up a metric's definition + aggregation + group_by
awk -F, 'NR>1 && $2=="postgresql.backends" {print "def:"$4"\nagg:"$9"\npost:"$10"\ngroup_by:"$11}' "$TK/postgres/metrics.csv"

# Source-name → tsuga-name lookup (critical for AWS)
awk -F, 'NR>1 {print $2" → "$7}' "$TK/aws-rds/metrics.csv" | grep -i cpu

# Cross-tech: which techs have a metric matching a pattern?
grep -l -r "replication" "$TK"/*/metrics.csv | sed 's|.*/references/||;s|/metrics.csv||'

# Glossary / concept lookup inside a tech's README
grep -B1 -A3 -i "bloom filter" "$TK/cassandra/README.md"
```

## Shell commands - composing a Tsuga query

Once you have the exact `tsuga_metric_name`, compose via `$tsuga-cli`. Aggregation body uses `timeRange` + `dataSource` + `queries` (see `$tsuga-cli/SKILL.md` for the full schema). GNU `date -d` works on the container (Linux); avoid BSD-only flags like `-v-2H`.

```bash
METRIC=$(awk -F, 'NR>1 && $2=="FreeStorageSpace" {print $7; exit}' "$TK/aws-rds/metrics.csv")
echo "$METRIC"   # → aws_rds_free_storage_space

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

- **This skill** - *where to look, what to query, exact metric names*.
- **`$tsuga-cli`** - *how to drive the CLI* (aggregation body syntax, flags).
- **`$incident-investigation/references/playbooks/`** - *how to reason* (disambiguation traps).

## Anti-patterns

- Do not guess metric names. Always pull from `tsuga_metric_name` column of `metrics.csv`.
- Do not paste CloudWatch / OTel source names directly into `tsuga` - Tsuga registers them under different strings (see the CSV).
- Do not dump the whole catalog. Filter by theme or incident shape. Use `cat` / `grep` not `cat` / bare `grep` on the reference trees — otherwise a single file scan can blow 20k tokens.
- Metric missing ≠ value zero. Receiver scope / permission issues look like absence. Say so explicitly.
