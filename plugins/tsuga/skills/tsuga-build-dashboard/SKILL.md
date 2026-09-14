---
name: tsuga-build-dashboard
description: "Use when asked to create, update, validate, delete, or review a Tsuga dashboard; add or fix widgets; correct layout; build a monitoring view for a service, team, system, SLO, capacity, latency, throughput, or error-rate question; verify dashboard payloads, widget queries, graph schemas, normalizers, formulas, table grouping, time presets, or layout rules."
---

# Dashboard design and construction

Design, build, and validate a Tsuga dashboard: design principles, widget choice, layout rules, and
the graph configuration schema.

## Example requests

- "Create a dashboard for service X"
- "Add a widget to this dashboard"
- "Fix the layout of this dashboard"
- "Build a monitoring view for [team / service / system]"
- "Update the error-rate widget to use the correct metric"
- "Why does this widget show nothing?"

## Required inputs

- What to monitor (required): the service, system, or questions the dashboard should answer. Ask if
  missing.
- Owner team ID (required): resolve with `tsuga teams list`. Ask if ambiguous.
- Dashboard ID (required for updates): resolve with `tsuga dashboards list`.

## Documentation grounding

Use `tsuga docs search`, then `tsuga docs get`, for product/API details. Cite `path`, `title`, and `link`
when docs were used. This skill owns the call shapes, safety rules, and workflow gates.

## Design principles

1. **Lead with the big picture.** The top row should be 3-4 query-value widgets showing the most
   critical numbers at a glance: error count, request rate, p99 latency. A viewer should understand
   system health in under 3 seconds.
2. **Then show trends.** Below the KPIs, use timeseries charts to show how those numbers change over
   time. This is where problems become visible - spikes, drops, and shifts.
3. **Then enable drill-down.** Bottom rows should have top-lists (which endpoint has the most
   errors?) and log tables (what do those errors actually say?) so the viewer can investigate
   without leaving the dashboard.
4. **Use color conditions aggressively.** A query-value widget without conditions is just a number.
   Add alert (red) and warning (yellow) thresholds so problems are immediately visible. Always set
   `"backgroundMode": "background"` for conditions to render.
5. **Every number needs a unit.** Always set a normalizer - `{"type": "duration", "unit": "ms"}` for
   latency, `{"type": "custom", "unit": "req/s"}` for rates, `{"type": "percent"}` for ratios. A
   number without context is meaningless.
6. **Group by meaningful dimensions.** Use `context.service.name` for multi-service views,
   `span.name` for operation breakdowns, `level` for severity splits. Avoid high-cardinality fields
   (user IDs, raw URLs).
7. **Keep it focused.** 6-12 widgets is ideal. One dashboard should answer one set of questions.
   Don't cram everything into a single view.
8. **Use section headers.** Note widgets as full-width dividers make the dashboard scannable.
   Color-code them to visually separate sections.

Audience shapes density: on-call dashboards should be dense and operational, executive dashboards
sparse and trend-focused.

## Section patterns

Standard order for service dashboards:

1. **Health** - error rate, availability KPIs (note color: `blue.200`)
2. **Throughput** - request rate, event volume (note color: `emerald.200`)
3. **Latency** - p50/p95/p99 by operation (note color: `amber.200`)
4. **Errors** - error breakdown, recent error logs (note color: `red.200`)

Not every dashboard needs all four - include only what the audience needs.

## Workflow

### Step 1 - Clarify goal

Determine:

- What service or system is this for?
- What questions should the dashboard answer? (health, throughput, latency, capacity)
- Audience: on-call engineers, team leads, or executives?

Sketch the planned sections and widget types **before** running any command. Example:

```
Health:     3× query-value (error rate, p99, availability)
Throughput: 1× timeseries (request rate by endpoint)
Latency:    1× timeseries (p50/p95/p99), 1× top-list (slowest operations)
```

### Step 2 - Discover metrics

Use `tsuga metrics list` and `tsuga metrics get` over the window. **Never invent metric names.** Read the
returned names yourself rather than piping them through non-`tsuga` shell commands.

For each candidate metric, record:

- `type` and `temporality` - needed for the metric aggregation choice in Step 3
- `attributes` - filter and groupBy candidates
- `unit` - normalizer hint for Step 4

If no metrics appear: widen the window, or verify `context.service.name` spelling with
`tsuga services list`.

### Step 3 - Build and verify each widget query

Pick `aggregate.type` and `functions` from the metric's `type` and `temporality` captured in Step 2.
A skill is read on its own, so the rules are repeated here rather than pointing at a sibling:

| Metric    | Temporality | Aggregation                                | Function                                    |
| --------- | ----------- | ------------------------------------------ | ------------------------------------------- |
| Gauge     | -           | `max` (saturation) or `average` (baseline) | none                                        |
| Counter   | Delta       | `sum`                                      | `per-second`                                |
| Counter   | Cumulative  | `sum`                                      | `rate` (per-sec) or `increase` (per-bucket) |
| Histogram | -           | `percentile` (+ `field` + `percentile`)    | none                                        |

Never average a counter, never apply a rate function to a gauge, and never pick counter math from
the metric name alone. If values look absurd (huge, or monotonically increasing), the combination is
wrong.

Compose the body with a body-level `timeRange` in unix seconds, `dataSource`, and `groupBy`, plus a
per-query `aggregate`, `filter`, and optional `functions`. `formula` defaults to `q1`, so omit a
bare `q1`. Verify it and confirm it returns data **before** embedding: `tsuga aggregation timeseries` for
time-bucketed widgets, `tsuga aggregation scalar` for scalar and grouped ones. On a multi-cluster org scope
the verification call with the `--cluster <cluster-id>` flag, not a body field; the dashboard
payload itself carries no cluster. Never embed an unverified body; if a query returns nothing, fix
it at the metric or filter level first.

### Step 4 - Assemble the dashboard payload

Embed the verified queries into widget JSON, following the widget and layout rules below. For the
payload shape use `tsuga dashboards create --generate-skeleton` (or
`tsuga dashboards update <id> --generate-skeleton`), and fetch `tsuga docs get` for
`api/createDashboard`, `api/updateDashboard`, `references/dashboards/widget-reference`, or
`references/dashboards/layout-rules` only when field semantics or grid composition are unclear.

### Step 5 - Confirm, then create or update

Summarize the planned change (widgets being added, updated, or removed) and wait for explicit user
confirmation before mutating. Pass payloads as files rather than inline JSON. Then:

- Create → `tsuga dashboards create` with `-f dashboard.json`.
- Update the dashboard as a whole → `tsuga dashboards get` first to avoid dropping widgets, then
  `tsuga dashboards update` with `-f dashboard.json`.
- Delete → `tsuga dashboards delete`, behind the same confirmation gate.
- Verify with `tsuga dashboards get` afterwards.

There is no single-widget update in the CLI: `update-dashboard-graph` is not exposed as a command,
so a one-widget change still goes through the whole-dashboard update above.

## Evidence requirements

- Every metric name must come from `tsuga metrics list` - never invented.
- Every aggregation body must be verified with `tsuga aggregation scalar` or `tsuga aggregation timeseries`, and
  return data, before embedding.
- `owner` must be a team ID from `tsuga teams list` - never inferred from a name.

## Choosing the right widget

The value below is `visualization.type`. Aggregation widgets take `source` + a `queries` array;
`note` and the list-style widgets do not.

| Type                | Use for                                                                                        | groupBy?                 |
| ------------------- | ---------------------------------------------------------------------------------------------- | ------------------------ |
| `timeseries`        | Trends, rates, latency over time                                                               | yes (max 7)              |
| `query-value`       | Single-number KPI                                                                              | no (silently dropped)    |
| `gauge`             | Single value against a known `max` (budget, utilization, SLO); set `max` and `colorThresholds` | no                       |
| `top-list`          | "Who is highest?" ranked triage                                                                | yes                      |
| `bar`               | Bounded-category comparison (methods, status codes)                                            | yes                      |
| `pie`               | Part-to-whole, ≤6 slices                                                                       | yes                      |
| `distribution`      | Spread/tail of a numeric `field` (latency, sizes); `percentileMarkers` are ints 0-100          | no                       |
| `heatmap`           | Density/intensity over time; `palette` sets the gradient                                       | no                       |
| `table`             | Per-entity scorecard; `source`/`queries` live PER COLUMN, not at the root                      | yes (multi-level, max 3) |
| `list`              | Raw log rows; takes a single `query` string, `source` must be `logs`                           | n/a                      |
| `list-log-patterns` | Clustered log patterns; single `query` string, logs-only                                       | n/a                      |
| `note`              | Section headers / context; markdown `note`, all fields optional                                | n/a                      |

Each aggregation widget also has a `*-connection` twin (`timeseries-connection`,
`top-list-connection`, `pie-connection`, `bar-connection`, `query-value-connection`,
`list-connection`) that runs read-only SQL via `connectionId` instead of a Tsuga `source` +
aggregation.

Visualization guidance:

- `query-value`: only for true SLO/KPI thresholds. `gauge`: a KPI against a known ceiling.
- `timeseries`: trends, incidents, correlations. `distribution`/`heatmap`: shape and density.
- `top-list`: triage (worst routes, biggest orgs, top queries). `table`: per-entity scorecards.
- `bar`/`pie`: discrete category comparisons (pie ≤6 slices).
- `note`: full-width `h:1` colored section headers.
- No legend if only one series.
- Use P99 for latencies/durations (never avg/max).

## Structural rules

- `owner` must be a team ID - resolve with `tsuga teams list`.
- Each graph requires a unique `id`, a `visualization` object, and a `layout` object.
- `query-value` does not support `groupBy` - the API silently drops it.
- Name each series in the legend via `visualization.aliases.queries`, keyed by the query's
  zero-based index as a string (`"0"`, `"1"`, ...), NOT `formula`'s `"q1"` / `"q2"`. Wrong keys are
  silently ignored (see `references/dashboards/widget-reference`).
- A `percent` normalizer only appends `%`; it does not multiply by 100. Scale in the `formula`
  (`q1/q2*100`) and put `query-value` `conditions` thresholds on the resulting 0-100 scale.
- List-style widget variants take a single `query` string: `list` (logs matching a Tsuga query),
  `list-log-patterns` (logs clustered into patterns), or `list-connection` (datastore rows via
  `connectionId` + read-only SQL).
- Never send an empty `name` or `description` (`""`) - the API rejects it (400, "must NOT have fewer
  than 1 characters"). Omit the key entirely when a widget has no label.
- Every numeric widget should set a `normalizer` so values render with units.
- Set `timePreset` (e.g. `past-1-hour`, `past-24-hours`, `past-7-days`) for the default window, or
  omit to let the user choose. Name widgets by what they show, never by the window (`Error rate`,
  not `Errors (1h)`).
- Formulas support arithmetic only (`q1 + q2`, `(q1 / (q1 + q2)) * 100`) - no `max()`, no `if()`.
- Always include dashboard-level env + team filters:

```json
"filters": [
  {"key": "context.env", "values": []},
  {"key": "context.team", "values": []}
]
```

Dashboard-level filters use that object form, not TQL strings. Keep them minimal (1-2 max) and
aligned to ownership dimensions (org, env, service), with consistent field names.

## Layout grid

12-column grid with consistent tile sizing. Every row must tile to exactly 12 columns.

Layout object: `{"x": 0, "y": 0, "w": 6, "h": 4}`

Row patterns:

- **3 KPIs:** w=4 each, x=0/4/8, h=2
- **4 KPIs:** w=3 each, x=0/3/6/9, h=2
- **1 full-width chart:** w=12, h=4
- **2 side-by-side charts:** w=6 each, x=0/6, h=4
- **Section header (note):** w=12, h=1

Within each section, put summary and ranking widgets on the left and trends on the right, and use
full-width colored note headers to separate domains.

## Visualization object by type

Each snippet below is the `visualization` object of one graph (`{id, visualization, layout}`).

### query-value

```json
{
  "type": "query-value",
  "source": "logs",
  "queries": [{"aggregate": {"type": "count"}, "filter": "level:ERROR"}],
  "backgroundMode": "background",
  "normalizer": {"type": "custom", "unit": "errors"},
  "conditions": [{"operator": "greater_than", "value": 100, "color": "alert"}]
}
```

Operators: `greater_than`, `less_than`, `equal`, `not_equal`, `greater_than_or_equal`,
`less_than_or_equal`. Colors: `alert`, `warning`, `success`. Use `success`/`warning`/`alert` plus
`backgroundMode` only for thresholded SLO tiles - color carries meaning, not decoration.

### gauge

```json
{
  "type": "gauge",
  "source": "metrics",
  "queries": [
    {
      "aggregate": {"type": "average", "field": "system.cpu.utilization"},
      "filter": "context.service.name:my-service"
    }
  ],
  "max": 100,
  "colorThresholds": [
    {"from": 0, "color": "green"},
    {"from": 70, "color": "yellow"},
    {"from": 90, "color": "red"}
  ],
  "normalizer": {"type": "percent"}
}
```

Each colorThreshold band runs from its `from` value up to the next band (or `max`). Single value
only - no groupBy.

### timeseries

```json
{
  "type": "timeseries",
  "source": "logs",
  "queries": [{"aggregate": {"type": "count"}, "filter": "context.service.name:my-service"}],
  "groupBy": [{"fields": ["context.service.name"], "limit": 10}],
  "normalizer": {"type": "custom", "unit": "req"},
  "thresholds": [{"value": 100, "level": "alert"}]
}
```

### top-list / bar / pie

Same query structure as timeseries. Requires `groupBy`. Pie: keep limit ≤6.

### list (logs only)

```json
{
  "type": "list",
  "source": "logs",
  "query": "level:ERROR context.service.name:my-service",
  "listColumns": [{"attribute": "message"}, {"attribute": "trace_id"}]
}
```

Uses `query` (string), NOT `queries` (array).

### note

```json
{"type": "note", "note": "## Health", "noteColor": "blue.200"}
```

Colors: `white`, `gray.100`, `blue.200`, `red.200`, `emerald.200`, `amber.200`, `lime.200`,
`cyan.200`, `violet.200`, `fuchsia.200`, `pink.200`.

## Normalizers

| Type     | JSON                                  | Use for                                                                                    |
| -------- | ------------------------------------- | ------------------------------------------------------------------------------------------ |
| Duration | `{"type": "duration", "unit": "ms"}`  | Latency (ns, us, ms, s, m, h, days)                                                        |
| Data     | `{"type": "data", "unit": "MB"}`      | Memory, payload size (B, KB, MB, GB, TB, PB)                                               |
| Percent  | `{"type": "percent"}`                 | Ratios, utilization                                                                        |
| Custom   | `{"type": "custom", "unit": "req/s"}` | Everything else                                                                            |
| None     | `{"type": "none"}`                    | Raw values with no unit; also prevents the UI from re-deriving a unit from metric metadata |

For `data` and `duration`, `unit` is the unit the raw value is **already** in (the UI auto-scales
up). OTel byte metrics emit bytes, so use `"B"`; setting `"GB"` on a bytes value overstates it by
1e9.

## Formula patterns

Formulas reference queries by position (`q1` = first, `q2` = second).

| Pattern       | Formula                  | Normalizer            |
| ------------- | ------------------------ | --------------------- |
| Error ratio % | `(q1 / (q1 + q2)) * 100` | `{"type": "percent"}` |
| Utilization % | `(q1 / q2) * 100`        | `{"type": "percent"}` |

## Time ranges

1-2h for active incidents, 24h for baseline health, 2d for adoption and customer trends.

## Anti-patterns

- Unsectioned chart dumps.
- KPI tiles without trend context.
- Raw counts without normalization.
- Inconsistent filters or dimensions across widgets.
- Duplicate chart names.

## Ship checklist

- Mission stated in title + first note.
- Top row: summary SLIs (`query-value`).
- Each domain has a colored header note.
- 12-col grid alignment is consistent.
- Units and normalizers are explicit.
- Minimal filters.
- Top offenders and diagnostics included.

## Related skills

- `tsuga-cli` - counter math, filter syntax, and aggregation body shape
- `tsuga-investigate-service-health` - find the signals worth putting on the dashboard
