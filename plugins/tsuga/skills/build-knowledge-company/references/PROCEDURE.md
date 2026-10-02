<!-- skill-lint: allow-forbidden-examples — the gate descriptions name the forbidden patterns -->

# PROCEDURE — phases for building knowledge-company

Ordered. Each phase has a clear completion signal. Do not skip ahead.

- [Identity fields, once](#identity-fields-once) — how teams, monitors and services each name a team
- [Phase 0 — access check](#phase-0--access-check)
- [Phase 1 — discover the team taxonomy](#phase-1--discover-the-team-taxonomy-live)
- [Phase 2 — notification fanout, routes, metric inventory](#phase-2--notification-fanout-routes-metric-inventory)
- [Phase 3 — score and pick services to dossier](#phase-3--score-and-pick-services-to-dossier)
- [Phase 4 — per-service helper extraction](#phase-4--per-service-helper-extraction)
- [Phase 5 — write the top-level docs](#phase-5--write-the-top-level-docs)
- [Phase 6 — write per-team dossiers](#phase-6--write-per-team-dossiers-serial-by-orchestrator)
- [Phase 7 — write per-service dossiers](#phase-7--write-per-service-dossiers-parallel-subagent-per-service)
- [Phase 8 — verification](#phase-8--verification)
- [Phase 9 — cross-link and commit](#phase-9--cross-link-and-commit)

## Identity fields, once

Three lookups disagree about how they name a team, and every phase below depends on getting it
right:

- `tsuga teams list` → `.id` (`jqzx-rd5j6-k084`) and `.name` (`central`).
- `tsuga monitors list` / `tsuga dashboards list` → `.owner` is the team **id**.
- `tsuga services list` → `.teams` is an array of objects, `[{"team": "central", "lastSeenAt": …}]`,
  keyed by team **name**.

Comparing `.teams[]` to an id, or to a bare string, silently matches nothing and scores every team
at zero. `services list` also returns one row per service/env sighting, not one per service, so
every count over it needs `map(.serviceName) | unique` first.

## Phase 0 — access check

```bash
tsuga --version                                  # must succeed
tsuga auth whoami                                # calls the API: proves the token works, not just that one is stored
tsuga teams list      | jq 'length'              # > 0
tsuga services list   | jq 'length'              # > 0
tsuga monitors list   | jq 'length'              # > 0
tsuga dashboards list | jq 'length'              # > 0
tsuga log-routes list | jq 'length'              # > 0

# Aggregation body path — exercise once to confirm the heredoc shape works
TO=$(date -u +%s); FROM=$((TO - 300))            # 5 minutes; portable on BSD and GNU
cat > /tmp/q.json <<JSON
{"timeRange":{"from":$FROM,"to":$TO},"dataSource":"logs","queries":[{"aggregate":{"type":"count"},"filter":"*"}]}
JSON
tsuga aggregation scalar -f /tmp/q.json          # returns {"results":[{"id":"q1","group":{},"value":N}]}
```

All five lists non-empty plus a scalar aggregation returning a number = **go**. Anything else, fix
auth before continuing: the procedure burns hours of subagent work if credentials drop mid-fanout.
On a multi-cluster account, pin `--cluster <id>` on every call or set a default — otherwise a
phase can read a different cluster than the one you scored.

## Phase 1 — discover the team taxonomy (live)

```bash
OUT=./skills/knowledge-company/references
mkdir -p "$OUT/teams"

tsuga teams list --limit 1000 > /tmp/teams-raw.json
jq 'length as $n | "discovered \($n) teams"' /tmp/teams-raw.json

jq -r '.[] | [.id, .name, .visibility // "private"] | @tsv' /tmp/teams-raw.json > /tmp/team-index.tsv
```

Not every team needs a TEAM_KNOWLEDGE.md — user-only teams (design, advisors) and bystanders with
zero services can be skipped. Score each one, caching the fleet dumps so the loop does not re-fetch
them per team:

```bash
tsuga monitors list   --limit 1000 > /tmp/monitors-raw.json
tsuga services list   --limit 1000 > /tmp/services-raw.json
tsuga dashboards list --limit 1000 > /tmp/dashboards-raw.json

while IFS=$'\t' read -r team_id team_name vis; do
  monitors=$(jq --arg id "$team_id" '[.[] | select(.owner == $id)] | length' /tmp/monitors-raw.json)
  dashboards=$(jq --arg id "$team_id" '[.[] | select(.owner == $id)] | length' /tmp/dashboards-raw.json)
  services=$(jq --arg n "$team_name" '[.[] | select(any(.teams[]?; .team == $n))] | map(.serviceName) | unique | length' /tmp/services-raw.json)
  printf '%s\t%s\t%s\t%s\t%s\n' "$team_id" "$team_name" "$monitors" "$dashboards" "$services"
done < /tmp/team-index.tsv > /tmp/team-score.tsv
sort -k3,3nr -k5,5nr /tmp/team-score.tsv
```

**Decision rule:** a team with 0 monitors AND 0 dashboards AND 0 services gets no
TEAM_KNOWLEDGE.md. Everyone else does.

## Phase 2 — notification fanout, routes, metric inventory

These feed the top-level docs:

```bash
tsuga notification-rules list --limit 1000 > /tmp/notification-rules.json
tsuga log-routes list         --limit 1000 > /tmp/routes.json
tsuga metrics list                         > /tmp/metrics.json

# Service-to-volume table (fuel for service scoring). `dataSource` is body-level, so logs and
# traces need one call each; ranking on logs alone buries a well-instrumented, log-quiet API.
TO=$(date -u +%s); FROM=$((TO - 604800))
for SRC in logs traces; do
  cat > /tmp/svc-vol-q.json <<JSON
{"timeRange":{"from":$FROM,"to":$TO},"dataSource":"$SRC","queries":[{"aggregate":{"type":"count"},"filter":"context.env:prod"}],"groupBy":[{"fields":["context.service.name"],"limit":500}]}
JSON
  tsuga aggregation scalar -f /tmp/svc-vol-q.json > "/tmp/svc-volume-7d-$SRC.json"
done

# Sum the two per service, ranked
jq -s '[.[].results[] | select(.value != null)]
       | group_by(.group."context.service.name")
       | map({svc: .[0].group."context.service.name", vol: (map(.value) | add)})
       | sort_by(-.vol)' /tmp/svc-volume-7d-logs.json /tmp/svc-volume-7d-traces.json \
  > /tmp/svc-volume-7d.json

jq '.[:50]' /tmp/svc-volume-7d.json
```

`tsuga metrics list` returns the cluster's metric-name catalog and ignores `--from` / `--to`, so
read it as the set of names the cluster knows, not as what is emitting right now — see
`LESSONS.md §15`.

Spot-check the top 20 service names against what you expect. A service you know is critical but
that does not appear is probably emitting under a second `context.service.name`
(`LESSONS.md §9`).

## Phase 3 — score and pick services to dossier

You do not write a dossier for every row in `tsuga services list`; most large deployments carry
hundreds of ecosystem services (kube-proxy, cert-manager) that belong to nobody's product team. You
write one for the union of:

1. every service in the top ~40 by 7-day log+trace volume,
2. every service that is the target of ≥1 monitor or dashboard by name,
3. every service referenced in ≥5 incident SUMMARY.md files.

```bash
# Top by volume — already sorted by Phase 2
jq -r '.[] | [.svc, .vol] | @tsv' /tmp/svc-volume-7d.json | head -40 > /tmp/top-by-vol.tsv

# Services targeted by a monitor's name. Monitor titles are prose ("Production web-backend P95"),
# so split them into words and keep only the ones that are real service names — matching a bare
# lowercase run against the title would pull out mid-word fragments and ordinary English words,
# and every one of those spawns a subagent for a service that does not exist.
jq -r '.[] | .serviceName' /tmp/services-raw.json | sort -u > /tmp/all-services.txt
jq -r '.[] | .name' /tmp/monitors-raw.json \
  | tr -cs 'a-zA-Z0-9-' '\n' \
  | sed -E 's/-[A-Z][A-Za-z0-9]*$//' \
  | sort -u \
  | grep -Fxf /tmp/all-services.txt > /tmp/monitor-named-services.txt

# Services with ≥5 incident mentions. A SUMMARY.md quotes service names both in CLI filters and
# inside pasted app deep links, where the colon arrives percent-encoded — match both spellings.
grep -rhoE "context\.service\.name(:|%3A)[a-z0-9-]+" skills/incident-history/references/incidents/*/SUMMARY.md \
  | sed -E 's/^context\.service\.name(:|%3A)//' \
  | sort | uniq -c | awk '$1>=5 {print $2}' > /tmp/incident-referenced-services.txt

{ awk '{print $1}' /tmp/top-by-vol.tsv
  cat /tmp/monitor-named-services.txt
  cat /tmp/incident-referenced-services.txt
} | sort -u > /tmp/services-to-dossier.txt
wc -l /tmp/services-to-dossier.txt

# The three sources name services in three different spaces, and `sort -u` cannot merge them:
# telemetry group names, catalog rows and whatever an incident responder typed. List the
# candidates with no catalog row — they are where the duplicates hide.
comm -23 /tmp/services-to-dossier.txt /tmp/all-services.txt
```

**Expected:** 40–60. Criterion 1 alone contributes 40, so the union only grows from there; past
~60, platform infrastructure is leaking in and wants an exclusion list.

Resolve the `comm` output by hand before fanning out — this is the step that stops one service
getting two dossiers. A candidate that is a second telemetry name for a catalog service
(`LESSONS.md §9`) merges into that service's entry; a genuine engine role (`LESSONS.md §8`) or a
high-volume emitter with no catalog row stays on its own; the rest are infrastructure bystanders
and get dropped. Then add the obvious omissions.

## Phase 4 — per-service helper extraction

The single biggest speedup in the procedure: each subagent then reads ~10 KB of pre-digested input
instead of the full fleet dump.

A monitor's filter lives at `.configuration.queries[].filter`, and a dashboard's graph titles at
`.graphs[].name`. Match on those, not on a flattened field name:

```bash
SVC_DATA=/tmp/service-data
mkdir -p "$SVC_DATA"
tsuga dashboards list --limit 1000 > /tmp/dashboards-raw.json

while read -r svc; do
  mkdir -p "$SVC_DATA/$svc"

  # Monitors targeting this service — by title or by a query filter naming it
  jq --arg s "$svc" '[.[] | select(
    (.name | contains($s)) or
    (any(.configuration.queries[]?; (.filter // "") | contains($s)))
  )]' /tmp/monitors-raw.json > "$SVC_DATA/$svc/monitors.json"

  # Dashboards — by title or by a graph title naming it
  jq --arg s "$svc" '[.[] | select(
    (.name | contains($s)) or
    (any(.graphs[]?; (.name // "") | contains($s)))
  )]' /tmp/dashboards-raw.json > "$SVC_DATA/$svc/dashboards.json"

  # Incident files mentioning the service
  grep -lE "context\.service\.name(:|%3A)${svc}([^a-zA-Z0-9_-]|$)" \
    skills/incident-history/references/incidents/*/SUMMARY.md 2>/dev/null \
    > "$SVC_DATA/$svc/incident-files.txt"
done < /tmp/services-to-dossier.txt
```

## Phase 5 — write the top-level docs

Two files. `RAW_TELEMETRY_KNOWLEDGE.md` is not one of them; its content belongs in
`COMPANY_TELEMETRY_KNOWLEDGE.md`, and the linter fails a tree that carries it.

### `COMPANY_GENERAL_KNOWLEDGE.md`

Narrative: what the company is, its architecture, its codebases, its team roster. Pulls from
`inputs/raw-docs/company-architecture.md` and `inputs/raw-docs/team-charters/*.md` when present,
otherwise synthesized from `tsuga teams list`, `inputs/codebase-repos.json`, and onboarding docs.

The orchestrator writes this, not a subagent — it is narrative and short (~150 lines).

### `COMPANY_TELEMETRY_KNOWLEDGE.md`

Reference: environments, clusters, service-identity rules, context attributes, metric naming,
dashboards of note, monitor P1 digest, log-pipeline flow, team operational weight at a glance,
notification-rule fanout, canonical query patterns, investigation starting points by symptom shape,
closing naming gotchas.

Also the orchestrator. Pulls from `/tmp/teams-raw.json`, `/tmp/notification-rules.json`,
`/tmp/routes.json`, `/tmp/metrics.json`, `/tmp/team-score.tsv`. ~500 lines.

## Phase 6 — write per-team dossiers (serial, by orchestrator)

For each team in `/tmp/team-score.tsv` owning at least one monitor, dashboard or service, write
`teams/<team>/TEAM_KNOWLEDGE.md` from `TEAM_KNOWLEDGE_TEMPLATE.md`. Skip the empty teams, per
Phase 1. These run 60–120 lines and are narrative.

**Do not fan these out.** A subagent cannot see the other teams and so cannot explain a cross-team
ownership split — a service whose code one team owns and whose paging monitors another does.

Per-team inputs:

```bash
jq --arg id "$team_id" '[.[] | select(.owner == $id)]' /tmp/monitors-raw.json
jq --arg id "$team_id" '[.[] | select(.owner == $id)]' /tmp/dashboards-raw.json
jq --arg n "$team_name" '[.[] | select(any(.teams[]?; .team == $n))]' /tmp/services-raw.json
```

## Phase 7 — write per-service dossiers (parallel, subagent per service)

**The big fan-out.** One subagent per service in `/tmp/services-to-dossier.txt`, each given:

- Service name + owning team name and id
- `$SETUP/build-knowledge-company/references/SERVICE_KNOWLEDGE_TEMPLATE.md`
- `$SETUP/build-knowledge-company/references/CLI_TRANSLATION.md`
- `$SETUP/build-knowledge-company/references/LESSONS.md`
- Helper inputs: `/tmp/service-data/<svc>/{monitors.json,dashboards.json,incident-files.txt}`
- Top-level refs as pointers only, never to copy from: `$OUT/COMPANY_GENERAL_KNOWLEDGE.md`,
  `$OUT/COMPANY_TELEMETRY_KNOWLEDGE.md`
- Team context: `$OUT/teams/<team>/TEAM_KNOWLEDGE.md`
- Output path: `$OUT/teams/<team>/services/<svc>/SERVICE_KNOWLEDGE.md` (the subagent `mkdir -p`s it)

Prompt template: `SUBAGENT_PROMPT.md`, copied verbatim with the placeholders substituted.

**Batch size:** 8–12 in parallel. Wider hits rate limits; narrower wastes wall-clock.

**Phase 7 is not complete until Gate A of `VERIFICATION.md` passes.**

## Phase 8 — verification

Run `VERIFICATION.md` end to end: the `check-skill-health` linter for structure and forbidden
tokens, then Gates A–D by hand. A failure means a template bug, not a file bug — fix the root and
regenerate the affected services.

## Phase 9 — cross-link and commit

Gate C in `VERIFICATION.md` checks the cross-links. Two more to eyeball:

- `COMPANY_GENERAL_KNOWLEDGE.md`'s team list matches the `teams/` directory contents.
- Every service named in `COMPANY_TELEMETRY_KNOWLEDGE.md §"Investigation starting points by symptom
  shape"` either has a dossier or is deliberately without one.

Commit in three chunks: top-level docs plus `SKILL.md`; every `TEAM_KNOWLEDGE.md`; every
`SERVICE_KNOWLEDGE.md`. Do not push before a human has read 5 random dossiers cover-to-cover —
subagent output goes "plausible but vacuous" when inputs are thin, and that is the one defect no
gate detects.
