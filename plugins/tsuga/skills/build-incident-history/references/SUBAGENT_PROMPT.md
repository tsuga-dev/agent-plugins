<!-- skill-lint: allow-forbidden-examples — this prompt enumerates forbidden patterns for the agent to avoid -->

# SUBAGENT_PROMPT — the exact per-incident subagent prompt

Copy verbatim. Substitute `{inc_id}` and `{company}`. The orchestrator fans out one of these per incident.

## Prompt template

```
Write a SUMMARY.md for {company} incident `{inc_id}`. This is one of many per-incident dossiers being generated in a single build of the `incident-history` skill.

**Output file:** `skills/incident-history/references/incidents/{inc_id}/SUMMARY.md` (create parent dir with `mkdir -p`).

**Also copy `metadata.json` verbatim:** `cp inputs/incidents/{inc_id}/metadata.json skills/incident-history/references/incidents/{inc_id}/metadata.json`

**MUST-READ references:**
1. `${CLAUDE_PLUGIN_ROOT}/skills/build-incident-history/references/SUMMARY_TEMPLATE.md` — canonical section list + exemplar.
2. `${CLAUDE_PLUGIN_ROOT}/skills/build-incident-history/references/LESSONS.md` — every mistake from previous runs.

**Inputs for this incident:**
- Raw: `inputs/incidents/{inc_id}/` — all source material (slack/, github/, tsuga/, incident-report.md, notes.md, metadata.json).
- Pre-digested helpers (if Phase 2 of the procedure was run): `/tmp/incident-extracts/{inc_id}/slack-flat.txt`, `prs-flat.txt`, `tsuga-commands.txt`.

**Procedure:**

1. Read `metadata.json` first — confirms `incident_id`, `declared_at`, `last_iso`, `title`, `severity`, `affected_services`, `affected_team`.
2. Skim the pre-digested helpers (if present) or the raw Slack thread to reconstruct the Timeline.
3. Extract the Diagnostic path from `tsuga/commands.txt` — this is the responder's actual command sequence. Translate each to real `tsuga` CLI syntax (no MCP-tool pseudo-syntax, no `rtk` prefix; see LESSONS.md §"Command-shape mistakes").
4. Write the SUMMARY.md in the canonical section order, following SUMMARY_TEMPLATE.md.

**Command translations to apply on every probe in Diagnostic path:**

| MCP-tool shape | Real `tsuga` CLI |
|---|---|
| `search-logs query="X" from=-1h to=now limit=20` | `tsuga logs search --query "X" --from -1h --to now --max-results 20` |
| `search-spans …` | `tsuga traces search --query "…" …` (note: traces, not spans) |
| `list-metrics` / `get-metric X` | `tsuga metrics list` / `tsuga metrics get X` |
| `list-monitors` / `get-monitor X` | `tsuga monitors list` / `tsuga monitors get X` (plural!) |
| `aggregate-scalar|timeseries …` | heredoc → `/tmp/q.json` + `tsuga aggregation {scalar,timeseries} -f /tmp/q.json` with Unix-seconds `timeRange` |

If the responder's original commands are not recoverable, **do NOT invent them**. Write a one-line note in the Diagnostic path section:

> _No command log captured for this incident. Reconstruction would be invention — flagged in Confidence._

And add a Confidence note at the bottom: "low — Diagnostic path not recoverable from inputs."

**Required structure (canonical section list):**

1. `# {inc_id} — {title}`
2. Identity table (declared/resolved/severity/services/team/customer/PR)
3. `## Incident at a glance`
4. `## Timeline`
5. `## Paging surface during incident`
6. `## Diagnostic path` ← the payload
7. `## Root cause`
8. `## Remediation` (immediate + durable)
9. `## Lessons / follow-ups`
10. `## Commentary` (optional, italicized)

**Length target:** under 400 lines. Overflow usually comes from unedited Slack dumps — trim. Never sacrifice the Diagnostic path to save length.

**Rules:**

- **No post-incident-PR leakage.** Reference the resolution PR number; do NOT paste its title, body, or diff. If your investigation runtime is evaluated under a time-bound cheat-prevention block, leaking answer-key content poisons future benchmarking.
- **Preserve Slack quotes verbatim.** If the thread says "Alex ran the reconcile", don't rewrite it as "the on-call engineer triggered a reconcile". Analogue search depends on the reader recognizing familiar phrases.
- **Redact PII.** Replace customer API keys, user emails, session IDs with `<redacted>` before pasting sample log lines.
- **Every section heading must be present**, even if one-line. Never delete a heading.

**Verification (MUST run before declaring done):**

```bash
F="skills/incident-history/references/incidents/{inc_id}/SUMMARY.md"

# Forbidden MCP-tool shapes
grep -nE "^(search-logs|search-spans|list-metrics|get-metric|list-monitors|get-monitor|list-dashboards|get-dashboard|aggregate-scalar|aggregate-timeseries|list-log-patterns|list-new-error-patterns|list-error-pattern-increases)\b" "$F"

# Pseudo-syntax arg shape
grep -nE "\bquery=|\bfrom=-|\b to=now\b|\blimit=|\bfilter=|\baggregationWindow=|\bdataSource=" "$F" \
  | grep -v '"aggregationWindow":' \
  | grep -v '"dataSource":' \
  | grep -v '"filter":' \
  | grep -v '/explorer?query='

# rtk prefix
grep -nE "^rtk |[[:space:]]rtk " "$F"

# Canonical sections
for h in "## Incident at a glance" "## Timeline" "## Paging surface during incident" "## Diagnostic path" "## Root cause" "## Remediation" "## Lessons / follow-ups"; do
  grep -qF "$h" "$F" || echo "MISSING: $h"
done

# metadata.json copied
[ -f "skills/incident-history/references/incidents/{inc_id}/metadata.json" ] || echo "MISSING metadata.json"
```

All four must return zero / clean output.

**Return** a 2–3 sentence summary:
- Line count + whether Diagnostic path was recoverable (N probes) or not.
- Number of timeline events, monitors cited.
- Confidence level you'd assign this SUMMARY (high/medium/low) and the reason.
```

## Notes for the orchestrator

- **Batch size:** 10–20 in parallel. Incidents are smaller tasks than service dossiers; wider batches fit.
- **`{company}`:** substitute with the company name (e.g., "Tsuga"). Used in the Incident-at-a-glance framing.
- **Progress tracking:** for batches in the 100+ range, use TodoWrite entries per wave of 20. Mark each wave complete only after the 2-random-file execution gate of `VERIFICATION.md` passes for that wave — not the moment the subagent returns "done".
- **Failures:** a subagent claiming success on a low-quality input (empty `tsuga/commands.txt`, no slack thread) must have produced a SUMMARY.md with explicit low-confidence notes — not fabricated content. Spot-check for this.
