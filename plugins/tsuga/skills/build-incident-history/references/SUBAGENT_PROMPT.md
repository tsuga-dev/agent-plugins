# SUBAGENT_PROMPT — the exact per-incident subagent prompt

Copy verbatim. Substitute `{inc_id}` and `{company}`. The orchestrator fans out one of these per incident.

## Prompt template

````
Write a SUMMARY.md for {company} incident `{inc_id}`. This is one of many per-incident dossiers being generated in a single build of the `incident-history` skill.

**Output file:** `skills/incident-history/references/incidents/{inc_id}/SUMMARY.md` (create parent dir with `mkdir -p`).

**Also copy `metadata.json` verbatim:** `cp inputs/incidents/{inc_id}/metadata.json skills/incident-history/references/incidents/{inc_id}/metadata.json`

**MUST-READ references:**
1. `${CLAUDE_PLUGIN_ROOT}/skills/build-incident-history/references/SUMMARY_TEMPLATE.md` — canonical section list + exemplar.
2. `${CLAUDE_PLUGIN_ROOT}/skills/build-incident-history/references/LESSONS.md` — the failure modes to avoid.
3. `${CLAUDE_PLUGIN_ROOT}/skills/build-knowledge-company/references/CLI_TRANSLATION.md` — the contract every `tsuga` command you emit must satisfy.

**Inputs for this incident:**
- Raw: `inputs/incidents/{inc_id}/` — all source material (slack/, github/, tsuga/, incident-report.md, notes.md, metadata.json).
- Pre-digested helpers (if Phase 2 of the procedure was run): `/tmp/incident-extracts/{inc_id}/slack-flat.txt`, `prs-flat.txt`, `tsuga-commands.txt`.

**Procedure:**

1. Read `metadata.json` first — confirms `incident_id`, `declared_at`, `last_iso`, `title`, `severity`, `affected_services`, `affected_team`.
2. Skim the pre-digested helpers (if present) or the raw Slack thread to reconstruct the Timeline.
3. Extract the Diagnostic path from `tsuga/commands.txt` — this is the responder's actual command sequence. Translate every entry into real `tsuga` CLI using the table in CLI_TRANSLATION.md. Apply it to every probe, not just the ones that look wrong.
4. Write the SUMMARY.md in the canonical section order, following SUMMARY_TEMPLATE.md.

If the responder's original commands are not recoverable, **do NOT invent them**. Write a one-line note in the Diagnostic path section:

> _No command log captured for this incident. Reconstruction would be invention — flagged in Confidence._

And add a `## Confidence` section at the bottom: "low — Diagnostic path not recoverable from inputs."

**Required structure:** exactly the section list in SUMMARY_TEMPLATE.md, in that order, no additions. `## Diagnostic path` is the payload. Every heading is present even when its content is one line — never delete a heading.

**Length target:** under 400 lines. Overflow usually comes from unedited Slack dumps — trim. Never sacrifice the Diagnostic path to save length.

**Rules** (LESSONS.md explains why each one matters):

- **No post-incident-PR leakage.** Reference the resolution PR number; do NOT paste its title, body, or diff.
- **Preserve Slack quotes verbatim.** Do not paraphrase, and do not replace a named person with a role.
- **Redact PII.** Replace customer API keys, user emails and session IDs with `<redacted>` before pasting a sample log line.

**Verification (MUST run before declaring done):**

```bash
D="skills/incident-history/references/incidents/{inc_id}"

# Command shape: the shared checker, scoped to just this incident's folder.
"${CLAUDE_PLUGIN_ROOT}/skills/check-skill-health/scripts/check-forbidden-tokens.sh" "$D"

# Canonical sections present. This checks presence only, not order.
for h in "## Incident at a glance" "## Timeline" "## Paging surface during incident" \
         "## Diagnostic path" "## Root cause" "## Remediation" "## Lessons / follow-ups"; do
  grep -qxF "$h" "$D/SUMMARY.md" || echo "MISSING: $h"
done

[ -f "$D/metadata.json" ] || echo "MISSING metadata.json"
```

The checker must print `PASS`, and nothing else in the block may print anything.

**Return** a 2–3 sentence summary:
- Line count + whether Diagnostic path was recoverable (N probes) or not.
- Number of timeline events, monitors cited.
- Confidence level you'd assign this SUMMARY (high/medium/low) and the reason.
````

## Notes for the orchestrator

- **Batch size:** 10–20 in parallel. Incidents are smaller tasks than service dossiers; wider batches fit.
- **`{company}`:** substitute with the company name (e.g., "Tsuga"). Used in the Incident-at-a-glance framing.
- **Progress tracking:** for batches in the 100+ range, use TodoWrite entries per wave of 20. Mark each wave complete only after the 5-random-file gate in `VERIFICATION.md` passes for that wave — not the moment the subagent returns "done".
- **Failures:** a subagent claiming success on a low-quality input (empty `tsuga/commands.txt`, no slack thread) must have produced a SUMMARY.md with explicit low-confidence notes — not fabricated content. Spot-check for this.
