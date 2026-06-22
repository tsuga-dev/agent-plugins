# Tsuga App Deep Links

Full URL catalog for `https://app.tsuga.com`. Load this file when you need to hand back a clickable link to a Tsuga page (monitor, dashboard, trace, metric, etc.).

The frontend uses TanStack Router with default JSON-encoded search params: object/array values are JSON-stringified and then URL-encoded once (`{` → `%7B`, `[` → `%5B`, `"` → `%22`, `:` → `%3A`, `,` → `%2C`).

## Global search params (work on any authenticated page)

- `clusterId=<cluster-id>` — target a specific cluster on multi-cluster tenants. Same id as `tsuga cluster list`. Omit on single-cluster tenants.
- `modal=<json>` — open a modal on top of the current page. Used for monitor + dashboard flows. Shape: `{"id":"<modal-id>","<entity>Id":"<id>","ui":true}`. The `ui:true` flag switches the modal into form mode (safe to include).
  - Modal ids: `monitor-create`, `monitor-edit`, `monitor-duplicate`, `monitor-read`, `dashboard-create`, `dashboard-edit`, `dashboard-duplicate`.
  - `monitor-edit` / `monitor-duplicate` / `monitor-read` require `monitorId`. `dashboard-edit` / `dashboard-duplicate` require `dashboardId`. `monitor-create` / `dashboard-create` accept prefilled draft fields (`queries`, `groupBy`, `formula`, `name`, `priority`, `owner`, etc.) instead of an id.

## Time encoding

- `timeRange` (used on most pages):
  - Relative: `{"type":"relative","preset":"past-24-hours"}` — presets: `past-{5,15,30}-minutes`, `past-{1,2,4,6,12,24}-hours`, `past-{2,3,7,30}-days`, `past-3-months`, `current-{day,week,month,year}`, `previous-{day,week,month,3-months,year}`.
  - Absolute: `{"type":"absolute","from":<ms>,"to":<ms>}` — Unix **milliseconds**.
- `timeInterval` (used only on `/traces/$traceId`): `{"from":<ms>,"to":<ms>}` — no `type` discriminator.

## Page catalog

| Page | Path | Notable search params |
|---|---|---|
| Logs explorer | `/explorer` | `query` (TQL string), `filter` (simple filters: `[[field,[v1,v2]], ...]`), `exclusiveFilters`, `timeRange`, `pattern` (bool), `id` (selected log id for side panel), `timestamp`, `sort`, `extraColumns`, `defaultColumns` |
| Metrics list | `/metrics` | `query`, `queryMetricAttribute` |
| Metric detail | `/metrics/$metricName` | (inherits global params) |
| Traces explorer | `/traces` | `search` (TQL), `filter`, `exclusiveFilters`, `timeRange`, `status` (`[]`), `service` (`[]`), `spanName` (`[]`), `spanDuration` (`{min,max}` ms), `spanKind` (`[]`), `isRoot` (bool), `team` (`[]`), `env` (`[]`), `sort`, `spanId`, `timestamp` |
| Trace detail | `/traces/$traceId` | `spanId`, `timeInterval` |
| Analytics | `/analytics` | `queries` (array of `{aggregate,filter,functions,visible}`), `groupBy` (array of `{fields,limit}`), `formula`, `source` (`logs`/`metrics`/`traces`), `timeRange`, `visibleSeries` |
| Analytics explain | `/analytics/explain` | `explainPoint` (`{groupId,filter,formula,label,timestamp,intervalInSeconds}`), `queries`, `groupBy`, `source`, `timeRange`, `openedGraph` |
| Dashboard list | `/dashboards` | `search`, `teams`, `tags`, `reportSearch` |
| Dashboard reports | `/dashboards/reports` (+ `/new`, `/$reportId`) | `reportSearch`, `reportStatus` |
| Dashboard grid | `/dashboards/$dashboardId` | `timeRange`, `fromMonitor` (monitor id that opened the link), `filter`, `exclusiveFilters`, plus analytics overrides (`queries`, `groupBy`, `formula`, `openedGraph`, `openedGraphReadonly`, `createGraph`, `reportView`) |
| Monitors list | `/monitors` | `priority` (`[]`), `search`, `teams`, `tags`, `type`, `activity` (`all`/`active`/`paused`/…), `clusterIds`, plus global `modal` (this is where the monitor-edit / monitor-read modals are typically opened) |
| Notification rules list | `/notification-rules` | `search`, `teams`, `targets`, `tags`, `status`, `scheduleTypes`, `clusterIds` |
| New / edit / duplicate notification rule | `/notification-rules/new`, `/notification-rules/$id/edit`, `/notification-rules/$id/duplicate` | — |
| Notification integrations | `/notification-rules/integrations[/new]` and per-vendor (`/notification-rules/integrations/{pagerduty,incident-io,grafana-irm,microsoft-teams,google-chat,servicenow,squadcast,webhook}[/$id/edit]`) | — |
| Notification silences | `/notification-rules/silences` (+ `/new`, `/$id/edit`, `/$id/duplicate`) | — |
| Services list | `/services` | `search`, `team`, `env`, `version`, `language`, `hasRecentData` |
| Service details | `/services/$serviceId` | `timeRange` (defaults to 24h), `version` (`[]`), `showDeployments` |
| Inventory | `/inventory`, `/inventory/all`, `/inventory/settings` | `search`, `tags`, `cloudAccount`, `cloudRegion`, `cloudPlatform`, `nativeResourceType`, `resourceType`, `isIacManaged` |
| Asset changes | `/asset-changes` (or `/asset-changes/$assetId`) | `assetId` |
| Add account | `/inventory/add-account[/$provider]` | — |
| Endpoint catalog | `/endpoint-catalog` | (feature-flagged) |
| Host catalog | `/host-catalog` | `hostId`, `search`, `filter`, `exclusiveFilters` |
| Kubernetes | `/kubernetes/{clusters,namespaces,pods,deployments}` | — |
| Resource graph | `/_resource-graph` | (internal) |
| Profiling | `/profiling` | `timeRange`, `service`, `viewMode` (`flamegraph`/`table`) |
| Ongoing alerts | `/ongoing-alerts` | — |
| SLOs | `/slos` | — |
| Alert statistics | `/alert-statistics` | — |
| Processing routes | `/processing/routes` (+ `/new`, `/edit/$routeId`, `/clone/$routeId`) | — |
| Sensitive data scanner | `/processing/sensitive-data-scanner` (+ `/$ruleKey/edit`) | — |
| Settings | `/settings/{profile,members,authentication,connections,llm,api-keys,clusters,access-controls,audit-logs,teams,quality-reports,usage-overview,behavior,retention}` | — |
| Team detail | `/settings/teams/$teamId` | — |
| API keys edit | `/settings/api-keys/edit/$id`, `/settings/api-keys/operation/edit/$id` (`/new`, `/operation/new` for create) | — |
| SAML configuration | `/settings/authentication/saml-configuration[/$id]` | — |
| Connection configuration | `/settings/connections/configuration[/$id]` | — |
| Documentation | `/documentation/$` (rest path under `home`) | — |
| Swagger | `/swagger`, `/internal-swagger` | — |
| Home | `/home` | — |
| Login / auth | `/login`, `/forgot-password`, `/new-password?resetId=...`, `/invite/accept?inviteSecret=...`, `/authentication` (SSO) | — |
| Internal | `/_design`, `/_graph`, `/_promql` | (developer-only) |

## Examples

```text
# Open a specific monitor for editing on a specific cluster (uses the global `modal` param)
https://app.tsuga.com/monitors?clusterId=j9k-9Ln-vnV&modal=%7B%22id%22%3A%22monitor-edit%22%2C%22monitorId%22%3A%226r52-tj8k2-qj4y%22%2C%22ui%22%3Atrue%7D

# Open a dashboard scoped to the last 24h
https://app.tsuga.com/dashboards/h45v-jynh5-38ec?clusterId=j9k-9Ln-vnV&timeRange=%7B%22type%22%3A%22relative%22%2C%22preset%22%3A%22past-24-hours%22%7D

# Drill into a span inside a trace, with the surrounding 30m window
https://app.tsuga.com/traces/579ac0ff4abdcb9e70289ddff79cf0b0?spanId=cb5122896755108a&timeInterval=%7B%22from%22%3A1778835408695%2C%22to%22%3A1778837208695%7D

# Open analytics with a unique-count of `account` grouped by `action.error.count`
https://app.tsuga.com/analytics?clusterId=j9k-9Ln-vnV&queries=%5B%7B%22aggregate%22%3A%7B%22type%22%3A%22unique-count%22%2C%22field%22%3A%22account%22%7D%2C%22filter%22%3A%22context.team%3Acentral%22%7D%5D&groupBy=%5B%7B%22fields%22%3A%5B%22action.error.count%22%5D%2C%22limit%22%3A10%7D%5D

# Edit a notification rule (path-based, no JSON params)
https://app.tsuga.com/notification-rules/x03c-9pqnk-kr2m/edit

# Logs explorer pinned to a single cluster (defaults strip the rest)
https://app.tsuga.com/explorer?clusterId=j9k-9Ln-vnV
```

## Tips for hand-rolling URLs

- Build the JSON value first, then `encodeURIComponent` it **once**. Don't double-encode.
- `filter` (logs/traces/dashboards) is **simple filters** — `Array<[field, string[]]>`, distinct from the TQL string in `query`/`search`. Don't confuse the two.
- Each route's `stripSearchParams` middleware drops values equal to the page default, so omitting empty `query`, default `timeRange`, etc. is fine.
- IDs in the URL are the same ids returned by `tsuga <resource> list` (monitors, dashboards, notification-rules, services, teams, …). Metrics are addressed by **name**, traces by **traceId**, spans by **spanId** inside a `traceId`.
- Use a relative `timeRange` (`past-24-hours`, etc.) for links a human will click later; use absolute (`{from,to}` ms) when pointing at a specific incident window so the view doesn't drift.
