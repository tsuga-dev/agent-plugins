---
name: tsuga-debug-telemetry-ingestion
description: "Debugs telemetry that is not arriving: checks presence per signal, classifies the gap as service-not-visible, all-signals-missing, one-signal-missing, sparse, collector-path or propagation, and separates absence from breakage. Use when telemetry is missing, sparse, delayed or not visible in Tsuga, when verifying arrival after a deploy, when a service does not appear, when RUM events are absent from the Mobile tab, when OTLP endpoint, protocol or auth is suspect, when an exporter is aimed at the wrong intake, when a Collector accepts data that Tsuga never shows, or when spans on two sides of a call do not link. Use tsuga-audit-telemetry-quality instead once the data is arriving and the question is whether its shape is right."
---

# Tsuga Debug Telemetry Ingestion

Read-only workflow for telemetry that should be in Tsuga and is not. `tsuga-cli` owns query shape, safety, result caps, and evidence labelling. The guides below own the per-path and per-language checklists. This skill keeps what neither has: how to classify the gap, and what a Tsuga query does not prove.

## Ask First

- Service name, the signal in question (logs, traces, metrics, RUM), and an explicit window with a timezone. "This morning" is not a window.
- The ingestion path end to end: app direct to Tsuga, app to Collector to Tsuga, stdout to Collector, a scraper, or the logs API. Check the nearest sender first and never debug two hops at once.
- Propagation questions also need caller, callee, transport, and both runtimes.
- Config evidence is variable names and set/unset state. Never ask for values.

## Runtime Docs Lookup

For docs lookup rationale and docs-error behavior, follow `tsuga-cli`; examples omit `--rationale` for brevity.

| Need                                                              | Fetch                                                                         |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| Per-path and per-language failure points, sampling, propagation   | `tsuga docs get data-collection/guides/how-to-troubleshoot-missing-telemetry` |
| Per-signal arrival check and the sender log lines that prove export | `tsuga docs get data-collection/guides/how-to-validate-telemetry-arrival-in-tsuga` |
| Intake response codes, body size cap, max age at intake           | `tsuga docs get data-collection/guides/intake-limits-and-responses`           |
| Where a field landed once it arrived                              | `tsuga docs get data-collection/guides/default-mapping-for-opentelemetry-formats` |
| Trace context propagation                                         | `tsuga docs get data-collection/guides/how-to-propagate-trace-context`        |
| Producer/consumer links across a queue                            | `tsuga docs get data-collection/guides/how-to-send-traces-through-messaging`  |
| Mobile RUM classification, and the attribute each Mobile column reads | `tsuga docs get data-collection/mobile/rum-events`                        |

Hand a confirmed-language source fix to `otel-instrumentation` and a Collector config fix to `otel-collector` once the fault surface is identified.

## Classify The Gap First

Name one of these before the second query. Each has a different next hop, and the wrong one costs an hour.

- **Service not visible.** `tsuga services list` is a catalog, not arrival evidence. It refreshes on an hourly cycle from a four-hour lookback and keeps a row for a week after a service stops being seen, so a service that started sending minutes ago has no row yet, and a service that stopped days ago keeps one. Query the signal directly before concluding either way.
- **All signals missing.** One thing shared by all three: endpoint, key, protocol, or a Collector that is down. Not instrumentation.
- **One signal missing.** That signal's provider, exporter, or pipeline. The other two already prove the endpoint and the key work.
- **Sparse signal.** A sampler or a filter processor, not export.
- **Collector path.** Separate app-to-Collector receipt from Collector-to-Tsuga export. A Collector that logs receipt proves nothing about export, and the two fail for unrelated reasons.
- **Propagation.** Only once spans exist on both sides.

## What A Result Does Not Prove

- **A `200` from the exporter means the batch reached Tsuga and nothing more.** The intake authenticates the credential and checks size, content type, and backpressure; it does not decode the payload, so every content decision happens after the sender already has its `200`. That includes the signal: the intake takes the signal from the URL path, so a metrics payload posted to the traces path is accepted and lost later. OTLP replies carry no partial-success block, so `rejected_spans`, `rejected_log_records`, and `rejected_data_points` are always absent and a dropped record is invisible to the sender. Querying for the record is the only way to know it was stored.
- **Freshly sent data is not immediately queryable.** Leave about a minute between the send and the query: logs and traces wait on an index commit up to 30 seconds after intake, metrics and RUM on a 15-second write batch. "Not observed" on a window ending seconds ago is not evidence.
- **A timestamp in the future is accepted and then unqueryable.** Records are dropped only for being too old, never too new, and a future timestamp files the record in a future storage bucket that an ordinary time range never reaches. A host with a skewed clock therefore produces a permanent, silent gap that looks exactly like a broken exporter. Check the sender's clock before the pipeline when one host is missing and its neighbours are fine.
- **A key that was just created or rotated is not live yet.** The intake refreshes its credential set on a one-minute cycle, so a correct key can answer `403` immediately after setup. Re-send once before treating a `403` as a wrong key.
- **`tsuga metrics list` ignores `--from` and `--to`.** It lists the cluster's metric-name catalog, which holds names for weeks after a metric stops reporting, so a five-minute window and a seven-day window return the same list. `tsuga metrics get <name>` returns metadata only. Metric arrival evidence is an `aggregation scalar` count over the window and nothing else.
- **Metric attribute keys are lowercased on ingest.** A filter on `orgId` matches nothing while `orgid` matches, and `statusCode` arrives as `statuscode`. Trace, log, and RUM attribute keys keep their case, and so do a few metric `context.*` keys, so do not derive the spelling from what the app emits. Read it off the `attributes` list in `tsuga metrics get <name>` before reporting a metric as missing.
- **Absence of callee spans is not propagation evidence.** That is an ingestion or instrumentation gap on the callee. Broken linkage needs callee spans carrying a missing or wrong parent, or several unrelated trace IDs for one logical request.

## RUM

`tsuga rum search` is the arrival check; `tsuga-cli` holds the stream prefixes and the permission it needs. Two gaps are RUM-only:

- The RUM intake takes a **public token**, not an ingestion key, and each intake rejects the other's credential, so an exporter aimed at the wrong intake populates nothing. A browser token additionally requires the page's `Origin` to be on the token's allow list and answers `403` when it is not. A mobile token has no such check, so one build of an app can arrive while the other does not.
- Records present but a **Mobile** column empty is a classification gap, not an arrival one: each column is derived from a specific event name or attribute. Read `data-collection/mobile/rum-events` instead of re-checking export.

## Evidence Rules

- Say "not observed in <window>", never "broken", until evidence supports it.
- Arrival evidence: logs, traces, and RUM need at least one result in the stated window; metrics need an aggregation count.
- A conclusion drawn from source or config is a hypothesis. Share it and ask whether it matches how the service instruments itself before finalizing.
- Label a finding CLI data cannot confirm as `Recommendation (not verified in Tsuga)`.

## Safety

`tsuga-cli` holds the shared rules. Two more apply because this skill reads customer source and config:

- Never read `.env`, `*.secret`, `*credentials*`, or `*token*`, and never reproduce a key, token, account ID, or endpoint URL found in one.
- Before editing any source file, config, or local file, show the change and the reason, and apply it only after explicit confirmation.

## Output Template

Extend the `tsuga-cli` template with a scope block (service, signals, window, query time, any scope expansion) and this table, one row per signal tested plus Propagation:

```markdown
| Signal      | Status                                             | Evidence          |
| ----------- | -------------------------------------------------- | ----------------- |
| Logs        | Present / Sparse / Not observed / Not tested       | <command + value> |
| Propagation | Linked / Broken / Not enough evidence / Not tested | <command + value> |
```

## Related Skills / Next Steps

- `otel-instrumentation` - language-specific SDK setup, exporter config, log correlation, and source fixes.
- `otel-collector` - Collector pipeline, exporter, processor, OTTL, and redaction debugging.
- `tsuga-audit-telemetry-quality` - audit signal shape once telemetry is arriving.
- `signal-choice-advisor` - redesign signal choice, semantic naming, or cardinality after the gap is closed.
