# Widget Reference

All 7 widget types, their schemas, and usage guidance.

## Widget Type Summary

| Widget | Use when | groupBy? | Source |
|--------|----------|----------|--------|
| `timeseries` | Trends over time | Yes (max 7) | logs, metrics, traces |
| `query-value` | Single-number KPIs | No (silently dropped) | logs, metrics, traces |
| `top-list` | "Who is highest?" triage | Yes (max 7) | logs, metrics, traces |
| `bar` | Category comparisons (bounded set) | Yes (max 7) | logs, metrics, traces |
| `pie` | Part-to-whole breakdown (≤6 slices) | Yes (max 7) | logs, metrics, traces |
| `list` | Log evidence table | N/A | logs only |
| `note` | Section headers, context blocks | N/A | N/A |

Max 15 queries per widget. `formula` references queries by position: `"q1"` = first query, `"q2"` = second, etc.

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

## Normalizer Reference

Every numeric widget should have a `normalizer` so values display with meaningful units.

| Type | JSON | Use for |
|------|------|---------|
| Duration | `{"type": "duration", "unit": "ms"}` | Latency (ns, us, ms, s, m, h, days) |
| Data | `{"type": "data", "unit": "MB"}` | Memory, payload size (B, KB, MB, GB, TB, PB) |
| Percent | `{"type": "percent"}` | Ratios, utilization |
| Custom | `{"type": "custom", "unit": "req/s"}` | Everything else — provide a unit label |

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
