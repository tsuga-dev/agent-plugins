---
name: build-knowledge-company
description: "Turns a live Tsuga account, a codebase list and ambient docs into a populated knowledge-company tree: company-level general and telemetry knowledge, per-team knowledge files, and per-service dossiers carrying ready-to-run `tsuga` commands discovered from live data rather than a prescribed list. Use when bootstrapping knowledge-company from scratch for a new company, refreshing it after a major service taxonomy change, or after a CLI change that invalidates the existing ready-to-run commands. Requires Tsuga CLI access and a populated incident-history archive to cross-link against. This is a one-shot build procedure, not an investigation skill."
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
- **Confirm `tsuga` CLI works.** Run `tsuga auth whoami`, `tsuga teams list`, and `tsuga logs search --query '*' --from=-5m --max-results 1`. All three must succeed — `whoami` proves the token reaches the API, the other two prove it has read scope. (`tsuga auth status` only reads local state and proves neither.) If any fail, fix auth with `tsuga auth login`, or `tsuga auth operation-key <key>` for non-interactive use.
- **Confirm the runtime agent's `knowledge-technology` skill exists** — many cross-links in `knowledge-company` point at it (for Postgres / Kafka / etc. metric catalogs). If absent, either build it or adjust the cross-refs.

## Procedure — read in order

A human operator kicking this off from a blank session can paste
[`RECOMMENDED_PROMPT.md`](RECOMMENDED_PROMPT.md) instead, which wraps the whole flow — build, then
health check — in one prompt.

1. [`references/INPUT_LAYOUT.md`](references/INPUT_LAYOUT.md) — what raw material you need, where to put it, how to validate the Tsuga CLI access is wired up.
2. [`references/PROCEDURE.md`](references/PROCEDURE.md) — the phase-by-phase workflow. Discovery → top-level → teams → services → verification.
3. [`references/CLI_TRANSLATION.md`](references/CLI_TRANSLATION.md) — the MCP-tool → real-CLI translation contract. Every subagent must read this before writing a single command.
4. [`references/SKILL_TEMPLATE.md`](references/SKILL_TEMPLATE.md) — the shape of the top-level SKILL.md.
5. [`references/TEAM_KNOWLEDGE_TEMPLATE.md`](references/TEAM_KNOWLEDGE_TEMPLATE.md) — per-team template.
6. [`references/SERVICE_KNOWLEDGE_TEMPLATE.md`](references/SERVICE_KNOWLEDGE_TEMPLATE.md) — the big one. Per-service template with every section's rules.
7. [`references/SUBAGENT_PROMPT.md`](references/SUBAGENT_PROMPT.md) — the exact prompt template to fan out to per-service subagents.
8. [`references/LESSONS.md`](references/LESSONS.md) — the failure modes this procedure designs around. Read before starting, re-read before any subagent batch.
9. [`references/VERIFICATION.md`](references/VERIFICATION.md) — acceptance gates: the `check-skill-health` linter, then the four gates it cannot reach. Gate A (sampled execution) and Gate B (aggregation bodies) are non-negotiable.

## Key principles

- **Discover taxonomy from live data, not a prescribed list.** `tsuga teams list` + `tsuga services list` + log+trace volume scoring are authoritative. Do not start with a list of "15 services I think exist" — you'll miss ones that matter and add ones that don't.
- **Parallel subagents, narrow scopes.** One subagent per service. Give each one: specific input files (pre-extracted helpers), specific output path, the template, the lessons doc, and an explicit list of `tsuga` commands to run as live probes before writing.
- **Every command must be tested.** A subagent holding Tsuga MCP tools writes its commands in the tool vocabulary (`search-logs query='…' from=-1h to=now limit=50`), which reads as plausible and runs as nothing. This is the most expensive defect the procedure has to prevent; `CLI_TRANSLATION.md` is the contract every subagent reads before writing a command.
- **Live data overrides the task brief.** If the brief says "service X is the foo write-path" and the live logs show it's the bar reconciler, trust the logs and reframe. Document the discrepancy in the service's Confidence note.
- **No invented structure.** Subagents will coin new headings, acronyms, and sections if given latitude. The template's section list is fixed. Use it.
- **Pointers, not duplication.** Top-level `COMPANY_*.md` files are the single source of truth for company-wide context. Per-team and per-service dossiers point to them. Do not paste the team roster into every service dossier.
