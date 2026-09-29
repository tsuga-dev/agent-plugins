# PROCEDURE — phases for building incident-history

Ordered. Each phase has a clear completion signal. Do not skip ahead; later phases assume earlier ones' invariants.

## Phase 0 — sanity check the input

Before touching the output tree. A subagent cannot produce a usable SUMMARY.md without `declared_at` and `last_iso`, so every incident folder needs a well-formed `metadata.json` (fields in `INPUT_LAYOUT.md`) or it is excluded from the run.

```bash
INPUTS=./inputs/incidents

for d in "$INPUTS"/INC-*/; do
  jq -e '.incident_id and .declared_at and .last_iso' "$d/metadata.json" >/dev/null 2>&1 \
    || echo "UNUSABLE: $(basename "$d")"
done
```

**Expected:** no output. Anything listed is a loader-script bug — fix it before fanning out, rather than letting the subagent guess.

## Phase 1 — prepare the output tree

```bash
OUTPUT=./skills/incident-history/references/incidents
mkdir -p "$OUTPUT"
```

If `$OUTPUT` already has folders from a previous run, decide: (a) incremental — only process incidents not yet in `$OUTPUT`; (b) clean rebuild — `rm -rf "$OUTPUT"/INC-*` first. Incremental is safer for production archives.

## Phase 2 — per-incident helper extraction (optional but recommended)

For each incident, pre-digest the raw inputs into smaller per-incident helper files that the subagent can skim without re-reading 10 MB of raw Slack JSON. Prechewing the input is the single largest reduction in subagent context burn available here.

Example helper script skeleton. Keep it outside this skill — it is ops-side glue — but keep it in version control, because a rebuild needs the same pre-digest to be reproducible.

```bash
for inc in "$INPUTS"/INC-*/; do
  inc_id=$(basename "$inc")
  rm -rf "/tmp/incident-extracts/$inc_id"
  mkdir -p "/tmp/incident-extracts/$inc_id"

  # Flatten Slack thread to one line per message, most important first
  jq -sr 'map(.messages) | add | sort_by(.ts) | .[] | "\(.ts) [\(.user_profile.real_name // .username // .user)] \(.text)"' \
    "$inc"/slack/thread-*.json > "/tmp/incident-extracts/$inc_id/slack-flat.txt" 2>/dev/null

  # Flatten PRs to title/author/merge-date/url. `mergedAt` is only present if the capture
  # requested it (`gh pr list --json number,state,title,mergedAt,url`).
  jq -r '.[] | "#\(.number) [\(.state)] \(.title) (merged=\(.mergedAt // "n/a")) \(.url)"' \
    "$inc/github/prs.json" > "/tmp/incident-extracts/$inc_id/prs-flat.txt" 2>/dev/null

  # tsuga/commands.txt is already flat — just copy
  cp "$inc/tsuga/commands.txt" "/tmp/incident-extracts/$inc_id/tsuga-commands.txt" 2>/dev/null
done
```

## Phase 3 — fan out subagents

**One subagent per incident, run in parallel.** Batch 10–20 at a time; each subagent has less to do than a service dossier, so wider waves are fine if the host tolerates them. Keep the batch size consistent with `SUBAGENT_PROMPT.md`.

Each subagent gets:

- `inc_id` (the directory name)
- Raw-input path: `inputs/incidents/<inc_id>/`
- Helper path: `/tmp/incident-extracts/<inc_id>/` (if Phase 2 was run)
- Output path: `skills/incident-history/references/incidents/<inc_id>/SUMMARY.md`
- Canonical template: `${CLAUDE_PLUGIN_ROOT}/skills/build-incident-history/references/SUMMARY_TEMPLATE.md`
- The lessons doc: `${CLAUDE_PLUGIN_ROOT}/skills/build-incident-history/references/LESSONS.md`
- The verification doc: `${CLAUDE_PLUGIN_ROOT}/skills/build-incident-history/references/VERIFICATION.md`

The subagent's contract is in `SUBAGENT_PROMPT.md` — do not retype it; copy verbatim and substitute the `{inc_id}` and `{company}` placeholders.

## Phase 4 — write `metadata.json` + `_inventory.csv`

Each subagent should copy `inputs/incidents/<inc_id>/metadata.json` into `skills/incident-history/references/incidents/<inc_id>/metadata.json` verbatim (no transformation). This is what `entrypoint.sh`'s snapshot-filter reads.

After all subagents return, generate the inventory:

```bash
OUTPUT=./skills/incident-history/references/incidents
{
  echo "incident_id,title,declared_at,last_iso,severity,affected_team,affected_services"
  for f in "$OUTPUT"/INC-*/metadata.json; do
    jq -r '[.incident_id, .title, .declared_at, .last_iso, .severity, .affected_team, ((.affected_services // []) | join(";"))] | @csv' "$f"
  done
} > "$OUTPUT/_inventory.csv"
```

## Phase 5 — verification

Run `VERIFICATION.md`'s gates. All must pass before you ship. The gate that catches most build bugs is the sampled execution of `## Diagnostic path` commands: a subagent that wrote pseudo-syntax, or that cited a metric / service / monitor absent from the account, fails there.

## Phase 6 — cross-link with knowledge-company

The dependency is one-way, so do not run the two builds in parallel: `knowledge-company`'s build greps this archive's SUMMARY files for service-name mentions and pre-builds a per-service incident list. Finish `incident-history` first, then build `knowledge-company`, which takes it as an input (see `${CLAUDE_PLUGIN_ROOT}/skills/build-knowledge-company/references/INPUT_LAYOUT.md`).

## Phase 7 — commit

One git commit for the batch, with a commit body that lists the incident count and the date range covered. If the archive is large (>50 incidents), split into commits per-year or per-quarter so future diffs are reviewable.

Do not push until `VERIFICATION.md`'s Gate 6 (human eyeball) has been done by a person.
