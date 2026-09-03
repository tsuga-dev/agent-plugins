#!/bin/bash
# skill-lint: allow-forbidden-examples — the checker is allowed to name the patterns it hunts.
# check-forbidden-tokens.sh — flag MCP-tool pseudo-syntax, rtk prefix, and wrong CLI shape.
#
# Usage: check-forbidden-tokens.sh <skill-dir>
# Exit:  0 = PASS, 1 = FAIL, 2 = script error.

set -uo pipefail

SKILL_DIR="${1:-}"
if [ -z "$SKILL_DIR" ]; then
  echo "usage: $0 <skill-dir>" >&2
  exit 2
fi

if [ ! -d "$SKILL_DIR" ]; then
  echo "FAIL [forbidden] $SKILL_DIR — not a directory"
  exit 1
fi

# Files to scan, as paths. Raw data dumps (Slack exports, incident-tool JSON, bulk CSV
# inventories) are not docs and carry URL-encoded params that would false-positive.
#
# Teaching docs opt out with "skill-lint: allow-forbidden-examples" anywhere in the file: they
# contain the forbidden patterns as examples of what NOT to write. Opt-outs are excluded by path,
# not by basename — several skills have a LESSONS.md, and excluding the name would silence them all.
FILES=()
while IFS= read -r f; do
  case "$(basename "$f")" in
    messages.json | raw.json | thread-*.json | _inventory.csv) continue ;;
  esac
  grep -qE 'skill-lint: *allow-forbidden-examples' "$f" 2>/dev/null && continue
  FILES+=("$f")
done < <(find "$SKILL_DIR" -type f -not -path '*/.git/*')

if [ ${#FILES[@]} -eq 0 ]; then
  echo "PASS [forbidden] $SKILL_DIR — no files to check"
  exit 0
fi

fail=0

report() {
  local label="$1" hits="$2" note="${3:-}"
  local count
  count=$(printf '%s\n' "$hits" | grep -c . )
  echo "FAIL [forbidden:$label] $SKILL_DIR — $count hits${note:+ ($note)}"
  printf '%s\n' "$hits" | head -3 | sed 's/^/    /'
  fail=1
}

# 1. MCP-tool verbs at line start (pseudo-CLI that isn't runnable).
MCP_VERBS='^(search-logs|search-spans|list-metrics|get-metric|list-monitors|get-monitor|list-dashboards|get-dashboard|list-routes|get-route|list-teams|get-team|list-services|get-service|list-notification-rules|list-notification-silences|aggregate-scalar|aggregate-timeseries|list-log-patterns|list-new-error-patterns|list-error-pattern-increases)\b'
hits=$(grep -nE "$MCP_VERBS" "${FILES[@]}" 2>/dev/null)
[ -n "$hits" ] && report mcp-verbs "$hits"

# 2. MCP-tool arg shape (query=, from=-, to=now, …). URLs and JSON keys legitimately carry these,
# so strip those spans from each line before matching instead of dropping the whole line: a line
# holding both a URL and a real violation must still be reported. LC_ALL=C keeps BSD sed from
# aborting on a bundle's binary assets, which would skip that file's real violations too.
hits=$(
  for f in "${FILES[@]}"; do
    LC_ALL=C sed -E 's#https?://[^ )"`]*##g; s#/(explorer|analytics)\?[^ )"`]*##g; s#"(aggregationWindow|dataSource|filter|query)":##g' "$f" \
      | grep -nE '\bquery=|\bfrom=-|\bto=now\b|\blimit=|\bfilter=|\baggregationWindow=|\bdataSource=' \
      | sed "s#^#$f:#"
  done
)
[ -n "$hits" ] && report mcp-args "$hits"

# 3. rtk used as a command prefix. Prose mentioning the tool is fine, so require a real binary
# after it rather than any lowercase word.
hits=$(grep -nE '(^|[[:space:]`])rtk (tsuga|git|gh|yarn|node|npm|jq|grep|find|proxy)\b' "${FILES[@]}" 2>/dev/null)
[ -n "$hits" ] && report rtk-prefix "$hits"

# 4. Singular resource verbs. The pattern cannot match a plural (it requires a space straight
# after the singular noun), so no plural filter is needed — one would discard whole lines that
# contain both forms and turn a violation into a PASS.
hits=$(grep -nE 'tsuga (monitor|dashboard|log-route|team|service|notification-rule|notification-silence) (get|list|create|update|delete)' "${FILES[@]}" 2>/dev/null)
[ -n "$hits" ] && report singular-verb "$hits" "use plural: tsuga monitors get"

# 5. `tsuga spans search` → should be `tsuga traces search`.
hits=$(grep -n 'tsuga spans search' "${FILES[@]}" 2>/dev/null)
[ -n "$hits" ] && report spans-search "$hits" "use 'tsuga traces search'"

# 6. --limit on telemetry commands, which take --max-results. Resource commands (monitors,
# dashboards, …) are genuinely paginated with --limit, so they are not flagged.
hits=$(grep -nE 'tsuga (logs|traces|metrics|patterns|attributes|aggregation|interesting-fields) [a-z-]+ .*--limit\b' "${FILES[@]}" 2>/dev/null)
[ -n "$hits" ] && report limit-flag "$hits" "use --max-results"

if [ "$fail" -eq 0 ]; then
  echo "PASS [forbidden] $SKILL_DIR — 0 hits across all 6 patterns"
fi

exit $fail
