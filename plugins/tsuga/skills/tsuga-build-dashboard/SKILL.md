---
name: tsuga-build-dashboard
description: "Use when asked to create a Tsuga dashboard, add or fix widgets, correct a layout, or build a monitoring view for a service or team."
---

# Tsuga Build Dashboard

Build, modify, and validate Tsuga dashboards from the command line. This skill leans on `tsuga-cli` (docs lookup, filter syntax, counter math, aggregation body construction, metric discovery, CRUD commands). This skill owns dashboard JSON schema, layout, verification, and create/update workflow.

## When to Trigger

- "Create a dashboard for service X"
- "Add a widget to this dashboard"
- "Fix the layout of this dashboard"
- "Build a monitoring view for [team / service / system]"
- "Update the error rate widget to use the correct metric"

## Inputs

- **What to monitor** (required): the service, system, or questions the dashboard should answer. Ask if missing.
- **Owner team ID** (required): resolve with `tsuga teams list`. Ask if ambiguous.
- **Dashboard ID** (required for updates): resolve with `tsuga dashboards list`.

## Workflow

### Step 1 — Clarify goal

Documentation queries for graph types, display options, dashboard workflow, and template behavior:

```bash
tsuga docs get visualize/analytics/graph-types-and-widget-options
tsuga docs get visualize/analytics/queries
tsuga docs get visualize/dashboards/index
```

Documentation queries for connection-backed widgets, scheduled reports, and dashboard templates:

```bash
tsuga docs get visualize/analytics/connection-backed-graphs
tsuga docs get visualize/dashboards/reports
tsuga docs get visualize/guides/how-to-create-a-dashboard-from-a-template
```

Determine:
- What service or system is this for?
- What questions should the dashboard answer? (health, throughput, latency, capacity)
- Who is the audience — on-call engineers, team leads, or executives?

Audience determines density and complexity. On-call → dense, operational. Exec → sparse, trend-focused.

Sketch the planned sections and widget types before touching any CLI commands. Example:
```
Health:     3× query-value (error rate, p99, availability)
Throughput: 1× timeseries (request rate by endpoint)
Latency:    1× timeseries (p50/p95/p99), 1× top-list (slowest operations)
```

### Step 2 — Discover metrics

**REQUIRED SUB-SKILL:** Use `tsuga-cli` for metric discovery. Never invent metric names.

```bash
tsuga metrics list --from -1h | grep <service-or-prefix>
tsuga metrics get <metric-name>
```

For each candidate metric, record:
- `type` and `temporality` — drives `aggregate.type` and `functions` selection in Step 3 (see `tsuga-cli`'s Counter Math section)
- `attributes` — filter and groupBy candidates
- `unit` — normalizer hint for Step 4

If no metrics appear: widen the window (`--from -24h`), or check `context.service.name` spelling with `tsuga services list`.

### Step 3 — Build and verify each widget query

Use `tsuga-cli` (Counter Math, filter syntax, aggregation body sections) to construct each widget's aggregation. For every widget:

1. Pick `aggregate.type` and `functions` from metric `type` + `temporality` — gauge → `max`/`average` no function; delta counter → `sum` + `per-second`; cumulative counter → `sum` + `rate` (or `increase`); histogram → `percentile` with `field` + `percentile`.
2. Compose the body: body-level `timeRange` (Unix seconds), `dataSource`, `groupBy`, `formula`; per-query `aggregate`, `filter`, optional `functions`.
3. Verify with `tsuga aggregation scalar -f query.json` and confirm it returns data before embedding.

Inputs for each widget:
- Metric name
- `type` and `temporality` (from Step 2)
- What the widget should show — e.g. "per-second error rate grouped by HTTP route"
- Service filter — e.g. `context.service.name:web-backend`

Do not embed an unverified query body. If a query returns no data, resolve at the metric/filter level before continuing.

### Step 4 — Assemble the dashboard payload

Embed the verified query bodies from Step 3 into widget JSON. Use `references/widget-reference.md` for payload schemas and API gotchas. Use `references/layout-rules.md` for grid positioning.

Key structural rules:
- `owner` must be a team ID — resolve with `tsuga teams list`
- Each graph requires a unique `id`, a `visualization` object, and a `layout` object
- `query-value` does not support `groupBy` — the API silently drops it
- List-style widgets take a single `query` string. Variants: `list` (logs matching a Tsuga query), `list-log-patterns` (logs clustered into patterns), `list-connection` (datastore rows via `connectionId` + read-only SQL)
- Always include dashboard-level env + team filters:

```json
"filters": [
  {"key": "context.env", "values": []},
  {"key": "context.team", "values": []}
]
```

### Step 5 — Confirm, then create or update

Summarize the planned change (widgets being added, updated, or removed) and wait for explicit user confirmation before mutating.

```bash
# Create
tsuga dashboards create -f dashboard.json

# Update — always fetch first to avoid dropping existing widgets
tsuga dashboards get <id>
tsuga dashboards update <id> -f dashboard.json

# Verify
tsuga dashboards get <id>
```

## Evidence Requirements

- Every metric name must come from `tsuga metrics list` — never invented
- Every aggregation body must be run through `tsuga aggregation scalar` and return data before embedding
- `owner` must be a team ID from `tsuga teams list` — never inferred from a name

## Output Template

```
## Dashboard: <name>

Owner: <team name> (<team-id>)
Widgets: <count>
Time preset: <preset>

## Queries Verified
| Widget | Metric | Aggregation | Result |
|--------|--------|-------------|--------|
| Error Rate | http.server.request.count | sum + per-second | 12.4 req/s |
| p99 Latency | http.server.request.duration | percentile p99 | 124ms |

## Payload
<full JSON — shown for user confirmation before applying>

## Limitations
- <caveats from aggregation construction, gaps in metric coverage>
```

## Safety Rules

- Never execute `tsuga dashboards create` or `tsuga dashboards update` without explicit user confirmation
- Show the exact command and full payload before running
- Never claim alert firing state — monitors show config only, not live state
- Never claim deployment causality — no deployment markers are available in the CLI
- One dashboard per confirmation — batch mutations are forbidden

## Limitations

- Dashboard-level filters use object form `{"key": "...", "values": [...]}`, not TQL strings
- Formulas support only arithmetic (`q1 + q2`, `(q1 / (q1 + q2)) * 100`) — no functions like `max()` or `if()`
- `query-value` does not support `groupBy` — the field is silently dropped by the API
- Monitor firing state is not available — dashboards cannot show whether an alert is currently firing
- No deployment markers — dashboards cannot correlate metric changes to code deploys
- `tsuga dashboards update` replaces the full dashboard — always fetch with `tsuga dashboards get <id>` first

## Related Skills / Next Steps

- `tsuga-cli` — filter syntax, counter math, aggregation body construction, metric discovery, dashboard CRUD, time formats
- `tsuga-audit-metrics` — audit metric quality before dashboarding
- `tsuga-investigate-service-health` — the health triage workflow that dashboards should operationalize
