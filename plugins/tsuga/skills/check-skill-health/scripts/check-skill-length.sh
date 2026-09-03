#!/bin/bash
# check-skill-length.sh — validate SKILL.md body length, references depth, bundle size.
#
# Usage: check-skill-length.sh <skill-dir>
# Exit:  0 = PASS/WARN, 1 = FAIL, 2 = script error.

set -uo pipefail

SKILL_DIR="${1:-}"
if [ -z "$SKILL_DIR" ]; then
  echo "usage: $0 <skill-dir>" >&2
  exit 2
fi

SKILL_MD="$SKILL_DIR/SKILL.md"
if [ ! -f "$SKILL_MD" ]; then
  echo "FAIL [length] $SKILL_DIR — SKILL.md not found"
  exit 1
fi

skill_name=$(basename "$SKILL_DIR")
status=0
warnings=0
out=""

# --- SKILL.md body length (excluding frontmatter) ---
# Count everything after the frontmatter's closing fence. Keying off every `---` would treat a
# horizontal rule in the body as a delimiter and under-report the length.
body_lines=$(awk 'NR==1 && /^---$/ {state=1; next} state==1 && /^---$/ {state=2; next} state==2 {print} state==0 {print}' "$SKILL_MD" | wc -l | tr -d ' ')
if [ "$body_lines" -gt 500 ]; then
  out+="FAIL [length] $SKILL_DIR — SKILL.md body $body_lines lines (max 500)"$'\n'
  status=1
elif [ "$body_lines" -gt 400 ]; then
  out+="WARN [length] $SKILL_DIR — SKILL.md body $body_lines lines (recommended <=400)"$'\n'
  warnings=1
else
  out+="PASS [length] $SKILL_DIR — SKILL.md body $body_lines lines"$'\n'
fi

# --- references/ depth ---
if [ -d "$SKILL_DIR/references" ]; then
  # Count nested dirs and nested files: references/topic/file.md is two levels down even though
  # there is no directory at depth 2.
  if ! deep_listing=$(find "$SKILL_DIR/references" -mindepth 2 2>/dev/null); then
    out+="FAIL [length] $SKILL_DIR — could not inspect references/"$'\n'
    printf '%s' "$out"
    exit 1
  fi
  deep_entries=$(printf '%s' "$deep_listing" | grep -c . )
  if [ "$deep_entries" -gt 0 ]; then
    # Exempt skills whose hierarchical taxonomy is intentional data structure,
    # not nested prose — SKILL.md still links these one hop away.
    case "$skill_name" in
      knowledge-company)
        out+="PASS [length] $SKILL_DIR — references/ has $deep_entries nested entries (EXEMPT: knowledge-company's teams/services taxonomy)"$'\n'
        ;;
      incident-history)
        out+="PASS [length] $SKILL_DIR — references/ has $deep_entries nested entries (EXEMPT: incident-history's per-incident folder structure)"$'\n'
        ;;
      *)
        out+="WARN [length] $SKILL_DIR — references/ has $deep_entries entries > 1 level deep (progressive loading prefers flat)"$'\n'
        warnings=1
        ;;
    esac
  else
    out+="PASS [length] $SKILL_DIR — references/ depth OK"$'\n'
  fi
fi

# --- bundle size ---
# du -s returns 512-byte blocks on macOS BSD; use -k for KB.
du_out=$(du -sk "$SKILL_DIR" 2>/dev/null) || du_out=""
size_kb=$(printf '%s\n' "$du_out" | awk '{print $1}')
case "${size_kb:-}" in
  '' | *[!0-9]*)
    out+="FAIL [length] $SKILL_DIR — could not measure bundle size"$'\n'
    printf '%s' "$out"
    exit 1
    ;;
esac
# Compare in KiB: integer MiB truncation let anything under 16 MiB pass a 15 MB limit.
size_mb=$(((size_kb + 1023) / 1024))
if [ "$size_kb" -gt $((15 * 1024)) ]; then
  out+="FAIL [length] $SKILL_DIR — bundle size ${size_mb} MB (max 15 MB)"$'\n'
  status=1
elif [ "$size_kb" -gt $((10 * 1024)) ]; then
  out+="WARN [length] $SKILL_DIR — bundle size ${size_mb} MB (recommended <=10 MB)"$'\n'
  warnings=1
else
  out+="PASS [length] $SKILL_DIR — bundle size ${size_kb} KB"$'\n'
fi

# --- "When to use" section in body (rule 3 — trigger logic belongs in description, not body) ---
if awk 'NR==1 && /^---$/ {state=1; next} state==1 && /^---$/ {state=2; next} state==2 {print} state==0 {print}' "$SKILL_MD" \
    | grep -qiE '^ {0,3}#{2,}[[:blank:]]*(when to use|when to trigger|when does this)\b'; then
  out+="WARN [length] $SKILL_DIR — SKILL.md has a 'When to use' body section; trigger logic belongs in frontmatter description"$'\n'
  warnings=1
fi

printf '%s' "$out"
exit $status
