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
| Service catalog refresh cycle and lookback                        | `tsuga docs get categorize/guides/how-to-troubleshoot-service-inventory-issues` |
| RUM credential and the Web token's allowed domain URLs            | `tsuga docs get account-and-settings/api-keys`                                |

Hand a confirmed-language source fix to `otel-instrumentation` and a Collector config fix to `otel-collector` once the fault surface is identified.

## Classify The Gap First

Name one of these before the second query. Each has a different next hop, and the wrong one costs an hour.

- **Service not visible.** `tsuga services list` is a catalog, not arrival evidence. `categorize/guides/how-to-troubleshoot-service-inventory-issues` has the refresh cycle, the lookback and the removal delay. A service that started sending minutes ago has no row yet. One that stopped within the last week keeps one. Query the signal directly before concluding either way.
- **All signals missing.** One thing shared by all three: endpoint, key, protocol, or a Collector that is down. Not instrumentation.
- **One signal missing.** That signal's provider, exporter, or pipeline. The other two already prove the endpoint and the key work.
- **Sparse signal.** A sampler or a filter processor, not export.
- **Collector path.** Separate app-to-Collector receipt from Collector-to-Tsuga export. A Collector that logs receipt proves nothing about export, and the two fail for unrelated reasons.
- **Propagation.** Only once spans exist on both sides.

## What A Result Does Not Prove

- **A `200` from the exporter means Tsuga accepted the request for processing and nothing more.** `data-collection/guides/intake-limits-and-responses` has the response codes, the absent partial-success counts, and the rule that querying for the record is the only proof it was stored. Request size, credentials, and the `Content-Type`/format selector are checked before the `200`; nothing that needs the payload decoded is. A batch sent to the wrong signal path is size-checked, authenticated, and answered `200` before anything discovers it cannot be decoded.
- **Freshly sent data is not immediately queryable.** `data-collection/guides/how-to-validate-telemetry-arrival-in-tsuga` gives the per-signal delay and the minute to wait before an empty result means anything. RUM lands on the same write batch as metrics. "Not observed" on a window ending seconds ago is not evidence.
- **A timestamp in the future is accepted and then unqueryable.** `intake-limits-and-responses` has the age rule and the clock check. It is the one failure that looks exactly like a broken exporter, so classify it before the pipeline when a single host is missing and its neighbours are fine.
- **A `403` seconds after a key was created or rotated is not a wrong key.** `intake-limits-and-responses` has the credential reload cycle. Re-send once before acting on the `403`.
- **`tsuga metrics list` ignores `--from` and `--to`.** A five-minute window and a seven-day window return the same list. `how-to-validate-telemetry-arrival-in-tsuga` covers the rest: the list is a cluster-wide name catalog that outlives the metric, and only a count over the window is arrival evidence. `tsuga metrics get <name>` reads that same catalog and returns metadata only.
- **Metric attribute keys are lowercased on ingest.** `data-collection/guides/default-mapping-for-opentelemetry-formats` has the rule, the empty result a wrong-case filter returns, and which signals are exempt. RUM keys keep their case too. From the CLI, read the spelling off the `attributes` list in `tsuga metrics get <name>` before reporting a metric as missing.
- **Absence of callee spans is not propagation evidence.** That is an ingestion or instrumentation gap on the callee. Broken linkage needs callee spans carrying a missing or wrong parent, or several unrelated trace IDs for one logical request.

## RUM

`tsuga rum search` is the arrival check; `tsuga-cli` holds the stream prefixes and the permission it needs. Two gaps are RUM-only:

- The RUM intake takes a **public token**, not an ingestion key. `data-collection/mobile/rum-events` and `account-and-settings/api-keys` have the credential split and the Web token's allowed domain URLs. When classifying: an exporter aimed at the wrong intake is rejected at authentication rather than accepted and silently dropped, so there is a failing response to read; and a `403` from a browser token points at the page's origin before the token.
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
