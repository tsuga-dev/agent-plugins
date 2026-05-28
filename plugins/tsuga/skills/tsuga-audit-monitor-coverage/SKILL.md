---
name: tsuga-audit-monitor-coverage
description: "Use when asked to check if services have monitors, audit alerting gaps, review notification routing, or find teams without alerts."
---

# Audit Monitor Coverage

## When to Trigger

- "Audit our alerting coverage"
- "Which services have no monitors?"
- "Are there notification routing gaps?"
- "Find services with no alerts configured"
- "Review our alerting setup"
- "Which teams have broken notification routing?"

## Required Inputs

- **Scope** (optional, default: all services): can be narrowed to a specific team or service. If scoping to all services, warn if the list exceeds 100 services before proceeding.

## Workflow

1. `tsuga services list` — full service inventory. If > 100 services: confirm scope with user before continuing.

2. `tsuga monitors list` — all monitors. Build a map of `{service-name-or-pattern → [monitors]}` by parsing `configuration.queries[].filter` for `context.service.name:` values.
   - Exact matches: `context.service.name:web-backend`
   - Glob patterns (e.g., `web-*`): these may cover multiple services — track them separately with a note that they cannot be precisely matched to service names

3. `tsuga teams list` — all teams; build `{team-id → team-name}` map.

4. `tsuga notification-rules list` — build `{team-id → [rules]}` map; note `isActive` per rule.

5. `tsuga notification-silences list` — list active silences; note coverage scope and expiry.

6. Cross-reference:
   - Services not covered by any exact-match monitor filter → coverage gap
   - Monitor `owner` teams with no active notification rule → routing gap (monitor fires, nobody is notified)
   - Notification rule `teamsFilter.teams[]` referencing team IDs not in `teams list` results → stale team reference

### Confirm Before Applying

Before creating any monitors or notification rules, show the full proposed list and wait for explicit confirmation.

1. Show the proposed change (diff, code block, or table) with a brief explanation of WHY
2. Wait for explicit user confirmation ("yes" / "no" / "select specific ones")
3. Apply only after confirmation

After deploy, recommend running `tsuga-smoke-test` to verify — do not block on it or treat it as a required step.

## Evidence Requirements

- "No monitor coverage" = service name not found in any `configuration.queries[].filter` (exact match). Glob-pattern monitors are listed separately as "possible coverage."
- "Routing gap" = monitor has an `owner` team ID that has no active (`isActive: true`) notification rule.
- State query timestamp in output.

## Output Template

```
## Monitor Coverage Audit
Scope: <all services / team <name> / service <name>> | As of: <query timestamp>

## Summary
Services audited: <N> | With monitors (exact match): <N> (<pct>%) | No monitors: <N>
Teams with monitors but no active notification rule: <N>
Active silences: <N>

## Uncovered Services (no exact-match monitor filter)
| Service | Team | Env |
|---|---|---|
| <serviceName> | <team name> | <env> |

## Possible Coverage via Glob Patterns
The following monitor filters use glob patterns and may cover services above:
- <monitor name>: filter pattern <filter value> (owner: <team>)

## Routing Gaps
| Team | Issue |
|---|---|
| <team name> | Has monitors but no active notification rule |
| <team name> | Notification rule references non-existent team ID: <id> |

## Active Silences
- <silence name>: covers <scope>, until <expiry>

## Suggested Remediation Commands
These require your explicit confirmation before execution.

```bash
# Create a monitor for <service> — generate skeleton, edit, then create
tsuga monitors create --generate-skeleton > monitor.json
# Edit monitor.json with service filter, conditions, and owner team
tsuga monitors create -f monitor.json

# Create a notification rule for <team>
tsuga notification-rules create --generate-skeleton > rule.json
# Edit rule.json with team filter, priority filter, and targets
tsuga notification-rules create -f rule.json
```

## Limitations
- Monitor coverage = filter text matching only; glob patterns cannot be precisely matched to service names
- Monitor firing state not available (config audit only, not runtime audit)
- Config audit reflects state at query time; newly created monitors/rules not reflected until next query
```

## Safety Rules

- Remediation commands require explicit user confirmation ("yes, proceed") before execution. Never batch-create monitors or rules without the user reviewing the full proposed list.
- Always show `--generate-skeleton` examples to help the user understand the payload shape before creating resources.
- Never claim a monitor is currently firing or that a gap is actively causing missed alerts.
- State query timestamp in output — this is a configuration snapshot, not live state.
- If > 100 services: warn the user and confirm scope before running the full audit.

## Related Skills / Next Steps
- `tsuga-cli` `references/playbooks/reliability-review.md` — quality report review (instrumentation gaps, scoring)
- `tsuga-investigate-service-health` — if a service has gaps, check current health
- `tsuga-cli` `references/playbooks/find-owner-and-context.md` — identify team owners for services missing monitors
