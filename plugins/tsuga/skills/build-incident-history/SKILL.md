---
name: build-incident-history
description: "Turns a raw incident dump of Slack threads, incident reports, pull requests and Tsuga CLI output into a populated incident-history archive, one folder per incident, each with a SUMMARY.md carrying a validated diagnostic path and a metadata.json for snapshot filtering. Use when bootstrapping incident-history from scratch for a new deployment, refreshing an existing archive with new incidents, or reformatting an incident tracker's export into the shape an investigation runtime expects. Inputs are per-incident directories of raw material; outputs are the incident folders plus an inventory CSV. This is a one-shot build procedure, not an investigation skill: to investigate an incident, use tsuga-investigate."
---

# build-incident-history

Procedure for bootstrapping the `incident-history` skill from raw incident material.

## What this produces

`skills/incident-history/references/incidents/` populated with one folder per incident:

```
skills/incident-history/references/incidents/
├── _inventory.csv                        ← index: incident_id, title, declared_at, last_iso, severity, affected_team, affected_services
├── INC-0001/
│   ├── SUMMARY.md                        ← the canonical dossier (see SUMMARY_TEMPLATE.md for the length target)
│   └── metadata.json                     ← {incident_id, declared_at, last_iso, title, severity, affected_services, affected_team}
├── INC-0002/
│   └── …
└── …
```

`SUMMARY.md` is the load-bearing artifact. Everything downstream reads from it: the history branch of an incident investigation (`tsuga-investigate`, following `references/incident-response/orchestration`), which mines the archive through the `$incident-history` skill when it is mounted; your investigation runtime's retrieval; and the snapshot-filter in any `entrypoint.sh`. `metadata.json` exists so a SNAPSHOT_AT filter can drop future incidents without parsing prose.

## When to run this

- Bootstrapping a new investigation-runtime deployment that has no prior archive.
- Refreshing the archive with a batch of new incidents.
- Re-validating an existing archive's `## Diagnostic path` commands against the CLI.

## Procedure — read in order

To hand the whole flow — build, then health check — to one agent in a single paste, use [`RECOMMENDED_PROMPT.md`](RECOMMENDED_PROMPT.md). It runs the same steps.

1. [`references/INPUT_LAYOUT.md`](references/INPUT_LAYOUT.md) — what raw material you need, where to put it, what each source contributes.
2. [`references/PROCEDURE.md`](references/PROCEDURE.md) — phase-by-phase workflow. Follow sequentially.
3. [`references/SUMMARY_TEMPLATE.md`](references/SUMMARY_TEMPLATE.md) — the canonical SUMMARY.md shape with exemplar section content.
4. [`references/LESSONS.md`](references/LESSONS.md) — the gotchas that will bite you if you skip them.
5. [`references/SUBAGENT_PROMPT.md`](references/SUBAGENT_PROMPT.md) — exact prompt template for the per-incident fan-out.
6. [`references/VERIFICATION.md`](references/VERIFICATION.md) — the acceptance gates. Every incident folder must pass before shipping.

## Key principles

- **One subagent per incident.** A real archive runs to hundreds of dossiers; a single thread cannot write them. Fan out and give each subagent a narrow scope: one `INC-id`, one raw-input directory, one output path.
- **Diagnostic path is the payload.** The `## Diagnostic path` section is what downstream agents actually read for analogue search. Every command in it must parse and execute as real `tsuga` CLI.
