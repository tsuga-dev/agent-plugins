# Public HTTP API (for user-built scripts)

For scripts or deployed services that hit Tsuga without the CLI or MCP (bulk backfills, metering jobs). Full OpenAPI reference: `https://app.tsuga.com/swagger`.

> During skill execution stay CLI-first — never curl the API yourself. This reference exists to hand correct integration facts to users building their own tooling.

- **Host:** `https://api.tsuga.com` — not `app.tsuga.com`, which is the web UI.
- **Auth:** `Authorization: Bearer <operation-key>`. The key must be an **operation key** with the relevant signal set to **Read** (e.g. Metrics = Read). An ingestion key is the wrong type — it can only send data in, never query it out. The CLI and MCP authenticate with the same key type, so a key that works in `tsuga auth` works over HTTP.
- **Aggregation endpoints** (mirror `tsuga aggregation`):
  - `POST /v1/aggregation/multi-query/scalar`
  - `POST /v1/aggregation/multi-query/timeseries` — body-level `aggregationWindow` (e.g. `"10s"`, `"1m"`, `"1h"`)
- **Request body:** identical to the CLI aggregation body documented in the skill (`dataSource`, `queries[]`, `timeRange`, `groupBy[]`, optional `formula`, optional `clusterId`). `timeRange.from`/`to` must be **Unix seconds (integers)** — ISO-8601 strings are rejected with `400 FST_ERR_VALIDATION`.
- **Response envelope:** `{"data": <result>, "requestId": "..."}` on success, `{"error": {...}, "requestId": "..."}` on 4XX/5XX. `data` carries the same shape the CLI prints (`results[]` for scalar, `series[].points[]` for timeseries).
- Most CLI commands have a `/v1/...` counterpart (`/v1/logs/search`, `/v1/logs/patterns`, `/v1/traces/search`, `/v1/metrics`, `/v1/monitors`, `/v1/dashboards`, …) — see the OpenAPI reference for the full surface.
- **Lookback is bounded by retention policies**, which are per-signal and resolve global → environment → team (1–3650 days). There is no universal retention constant — check `tsuga retention-policies list` (or Settings → Retention) before assuming how far back a query can go.
