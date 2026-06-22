<!-- skill-lint: allow-forbidden-examples — procedure references forbidden patterns when describing common failures -->

# PROCEDURE — phases for building incident-history

Ordered. Each phase has a clear completion signal. Do not skip ahead; later phases assume earlier ones' invariants.

## Phase 0 — sanity check the input

Before touching the output tree:

```bash
INPUTS=./inputs/incidents

# How many incident folders?
ls "$INPUTS" | grep -c '^INC-'

# How many have metadata.json?
find "$INPUTS" -maxdepth 2 -name metadata.json | wc -l

# Which incidents are missing metadata.json (they must be excluded)
for d in "$INPUTS"/INC-*/; do
  [ ! -f "$d/metadata.json" ] && echo "MISSING: $(basename "$d")"
done
```

**Expected:** metadata.json count == incident folder count. Any missing → fix before continuing. A subagent cannot produce a usable SUMMARY.md without `declared_at` and `last_iso`.

Validate one metadata.json by hand:

```bash
jq -e '.incident_id and .declared_at and .last_iso' "$INPUTS/INC-0001/metadata.json"
```

Should print `true`. If not, the loader script emitted malformed JSON — fix it before fanning out.

## Phase 1 — prepare the output tree

```bash
OUTPUT=./skills/incident-history/references/incidents
mkdir -p "$OUTPUT"
```

If `$OUTPUT` already has folders from a previous run, decide: (a) incremental — only process incidents not yet in `$OUTPUT`; (b) clean rebuild — `rm -rf "$OUTPUT"/INC-*` first. Incremental is safer for production archives.

## Phase 2 — per-incident helper extraction (optional but recommended)

For each incident, pre-digest the raw inputs into smaller per-incident helper files that the subagent can skim without re-reading 10 MB of raw Slack JSON. This is what separated "slow subagents" from "fast subagents" during the `knowledge-company` build — prechewing input 10× reduces subagent context burn.

Example helper script skeleton (keep outside this skill; it's your ops-side glue):

```bash
for inc in "$INPUTS"/INC-*/; do
  inc_id=$(basename "$inc")
  mkdir -p "/tmp/incident-extracts/$inc_id"

  # Flatten Slack thread to one line per message, most important first
  jq -r '.messages | sort_by(.ts) | .[] | "\(.ts) [\(.user_name)] \(.text)"' \
    "$inc/slack/thread-*.json" > "/tmp/incident-extracts/$inc_id/slack-flat.txt" 2>/dev/null

  # Flatten PRs to title/author/merge-date/url
  jq -r '.[] | "#\(.number) [\(.state)] \(.title) (merged=\(.mergedAt // "n/a")) \(.url)"' \
    "$inc/github/prs.json" > "/tmp/incident-extracts/$inc_id/prs-flat.txt" 2>/dev/null

  # tsuga/commands.txt is already flat — just copy
  cp "$inc/tsuga/commands.txt" "/tmp/incident-extracts/$inc_id/tsuga-commands.txt" 2>/dev/null
done
```

Result: per-incident helper files the subagent reads instead of raw JSON. Saves tokens and speeds parsing.

## Phase 3 — fan out subagents

**One subagent per incident. Run in parallel — aim for batches of 10–20 at a time.** The per-service fan-out in `knowledge-company` used 32 in parallel; incident-history can match that or go wider since each subagent has less to do.

Each subagent gets:

- `inc_id` (the directory name)
- Raw-input path: `inputs/incidents/<inc_id>/`
- Helper path: `/tmp/incident-extracts/<inc_id>/` (if Phase 2 was run)
- Output path: `skills/incident-history/references/incidents/<inc_id>/SUMMARY.md`
- Canonical template: `${CLAUDE_PLUGIN_ROOT}/skills/build-incident-history/references/SUMMARY_TEMPLATE.md`
- The lessons doc: `${CLAUDE_PLUGIN_ROOT}/skills/build-incident-history/references/LESSONS.md`
- The verification doc: `${CLAUDE_PLUGIN_ROOT}/skills/build-incident-history/references/VERIFICATION.md`

The subagent's contract is in `SUBAGENT_PROMPT.md` — do not retype it; copy verbatim and substitute only the `{inc_id}` placeholder.

## Phase 4 — write `metadata.json` + `_inventory.csv`

Each subagent should copy `inputs/incidents/<inc_id>/metadata.json` into `skills/incident-history/references/incidents/<inc_id>/metadata.json` verbatim (no transformation). This is what `entrypoint.sh`'s snapshot-filter reads.

After all subagents return, generate the inventory:

```bash
OUTPUT=./skills/incident-history/references/incidents
{
  echo "incident_id,title,declared_at,last_iso,severity,affected_team,affected_services"
  for f in "$OUTPUT"/INC-*/metadata.json; do
    jq -r '[.incident_id, .title, .declared_at, .last_iso, .severity, .affected_team, (.affected_services | join(";"))] | @csv' "$f"
  done
} > "$OUTPUT/_inventory.csv"
```

Spot-check the resulting CSV: correct row count, no empty cells in the required columns, dates parse.

## Phase 5 — verification

Run `VERIFICATION.md`'s gates. All must pass before you ship. The most common failure after a first run is `## Diagnostic path` commands that do not execute — either because the subagent wrote MCP-tool pseudo-syntax (`search-logs query='...'`) or because the command references a metric / service / monitor that no longer exists. Both are caught by the sampled execution gate in `VERIFICATION.md`.

## Phase 6 — cross-link with knowledge-company

Once `knowledge-company/` is also populated, the per-service dossier should link to the incidents that reference it. This happens in reverse: `knowledge-company`'s build procedure greps `incident-history`'s SUMMARY files for service-name mentions and pre-builds per-service incident lists. So the order is:

1. Build `incident-history` fully (this skill).
2. Build `knowledge-company`, which ingests `incident-history` as one of its inputs (see `build-knowledge-company/references/INPUT_LAYOUT.md`).

Do not try to run them in parallel on the first pass — the dependency is one-way.

## Phase 7 — commit

One git commit for the batch, with a commit body that lists the incident count and the date range covered. If the archive is large (>50 incidents), split into commits per-year or per-quarter so future diffs are reviewable.

Do not push until someone has sampled 5 random SUMMARY.md files by eye and confirmed they read coherently. Subagents can produce "valid-looking but hallucinated" output when inputs are thin; the human eye catches this faster than any automated check.
