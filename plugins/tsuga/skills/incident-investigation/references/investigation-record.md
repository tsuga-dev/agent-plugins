# Durable deliverables: investigation record + proofs dashboard

Every investigation that reaches a verdict ships **three** artifacts:

1. The chat verdict (the `## Output contract` in SKILL.md).
2. A Tsuga **investigation record** (`tsuga investigations create/update`) — the durable document.
3. A **proofs dashboard** (`tsuga dashboards create`) — one graph per validated telemetry claim.

2 and 3 are **defaults, not extras**. Skip one ONLY when:

- the user explicitly said not to create it, or
- the verdict is a fast-path close (`healthy` / `validation_noise` after one confirmation probe), or
- the API key lacks the permission (403 — skip silently, never block or retry), or
- (dashboard only) the verdict rests purely on code/config evidence with zero telemetry claims to graph, or
- rarely, your own judgment that the artifact adds nothing for this case — judgment skips must be the exception, not a habit.

Whenever a deliverable is skipped, the chat verdict's `Deliverables:` line must say which one and why; an unexplained skip is a contract violation.

## Environment hygiene (before any write)

- Verify the CLI targets the intended environment: `tsuga config` (key + default cluster). On shared machines the active config may have been switched by another session — prefer explicit `--operation-api-key` / `--cluster` flags over mutating shared config.
- Multi-cluster orgs: aggregation bodies need `"clusterId"`, and every deep link needs `clusterId=` pinned.

## Investigation record

Open it at Workflow step 2 with the case board, update it at gate passes, and finish it by replacing the content with the structured document below. Updates are full PUTs: always resend `name` and `owner`.

### `name`

Short — `<INC-id>: <symptom in a few words>`. The app displays it everywhere; do NOT restate it inside `contentMd` (no leading `# title`).

### `contentMd` template

```markdown
## Summary
3–5 lines: the finding(s), impact, status. Link the proofs dashboard here.

## Key facts
| | |
|---|---|
| Status | investigating · root cause confirmed/fixes pending · mitigated · resolved |
| Severity | with one clause of justification |
| Reported | timestamp UTC + where (channel/monitor) + incident lead |
| Detected via | monitor that fired, or "human observation — no monitor fired" (a detection gap is itself a finding) |
| Symptom onset | when symptoms actually started (≠ reported); state evidence edge if unknown |
| Services | affected services (deep-linked) + relevant sidecars/callers |
| Teams | owner · deploy · other involved |
| Impact | quantified per dimension, or "none user-visible confirmed" |

## Timeline (UTC)
| When | Event |
|---|---|
One row per event, chronological: relevant changes/deploys, symptom onsets,
detection, key diagnosis milestones, mitigations. End with current state.

## Symptoms
What was observed, exact values, [evidence:] tags. Symptom ≠ cause.

## Contributing causes
Numbered (plural — avoid single-root-cause framing). Each carries:
*Trigger:* (may honestly be "not pinned" + candidates) · *Mechanism:* with
file:line pins · *Verified:* how it was confirmed [evidence: tag].

## Mitigation & action items
One line for what was done during the incident (or "none required").
| # | Action | Owner | Ticket | Status |
Owner = team, not person. Ticket "—" until filed.
End with **Verify fixes:** the observable signal that proves each fix worked.

## Open questions
Only genuinely open items + what would close each.

## Falsified along the way
One line per dead hypothesis + the evidence that killed it. This is what
saves the next responder from re-walking dead ends.

## Lessons learned *(draft — finalize at postmortem)*
Went well / went wrong / got lucky. Seed it; the team finalizes 48–72h later.
```

### Linking rules

- Every ID in `contentMd` whose URL shape is known gets a deep link. URL catalog: `${CLAUDE_PLUGIN_ROOT}/skills/tsuga-cli/references/app-deep-links.md`. Never invent a URL shape.
- Evidence links use an **absolute** `timeRange` (the incident window, ms) so the view never drifts; only live views (service page) use relative presets.
- `linkedAssets`: always populate — proofs dashboard, affected service(s), the fired monitor if any. Allowed types: `dashboard`, `monitor`, `service`, `slo`, `log-route`.

## Proofs dashboard

- `name`: `<INC-id> — <symptom> (proofs)`; `owner`: the affected team's id; tag `{"key": "incident", "value": "<inc-id>"}`.
- **One graph per validated telemetry claim.** Graph names are assertions, not metric names: "Sidecar UNHEALTHY status (1 = failing, constant)", "In-flight requests — saturated since 06-03 08:00 UTC".
- **Probe-verify every query** (`tsuga aggregation scalar`) before creating the dashboard — never ship a graph whose query returns nothing, unless absence IS the claim (then say so in the graph name).
- Time preset must cover symptom onset plus a control stretch (e.g. `past-3-days`).
- Layout: two graphs per row (`w:6,h:4`).
- Link it from the record's Summary and in `linkedAssets`.

These two creates (plus record updates) are the only sanctioned mutations in this skill — everything else stays read-only unless the user explicitly asks.
