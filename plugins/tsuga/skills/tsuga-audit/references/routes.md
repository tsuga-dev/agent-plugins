# Telemetry Routing Audit

Audits the `routes` resource — team-owned log processing definitions that decide which team owns incoming telemetry and what enrichment runs on it before it's queryable. This is upstream of and distinct from monitor/notification routing: a route decides *who owns this data*; a notification rule decides *who gets alerted*.

## Example Requests

- "Audit our log routing"
- "Are there logs that don't match any route?"
- "Which routes are duplicating processing on the same logs?"
- "Does every team have a route for their logs?"
- "Review our route configuration"

## Required Inputs

- **Scope** (optional, default: all routes): team, or a specific route ID/name.

## Runtime Docs Lookup

For docs lookup rationale and docs-error behavior, follow `tsuga-cli`; examples omit `--rationale` for brevity.

| Need | Fetch |
|---|---|
| Route model — ownership, ranking, non-exclusive matching | `tsuga docs get process/routes/index` |
| Processor field/parse behavior | `tsuga docs get process/routes/processors` |
| Route API body | `tsuga docs get api/createRoute` and `tsuga docs get api/updateRoute` |
| Missing/changed log troubleshooting | `tsuga docs get process/guides/how-to-investigate-a-missing-or-changed-log` |
| TQL syntax used in Source query | `tsuga docs get explore/query-syntax` |

## Workflow

1. Resolve scope. `tsuga routes list` has no server-side filter — pull the full list and filter locally by `owner`/`tags`.

2. Start from the quality report (same convention as the other references): filter rows to `ruleId` in `team-has-route`, `unrouted-logs`, `no-over-routed-logs` for the requested team, or use the rows the orchestrator already fetched.

3. **Understand the matching model before flagging anything.** Routes are not exclusive: Tsuga checks every *enabled* route top to bottom by `rank`, and every route whose `query` matches a log runs on it — later routes see and can modify fields written by earlier ones. This is intentional layered enrichment, not a bug. Don't flag every log matched by more than one route as a problem; use the quality report's `no-over-routed-logs` finding and its `recommendation` text to identify *excessive* overlap, not any overlap.

4. `tsuga routes list` — for each route, note `owner`, enabled/disabled state, `rank`, and `query`. Cross `owner` against `tsuga teams list`: an owner ID absent from `teams list` is a stale team reference, same convention used for monitors and dashboards.

5. Team routing coverage: cross `tsuga teams list` against distinct enabled-route `owner` values. A team with zero enabled routes is a coverage gap — its telemetry either falls through unrouted or depends entirely on another team's route matching it incidentally.

6. Unrouted-logs check: sample recent logs (`tsuga logs search --max-results 10`) and compare against the union of enabled route `query` strings for an intuition check, but treat the quality report's `unrouted-logs` finding as the primary evidence — it's computed over the full ingest window, not a 10-row sample.

7. Disabled routes: list them separately. New routes start inactive by design until reviewed, so a route existing but disabled is a different finding than no route existing at all — don't conflate "unactivated" with "missing."

## Evidence Rules

- Every finding cites the command and value that produced it.
- "Over-routed" requires the quality report's `no-over-routed-logs` finding, not a manual count of overlapping `query` strings — multiple matches are expected by design; only the report's threshold identifies excess.
- Route config changes propagate only to logs ingested after the cluster picks up the change — a route audit reflects current config, not necessarily what produced already-ingested historical logs. State this when a finding depends on route config explaining past log behavior.
- Quality-report findings: carry the row's `recommendation` text into Recommended Actions close to verbatim, and prioritize multiple findings by estimated impact — see `tsuga-audit`'s Quality Reports step for the exact rule.

## Safety Rules

- Read-only by default. Creating, updating, enabling/disabling, re-ranking, or deleting a route requires the mutation gate: show the proposed change and why, wait for explicit confirmation, apply only after.
- Changing a route's Source query requires Global Admin or an admin of the route's owning team in the product — if a proposed fix needs this, say so rather than assuming the acting credential has permission.
- Never claim a route "fixed" missing data without confirming with a fresh `logs search` after the cluster picks up the change — propagation isn't instant.

## Output Template

```markdown
## Telemetry Routing Audit
Scope: <all routes / team <name>> | As of: <query timestamp> | Quality report generated: <createdAt>

## Summary
Routes audited: <N> | Enabled: <N> | Disabled: <N>
Teams with zero enabled routes: <N>

## Unrouted Logs (quality report evidence)
<finding, recommendation text, estimated impact>

## Over-Routed Logs (quality report evidence)
<finding, recommendation text, estimated impact>

## Stale Team References
| Route | Owner (missing team ID) |
|---|---|

## Teams Without Any Enabled Route
| Team | Note |
|---|---|

## Disabled Routes
| Route | Owner | Note |
|---|---|---|

## Findings
| Finding | Evidence | Source | Confidence |
|---|---|---|---|

## Recommended Actions

## Limitations
- Route matching is non-exclusive by design; overlap alone isn't a defect — only the quality report's threshold identifies excess.
- Route changes apply prospectively; this audit doesn't explain historical log behavior from before the current config was saved.
- `routes list` has no server-side filter; large route inventories are filtered client-side.
```

## Related Skills / Next Steps

- `tsuga-cli` — resource command syntax, TQL for Source query, owner lookups.
- `tsuga-audit` (monitor coverage class) — once telemetry is routed to a team, check whether it's also monitored and alerted on.
