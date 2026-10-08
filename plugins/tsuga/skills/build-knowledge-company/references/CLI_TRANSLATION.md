<!-- skill-lint: allow-forbidden-examples — this file documents the forbidden patterns as teaching examples -->

# CLI_TRANSLATION — turning MCP-tool shapes into real `tsuga` CLI

A subagent holding Tsuga MCP tools writes its dossier commands in the tool vocabulary
(`search-logs query='…' from=-1h to=now limit=50`) — plausible-looking, not runnable.

**The rule: every command block in every SERVICE_KNOWLEDGE.md must be directly runnable as a
`tsuga` CLI invocation.** No `rtk` prefix, no tool pseudo-syntax, no placeholder the reader has to
translate.

## Name translation

The CLI names a resource in the plural and the verb second: `tsuga <resource-plural> <verb>`.
`tsuga monitor get X` does not exist.

| MCP tool | `tsuga` CLI |
|---|---|
| `search-logs` | `tsuga logs search` |
| `search-spans` | `tsuga traces search` (the CLI verb is **traces**; `spans` is only the TQL data source) |
| `list-log-patterns` | `tsuga logs patterns` |
| `list-log-attributes` | `tsuga logs attributes` |
| `list-new-error-patterns` | `tsuga logs new-error-patterns` |
| `list-error-pattern-increases` | `tsuga logs error-pattern-increases` |
| `get-contrast-sets` | `tsuga traces contrast-sets` |
| `aggregate-scalar` | `tsuga aggregation scalar` |
| `aggregate-timeseries` | `tsuga aggregation timeseries` |
| `list-metrics` / `get-metric` | `tsuga metrics list` / `tsuga metrics get <name>` |
| `query-monitors` / `get-monitor` | `tsuga monitors list` / `tsuga monitors get <id>` |
| `query-dashboards` / `get-dashboard` | `tsuga dashboards list` / `tsuga dashboards get <id>` |
| `list-teams` / `get-team` | `tsuga teams list` / `tsuga teams get <id>` |
| `query-services` / `get-service` | `tsuga services list` / `tsuga services get <id>` |
| `list-log-routes` / `get-log-route` | `tsuga log-routes list` / `tsuga log-routes get <id>` |
| `list-notification-rules` | `tsuga notification-rules list` |
| `list-notification-silences` | `tsuga notification-silences list` |
| `list-clusters` | `tsuga clusters list` |
| `list-quality-reports` | `tsuga quality-reports list` |

Run `tsuga <command> --help` for the flags; nothing here restates them. Three translation traps
`--help` will not warn you about:

- A tool's `limit=` becomes `--max-results` on a telemetry search and `--limit` on a paginated
  resource list. Both flags exist, on different commands.
- `tsuga logs patterns` has no result cap at all — narrow it with `--query`, not a flag.
- `tsuga logs error-pattern-increases` filters by `--team` and `--env` only. There is no
  `--service`; `tsuga logs new-error-patterns` is the one that takes it.

## Aggregations need a body file

A compact tool call like `aggregate-scalar dataSource=logs aggregate=count filter="…" from=-1h`
has no one-liner CLI equivalent. It becomes a JSON body plus `-f`:

```bash
TO=$(date -u +%s); FROM=$((TO - 3600))
# or on Linux: FROM=$(date -u -d '1 hour ago' +%s); TO=$(date -u +%s)

cat > /tmp/q.json <<JSON
{
  "timeRange": {"from": $FROM, "to": $TO},
  "dataSource": "logs",
  "queries": [
    {"aggregate": {"type": "count"}, "filter": "context.service.name:X level:ERROR"}
  ]
}
JSON
tsuga aggregation scalar -f /tmp/q.json
```

`"timeRange"` takes Unix-seconds integers, which is why the `date` helper is here — a relative
string like `"-1h"` is rejected in the body even though `--from=-1h` is fine as a flag. Emit the
helper once per dossier, the first time an aggregation needs it.

On `"dataSource": "metrics"` every aggregate needs a `"field"`, `count` included — it counts
datapoints of that metric, and omitting the field returns
`count aggregate requires a non-empty field`. Swapping in `sum` to dodge the error answers a
different question.

For the rest of the body — where `groupBy`, `formula`, `aggregationWindow` and per-query
`functions` sit, and which aggregate a metric's type and temporality call for — start from
`tsuga aggregation scalar --generate-skeleton` and the `$tsuga-cli` skill. Two doc pages carry the
rest, both via `tsuga docs get <path>`: `visualize/guides/how-to-choose-a-metric-aggregation` for
which aggregate a metric type and temporality call for, and `explore/query-syntax` for query-value
units (`duration` is milliseconds). Do not restate either in a dossier.

## Quoting

- Double-quote a query containing a space or a TQL operator: `--query "context.service.name:X level:ERROR"`.
- Single-quote the outer shell when the query itself contains a phrase match:
  `--query 'context.service.name:X "Exact phrase"'`.

## No `rtk` prefix

The RTK hook rewrites commands at execution time, so `rtk tsuga logs search …` in a dossier buys
nothing and reads as broken to anyone without the hook. Emit plain `tsuga …`.

## The verification grep

`check-skill-health`'s `scripts/check-forbidden-tokens.sh <skill-dir>` is the authoritative check
and already knows the JSON-key and URL exclusions. Run it over the generated tree rather than
hand-rolling greps; `VERIFICATION.md` covers what it does not reach.
