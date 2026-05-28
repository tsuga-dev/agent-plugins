# INPUT_LAYOUT — what you drop in before running the procedure

The procedure assumes raw material lives under `inputs/incidents/<INC-id>/`. Each incident folder is self-contained so one subagent can pick one directory and produce one `SUMMARY.md` without cross-incident reads.

## Required structure

```
inputs/incidents/
├── INC-0001/
│   ├── metadata.json                 REQUIRED — incident-tracker export
│   ├── slack/                        OPTIONAL but high-value
│   │   ├── thread-<channel>.json     raw Slack message export
│   │   └── attachments/              any files pasted into the thread
│   ├── incident-report.md            OPTIONAL — postmortem draft if one exists
│   ├── github/                       OPTIONAL
│   │   ├── prs.json                  `gh pr list --search "...{incident window}"` output
│   │   ├── issues.json               related issues
│   │   └── diffs/                    saved PR diffs for suspected-culprit PRs
│   ├── tsuga/                        OPTIONAL but canonical for Diagnostic path
│   │   ├── commands.txt              ordered list of commands the responder actually ran
│   │   ├── outputs/                  redacted output captures (logs, monitors, dashboards)
│   │   └── monitors-fired.json       `tsuga monitors list` snapshot + which ones fired
│   └── notes.md                      OPTIONAL — responder's scratch notes
├── INC-0002/
│   └── …
└── …
```

## `metadata.json` — required fields

```json
{
  "incident_id": "INC-0001",
  "title": "Metrics on acme-trading are slow",
  "declared_at": "2026-03-02T09:44:43.87Z",
  "last_iso": "2026-03-02T14:18:03Z",
  "severity": "P2",
  "affected_services": ["query-engine", "segment-compaction"],
  "affected_team": "infra",
  "customer": "acme-trading",
  "resolution_pr": 42
}
```

- `declared_at` is the incident-start ISO timestamp. An `entrypoint.sh` (or equivalent SNAPSHOT_AT loader) uses this to filter future incidents from the archive (cutoff = `declared_at - 20 min`).
- `last_iso` is the timestamp of the latest message in the Slack thread / incident log. Used for the same filter.
- `affected_services` must use the telemetry `context.service.name` values, not casual English ("the ingest service"). These feed the cross-reference with `knowledge-company` service dossiers.
- `severity` is the incident-tracker severity (P1/P2/P3/...). Optional but informative.
- `resolution_pr` is optional but makes the "after-the-fact cheat check" in a time-bound investigation-runtime constraint easier.

## Where each source contributes

| Source | What it provides | SUMMARY.md section it feeds |
|---|---|---|
| `metadata.json` | identity + timing | frontmatter + "Incident at a glance" |
| `slack/thread-*.json` | blow-by-blow responder timeline, direct quotes | "Timeline" + "Diagnostic path" narrative |
| `incident-report.md` | RCA writeup, retrospective lessons | "Root cause" + "Remediation" + "Lessons" |
| `github/prs.json` + `diffs/` | change-correlation evidence | "Change correlation" |
| `tsuga/commands.txt` + `outputs/` | the real probes that cracked the case | "Diagnostic path" (most important) |
| `tsuga/monitors-fired.json` | which monitors were paging | "Paging surface during incident" |
| `notes.md` | responder impressions not captured elsewhere | "Commentary" (italicized, small) |

## Minimum viable input

If all you have is `metadata.json` + a Slack thread + a few `tsuga` commands the responder remembered, **that is enough** to produce a useful SUMMARY.md. The other sources enrich; they are not gating. The Diagnostic path is the only section where low-quality input seriously hurts downstream value, so prioritize the `tsuga/commands.txt` file — it should be a faithful, chronological list of the real commands run, not a reconstruction.

## What NOT to put in `inputs/incidents/`

- Raw customer data (PII, credentials, API keys). Scrub before ingesting — once it lands in the archive it's hard to pull back.
- Post-incident PRs whose merge date is ≥ `declared_at` with rich context. The incident-history archive is consumed by agents under a time-bound constraint; leaking the "answer key" into the SUMMARY poisons future benchmarking runs. Reference the PR number for context, but do not paste the PR diff into the SUMMARY's narrative.
- Multi-incident Slack threads. Split them manually — one folder per incident.

## Bulk-loading from an incident tracker

Most trackers (incident.io, PagerDuty, linear) have CSV or JSON exports. Write a small transform script (not part of this skill — stays in your ops toolkit) that emits the directory structure above from one export. The `PROCEDURE.md` phases assume the structure is already in place when you start.
