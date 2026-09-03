<!-- skill-lint: allow-forbidden-examples — this file documents the forbidden patterns as verification examples -->

# VERIFICATION — acceptance gates before shipping the archive

Run all of these before the commit that ships the archive. Each has a concrete pass/fail.

## Gate 1 — Structural completeness

Every incident folder must have exactly the expected shape:

```bash
OUTPUT=./skills/incident-history/references/incidents

# Every INC-* folder has SUMMARY.md and metadata.json
missing=0
for d in "$OUTPUT"/INC-*/; do
  [ -f "$d/SUMMARY.md" ]    || { echo "MISSING SUMMARY.md: $d"; missing=$((missing+1)); }
  [ -f "$d/metadata.json" ] || { echo "MISSING metadata.json: $d"; missing=$((missing+1)); }
done
echo "missing: $missing"
```

**Pass:** `missing: 0`.

## Gate 2 — Metadata parses + carries required fields

```bash
for f in "$OUTPUT"/INC-*/metadata.json; do
  jq -e '.incident_id and .declared_at and .last_iso' "$f" >/dev/null \
    || echo "BAD METADATA: $f"
done
```

**Pass:** no output (every file has all three fields).

## Gate 3 — Canonical section list

Every SUMMARY.md must contain these headings, in order:

```
# {incident_id} — {title}
## Incident at a glance
## Timeline
## Paging surface during incident
## Diagnostic path
## Root cause
## Remediation
## Lessons / follow-ups
```

Quick check:

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

## Gate 4 — Forbidden tokens

The Diagnostic path sections must not contain MCP-tool pseudo-syntax or `rtk` prefix. Grep for:

```bash
# Pseudo-syntax verbs
grep -rnE "^(search-logs|search-spans|list-metrics|get-metric|list-monitors|get-monitor|list-dashboards|get-dashboard|list-routes|list-teams|list-services|list-notification-rules|aggregate-scalar|aggregate-timeseries|list-log-patterns|list-new-error-patterns|list-error-pattern-increases)\b" "$OUTPUT"

# Pseudo-syntax argument shape
# Strip URL params and JSON keys from each line first: dropping whole lines would mask a real
# violation that happens to share a line with a legitimate URL or key.
grep -rl . "$OUTPUT" | while IFS= read -r f; do
  sed -E 's#/explorer\?query=[^ )"`]*##g; s#"(aggregationWindow|dataSource|filter)":##g' "$f" \
    | grep -nE '\bquery=|\bfrom=-|\bto=now\b|\blimit=|\bfilter=|\baggregationWindow=|\bdataSource=' \
    | sed "s#^#$f:#"
done

# rtk prefix
grep -rnE "^rtk |[[:space:]]rtk " "$OUTPUT" | head -20
```

**Pass:** all three return zero hits (ignoring the known-safe URL / JSON-body cases).

## Gate 5 — Sampled execution

Pick 5 random SUMMARY.md files and run every `tsuga` command in their Diagnostic path section:

```bash
# Pick 5
files=$(ls "$OUTPUT"/INC-*/SUMMARY.md | shuf -n 5)

for f in $files; do
  echo "=== $f ==="
  # Extract the Diagnostic path section's bash blocks
  awk '/^## Diagnostic path/,/^## Root cause/' "$f" \
    | awk '/^```bash$/{flag=1;next}/^```$/{flag=0}flag'
done
```

Copy each command block into a shell and confirm:
- It parses (no "unknown option" or shell syntax error).
- It returns a valid response (empty results `{"logs":[]}` are fine; errors are not).

**Pass:** every sampled command executes cleanly.

If even one fails, the bug is in the subagent template, not the individual file. Fix the template (probably in `LESSONS.md` or `SUMMARY_TEMPLATE.md`), regenerate the affected batch, and re-run this gate.

## Gate 6 — Inventory consistency

```bash
# Row count matches folder count
folder_count=$(ls -d "$OUTPUT"/INC-*/ | wc -l)
inventory_count=$(tail -n +2 "$OUTPUT/_inventory.csv" | wc -l)
[ "$folder_count" = "$inventory_count" ] \
  && echo "OK: $folder_count incidents" \
  || echo "MISMATCH: $folder_count folders vs $inventory_count inventory rows"

# Inventory has no empty cells in the required columns
awk -F, 'NR>1 && ($1=="" || $2=="" || $3=="" || $4=="") {print NR": "$0}' "$OUTPUT/_inventory.csv"
```

**Pass:** `OK:` line + no output from awk.

## Gate 7 — Snapshot-filter dry-run

`entrypoint.sh` filters the archive by `SNAPSHOT_AT` at container start. Simulate that filter to confirm `metadata.json` dates are actually usable:

```bash
# Every incident, not just one. Parse with python so the check works on BSD and GNU alike, and
# so an empty last_iso fails instead of being skipped.
bad=0
for f in "$OUTPUT"/INC-*/metadata.json; do
  iso=$(jq -r '.last_iso // empty' "$f")
  if [ -z "$iso" ] || ! python3 -c 'import sys,datetime; datetime.datetime.fromisoformat(sys.argv[1].replace("Z","+00:00"))' "$iso" 2>/dev/null; then
    echo "FAIL: $(dirname "$f") last_iso does not parse: '${iso:-<missing>}'"
    bad=$((bad+1))
  fi
done
[ "$bad" -eq 0 ] && echo "OK: every last_iso parses as an ISO-8601 timestamp"
```

**Pass:** every `metadata.json`'s `last_iso` parses to Unix seconds. If any don't, `entrypoint.sh` will silently drop those incidents on filter.

## Gate 8 — Human eyeball

Open 5 random SUMMARY.md files and read them cover-to-cover. Check:

- Does the narrative flow from symptom → investigation → cause → fix?
- Are there any paragraphs that feel generic / boilerplate / invented?
- Does the Diagnostic path section tell a coherent story of what the responder actually did, or does it read like a checklist of unrelated probes?
- Is the Incident-at-a-glance paragraph something you'd want to read at 3am?

No automated check for this. If anything feels off, regenerate the affected batch with a tightened subagent prompt (e.g., "do not add sections beyond those in the template", "cite specific times and numbers from the input").

## Gate 9 — Post-incident PR leakage

A smell-test for answer-key leakage. If any SUMMARY.md contains the full text of a post-incident PR's description, that's a benchmarking poison.

```bash
# PR-like snippets (long diffs pasted in)
grep -rnE "^(diff --git|\+\+\+ |--- )" "$OUTPUT" | head
# Long quoted PR titles
grep -rnE 'PR #[0-9]+ merged at' "$OUTPUT" | head
```

**Pass:** no output or very short output (referencing PR numbers is fine; pasting diffs is not).

## If a gate fails

Do NOT hand-edit individual files. Go back to the subagent prompt / template, fix the root cause, and regenerate the affected batch. This keeps the archive reproducible.

The one exception is `_inventory.csv` — regenerating it is cheap (one script), so fix that directly.
