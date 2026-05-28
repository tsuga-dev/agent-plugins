# Playbook: Reliability Review

Use when asked for an observability posture overview, quality scores, reliability status, or which teams have poor instrumentation. Quality report review: lowest-scoring teams, failing instrumentation rules, double-risk cross-reference.

## Inputs

- **Team filter** (optional): if provided, scope review to named teams only
- **Score threshold** (optional, default: `0.7`): teams below this score are flagged

## Workflow

1. `tsuga quality-reports list` — extract `report.generatedAt`, `report.overallScore`, `report.teamResults[]` sorted by `score` ascending.
2. If `report.generatedAt` is more than 48 hours ago: flag as potentially stale before continuing.
3. Flag teams below threshold; for each: extract `ruleResults[]` to identify failing rules — key fields: `key`, `title`, `recommendation`.
4. `tsuga teams list` — cross-reference `teamId` → team name (quality report includes `teamName` but verify against live data).
5. `tsuga monitors list` — identify teams with low quality score **and** few or no monitors; these represent the highest combined risk.

## Evidence Requirements

- Always state `report.generatedAt` — this is a snapshot, not live data.
- Score conventions (document as conventions, not official Tsuga severity levels):
  - ≥ 0.8 = healthy
  - 0.6–0.79 = at risk
  - < 0.6 = failing
- "Low monitor coverage" = no monitors found referencing service names associated with this team.

## Output Template

```
## Reliability Review
Report generated: <generatedAt> | Overall score: <overallScore>
[If generatedAt > 48h ago: "⚠️ Report may be stale — generated <N> hours ago."]
Teams assessed: <N> | Below threshold (<threshold>): <N>

## Team Scores
| Team | Score | Status | Top failing rule |
|---|---|---|---|
| <teamName> | <score> | healthy / at-risk / failing | <ruleResults[0].title> |

## Failing Rules Detail (teams below <threshold>)

**Team: <teamName>** (score: <score>)
- ❌ <rule.title>: <summary> → Recommendation: <recommendation>

## Double Risk: Low Quality + Low Monitor Coverage
Teams flagged in both this review and a monitor coverage audit:
- <team name>: score=<N>, no monitors found

## Recommended Actions
1. <team with worst score>: address <top failing rule> — <recommendation>

## Limitations
- Report generated at <generatedAt>; changes after this time are not reflected
- Scores measure instrumentation quality, not incident risk or SLO compliance
- Score thresholds (healthy/at-risk/failing) are conventions, not official Tsuga severity levels
- Monitor coverage check is text-based; glob patterns in monitor filters may cover services not directly matched
```

## Safety Rules

- Always state `report.generatedAt` in the output. Never present quality scores without the report timestamp.
- Never equate quality score with incident probability or current health.
- Score thresholds (0.7 default) are conventions — state this explicitly in output.
- If `generatedAt` > 48h ago: flag as potentially stale before presenting findings.

## Related / Next Steps

- `tsuga-audit-monitor-coverage` skill — alerting gap audit
- `otel-instrumentation` skill — full observability audit for a specific service (routes to per-lang `references/audit-checklist.md`)
- `tsuga-audit-metrics` skill — metric design and naming quality audit
- `./find-owner-and-context.md` — identify team owners for failing services (sibling playbook)
