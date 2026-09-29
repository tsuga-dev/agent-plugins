<!-- skill-lint: allow-forbidden-examples — this file documents the forbidden patterns as teaching examples -->

# LESSONS — the failure modes this procedure has to design around

Read before starting, re-read before each subagent batch. Command shape lives in
`CLI_TRANSLATION.md` and is not repeated here.

- [Subagent output](#subagent-output) — §1–5: self-reports, empty inputs, headings, brief vs live data
- [Taxonomy and discovery](#taxonomy-and-discovery) — §6–10: service list, three ownership axes, dual service names
- [Content](#content) — §11–15: pointers, Caveats padding, Confidence tiers, stale monitor filters, metric sweeps
- [Process](#process) — §16–20: fan-out, gates, regenerate over patch, commit shape
- [Data hygiene](#data-hygiene) — §21–22: redaction, post-incident PR leakage

## Subagent output

### 1. A "fixed, 0 matches" self-report is not evidence

It means the subagent believes its own grep returned zero. Sample 5–10 output files by eye and
check independently:

- Do the Golden signals cite metric names that appear in `tsuga metrics list`?
- Do the Monitor reproductions use IDs that resolve via `tsuga monitors get <id>`?
- Does at least one Ready-to-run command execute cleanly when pasted into a shell?

A failing sample is a template or prompt bug, not a file bug. Regenerate the batch.

### 2. Empty inputs get an honest note, not filler

When a subagent's helper files come back empty (`monitors.json: []`, `dashboards.json: []`,
`incident-files.txt: ""`), it must not invent plausible content. Instead: record the gap in the
Confidence note ("`monitors.json` and `dashboards.json` were empty at collect time; monitor and
dashboard references are inferred from TEAM_KNOWLEDGE.md, not probed"), keep the sections short,
and lean harder on live probes to ground what is there. A visible low-confidence note beats
plausible-looking fabrication.

### 3. Canonical headings only

Subagents given latitude coin sections — "Ad-hoc scans", "Post-mortem debrief", "Hot-take",
"rtk scans (ready-to-kick investigations)". Reject all of them. The section list in
`SERVICE_KNOWLEDGE_TEMPLATE.md` is fixed, and downstream retrieval depends on stable names.

### 4. Live data overrides the task brief

The orchestrator's framing of what a service does can be wrong: a brief calling `config-store`
"the object-storage write-path for processed data" against live logs showing an asset/policy
reconciler is the shape to expect. Trust the live evidence, reframe, and document the
contradiction in Quick context and the Confidence note.

### 5. A low incident count does not mean a short dossier

Live probes — Log shape, Golden signals, Ready-to-run — are the meat; incident shapes are bonus.
A service with no incidents can still carry a rich dossier built entirely from live data.

## Taxonomy and discovery

### 6. Derive the service list, never prescribe it

A hand-picked list of "the services I think matter" misses renamed services, critical services
with low log volume, and anything added since the last refresh. Use the three-source union in
`PROCEDURE.md §"Phase 3"`: top-by-volume, monitor-named, incident-referenced.

### 7. Code ownership, monitor ownership and team tag diverge

Three axes, three answers. A `health-aggregator` service can be platform-team code in the
TypeScript repo while its P1 monitors are infra-team owned (they report infra SLIs) and a
neighbouring monitor is solution-team owned. The dossier lives under the team that owns the code
repo; monitor ownership comes from `tsuga monitors get <id>` → `.owner`, never from the service's
team.

### 8. Engine roles are not first-party services

`indexer`, `searcher`, `metastore` and similar names come from an embedded search/storage engine.
They surface as `context.service.name:<role>` with a `tech` tag naming the engine, often scraped
by a sidecar from the engine's pods. When scoring surfaces them, state the role/service
distinction up front — readers conflate them otherwise.

### 9. One service, two telemetry names

K8s-scraped (Deployment/StatefulSet name) and OTel-self-reported (`OTEL_SERVICE_NAME`) can
differ: `app-order-ingest` versus `ingest`. A bare `context.service.name:ingest` silently drops
half the events. Every probe for such a service uses the OR idiom:

```
(context.service.name:app-order-ingest OR context.service.name:ingest)
```

### 10. `context.app:python` spans services

Several Python services share it. A filter carrying only `context.app` matches all of them; always
narrow with `context.service.name`.

## Content

### 11. Point at the top-level docs, do not copy them

The cluster ↔ customer table, the notification-rule fanout and the canonical query patterns live
in `COMPANY_TELEMETRY_KNOWLEDGE.md`. A dossier under 300 lines is a good sign you are pointing
rather than pasting.

### 12. Caveats attract filler

It is the section subagents pad when they run out of real content ("always check logs first",
"use the dashboard"). Service-specific footguns only, 5–10 bullets.

### 13. Confidence notes are tiered or they are useless

High (cross-validated against multiple authoritative sources), medium (one source, not re-probed),
low/inferred (guesses, flagged for re-verification), plus what to refresh and which commands do
it. A single generic paragraph tells the next reader nothing.

### 14. A monitor's filter can point at a code path that has moved

`event-relay`'s P1 monitor filtering on `filename:src/api/v1/log.rs` while live ERRORs emit from
`src/api/v2/log.rs` is the shape: the monitor is green and silent on the real failure path. Run
each monitor's filter live while writing the Monitor reproduction section; if it has been empty
for days, that belongs in Caveats.

### 15. `tsuga metrics list` is a catalog, not a window

It lists the cluster's metric-name catalog and ignores `--from` / `--to` — the same invocation
returns the same rows at `-5m` and at `-30d` — and it keeps a name for weeks after the metric
stops reporting. So a name being in the list says nothing about whether that metric arrived in
the window you care about; only an `aggregation scalar` count over the window does. A Golden
signal citing a name the list does not carry is the one to challenge.

## Process

### 16. Fan out; do not run subagents serially

Thirty-odd dossiers in a single thread takes a working day. In parallel batches of 8–12 it takes
under an hour.

### 17. The sampled-execution gate is the only one that catches hallucination

`VERIFICATION.md §"Gate A"` — copy commands out of 5 random dossiers and run them. A
forbidden-token grep passes happily on a dossier whose every metric name is invented; execution
does not. Regenerating a batch is cheaper than hand-patching it.

### 18. The commit is not the end state

Before pushing, a human reads 5 random dossiers cover-to-cover and confirms they cohere. Subagent
output is "valid-looking but vacuous" when inputs are thin, and no automated gate detects that.

### 19. Fix the template, never the output

The whole tree is regenerable. When a CLI change invalidates the ready-to-run commands, you re-run
this procedure — so hand-edits to an individual SERVICE_KNOWLEDGE.md are clobbered on the next
rebuild. Fix the template or the subagent prompt and regenerate.

### 20. Commit in logical chunks

One commit with 32 new files is unreviewable. Split: top-level docs plus the skill scaffold; then
`TEAM_KNOWLEDGE.md` across all teams; then the service dossiers (one commit is fine when they were
generated together).

## Data hygiene

### 21. Redact before pasting a log line

Live probes return customer data. Log shape needs *an* example, not a real one:
`customer: <redacted>`, `usr.email: user@example.com`.

### 22. Reference post-incident PRs by number, not content

When the investigation runtime is evaluated under a time-bound block that forbids reading PRs at
or after `declared_at`, a dossier quoting the fix PR for a known incident leaks it into the
agent's context through retrieval. Same rule as `build-incident-history`.
