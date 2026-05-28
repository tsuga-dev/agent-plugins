<!-- skill-lint: allow-forbidden-examples — this prompt enumerates forbidden patterns for the agent to avoid -->

# RECOMMENDED_PROMPT — ready-to-paste prompt for bootstrapping incident-history

Copy the block below verbatim into Claude (or Codex) when you're ready to bootstrap or refresh the `incident-history` skill. Substitute the `<…>` placeholders before pasting.

The prompt couples the **build** skill with the **health-check** skill — the agent runs the full procedure, then lints the output, reports both.

---

## Prompt to paste

```
You are bootstrapping the runtime `incident-history` skill for this repository. Follow both skills listed below end-to-end in a single session. Do not declare done until the health check passes.

Repo root: <absolute path to your investigation-agent checkout, e.g. /Users/me/projects/my-investigation-agent>
Raw incident inputs: <absolute path where I dropped the raw dump, e.g. /Users/me/projects/my-investigation-agent/inputs/incidents>
Output target: `skills/incident-history/references/incidents/` inside the repo.

Phase 1 — build:
Use the `$build-incident-history` skill. Specifically:
1. Read `setup-skills/build-incident-history/SKILL.md` and every file under `setup-skills/build-incident-history/references/`.
2. Execute the phases in `PROCEDURE.md` in order. Do NOT skip Phase 0 (sanity check) or Phase 5 (verification).
3. Fan out per-incident SUMMARY.md writing to parallel subagents — batches of 10–20. Each subagent gets one INC-id, the template, and the lessons doc. Prompt template is in `SUBAGENT_PROMPT.md`; copy verbatim, substitute `{inc_id}` and `{company}`.
4. Before subagent fan-out, optionally run Phase 2 (per-incident helper extraction) to pre-digest raw inputs into `/tmp/incident-extracts/<inc_id>/`. This is faster than having each subagent parse the raw JSON.
5. After fan-out, run Phase 4 to emit `_inventory.csv`.

Phase 2 — health check:
Use the `$check-skill-health` skill. Specifically:
1. Run `setup-skills/check-skill-health/scripts/lint-all.sh skills/incident-history/`.
2. If any FAIL appears, do NOT hand-edit the affected file. Find the root cause in the template / subagent prompt / lessons doc, fix it there, regenerate the affected incidents via subagent, then re-run lint. Iterate until `lint-all.sh` returns exit code 0.
3. WARNs are informational — read them, decide whether to fix or annotate as intentional.

Phase 3 — report:
Return a concise summary:
- Incident count processed + how many folders shipped.
- Any failures from the lint pass and what you did about them.
- Any incidents whose Diagnostic path could NOT be recovered from the raw inputs — these should have explicit low-confidence notes in their SUMMARY.md. List them.
- The commit you made (or the diff you staged).

Hard rules for the whole flow:
- Every `tsuga` command you emit must be real CLI. No MCP-tool pseudo-syntax (`search-logs`, `aggregate-timeseries`, `query=`, `from=-`, `limit=`). No `rtk` prefix. `setup-skills/build-knowledge-company/references/CLI_TRANSLATION.md` has the full translation contract.
- No leakage of post-incident PR content (titles, bodies, diffs) into SUMMARY.md. Reference the PR number only. If your investigation runtime is evaluated under a time-bound cheat-prevention block, leaking fixes poisons future benchmarking.
- Scrub PII before ingesting: customer API keys, user emails, session IDs must be redacted.
- Do not delete anything outside `skills/incident-history/`. Do not touch any other skill.
- If you hit a phase that seems impossible with the available inputs, STOP and ask rather than invent.
```

---

## Where to put raw data

Local paths, in order of preference:

1. **`inputs/incidents/`** at the repo root — a local directory you drop exports into. Not committed (add to `.gitignore`). Good for one-off bootstraps.
2. **Mounted volume** if running inside the docker-compose flow — mount the raw dump at `/mnt/inputs/incidents/` and symlink to `./inputs/incidents/` before kicking off.
3. **Remote (S3 / Drive)** — sync down to `inputs/incidents/` first, don't try to stream during the build. Subagents expect a local filesystem.

The expected per-incident layout (Slack JSON, github/, tsuga/commands.txt, etc.) is in `setup-skills/build-incident-history/references/INPUT_LAYOUT.md`. Don't improvise the shape.

## Operator notes

- **First bootstrap** will take 30–90 minutes depending on incident count and subagent parallelism. Budget accordingly.
- **Refresh** (new incidents only) — set your output-tree check to "incremental" in Phase 1 of `PROCEDURE.md` so existing SUMMARY.md files are not regenerated.
- **Full rebuild** — when the template or canonical section list changes, rebuild is cheaper than hand-patching 100+ files. Let the procedure run.
