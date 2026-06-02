---
name: tsuga-cli
description: "Use whenever the task involves a `tsuga` CLI command: searching logs/traces with TQL, composing `tsuga aggregation` bodies, picking the right aggregate type for a metric's temporality (gauge/delta/cumulative/histogram), managing clusters or any CRUD resource (monitors, dashboards, routes, teams, notification-rules, retention/tag policies, ingestion keys, …), or building deep links into `app.tsuga.com`. Also use for two specific lookups: service-ownership (`who owns X?`, `which team owns X?`, `what monitors/dashboards does X have?`) and reliability posture (`quality scores`, `observability posture`, `which teams have failing instrumentation?`) — both load a playbook from `references/playbooks/`. Produces shell commands, JSON bodies, and URLs."
---

# Tsuga CLI

Manage Tsuga resources and query telemetry data from the command line. All output is JSON.

## Setup

```bash
npm install -g @tsuga/cli
tsuga auth <token>         # saves to ~/.config/tsuga/config.json
tsuga config               # show API URL, masked key, config path, and defaults
```

Keep the CLI up to date (`npm install -g @tsuga/cli@latest`) — new resources ship regularly. If a command documented here is missing, update before debugging.

For auth and cluster, the lookup order is the same: **CLI flag > env var > saved config**.

- Auth: `--operation-api-key <token>` / `TSUGA_OPERATION_API_KEY`
- Cluster: `--cluster <id>` / `TSUGA_CLUSTER_ID`

## Clusters

Multi-cluster tenants must target a specific cluster (single-cluster tenants can ignore this — the backend picks the only one).

```bash
tsuga cluster list                              # show all clusters
tsuga config set default cluster <cluster-id>   # save as the default
tsuga config set default cluster ''             # clear it
```

## Resource Commands

All resources follow the same CRUD pattern:

```bash
tsuga <resource> list
tsuga <resource> get <id>
tsuga <resource> create [-f <file> | -d '<json>'] [--generate-skeleton]
tsuga <resource> update <id> [-f <file> | -d '<json>'] [--generate-skeleton]
tsuga <resource> delete <id>
```

Resources: `dashboards`, `monitors`, `teams`, `routes`, `notification-rules`, `notification-silences`, `ingestion-api-keys`, `retention-policies`, `tag-policies`, `investigations`, `quality-reports`, `cloud-resources`.

> Note: `ingestion-api-keys` does not support `get <id>`.
> Note: `quality-reports` and `cloud-resources` only support `list` (read-only).
> Note: `investigations` is **beta** — see [Investigations (beta)](#investigations-beta).

### Input methods

- `-f payload.json` — read body from file
- `-f -` — read body from stdin
- `-d '{"name":"foo"}'` — inline JSON
- `--generate-skeleton` — print a JSON template and exit (no API call)

### Resource-specific flags

- `tsuga dashboards list --owners <id1> <id2>` — filter by owner team IDs

### Examples

```bash
tsuga teams list
tsuga teams get qz9c-d08h8-0vfa
tsuga teams create -d '{"name":"platform","visibility":"public"}'
tsuga monitors create --generate-skeleton > monitor.json   # edit, then:
tsuga monitors create -f monitor.json
tsuga dashboards list --owners team-1 team-2
tsuga routes update abc-123 -d '{"name":"Updated route"}'
tsuga retention-policies delete abc-123
echo '{"name":"My Team"}' | tsuga teams create -f -
```

## Investigations (beta)

Store investigation / RCA write-ups in Tsuga, where they appear in the Investigations page and can link to other assets.

**Beta:** only use this if the operation API key has the `investigations` permission (403 otherwise), and expect the API to change.

```bash
tsuga investigations list
tsuga investigations create -d '{
  "name": "Checkout 5xx surge - RCA",
  "owner": "<team-id>",
  "env": "prod",
  "contentMd": "# Summary\n...",
  "linkedAssets": [{"type": "monitor", "id": "<monitor-id>"}]
}'
```

- `contentMd` is Markdown; headings, lists, and code blocks render in the UI.
- `linkedAssets[].type` is one of `dashboard`, `monitor`, `service`, `slo`, `log-route`.

## Quality Reports

```bash
tsuga quality-reports list              # get the latest quality report
tsuga quality-reports list | jq '.report.overallScore'
tsuga quality-reports list | jq '.report.teamResults[].teamName'
```

Key fields: `report.generatedAt`, `report.overallScore`, `report.teamResults[]{teamId, teamName, score, weightedScore, ruleResults[]}`. Generated at least once per 24h. Only supports `list`.

## Services

```bash
tsuga services list
tsuga services get <id>
```

Key fields: `id`, `serviceName`, `serviceNamespace` (optional), `teams[]`, `sources[]`, `env`,
`versions[]` (`{version, firstSeenAt, lastSeenAt, faulty?}`), `languages[]` (`{language, lastSeenAt}`),
`firstSeenAt`, `lastSeenAt`

Pre-computed 24h counters (extremely useful for quick triage):

- `logsCount24h` — total log volume in last 24h
- `errorLogsCount24h` — error log volume in last 24h
- `tracesCount24h` — total trace volume in last 24h
- `errorTracesCount24h` — error trace volume in last 24h

> 24h counters are rolling windows. State this when reporting them.

## Cloud Resources

Inventory of cloud resources (AWS/GCP/Azure) discovered by Tsuga inventory scans.

```bash
tsuga cloud-resources list
tsuga cloud-resources list | jq 'length'
tsuga cloud-resources list | jq '.[] | select(.cloudPlatform=="aws" and .resourceType=="bucket")'
tsuga cloud-resources list | jq 'group_by(.cloudPlatform) | map({platform: .[0].cloudPlatform, count: length})'
```

Read-only — only supports `list`. Each item has: `id`, `cloudPlatform` (`aws` / `gcp` / `azure`), `cloudAccount`, `cloudRegion`, `fullyQualifiedResourceId` (cloud-native ARN/URN), `displayName`, `nativeResourceType` (e.g. `aws_s3_bucket`, `gcp_compute_instance`), `resourceCreatedAt`, `resourceUpdatedAt`, `resourceLastSeenAt`, `tags[]`, plus a discriminated `category` + `resourceType` + `attributes` (e.g. `data.bucket.versioningStatus`, `compute.virtualMachine.instanceType`).

Operation API key permission required: `inventory: read` (labelled "Cloud resources" in the UI).

## Service Graph

Derives a service dependency graph from trace spans in the given window — which services called which, and how many times.

```bash
tsuga service-graph get <serviceId>                         # last 30m, all traces
tsuga service-graph get <serviceId> --from -24h             # wider window
tsuga service-graph get <serviceId> --query "span_name:GET" # filter source spans
```

Flags: `--from` (`-30m`), `--to` (`now`), `--query` (`*`). Pass a **service id** (not a service name) — grab it from `tsuga services list`.

Output: `{"nodes": [{"serviceName": ...}], "edges": [{"from": <svc>, "to": <svc>, "count": N}]}`. `count` is the number of parent→child span transitions observed in the window — useful for spotting unexpected callers, orphaned downstreams, or traffic shifts after a deploy.

> Empty graph usually means the service has no traces in the window, not that it has no dependencies. Widen `--from` before concluding isolation.

## Filter Syntax (TQL)

Applies to all `--query` flags and aggregation `filter` fields.

| Syntax           | Meaning                  | Example                                                |
| ---------------- | ------------------------ | ------------------------------------------------------ |
| `field:value`    | Exact match              | `level:ERROR`                                          |
| `term1 term2`    | AND (default)            | `level:ERROR context.service.name:api`                 |
| `term1 OR term2` | OR (must be uppercase)   | `level:ERROR OR level:WARN`                            |
| `NOT term`       | Negation (uppercase)     | `NOT context.env:staging`                              |
| `(...)`          | Grouping                 | `(level:ERROR OR level:WARN) context.service.name:api` |
| `field:(a OR b)` | Field-level OR           | `context.service.name:(web-backend OR api-gateway)`    |
| `field:*`        | Field exists             | `trace_id:*`                                           |
| `_exists_:field` | Field exists (alternate) | `_exists_:trace_id`                                    |
| `field:[A TO B]` | Range, inclusive         | `duration:[100 TO 500]`                                |
| `field:{A TO B}` | Range, exclusive         | `duration:{100 TO 500}`                                |
| `field:>N`       | Numeric comparison       | `duration:>100`                                        |

AND is the default (space-separated terms); OR binds looser than AND. `OR` and `NOT` must be uppercase — lowercase `or`/`not` are treated as literal search terms.

## Shared Attributes (Cross-Signal)

- **`context.team`** — mandatory on all data (logs, metrics, traces)
- **`context.env`** — mandatory on all data
- **`context.service.name`** — available on logs and traces; use for service-scoped queries: `context.service.name:web-backend`
- **`trace_id` + `span_id`** — present on logs only when the log was emitted during a traced request; enables cross-signal correlation

Trace span `duration` values are in **milliseconds**.

## Logs

**Always filter.** A bare `tsuga logs search` returns the last 30m of _all_ logs across every service — useless noise. Every invocation must include at minimum `--query` (a TQL filter scoping to a service / team / level / pod / cluster) AND a sensible `--from`. If you don't know what to filter on, ask or run `tsuga services list` first.

```bash
# Search — always with --query
tsuga logs search --query "context.service.name:web-backend AND level:ERROR" --from -1h
tsuga logs search --query "level:ERROR" --max-results 50 -o tsv
tsuga logs search --query "context.k8s.pod.name:foo-*" -o csv \
  --fields timestamp,level,message,context.k8s.pod.name

# Cluster a result set by structural pattern (cuts thousands of lines to N templates)
tsuga logs patterns --query "level:ERROR AND context.team:infra" --from -1h

# Specialized anomaly endpoints (use these instead of search when applicable)
tsuga logs new-error-patterns       --team platform --env prod --from -24h
tsuga logs error-pattern-increases  --team infra    --env prod --from -24h
```

Flags: `--query` (`*`), `--from` (`-30m`), `--to` (`now`), `--max-results` (`100`), `--fields a,b,c.d` (project dot-paths), `-o, --output json|tsv|csv` (default `json`). TSV/CSV default to `timestamp,level,message`; `--fields` overrides.

Output: `logs search` → `{"logs": [...]}` (or rows); `logs patterns` → `{"patterns": [{pattern, size, groups}], "sampleSize": N}` — `pattern` is the formatted string (e.g. `"Resolved segment SegmentId([0:1]) from cache"`); supports `-o tsv|csv` with default columns `count,ratio,team,level,pattern`; `logs new-error-patterns` → patterns first seen in the window (scoped by `--team`/`--env`/`--service`); `logs error-pattern-increases` → `{errorPatternIncreases: [{team, env, pattern, increaseTimestamps}]}` (anomalous-volume increases; `--team` required).

## Traces

```bash
tsuga traces search                                         # last 30m
tsuga traces search --query "span_name:GET" --from -1h
tsuga traces search --max-results 50
```

Flags: same as logs.

## Metrics

```bash
tsuga metrics list                          # list all metrics (last 30m)
tsuga metrics list --from -1h               # custom time range
tsuga metrics get <metric-name>             # get metadata for a specific metric
```

## Aggregations

Scalar (single value) and timeseries queries use JSON body input:

```bash
tsuga aggregation scalar -f query.json
tsuga aggregation timeseries -f query.json
tsuga aggregation scalar --generate-skeleton > query.json   # get a template
```

Aggregate types: `count`, `unique-count`, `average`, `max`, `min`, `sum`, `percentile`.
Data sources: `logs`, `metrics`, `traces`.
Timeseries adds `"aggregationWindow"` (e.g. `"5m"`) at body level.

Functions (optional per query, max 10): `per-second`, `per-minute`, `per-hour`, `rate`, `increase`,
`rolling` (+ `window`), `log` (+ `base`), `power` (+ `exponent`), `sqrt`

Example — per-second rate of a counter:
`{"aggregate": {"type": "sum", "field": "my.counter"}, "functions": [{"type": "per-second"}]}`

**Correct body format:**

```json
{
  "timeRange": {"from": 1774007100, "to": 1774010700},
  "dataSource": "logs",
  "queries": [
    {"aggregate": {"type": "count"}, "filter": "context.service.name:web-backend level:ERROR"}
  ],
  "groupBy": [{"fields": ["span.name"], "limit": 10}],
  "formula": "q1"
}
```

- `timeRange` uses **Unix seconds** (not relative strings like `"-1h"`)
- `dataSource` and `formula` are **body-level** fields; query items do not have `id` or `dataSource`
- `formula` references queries by position: `"q1"` = first query, `"q2"` = second, etc.
- `groupBy` is at **body level** (not inside query items): `[{"fields": ["field.name"], "limit": N}]`
- `count` is the only aggregate that does not require `"field"` (and is not valid on `metrics` dataSource — use `sum` instead). All others (`sum`, `average`, `max`, `min`, `percentile`, `unique-count`) require `"field"`: `{"type": "percentile", "percentile": 95, "field": "duration"}`, `{"type": "sum", "field": "my.counter"}`
- Timeseries example (p95 latency by operation):

```json
{
  "timeRange": {"from": 1774007100, "to": 1774010700},
  "dataSource": "traces",
  "queries": [
    {
      "aggregate": {"type": "percentile", "percentile": 95, "field": "duration"},
      "filter": "context.service.name:web-backend"
    }
  ],
  "groupBy": [{"fields": ["span.name"], "limit": 10}],
  "formula": "q1",
  "aggregationWindow": "5m"
}
```

**Scalar output:** `{"results": [{"id": "q1", "group": {}, "value": N}]}`
**Timeseries output:** `{"series": [{"id": "q1", "group": {}, "points": [{"timestamp": <ms>, "value": <float>}]}]}`

## Counter Math — picking `aggregate.type` + `functions`

Check `tsuga metrics get <name>` for `type` + `temporality` first; picking wrong produces meaningless values.

| Metric              | Aggregation                               | Function                                    |
| ------------------- | ----------------------------------------- | ------------------------------------------- |
| Gauge               | `max` (saturation) / `average` (baseline) | none                                        |
| Counter, delta      | `sum`                                     | `per-second`                                |
| Counter, cumulative | `sum`                                     | `rate` (per-sec) or `increase` (per-bucket) |
| Histogram           | `percentile` (+ `field` + `percentile`)   | none                                        |

`average` on a counter, no function on a cumulative counter, or `per-second` on a gauge all produce garbage. Custom pipelines may have non-standard temporality — when in doubt, `$knowledge-technology/<tech>/metrics.csv` (`type` + `post_function` columns) is authoritative.

## Safety

- Before running any filter you're constructing, check it doesn't contain field names that look like secrets (`password`, `token`, `api_key`, `secret`). If it does, drop the field; never echo secret material into a tsuga query.
- `tsuga` reads/writes Tsuga state. `delete`, `update`, and `create` mutate. Only invoke mutating commands with explicit user authorization.

## Rationale

Every API-calling command accepts an optional `--rationale <text>` to explain why the call was made. It does not change the result.

```bash
tsuga logs patterns --rationale "exploring telemetry to investigate prod outage"
```

Use it on agent-issued calls so the activity log explains intent.

## Feedback

Report friction with Tsuga tooling or APIs (a failing command, unusable output, confusing behavior):

```bash
tsuga feedback "the traces command keeps timing out on large services"
```

## Defaults

```bash
tsuga config                              # show builtin + custom defaults (* = custom)
tsuga config set default from -1h         # override default lookback
tsuga config set default max-results 50   # override default result count
tsuga config set default cluster <id>     # pin the default cluster (see Clusters section)
tsuga config reset defaults               # clear all custom defaults
tsuga config set default <key> ''         # clear a single default
```

Priority: CLI flag > custom default > built-in default.
Built-ins: `from: -30m`, `to: now`, `query: *`, `max-results: 100`. `cluster` has no built-in default (backend picks first if unset).

Dash-prefixed values are accepted as-is (`tsuga config set default from -45m` works without a `--` separator).

## Time Formats

All time flags (`--from`, `--to`) accept:

- Relative: `-30m`, `-1h`, `-7d`, `-30s` (seconds, minutes, hours, days)
- `now` — current time
- Unix seconds: `1704067200`
- ISO 8601: `2024-01-01T00:00:00Z`

## Common Patterns

```bash
# Pipe to jq
tsuga dashboards list | jq '.[].name'
tsuga monitors list | jq '.[] | select(.priority == 1)'
tsuga logs search --query "level:ERROR" | jq '.logs[].message'

# Generate skeleton, edit, create
tsuga monitors create --generate-skeleton > monitor.json
# ... edit monitor.json ...
tsuga monitors create -f monitor.json

# Stdin piping
echo '{"name":"test","visibility":"public"}' | tsuga teams create -f -
```

## App Deep Links

When a CLI result (monitor id, dashboard id, trace id, metric name, …) needs to be handed back as a clickable URL into `https://app.tsuga.com`, read `references/app-deep-links.md` for the full page catalog, search-param shapes, time-range / modal encoding, and worked examples.

## Cloud / Kubernetes CLI Translators

When the user is reaching for `kubectl`, `aws`, `gcloud`, or `az` and the question is read-only (logs, events, object spec, metrics, queue depth, CPU, etc.), check if Tsuga already has the data:

- `references/kubectl-translator.md` — `kubectl get` / `describe` / `logs` / `top` → `tsuga` mapping. Object snapshots (`k8s.resource.name:<kind>`), event records (`event.domain:k8s`), `k8s.*` native metrics.
- `references/aws-translator.md` — `aws sqs` / `aws cloudwatch get-metric-statistics` / ALB / RDS / Lambda / EBS / S3 / Firehose / NAT / Kinesis / EKS etc. → `tsuga aggregation`. Requires a CloudWatch metric stream feeding Tsuga; spec / `describe-*` is not ingested.
- `references/gcp-translator.md` — `gcloud sql` / `gcloud pubsub` / GCS / Compute / Cloud Run / GKE → `tsuga aggregation`. Native metric form `<service>.googleapis.com/<path>`.
- `references/azure-translator.md` — `az vm` / ServiceBus / Storage / AKS → `tsuga aggregation`. Aggregate suffix encoded in the metric name (`azure_<metric>_{maximum,average,total,…}`).

Load only the translator(s) relevant to the request; they overlap in scope but the gotchas differ per cloud.

## Lookup Playbooks

Two structured lookups live under `references/playbooks/`. Load the matching one when the intent fits; the heavier service-triage workflows are handled by their own skills (see Related, below).

| Trigger intent                                            | Playbook                                         |
| --------------------------------------------------------- | ------------------------------------------------ |
| "Who owns X?" / "What dashboards/monitors does X have?"   | `references/playbooks/find-owner-and-context.md` |
| "Reliability overview" / "quality scores" / failing rules | `references/playbooks/reliability-review.md`     |

## Troubleshooting

- Auth error? Check `tsuga config` or re-run `tsuga auth <key>`
- Empty results? Widen time window with `--from` / `--to`
- Version? `tsuga --version`
- Uninstall: `npm uninstall -g @tsuga/cli`

## Related

- `tsuga-investigate-service-health` — multi-signal first-response triage for a named service ("is X healthy?", "what's wrong with X?")
- `tsuga-investigate-errors` — error pattern deep-dive when errors are spiking
- `tsuga-analyze-trace-latency` — p95 / latency-spike investigation
- `tsuga-audit-monitor-coverage` — alerting gap audit across services/teams
- `$knowledge-technology/<tech>/metrics.csv` — authoritative `tsuga_metric_name` + units + aggregation hints per tech. Grep it for the exact metric string before composing an aggregation.
- `$incident-investigation` — if you're composing a query as part of an incident investigation, follow the orchestrator's workflow; it anchors the query choice to the monitor that fired.
