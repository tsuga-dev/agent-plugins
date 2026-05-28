#!/bin/bash
# check-frontmatter.sh — validate a skill's SKILL.md frontmatter.
#
# Usage: check-frontmatter.sh <skill-dir>
# Exit:  0 = PASS, 1 = FAIL, 2 = script error.
#
# Checks:
#   - SKILL.md exists
#   - Frontmatter block present (two `---` delimiters at top)
#   - name: field present, non-empty
#   - name value matches enclosing folder name (warn only)
#   - description: field present, non-empty
#   - description word count in [30, 200], with warn outside [50, 120]

set -uo pipefail

SKILL_DIR="${1:-}"
if [ -z "$SKILL_DIR" ]; then
  echo "usage: $0 <skill-dir>" >&2
  exit 2
fi

SKILL_MD="$SKILL_DIR/SKILL.md"
if [ ! -f "$SKILL_MD" ]; then
  echo "FAIL [frontmatter] $SKILL_DIR — SKILL.md not found"
  exit 1
fi

# Extract the first frontmatter block (lines between the first two `---`).
fm=$(awk 'BEGIN{state=0} /^---$/{state++; next} state==1 {print} state==2 {exit}' "$SKILL_MD")
if [ -z "$fm" ]; then
  echo "FAIL [frontmatter] $SKILL_DIR — no frontmatter block found (expected \`---\` delimiters at top)"
  exit 1
fi

# Pull `name:` value.
name=$(echo "$fm" | awk '/^name:/ { sub(/^name: */, ""); sub(/^"/, ""); sub(/"$/, ""); print; exit }')
if [ -z "$name" ]; then
  echo "FAIL [frontmatter] $SKILL_DIR — name: field missing or empty"
  exit 1
fi

# Pull `description:` — single-line, optionally quoted.
desc=$(echo "$fm" | awk '/^description:/ { sub(/^description: */, ""); sub(/^"/, ""); sub(/"$/, ""); print; exit }')
if [ -z "$desc" ]; then
  echo "FAIL [frontmatter] $SKILL_DIR — description: field missing or empty"
  exit 1
fi

# Word count of description.
word_count=$(echo "$desc" | wc -w | tr -d ' ')

status="PASS"
msg=""

# Hard bounds.
if [ "$word_count" -lt 30 ]; then
  status="FAIL"
  msg="description too short ($word_count words; min 30)"
elif [ "$word_count" -gt 200 ]; then
  status="FAIL"
  msg="description too long ($word_count words; max 200)"
# Soft bounds.
elif [ "$word_count" -lt 50 ]; then
  status="WARN"
  msg="description short ($word_count words; recommended 50-120)"
elif [ "$word_count" -gt 120 ]; then
  status="WARN"
  msg="description long ($word_count words; recommended 50-120)"
fi

# Folder-name vs name-field match (soft).
folder_name=$(basename "$SKILL_DIR")
name_match_note=""
if [ "$name" != "$folder_name" ]; then
  name_match_note=" (note: folder '$folder_name' != name '$name')"
fi

echo "$status [frontmatter] $SKILL_DIR — name: $name, description: $word_count words${msg:+ — $msg}${name_match_note}"

case "$status" in
  PASS|WARN) exit 0 ;;
  FAIL)      exit 1 ;;
esac
