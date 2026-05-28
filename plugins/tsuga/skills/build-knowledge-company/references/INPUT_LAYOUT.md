# INPUT_LAYOUT — what you drop in and what access you need

Unlike `build-incident-history`, this skill is mostly driven by **live queries** against the target Tsuga account, not a static dump. The raw file inputs are small; the heavy lifting is in discovery calls.

## Required access (live)

Before starting Phase 0:

- **Tsuga CLI authenticated.** `tsuga config` must show a valid token. Needs read access to: teams, monitors, dashboards, routes, notification-rules, services, logs, traces, metrics, aggregations.
- **Tsuga MCP tools available to the orchestrating agent.** Subagents fan out via the orchestrator; they will hit MCP tools for the discovery / scoring / live-probe phases (MCP is fine for *internal* probes; the *output* dossiers must use `tsuga` CLI commands).
- **GitHub access** for the company's main org (`gh auth status` green). Used for phase 1 to resolve "which services live in which repo".

Confirm:

```bash
tsuga --version
tsuga teams list | jq 'length'    # >0 teams, else auth is wrong
tsuga services list | jq 'length' # >0 services
gh auth status
```

## Optional raw inputs

```
inputs/
├── raw-docs/                        OPTIONAL — whatever architecture / onboarding docs exist
│   ├── company-architecture.md
│   ├── team-charters/
│   │   ├── infra.md
│   │   ├── platform.md
│   │   └── …
│   └── runbooks/                    any existing runbooks worth pulling excerpts from
├── codebase-repos.json              OPTIONAL — authoritative repo list with team mapping
└── slack-exports/                   OPTIONAL — historical channel archives for team context
```

### `codebase-repos.json` — recommended shape

```json
[
  {"repo": "acme-co/typescript",      "owner_team": "platform", "services": ["api-gateway", "admin-ui", "ingress", "monitor-runner", "notification-service", "service-registry", "health-aggregator"]},
  {"repo": "acme-co/rust",            "owner_team": "infra",    "services": ["order-ingest", "order-processing-*", "query-*", "event-relay", "segment-compaction", "segment-retention"]},
  {"repo": "acme-co/python",          "owner_team": "data",     "services": ["analytics-engine", "deploy-anomaly-detector", "report-generator"]},
  {"repo": "acme-co/infra-as-code",   "owner_team": "infra",    "services": []}
]
```

This file feeds the "owner team" annotation in each service dossier's header. If you don't supply it, Phase 3 infers ownership from the `context.team` telemetry tag — which is authoritative but occasionally gives surprising answers (e.g., `analytics-engine` may live in a `platform`-owned repo but its team tag is `data`). Both inference sources are correct in their own way; the JSON file lets you decide which to prefer.

## What the raw docs contribute (if present)

| Source | Feeds which output file |
|---|---|
| `company-architecture.md` | `COMPANY_GENERAL_KNOWLEDGE.md` — the "what is the company" narrative |
| `team-charters/<team>.md` | `teams/<team>/TEAM_KNOWLEDGE.md` — ownership + historical context |
| `runbooks/<service>.md` | `teams/<team>/services/<service>/SERVICE_KNOWLEDGE.md` — the Caveats + Typical incident shapes sections |
| `slack-exports/` | cross-check against inferred team ownership; cultural context |

If none of these exist, the skill still builds — Phase 1 infers everything from live telemetry. But the top-level `COMPANY_GENERAL_KNOWLEDGE.md` will be thinner without architecture docs.

## Cross-input: `skills/incident-history/references/incidents/`

**Required.** Built by `../build-incident-history/`. Used for:

- Per-service incident counts (scoring — Phase 3's service-ranking step).
- Per-service diagnostic-path mining (what commands have responders actually used?).
- Per-service incident-shape distillation (the "Typical incident shapes" section).

If this doesn't exist yet, build it first. Do not fake it — service dossiers without validated incident shapes are worth much less.

## Live discovery — what Phase 0/1 reads

Phase 0/1 in `PROCEDURE.md` runs these calls against the live Tsuga account. Not inputs per se, but worth listing so you can pre-cache them if rate limits are tight:

```bash
tsuga teams list                                    # all teams + metadata
tsuga monitors list                                 # all monitors
tsuga dashboards list                               # all dashboards
tsuga routes list                                   # all telemetry routes
tsuga services list                                 # all services with 24h activity counters
tsuga notification-rules list                       # all notification routing rules
tsuga metrics list                                  # all metric names currently reporting

# Log-volume by service (fuel for service scoring)
FROM=$(date -u -v-7d +%s); TO=$(date -u +%s)
cat > /tmp/svc-vol.json <<JSON
{"timeRange":{"from":$FROM,"to":$TO},"dataSource":"logs","queries":[{"aggregate":{"type":"count"},"filter":"context.env:prod"}],"groupBy":[{"fields":["context.service.name"],"limit":200}],"formula":"q1"}
JSON
tsuga aggregation scalar -f /tmp/svc-vol.json   # save to inputs/cache/svc-volume-7d.json
```

Cache these outputs under `inputs/cache/` if you plan to iterate — they are slow enough that re-running Phase 3 five times will hit your patience before it hits any rate limit.

## Per-service helper extraction

Phase 3 pre-digests discovery output into per-service helper directories so each subagent has a narrow, focused input to read. See `PROCEDURE.md §"Phase 3"` for the exact script. The end state looks like:

```
/tmp/service-data/
├── order-ingest/
│   ├── monitors.json              monitors matching this service (by name or wildcard)
│   ├── dashboards.json            dashboards referencing this service
│   └── incident-files.txt         paths to SUMMARY.md files that mention this service
├── api-gateway/
│   └── …
└── …
```

Do NOT put per-service data in a subagent's main input tree — the subagent should receive pointers to these helper files and read only what it needs.
