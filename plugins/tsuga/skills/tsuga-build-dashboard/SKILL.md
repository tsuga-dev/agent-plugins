---
name: tsuga-build-dashboard
description: "Designs, builds, validates and repairs Tsuga dashboards: picks widget types, verifies every query before embedding it, lays widgets out on the 12-column grid, and gates every mutation behind confirmation. Use when asked to create, update, delete or review a dashboard, add or fix a widget, correct a layout, build a monitoring view for a service, team, system, SLO, capacity, latency, throughput or error-rate question, or diagnose a widget that shows nothing. Also use to verify dashboard payloads, widget queries, graph schemas, normalizers, formulas, table grouping, time presets and layout rules. For ad-hoc querying without a dashboard, use tsuga-cli instead."
---

# Dashboard design and construction

Design, build, and validate a Tsuga dashboard.

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
- Owner team ID (required): resolve it from the teams list. Ask if ambiguous.
- Dashboard ID (required for updates): resolve it from the dashboards list.

## Documentation grounding

Two reference pages carry every field-level rule. Fetch them with `tsuga docs get`; do not reconstruct
their contents from memory, and do not guess a field name that neither page lists.

- `references/dashboards/widget-reference` — every widget type with worked JSON, the required and
  optional field list per type, the cross-cutting options (`groupBy`, `groupByMode`, `aliases`,
  `legendMode`, `customLink`, `yAxisSettings`), normalizers, formula patterns, `functions`, the
  connection and PromQL variants, and the per-type gotchas.
- `references/dashboards/layout-rules` — the 12-column grid, row tiling patterns, minimum widget
  size, section ordering, the section color rotation, widget naming, dashboard-level filters,
  folders, and `timePreset` values.

For product behaviour behind a field, use `tsuga docs search` then `tsuga docs get`, and cite `path`,
`title`, and `link`. `visualize/analytics/display-options`, `visualize/analytics/queries` and
`visualize/dashboards/index` are the pages the reference pages defer to.

## Design principles

1. **Lead with the big picture.** The top row should be 3-4 query-value widgets showing the most
   critical numbers at a glance: error count, request rate, p99 latency. A viewer should understand
   system health in under 3 seconds.
2. **Then show trends.** Below the KPIs, use timeseries charts to show how those numbers change over
   time. This is where problems become visible — spikes, drops, and shifts.
3. **Then enable drill-down.** Bottom rows should have top-lists (which endpoint has the most
   errors?) and log tables (what do those errors actually say?) so the viewer can investigate
   without leaving the dashboard.
4. **Color carries meaning, not decoration.** Put `conditions` on a `query-value` only where a real
   SLO or alert threshold exists. A tile that is always green teaches a viewer to ignore color.
5. **Every number needs a unit.** Set a `normalizer` on every numeric widget, and set it to the unit
   the raw value is already in.
6. **Group by meaningful dimensions.** `context.service.name` for multi-service views, `span.name`
   for operation breakdowns, `level` for severity splits. Avoid high-cardinality fields (user IDs,
   raw URLs).
7. **Keep it focused.** 6-12 widgets is ideal. One dashboard should answer one set of questions.
8. **Use section headers.** Full-width `note` widgets as dividers make the dashboard scannable.

Audience shapes density: on-call dashboards should be dense and operational, executive dashboards
sparse and trend-focused. Pick the default window to match — 1-2h for an incident board, 24h for
baseline health, 2d for adoption and customer trends.

## Workflow

### Step 1 — Clarify goal

Determine what service or system this is for, which questions it should answer (health, throughput,
latency, capacity), and whether the audience is on-call engineers, team leads, or executives.

Sketch the planned sections and widget types **before** running any command. Example:

```
Health:     3× query-value (error rate, p99, availability)
Throughput: 1× timeseries (request rate by endpoint)
Latency:    1× timeseries (p50/p95/p99), 1× top-list (slowest operations)
```

### Step 2 — Discover the signal

A widget reads one `source`: `logs`, `metrics` or `traces`. Pick it from the question before
discovering anything — "how many errors" is usually a log or span count, "how much memory" is a
metric. The `list` and `list-log-patterns` widgets are logs-only and `list-spans` is spans-only;
none of them takes a `source`.

For **metrics**: `tsuga metrics list` and `tsuga metrics get`. Both read a catalog that ignores the time range,
so a name appearing there means it was seen at some point, never that it reported in your window —
confirm with an aggregation count before building on it. **Never invent metric names.** Read the
returned names yourself rather than piping them through non-`tsuga` shell commands. For each
candidate record its `type` and `temporality` (they decide the aggregation in Step 3), its
`attributes` (filter and groupBy candidates), and its `unit` (the normalizer).

For **logs**: `tsuga logs attributes` names the attribute dot-paths observed in a range, but names
only — run `tsuga logs search` over the window to read real values. For **traces**: no catalog, so run
`tsuga traces search`. Either way a filter and a groupBy must name something that exists.

If no metric appears, widening the window will not help: verify the `context.service.name` spelling
with `tsuga services list` instead.

### Step 3 — Build and verify each widget query

On `metrics`, pick `aggregate.type` and `functions` from the metric's `type` and `temporality`. The
mapping is in `visualize/guides/how-to-choose-a-metric-aggregation`; fetch it rather than guessing
counter math from a metric's name. If values look absurd — huge, or monotonically increasing — the
combination is wrong. That mapping is metrics-only: on `logs` and `traces` there is no temporality
and `count` is the usual aggregate, taking no `field`.

The body shape, the filter syntax and the counter math all belong to `tsuga-cli`. Verify every body
and confirm it **returns data** before embedding: `tsuga aggregation timeseries` for time-bucketed widgets,
`tsuga aggregation scalar` for scalar and grouped ones. On a multi-cluster org scope the verification call
with the `--cluster <cluster-id>` flag, not a body field; the dashboard payload itself carries no
cluster. If a query returns nothing, fix it at the metric or filter level — never embed an
unverified body.

### Step 4 — Assemble the payload

Embed the verified queries into widget JSON, following the two reference pages above. Run
`tsuga dashboards create` (or `tsuga dashboards update`) with `--generate-skeleton` for the envelope, and read the
`api/createDashboard` / `api/updateDashboard` doc pages when a dashboard-level field is unclear.

### Step 5 — Confirm, then create or update

Summarize the planned change (widgets added, updated, removed) and wait for explicit user
confirmation before mutating. Pass payloads as files, not inline JSON. Then:

- Create → `tsuga dashboards create` with `-f dashboard.json`.
- Update → `tsuga dashboards get` first so you do not drop widgets, then `tsuga dashboards update` with
  `-f dashboard.json`.
- Delete → `tsuga dashboards delete`, behind the same confirmation gate.
- Verify with `tsuga dashboards get` afterwards.

The CLI exposes no single-widget update — `update-dashboard-graph` is not a command — so a
one-widget change goes through the whole-dashboard update above.

## Safety

- Never run `tsuga dashboards create`, `tsuga dashboards update` or `tsuga dashboards delete` without explicit user
  confirmation.
- Show the exact command and full payload before running it.
- One dashboard per confirmation — batch mutations are forbidden.

## Limitations

- Monitor firing state is not available: a dashboard cannot show whether an alert is firing, so
  never claim one is.
- There are no deployment markers, so never assert that a deploy caused a change you see.

## Evidence requirements

- Every metric name must come from `tsuga metrics list` — never invented.
- Every aggregation body must be verified with `tsuga aggregation scalar` or `tsuga aggregation timeseries`, and
  return data, before embedding.
- `owner` must be a team ID from `tsuga teams list` — never inferred from a name.

## Related skills

- `tsuga-cli` — counter math, filter syntax, and aggregation body shape
- `tsuga-investigate-service-health` — find the signals worth putting on the dashboard

## Anti-patterns

- Unsectioned chart dumps.
- KPI tiles without trend context.
- Raw counts without normalization.
- Inconsistent filters or dimensions across widgets.
- Duplicate chart names, or a window baked into a name (`Errors (1h)`).

## Ship checklist

- Mission stated in the title and the first note.
- Top row: summary SLIs as `query-value` widgets.
- Each domain has a colored header note.
- Every row tiles to exactly 12 columns.
- Units and normalizers are explicit.
- Dashboard filters are minimal and left unset.
- Top offenders and diagnostics included.
