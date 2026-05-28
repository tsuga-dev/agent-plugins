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
body_lines=$(awk 'BEGIN{state=0} /^---$/{state++; next} state>=2 {print}' "$SKILL_MD" | wc -l | tr -d ' ')
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
  deep_dirs=$(find "$SKILL_DIR/references" -mindepth 2 -type d 2>/dev/null | wc -l | tr -d ' ')
  if [ "$deep_dirs" -gt 0 ]; then
    # Exempt skills whose hierarchical taxonomy is intentional data structure,
    # not nested prose — SKILL.md still links these one hop away.
    case "$skill_name" in
      knowledge-company)
        out+="PASS [length] $SKILL_DIR — references/ has $deep_dirs nested dirs (EXEMPT: knowledge-company's teams/services taxonomy)"$'\n'
        ;;
      incident-history)
        out+="PASS [length] $SKILL_DIR — references/ has $deep_dirs nested dirs (EXEMPT: incident-history's per-incident folder structure)"$'\n'
        ;;
      *)
        out+="WARN [length] $SKILL_DIR — references/ has $deep_dirs dirs > 1 level deep (progressive loading prefers flat)"$'\n'
        warnings=1
        ;;
    esac
  else
    out+="PASS [length] $SKILL_DIR — references/ depth OK"$'\n'
  fi
fi

# --- bundle size ---
# du -s returns 512-byte blocks on macOS BSD; use -k for KB.
size_kb=$(du -sk "$SKILL_DIR" 2>/dev/null | awk '{print $1}')
size_mb=$((size_kb / 1024))
if [ "$size_mb" -gt 15 ]; then
  out+="FAIL [length] $SKILL_DIR — bundle size ${size_mb} MB (max 15 MB)"$'\n'
  status=1
elif [ "$size_mb" -gt 10 ]; then
  out+="WARN [length] $SKILL_DIR — bundle size ${size_mb} MB (recommended <=10 MB)"$'\n'
  warnings=1
else
  out+="PASS [length] $SKILL_DIR — bundle size ${size_mb} MB (${size_kb} KB)"$'\n'
fi

# --- "When to use" section in body (rule 3 — trigger logic belongs in description, not body) ---
if awk 'BEGIN{state=0} /^---$/{state++; next} state>=2 {print}' "$SKILL_MD" \
    | grep -qiE '^##+ *(when to use|when to trigger|when does this)\b'; then
  out+="WARN [length] $SKILL_DIR — SKILL.md has a 'When to use' body section; trigger logic belongs in frontmatter description"$'\n'
  warnings=1
fi

printf '%s' "$out"
exit $status
