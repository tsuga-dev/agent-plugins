# Playbook: Find Owner and Context

Use when asked who owns a service, which team is responsible, what observability exists for a service, or before making changes that affect a service. Resolves owning team, dashboards, monitors, and notification routing.

## Inputs

- **Service name** (required): Stop and ask if missing. If multiple services partially match, list candidates and ask the user to confirm which one.

## Workflow

1. `tsuga services list` — find by `serviceName`. If multiple partial matches, show them and ask the user to confirm before proceeding.
2. Extract from matched service: `teams[]`, `logsCount24h`, `errorLogsCount24h`, `tracesCount24h`, `errorTracesCount24h`, `sources[]`, `env`, `lastSeenAt`.
3. For each team ID in `teams[]`: `tsuga teams get <team-id>` — get `name`, `description`.
4. For each team ID: `tsuga dashboards list -d '{"filters":{"owners":{"values":["<team-id>"]}}}'` — list dashboards owned by this team.
5. `tsuga monitors list` — filter results where `configuration.queries[].filter` contains the service name. Note: glob patterns (e.g., `web-*`) in filters may cover this service without an exact match — flag these separately.
6. `tsuga notification-rules list` — filter by team ID appearing in `teamsFilter.teams[]`; note `isActive` per rule.

Documentation queries for returned surfaces:

```bash
tsuga docs get categorize/services/index
tsuga docs get categorize/services/service-page
tsuga docs get visualize/dashboards/dashboard-list
tsuga docs get alert/monitors/index
tsuga docs get alert/notifications/rules
```

## Evidence Requirements

- Ownership comes only from `services list` → `teams[]`. Never infer ownership from service name patterns.
- If `teams[]` is empty: state "no team assigned in Tsuga" — do not guess.
- Monitor coverage is text-based matching only; state this limitation explicitly.

## Output Template

```
## Service: <canonical serviceName> (<id>)
Env: <env> | Last seen: <lastSeenAt> | Sources: <logs / traces / logs+traces>
24h counters (rolling): logs=<logsCount24h> (errors=<errorLogsCount24h>), traces=<tracesCount24h> (errors=<errorTracesCount24h>)

## Owner(s)
- <team name> (<team-id>): <description>
[If teams[] is empty: "No team assigned in Tsuga."]

## Dashboards (<N total>)
- <dashboard name>
[If none: "No dashboards found for this team."]

## Monitors (<N matched>)
- <monitor name> (priority <N>, type: <configuration.type>)
[Glob-pattern monitors that may cover this service:]
- <monitor name> — filter pattern: <filter value>
[If none: "No monitors found referencing this service name."]

## Notification Rules
- <rule name> → <targets[].config.type> (active: yes/no)
[If none: "No notification rules found for this team."]

## Limitations
- Monitor firing state is not available (CLI returns config only, not live state)
- Monitor filter matching is text-based; glob patterns like web-* may cover this service without appearing in results
- On-call schedules are not available in Tsuga
- 24h counters are rolling windows computed server-side; report time: <query timestamp>
```

## Safety Rules

- Never infer ownership from service name conventions. Always use `services list` → `teams[]`.
- If `teams[]` is empty: say "no team assigned in Tsuga." Do not guess based on the service name.
- Never claim a monitor is currently firing. CLI returns configuration only.
- 24h counters are rolling; always state this when reporting them.

## Related / Next Steps

- `tsuga-investigate-service-health` skill — health check for the identified service
- `tsuga-audit-monitor-coverage` skill — check alerting coverage for the team's services
- `otel-instrumentation` skill — full observability review for the service (routes to per-lang `references/audit-checklist.md`)
