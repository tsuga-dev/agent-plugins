---
name: build-incident-history
description: "One-shot procedure for turning a raw incident dump (Slack threads, incident reports, GitHub PRs, Tsuga CLI output) into a populated `skills/incident-history/references/incidents/` archive with one folder per incident, each containing a SUMMARY.md with a validated `## Diagnostic path` section. Trigger this skill when bootstrapping `incident-history` from scratch for a new deployment, refreshing an existing archive with new incidents, or reformatting an incident tracker's export into the shape your investigation runtime expects. Inputs: `inputs/incidents/<INC-id>/` directories holding raw material per incident. Outputs: `skills/incident-history/references/incidents/<INC-id>/SUMMARY.md` + `_inventory.csv`."
---

# build-incident-history

Procedure for bootstrapping the `incident-history` skill from raw incident material.

## What this produces

`skills/incident-history/references/incidents/` populated with one folder per incident:

```
skills/incident-history/references/incidents/
├── _inventory.csv                        ← index: incident-id, title, declared_at, last_iso, service, team, severity
├── INC-0001/
│   ├── SUMMARY.md                        ← the canonical ~300-line dossier
│   └── metadata.json                     ← {incident_id, declared_at, last_iso, title, severity}
├── INC-0002/
│   └── …
└── …
```

`SUMMARY.md` is the load-bearing artifact. Everything downstream (the `$incident-history` skill's analogue-search behavior, your investigation runtime's retrieval, the snapshot-filter in any `entrypoint.sh`) reads from it. `metadata.json` exists so a SNAPSHOT_AT filter can drop future incidents without parsing prose.

## When to run this

- Bootstrapping a new investigation-runtime deployment that has no prior archive.
- Refreshing the archive with a batch of new incidents.
- Re-validating an existing archive whose `## Diagnostic path` commands have gone stale after a CLI change.

## Procedure — read in order

1. [`references/INPUT_LAYOUT.md`](references/INPUT_LAYOUT.md) — what raw material you need, where to put it, what each source contributes.
2. [`references/PROCEDURE.md`](references/PROCEDURE.md) — phase-by-phase workflow. Follow sequentially.
3. [`references/SUMMARY_TEMPLATE.md`](references/SUMMARY_TEMPLATE.md) — the canonical SUMMARY.md shape with exemplar section content.
4. [`references/LESSONS.md`](references/LESSONS.md) — the gotchas that will bite you if you skip them.
5. [`references/SUBAGENT_PROMPT.md`](references/SUBAGENT_PROMPT.md) — exact prompt template for the per-incident fan-out.
6. [`references/VERIFICATION.md`](references/VERIFICATION.md) — the acceptance gates. Every incident folder must pass before shipping.

## Key principles

- **One subagent per incident.** Do not try to write 174 SUMMARY.md files in a single thread. Fan out and give each subagent a narrow scope: one `INC-id`, one raw-input directory, one output path.
- **Diagnostic path is the payload.** The `## Diagnostic path` section is what downstream agents actually read for analogue search. Every command in it must parse and execute against a real `tsuga` CLI. No MCP-tool pseudo-syntax. No `rtk` prefix.
- **Metadata is non-negotiable.** `metadata.json` with at minimum `declared_at` and `last_iso` (ISO 8601) is required for the snapshot-filter. Incidents missing it get silently dropped by `entrypoint.sh`.
- **Preserve the slack-quote spirit.** The post-mortem prose is often a Slack thread — keep the direct quotes, attribution, and timestamps. Do not paraphrase. Future analogue search depends on the reader recognizing familiar customer names and error strings.
- **Test before shipping.** Sample 5 incidents at random and execute every `tsuga` command in their Diagnostic path sections. If any command fails to parse, fix the template and re-run the subagent batch. Do not hand-patch individual files.
