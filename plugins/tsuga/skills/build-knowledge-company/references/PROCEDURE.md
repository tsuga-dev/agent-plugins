<!-- skill-lint: allow-forbidden-examples — procedure references forbidden patterns when describing gates -->

# PROCEDURE — phases for building knowledge-company

Ordered. Each phase has a clear completion signal. Do not skip ahead.

## Phase 0 — access check

Before touching the output tree:

```bash
tsuga --version                                  # must succeed
tsuga teams list      | jq 'length'              # > 0
tsuga services list   | jq 'length'              # > 0
tsuga monitors list   | jq 'length'              # > 0
tsuga dashboards list | jq 'length'              # > 0
tsuga routes list     | jq 'length'              # > 0
gh auth status                                   # authenticated

# Aggregation body path — exercise once to confirm heredoc shape works
FROM=$(date -u -v-5M +%s); TO=$(date -u +%s)
cat > /tmp/q.json <<JSON
{"timeRange":{"from":$FROM,"to":$TO},"dataSource":"logs","queries":[{"aggregate":{"type":"count"},"filter":"*"}],"formula":"q1"}
JSON
tsuga aggregation scalar -f /tmp/q.json          # returns {"results":[{"id":"q1","group":{},"value":N}]}
```

All four `list`s non-empty + the scalar aggregation returning a number = **go**. Anything else → fix auth, verify `--agent-type` env, or raise bandwidth with the account owner before continuing. The procedure will burn hours of subagent work if credentials drop mid-fanout.

## Phase 1 — discover the team taxonomy (live)

```bash
OUT=./skills/knowledge-company/references
mkdir -p "$OUT/teams"

# Dump teams
tsuga teams list > /tmp/teams-raw.json
jq 'length as $n | "discovered \($n) teams"' /tmp/teams-raw.json

# For each team, record id, name, visibility, and note whether it has owned monitors/dashboards/services
jq -r '.[] | [.id, .name, .visibility // "private"] | @tsv' /tmp/teams-raw.json > /tmp/team-index.tsv
cat /tmp/team-index.tsv
```

Not every team needs a TEAM_KNOWLEDGE.md — user-only teams (design, advisors) and POC bystanders (e.g., a single-person team with zero services) can be skipped. Score each team:

```bash
# For each team id, count monitors, dashboards, services
while IFS=$'\t' read -r team_id team_name vis; do
  monitors=$(tsuga monitors list | jq "[.[] | select(.owner == \"$team_id\")] | length")
  dashboards=$(tsuga dashboards list --owners "$team_id" | jq 'length')
  services=$(tsuga services list | jq "[.[] | select(.teams[]? == \"$team_id\")] | length")
  printf '%s\t%s\t%s\t%s\t%s\n' "$team_id" "$team_name" "$monitors" "$dashboards" "$services"
done < /tmp/team-index.tsv > /tmp/team-score.tsv
sort -k3,3nr -k5,5nr /tmp/team-score.tsv
```

**Decision rule:** teams with 0 monitors AND 0 dashboards AND 0 services don't get a TEAM_KNOWLEDGE.md. Everyone else does.

## Phase 2 — discover notification fanout + routes + metrics inventory

These feed the top-level docs:

```bash
tsuga notification-rules list > /tmp/notification-rules.json
tsuga routes list              > /tmp/routes.json
tsuga metrics list             > /tmp/metrics.json

# Service-to-log-volume table (fuel for service scoring)
FROM=$(date -u -v-7d +%s); TO=$(date -u +%s)
cat > /tmp/svc-vol-q.json <<JSON
{"timeRange":{"from":$FROM,"to":$TO},"dataSource":"logs","queries":[{"aggregate":{"type":"count"},"filter":"context.env:prod"}],"groupBy":[{"fields":["context.service.name"],"limit":500}],"formula":"q1"}
JSON
tsuga aggregation scalar -f /tmp/svc-vol-q.json > /tmp/svc-volume-7d.json

jq '.results | map(select(.value != null)) | sort_by(-.value) | .[:50] | map({svc: .group."context.service.name", vol: .value})' /tmp/svc-volume-7d.json
```

Spot-check the top-20 service names against what you expect — if a service you know is critical doesn't appear, it may be emitting under a different `context.service.name` than you think (OR-matched alias, see `LESSONS.md §"Service-name collisions"`).

## Phase 3 — score + pick services to dossier

You do NOT write a SERVICE_KNOWLEDGE.md for every service in `tsuga services list` (there can be hundreds of platform / ecosystem services — kube-proxy, cert-manager, etc., none of which are Tsuga-specific). You write one for:

1. Every service whose logs+traces in the last 7 days are in the top ~40 by volume,
2. **plus** every service that is the target of ≥1 monitor or dashboard by name,
3. **plus** every service referenced in ≥5 incident SUMMARY.md files.

Compute the ranking:

```bash
# Top by volume
jq -r '.results[] | [.group."context.service.name", .value] | @tsv' /tmp/svc-volume-7d.json | sort -k2,2nr | head -60 > /tmp/top-by-vol.tsv

# Services targeted by a monitor's name
jq -r '.[] | .name' /tmp/service-data-monitors.json 2>/dev/null \
  || jq -r '.[] | .name' <(tsuga monitors list) \
  | awk 'match($0, /([a-z][a-z0-9-]*-)+[a-z][a-z0-9-]*/) { print substr($0, RSTART, RLENGTH) }' \
  | sort -u > /tmp/monitor-named-services.txt

# Services with incident mentions (≥5)
grep -rh "context.service.name:\([a-z0-9-]*\)" skills/incident-history/references/incidents/*/SUMMARY.md \
  | grep -oE "context.service.name:[a-z0-9-]+" \
  | sort | uniq -c | awk '$1>=5 {print $2}' > /tmp/incident-referenced-services.txt

# Union all three → final service list
{ cat /tmp/top-by-vol.tsv | awk '{print $1}'; cat /tmp/monitor-named-services.txt; cat /tmp/incident-referenced-services.txt; } \
  | sort -u > /tmp/services-to-dossier.txt
wc -l /tmp/services-to-dossier.txt
```

**Expected:** 25–40 services. If you get <15, the scoring is too narrow (or the deployment is small). If you get >60, you're including platform infra (kube-proxy, karpenter-controller, etc.) — add an exclusion list for `platform/infrastructure` services that don't belong to Tsuga product teams.

Manually sanity-check the list. Add services that obviously should be there and are missing (`web-backend` is always the top candidate to sanity-check). Remove services that are clearly infrastructure bystanders.

## Phase 4 — per-service helper extraction

For each service in `/tmp/services-to-dossier.txt`, extract:

```bash
SVC_DATA=/tmp/service-data
mkdir -p "$SVC_DATA"
while read svc; do
  mkdir -p "$SVC_DATA/$svc"

  # Monitors targeting this service — match by name OR by filter containing the service
  jq --arg s "$svc" '[.[] | select(
    (.name | contains($s)) or
    (.configuration.query // "" | contains($s)) or
    (.configuration.options.query // "" | contains($s)) or
    (.graph_names // [] | any((. // "") | contains($s)))
  )]' <(tsuga monitors list) > "$SVC_DATA/$svc/monitors.json"

  # Dashboards
  jq --arg s "$svc" '[.[] | select(
    (.name | contains($s)) or
    (.graph_names // [] | any((. // "") | contains($s)))
  )]' <(tsuga dashboards list) > "$SVC_DATA/$svc/dashboards.json"

  # Incident files mentioning the service
  grep -l "context.service.name:${svc}" skills/incident-history/references/incidents/*/SUMMARY.md 2>/dev/null \
    > "$SVC_DATA/$svc/incident-files.txt"
done < /tmp/services-to-dossier.txt
```

This is the single biggest speedup in the whole procedure. Per-service helper files mean each subagent reads ~10 KB of pre-digested input instead of the full fleet dump.

## Phase 5 — write top-level docs

Three files (not four — `RAW_TELEMETRY_KNOWLEDGE.md` is intentionally not produced; its content is folded into `COMPANY_TELEMETRY_KNOWLEDGE.md`):

### `COMPANY_GENERAL_KNOWLEDGE.md`

Narrative: what the company is, its architecture, its codebases, its team roster. Pulls from `inputs/raw-docs/company-architecture.md` and `inputs/raw-docs/team-charters/*.md` if present, otherwise synthesized from:

- `tsuga teams list` for the team roster
- `inputs/codebase-repos.json` for the repo → team mapping
- Ambient knowledge / onboarding docs

Write this one yourself (orchestrator). Not a subagent task — it's narrative and short (~150 lines).

### `COMPANY_TELEMETRY_KNOWLEDGE.md`

Reference: environments, clusters, service-identity rules, context attributes, metric naming, dashboards of note, monitor P1 digest, log-pipeline flow, **team operational weight at a glance**, **notification-rule fanout**, **canonical query patterns**, **investigation starting points by symptom shape**, closing naming gotchas.

Write yourself. Pulls from `/tmp/teams-raw.json`, `/tmp/notification-rules.json`, `/tmp/routes.json`, `/tmp/metrics.json`, `/tmp/team-score.tsv`, plus the log-pipeline description from internal processing docs. ~500 lines.

## Phase 6 — write per-team dossiers (serial, by orchestrator)

For each team in `/tmp/team-score.tsv`, write `teams/<team>/TEAM_KNOWLEDGE.md` following `TEAM_KNOWLEDGE_TEMPLATE.md`. These are short (60–120 lines), are narrative, and benefit from the orchestrator's broader context (cross-team references). **Do not fan out to subagents for this phase** — a subagent doesn't have the visibility to explain cross-team ownership splits (e.g., a service whose code is owned by one team but whose paging monitors are owned by another).

Per-team inputs the orchestrator uses:

- `/tmp/teams-raw.json[<team>]` for metadata
- `jq '.[] | select(.owner == "<team_id>")' <(tsuga monitors list)` for owned monitors
- `tsuga dashboards list --owners <team_id>` for owned dashboards
- `jq '.[] | select(.teams[]? == "<team_id>")' <(tsuga services list)` for owned services

## Phase 7 — write per-service dossiers (parallel, subagent per service)

**This is the big fan-out.** For each service in `/tmp/services-to-dossier.txt`, spawn one subagent with:

- Service name + owning team ID
- Template path: `$SETUP/build-knowledge-company/references/SERVICE_KNOWLEDGE_TEMPLATE.md`
- Lessons path: `$SETUP/build-knowledge-company/references/LESSONS.md`
- CLI translation contract: `$SETUP/build-knowledge-company/references/CLI_TRANSLATION.md`
- Helper input paths: `/tmp/service-data/<svc>/{monitors.json, dashboards.json, incident-files.txt}`
- Top-level refs (pointers only — subagent must not duplicate from these): `$OUT/COMPANY_GENERAL_KNOWLEDGE.md`, `$OUT/COMPANY_TELEMETRY_KNOWLEDGE.md`
- Team context: `$OUT/teams/<team>/TEAM_KNOWLEDGE.md`
- Output path: `$OUT/teams/<team>/services/<svc>/SERVICE_KNOWLEDGE.md` (subagent must `mkdir -p`)

Prompt template: `SUBAGENT_PROMPT.md` — copy verbatim, substitute `{svc}` + `{team}` + `{team_id}`.

**Batch size:** 8–12 in parallel is the sweet spot. Wider batches hit MCP rate limits; narrower batches waste wall-clock time. The first-pass `knowledge-company` used 4 waves of 8 subagents each.

**Do NOT claim Phase 7 complete before Gate 4 of `VERIFICATION.md` passes.**

## Phase 8 — verification

Run `VERIFICATION.md`'s full gate set. The two gates you cannot skip:

- **Gate 4 — forbidden tokens.** Every SERVICE_KNOWLEDGE.md must be free of MCP-tool pseudo-syntax (`search-logs`, `aggregate-timeseries`, `query=`, `from=-`, etc.) and `rtk` prefixes.
- **Gate 5 — sampled execution.** Pick 5 random SERVICE_KNOWLEDGE.md files, copy every `tsuga` command in their Ready-to-run section into a shell, confirm it executes. If any fail, it is a fleet-wide template bug — fix the template and regenerate the affected batch.

If Gate 4 or Gate 5 fails, you do NOT hand-patch the affected files. Fix the root template / prompt / lesson doc, then re-run Phase 7 for just the failing services.

## Phase 9 — cross-link and commit

Cross-links to verify:

- Top-level `COMPANY_GENERAL_KNOWLEDGE.md` references the team list — must match `teams/` directory contents.
- `COMPANY_TELEMETRY_KNOWLEDGE.md §"Investigation starting points by symptom shape"` table — every service it names must have a corresponding `SERVICE_KNOWLEDGE.md`.
- Every `SERVICE_KNOWLEDGE.md` references `../../TEAM_KNOWLEDGE.md` at least once (Upstream / downstream or Dashboards section).

```bash
OUT=./skills/knowledge-company/references
# Services named in COMPANY_TELEMETRY's symptom table vs actual dossier files
grep -oE "`[a-z][a-z0-9-]+`" "$OUT/COMPANY_TELEMETRY_KNOWLEDGE.md" | sort -u > /tmp/svc-named-in-top.txt
find "$OUT/teams" -name SERVICE_KNOWLEDGE.md -path '*/services/*' | awk -F/ '{print "`" $(NF-1) "`"}' | sort -u > /tmp/svc-dossier-files.txt
comm -23 /tmp/svc-named-in-top.txt /tmp/svc-dossier-files.txt | head    # named but no dossier (may be intentional)
comm -13 /tmp/svc-named-in-top.txt /tmp/svc-dossier-files.txt | head    # dossier exists but not in top — fine
```

Commit in logical chunks:

1. Top-level docs (`COMPANY_*.md`) + `SKILL.md`.
2. `TEAM_KNOWLEDGE.md` × all teams.
3. `SERVICE_KNOWLEDGE.md` × all services (can be one commit).

Do not push until someone has read 5 random SERVICE_KNOWLEDGE.md files cover-to-cover and confirmed they read coherently. Subagents will produce "plausible but vacuous" output when their inputs are thin — the human eye is the only reliable filter.
