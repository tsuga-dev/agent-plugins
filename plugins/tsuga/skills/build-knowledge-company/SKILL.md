---
name: build-knowledge-company
description: "One-shot procedure for turning a live Tsuga account + codebase list + ambient docs into the `skills/knowledge-company/` tree: top-level COMPANY_GENERAL_KNOWLEDGE.md + COMPANY_TELEMETRY_KNOWLEDGE.md, per-team TEAM_KNOWLEDGE.md, per-service SERVICE_KNOWLEDGE.md dossiers with ready-to-run `tsuga` CLI queries. Trigger this skill when bootstrapping knowledge-company from scratch for a new customer / company, refreshing it after a major service taxonomy change, or after a CLI rename that invalidates the existing ready-to-run commands. Inputs: Tsuga MCP / CLI access, list of GitHub codebases, optional `inputs/raw-docs/` for architecture notes. Outputs: populated `skills/knowledge-company/` ready for the runtime agent to load."
---
<!-- skill-lint: allow-forbidden-examples — SKILL.md mentions the forbidden patterns as teaching context -->

# build-knowledge-company

Procedure for bootstrapping the `knowledge-company` skill from a live Tsuga account and a list of codebases.

## What this produces

```
skills/knowledge-company/
├── SKILL.md                              ← thin dispatcher
└── references/
    ├── COMPANY_GENERAL_KNOWLEDGE.md      ← what the company is; architecture; teams
    ├── COMPANY_TELEMETRY_KNOWLEDGE.md    ← env / signal / routing conventions + canonical query patterns + symptom-routing
    └── teams/
        ├── <team>/
        │   ├── TEAM_KNOWLEDGE.md         ← team overview, services, paging surface
        │   └── services/
        │       └── <service>/
        │           └── SERVICE_KNOWLEDGE.md   ← ready-to-run + golden signals + log shape + dashboards + incident shapes + caveats
        └── …
```

The load-bearing artifact is the **per-service SERVICE_KNOWLEDGE.md**. It's what the runtime agent reads first when an incident names a service, and it's the largest surface to get right.

## When to run this

- Bootstrapping for a new deployment (no existing `knowledge-company/`).
- Refreshing after a material taxonomy change (team reorg, large service rename, new team spun up).
- Re-validating after a CLI change (e.g., TQL syntax revision, new aggregation flags) — the ready-to-run commands in every dossier must be re-tested against the new shape.

## Before you start

- **Build `incident-history` first.** `knowledge-company`'s service dossiers cross-link to incidents — that requires a populated `skills/incident-history/references/incidents/` tree. See `../build-incident-history/` for that procedure.
- **Confirm `tsuga` CLI works.** Run `tsuga teams list` and `tsuga logs search --query '*' --from -5m --max-results 1`. Both must succeed. If not, fix auth (`tsuga auth <token>`) before continuing.
- **Confirm the runtime agent's `knowledge-technology` skill exists** — many cross-links in `knowledge-company` point at it (for Postgres / Kafka / etc. metric catalogs). If absent, either build it or adjust the cross-refs.

## Procedure — read in order

1. [`references/INPUT_LAYOUT.md`](references/INPUT_LAYOUT.md) — what raw material you need, where to put it, how to validate the Tsuga CLI access is wired up.
2. [`references/PROCEDURE.md`](references/PROCEDURE.md) — the phase-by-phase workflow. Discovery → top-level → teams → services → verification.
3. [`references/CLI_TRANSLATION.md`](references/CLI_TRANSLATION.md) — the MCP-tool → real-CLI translation contract. Every subagent must read this before writing a single command.
4. [`references/SKILL_TEMPLATE.md`](references/SKILL_TEMPLATE.md) — the shape of the top-level SKILL.md.
5. [`references/TEAM_KNOWLEDGE_TEMPLATE.md`](references/TEAM_KNOWLEDGE_TEMPLATE.md) — per-team template.
6. [`references/SERVICE_KNOWLEDGE_TEMPLATE.md`](references/SERVICE_KNOWLEDGE_TEMPLATE.md) — the big one. Per-service template with every section's rules.
7. [`references/SUBAGENT_PROMPT.md`](references/SUBAGENT_PROMPT.md) — the exact prompt template to fan out to per-service subagents.
8. [`references/LESSONS.md`](references/LESSONS.md) — every mistake the first pass made. Read before starting, re-read before any subagent batch.
9. [`references/VERIFICATION.md`](references/VERIFICATION.md) — acceptance gates. The Gate 5 / Gate 6 sampled-execution tests are non-negotiable.

## Key principles

- **Discover taxonomy from live data, not a prescribed list.** `tsuga teams list` + `tsuga services list` + log-volume scoring are authoritative. Do not start with a list of "15 services I think exist" — you'll miss ones that matter and add ones that don't.
- **Parallel subagents, narrow scopes.** One subagent per service. Give each one: specific input files (pre-extracted helpers), specific output path, the template, the lessons doc, and an explicit list of `tsuga` commands to run as live probes before writing.
- **Every command must be tested.** The single most expensive bug in the first pass was subagents writing MCP-tool pseudo-syntax (`search-logs query='…' from=-1h to=now limit=50`) instead of real `tsuga` CLI. See `CLI_TRANSLATION.md` and `LESSONS.md §"Command-shape mistakes"`.
- **Live data overrides the task brief.** If the brief says "service X is the foo write-path" and the live logs show it's the bar reconciler, trust the logs and reframe. Document the discrepancy in the service's Confidence note.
- **No invented structure.** Subagents will coin new headings, acronyms, and sections if given latitude. The template's section list is fixed. Use it.
- **Pointers, not duplication.** Top-level `COMPANY_*.md` files are the single source of truth for company-wide context. Per-team and per-service dossiers point to them. Do not paste the team roster into every service dossier.
