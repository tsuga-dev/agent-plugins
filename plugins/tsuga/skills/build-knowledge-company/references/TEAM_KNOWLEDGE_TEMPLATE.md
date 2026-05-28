# TEAM_KNOWLEDGE_TEMPLATE — per-team dossier

One per operationally-meaningful team. ~60–120 lines each. Narrative and scannable, not exhaustive. Exhaustive belongs in the per-service dossiers.

## Target length: 60–120 lines

If the team has 1–3 services (e.g., `data` team or `web` team), 60–80 lines is plenty. If the team is sprawling (e.g., `infra` with 100+ services), 120 lines is the cap — condense via a "top 5 by volume" treatment.

## Template — copy verbatim, fill in placeholders

```markdown
# Team — {team_name}

| Field | Value |
|---|---|
| Team ID | `{team_id}` |
| Common name | **{display_name}**. Telemetry tag: `context.team:{team_name}`. |
| Owner GitHub project(s) | `{repo_1}`, `{repo_2}` |
| Operational weight | **{one-line summary}**. {N} direct services, {X} logs / {Y} traces per day, {Z} monitors. |

## What they own

{One or two paragraphs.} Mental model: what's the team's charter in one sentence? What do they page on? What's the distinguishing feature vs. other teams?

Services:
- **`<service-1>`** — one-line purpose. Cross-link to SERVICE_KNOWLEDGE.md if present.
- **`<service-2>`** — …

{Optionally: footnote on cross-team service ownership.} Some services are owned here but their monitors are owned by another team (classic example: a health-aggregator service may live under `platform` but its P1 monitors are owned by `infra` because they report infra SLIs). Call this out — it's a triage trap.

## Where to look first

| Incident class | Dashboard |
|---|---|
| {Symptom A} | **{Dashboard name}** ({N} graphs, {tags}) |
| {Symptom B} | `{Dashboard name}` ({N} graphs) |
| Personal WIP | `[Person] Debug dashboard` — skip unless debugging someone's draft |

Always use `managed-by=Pulumi` or `oncall=true` tagged dashboards over person-named ones — hand-edits on the latter get overwritten.

## Paging surface

{N} monitors: **X P1** (specifics), Y P2, Z P3, …

### P1 monitors (paging shape)

{Short narrative: what shapes of P1 fire from this team? Queue lag? Error rate? Anti-silence?}

| Monitor | Query shape | Threshold |
|---|---|---|
| `{monitor_id}` `{monitor_name}` | {query gist} | `{threshold}` |
| … | … | … |

### Notification routing quirks

{One or two sentences on how this team's monitors route.} For example: "`platform`-team P1s go through the global `[P1] Paging alerts` rule → incident.io." Or: "The `data` team has its own `[Data] Prod paging alerts` rule — Slack-only, no incident.io. If nobody in that channel responds, there is no fallback."

## Typical incident shapes

1. **{Shape 1 title}** — one paragraph of what happens, how to diagnose, which service is usually the culprit.
2. **{Shape 2 title}** — …
3. **{Shape 3 title}** — …

These should be distilled from the team's incident history (greppable in `skills/incident-history/references/incidents/`). Keep to 2–4 shapes; the full archive is the authoritative source for the long tail.

## Services with individual dossiers

See `services/<service-name>/SERVICE_KNOWLEDGE.md` for:

`<service-1>`, `<service-2>`, `<service-3>`.

### Services owned but without a dossier

- `<service-X>` — {one-line reason, e.g., "lambda function, no runtime dashboard, grep by function name"}
- `<service-Y>` — {e.g., "managed Postgres, see `$knowledge-technology/postgres/` instead"}
```

## Rules the orchestrator must follow

1. **One TEAM_KNOWLEDGE.md per non-trivial team.** Trivial = 0 owned monitors + 0 owned dashboards + 0 owned services. Skip those.
2. **Ownership-mismatch traps must be called out up front.** If a team's monitors are owned by another team's ID (like the health-aggregator / infra situation above), document it in both team dossiers.
3. **Don't duplicate from top-level docs.** The cluster ↔ customer table lives in `COMPANY_TELEMETRY_KNOWLEDGE.md`; don't paste it into every team file. Reference it.
4. **Don't list every owned service in prose.** The closing section has the dossier list. Prose services in "What they own" should be the headline ones, not an exhaustive inventory.
5. **"Typical incident shapes" must cite real incidents.** Not fabricated, not generic. Grep `incident-history` for each team's involvement and distill the top 3 recurring shapes. If only 1 incident fits a shape, don't inflate it to 3.
6. **Dashboards tagged `[Person]` are scratch.** Mention them only with the "skip unless debugging that person's draft" caveat; never recommend them as primary.
7. **The orchestrator writes these, not subagents.** These files require cross-team visibility to write well. Subagents don't see the other teams' files during their narrow per-service tasks.
