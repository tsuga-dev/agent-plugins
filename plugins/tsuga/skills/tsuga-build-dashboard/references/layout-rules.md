# Layout Rules

## Grid

- 12-column grid, unlimited vertical height
- Every row must tile to exactly 12 columns — no gaps, no overlaps
- Widgets in the same row must share the same `y` value
- Widgets in the same row share their height (`h`) implicitly by convention — choose consistent heights per row type
- Minimum chart width: 3 columns; minimum chart height: 2 (default: 4)

Layout object fields:
```json
{"x": 0, "y": 0, "w": 6, "h": 4}
```
- `x`: column start (0–11)
- `y`: row start (0+, in grid units)
- `w`: width in columns (1–12)
- `h`: height in grid units

---

## Section Structure

Each logical section of a dashboard follows this pattern:

```
[full-width note header, h=1]
[widget row(s)]
```

Example (Health section):
```json
{"id": "s-health", "visualization": {"type": "note", "note": "## Health", "noteColor": "blue.200"}, "layout": {"x": 0, "y": 0, "w": 12, "h": 1}},
{"id": "g-qv-1",  "visualization": {...},  "layout": {"x": 0, "y": 1, "w": 4, "h": 2}},
{"id": "g-qv-2",  "visualization": {...},  "layout": {"x": 4, "y": 1, "w": 4, "h": 2}},
{"id": "g-qv-3",  "visualization": {...},  "layout": {"x": 8, "y": 1, "w": 4, "h": 2}},
{"id": "g-chart", "visualization": {...},  "layout": {"x": 0, "y": 3, "w": 12, "h": 4}}
```

**Note heights:** a pure section-divider header is `h: 1`. An intro / context note with prose needs `h ≈ 3–5` — size it to the text. Don't leave it at `h: 1` (text clips) or balloon it to `h: 8+` (it dominates and pushes every chart below the fold — the #1 cause of an unreadable board).

---

## Row Tiling Patterns

**Query-value rows** (h=2 recommended):

| Count | Widths | x positions |
|-------|--------|-------------|
| 3 QVs | 4+4+4 | 0, 4, 8 |
| 4 QVs | 3+3+3+3 | 0, 3, 6, 9 |
| 6 QVs | 2+2+2+2+2+2 | 0, 2, 4, 6, 8, 10 |

**Chart rows** (h=4 recommended):

| Count | Widths | x positions |
|-------|--------|-------------|
| 1 chart | 12 | 0 |
| 2 charts | 6+6 | 0, 6 |
| 3 charts | 4+4+4 | 0, 4, 8 |

**Mixed rows** (QV + chart side by side):

| Layout | Widths | x positions |
|--------|--------|-------------|
| 1 QV + 1 chart | 3+9 | 0, 3 |
| 2 QVs + 1 chart | 3+3+6 | 0, 3, 6 |

---

## Section Ordering

Standard section order for service dashboards:

1. **Health** — error rate, availability KPIs
2. **Throughput** — request rate, event volume
3. **Latency** — p50 / p95 / p99 by operation
4. **Capacity** — memory, CPU, connections, queue depth
5. **Tech-specific** — database queries, cache hits, queue lag, etc.

Not every dashboard needs all five sections — include only the sections the audience needs.

---

## Widget Naming

Name widgets by **what they show**, never by the current time window or any other dashboard-level control. The time range is a per-view control the user changes freely — a name like `Indexed (7d)` is stale the instant someone picks a different range. Use `Indexed bytes`, not `Indexed (7d)`; `Error rate`, not `Errors (1h)`. Keep the window out of widget names and descriptions.

---

## Section Color Rotation

Use note colors to visually separate sections. Rotate through this sequence:

`blue.200` → `red.200` → `emerald.200` → `amber.200` → repeat

Starting with `blue.200` reserves red for genuinely alert-adjacent sections if needed.

---

## Dashboard-Level Filters

Include these filters when they are relevant to the dashboard audience or scope so users can scope the dashboard without editing JSON:

```json
"filters": [
  {"key": "context.env", "values": []},
  {"key": "context.team", "values": []}
]
```

- `values: []` means the filter is present but not pre-set — the UI shows a picker
- Filters apply to every widget on the dashboard
- Filters use object form, not TQL strings
- **Keep `values: []` for entity filters** (`context.cluster_id`, `context.org_name`, `context.service.name`). Because a filter is global, *pre-setting* one collapses every widget that groups *across* that entity down to a single series — e.g. a "cost by org" top-list under a hard-set `org_name` shows one row. Pre-set a filter only on a board that is genuinely about one entity; a comparison/breakdown board must leave them empty.

---

## `timePreset` Values

The `timePreset` field sets the dashboard's default time window. Omit it to let users choose in the UI.

Common values: `past-1-hour`, `past-4-hours`, `past-24-hours`, `past-7-days`

Full list: `past-5-minutes`, `past-15-minutes`, `past-30-minutes`, `past-1-hour`, `past-2-hours`, `past-4-hours`, `past-6-hours`, `past-12-hours`, `past-24-hours`, `past-2-days`, `past-3-days`, `past-7-days`, `past-30-days`, `past-3-months`, `current-day`, `current-week`, `current-month`, `previous-day`, `previous-week`, `previous-month`

---

## Complete Example Payload Structure

```json
{
  "name": "Web Backend — Health Overview",
  "owner": "<team-id>",
  "timePreset": "past-1-hour",
  "filters": [
    {"key": "context.env", "values": []},
    {"key": "context.team", "values": []}
  ],
  "tags": [{"key": "service", "value": "web-backend"}],
  "graphs": [
    {
      "id": "s-health",
      "name": "Health",
      "visualization": {"type": "note", "note": "## Health", "noteColor": "blue.200"},
      "layout": {"x": 0, "y": 0, "w": 12, "h": 1}
    },
    {
      "id": "g-error-rate",
      "name": "Error Rate",
      "visualization": {
        "type": "query-value",
        "source": "metrics",
        "queries": [{"aggregate": {"type": "sum", "field": "http.server.request.count"}, "filter": "context.service.name:web-backend", "functions": [{"type": "per-second"}]}],
        "formula": "q1",
        "backgroundMode": "background",
        "normalizer": {"type": "custom", "unit": "req/s"},
        "conditions": [{"operator": "greater_than", "value": 50, "color": "alert"}]
      },
      "layout": {"x": 0, "y": 1, "w": 4, "h": 2}
    },
    {
      "id": "s-throughput",
      "name": "Throughput",
      "visualization": {"type": "note", "note": "## Throughput", "noteColor": "emerald.200"},
      "layout": {"x": 0, "y": 3, "w": 12, "h": 1}
    }
  ]
}
```
