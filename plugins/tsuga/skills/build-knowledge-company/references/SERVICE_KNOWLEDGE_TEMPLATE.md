# SERVICE_KNOWLEDGE_TEMPLATE — per-service dossier

The highest-leverage file in the entire skill. Every section has rules; follow them mechanically. Hallucination-prone sections (Caveats, Typical incident shapes) have extra guards.

## Target length: 180–350 lines

Under 180: the service probably doesn't merit its own dossier (fold into TEAM_KNOWLEDGE.md instead). Over 350: you are duplicating from the top-level docs or padding the Confidence note — trim.

## Canonical section list (do not rename, do not reorder)

```
# Service — {service_name}
## Quick context          (table + one-paragraph framing)
## Ready-to-run           (tsuga CLI queries, grouped into subsections)
## Golden signals         (traffic / errors / latency / saturation, with real metric names)
## Log shape              (top 3–5 patterns, with examples)
## Dashboards             (the ones actually worth opening)
## Upstream / downstream  (ascii flow or bullet list)
## Incident shapes        (2–4 shapes from the archive, with INC-xxxx citations)
## Caveats, footguns, known behaviors
## Confidence note        (what's grounded vs. inferred, what to refresh)
```

Subagents will try to coin new sections ("Ad-hoc scans", "Post-mortem debrief", "rtk scans"). Reject these. Use the canonical list exactly.

## Template — copy verbatim, fill in placeholders

````markdown
# Service — {service_name}

## Quick context

| Field | Value |
|---|---|
| Service name (telemetry) | `context.service.name:{service_name}` (plus aliases if any — see §"Caveats") |
| Owning team | **{team_name}** (`context.team:{team_tag}`, team id `{team_id}`) |
| Stack | {language, runtime, major frameworks} |
| Repo | `{repo_path}` |
| Environments | `prod`, `staging`, `dev` (omit any that don't apply) |
| Shape | {Deployment / StatefulSet / Lambda / Fargate, replica count if known, 1 para} |
| Workhorse status | {volume / error-rate / incident-count context, 1–2 sentences} |

{One or two paragraphs.} What does this service actually do — in one sentence, grounded in the live log evidence? What's the headline operational risk? Who cares when it breaks?

If the task brief's framing doesn't match the live-data reality, **document the discrepancy here**. The orchestrator may have been wrong. Trust the logs.

## Ready-to-run

Subsections, each a single purpose:

### Is it healthy?

```bash
# Three to five terse probes: baseline error count, request rate, saturation indicator.
# Every command must be real `tsuga` CLI. See `CLI_TRANSLATION.md`.

tsuga logs search --query "context.env:prod context.service.name:{service_name} level:ERROR" --from -1h --to now --max-results 20

# For aggregations, use the heredoc pattern:
FROM=$(date -u -v-1H +%s); TO=$(date -u +%s)   # macOS
# or on Linux: FROM=$(date -u -d '1 hour ago' +%s); TO=$(date -u +%s)
cat > /tmp/q.json <<JSON
{
  "timeRange": {"from": $FROM, "to": $TO},
  "dataSource": "metrics",
  "queries": [
    {"aggregate": {"type": "percentile", "percentile": 95, "field": "{key_metric}"}, "filter": "context.env:prod"}
  ],
  "groupBy": [{"fields": ["context.cluster_id"], "limit": 10}],
  "formula": "q1",
  "aggregationWindow": "5m"
}
JSON
tsuga aggregation timeseries -f /tmp/q.json
```

### Monitor reproduction

For each monitor that targets this service (from `monitors.json`), reproduce the exact query as a runnable `tsuga` command:

```bash
# {monitor_id}, P{priority}, {one-line name}
tsuga monitors get {monitor_id}
tsuga logs search --query "{filter from monitor config}" --from -5m --to now
# threshold: {threshold} over {window}, groupBy: {groups}
```

### Incident-drill queries

For each recurring incident shape (from `incident-files.txt`), the query that cracked it:

```bash
# drill-{shape-name} (anchor: INC-xxxx, INC-yyyy)
tsuga logs search --query "..." --from -Nh --to now
# Finding signature: {what this query surfaces}
```

## Golden signals

Traffic / errors / latency / saturation. Each signal names a **specific metric or log pattern** grounded in `tsuga metrics list` output (not invented). Threshold values should be taken from the monitor definitions where they exist.

| Signal | Metric / log | Healthy | Unhealthy | Monitor |
|---|---|---|---|---|
| Traffic | `{metric_name}` | ~{N}/s steady-state | drop-to-zero = upstream down | — |
| Errors | log count on `level:ERROR` | near zero | >{N}/5min | `{monitor_id}` |
| Latency | p95 of `{metric}` | <{ms}ms | >{ms}ms | `{monitor_id}` |
| Saturation | `{queue_depth_or_pool_metric}` | <{N} | >{N} | `{monitor_id}` |

If any signal has no live-metric backing (i.e., you can't find the metric in `tsuga metrics list`), say so explicitly: "No emitted metric for this signal; derive by log count." Don't invent a metric name.

## Log shape

Top 3–5 patterns you actually see in live logs. Each with:

1. **The pattern string** (grokable substring the agent can use in `--query`).
2. **An example log line** (one real sample from `tsuga logs search` output — redact customer names if sensitive).
3. **What it means** (one sentence).

Example:

- **`"Reconcile failed"`** — `level:ERROR context.service.name:config-store "Reconcile failed"` → the central reconcile path is sick, not the cluster-side service.

Do NOT guess patterns. Run a live `tsuga logs search` + `tsuga logs patterns` at authoring time and base this section on real output.

## Dashboards

Dashboards that actually help during an incident for this service. Include ID + tag set + graph count. Reject hand-maintained duplicates unless they have graphs the Pulumi version doesn't.

- **{Dashboard name}** (`{dashboard_id}`, `managed-by=Pulumi oncall=true`, {N} graphs) — when to open it.
- `{Dashboard name}` ({N}, `{tags}`) — secondary.

If there's no dashboard scoped to this service, say so: "No service-scoped dashboard; use **{generic cluster board}** with `context.service.name:{service_name}` filter." Don't invent IDs.

## Upstream / downstream

An ASCII diagram or bullet list. Who feeds this service, who it feeds. Cross-links to other SERVICE_KNOWLEDGE.md files.

```
              ┌────────────┐        ┌──────────────────────┐        ┌────────────┐
{upstream} ──►│ {service}  │───────►│ {next-service}       │───────►│ {sink}     │
              └────────────┘        └──────────────────────┘        └────────────┘
                   │
                   └──► (sidecar effect)
```

Plus a bullet list of cross-service dependencies / blast radius. Cross-team dependencies (e.g., "loads data-science-rust wheel") are especially important — they're the source of surprising failures.

## Incident shapes

2–4 shapes from the archive. Each:

1. **One-sentence title.**
2. **Anchor incidents** — INC-xxxx, INC-yyyy from `incident-files.txt`. Cite paths: `skills/incident-history/references/incidents/INC-xxxx/SUMMARY.md`.
3. **First probe** — which Ready-to-run query or monitor-repro to start with.

Example:

1. **Fleet-wide poll/reconcile failure → upstream reconciler is sick (INC-0042, INC-0043).** Many clusters show the same ERROR string simultaneously; service itself is healthy. First probe: `drill-reconcile` query above.
2. …

If the service has fewer than 2 incidents in `incident-files.txt`, keep this section but note that low-incident-count services may have unknown failure modes (flag in Confidence).

## Caveats, footguns, known behaviors

5–10 bullets. The non-obvious things an investigator needs to know. Examples:

- Service name has two forms in telemetry — OR-match both: `(context.service.name:{k8s-name} OR context.service.name:{otel-name})`.
- The P1 monitor `{id}` filters on a specific filename; if the code path moved, the monitor is silent on the real failure. Cross-check before trusting its "green" state.
- Retry WARN logs contain `"403"` and `"429"` as part of duration literals, not as HTTP status codes — don't grep blindly.
- Cross-team ownership: this service is owned by team X but its paging monitors are owned by team Y (see §"Quick context").
- The three-way cloud backend error shapes differ (S3 SlowDown ≠ Azure ServerBusy ≠ GCS 429) — always group by `context.cloud` when backend errors fire.

Do NOT pad this section with generic advice ("check logs first", "look at the dashboard"). Only service-specific footguns go here.

## Confidence note

What's grounded in live evidence, what's inferred, and what the reader should re-verify:

- **High confidence:** {monitor IDs, metric names, log patterns — anything pulled from authoritative sources and cross-validated}.
- **Medium confidence:** {things pulled from docs or team dossier but not re-probed live; dashboard counts from an aggregate that may have paginated}.
- **Low confidence / inferred:** {things the agent guessed, e.g., "probably uses Redis because the image name suggests it" — mark these clearly}.
- **What to refresh:** "re-run `tsuga metrics list` before assuming a metric is absent — this dossier used a 7-day window which may miss sparse emitters."
- **Source material quality:** flag here if `monitors.json`/`dashboards.json`/`incident-files.txt` inputs were empty at collect time.

This section is load-bearing. It's what tells a future investigator which claims in the dossier to trust and which to re-verify.
````

## Rules the subagent must follow

### On structure

1. **No extra sections.** Do not coin new headings. Use only the canonical list above.
2. **No section-header renaming.** `"## Ready-to-run"` is the literal heading, not `"## Ready-to-Run Commands"` or `"## Diagnostic Commands"`.
3. **Do not delete empty sections.** If a section has nothing for this service, write one line ("No service-scoped dashboard — …") and move on. Downstream retrieval depends on stable section names.

### On commands

4. **Every bash block must be real `tsuga` CLI.** The `CLI_TRANSLATION.md` contract is non-negotiable. After writing, run the forbidden-token grep from that contract. Zero hits required.
5. **Include the `FROM=$(date ...)` helper once per file** the first time an aggregation needs it.
6. **No `rtk` prefix, ever.**

### On content

7. **Every metric name must be real.** Before writing a metric in Golden signals, confirm it's in `tsuga metrics list`. If it isn't, say so in Confidence (low emission? renamed?) rather than writing a plausible-looking name.
8. **Every monitor ID must be real.** If the subagent's input `monitors.json` is empty, don't invent IDs — write "None owned directly; see §Typical incident shapes for shared monitors."
9. **Live probe at least once.** Run `tsuga logs search --query "context.service.name:{service}" --from -7d --max-results 50` before writing Log shape. The patterns must come from real output.
10. **Cite incident SUMMARY paths explicitly.** `skills/incident-history/references/incidents/INC-xxxx/SUMMARY.md` — the full relative path. Don't just say "INC-xxxx".

### On framing

11. **Live data beats task brief.** If the brief says "service X is the foo write-path" and live logs show it's actually a bar reconciler, trust the logs, reframe, and document the discrepancy in Quick context + Confidence.
12. **No invented acronyms.** No "rtk scans", no "RTFM checklist", no "PRoBE analysis". Use the terms established in the templates and in `LESSONS.md`.
13. **Confidence note must be honest.** If the subagent's inputs are thin or its live probes returned empty, the Confidence note should say so clearly. A fabricated dossier is worse than one with an honest "low confidence" note.

### On length

14. **Target 180–350 lines.** If over, the first things to cut are: padded Caveats, duplicated content from top-level docs, speculative incident shapes.
15. **Pointers, not duplication.** "See `COMPANY_TELEMETRY_KNOWLEDGE.md §"Canonical query patterns"` for the full table" beats pasting the table.
