# Branch: telemetry sweep

You were spawned as a telemetry-sweep subagent — this file is everything you need. You don't synthesize a verdict; you surface facts + verbatim signals for codebase-grep + a completeness-check report.

Read-only evidence gathering from Tsuga. This branch does not declare root cause on its own — it produces facts the orchestrator synthesizes.

## Inputs

Time window, scope hint (service / cluster / env / customer / monitor), reported symptom. Missing scope → return only the discovery steps needed to resolve it.

## Procedure

1. **Monitor anchor (if the case cites a monitor).** `tsuga monitors get <monitor-id>` FIRST. Read the monitor's filter, aggregation, threshold, and groupBy — this IS the exact telemetry shape that crossed. Re-run the same query against the incident window AND a control window (same weekday + hour, 7 days earlier). Record the crossed value, the control value, and the ratio.
2. **Normalize scope.** `tsuga services list|get`. Capture canonical name, env, team, versions, sources, 24h log/trace counts.
3. **Normalize session.** Check `tsuga config` (active key, default cluster). Always set explicit `--from`, `--to`, `--max-results`. For `tsuga aggregation`, convert windows to epoch seconds; on multi-cluster orgs include `"clusterId"` in the body.
4. **Load tech knowledge.** If scope names a known tech (Postgres, Redis, Kafka, …), load the matching `$knowledge-technology` reference to target the sweep.
5. **Config-threshold preflight (capacity-shaped symptoms).** If the reported symptom is capacity-shaped — queue lag, `CrashLoopBackOff`, `OOMKilled`, throttling, "too many", "insufficient" — spend one probe asking _"is there a single config knob that would fix this?"_ before any elaborate change-correlation. Grep mounted codebases / helm / Pulumi for patterns like `*BatchSize`, `*PoolSize`, `*Concurrency`, `*MaxConnections`, `*FailureThreshold`, `*InFlightBatches`, `*MemPoolSize` scoped to the affected service.
6. **Evidence sweep.** Prefer in order:
   - `logs new-error-patterns` / `logs error-pattern-increases` (when team scope exists)
   - `logs patterns` to cluster failure shapes
   - `logs search` only after pattern discovery
   - `traces search` for exact failing spans
   - `aggregation scalar|timeseries` for counts, rates, comparisons
   - `monitors list|get` for signal semantics (not live truth)
   - `dashboards list|get` / `quality-reports list` as supporting context only
7. **Compare.** Bad window vs good control window. Affected entity vs sibling healthy entity when possible.
8. **Surface verbatim signals for codebase-grep.** As the sweep produces error strings, log patterns, metric names, and monitor filters, emit them as a distinct list at the end of the output — one per line. The orchestrator will spawn a codebase-grep subagent per entry to pin each signal to its emitting `file:line`. Do not try to explain what a signal _means_ until its emitting code is found.
9. **Write evidence matrix.** Four columns: symptom evidence | subsystem evidence | mechanism clues | unknowns. If evidence only supports subsystem diagnosis, say so.
10. **Sweep completeness check.** Before returning, tick these boxes — if any is unchecked and cheap to resolve, do it now:
    - [ ] Service metadata resolved (canonical name, team, env, 24h counters)
    - [ ] Monitor's own query pulled + replayed against bad + control windows (if case came from a monitor)
    - [ ] Config-threshold preflight done (for capacity-shaped symptoms)
    - [ ] Error-log patterns scanned (`new-error-patterns` OR `patterns`)
    - [ ] Primary metric aggregated in bad window AND control window
    - [ ] At least one trace from the failing path inspected (when traces exist)
    - [ ] Recent-deploy correlation asked (even if the answer is "no data here — defer to change branch")
    - [ ] Verbatim signals surfaced for the codebase-grep branch

## No-data honesty

A metric or log pattern being absent is NOT equivalent to its value being zero. Causes of absence include receiver scope / permission issues, feature not enabled, instrumentation gap, or scrape failure.

When you checked and found nothing, say which: `(absent)` — did not appear in window `|` `(not instrumented)` — scope lacks the receiver `|` `(denied)` — permission error `|` `(empty)` — query ran, returned 0 rows. Never report silent absence as "metric is zero" in a Validated claim.

## Branch output

```
Observed symptom: <one sentence>
Monitor anchor: <monitor id + filter + threshold, or (none) if case didn't cite a monitor>
Confirmed failing subsystem: <one sentence, or (unknown)>
Signals that support it:
  - <fact with exact value> [evidence: tsuga_logs | tsuga_traces | tsuga_aggregation | tsuga_monitors | service_metadata]
Signals that do not yet support causality:
  - <what you checked that was silent>
Control-window comparison: <bad vs good: counts / rates / ratio, or (skipped) with reason>
Verbatim signals for codebase-grep:
  - "exact error string 1"
  - "exact error string 2"
  - metric.name.to_grep
  - log pattern
Config-threshold preflight result: <summary, or (N/A — non-capacity symptom)>
Best next non-Tsuga check: <one action, or (none)>
```

Every claim carries `[evidence: …]`. No tag = hypothesis, belongs in the non-causal section.

## Branch guardrails

- `metrics list|get` is metadata. Use `aggregation` for values.
- Monitor definitions are clues, not live truth.
- Do not claim deploy or config causality from Tsuga alone.
- Exact counts and windows > prose summaries.
- Stop at `symptom diagnosis only` when you can't tie the subsystem to a trigger.

More detail on `tsuga` command patterns: [tsuga-rules.md](./tsuga-rules.md).
