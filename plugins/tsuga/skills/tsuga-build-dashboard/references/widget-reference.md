# Widget Reference

All widget types, their schemas, and usage guidance.

## Widget Type Summary

| Widget | Use when | groupBy? | Source |
|--------|----------|----------|--------|
| `timeseries` | Trends over time | Yes (max 7) | logs, metrics, traces |
| `query-value` | Single-number KPIs | No (silently dropped) | logs, metrics, traces |
| `gauge` | Single value against a known max (budget, utilization, SLO) | No | logs, metrics, traces |
| `top-list` | "Who is highest?" triage | Yes (max 7) | logs, metrics, traces |
| `bar` | Category comparisons (bounded set) | Yes (max 7) | logs, metrics, traces |
| `pie` | Part-to-whole breakdown (≤6 slices) | Yes (max 7) | logs, metrics, traces |
| `distribution` | Spread of a value (latency, token counts) | No | logs, metrics, traces |
| `heatmap` | Time × value density | No | logs, metrics, traces |
| `table` | Per-entity scorecard — many metrics as columns | Yes (max 3, multi-level) | logs, metrics, traces |
| `list` | Log evidence table | N/A | logs only |
| `list-log-patterns` | Clustered log patterns from noisy streams | N/A | logs only |
| `note` | Section headers, context blocks | N/A | N/A |

Supported connection variants (`timeseries-connection`, `list-connection`, `top-list-connection`, `pie-connection`, `bar-connection`, `query-value-connection`) run read-only SQL against a datastore connection instead of a Tsuga aggregation — see "Database connection variants" at the end.

Max 15 queries per widget. `formula` references queries by position: `"q1"` = first query, `"q2"` = second, etc.

**Never send an empty `name` or `description` (`""`)** — the API rejects it with a 400 (`must NOT have fewer than 1 characters`). When a widget has no label (common for notes), **omit the key entirely** rather than passing `""`. (For aggregate/query-body rules — `count` not valid on `metrics`, Unix-seconds `timeRange`, etc. — see `tsuga-cli`.)

### Series names in the legend (`aliases`)

Every series renders with an auto-generated label like `Count on (<filter>)` unless you name it. To set legible legend names, add `aliases` to the visualization:

```json
"aliases": {
  "queries": {"0": "Humans", "1": "AI agents", "2": "Automation"},
  "formula": "Programmatic %"
}
```

- `aliases.queries` is keyed by each query's **zero-based index as a string** — `"0"` is the first query in `queries`, `"1"` the second, and so on.
- ⚠️ this key is NOT the `formula` syntax. `formula` references queries as `"q1"`, `"q2"`; `aliases.queries` uses `"0"`, `"1"`. Using `"q1"` as an alias key is silently ignored and the generated label stays.
- Works on every aggregation widget (`timeseries`, `top-list`, `pie`, `bar`, `gauge`, ...). On `table`, aliases are set per column instead (see the `table` section).

---

## `timeseries`

Displays metric or log data as a line chart over time. Use for trends, rates, and latency distributions.

```json
{
  "id": "g-errors-over-time",
  "name": "Error Rate",
  "visualization": {
    "type": "timeseries",
    "source": "metrics",
    "queries": [
      {
        "aggregate": {"type": "sum", "field": "http.server.request.count"},
        "filter": "context.service.name:web-backend level:ERROR",
        "functions": [{"type": "per-second"}]
      }
    ],
    "formula": "q1",
    "groupBy": [{"fields": ["context.service.name"], "limit": 10}],
    "normalizer": {"type": "custom", "unit": "req/s"},
    "thresholds": [{"value": 10, "level": "alert"}]
  },
  "layout": {"x": 0, "y": 0, "w": 12, "h": 4}
}
```

**Required:** `source`, `queries`
**Optional:** `formula`, `groupBy`, `timeBucket`, `normalizer`, `precision`, `legendMode`, `thresholds`
**Gotchas:**
- Without a `normalizer`, raw numbers display without units — always set one for numeric widgets
- `thresholds` draw horizontal reference lines; use `query-value` `conditions` for color-coded KPIs

---

## `query-value`

Displays a single aggregated number. Use for KPIs on the dashboard's top row.

```json
{
  "id": "g-error-count",
  "name": "Error Count",
  "visualization": {
    "type": "query-value",
    "source": "logs",
    "queries": [
      {
        "aggregate": {"type": "count"},
        "filter": "level:ERROR context.service.name:web-backend"
      }
    ],
    "formula": "q1",
    "backgroundMode": "background",
    "normalizer": {"type": "custom", "unit": "errors"},
    "conditions": [
      {"operator": "greater_than", "value": 100, "color": "alert"},
      {"operator": "greater_than", "value": 10, "color": "warning"}
    ]
  },
  "layout": {"x": 0, "y": 1, "w": 4, "h": 2}
}
```

**Required:** `source`, `queries`
**Optional:** `formula`, `backgroundMode`, `conditions`, `normalizer`, `precision`, `legendMode`
**Gotchas:**
- `groupBy` is silently dropped — the API accepts it but ignores it
- Always set `"backgroundMode": "background"` so conditions (colors) are visible
- Condition operators: `greater_than`, `less_than`, `equal`, `not_equal`, `greater_than_or_equal`, `less_than_or_equal`
- Condition colors: `alert` (red), `warning` (yellow), `success` (green) — no other values

---

## `gauge`

Displays a single aggregated value as a dial against a maximum. Use for bounded quantities where "how close to the ceiling?" is the question — budget/quota burn, utilization, SLO attainment. For an unbounded KPI, use `query-value`.

```json
{
  "id": "g-budget-burn",
  "name": "LLM spend vs monthly budget",
  "visualization": {
    "type": "gauge",
    "source": "logs",
    "queries": [
      {
        "aggregate": {"type": "sum", "field": "cost_usd"},
        "filter": "context.service.name:claude-code event.name:api_request"
      }
    ],
    "formula": "q1",
    "max": 2000,
    "normalizer": {"type": "custom", "unit": "USD"},
    "colorThresholds": [
      {"from": 0, "color": "green"},
      {"from": 1500, "color": "yellow"},
      {"from": 1800, "color": "red"}
    ]
  },
  "layout": {"x": 0, "y": 0, "w": 3, "h": 3}
}
```

**Required:** `source`, `queries`
**Optional:** `formula`, `max`, `colorThresholds`, `normalizer`, `precision`, `legendMode`
**Gotchas:**
- No `groupBy` — a gauge renders one value. To compare across a dimension, use `bar` or `top-list`.
- Set `max` — without it the dial has no scale to fill against.
- `colorThresholds` colors are the full palette (`red`, `pink`, `violet`, `blue`, `cyan`, `green`, `yellow`, `orange`) — NOT the `alert`/`warning`/`success` set used by `query-value` `conditions`. Each `from` starts a band that runs to the next threshold (or to `max`).

---

## `top-list`

Displays a ranked list of the top values for a grouped aggregation. Use for "which service has the most errors?" triage.

```json
{
  "id": "g-top-error-services",
  "name": "Top Error Services",
  "visualization": {
    "type": "top-list",
    "source": "logs",
    "queries": [
      {
        "aggregate": {"type": "count"},
        "filter": "level:ERROR"
      }
    ],
    "formula": "q1",
    "groupBy": [{"fields": ["context.service.name"], "limit": 10}],
    "normalizer": {"type": "custom", "unit": "errors"}
  },
  "layout": {"x": 0, "y": 0, "w": 6, "h": 4}
}
```

**Required:** `source`, `queries`
**Optional:** `formula`, `groupBy`, `normalizer`, `precision`
**Gotchas:**
- Without `groupBy`, shows a single aggregate value — use `query-value` instead
- `limit` in `groupBy` controls how many rows appear

---

## `bar`

Displays aggregated values as vertical bars. Use for comparing a bounded category set (environments, HTTP methods, status codes) — not for unbounded high-cardinality fields.

```json
{
  "id": "g-requests-by-method",
  "name": "Requests by HTTP Method",
  "visualization": {
    "type": "bar",
    "source": "traces",
    "queries": [
      {
        "aggregate": {"type": "count"},
        "filter": "context.service.name:web-backend"
      }
    ],
    "formula": "q1",
    "groupBy": [{"fields": ["http.method"], "limit": 10}],
    "normalizer": {"type": "custom", "unit": "requests"}
  },
  "layout": {"x": 6, "y": 0, "w": 6, "h": 4}
}
```

**Required:** `source`, `queries`
**Optional:** `formula`, `groupBy`, `timeBucket`, `normalizer`, `precision`, `thresholds`, `legendMode`
**Gotchas:**
- Without `groupBy`, renders a single bar — usually not useful; prefer `query-value`
- `timeBucket` controls bar width when used as a histogram: `{"time": 5, "metric": "min"}`

---

## `pie`

Displays part-to-whole proportion. Keep slices to ≤6; more than that is unreadable. Use for status code breakdown, environment split, etc.

```json
{
  "id": "g-status-split",
  "name": "Requests by Status Class",
  "visualization": {
    "type": "pie",
    "source": "logs",
    "queries": [
      {
        "aggregate": {"type": "count"},
        "filter": "context.service.name:web-backend"
      }
    ],
    "formula": "q1",
    "groupBy": [{"fields": ["level"], "limit": 6}],
    "normalizer": {"type": "custom", "unit": "requests"}
  },
  "layout": {"x": 0, "y": 0, "w": 6, "h": 4}
}
```

**Required:** `source`, `queries`
**Optional:** `formula`, `groupBy`, `normalizer`, `precision`, `legendMode`
**Gotchas:**
- Keep `limit` ≤ 6 — slices beyond that are visually indistinguishable
- Without `groupBy`, renders a single-slice pie — always include it

---

## `distribution`

Displays the spread of an aggregated value as a histogram. Use when the *shape* — tail, modality, outliers — matters more than a single percentile: request latency, tokens per call, payload sizes.

```json
{
  "id": "g-latency-dist",
  "name": "API request latency distribution",
  "visualization": {
    "type": "distribution",
    "source": "logs",
    "queries": [
      {
        "aggregate": {"type": "percentile", "field": "duration_ms", "percentile": 95},
        "filter": "context.service.name:claude-code event.name:api_request"
      }
    ],
    "percentileMarkers": [50, 95, 99],
    "normalizer": {"type": "duration", "unit": "ms"}
  },
  "layout": {"x": 0, "y": 0, "w": 6, "h": 4}
}
```

**Required:** `source`, `queries`
**Optional:** `formula`, `percentileMarkers`, `normalizer`, `precision`
**Gotchas:**
- `percentileMarkers` are integers 0–100 (e.g. `[50, 95, 99]`) drawn as vertical reference lines on the histogram.
- The widget buckets the queried numeric `field`, so point the aggregate at a numeric field (`duration_ms`, `output_tokens`, …) — `count` with no field gives nothing to distribute. Verify the aggregation body with `tsuga aggregation scalar`; rendered distribution/heatmap shape remains a limitation unless the user separately asks for UI validation.

---

## `heatmap`

Displays an aggregated value as a color-intensity grid over time. Use for density or intensity trends where the aggregate is the cell color.

```json
{
  "id": "g-activity-heatmap",
  "name": "Prompt activity by user over time",
  "visualization": {
    "type": "heatmap",
    "source": "logs",
    "queries": [
      {
        "aggregate": {"type": "count"},
        "filter": "context.service.name:claude-code event.name:user_prompt"
      }
    ],
    "palette": "green",
    "normalizer": {"type": "custom", "unit": "prompts"}
  },
  "layout": {"x": 0, "y": 0, "w": 12, "h": 5}
}
```

**Required:** `source`, `queries`
**Optional:** `formula`, `palette`, `normalizer`, `precision`
**Gotchas:**
- `palette` is one color from `red`, `pink`, `violet`, `blue`, `cyan`, `green`, `yellow`, `orange` — it sets the intensity gradient.
- `groupBy` is not supported for heatmap widgets. Use `timeseries` or `top-list` for grouped comparisons.

---

## `table`

Displays several independent aggregations as columns, with rows defined by `groupBy`. The densest widget — use for per-entity scorecards (one row per user / service / route, several metrics across). The existing LLM-usage dashboard uses it for per-user breakdowns.

```json
{
  "id": "g-per-user",
  "name": "Per-user activity",
  "visualization": {
    "type": "table",
    "columns": [
      {
        "name": "Events",
        "source": "logs",
        "queries": [{"aggregate": {"type": "count"}, "filter": "context.service.name:claude-code"}],
        "precision": 0
      },
      {
        "name": "Spend",
        "source": "logs",
        "queries": [{"aggregate": {"type": "sum", "field": "cost_usd"}, "filter": "context.service.name:claude-code event.name:api_request"}],
        "normalizer": {"type": "custom", "unit": "$"},
        "precision": 2
      },
      {
        "name": "vs last week",
        "source": "logs",
        "queries": [
          {"aggregate": {"type": "count"}, "filter": "context.service.name:claude-code"},
          {"aggregate": {"type": "count"}, "functions": [{"type": "time-offset", "seconds": 604800}], "filter": "context.service.name:claude-code"}
        ],
        "formula": "(q1-q2)/q2*100",
        "normalizer": {"type": "percent"},
        "precision": 1
      }
    ],
    "groupBy": [{"fields": ["user.email"], "limit": 50}]
  },
  "layout": {"x": 0, "y": 0, "w": 12, "h": 6}
}
```

**Required:** `columns` (≥1; each column needs `name`, `source`, `queries`)
**Optional per column:** `formula`, `normalizer`, `precision`, `aliases`
**Optional top-level:** `groupBy` (max 3, applied as multi-level row grouping), `defaultSorting` (`[{"id": "<column id>", "desc": true}]`)
**Gotchas:**
- Unlike every other widget, `source` / `queries` live **per column**, not at the visualization root.
- `groupBy` defines the rows; each column aggregates within those rows.
- Per-column `formula` enables week-over-week deltas via a `time-offset` second query (see the percent column above).
- `defaultSorting.id` is the column id — confirm it in the app before relying on it; omit to use the default order.

---

## `list`

Displays raw log records in a table. Use for log evidence rows below a chart that identified a problem. Source must be `"logs"`.

```json
{
  "id": "g-recent-errors",
  "name": "Recent Errors",
  "visualization": {
    "type": "list",
    "source": "logs",
    "query": "level:ERROR context.service.name:web-backend",
    "listColumns": [
      {"attribute": "message"},
      {"attribute": "context.service.name"},
      {"attribute": "trace_id"}
    ]
  },
  "layout": {"x": 0, "y": 4, "w": 12, "h": 4}
}
```

**Required:** `source` (must be `"logs"`), `query` (a TQL string — not a `queries` array)
**Optional:** `listColumns`
**Gotchas:**
- Uses `query` (string), not `queries` (array) — the structure is different from all other widgets
- `source` must be `"logs"` — no other source is accepted
- Without `listColumns`, shows a default column set

---

## `list-log-patterns`

Clusters the logs matching a query into recurring patterns (templated messages with the variable parts factored out). Use to summarize a noisy stream — "what distinct things are being logged?" — instead of scrolling raw rows. Logs-only.

```json
{
  "id": "g-error-patterns",
  "name": "Error patterns",
  "visualization": {
    "type": "list-log-patterns",
    "query": "level:ERROR context.service.name:web-backend",
    "layout": "vertical"
  },
  "layout": {"x": 0, "y": 0, "w": 12, "h": 5}
}
```

**Required:** `query` (a TQL string — like `list`, not a `queries` array)
**Optional:** `layout` (`horizontal` | `vertical`)
**Gotchas:**
- Like `list`, it takes a single `query` string and is logs-only — no `source`, no aggregation.
- The visualization-level `layout` (`horizontal`/`vertical`) is a different field from the widget's grid `layout` (`x/y/w/h`) — both appear in the same widget object.

---

## `note`

Displays static markdown text. Use as section headers and context blocks.

```json
{
  "id": "section-health",
  "name": "Health Section Header",
  "visualization": {
    "type": "note",
    "note": "## Health\nOverall service health indicators.",
    "noteColor": "blue.200",
    "noteAlign": "flex-start",
    "noteJustifyContent": "center"
  },
  "layout": {"x": 0, "y": 0, "w": 12, "h": 1}
}
```

**Required:** nothing (all fields optional)
**Optional:** `note` (markdown string), `noteColor`, `noteAlign`, `noteJustifyContent`

**noteColor values:**
`white`, `gray.100`, `blue.200`, `red.200`, `emerald.200`, `amber.200`, `lime.200`, `cyan.200`, `violet.200`, `fuchsia.200`, `pink.200`

**noteAlign / noteJustifyContent:** `flex-start`, `center`, `flex-end`

**Gotchas:**
- Note text supports markdown — use `##` for section headings
- Use real newlines (`\n` in JSON), not literal backslash-n in the rendered text
- Section header notes should always be `w: 12, h: 1` (full-width, one row tall)

---

## Database connection variants

Supported aggregation widgets can have a `*-connection` twin that runs read-only SQL against a configured datastore connection instead of a Tsuga aggregation: `timeseries-connection`, `top-list-connection`, `pie-connection`, `bar-connection`, `query-value-connection`, `list-connection`. They drop `source` + aggregation `queries` and use instead:

- `connectionId` — the datastore connection to query (not a Tsuga `source`)
- `queries` — an array of read-only SQL strings (`SELECT` only); `list-connection` uses a single `query` string

```json
{
  "id": "g-signups",
  "name": "Signups",
  "visualization": {
    "type": "timeseries-connection",
    "connectionId": "<connection-id>",
    "queries": ["SELECT date_trunc('day', created_at) AS time, COUNT(*) AS value FROM users WHERE created_at BETWEEN '{{ time_from }}' AND '{{ time_to }}' GROUP BY 1 ORDER BY 1"]
  },
  "layout": {"x": 0, "y": 0, "w": 6, "h": 4}
}
```

**Gotchas:**
- SQL must be read-only — anything other than `SELECT` is rejected.
- `connectionId` comes from the configured connections, not from `tsuga services list`.
- `legendMode`, `thresholds`, `yAxisSettings`, `listColumns` apply the same as on the non-connection twin.

---

## Normalizer Reference

Every numeric widget should have a `normalizer` so values display with meaningful units.

| Type | JSON | Use for |
|------|------|---------|
| Duration | `{"type": "duration", "unit": "ms"}` | Latency — set `unit` to the metric's actual unit (ns, us, ms, s, m, h, days) |
| Data | `{"type": "data", "unit": "B"}` | Bytes — set `unit` to the value's actual unit; OTel byte metrics are bytes → `B` (B, KB, MB, GB, TB, PB) |
| Percent | `{"type": "percent"}` | Ratios, utilization |
| Custom | `{"type": "custom", "unit": "req/s"}` | Everything else — provide a unit label |

**Critical — for `data` and `duration`, `unit` is the unit the raw value is ALREADY in, not a display target.** The UI auto-scales *up* from that base unit and picks the readable magnitude itself, so set it to the metric's true unit and let the widget format. OTel byte metrics (`*_bytes`, `intake_api_batch_bytes`, `quickwit_*_bytes`, …) emit **bytes** → use `"B"`, and the widget renders `58 TB`, `4.2 GB`, etc. on its own. Setting a larger base like `"GB"` on a bytes value overstates the reading by 1e9 — e.g. 58 TB displays as "58M PB". Always confirm the metric's unit with `tsuga metrics get <name>` before choosing.

---

## Formula Patterns

Formulas reference queries by position. Place the formula at body level (same level as `queries`).

| Pattern | Formula | Normalizer |
|---------|---------|------------|
| Error ratio % | `(q1 / (q1 + q2)) * 100` | `{"type": "percent"}` |
| Utilization % | `(q1 / q2) * 100` | `{"type": "percent"}` |
| Gap / delta | `q1 - q2` | Match the unit of q1 and q2 |

---

## Functions

The `functions` array transforms a raw aggregation result (e.g. `[{"type": "per-second"}]`). Which function a given metric requires depends on its type and temporality — see the Counter Math section of `tsuga-cli` for the type/temporality → aggregate + function mapping. Verify each body with `tsuga aggregation scalar` or `tsuga aggregation timeseries` before embedding here.
