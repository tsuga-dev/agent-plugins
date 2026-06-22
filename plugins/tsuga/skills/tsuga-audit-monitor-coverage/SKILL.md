---
name: tsuga-audit-monitor-coverage
description: "Use when asked to check monitor coverage, services without monitors, alerting gaps, notification routing, notification-rules, silences, stale team references, PagerDuty or Slack routing destinations, teams without configured alerts, monitor ownership, monitor filters, log-error-pattern coverage, active/inactive routing rules, coverage summaries, routing gaps, coverage percentages, or whether alert configuration covers a service/team scope."
---

# Audit Monitor Coverage

## Example Requests

- "Audit our alerting coverage"
- "Which services have no monitors?"
- "Are there notification routing gaps?"
- "Find services with no alerts configured"
- "Review our alerting setup"
- "Which teams have broken notification routing?"

## Required Inputs

- **Scope** (optional, default: all services): can be narrowed to a specific team or service. If scoping to all services, warn if the list exceeds 100 services before proceeding.

## Workflow

1. Resolve requested service/team/env scope first. `tsuga services list` has no filter flags, so filter returned rows locally; if a full all-service audit would exceed 100 services, confirm scope with the user before continuing.

2. `tsuga monitors list` — monitor definitions. Use `-d '<json-filter>'` when a read-only server-side filter is available; otherwise filter locally. Build coverage using the same shapes the app uses for service-related resources:
   - Aggregation monitors: parse `configuration.queries[].filter` for exact or glob `service:` and `context.service.name:` values, including quoted values.
   - Log-error-pattern monitors: check `configuration.filter.service`, `env`, and `teamIds` when present.
   - Deployment/cluster-scoped monitors: treat env/namespace/cluster matches as possible coverage and explain the match basis.

3. `tsuga teams list` — all teams; build `{team-id → team-name}` map.

4. `tsuga notification-rules list` — evaluate active rules by CLI-visible matcher fields: `teamsFilter`, `prioritiesFilter`, `transitionTypesFilter`, `clusterIdsFilter`, `isActive`, and optional `queryString` when present. Treat `targets` as delivery destinations, not match constraints; label tag/dimension matching unverified unless `queryString` exposes it.

5. `tsuga notification-silences list` — list active silences; note coverage scope and schedule type. For one-time silences report `endTime`; for recurring weekly silences report schedule and timezone.

6. Cross-reference:
   - Services not covered by any exact-match or supported monitor association → coverage gap
   - Monitor owner/team with no active matching notification rule after applying CLI-visible filters → routing gap
   - Notification rule `teamsFilter.teams[]` referencing team IDs not in `teams list` results → stale team reference

### Confirm Before Applying

Before creating any monitors or notification rules, show the full proposed list and wait for explicit confirmation.

1. Show the proposed change (diff, code block, or table) with a brief explanation of WHY
2. Wait for explicit user confirmation ("yes" / "no" / "select specific ones")
3. Apply only after confirmation

After deploy, recommend running `tsuga-debug-telemetry-ingestion` to verify signal arrival — do not block on it or treat it as a required step.

## Evidence Requirements

- "No monitor coverage" = service name not found in exact `service:` / `context.service.name:` aggregation filters, log-error-pattern service filters, or app-supported service associations. Glob, env, namespace, tag, or cluster matches are listed separately as "possible or indirect coverage."
- "Routing gap" = no active notification rule matches the monitor/team after applying CLI-visible filters; target presence only proves a destination exists.
- Every finding cites the command and value that produced it.
- State query timestamp in output.

## Output Template

```
## Monitor Coverage Audit
Scope: <all services / team <name> / service <name>> | As of: <query timestamp>

## Summary
Services audited: <N> | With monitors (exact match): <N> (<pct>%) | No monitors: <N>
Teams with monitors but no active notification rule: <N>
Active silences: <N>

## Uncovered Services (no exact or supported monitor association)
| Service | Team | Env |
|---|---|---|
| <serviceName> | <team name> | <env> |

## Possible or Indirect Coverage
The following monitor filters use glob, env, namespace, tag, or cluster scope and may cover services above:
- <monitor name>: filter pattern <filter value> (owner: <team>)

## Routing Gaps
| Team | Issue |
|---|---|
| <team name> | Has monitors but no active notification rule |
| <team name> | Notification rule references non-existent team ID: <id> |

## Active Silences
- <silence name>: covers <scope>, schedule <one-time endTime / recurring weekly timezone>

## Suggested Remediation Commands
These require your explicit confirmation before execution. Generate skeletons in the CLI, then prepare payloads for review; do not write local files unless the user explicitly approves a local file write.

```bash
# Start from skeletons. Fetch `tsuga docs get api/createMonitor` or
# `tsuga docs get api/createNotificationRule` only if field meaning is unclear.
tsuga monitors create --generate-skeleton
tsuga notification-rules create --generate-skeleton

# Create a monitor for <service>
tsuga monitors create -d '<reviewed-json-payload>'

# Create a notification rule for <team>
tsuga notification-rules create -d '<reviewed-json-payload>'
```

## Limitations
- Monitor coverage uses known monitor associations from config fields; unsupported custom filters may still need manual review
- Services are telemetry-derived inventory snapshots, not an authoritative service ownership registry
- Monitor firing state not available (config audit only, not runtime audit)
- Config audit reflects state at query time; newly created monitors/rules not reflected until next query
```

## Safety Rules

- Remediation commands require explicit user confirmation ("yes, proceed") before execution. Never batch-create monitors or rules without the user reviewing the full proposed list.
- Start proposed payloads from `--generate-skeleton`; fetch `api/createMonitor` / `api/createNotificationRule` only when field meaning, enums, or response shape are unclear.
- Never claim a monitor is currently firing or that a gap is actively causing missed alerts.
- State query timestamp in output — this is a configuration snapshot, not live state.
- If > 100 services: warn the user and confirm scope before running the full audit.

## Related Skills / Next Steps
- `tsuga-cli` — quality report review, resource command syntax, and owner/context lookups
- `tsuga-investigate-service-health` — if a service has gaps, check current health
- `tsuga-debug-telemetry-ingestion` — if services or signals are missing from Tsuga
