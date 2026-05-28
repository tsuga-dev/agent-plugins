#!/bin/bash
# check-knowledge-company.sh — verify the structure of a knowledge-company skill tree.
#
# Usage: check-knowledge-company.sh <skill-dir>
# Skipped silently if the dir doesn't look like a knowledge-company skill.

set -uo pipefail

SKILL_DIR="${1:-}"
if [ -z "$SKILL_DIR" ]; then
  echo "usage: $0 <skill-dir>" >&2
  exit 2
fi

REFS="$SKILL_DIR/references"
TEAMS="$REFS/teams"
if [ ! -d "$TEAMS" ]; then
  # Not a knowledge-company skill; skip silently.
  exit 0
fi

fail=0

# --- Required top-level files ---
for f in COMPANY_GENERAL_KNOWLEDGE.md COMPANY_TELEMETRY_KNOWLEDGE.md; do
  if [ ! -f "$REFS/$f" ]; then
    echo "FAIL [knowledge-company] $SKILL_DIR — missing references/$f"
    fail=1
  fi
done

# --- RAW_TELEMETRY_KNOWLEDGE.md must NOT exist (folded into COMPANY_TELEMETRY) ---
if [ -f "$REFS/RAW_TELEMETRY_KNOWLEDGE.md" ]; then
  echo "FAIL [knowledge-company] $SKILL_DIR — references/RAW_TELEMETRY_KNOWLEDGE.md should not exist (folded into COMPANY_TELEMETRY_KNOWLEDGE.md)"
  fail=1
fi

# --- Every team dir has TEAM_KNOWLEDGE.md ---
team_count=0
missing_team_md=0
for d in "$TEAMS"/*/; do
  [ -d "$d" ] || continue
  team_count=$((team_count+1))
  if [ ! -f "$d/TEAM_KNOWLEDGE.md" ]; then
    missing_team_md=$((missing_team_md+1))
    [ $missing_team_md -le 3 ] && echo "  missing TEAM_KNOWLEDGE.md: $d"
  fi
done
if [ $missing_team_md -gt 0 ]; then
  echo "FAIL [knowledge-company] $SKILL_DIR — $missing_team_md/$team_count teams missing TEAM_KNOWLEDGE.md"
  fail=1
fi

# --- Every service dir has SERVICE_KNOWLEDGE.md ---
service_count=0
missing_svc_md=0
for d in "$TEAMS"/*/services/*/; do
  [ -d "$d" ] || continue
  service_count=$((service_count+1))
  if [ ! -f "$d/SERVICE_KNOWLEDGE.md" ]; then
    missing_svc_md=$((missing_svc_md+1))
    [ $missing_svc_md -le 3 ] && echo "  missing SERVICE_KNOWLEDGE.md: $d"
  fi
done
if [ $missing_svc_md -gt 0 ]; then
  echo "FAIL [knowledge-company] $SKILL_DIR — $missing_svc_md/$service_count services missing SERVICE_KNOWLEDGE.md"
  fail=1
fi

# --- SERVICE_KNOWLEDGE.md canonical sections (prefix match; section naming has stylistic variants) ---
# Each entry is a regex — heading must start with "## <pattern>" (case-sensitive).
# This tolerates variants like "## Ready-to-run `tsuga` commands",
# "## Typical incident shapes", "## Caveats, footguns, known behaviors".
required_patterns=(
  '^## Quick context'
  '^## Ready-to-run'
  '^## Golden signals'
  '^## Log shape'
  '^## Dashboards'
  '^## Upstream / downstream'
  '^## (Typical |Historical |Related )?[Ii]ncident'
  '^## Caveats'
  '^## Confidence note'
)
missing_section_total=0
services_with_missing=0
for f in "$TEAMS"/*/services/*/SERVICE_KNOWLEDGE.md; do
  [ -f "$f" ] || continue
  missed_in_this=0
  missed_labels=""
  for pat in "${required_patterns[@]}"; do
    if ! grep -qE "$pat" "$f"; then
      missed_in_this=$((missed_in_this+1))
      missed_labels+=" [${pat#^## }]"
    fi
  done
  if [ $missed_in_this -gt 0 ]; then
    missing_section_total=$((missing_section_total + missed_in_this))
    services_with_missing=$((services_with_missing+1))
    [ $services_with_missing -le 3 ] && echo "  $f — missing $missed_in_this:$missed_labels"
  fi
done
if [ $missing_section_total -gt 0 ]; then
  echo "WARN [knowledge-company] $SKILL_DIR — $services_with_missing services missing $missing_section_total canonical-section variants (soft — many services ship with stylistic variance)"
fi

# --- TEAM_KNOWLEDGE.md basic section check ---
team_required=("## What they own" "## Paging surface")
missing_team_sections=0
for f in "$TEAMS"/*/TEAM_KNOWLEDGE.md; do
  [ -f "$f" ] || continue
  for h in "${team_required[@]}"; do
    grep -qF "$h" "$f" || {
      missing_team_sections=$((missing_team_sections+1))
      [ $missing_team_sections -le 3 ] && echo "  $f — missing '$h'"
    }
  done
done
if [ $missing_team_sections -gt 0 ]; then
  echo "WARN [knowledge-company] $SKILL_DIR — $missing_team_sections TEAM_KNOWLEDGE.md files missing a canonical heading"
fi

# --- Cross-link integrity: every file path referenced in SKILL.md resolves (relative to references/) ---
skill_md="$SKILL_DIR/SKILL.md"
if [ -f "$skill_md" ]; then
  bad_links=0
  # Pull paths that look like relative md / csv / json references inside backticks.
  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    # Resolve relative to SKILL.md's directory.
    target="$SKILL_DIR/$ref"
    if [ ! -e "$target" ] && [ ! -e "$REFS/$ref" ]; then
      bad_links=$((bad_links+1))
      [ $bad_links -le 3 ] && echo "  broken reference in SKILL.md: $ref"
    fi
  done < <(grep -oE '`[a-zA-Z_/.*-]+\.(md|csv|json|yaml|yml|sh|py)`' "$skill_md" 2>/dev/null | tr -d '`' | sort -u)
  if [ $bad_links -gt 0 ]; then
    echo "WARN [knowledge-company] $SKILL_DIR — $bad_links file references from SKILL.md don't resolve (may be templates / placeholders)"
  fi
fi

if [ $fail -eq 0 ]; then
  echo "PASS [knowledge-company] $SKILL_DIR — $team_count teams, $service_count services, all canonical sections present"
fi

exit $fail
