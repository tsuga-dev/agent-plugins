<!-- skill-lint: allow-forbidden-examples — this file documents the forbidden patterns as teaching examples -->

# LESSONS — hard-won mistakes from the first `incident-history` build

Read all of these before running the procedure. Every one of them cost us time on a first pass.

## Command-shape mistakes

### 1. MCP-tool pseudo-syntax is not `tsuga` CLI

When an agent has access to the Tsuga MCP tools (`mcp__tsuga__search-logs`, `mcp__tsuga__aggregate-timeseries`, etc.), it will naturally reach for that shape when writing "ready-to-run commands" — producing output like:

```
search-logs query='context.service.name:report-generator' from=-24h to=now limit=50
```

**This is not runnable.** The real CLI is:

```bash
tsuga logs search --query "context.service.name:report-generator" --from -24h --to now --max-results 50
```

Translation table the subagent MUST follow:

| MCP-tool shape | Real `tsuga` CLI |
|---|---|
| `search-logs query=X from=-1h to=now limit=N` | `tsuga logs search --query "X" --from -1h --to now --max-results N` |
| `search-spans …` | `tsuga traces search --query "…" --from … --max-results …` |
| `list-metrics` | `tsuga metrics list` |
| `get-metric name=X` | `tsuga metrics get X` |
| `list-monitors` / `get-monitor id=X` | `tsuga monitors list` / `tsuga monitors get X` (note the plural "monitors"!) |
| `list-dashboards` / `get-dashboard id=X` | `tsuga dashboards list` / `tsuga dashboards get X` |
| `list-routes`, `list-teams`, `list-services`, `list-notification-rules` | all singular→plural: `tsuga routes list`, `tsuga teams list`, etc. |
| `aggregate-scalar dataSource=logs aggregate=count filter="X"` | heredoc into `/tmp/q.json` + `tsuga aggregation scalar -f /tmp/q.json` |
| `aggregate-timeseries dataSource=metrics aggregationWindow=5m …` | heredoc + `tsuga aggregation timeseries -f /tmp/q.json`, body has `aggregationWindow: "5m"` |

The forbidden-token grep in `VERIFICATION.md` catches this. If any forbidden token appears, regenerate.

### 2. `--limit` is wrong. Use `--max-results`.

Easy to paste from memory and get wrong.

### 3. `tsuga spans search` does not exist. It's `tsuga traces search`.

The data source is "spans" in the TQL sense but the CLI command is `traces search`.

### 4. Singular vs plural resource names

`tsuga monitor get X` is wrong. The CLI follows the pattern `tsuga <resources-plural> <verb>`: `tsuga monitors get`, `tsuga dashboards list`, `tsuga routes get`, `tsuga teams list`, `tsuga services get`, etc. Always plural.

### 5. `rtk` prefix is noise in docs

The RTK hook rewrites commands transparently at execution time. Writing `rtk tsuga logs search …` in a dossier / SUMMARY.md is redundant and confuses human readers who don't have the hook. Always emit plain `tsuga …`.

### 6. Aggregation gotchas

- `timeRange` in the JSON body requires **Unix seconds integers**, not relative strings like `"-1h"`. Use the helper:
  ```bash
  FROM=$(date -u -v-1H +%s); TO=$(date -u +%s)   # macOS
  # Linux: FROM=$(date -u -d '1 hour ago' +%s); TO=$(date -u +%s)
  ```
- `groupBy` goes at body level, not inside query items: `"groupBy": [{"fields": ["context.cluster_id"], "limit": 10}]`.
- `functions` (like `rate`, `per-second`) go per-query: `"functions": [{"type": "rate"}]`.
- `formula` is at body level and references queries by position (`"q1"`, `"q2"`, …).
- `count` aggregate is **not valid** on `metrics` dataSource. Use `sum` instead for metrics. `count` is fine on `logs` / `traces`.
- `dataSource` is `"logs"`, `"traces"`, or `"metrics"` — not `"spans"`.

### 7. Duration units in queries

Trace span `duration` is in **milliseconds**. A query like `duration:>10s` is wrong; it's `duration:>10000`. Same for any metric that names a unit suffix.

## Content mistakes

### 8. Don't fabricate when inputs are empty

If the responder's `tsuga/commands.txt` is missing or empty for an incident, the subagent must NOT invent a plausible-looking Diagnostic path. It must:

- Leave the Diagnostic path section empty except for a one-line note:
  > _No command log captured for this incident. Reconstruction would be invention — flagged in Confidence._
- Add a Confidence note at the bottom of the SUMMARY.md: "low — Diagnostic path not recoverable from inputs."

A SUMMARY.md with an honest empty section is far more useful than one with hallucinated probes, because the retrieval layer can filter out low-confidence entries from analogue search.

### 9. Don't invent headings or acronyms

The template in `SUMMARY_TEMPLATE.md` has a fixed section list. Subagents will improvise — coining section names like "Post-mortem debrief", "rtk scans (ready-to-kick investigations)", "Hot-take". Do not allow these. Use the canonical set exactly.

If a section has no content for a given incident, write one line (e.g., "None — no monitors paged during this incident") and move on. Do not delete the heading.

### 10. Don't paraphrase Slack quotes

Analogue search depends on the reader recognizing familiar phrases ("RDS failover started", "cannot find namespace", specific customer names). Preserve the original text. If the Slack thread says "Alex ran the reconcile", don't rewrite it as "the on-call engineer triggered a reconcile".

### 11. Don't leak post-incident PR context

If your investigation runtime wraps prompts in a time-bound cheat-prevention block that forbids the agent from reading PRs dated ≥ `declared_at`, pasting the full diff of the resolution PR into the Root cause section poisons future evaluation runs.

Reference the PR number + one-line description. Do not paste the diff, title, or body. The responder's observations at the time of the incident are acceptable; the post-facto PR is not.

### 12. Watch for service-name collisions

A service can have two names in telemetry:

- The K8s-scraped name (Deployment/StatefulSet): `app-order-ingest`
- The OTel-self-reported short name (`OTEL_SERVICE_NAME`): `ingest`

When writing a Diagnostic path probe, use the OR-match idiom:

```bash
tsuga logs search --query "(context.service.name:app-order-ingest OR context.service.name:ingest) level:ERROR" --from -1h
```

If the responder's original probe used only one form and that caused them to miss a subset, note this in the Findings — it's the most common source of "we couldn't see half the problem" confusion.

### 13. Engine roles are not first-party services

`indexer`, `searcher`, `metastore`, and similar role names come from an embedded search/storage engine, not first-party services. They show up as `context.service.name:<role>` with a `tech` tag set to the engine. When the incident narrative names one of these, call out the role/service distinction — readers will confuse them otherwise.

## Process mistakes

### 14. Don't run subagents sequentially

A batch of 150–200 incidents in a single thread takes days. Fan out. 20 parallel subagents finishes in under an hour, with the bottleneck being the slowest individual incident.

### 15. Don't trust subagent self-reports

A subagent returning "fixed, 0 matches" does not mean the work is correct. It means the subagent believes its verification grep returned zero. Sample 5–10 output files by eye and verify independently.

Specific things to eyeball:

- Does the Diagnostic path look like plausible probes, or like generic boilerplate?
- Do the monitor IDs / metric names actually exist? (Run `tsuga monitors get <id>` on one at random.)
- Does the narrative match the template length budget, or is it 80 lines of fluff?

### 16. Don't push without testing sampled Diagnostic paths

Pick 5 random SUMMARY.md files. Copy-paste every `tsuga` command from each one into a shell and confirm it executes. If any fails, that's a fleet-wide bug in the subagent's output — regenerate the batch, don't hand-patch.

### 17. Cache-warm before fanning out

Each subagent does similar initial reads (template, lessons doc, procedure doc). Running them in parallel after a lead-in warm-up is cheaper than cold-starting each. If your infra permits, touch all reference files once at the start of Phase 3.

## Data-hygiene mistakes

### 18. Scrub PII and credentials before ingesting

Once a SUMMARY.md is committed, pulling it back out is painful. Run a pre-ingest scrubber over the raw inputs:

```bash
# Trivial sanity check — does any input contain what looks like an API key or PII?
grep -rIE "(sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|eyJ[A-Za-z0-9_-]+\.eyJ|[\w.-]+@[\w.-]+\.\w+)" inputs/ | head
```

Not exhaustive, but catches the obvious cases. Add project-specific patterns.

### 19. Don't ingest multi-incident Slack threads

Sometimes one Slack channel discussed two unrelated incidents simultaneously. Split into two folders before running the procedure. Subagents given merged threads will produce mangled SUMMARY.md files that conflate two root causes.

### 20. Keep the archive reproducible

The procedure is meant to be re-runnable. If a downstream CLI or service gets renamed six months from now, you want to re-run the whole batch and regenerate — not manually edit 174 files. So: keep your pre-digest scripts (Phase 2) in version control alongside this skill, and note any ad-hoc hand-edits in the commit message so future runs can decide whether to preserve them.
