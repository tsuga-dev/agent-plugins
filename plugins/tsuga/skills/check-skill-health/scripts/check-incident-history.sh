#!/bin/bash
# check-incident-history.sh — verify the structure of an incident-history skill tree.
#
# Usage: check-incident-history.sh <skill-dir>
# Skipped silently if the dir doesn't look like an incident-history skill.

set -uo pipefail

SKILL_DIR="${1:-}"
if [ -z "$SKILL_DIR" ]; then
  echo "usage: $0 <skill-dir>" >&2
  exit 2
fi

INCIDENTS_DIR="$SKILL_DIR/references/incidents"
if [ ! -d "$INCIDENTS_DIR" ]; then
  # Not an incident-history skill; skip silently.
  exit 0
fi

fail=0

# --- Folder presence ---
folder_count=$(find "$INCIDENTS_DIR" -mindepth 1 -maxdepth 1 -type d -name 'INC-*' 2>/dev/null | wc -l | tr -d ' ')
if [ "$folder_count" -eq 0 ]; then
  echo "FAIL [incident-history] $SKILL_DIR — references/incidents/ has no INC-* folders"
  exit 1
fi

# --- Every folder has SUMMARY.md and metadata.json ---
missing_summary=0
missing_metadata=0
for d in "$INCIDENTS_DIR"/INC-*/; do
  [ -f "$d/SUMMARY.md" ]    || { missing_summary=$((missing_summary+1)); [ $missing_summary -le 3 ] && echo "  missing SUMMARY.md: $d"; }
  [ -f "$d/metadata.json" ] || { missing_metadata=$((missing_metadata+1)); [ $missing_metadata -le 3 ] && echo "  missing metadata.json: $d"; }
done
if [ $missing_summary -gt 0 ] || [ $missing_metadata -gt 0 ]; then
  echo "FAIL [incident-history] $SKILL_DIR — missing files: $missing_summary SUMMARY.md, $missing_metadata metadata.json (out of $folder_count folders)"
  fail=1
fi

# --- metadata.json parses + carries the fields entrypoint.sh actually reads ---
# The authoritative required field per entrypoint.sh is `.last_iso` (for the snapshot filter).
# We also require an incident identifier (either `.inc_id` or `.incident_id`) so the folder
# name and metadata stay consistent. Both schemas exist in the wild and both are accepted.
if command -v jq >/dev/null 2>&1; then
  bad_metadata=0
  for f in "$INCIDENTS_DIR"/INC-*/metadata.json; do
    [ -f "$f" ] || continue
    if ! jq -e '.last_iso and (.inc_id // .incident_id)' "$f" >/dev/null 2>&1; then
      bad_metadata=$((bad_metadata+1))
      [ $bad_metadata -le 3 ] && echo "  bad metadata: $f (requires .last_iso + one of .inc_id / .incident_id)"
    fi
  done
  if [ $bad_metadata -gt 0 ]; then
    echo "FAIL [incident-history] $SKILL_DIR — $bad_metadata metadata.json files missing required fields"
    fail=1
  fi
else
  echo "WARN [incident-history] $SKILL_DIR — jq not installed; skipped metadata validation"
fi

# --- Canonical section headings in every SUMMARY.md ---
# Two schemas exist in the wild: the old Slack-export-based shape (Symptom, Root cause,
# Diagnostic path, Fix, Resolution, …) and the newer aspirational shape
# (Incident at a glance, Timeline, Paging surface, …). Both carry "Root cause" and
# "Diagnostic path" — those two are load-bearing for analogue search. Require both.
required_core=(
  "## Root cause"
  "## Diagnostic path"
)
missing_sections=0
for f in "$INCIDENTS_DIR"/INC-*/SUMMARY.md; do
  [ -f "$f" ] || continue
  for h in "${required_core[@]}"; do
    if ! grep -qF "$h" "$f"; then
      missing_sections=$((missing_sections+1))
      [ $missing_sections -le 3 ] && echo "  missing '$h' in $f"
      break
    fi
  done
done
if [ $missing_sections -gt 0 ]; then
  echo "FAIL [incident-history] $SKILL_DIR — $missing_sections SUMMARY.md files missing a load-bearing section (## Root cause or ## Diagnostic path)"
  fail=1
fi

# --- _inventory.csv row count matches folder count (if present) ---
inventory="$INCIDENTS_DIR/_inventory.csv"
if [ -f "$inventory" ]; then
  inventory_count=$(tail -n +2 "$inventory" | wc -l | tr -d ' ')
  if [ "$inventory_count" != "$folder_count" ]; then
    echo "FAIL [incident-history] $SKILL_DIR — _inventory.csv has $inventory_count rows but $folder_count folders exist"
    fail=1
  fi
else
  echo "WARN [incident-history] $SKILL_DIR — _inventory.csv not present (informational)"
fi

if [ $fail -eq 0 ]; then
  echo "PASS [incident-history] $SKILL_DIR — $folder_count incident folders, all with SUMMARY.md + metadata.json + canonical headings"
fi

exit $fail
