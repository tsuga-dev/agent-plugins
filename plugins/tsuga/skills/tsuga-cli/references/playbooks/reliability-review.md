# Playbook: Reliability Review

Use when asked for an observability posture overview, quality scores, reliability status, or which teams have poor instrumentation. Quality report review: lowest-scoring teams, failing instrumentation rules, double-risk cross-reference.

## Inputs

- **Team filter** (optional): if provided, scope review to named teams only
- **Score threshold** (optional, default: `0.7`): teams below this score are flagged

## Workflow

1. `tsuga quality-reports list` (pass `--cluster <id>` in multi-cluster orgs) — returns a flat array of rule-evaluation rows. Each row has `ruleId`, `owner` (team id or absent for global), `status`, `score`, `weight`, `reportOverallScore` and `reportTotalWeight` (per-owner aggregates), `createdAt`, optional `recommendation` and `examples`.
2. Group rows by `owner` to get per-team scores. Within each team's rows, every row carries the same `reportOverallScore` — use that as the team score. The report timestamp is `min(.[].createdAt)`. Rows where `owner` is absent are global (cluster-level) rules.
3. If the derived report timestamp is more than 48 hours ago: flag as potentially stale before continuing.
4. Flag teams below threshold; for each, list rows where `status == "failed"` — key fields: `ruleId`, `recommendation`, optional `examples`.
5. `tsuga teams list` — cross-reference `owner` (team id) → team name.
6. `tsuga monitors list` — identify teams with low quality score **and** few or no monitors; these represent the highest combined risk.

## Evidence Requirements

- Always state the derived report timestamp — this is a snapshot, not live data.
- Score conventions (document as conventions, not official Tsuga severity levels):
  - ≥ 0.8 = healthy
  - 0.6–0.79 = at risk
  - < 0.6 = failing
- "Low monitor coverage" = no monitors found referencing service names associated with this team.

## Output Template

```
## Reliability Review
Report generated: <min(rows.createdAt)>
[If derived timestamp > 48h ago: "⚠️ Report may be stale — generated <N> hours ago."]
Teams assessed: <N> | Below threshold (<threshold>): <N>

## Team Scores
| Team | Score | Status | Top failing rule |
|---|---|---|---|
| <team name from `tsuga teams list`> | <reportOverallScore> | healthy / at-risk / failing | <ruleId of a failed row> |

## Failing Rules Detail (teams below <threshold>)

**Team: <team name>** (score: <reportOverallScore>)
- ❌ <ruleId>: <recommendation>

## Double Risk: Low Quality + Low Monitor Coverage
Teams flagged in both this review and a monitor coverage audit:
- <team name>: score=<N>, no monitors found

## Recommended Actions
1. <team with worst score>: address <top failing ruleId> — <recommendation>

## Limitations
- Report generated at <min(rows.createdAt)>; changes after this time are not reflected
- Scores measure instrumentation quality, not incident risk or SLO compliance
- Score thresholds (healthy/at-risk/failing) are conventions, not official Tsuga severity levels
- Monitor coverage check is text-based; glob patterns in monitor filters may cover services not directly matched
```

## Safety Rules

- Always state the derived report timestamp in the output. Never present quality scores without it.
- Never equate quality score with incident probability or current health.
- Score thresholds (0.7 default) are conventions — state this explicitly in output.
- If the derived timestamp is > 48h ago: flag as potentially stale before presenting findings.

## Related / Next Steps

- `tsuga-audit-monitor-coverage` skill — alerting gap audit
- `otel-instrumentation` skill — full observability audit for a specific service via runtime docs
- `tsuga-audit-telemetry-quality` skill — metric design and telemetry quality audit
- `tsuga-cli` — identify team owners for failing services; use the bundled owner/context playbook when needed
