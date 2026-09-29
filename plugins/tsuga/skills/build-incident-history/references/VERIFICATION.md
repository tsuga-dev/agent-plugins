# VERIFICATION — acceptance gates before shipping the archive

Run all of these before the commit that ships the archive. Each has a concrete pass/fail.

## Contents

1. [The mechanical lint](#gate-1--the-mechanical-lint) — `lint-all.sh`
2. [Canonical section list, in order](#gate-2--canonical-section-list-in-order)
3. [Sampled execution](#gate-3--sampled-execution) — the payload gate
4. [Inventory column completeness](#gate-4--inventory-column-completeness)
5. [Post-incident PR leakage](#gate-5--post-incident-pr-leakage)
6. [Human eyeball](#gate-6--human-eyeball)
7. [If a gate fails](#if-a-gate-fails)

`OUTPUT=./skills/incident-history/references/incidents` throughout.

## Gate 1 — the mechanical lint

```bash
${CLAUDE_PLUGIN_ROOT}/skills/check-skill-health/scripts/lint-all.sh ./skills/incident-history/
```

**Pass:** exit code 0, no `FAIL` lines.

This covers, and is stricter than, a hand-rolled check of: every `INC-*` folder carrying both `SUMMARY.md` and `metadata.json`; `metadata.json` parsing with ISO-8601 `declared_at` and `last_iso` and an id that matches its folder name; `## Root cause` and `## Diagnostic path` present in every `SUMMARY.md`; `_inventory.csv` row count equal to folder count; and the MCP-pseudo-syntax / `rtk` / singular-resource / `--limit` forbidden-token sweep.

A folder whose `last_iso` does not parse is the one failure that matters most: `entrypoint.sh`'s `SNAPSHOT_AT` filter drops those incidents silently rather than erroring.

The gates below are the ones no script covers.

## Gate 2 — canonical section list, in order

The lint requires only the two load-bearing headings. A build run must produce the whole list from `SUMMARY_TEMPLATE.md`, in template order.

```bash
required=(
  "## Incident at a glance"
  "## Timeline"
  "## Paging surface during incident"
  "## Diagnostic path"
  "## Root cause"
  "## Remediation"
  "## Lessons / follow-ups"
)
for f in "$OUTPUT"/INC-*/SUMMARY.md; do
  grep -qE '^# INC-[0-9]+ — .+' "$f" || echo "MISSING or malformed H1 '# {incident_id} — {title}' in $f"
  # Presence and order: a dossier with the right headings in the wrong order is not canonical.
  prev=0
  for h in "${required[@]}"; do
    n=$(grep -nxF "$h" "$f" | head -1 | cut -d: -f1)
    if [ -z "$n" ]; then
      echo "MISSING '$h' in $f"
    elif [ "$n" -lt "$prev" ]; then
      echo "OUT OF ORDER '$h' in $f"
    else
      prev=$n
    fi
  done
done
```

**Pass:** no output.

## Gate 3 — sampled execution

The payload gate. Pick 5 random `SUMMARY.md` files and run every `tsuga` command in their Diagnostic path:

```bash
files=$(ls "$OUTPUT"/INC-*/SUMMARY.md | awk 'BEGIN{srand()} {print rand()"\t"$0}' | sort -n | cut -f2- | head -5)

for f in $files; do
  echo "=== $f ==="
  awk '/^## Diagnostic path/,/^## Root cause/' "$f" \
    | awk '/^```bash$/{flag=1;next}/^```$/{flag=0}flag'
done
```

Paste each block into a shell and confirm it parses and returns a response. Empty results (`{"logs":[]}`) pass; an error does not. A mistyped `tsuga` command prints **empty stdout**, so treat no output at all as a failure, not a pass.

**Pass:** every sampled command executes cleanly.

## Gate 4 — inventory column completeness

The lint compares row count to folder count but not cell contents.

```bash
awk -F, 'NR>1 && ($1=="" || $2=="" || $3=="" || $4=="") {print NR": "$0}' "$OUTPUT/_inventory.csv"
```

**Pass:** no output.

## Gate 5 — post-incident PR leakage

A smell test for answer-key leakage: a SUMMARY.md carrying a resolution PR's full text is benchmarking poison.

```bash
grep -rnE "^(diff --git|\+\+\+ |--- )" "$OUTPUT" | head
grep -rnE 'PR #[0-9]+ merged at' "$OUTPUT" | head
```

**Pass:** no output. Referencing a PR number is fine; pasting a diff is not.

## Gate 6 — human eyeball

Open 5 random `SUMMARY.md` files and read them cover to cover:

- Does the narrative flow from symptom → investigation → cause → fix?
- Any paragraph that reads generic, boilerplate or invented?
- Does the Diagnostic path tell a coherent story of what the responder did, or is it a checklist of unrelated probes?
- Is "Incident at a glance" something you would want to read at 3am?

Thin inputs make subagents produce valid-looking hallucination that every automated gate passes. This is the only gate that catches it.

## If a gate fails

Do not hand-edit individual files — a failure in one sampled file is a template-wide bug. Fix the root cause in `SUMMARY_TEMPLATE.md`, `SUBAGENT_PROMPT.md` or `LESSONS.md`, regenerate the affected batch, re-run the gate. This keeps the archive reproducible.

The one exception is `_inventory.csv`: regenerating it is one script (`PROCEDURE.md` Phase 4), so fix it directly.
