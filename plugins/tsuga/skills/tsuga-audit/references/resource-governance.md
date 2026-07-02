# Resource Governance Audit

Covers three administrative Tsuga config resources whose hygiene isn't captured by the telemetry-quality, monitor-coverage, dashboard-hygiene, or routing classes: ingestion API keys, tag policies, and retention policies. Each is individually thin — a handful of fields, a handful of real checks — which is why this reference covers all three instead of splitting into three near-empty files.

## Example Requests

- "Are there any unused ingestion keys we should revoke?"
- "Do we have tag policies configured, and are they active?"
- "Which teams or environments have no retention policy?"
- "Audit our resource governance"

## Required Inputs

- **Scope** (optional, default: all three resource types, all teams): can be narrowed to a team, or to just one of ingestion keys / tag policies / retention policies.

## Runtime Docs Lookup

For docs lookup rationale and docs-error behavior, follow `tsuga-cli`; examples omit `--rationale` for brevity.

| Need | Fetch |
|---|---|
| Ingestion vs operation keys, ownership/tag model | `tsuga docs get account-and-settings/api-keys` |
| Tag policy product docs | `tsuga docs get account-and-settings/tag-policies` |
| Configuring tag policies | `tsuga docs get account-and-settings/guides/how-to-configure-tag-policies` |
| Retention product docs | `tsuga docs get account-and-settings/retention` |
| Configuring retention policies | `tsuga docs get account-and-settings/guides/how-to-configure-data-retention-policies` |

## Workflow

### Ingestion API keys

1. `tsuga ingestion-api-keys list` — inventory visible key metadata such as name, masked value, owner, tags, and team override fields when present. Do not assume the CLI response exposes usage volume or last-seen fields — "unused" is not independently verifiable via this command unless the installed CLI output clearly includes a usage field.
2. Start from the quality report's `no-unused-ingestion-api-keys` rows (or the ones the orchestrator already fetched) as the primary — effectively only — source of "unused" evidence. Label it `source: quality report (not independently verifiable via CLI)`.
3. As indirect, approximate corroboration only: cross the key's `owner` team against that team's services in `tsuga services list` (`lastSeenAt`, signal counters). This isn't a 1:1 mapping — a key doesn't correspond to exactly one service — so label any finding from this step as indirect, not confirmed.
4. Resolve ownership as usual: `owner` values absent from `tsuga teams list` are stale team references.

### Tag policies

5. `tsuga tag-policies list` — fields include `name`, `isActive`, `tagKey`, `allowedTagValues[]`, `isRequired`, `owner`, and `configuration` (`type`: `telemetry` or `tsuga_asset`, plus `assetTypes[]`). `configuration` decides what a policy actually governs — check it before choosing evidence in step 6. Flag inactive policies (`isActive: false`) separately — an inactive policy exists in config but enforces nothing.
6. For an active, required policy, the compliance check depends on `configuration.type`:
   - `type: "telemetry"` (`assetTypes` includes `logs`/`metrics`/`traces`): cross `tagKey` against real telemetry — sample recent data with that attribute (`tsuga logs search --query "<tagKey>:*" --max-results 10`, or `tsuga aggregation scalar` grouped by the tag) and check whether observed values fall inside `allowedTagValues`. This is a bounded proxy, not an exhaustive scan — state the sample size and window.
   - `type: "tsuga_asset"` with `assetTypes` including `ingestion-api-key`: this governs tags on the ingestion key resource itself, not telemetry — the tag will never appear in log/metric/trace attributes, so a telemetry search is the wrong evidence and will read as a false gap. Cross `allowedTagValues` against the `tags[]` array already pulled from `tsuga ingestion-api-keys list` in step 1, keyed by `tagKey`.
   - `type: "tsuga_asset"` with other `assetTypes` (e.g. `rum-public-token`): no CLI resource lists or reads that asset type's tags — label any finding `source: quality report only (no CLI resource for this asset type)` rather than fabricating a check.
7. Resolve ownership as usual, and note `configuration.assetTypes` in any finding so the evidence type is traceable.

### Retention policies

8. `tsuga retention-policies list` — fields are `env`, `teamId`, `dataSource`, `durationDays`, `isEnabled`. Cross `tsuga teams list` × known envs × `dataSource` (`logs`/`metrics`/`traces`) to find combinations with no policy at all — these fall back to an org default that may not match compliance or cost intent. Say so rather than assuming the gap itself is wrong; some orgs deliberately rely on the default.
9. Flag `durationDays` values that are outliers relative to peer teams/envs for the same `dataSource` — e.g. one team retaining logs for 3 years next to everyone else's 30 days is worth a question, not an automatic finding. Organizations vary intentionally; state it as "worth investigating."

## Evidence Rules

- Every finding cites the command and value that produced it.
- Label ingestion-key "unused" findings as quality-report-only; label telemetry tag-value compliance findings as a sampled proxy, not exhaustive; label asset-tag compliance findings (`configuration.type: "tsuga_asset"`) as cross-referenced against the asset's own `tags[]`, not sampled; label retention-duration outliers as "worth investigating," not a defect.
- Quality-report findings: carry the row's `recommendation` text into Recommended Actions close to verbatim, and prioritize multiple findings by estimated impact — see `tsuga-audit`'s Quality Reports step for the exact rule.

## Safety Rules

- Read-only by default. Creating, updating, or deleting any of the three resource types requires the mutation gate: show the proposed change and why, wait for explicit confirmation, apply only after.
- **Revoking an ingestion key is high blast-radius** — it can immediately stop ingestion for every service sending through it. Confirm the key is genuinely unused (not just report-flagged) via the indirect service-signal check before recommending revocation, and call out the blast radius explicitly in the proposed change.
- Never present a tag-value compliance finding as exhaustive; it's a bounded sample.

## Output Template

```markdown
## Resource Governance Audit
Scope: <all / team <name> / <resource type>> | As of: <query timestamp> | Quality report generated: <createdAt>

## Summary
Ingestion keys: <N> | Flagged unused (quality report): <N>
Tag policies: <N> | Inactive: <N> | Compliance samples checked: <N>
Retention policies: <N> | Team/env/dataSource combinations with no policy: <N>

## Ingestion Keys — Findings
| Key | Owner | Note |
|---|---|---|

## Tag Policies — Findings
| Policy | Tag key | Status | Note |
|---|---|---|---|

## Retention Policies — Findings
| Team/Env | Data source | Duration | Note |
|---|---|---|---|

## Findings
| Finding | Evidence | Source | Confidence |
|---|---|---|---|

## Recommended Actions

## Limitations
- Ingestion-key usage may not be exposed by the installed CLI; when no usage field is present, "unused" relies entirely on the quality report.
- Tag-value compliance checks are bounded samples, not exhaustive scans.
- Retention-duration comparisons are heuristic (peer outliers), not measured against a stated organizational policy unless one exists.
```

## Related Skills / Next Steps

- `tsuga-cli` — resource command syntax, owner lookups.
- `tsuga-audit` (telemetry quality class) — cross-check tag/attribute compliance findings against broader naming/cardinality issues.
