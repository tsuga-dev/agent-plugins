#!/bin/bash
# sample-execute-commands.sh — pick N SERVICE_KNOWLEDGE.md files,
# extract the first `tsuga` command from each, and audit whether it is safe to run.
#
# Usage: sample-execute-commands.sh <knowledge-company-skill-dir> [sample-count]
#
# This is opt-in and intentionally read-only: it never executes extracted commands.

set -uo pipefail

SKILL_DIR="${1:-}"
N="${2:-5}"

if [ -z "$SKILL_DIR" ]; then
  echo "usage: $0 <knowledge-company-skill-dir> [sample-count]" >&2
  exit 2
fi

TEAMS="$SKILL_DIR/references/teams"
if [ ! -d "$TEAMS" ]; then
  # Not a knowledge-company skill; skip silently (no service dossiers to audit).
  exit 0
fi

# Pick up to N SERVICE_KNOWLEDGE.md files with portable shell builtins.
files=()
while IFS= read -r f; do
  files+=("$f")
  [ "${#files[@]}" -ge "$N" ] && break
done < <(find "$TEAMS" -name SERVICE_KNOWLEDGE.md -path '*/services/*' 2>/dev/null)

if [ ${#files[@]} -eq 0 ]; then
  echo "WARN [sample-execute] $SKILL_DIR — no SERVICE_KNOWLEDGE.md files found"
  exit 0
fi

passed=0
failed=0
failures=""

is_read_only_tsuga_command() {
  local cmd="$1"
  local cluster_id=""
  local rest=""

  case "$cmd" in
    *"|"*|*";"*|*"&"*|*">"*|*"<"*|*"\`"*|*'$('*)
      return 1
      ;;
  esac

  case "$cmd" in
    tsuga\ --cluster\ *\ *)
      cmd="${cmd#tsuga --cluster }"
      cluster_id="${cmd%% *}"
      rest="${cmd#"$cluster_id"}"
      case "$cluster_id" in
        ""|-*) return 1 ;;
      esac
      case "$rest" in
        " "*) cmd="tsuga$rest" ;;
        *) return 1 ;;
      esac
      ;;
  esac

  has_arg() {
    case " $cmd " in
      *" $1 "*) return 0 ;;
      *) return 1 ;;
    esac
  }

  has_from_to() {
    has_arg --from && has_arg --to
  }

  has_max_results_10() {
    case " $cmd " in
      *" --max-results 10 "*|*" --max-results=10 "*) return 0 ;;
      *) return 1 ;;
    esac
  }

  case "$cmd" in
    tsuga\ logs\ search\ *)
      if has_from_to && has_max_results_10; then
        return 0
      fi
      return 1
      ;;
    tsuga\ traces\ search\ *)
      if has_from_to && has_max_results_10; then
        return 0
      fi
      return 1
      ;;
    tsuga\ logs\ patterns\ *|tsuga\ logs\ new-error-patterns\ *|tsuga\ logs\ error-pattern-increases\ *|tsuga\ logs\ attributes\ *|tsuga\ metrics\ list*|tsuga\ metrics\ get\ *)
      has_from_to
      return
      ;;
    tsuga\ metrics\ assets-usage\ *)
      return 0
      ;;
    tsuga\ aggregation\ scalar\ *|tsuga\ aggregation\ timeseries\ *)
      case "$cmd" in
        *" -d "*|*" --data "*)
          case "$cmd" in
            *timeRange*from*to*) return 0 ;;
          esac
          ;;
      esac
      return 1
      ;;
    tsuga\ services\ list*|tsuga\ services\ get\ *|tsuga\ teams\ list*|tsuga\ teams\ get\ *|tsuga\ monitors\ list*|tsuga\ monitors\ get\ *|tsuga\ dashboards\ list*|tsuga\ dashboards\ get\ *|tsuga\ routes\ list*|tsuga\ routes\ get\ *|tsuga\ notification-rules\ list*|tsuga\ notification-rules\ get\ *|tsuga\ notification-silences\ list*|tsuga\ notification-silences\ get\ *|tsuga\ quality-reports\ list*|tsuga\ docs\ search\ *|tsuga\ docs\ get\ *)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

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

  if is_read_only_tsuga_command "$cmd"; then
    passed=$((passed+1))
  else
    failed=$((failed+1))
    failures+=$'\n'"  FAIL: $(basename "$(dirname "$f")")"$'\n'"    unsafe or non-read-only command: $cmd"
  fi
done

total=$((passed + failed))

if [ $failed -eq 0 ] && [ $passed -gt 0 ]; then
  echo "PASS [sample-execute] $SKILL_DIR — $passed/$total commands audited as read-only"
  exit 0
elif [ $failed -gt 0 ]; then
  echo "FAIL [sample-execute] $SKILL_DIR — $failed/$total sampled commands are unsafe$failures"
  exit 1
else
  echo "WARN [sample-execute] $SKILL_DIR — 0 commands audited (none found in sampled files)"
  exit 0
fi
