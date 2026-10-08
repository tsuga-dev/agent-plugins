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
MCP_VERBS='^(aggregate-scalar|aggregate-timeseries|create-dashboard|create-investigation|create-monitor|delete-dashboard|delete-investigation|get-contrast-sets|get-dashboard|get-doc-page|get-investigation|get-metric|get-metric-assets-usage|get-monitor|get-notification-rule|get-route|get-service|get-team|list-clusters|query-dashboards|list-error-pattern-increases|list-investigations|list-log-attributes|list-metrics|query-monitors|list-new-error-patterns|list-notification-rules|list-quality-reports|list-routes|query-services|list-teams|query-promql|search-docs|search-logs|search-spans|update-dashboard|update-dashboard-graph|update-investigation)\b'
hits=$(grep -nE "$MCP_VERBS" "${FILES[@]}" 2>/dev/null)
[ -n "$hits" ] && report mcp-verbs "$hits"

# 2. MCP-tool arg shape (query=, from=-, to=now, …) written as bare tokens. The leading
# (^|[^-[:alnum:]_]) keeps the word-boundary intent while excluding a `--` prefix: the CLI itself
# requires `--from=-1h`, because a bare `-1h` lexes into the short options `-1` and `-h`.
# URLs and JSON keys legitimately carry these,
# so strip those spans from each line before matching instead of dropping the whole line: a line
# holding both a URL and a real violation must still be reported. LC_ALL=C keeps BSD sed from
# aborting on a bundle's binary assets, which would skip that file's real violations too.
hits=$(
  for f in "${FILES[@]}"; do
    LC_ALL=C sed -E 's#https?://[^ )"`]*##g; s#/(explorer|analytics)\?[^ )"`]*##g; s#"(aggregationWindow|dataSource|filter|query)":##g' "$f" \
      | grep -nE '(^|[^-[:alnum:]_])(query=|from=-|to=now|limit=|filter=|aggregationWindow=|dataSource=)' \
      | sed "s#^#$f:#"
  done
)
[ -n "$hits" ] && report mcp-args "$hits"

# 3. rtk used as a command prefix. Prose mentioning the tool is fine, so require a real binary
# after it rather than any lowercase word.
hits=$(grep -nE '(^|[[:space:]`])rtk (tsuga|git|gh|yarn|node|npm|jq|grep|find|proxy)\b' "${FILES[@]}" 2>/dev/null)
[ -n "$hits" ] && report rtk-prefix "$hits"

# 4. Singular resource verbs. Every resource group in the CLI is plural, so the singular is always
# wrong. The pattern cannot match a plural (it requires a space straight after the singular noun),
# so no plural filter is needed — one would discard whole lines that contain both forms and turn a
# violation into a PASS.
SINGULAR='monitor|dashboard|dashboard-folder|log-route|team|service|slo|investigation|retention-policy|tag-policy|quality-report|public-token|ingestion-api-key|cloud-resource|notification-rule|notification-silence|notification-integration'
hits=$(grep -nE "tsuga ($SINGULAR) (get|list|create|update|delete)" "${FILES[@]}" 2>/dev/null)
[ -n "$hits" ] && report singular-verb "$hits" "use plural: tsuga monitors get"

# 5. Command groups that do not exist. The telemetry groups are logs, traces, metrics and rum;
# `tsuga spans search`, `tsuga trace get`, `tsuga alerts list` and friends are invented. These
# spellings stay wrong whatever the CLI adds, because a group name is never singular and the
# telemetry nouns are already taken. Required to be in command position — at line start or opening
# an inline code span — so prose like "the tsuga trace summary" is not flagged.
hits=$(grep -nE '(^|`)tsuga (span|spans|trace|log|metric|event|events|alert|alerts|incident|incidents|query|search) [a-z]' "${FILES[@]}" 2>/dev/null)
[ -n "$hits" ] && report no-such-group "$hits" "groups are logs, traces, metrics, rum, aggregation"

# 6. --limit on telemetry commands, which take --max-results. Resource commands (monitors,
# dashboards, …) are genuinely paginated with --limit, so they are not flagged.
hits=$(grep -nE 'tsuga (logs|traces|metrics|rum|aggregation|interesting-fields) [a-z-]+ .*--limit\b' "${FILES[@]}" 2>/dev/null)
[ -n "$hits" ] && report limit-flag "$hits" "use --max-results"

if [ "$fail" -eq 0 ]; then
  echo "PASS [forbidden] $SKILL_DIR — 0 hits across all 6 patterns"
fi

exit $fail
