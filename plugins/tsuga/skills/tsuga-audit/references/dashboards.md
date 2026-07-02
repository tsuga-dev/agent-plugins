# Dashboard Audit

## Example Requests

- "Audit our dashboards"
- "Which dashboards are empty or stale?"
- "Do we have unused dashboards we should clean up?"
- "Review dashboard hygiene for team X"
- "Does every team have a dashboard?"

## Required Inputs

- **Scope** (optional, default: all dashboards): can be narrowed to a specific team or dashboard. If scoping to all dashboards and the org has more than ~50, warn before proceeding — dashboards are usually far fewer than services, so this is a lower bar than the 100-service threshold used elsewhere.

## Runtime Docs Lookup

For docs lookup rationale and docs-error behavior, follow `tsuga-cli`; examples omit `--rationale` for brevity.

| Need | Fetch |
|---|---|
| Dashboards product docs | `tsuga docs get visualize/dashboards/index` |
| Dashboard query/filter/sort fields | `tsuga docs get api/queryDashboards` |
| Quality report concepts and rule families | `tsuga docs get account-and-settings/quality-reports` |

## Workflow

1. Resolve requested team/dashboard scope. `tsuga dashboards list` supports server-side filtering by `owners`, `tags`, and `folderId` — use `-d '<json-filter>'` rather than filtering locally when scope is known.

2. **Start from the quality report, not from scratch.** If this reference is running inside a `tsuga-audit` orchestrator pass, use the rows it already fetched. If invoked standalone, pull them directly:
   ```bash
   tsuga quality-reports list --team <team> --rationale "..."
   ```
   Filter to `ruleId` in `no-empty-dashboards`, `no-stale-dashboards`, `no-unused-dashboards`. These three are dashboard-hygiene rules scored on every report run — they tell you where to look before you run a single dashboard query.
   - **`no-unused-dashboards` is quality-report-only evidence.** Dashboard view counts are not exposed through `tsuga dashboards list`/`get` or any documented API field — the quality report is the only source for "zero views in N days." Report it as `source: quality report (not independently verifiable via CLI)`, not as a CLI-confirmed finding.
   - `no-empty-dashboards` and `no-stale-dashboards` *are* independently checkable — corroborate them in the next two steps rather than taking the report's pass/fail at face value, since the report is a stored snapshot and dashboards change after it was generated.

3. `tsuga dashboards list -d '<filter>'` with `sort: {"by": "widgetCount", "direction": "asc"}` — confirm actual empty/near-empty dashboards. Neither `list` nor `get` returns a `widgetCount` scalar field (it's a sort key only); count widgets from each returned dashboard's `graphs` array length (`graphs.length` ≤ 1) rather than citing a field that isn't in the payload.

4. Same call with `sort: {"by": "updatedAt", "direction": "asc"}` orders dashboards oldest-to-newest, but `updatedAt` is a sort key only — it's never returned as a field on the dashboard object in either `list` or `get`, so an exact "days since update" cannot be computed from CLI/API data alone. Use the sort order as directional corroboration (which dashboards rank oldest), and treat the quality report's `no-stale-dashboards` row — which has the actual staleness verdict and threshold, currently 180 days at time of writing — as the source of truth for the finding and threshold; read the live `recommendation` text rather than hardcoding the number.

5. Resolve ownership: cross dashboard `owner` values against `tsuga teams list`. A dashboard owned by a team ID absent from `teams list` is a stale team reference, same pattern as monitor coverage.

6. Team dashboard coverage: cross `tsuga teams list` against the distinct `owner` values returned by `dashboards list`. A team with zero dashboards is a coverage gap — surface it, but don't assume it's wrong; some teams legitimately rely on another team's shared dashboard.

7. Cross-reference monitors when available: a quality-report `no-orphan-monitors` failure ("monitors not linked to a dashboard") for the same team corroborates a dashboard coverage gap — cite it as corroboration, don't re-derive monitor-linkage logic here; that check belongs to the monitor-coverage reference.

8. Before recommending deletion or archival of any flagged dashboard, run `tsuga dashboards get <id>` to inspect its actual widgets. A quality-report snapshot can be stale — confirm the dashboard is still empty/untouched at the time of the audit, not just at report-generation time.

## Evidence Rules

- Every finding cites the command and value that produced it — quality-report rows cite `ruleId` + `createdAt` + `recommendation`; CLI findings cite the exact field value (`owner`) or derived value (`graphs.length` for widget count). `widgetCount` and `updatedAt` are sort keys, not returned fields — never cite them as if the API handed back that literal value.
- Label evidence as `source: tsuga CLI` or `source: quality report`. Findings that combine both should say so explicitly.
- Treat `min(rows.createdAt)` across quality-report rows as the report generation time; flag it if older than 48 hours, same convention used elsewhere.
- `status: ignored` rows are a human-suppressed result, not a pass — report them separately from `failed`, never silently drop or count them as healthy.
- Do not recommend deleting or archiving a dashboard from the quality-report score alone; confirm with `dashboards get` first (step 8).
- Carry each row's `recommendation` text into Recommended Actions close to verbatim, and prioritize multiple findings by estimated impact — see `tsuga-audit`'s Quality Reports step for the exact rule.

## Safety Rules

- Read-only by default. Archiving or deleting a dashboard requires the same mutation gate as everywhere else: show the proposed change and why, wait for explicit confirmation, apply only after.
- Never batch-delete or batch-archive dashboards without the user reviewing the full proposed list.
- State the quality-report query timestamp in output — it is a configuration/usage snapshot, not a live view.

## Output Template

```markdown
## Dashboard Audit
Scope: <all dashboards / team <name>> | As of: <query timestamp> | Quality report generated: <createdAt>

## Summary
Dashboards audited: <N> | Empty (widgetCount ≤ 1): <N> | Stale (not updated in <threshold> days): <N> | Unused (quality report only): <N>
Teams with zero dashboards: <N>

## Empty Dashboards
| Dashboard | Owner | Widget count |
|---|---|---|

## Stale Dashboards
| Dashboard | Owner | Staleness evidence |
|---|---|---|

## Unused Dashboards (quality report only — not independently verifiable via CLI)
| Dashboard | Owner | Recommendation text |
|---|---|---|

## Teams Without Any Dashboard
| Team | Note |
|---|---|

## Findings
| Finding | Evidence | Source | Confidence |
|---|---|---|---|

## Recommended Actions

## Limitations
- Dashboard view counts are not exposed via CLI/API; "unused" relies entirely on the quality report snapshot.
- `updatedAt` is documented as a dashboard query sort key; if it is not returned in the CLI payload, exact last-updated timestamps and days-since-update must come from the quality report recommendation, not CLI evidence.
- Widget-level query health (references to removed metrics or log fields) requires manual inspection via `tsuga dashboards get <id>`, not checked automatically here.
- Stale-dashboard threshold is a rule parameter, not a fixed product guarantee — read it from the live `recommendation` text.
```

## Related Skills / Next Steps

- `tsuga-build-dashboard` — fix, rebuild, or repopulate a flagged dashboard.
- `tsuga-cli` — resource command syntax, filter/sort bodies, owner lookups.
- `tsuga-audit` (monitor coverage class) — cross-check monitor-to-dashboard linkage when a coverage gap spans both.
