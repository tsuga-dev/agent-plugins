#!/bin/bash
# lint-all.sh — orchestrator, runs every health check against one or more skill dirs.
#
# Usage:
#   lint-all.sh                                   # auto-discover in standard paths
#   lint-all.sh <skill-dir> [<skill-dir> ...]     # lint specific dirs
#   lint-all.sh --execute                         # include sampled read-only command safety audit
#   lint-all.sh --quiet                           # suppress PASS lines, show only WARN/FAIL

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

EXECUTE=0
QUIET=0
targets=()

for arg in "$@"; do
  case "$arg" in
    --execute) EXECUTE=1 ;;
    --quiet)   QUIET=1 ;;
    --help|-h)
      sed -n '2,10p' "$0"
      exit 0
      ;;
    --*)
      echo "unknown flag: $arg" >&2
      exit 2
      ;;
    *)
      targets+=("$arg")
      ;;
  esac
done

# Auto-discovery: scan the standard paths for directories that contain a SKILL.md.
if [ ${#targets[@]} -eq 0 ]; then
  candidates=()
  [ -d "./skills" ]                  && candidates+=("./skills")
  [ -d "./plugins/tsuga/skills" ]     && candidates+=("./plugins/tsuga/skills")
  [ -d "$HOME/.claude/skills" ]      && candidates+=("$HOME/.claude/skills")
  [ -d "$HOME/.codex/skills" ]       && candidates+=("$HOME/.codex/skills")
  [ -d "./.agents/skills" ]          && candidates+=("./.agents/skills")

  for root in "${candidates[@]}"; do
    while IFS= read -r skill_md; do
      targets+=("$(dirname "$skill_md")")
    done < <(find "$root" -mindepth 1 -maxdepth 2 -name SKILL.md 2>/dev/null)
  done

  if [ ${#targets[@]} -eq 0 ]; then
    echo "No skill dirs found in ./skills, ~/.claude/skills, ~/.codex/skills, or ./.agents/skills." >&2
    echo "Pass a directory explicitly: $0 path/to/skill" >&2
    exit 2
  fi
fi

# Counters.
total_pass=0; total_warn=0; total_fail=0
failed_skills=()

for skill in "${targets[@]}"; do
  if [ ! -d "$skill" ]; then
    echo "FAIL [lint-all] $skill — not a directory"
    total_fail=$((total_fail+1))
    continue
  fi

  echo "=== $skill ==="

  # Collect output per check so we can count pass/warn/fail.
  outputs=()
  checks=(
    "check-frontmatter.sh"
    "check-skill-length.sh"
    "check-forbidden-tokens.sh"
    "check-incident-history.sh"
    "check-knowledge-company.sh"
  )
  [ "$EXECUTE" -eq 1 ] && checks+=("sample-execute-commands.sh")

  this_fail=0
  for c in "${checks[@]}"; do
    script="$SCRIPT_DIR/$c"
    result=$(bash "$script" "$skill" 2>&1 || true)
    # Count tokens in the result.
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      case "$line" in
        PASS\ *) total_pass=$((total_pass+1)); [ "$QUIET" -eq 0 ] && echo "$line" ;;
        WARN\ *) total_warn=$((total_warn+1)); echo "$line" ;;
        FAIL\ *) total_fail=$((total_fail+1)); this_fail=1; echo "$line" ;;
        *)       echo "$line" ;;
      esac
    done <<< "$result"
  done

  [ $this_fail -eq 1 ] && failed_skills+=("$skill")
  echo ""
done

# Summary.
echo "=== summary ==="
echo "PASS: $total_pass   WARN: $total_warn   FAIL: $total_fail"
if [ ${#failed_skills[@]} -gt 0 ]; then
  echo ""
  echo "Skills with failures:"
  printf '  %s\n' "${failed_skills[@]}"
fi

[ $total_fail -gt 0 ] && exit 1
exit 0
