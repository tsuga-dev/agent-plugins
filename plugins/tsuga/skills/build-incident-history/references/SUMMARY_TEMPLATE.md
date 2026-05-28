# SUMMARY_TEMPLATE — the canonical shape of each incident's SUMMARY.md

Subagents must emit exactly these sections in this order. The retrieval layer relies on stable section names for partial-read optimizations. Do not rename or reorder.

Keep the total length under ~400 lines per incident. If you hit 400, trim — most overflow comes from unedited Slack dumps and is fine to lose. The Diagnostic path section is the one to preserve at all costs.

---

## Template body — copy verbatim, fill in placeholders

```markdown
# {incident_id} — {title}

| Field | Value |
|---|---|
| Declared at | `{declared_at}` |
| Resolved at | `{last_iso}` |
| Severity | **{severity}** |
| Affected services | `{service_1}`, `{service_2}`, … |
| Affected team | `{team}` |
| Customer (if scoped) | `{customer_or_"—"}` |
| Resolution PR | {#N or "—"} |

## Incident at a glance

One short paragraph (3–5 sentences) that a responder paged at 3am would want to read first. What broke, what the user-visible symptom was, what the root cause turned out to be, how it was mitigated. No jargon that is not already obvious from the service name.

## Timeline

Terse, dashed list. One line per event. Relative times are fine if the absolute timestamp is in the bullet too.

- `HH:MM:SS` — {event}
- `HH:MM:SS` — {event}

Rules:
- Start from the first signal (not the page — the first *anything* that was anomalous).
- Include non-agentic events too: "deploy X rolled out", "Postgres failover started", "customer reported in Slack".
- End at the declared resolution.

## Paging surface during incident

Which monitors fired, when, and what they said. Verbatim from `tsuga/monitors-fired.json` if provided, otherwise reconstruct from the Slack thread.

- `{monitor_id}` `{monitor_name}` — fired at `HH:MM:SS`, P{priority}. {one-line why it fired}

## Diagnostic path

**This is the most important section.** Every probe the responder ran to narrow down the root cause, in order. Each probe is:

1. The one-line goal ("what question does this answer?").
2. The `tsuga` CLI command, copy-pasteable.
3. The key finding — one sentence, grounded in the output.

Format:

### Probe 1 — {question the probe answered}

```bash
tsuga logs search --query "context.env:prod context.service.name:{svc} level:ERROR" --from -30m --to now --max-results 50
```

Finding: {one sentence about what the output revealed}.

### Probe 2 — {…}

```bash
# For aggregations, use the real CLI shape:
FROM=$(date -u -v-1H +%s); TO=$(date -u +%s)   # macOS
cat > /tmp/q.json <<JSON
{
  "timeRange": {"from": $FROM, "to": $TO},
  "dataSource": "metrics",
  "queries": [
    {"aggregate": {"type": "percentile", "percentile": 95, "field": "my_metric"}, "filter": "context.env:prod"}
  ],
  "groupBy": [{"fields": ["context.cluster_id"], "limit": 10}],
  "formula": "q1",
  "aggregationWindow": "5m"
}
JSON
tsuga aggregation timeseries -f /tmp/q.json
```

Finding: {…}.

Rules:
- Every command must parse as real `tsuga` CLI. See `LESSONS.md §"Commands must be tested"` for the full translation table and the forbidden-token grep.
- No `rtk` prefix.
- If the responder ran the same probe three times with different time ranges, consolidate to one probe with a note about iteration.
- If a probe returned nothing useful, **keep it** — negative probes are the most valuable signal for analogue search ("tried X, didn't help").

## Root cause

One paragraph. What was actually wrong. If the Slack thread debated multiple hypotheses, name the one that turned out to be right and briefly dismiss the others (one line each).

## Remediation

What fixed it, including (a) the immediate mitigation (rollback, scale up, restart) and (b) the durable fix (PR link). If the durable fix is still pending, say so.

- Immediate: {action}
- Durable: {PR or "pending"}

## Lessons / follow-ups

Bullets. Each is one sentence about something the team learned or committed to change. Examples from real post-mortems in this archive:

- Ratio monitors without a `noDataBehavior=alert` companion can go silent — audit critical pipelines for this gap.
- `order-ingest` dropped events for N minutes with no alert because the only P1 was on poll latency, not on batch throughput — add a throughput monitor.
- A customer had a hand-edited ingestion API key that the reconcile code path deleted on a schema migration — add a pre-reconcile diff/confirm step.

## Commentary (optional)

Italicized one-paragraph running commentary from the responder's scratch notes, if any. Useful context but not load-bearing.
```

---

## Exemplar — abbreviated

Here is what a healthy SUMMARY.md looks like in miniature:

```markdown
# INC-0001 — Metrics on acme-trading are slow

| Field | Value |
|---|---|
| Declared at | `2026-03-02T09:44:43.87Z` |
| Resolved at | `2026-03-02T14:18:03Z` |
| Severity | **P2** |
| Affected services | `query-engine`, `segment-compaction` |
| Affected team | `infra` |
| Customer | `acme-trading` |
| Resolution PR | #042 |

## Incident at a glance

acme-trading's metric queries and the UI metric-dropdown exploration were both slow starting 09:44. Logs and spans were healthy. Root cause was `segment-compaction` falling behind on metric segments for this single cluster, which forced the query-engine to scan a much larger working set per query. Mitigated by a targeted compaction kick; durable fix was to change the compaction scheduler to prioritize segments by cluster-scope read volume.

## Timeline
- 09:44:43 — first slow-query trace on acme-trading
- 09:46 — customer reports in #support
- 09:51 — responder confirms logs/spans unaffected, metrics only
- 10:12 — `segment-compaction` lag on metric segments identified (see Probe 3)
- 10:34 — manual compaction run completes, query p95 drops from 2800ms to 180ms
- 14:18 — incident resolved

## Paging surface during incident
- `8f53-hvy56-91qa` `[Prod] [health-aggregator] Query engine p95 high` — fired 09:49, P3. Fired on cluster-wide p95 > 1200ms.

## Diagnostic path

### Probe 1 — is the customer's complaint isolated to metrics?
```bash
tsuga logs search --query "context.env:prod context.cluster_id:acme-trading level:ERROR" --from -1h --to now
```
Finding: no errors. Logs + spans were healthy — metrics-only regression.

### Probe 2 — is the query engine reporting cold-path saturation?
```bash
FROM=$(date -u -v-1H +%s); TO=$(date -u +%s)
cat > /tmp/q.json <<JSON
{"timeRange":{"from":$FROM,"to":$TO},"dataSource":"metrics","queries":[{"aggregate":{"type":"percentile","percentile":95,"field":"query_below_day_duration_milliseconds"},"filter":"context.env:prod context.cluster_id:acme-trading"}],"formula":"q1","aggregationWindow":"5m"}
JSON
tsuga aggregation timeseries -f /tmp/q.json
```
Finding: p95 climbed from ~180ms to 2800ms starting 09:44 sharp.

### Probe 3 — is compaction falling behind on this cluster?
```bash
tsuga logs search --query "context.service.name:segment-compaction context.cluster_id:acme-trading level:INFO" --from -2h --to now --max-results 200
```
Finding: compaction runs were completing but `merged_doc_count` per run was 6x normal → compaction was running but not keeping up with inflow for this cluster specifically.

## Root cause
`segment-compaction`'s scheduler was round-robin across clusters, so a cluster with high metric-write volume (acme-trading during market open) could starve its own compaction while other clusters got equal time slices. Queries against the uncompacted working set hit a cold path in the query engine.

## Remediation
- Immediate: manual `compact-cluster` invocation against acme-trading at 10:34.
- Durable: PR #042 — weight the compaction scheduler by per-cluster write volume.

## Lessons / follow-ups
- Add a per-cluster compaction-lag monitor — the cluster-wide one did not fire because aggregate was fine.
- Consider a "cold-path fraction" metric on query-engine so the next one pages faster.
```

Ship at roughly this density.
