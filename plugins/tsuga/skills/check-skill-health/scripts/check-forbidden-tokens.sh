#!/bin/bash
# skill-lint: allow-forbidden-examples — the checker is allowed to name the patterns it hunts.
# check-forbidden-tokens.sh — flag MCP-tool pseudo-syntax, rtk prefix, and wrong CLI shape.
#
# Usage: check-forbidden-tokens.sh <skill-dir>
# Exit:  0 = PASS, 1 = FAIL.

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

# Files we deliberately ignore: raw data dumps (Slack exports, incident-tool JSON,
# bulk CSV inventories) are not docs and naturally contain URL-encoded query params
# and other shapes that would fire false positives.
EXCL=(--exclude='messages.json' --exclude='raw.json' --exclude='thread-*.json' --exclude='_inventory.csv' --exclude-dir='.git')

# Build a list of files that opted out via magic marker — teaching docs (LESSONS.md,
# CLI_TRANSLATION.md, RULES.md, etc.) contain the forbidden patterns as examples of
# what NOT to write. They declare themselves exempt with:
#   "skill-lint: allow-forbidden-examples"
# anywhere in the file. Pass those as additional --exclude args to grep.
while IFS= read -r f; do
  EXCL+=(--exclude="$(basename "$f")")
done < <(grep -rlE 'skill-lint: *allow-forbidden-examples' "$SKILL_DIR" 2>/dev/null)

fail=0

# 1. MCP-tool verbs at line start (pseudo-CLI that isn't runnable).
mcp_hits=$(grep -rnE "${EXCL[@]}" '^(search-logs|search-spans|list-metrics|get-metric|list-monitors|get-monitor|list-dashboards|get-dashboard|list-routes|list-teams|list-services|get-service|list-notification-rules|list-notification-silences|aggregate-scalar|aggregate-timeseries|list-log-patterns|list-new-error-patterns|list-error-pattern-increases)\b' "$SKILL_DIR" 2>/dev/null | wc -l | tr -d ' ')
if [ "$mcp_hits" -gt 0 ]; then
  echo "FAIL [forbidden:mcp-verbs] $SKILL_DIR — $mcp_hits hits"
  grep -rnE "${EXCL[@]}" '^(search-logs|search-spans|list-metrics|get-metric|list-monitors|get-monitor|list-dashboards|get-dashboard|list-routes|list-teams|list-services|get-service|list-notification-rules|list-notification-silences|aggregate-scalar|aggregate-timeseries|list-log-patterns|list-new-error-patterns|list-error-pattern-increases)\b' "$SKILL_DIR" 2>/dev/null | head -3 | sed 's/^/    /'
  fail=1
fi

# 2. MCP-tool arg shape (query=, from=-, to=now, etc.) — excluding JSON keys and URL params.
# Lines containing a Tsuga UI URL (`app.tsuga.com/`) are skipped because URLs
# legitimately carry `?query=…&filter=…&groupBy=…` params that would false-positive.
arg_hits=$(grep -rnE "${EXCL[@]}" '\bquery=|\bfrom=-|\b to=now\b|\blimit=|\bfilter=|\baggregationWindow=|\bdataSource=' "$SKILL_DIR" 2>/dev/null \
  | grep -v '"aggregationWindow":' \
  | grep -v '"dataSource":' \
  | grep -v '"filter":' \
  | grep -v 'app.tsuga.com/' \
  | grep -v 'app\.tsuga\.com/' \
  | grep -v '/explorer?' \
  | grep -v '/analytics?' \
  | wc -l | tr -d ' ')
if [ "$arg_hits" -gt 0 ]; then
  echo "FAIL [forbidden:mcp-args] $SKILL_DIR — $arg_hits hits"
  grep -rnE "${EXCL[@]}" '\bquery=|\bfrom=-|\b to=now\b|\blimit=|\bfilter=|\baggregationWindow=|\bdataSource=' "$SKILL_DIR" 2>/dev/null \
    | grep -v '"aggregationWindow":' \
    | grep -v '"dataSource":' \
    | grep -v '"filter":' \
    | grep -v 'app.tsuga.com/' \
    | grep -v 'app\.tsuga\.com/' \
    | grep -v '/explorer?' \
    | grep -v '/analytics?' \
    | head -3 | sed 's/^/    /'
  fail=1
fi

# 3. rtk prefix on commands (not prose mentioning the tool name).
rtk_hits=$(grep -rnE "${EXCL[@]}" '^rtk |[[:space:]]rtk [a-z]' "$SKILL_DIR" 2>/dev/null | wc -l | tr -d ' ')
if [ "$rtk_hits" -gt 0 ]; then
  echo "FAIL [forbidden:rtk-prefix] $SKILL_DIR — $rtk_hits hits"
  grep -rnE "${EXCL[@]}" '^rtk |[[:space:]]rtk [a-z]' "$SKILL_DIR" 2>/dev/null | head -3 | sed 's/^/    /'
  fail=1
fi

# 4. Singular resource verbs (tsuga monitor get, etc. — CLI wants plural).
sing_hits=$(grep -rnE "${EXCL[@]}" 'tsuga (monitor|dashboard|route|team|service|notification-rule|notification-silence) (get|list|create|update|delete)' "$SKILL_DIR" 2>/dev/null \
  | grep -vE 'tsuga (monitors|dashboards|routes|teams|services|notification-rules|notification-silences) (get|list|create|update|delete)' \
  | wc -l | tr -d ' ')
if [ "$sing_hits" -gt 0 ]; then
  echo "FAIL [forbidden:singular-verb] $SKILL_DIR — $sing_hits hits (use plural: tsuga monitors get, not tsuga monitor get)"
  grep -rnE "${EXCL[@]}" 'tsuga (monitor|dashboard|route|team|service|notification-rule|notification-silence) (get|list|create|update|delete)' "$SKILL_DIR" 2>/dev/null \
    | grep -vE 'tsuga (monitors|dashboards|routes|teams|services|notification-rules|notification-silences) (get|list|create|update|delete)' \
    | head -3 | sed 's/^/    /'
  fail=1
fi

# 5. `tsuga spans search` → should be `tsuga traces search`.
spans_hits=$(grep -rn "${EXCL[@]}" 'tsuga spans search' "$SKILL_DIR" 2>/dev/null | wc -l | tr -d ' ')
if [ "$spans_hits" -gt 0 ]; then
  echo "FAIL [forbidden:spans-search] $SKILL_DIR — $spans_hits hits (use 'tsuga traces search')"
  grep -rn "${EXCL[@]}" 'tsuga spans search' "$SKILL_DIR" 2>/dev/null | head -3 | sed 's/^/    /'
  fail=1
fi

# 6. --limit flag (should be --max-results).
limit_hits=$(grep -rnE "${EXCL[@]}" 'tsuga [a-z]+ [a-z]+ .*--limit\b' "$SKILL_DIR" 2>/dev/null | wc -l | tr -d ' ')
if [ "$limit_hits" -gt 0 ]; then
  echo "FAIL [forbidden:limit-flag] $SKILL_DIR — $limit_hits hits (use --max-results)"
  grep -rnE "${EXCL[@]}" 'tsuga [a-z]+ [a-z]+ .*--limit\b' "$SKILL_DIR" 2>/dev/null | head -3 | sed 's/^/    /'
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS [forbidden] $SKILL_DIR — 0 hits across all 6 patterns"
fi

exit $fail
