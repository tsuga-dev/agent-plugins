<!-- skill-lint: allow-forbidden-examples — this file documents the forbidden patterns as teaching examples -->

# VERIFICATION — acceptance gates for `knowledge-company`

Run all of these before pushing. Each has a concrete pass/fail signal.

## Gate 1 — Structural completeness

```bash
OUT=./skills/knowledge-company/references

# Required top-level files
for f in COMPANY_GENERAL_KNOWLEDGE.md COMPANY_TELEMETRY_KNOWLEDGE.md; do
  [ -f "$OUT/$f" ] || echo "MISSING: $f"
done

# RAW_TELEMETRY_KNOWLEDGE.md must NOT exist (folded into COMPANY_TELEMETRY_KNOWLEDGE.md)
[ -f "$OUT/RAW_TELEMETRY_KNOWLEDGE.md" ] && echo "UNEXPECTED: RAW_TELEMETRY_KNOWLEDGE.md should not exist"

# Every team dir has TEAM_KNOWLEDGE.md
for d in "$OUT"/teams/*/; do
  [ -f "$d/TEAM_KNOWLEDGE.md" ] || echo "MISSING: ${d}TEAM_KNOWLEDGE.md"
done

# Every service dir has SERVICE_KNOWLEDGE.md
find "$OUT"/teams/*/services/ -mindepth 1 -maxdepth 1 -type d | while read svc_dir; do
  [ -f "$svc_dir/SERVICE_KNOWLEDGE.md" ] || echo "MISSING: $svc_dir/SERVICE_KNOWLEDGE.md"
done
```

**Pass:** no output.

## Gate 2 — SKILL.md frontmatter

```bash
# Frontmatter present
head -5 "$OUT/../SKILL.md" | grep -q '^name: knowledge-company$' || echo "MISSING: SKILL.md name frontmatter"
head -5 "$OUT/../SKILL.md" | grep -q '^description:' || echo "MISSING: SKILL.md description frontmatter"

# Description is non-trivial (>100 chars)
desc=$(awk '/^description:/{sub(/^description: *"/, ""); sub(/"$/, ""); print; exit}' "$OUT/../SKILL.md")
[ "${#desc}" -lt 100 ] && echo "TOO SHORT: description is only ${#desc} chars"
```

**Pass:** no output.

## Gate 3 — Canonical section headings in every SERVICE_KNOWLEDGE.md

```bash
required=(
  "## Quick context"
  "## Ready-to-run"
  "## Golden signals"
  "## Log shape"
  "## Dashboards"
  "## Upstream / downstream"
  "## Incident shapes"
  "## Caveats, footguns, known behaviors"
  "## Confidence note"
)
find "$OUT"/teams/*/services/*/SERVICE_KNOWLEDGE.md | while read f; do
  for h in "${required[@]}"; do
    grep -qF "$h" "$f" || echo "MISSING '$h' in $f"
  done
done
```

**Pass:** no output. (If a section has genuinely no content, it should still have the heading + a one-line note; never delete the heading.)

## Gate 4 — Forbidden tokens

```bash
# MCP-tool pseudo-syntax verbs
grep -rnE "^(search-logs|search-spans|list-metrics|get-metric|list-monitors|get-monitor|list-dashboards|get-dashboard|list-routes|list-teams|list-services|get-service|list-notification-rules|list-notification-silences|aggregate-scalar|aggregate-timeseries|list-log-patterns|list-new-error-patterns|list-error-pattern-increases)\b" "$OUT"

# Pseudo-syntax argument shape (but OK inside JSON bodies and in URLs)
grep -rnE "\bquery=|\bfrom=-|\b to=now\b|\blimit=|\bfilter=|\baggregationWindow=|\bdataSource=" "$OUT" \
  | grep -v '"aggregationWindow":' \
  | grep -v '"dataSource":' \
  | grep -v '"filter":' \
  | grep -v '/explorer?query='

# rtk prefix anywhere in commands
grep -rnE "^rtk |[[:space:]]rtk " "$OUT"

# Wrong singular resource names
grep -rnE "tsuga (monitor|dashboard|route|team|service|notification-rule|notification-silence) (get|list|create|update|delete)" "$OUT" \
  | grep -vE "tsuga (monitors|dashboards|routes|teams|services|notification-rules|notification-silences) (get|list|create|update|delete)"

# spans search (should be traces search)
grep -rn "tsuga spans search" "$OUT"
```

**Pass:** all five return zero hits.

## Gate 5 — Sampled command execution

Pick 5 random SERVICE_KNOWLEDGE.md files. Copy every `tsuga` command in their Ready-to-run section into a shell and confirm:
- It parses (no "unknown option" or shell syntax error).
- It returns a valid response (empty results `{"logs":[]}` / `{"series":[]}` are fine; errors are not).

```bash
files=$(find "$OUT"/teams/*/services/*/SERVICE_KNOWLEDGE.md | shuf -n 5)
for f in $files; do
  echo "=== $f ==="
  # Extract the Ready-to-run section's bash blocks
  awk '/^## Ready-to-run/,/^## Golden signals/' "$f" \
    | awk '/^```bash$/{flag=1;next}/^```$/{flag=0}flag'
done
```

Run each extracted command. If any fails to parse or returns a CLI error, the bug is in the SERVICE_KNOWLEDGE_TEMPLATE.md or the subagent prompt — fix the root cause, regenerate the affected batch, do NOT hand-patch the individual file.

**Pass:** every sampled command executes cleanly.

## Gate 6 — Aggregation body sanity

Aggregation heredocs are the highest-risk code blocks (most places to get wrong). Spot-check 3 random aggregation blocks:

```bash
# Find all aggregation bash blocks
grep -lr "tsuga aggregation" "$OUT"/teams | shuf -n 3 | while read f; do
  echo "=== $f ==="
  awk '/<<JSON$/,/^JSON$/' "$f" | head -50
done
```

For each:
- `"timeRange"` is present and uses `$FROM` / `$TO` (Unix seconds), not relative strings.
- `"dataSource"` is `"logs"`, `"traces"`, or `"metrics"` (never `"spans"`).
- `"formula"` is at body level (references `"q1"`, `"q2"`, etc.).
- `"groupBy"` is at body level when used.
- `"aggregationWindow"` is at body level when used (timeseries only).
- `count` aggregate is not used on `"dataSource": "metrics"`.

**Pass:** every sampled body conforms. If any don't, the subagent wasn't following `CLI_TRANSLATION.md` — regenerate.

## Gate 7 — Cross-link consistency

```bash
# Services named in COMPANY_TELEMETRY's symptom table but missing a dossier
grep -oE "\`[a-z][a-z0-9-]+\`" "$OUT/COMPANY_TELEMETRY_KNOWLEDGE.md" | sort -u > /tmp/svc-named.txt
find "$OUT/teams" -name SERVICE_KNOWLEDGE.md -path '*/services/*' | awk -F/ '{print "`" $(NF-1) "`"}' | sort -u > /tmp/svc-have.txt
echo "=== named in top-level but no dossier (informational) ==="
comm -23 /tmp/svc-named.txt /tmp/svc-have.txt | head

# Every SERVICE_KNOWLEDGE.md references its TEAM_KNOWLEDGE.md
find "$OUT/teams" -name SERVICE_KNOWLEDGE.md -path '*/services/*' | while read f; do
  grep -q "TEAM_KNOWLEDGE.md" "$f" || echo "MISSING team cross-link in $f"
done
```

**Pass:** the second check returns no output. The first check is informational — services mentioned in the symptom table may legitimately not have dedicated dossiers.

## Gate 8 — Human eyeball

Open 5 random SERVICE_KNOWLEDGE.md files and read them cover-to-cover. Check:

- **Quick context** — does the one-paragraph framing match what the service actually does (per live log probe)? Or does it read like generic template filler?
- **Golden signals** — do the metric names look plausible? Are thresholds pulled from real monitors or invented?
- **Log shape** — do the pattern strings look like real log lines, or sanitized templates?
- **Incident shapes** — do they cite real INC-xxxx paths? Do the paths actually exist (`ls skills/incident-history/references/incidents/INC-xxxx/SUMMARY.md`)?
- **Confidence note** — is it tiered (high / medium / low) and specific, or is it one generic paragraph?

No automated check for this. If anything feels off, regenerate the affected batch with a tightened subagent prompt.

## Gate 9 — Length sanity

```bash
# Services with fewer than 120 lines OR more than 450 lines deserve a second look
find "$OUT"/teams/*/services/*/SERVICE_KNOWLEDGE.md -exec wc -l {} + | awk '$1<120 || $1>450 {print}'
```

**Informational.** Under 120 lines → the service probably didn't merit a dossier (fold into TEAM_KNOWLEDGE.md?). Over 450 → trim. These aren't hard fails but deserve review.

## Gate 10 — No unresolved RAW_TELEMETRY_KNOWLEDGE references

The distillation step (Phase 5) folded `RAW_TELEMETRY_KNOWLEDGE.md` into `COMPANY_TELEMETRY_KNOWLEDGE.md`. Stale references are a smell.

```bash
grep -rn "RAW_TELEMETRY_KNOWLEDGE\|RAW_TELEMETRY" "$OUT"
```

**Pass:** no output. If any, update the reference to `COMPANY_TELEMETRY_KNOWLEDGE.md §"..."`.

## Gate 11 — Gate against re-introducing rtk mentions

The first pass shipped with `rtk` prefixes that had to be stripped in a follow-up commit. Prevent regression:

```bash
grep -rnE "\brtk\b" "$OUT" | grep -v "## Rules\|RTK" | head
```

**Pass:** no output. (Legit mentions inside section headings or explanatory prose can be kept, but the command-prefix usage must be gone.)

## If a gate fails

Do NOT hand-edit individual files. Go back to the root cause:

- Gate 3 (missing sections) → fix `SERVICE_KNOWLEDGE_TEMPLATE.md`, regenerate affected services.
- Gate 4 (forbidden tokens) → check `CLI_TRANSLATION.md` and `SUBAGENT_PROMPT.md`; the subagent prompt may need the contract-reference strengthened.
- Gate 5 (execution fails) → check the live `tsuga` CLI version; the CLI may have changed under you. Fix `CLI_TRANSLATION.md`, regenerate.
- Gate 6 (aggregation body) → same as Gate 5.
- Gate 7 (cross-links) → add the missing link to the template; may require fixing a single file by hand (exception to the rule, only when the template change doesn't affect the shape).
- Gate 10/11 (stale refs) → fix the `perl -i -pe` sweep you're running after Phase 5.

After fixing the root cause, regenerate the affected batch via subagent, then re-run all gates. Do not ship partial passes.
