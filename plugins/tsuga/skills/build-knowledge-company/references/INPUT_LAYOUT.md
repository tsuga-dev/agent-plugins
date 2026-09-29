# INPUT_LAYOUT — what you drop in and what access you need

Unlike `build-incident-history`, this skill is mostly driven by **live queries** against the target Tsuga account, not a static dump. The raw file inputs are small; the heavy lifting is in discovery calls.

## Required access (live)

Before starting Phase 0:

- **Tsuga CLI authenticated.** Needs read access to teams, monitors, dashboards, log-routes, notification-rules, services, logs, traces, metrics and aggregations.
- **Tsuga MCP tools available to the orchestrating agent.** Subagents fan out via the orchestrator and will hit MCP tools for the discovery / scoring / live-probe phases. MCP is fine for *internal* probes; the *output* dossiers must carry `tsuga` CLI commands.
- **GitHub access** — optional. No phase calls `gh`; the repo-to-service mapping is read from `inputs/codebase-repos.json` in Phase 5, falling back to the `teams` field on `tsuga services list`.

Confirm:

```bash
tsuga auth whoami                 # calls the API; proves the token is live and names the org
tsuga teams list | jq 'length'    # >0 teams, else the token lacks scope
tsuga services list | jq 'length' # >0 services
```

`tsuga auth status` and `tsuga config` only read local state. They report a stored session that the
API may already reject, so neither is a substitute for a call that reaches the server.

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

This file feeds the "owner team" annotation in each service dossier's header. Without it, ownership falls back to the `teams` field on `tsuga services list` — the same mapping Phase 1 scores teams with, and one that reads by team name rather than id (see `PROCEDURE.md §"Identity fields, once"`). That fallback is authoritative but occasionally surprising: `analytics-engine` may live in a `platform`-owned repo while its team tag says `data`. Both sources are correct in their own way; the JSON file lets you choose.

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

## Live discovery

The fleet dumps and the service-volume aggregation are listed with the phases that run them, in
`PROCEDURE.md §"Phase 0"` through `§"Phase 2"`. Cache their output under `inputs/cache/` if you
plan to iterate: they are slow enough that re-running Phase 3 five times exhausts your patience
before it hits any rate limit.

## Per-service helper extraction

Phase 4 pre-digests discovery output into per-service helper directories so each subagent has a narrow, focused input to read. See `PROCEDURE.md §"Phase 4"` for the exact script. The end state looks like:

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
