# SKILL_TEMPLATE — the top-level `skills/knowledge-company/SKILL.md`

Short dispatcher. This file is what Claude / Codex load into context at run time, so it must be tight.

## Target length: 40–70 lines

The description field in the frontmatter is the most load-bearing part — it determines whether the skill triggers on a given incident. Write it to include every service name an agent might search for.

## Template — copy verbatim, substitute `{company}` + `{service-name-list}`

```markdown
---
name: knowledge-company
description: "{company}-specific domain knowledge: what the company does, how its own telemetry is routed, and per-team / per-service operational playbooks. Trigger at the start of any {company}-internal incident (a cluster service slow, a pipeline lagging, a monitor fired) or whenever a service name like {service-name-list} appears. References live at `{{SKILLS_DIR}}/knowledge-company/references/`: `COMPANY_GENERAL_KNOWLEDGE.md` (what {company} is), `COMPANY_TELEMETRY_KNOWLEDGE.md` (how telemetry is shaped + live catalog of teams, monitors, canonical query patterns, symptom-routing), plus `teams/<team>/TEAM_KNOWLEDGE.md` and `teams/<team>/services/<service-name>/SERVICE_KNOWLEDGE.md` dossiers for the operational surface of each team and its services. Each SERVICE_KNOWLEDGE.md leads with ready-to-run `tsuga` CLI commands."
---

# Company Knowledge

Curated reference bundles for {company}'s own engineering + operations. Start here whenever the investigation names a {company} service, team, or internal subsystem — the `knowledge-technology` skill covers *classes* of technology (Postgres, Kafka, Redis), this skill covers *specific* {company} services.

## Layout

\`\`\`
references/
├── COMPANY_GENERAL_KNOWLEDGE.md       ← what {company} is (architecture, codebases, teams)
├── COMPANY_TELEMETRY_KNOWLEDGE.md     ← how telemetry is shaped + monitor/dashboard catalog + symptom-routing
└── teams/
    ├── <team-a>/
    │   ├── TEAM_KNOWLEDGE.md          ← team overview, services owned, paging surface, dashboards
    │   └── services/
    │       ├── <service>/SERVICE_KNOWLEDGE.md
    │       └── …
    ├── <team-b>/
    └── …
\`\`\`

Service folder names match the literal `context.service.name` value in telemetry — so `grep -l -r <service-name> references/teams/` lands you in the right dossier even without knowing the team.

## When to read what

| Question | Start here |
|---|---|
| "What is {company}, how is the code organized?" | `COMPANY_GENERAL_KNOWLEDGE.md` |
| "What's the env / signal / routing convention?" | `COMPANY_TELEMETRY_KNOWLEDGE.md` |
| "Which monitors exist, what are canonical query shapes, where to look when symptom X fires?" | `COMPANY_TELEMETRY_KNOWLEDGE.md` — §"Canonical query patterns" + §"Investigation starting points by symptom shape" |
| "What does team X own, how are its pages routed?" | `teams/<team>/TEAM_KNOWLEDGE.md` |
| "How do I investigate service Y right now?" | `teams/<team>/services/<Y>/SERVICE_KNOWLEDGE.md` — top of file is ready-to-run `tsuga` commands |

## Shell commands

\`\`\`bash
CK={{SKILLS_DIR}}/knowledge-company/references

# Which teams have dossiers?
ls "$CK/teams"

# Which services does team <t> own (that we have dossiers for)?
ls "$CK/teams/<t>/services"

# Find the team a service belongs to (fuzzy name known)
find "$CK/teams" -type d -name '*<fragment>*'

# Jump straight to the ready-to-run queries at the top of a service dossier
cat "$CK/teams/<team>/services/<service>/SERVICE_KNOWLEDGE.md"

# All services with a monitor that pages (grep across SERVICE_KNOWLEDGE files)
grep -l -r "Priority: P1" "$CK/teams"

# All dossiers that mention a specific symptom
grep -l -r -i "queue lag" "$CK/teams"

# Canonical query for a symptom category
grep -B2 -A8 -i "queue lag" "$CK/COMPANY_TELEMETRY_KNOWLEDGE.md"
\`\`\`

## Service-naming gotcha (if applicable to {company})

Some services have multiple identities in telemetry (e.g., K8s-scraped vs OTel-self-reported). When that's true, document the OR-match idiom here. See `COMPANY_TELEMETRY_KNOWLEDGE.md §"Service identity"` for the full mapping.

## Boundary

- **This skill** — *what {company} is, who owns what, how to probe a specific service right now.*
- **`$knowledge-technology`** — *generic tech (Postgres, Kafka, Redis) metric catalog.*
- **`$tsuga-cli`** — *CLI driver: TQL syntax, aggregation body shape, flags.*
- **`$incident-investigation`** — *how to reason: mode classification, branch planning, evidence gates.*
- **`$incident-history`** — *prior verified incidents; useful for analogue search.*
```

## Rules the orchestrator must follow

1. **`{service-name-list}` must be comprehensive.** Include every service that has a SERVICE_KNOWLEDGE.md — comma-separated, backtick-wrapped. This is the trigger vocabulary. Missing a service here means the skill won't fire when that service is in an incident title.
2. **Do NOT list every service by name in the body.** The description field carries that weight. The body stays short.
3. **No `RAW_TELEMETRY_KNOWLEDGE.md` reference.** That file was folded into `COMPANY_TELEMETRY_KNOWLEDGE.md` in the distillation pass. Do not resurrect it.
4. **No `rtk` tool-note section.** The RTK hook is transparent; end-users of the skill don't need to see it.
5. **Link sibling skills by `$name` convention** in the Boundary section. These are soft references that render in Claude's UI.
