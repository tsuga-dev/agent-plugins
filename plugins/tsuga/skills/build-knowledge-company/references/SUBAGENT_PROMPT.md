<!-- skill-lint: allow-forbidden-examples — this file contains the verification greps (which reference the forbidden patterns) -->

# SUBAGENT_PROMPT — the exact per-service subagent prompt

Copy this verbatim. Substitute `{svc}`, `{team}`, `{team_id}`, `{team_repo}`. Do not edit anything else. The orchestrator's job is to fan out dozens of these in parallel.

## Prompt template

```
Write a SERVICE_KNOWLEDGE.md dossier for the {company} service `{svc}` (owning team: `{team}`, team id `{team_id}`). This is one of ~{N} per-service dossiers that go under the `knowledge-company` skill.

**Output file:** `skills/knowledge-company/references/teams/{team}/services/{svc}/SERVICE_KNOWLEDGE.md` (create parent dir with `mkdir -p`).

**MUST-READ references (in order, before writing anything):**
1. `${CLAUDE_PLUGIN_ROOT}/skills/build-knowledge-company/references/SERVICE_KNOWLEDGE_TEMPLATE.md` — the canonical section list and every section's rules.
2. `${CLAUDE_PLUGIN_ROOT}/skills/build-knowledge-company/references/CLI_TRANSLATION.md` — every command you write must be real `tsuga` CLI, not MCP-tool pseudo-syntax. Follow this contract.
3. `${CLAUDE_PLUGIN_ROOT}/skills/build-knowledge-company/references/LESSONS.md` — read the full list. Every mistake listed cost us time on a previous run.

**Per-service helper inputs (pre-extracted for you):**
- Monitors targeting this service: `/tmp/service-data/{svc}/monitors.json`
- Dashboards: `/tmp/service-data/{svc}/dashboards.json`
- Incident SUMMARY.md files referencing this service: `/tmp/service-data/{svc}/incident-files.txt` (read the top 5 most relevant; focus on their `## Diagnostic path` sections)

**Top-level context (skim, don't duplicate from):**
- `skills/knowledge-company/references/COMPANY_GENERAL_KNOWLEDGE.md`
- `skills/knowledge-company/references/COMPANY_TELEMETRY_KNOWLEDGE.md`

**Team context:**
- `skills/knowledge-company/references/teams/{team}/TEAM_KNOWLEDGE.md`

**Live probes you MUST run** (before writing — this grounds the dossier in reality):

```bash
# 1. Log shape + volume in the last 7 days
tsuga logs search --query "context.env:prod context.service.name:{svc}" --from -7d --max-results 50

# 2. Top error patterns in the last 24h
tsuga logs patterns --query "context.env:prod context.service.name:{svc} level:ERROR" --from -24h

# 3. Active metric namespace
tsuga metrics list | jq '.[] | select(.name | startswith("{svc-prefix}_"))'

# 4. Service metadata (team membership, 24h counters)
tsuga services list | jq '.[] | select(.serviceName == "{svc}")'
```

Do not skip these. The Golden signals, Log shape, and Metric-namespace sections all depend on the live output. If a live probe returns empty, **say so in the Confidence note** — do not invent replacement content.

**Required output structure** (canonical section list from SERVICE_KNOWLEDGE_TEMPLATE.md):

1. `# Service — {svc}`
2. `## Quick context` — identity table + 1–2 paragraph framing
3. `## Ready-to-run` — subsections: "Is it healthy?", "Monitor reproduction", "Incident-drill queries"
4. `## Golden signals` — traffic / errors / latency / saturation table
5. `## Log shape` — top 3–5 patterns with examples from live probe
6. `## Dashboards` — the ones actually worth opening
7. `## Upstream / downstream` — ASCII flow or bullet list
8. `## Incident shapes` — 2–4 from `incident-files.txt`
9. `## Caveats, footguns, known behaviors` — 5–10 service-specific bullets
10. `## Confidence note` — what's grounded vs. inferred, what to re-verify

**Length target:** 180–350 lines. If you hit 350, the first cuts are: padded Caveats, duplicated content from top-level docs, speculative incident shapes.

**Verification (you MUST run this before declaring done):**

```bash
F="skills/knowledge-company/references/teams/{team}/services/{svc}/SERVICE_KNOWLEDGE.md"

# Forbidden MCP-tool verbs
grep -nE '^(search-logs|search-spans|list-metrics|get-metric|list-monitors|get-monitor|list-dashboards|get-dashboard|list-routes|list-teams|list-services|get-service|list-notification-rules|list-notification-silences|aggregate-scalar|aggregate-timeseries|list-log-patterns|list-new-error-patterns|list-error-pattern-increases)\b' "$F"

# Forbidden MCP-tool arg shapes (but OK inside JSON bodies)
grep -nE '\bquery=|\bfrom=-|\b to=now\b|\blimit=|\bfilter=|\baggregationWindow=|\bdataSource=' "$F" \
  | grep -v '"aggregationWindow":' \
  | grep -v '"dataSource":' \
  | grep -v '"filter":' \
  | grep -v '/explorer?query='

# Forbidden rtk prefix
grep -nE '^rtk |[[:space:]]rtk ' "$F"

# Canonical sections present
for h in "## Quick context" "## Ready-to-run" "## Golden signals" "## Log shape" "## Dashboards" "## Upstream / downstream" "## Incident shapes" "## Caveats, footguns, known behaviors" "## Confidence note"; do
  grep -qF "$h" "$F" || echo "MISSING HEADING: $h"
done
```

All four must return zero hits. If any fail, fix and re-check before declaring done.

**Additionally, execute one command from your own output** to prove it runs:

```bash
# Pick any bash block from Ready-to-run, run it. Confirm it parses and returns a valid response (empty is fine).
```

**Return** a 3–5 sentence summary covering:
- Line count + byte count of the output file.
- How many monitors cited (by ID) + how many incidents cited (by INC-id).
- Any surprises or live-data/task-brief discrepancies you documented in the Confidence note.
- Confirmation that the verification greps all returned zero hits.
```

## Notes for the orchestrator

- **Batch size:** 8–12 subagents in parallel. Wider risks MCP rate limits; narrower wastes wall-clock.
- **`{N}`:** substitute with the actual count from `/tmp/services-to-dossier.txt` — subagents reading "one of ~30" calibrate differently than "one of ~100".
- **`{svc-prefix}`:** the prefix you expect the service's metrics to use (`intake_`, `web_backend_`, `bridge_`). If the service has no metric namespace, omit that probe from the prompt.
- **Failure handling:** if a subagent returns claiming "fixed, 0 matches" but a sampled `tsuga` command doesn't run, the template has a fleet-wide bug. Do NOT hand-patch the output. Fix the template (likely `SERVICE_KNOWLEDGE_TEMPLATE.md` or `LESSONS.md`) and regenerate the affected batch.
- **Progress tracking:** the first-pass build used one TodoWrite entry per wave of 8 subagents. Mark each wave complete only after its VERIFICATION.md sampled-execution gate passes for 2 random members.
