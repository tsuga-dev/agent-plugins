#!/bin/bash
# sample-execute-commands.sh — pick N random SERVICE_KNOWLEDGE.md files,
# extract the first `tsuga` command from each, execute it, report pass/fail.
#
# Usage: sample-execute-commands.sh <knowledge-company-skill-dir> [sample-count]
# Requires: `tsuga` CLI on PATH with auth configured.
#
# This is opt-in — live probes against prod telemetry cost real quota.

set -uo pipefail

SKILL_DIR="${1:-}"
N="${2:-5}"

if [ -z "$SKILL_DIR" ]; then
  echo "usage: $0 <knowledge-company-skill-dir> [sample-count]" >&2
  exit 2
fi

TEAMS="$SKILL_DIR/references/teams"
if [ ! -d "$TEAMS" ]; then
  # Not a knowledge-company skill; skip silently (no service dossiers to execute).
  exit 0
fi

if ! command -v tsuga >/dev/null 2>&1; then
  echo "FAIL [sample-execute] $SKILL_DIR — tsuga CLI not on PATH (install @tsuga/cli)"
  exit 1
fi

# Pick N random SERVICE_KNOWLEDGE.md files.
mapfile -t files < <(find "$TEAMS" -name SERVICE_KNOWLEDGE.md -path '*/services/*' 2>/dev/null | shuf | head -n "$N")
if [ ${#files[@]} -eq 0 ]; then
  echo "WARN [sample-execute] $SKILL_DIR — no SERVICE_KNOWLEDGE.md files found"
  exit 0
fi

passed=0
failed=0
failures=""

for f in "${files[@]}"; do
  # Extract the first `tsuga ...` command from the Ready-to-run section.
  # Strategy: read the Ready-to-run block, extract bash fences, pick the first line
  # starting with `tsuga ` (skipping heredoc bodies, variables, comments).
  cmd=$(awk '
    /^## Ready-to-run/ { in_ready=1; next }
    in_ready && /^## / { in_ready=0 }
    in_ready && /^```bash$/ { in_bash=1; next }
    in_ready && /^```$/ { in_bash=0 }
    in_ready && in_bash && /^tsuga / { print; exit }
  ' "$f")

  if [ -z "$cmd" ]; then
    echo "  SKIP: $f — no tsuga command in Ready-to-run section"
    continue
  fi

  # Execute with a 20s timeout so a slow query does not hang the lint run.
  if output=$(timeout 20 sh -c "$cmd" 2>&1); then
    passed=$((passed+1))
  else
    failed=$((failed+1))
    failures+=$'\n'"  FAIL: $(basename $(dirname "$f"))"$'\n'"    cmd: $cmd"$'\n'"    err: $(echo "$output" | head -2 | tr '\n' ' ')"
  fi
done

total=$((passed + failed))

if [ $failed -eq 0 ] && [ $passed -gt 0 ]; then
  echo "PASS [sample-execute] $SKILL_DIR — $passed/$total commands executed successfully"
  exit 0
elif [ $failed -gt 0 ]; then
  echo "FAIL [sample-execute] $SKILL_DIR — $failed/$total commands failed$failures"
  exit 1
else
  echo "WARN [sample-execute] $SKILL_DIR — 0 commands executed (none found in sampled files)"
  exit 0
fi
