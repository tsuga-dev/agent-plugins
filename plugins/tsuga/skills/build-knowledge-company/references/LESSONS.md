<!-- skill-lint: allow-forbidden-examples — this file documents the forbidden patterns as teaching examples -->

# LESSONS — hard-won mistakes from the first `knowledge-company` build

Read all of these before running the procedure. Every one of them cost us time on a first pass.

## Command-shape mistakes

### 1. MCP-tool pseudo-syntax is not `tsuga` CLI

The #1 bug by volume on first pass. Subagents with access to `mcp__tsuga__*` MCP tools will write output like:

```
search-logs query='context.service.name:report-generator' from=-24h to=now limit=50
aggregate-timeseries dataSource=metrics aggregationWindow=5m aggregate=sum field=foo
```

**These are not runnable.** Real `tsuga` CLI is:

```bash
tsuga logs search --query "context.service.name:report-generator" --from -24h --to now --max-results 50
```

Full translation contract in `CLI_TRANSLATION.md`. The forbidden-token grep in `VERIFICATION.md` catches this. Zero tolerance — any hit means the subagent ignored the contract; regenerate.

### 2. `--limit` is wrong. Use `--max-results`

Easy to paste from memory and get wrong.

### 3. `tsuga spans search` does not exist — it's `tsuga traces search`

The TQL data source is `spans`; the CLI verb is `traces`. This mismatch is a common stumble.

### 4. Singular vs plural resource names

The CLI pattern is always `tsuga <resource-plural> <verb>`:

- `tsuga monitors get` not `tsuga monitor get`
- `tsuga dashboards list` not `tsuga dashboard list`
- `tsuga routes list`, `tsuga teams list`, `tsuga services list`, etc.

### 5. `rtk` prefix is noise

The RTK hook rewrites commands transparently. Writing `rtk tsuga logs search …` in a dossier confuses human readers who don't have the hook. Always emit plain `tsuga …`.

### 6. Aggregation body gotchas

- `timeRange` requires **Unix seconds integers**, not strings. Use the helper:
  ```bash
  FROM=$(date -u -v-1H +%s); TO=$(date -u +%s)   # macOS
  # Linux: FROM=$(date -u -d '1 hour ago' +%s); TO=$(date -u +%s)
  ```
- `groupBy` is at **body level**: `"groupBy": [{"fields": ["X"], "limit": N}]`. Not inside query items.
- `functions` (`rate`, `per-second`, `increase`) are **per-query**: `"functions": [{"type": "rate"}]`.
- `formula` is at body level, references queries by position (`"q1"`, `"q2"`).
- `aggregationWindow` is at body level, only for timeseries.
- `count` aggregate is **not valid on `metrics`** dataSource. Use `sum` instead.
- Percentile is `{"type": "percentile", "percentile": 95, "field": "duration"}` — the `percentile` number sits on the aggregate object, not at body level.

### 7. Duration units

Trace span `duration` is in **milliseconds**. `duration:>10s` is wrong; it's `duration:>10000`.

### 8. Counter-math mistakes produce meaningless values

Before aggregating a metric, check its type + temporality (`tsuga metrics get <name>`).

- Gauge: `max` or `average`, no function.
- Delta counter: `sum` + `per-second` function.
- Cumulative counter: `sum` + `rate` (or `increase`).
- Histogram: `percentile`, no function.

See `CLI_TRANSLATION.md §"Counter-math cheat sheet"`.

## Subagent-output mistakes

### 9. Don't trust "fixed, 0 matches" self-reports

A subagent returning "fixed, 0 matches" means it believes its verification grep returned zero. **Sample 5–10 output files by eye** and verify independently. Specifically:

- Do the Golden signals cite metric names that actually exist in `tsuga metrics list`?
- Do the Monitor reproductions use monitor IDs that resolve via `tsuga monitors get`?
- Does at least one of the Ready-to-run commands execute cleanly when copied to a shell?

If any sample fails, the bug is in the template or subagent prompt, not the individual file. Regenerate the batch.

### 10. Don't fabricate when inputs are empty

When a subagent's helper JSON files are empty (`monitors.json: []`, `dashboards.json: []`, `incident-files.txt: ""`), it must NOT invent plausible content. Instead:

- Note the empty inputs in the Confidence section: "Source material quality: `monitors.json` and `dashboards.json` were empty at collect time. Monitor/dashboard references are inferred from TEAM_KNOWLEDGE.md, not direct probe."
- Keep the sections short + factual.
- Lean harder on live probes (`tsuga logs search` + `tsuga logs patterns`) to ground what's there.

The first pass had at least three files with fabricated content flagged this way in their Confidence notes. That's the correct outcome — visible low-confidence beats plausible-looking fabrication.

### 11. Don't invent headings or acronyms

Subagents coined:
- "rtk scans (ready-to-kick investigations)" — a made-up acronym embedded in a real section
- "Ad-hoc scans" — non-canonical section name
- "Post-mortem debrief" — non-canonical section name
- "Hot-take" — non-canonical section name

Reject these. Use only the canonical sections from `SERVICE_KNOWLEDGE_TEMPLATE.md`.

### 12. Live data overrides the task brief

The orchestrator's assumptions about what a service does can be wrong. For example, one subagent was told "`config-store` is the object-storage write-path for processed data" — but live logs showed it was actually the asset/policy reconciler (monitors, dashboards, routes, api-keys to S3/GCS/Azure Blob). The subagent correctly flipped the framing and documented the discrepancy in the Confidence note.

**Rule:** when live evidence contradicts the task brief, trust live evidence and document the contradiction clearly.

### 13. Low-incident-count services still need full dossiers

Just because a service has only 1–2 incidents in `incident-files.txt` doesn't mean the dossier is short. The live probes (Log shape, Golden signals, Ready-to-run) are the meat — incident shapes are bonus. A service with no incidents can still have a rich dossier built entirely from live data.

## Taxonomy / discovery mistakes

### 14. Don't prescribe the service list — derive it

First-pass `knowledge-company` used a prescribed list of 32 services ("the ones I think are important"). That misses:
- Services that used to be important but got renamed (e.g., embedded-engine roles vs first-party services).
- Services that are CRITICAL but have low log volume (e.g., small-traffic canaries).
- Services that got added since the last refresh.

Use the scoring in `PROCEDURE.md §"Phase 3"`: top-by-volume + monitor-named + incident-referenced. Union the three sources.

### 15. Team ownership vs monitor ownership vs service code repo

These three can all diverge. Worked example:

- `health-aggregator` is a **platform-team** service (Node.js in `acme-co/typescript`).
- But its P1 monitors (`wha7-mnq64-vpd6`, etc.) are **infra-team** owned — because they report SLIs of infra-owned services.
- And some related monitors (`cqqx-8vpd0-wwjr`) are **solution-team** owned.

Always cross-check the three axes. The service dossier lives under the team that owns the code repo. The monitor IDs should be looked up via `tsuga monitors get <id>` → `.owner` field, not assumed to match the service's team.

### 16. Engine roles are not first-party services

`indexer`, `searcher`, `metastore`, and similar role names come from an embedded search/storage engine, not first-party services. They appear as `context.service.name:<role>` with a `tech` tag set to the engine name, and may be scraped by a sidecar from the engine's pods. When the taxonomy scoring surfaces these, document them with a role/service distinction up front — readers will conflate otherwise.

### 17. Service-name collisions

A service can have two names in telemetry:

- K8s-scraped (Deployment/StatefulSet name): `app-order-ingest`
- OTel-self-reported (`OTEL_SERVICE_NAME`): `ingest`

A bare `context.service.name:ingest` misses the half emitted under the K8s name. The OR-match idiom must be in every probe:

```
(context.service.name:app-order-ingest OR context.service.name:ingest)
```

### 18. `context.app:python` is a cross-service namespace

Several Python services all emit `context.app:python`. A query with only that filter will match all of them at once. When documenting a Python service's log filter, always include `context.service.name` to narrow.

## Content mistakes

### 19. Don't duplicate from top-level docs

The cluster ↔ customer table, the notification-rule fanout, the canonical query patterns — all live in `COMPANY_TELEMETRY_KNOWLEDGE.md`. Per-service dossiers should reference them, not paste copies. A dossier under 300 lines is a strong hint that you're correctly pointing instead of duplicating.

### 20. Don't pad the Caveats section

Subagents fill space when they run out of real content. Caveats specifically attracts filler ("Always check logs first", "Use the dashboard"). **Service-specific only.** 5–10 bullets is the sweet spot.

### 21. Confidence notes are load-bearing

The first pass shipped several dossiers with vague Confidence notes. The best dossiers had tiered notes:

- **High:** explicit list of what was cross-validated against multiple authoritative sources.
- **Medium:** pulled from one source or docs but not re-probed.
- **Low / inferred:** guesses, flagged so the reader re-verifies.
- **What to refresh:** commands the next agent should run to update stale claims.

Insist on this structure.

### 22. Stale monitor filters

A monitor's query filter can point at code that no longer exists. Worked example: `event-relay`'s P1 monitor filters on `filename:src/api/v1/log.rs`, but live ERRORs now emit from `src/api/v2/log.rs`. The monitor is silent on the real failure path.

When writing Monitor reproduction sections, **run the monitor's filter live** and check it returns non-empty. If it's been silent for N days, flag it in Caveats.

## Process mistakes

### 23. Don't run subagents sequentially

32 service dossiers in a single thread takes a full working day. In parallel batches of 8–12 it takes under an hour. Fan out.

### 24. Don't skip the sampled-execution gate

`VERIFICATION.md §Gate 5` is sampled execution — copy 5 random commands from 5 random dossiers into a shell, confirm they run. This is the only gate that catches subagent hallucination of metric names and monitor IDs.

First-pass error: claimed success on all 32 dossiers based on the forbidden-token grep, then discovered on use that half the aggregation queries referenced metric names that didn't exist. Regenerate would have been faster than the hand-patching that ensued.

### 25. Don't claim "done" before pushing

The commit is not the end state. Push requires a human to have read 5 random dossiers cover-to-cover and confirmed coherence. Subagent output can be "valid-looking but vacuous" when inputs are thin; the human eye is the only reliable filter for this.

### 26. Keep the build procedure in version control

If the CLI syntax changes six months from now, you want to re-run this whole procedure and regenerate. Do not hand-edit individual SERVICE_KNOWLEDGE.md files; fix the template, regenerate. Any hand-edits get clobbered on the next rebuild.

### 27. Commit in logical chunks

One commit with 32 new files is painful to review. Prefer:

1. Top-level docs (`SKILL.md`, `COMPANY_*.md`) + skill scaffold.
2. `TEAM_KNOWLEDGE.md` × all teams.
3. `SERVICE_KNOWLEDGE.md` × all services (acceptable to be one commit if they're generated together).

## Data-hygiene mistakes

### 28. Don't copy customer PII into dossiers

Live log probes will return customer data. The Log shape section needs *an* example, not a real one — redact customer names / API keys / session IDs before pasting. `customer: <redacted>`, `usr.email: user@example.com` are the normal anonymizations.

### 29. Don't leak post-incident PR context

Same rule as `build-incident-history`'s LESSONS: if your investigation runtime is evaluated under a time-bound cheat-prevention block that forbids reading PRs ≥ `declared_at`, per-service dossiers referencing the latest fix PR for a known incident can leak that into the agent's context via retrieval. Reference PR numbers for brevity, not content.

### 30. Keep metric-inventory freshness notes honest

Metric emissions are sparse. A `tsuga metrics list` over 7 days might miss a rarely-emitted counter. When Golden signals cite a metric that wasn't in the sweep, note it: "not observed in the 7d `tsuga metrics list` window; may be sparse — cross-check the live dashboard before assuming absence."
