<!-- skill-lint: allow-forbidden-examples — this file documents the forbidden patterns as teaching examples -->

# CLI_TRANSLATION — turning MCP-tool shapes into real `tsuga` CLI

The single most expensive bug in the first `knowledge-company` build was subagents emitting MCP-tool pseudo-syntax (`search-logs query='…' from=-1h to=now limit=50`) in the "Ready-to-run" sections. This looks plausible but is not runnable as a `tsuga` CLI invocation. Every subagent prompt must include the contract in this file.

## The rule

**Every command block in every SERVICE_KNOWLEDGE.md must be directly runnable as a `tsuga` CLI invocation.** No exceptions. No `rtk` prefix. No pseudo-syntax. No placeholder commands that require the reader to mentally translate.

## Translation table

### Logs / traces / metrics

| MCP-tool shape | Real `tsuga` CLI |
|---|---|
| `search-logs query="X" from=-1h to=now limit=20` | `tsuga logs search --query "X" --from -1h --to now --max-results 20` |
| `search-logs query='X' from=-1h` (no to/limit) | `tsuga logs search --query 'X' --from -1h` (`--to now` is default; default `--max-results` is 100) |
| `search-logs` (no args) | `tsuga logs search` |
| `search-spans query=…` | `tsuga traces search --query "…" --from … --to … --max-results …` (note: **traces**, not spans) |
| `list-metrics` | `tsuga metrics list` |
| `list-metrics` (intended to filter by prefix) | `tsuga metrics list \| jq '.[] \| select(.name \| startswith("prefix_"))'` |
| `get-metric name=X` | `tsuga metrics get X` |
| `list-log-patterns query="X" from=-1h` | `tsuga logs patterns --query "X" --from -1h` |
| `list-new-error-patterns --service X --from -24h` | `tsuga logs new-error-patterns --service X --from -24h` |
| `list-error-pattern-increases --team infra --from -24h` | `tsuga logs error-pattern-increases --team infra --from -24h` |

### Resource list / get

| MCP-tool shape | Real `tsuga` CLI |
|---|---|
| `list-monitors` | `tsuga monitors list` |
| `get-monitor id=X` | `tsuga monitors get X` |
| `list-dashboards` | `tsuga dashboards list` |
| `list-dashboards owners=A,B` | `tsuga dashboards list -d '{"filters":{"owners":{"values":["A","B"]}}}'` |
| `get-dashboard id=X` | `tsuga dashboards get X` |
| `list-routes` / `get-route id=X` | `tsuga routes list` / `tsuga routes get X` |
| `list-teams` / `get-team id=X` | `tsuga teams list` / `tsuga teams get X` |
| `list-services` / `get-service id=X` | `tsuga services list` / `tsuga services get X` |
| `list-notification-rules` | `tsuga notification-rules list` |
| `list-notification-silences` | `tsuga notification-silences list` |

**Always plural resource names.** `tsuga monitor get X` is wrong. The CLI pattern is `tsuga <resource-plural> <verb>`: `tsuga monitors get`, `tsuga dashboards list`, etc.

### Aggregations (scalar / timeseries)

MCP compact shapes like:

```
aggregate-scalar dataSource=logs aggregate=count filter="…" from=-1h to=now
aggregate-timeseries dataSource=metrics aggregationWindow=5m aggregate=sum field=foo filter="…" from=-1h to=now groupBy=context.cluster_id
```

have no one-liner equivalent in the CLI. They require a JSON body file. Translate to **heredoc + CLI invocation**:

```bash
FROM=$(date -u -v-1H +%s); TO=$(date -u +%s)   # macOS
# or on Linux: FROM=$(date -u -d '1 hour ago' +%s); TO=$(date -u +%s)

cat > /tmp/q.json <<JSON
{
  "timeRange": {"from": $FROM, "to": $TO},
  "dataSource": "logs",
  "queries": [
    {"aggregate": {"type": "count"}, "filter": "context.service.name:X level:ERROR"}
  ],
  "formula": "q1"
}
JSON
tsuga aggregation scalar -f /tmp/q.json
```

For timeseries, add `"aggregationWindow": "5m"` at body level:

```bash
cat > /tmp/q.json <<JSON
{
  "timeRange": {"from": $FROM, "to": $TO},
  "dataSource": "metrics",
  "queries": [
    {"aggregate": {"type": "percentile", "percentile": 95, "field": "my_metric"}, "filter": "context.env:prod"}
  ],
  "groupBy": [{"fields": ["context.cluster_id"], "limit": 10}],
  "formula": "q1",
  "aggregationWindow": "5m"
}
JSON
tsuga aggregation timeseries -f /tmp/q.json
```

## Body-structure rules for aggregations

These are easy to get wrong. A subagent that hasn't read this section will write malformed JSON that returns an error.

- `"timeRange"` requires **Unix seconds integers**, not relative strings like `"-1h"`. Use the `FROM=$(date -u ... +%s)` helper.
- `"dataSource"` is `"logs"`, `"traces"`, or `"metrics"`. Not `"spans"`.
- `"groupBy"` is at **body level**, not inside query items: `"groupBy": [{"fields": ["error.type"], "limit": 10}]`.
- `"functions"` (e.g., `rate`, `per-second`, `increase`) are **per-query**: `"functions": [{"type": "rate"}]`.
- `"formula"` is at body level and references queries by position: `"q1"` = first query, `"q2"` = second, etc.
- `"aggregationWindow"` is at body level, only for timeseries (e.g., `"5m"`, `"30m"`).
- Each query in `"queries"` has `"aggregate"` (object with `"type"`, and `"field"` for anything other than `count`) and `"filter"` (string). No `"id"` field.
- `count` is valid on `logs` / `traces` but **not on `metrics`** — use `sum` instead.
- Percentile: `{"type": "percentile", "percentile": 95, "field": "duration"}`. The percentile number goes on the aggregate object, not on the body.

## Counter-math cheat sheet

When aggregating a metric, picking `aggregate.type` + `functions` wrong produces meaningless values. Always check the metric's type + temporality first:

```bash
tsuga metrics get <metric-name>     # returns type + temporality + unit
```

| Metric type | Temporality | Aggregation | Function | Why |
|---|---|---|---|---|
| Gauge | — | `max` or `average` | none | Point-in-time values. |
| Counter | Delta | `sum` | `per-second` | Delta counters report per-interval increments. |
| Counter | Cumulative | `sum` | `rate` | Monotonically increasing; `rate` = per-second derivative. |
| Counter | Cumulative | `sum` | `increase` | Same as above but per-bucket totals. |
| Histogram | — | `percentile` (p50/p95/p99) | none | Pre-aggregated distributions. |

Common mistakes:
- `{"type": "average", "field": "http.server.request.count"}` on a delta counter averages deltas, meaningless.
- Charting a cumulative counter with no function produces an ever-increasing line (lifetime total).
- Applying `per-second` to a gauge double-derives a point-in-time value.

## Duration units

Trace span `duration` is in **milliseconds**. A TQL filter `duration:>10s` is wrong; it's `duration:>10000`. Same for any metric whose name suffix suggests a unit (`*_seconds`, `*_milliseconds`, `*_bytes`).

## Quoting rules

- Double-quote the query string if it contains a space or TQL operator: `--query "context.service.name:X level:ERROR"`.
- Use single quotes for the outer shell if the query contains double-quoted phrase match: `--query 'context.service.name:X "Exact phrase"'`.
- Don't mix: `--query "context.service.name:X \"phrase\""` works but is harder to read.

## Forbidden tokens — the verification grep

After writing any SERVICE_KNOWLEDGE.md, this must return zero hits:

```bash
grep -nE '^(search-logs|search-spans|list-metrics|get-metric|list-monitors|get-monitor|list-dashboards|get-dashboard|list-routes|list-teams|list-services|get-service|list-notification-rules|list-notification-silences|aggregate-scalar|aggregate-timeseries|list-log-patterns|list-new-error-patterns|list-error-pattern-increases)\b' <file>

grep -nE '\bquery=|\bfrom=-|\b to=now\b|\blimit=|\bfilter=|\baggregationWindow=|\bdataSource=' <file> \
  | grep -v '"aggregationWindow":' \
  | grep -v '"dataSource":' \
  | grep -v '"filter":' \
  | grep -v '/explorer?query='
```

Inside JSON heredocs, `"aggregationWindow":`, `"dataSource":`, and `"filter":` are valid and must be kept — the verification grep excludes those. `/explorer?query=` is a legitimate URL parameter, also excluded.

## Do NOT prefix with `rtk`

The RTK hook rewrites commands transparently at execution time. Writing `rtk tsuga logs search …` in a dossier is noise — human readers without the hook see a broken command. Always emit plain `tsuga …`.

If the dossier is for an agent that *does* have the hook, the hook handles it. If it's for a human user or an agent without the hook, `rtk` is wrong. Either way, don't include it.
