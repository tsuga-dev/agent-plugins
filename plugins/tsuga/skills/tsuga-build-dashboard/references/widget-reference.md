# Widget Reference

Dashboard JSON schema notes and API gotchas for `tsuga dashboards create|update`.

Documentation queries:

```bash
tsuga docs get visualize/analytics/graph-types-and-widget-options
tsuga docs get visualize/analytics/queries
tsuga docs get visualize/analytics/display-options
tsuga docs get visualize/analytics/connection-backed-graphs
```

The visualization `type` strings here are API values, not necessarily the UI labels used in docs.

Max 15 queries per widget. `formula` references queries by position: `"q1"` = first query, `"q2"` = second, etc.

**Never send an empty `name` or `description` (`""`)** — the API rejects it with a 400 (`must NOT have fewer than 1 characters`). When a widget has no label (common for notes), **omit the key entirely** rather than passing `""`. (For aggregate/query-body rules — `count` not valid on `metrics`, Unix-seconds `timeRange`, etc. — see `tsuga-cli`.)

---

## `timeseries`

API payload for a time-series line chart.

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

API payload for a single aggregated number.

```json
{
  "id": "g-error-count",
  "name": "Error Count (1h)",
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

API payload for a gauge.

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

API payload for a ranked grouped aggregation.

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

API payload for a bar chart.

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

API payload for a donut/pie chart.

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

API payload for a distribution chart.

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
**Optional:** `formula`, `groupBy`, `percentileMarkers`, `normalizer`, `precision`
**Gotchas:**
- `percentileMarkers` are integers 0–100 (e.g. `[50, 95, 99]`) drawn as vertical reference lines on the histogram.
- The widget buckets the queried numeric `field`, so point the aggregate at a numeric field (`duration_ms`, `output_tokens`, …) — `count` with no field gives nothing to distribute. Verify the rendered shape with `tsuga aggregation scalar` + the app before embedding.

---

## `heatmap`

API payload for a heatmap.

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
    "groupBy": [{"fields": ["user.email"], "limit": 30}],
    "palette": "green",
    "normalizer": {"type": "custom", "unit": "prompts"}
  },
  "layout": {"x": 0, "y": 0, "w": 12, "h": 5}
}
```

**Required:** `source`, `queries`
**Optional:** `formula`, `groupBy`, `palette`, `normalizer`, `precision`
**Gotchas:**
- `palette` is one color from `red`, `pink`, `violet`, `blue`, `cyan`, `green`, `yellow`, `orange` — it sets the intensity gradient.
- Without `groupBy` the heatmap collapses to a single time-banded row; group by the dimension you want on the y-axis.
- High-cardinality `groupBy` makes rows unreadable — cap `limit` to what fits vertically (~20–30).

---

## `table`

API payload for a table.

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
**Optional top-level:** `groupBy` (max 7, applied as multi-level row grouping), `defaultSorting` (`[{"id": "<column id>", "desc": true}]`)
**Gotchas:**
- Unlike every other widget, `source` / `queries` live **per column**, not at the visualization root.
- `groupBy` defines the rows; each column aggregates within those rows.
- Per-column `formula` enables week-over-week deltas via a `time-offset` second query (see the percent column above).
- `defaultSorting.id` is the column id — confirm it in the app before relying on it; omit to use the default order.

---

## `list`

API payload for raw log rows.

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

API payload for clustered log patterns.

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

API payload for static dashboard notes.

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

API payloads for connection-backed variants drop `source` + aggregation `queries` and use instead:

- `connectionId` — the datastore connection to query (not a Tsuga `source`)
- `queries` — an array of read-only SQL strings (`SELECT` only); `list-connection` uses a single `query` string

```json
{
  "id": "g-signups",
  "name": "Signups (last 7d)",
  "visualization": {
    "type": "timeseries-connection",
    "connectionId": "<connection-id>",
    "queries": ["SELECT date_trunc('day', created_at) AS t, count(*) FROM users GROUP BY 1 ORDER BY 1"]
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

The `functions` array transforms a raw aggregation result (e.g. `[{"type": "per-second"}]`). Which function a given metric requires depends on its type and temporality — see the Counter Math section of `tsuga-cli` for the type/temporality → aggregate + function mapping. Verify each body with `tsuga aggregation scalar` before embedding here.
