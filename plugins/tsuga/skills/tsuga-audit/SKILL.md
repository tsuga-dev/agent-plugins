---
name: tsuga-audit
description: "Use for Tsuga audits: broad setup health checks, quality reports/scores/rules, telemetry quality, monitor and alerting coverage, dashboard hygiene, telemetry routes, and resource governance. Trigger on asks about log/metric/trace quality, naming, cardinality, correlation, resource identity, services without monitors, notification routing, silences, stale teams, empty/stale/unused dashboards, unrouted or over-routed logs, unused ingestion keys, tag policies, or retention policies. Ask which class to run when the request is broad or unclear."
---

# Tsuga Audit

Front door for auditing a Tsuga setup. This skill itself only decides which audit class (or classes) to run — the actual workflow, evidence rules, safety rules, and output format for each class live in `references/`, and each reference is a complete, self-contained procedure on its own.

## Audit Classes

| Class | Covers | Reference |
|---|---|---|
| Telemetry quality | Log structure/correlation, metric naming/units/temporality/cardinality, span naming/status/kind/noisy spans, quality reports, resource drift, high-cardinality attributes | `references/telemetry-quality.md` |
| Monitor & alerting coverage | Services without monitors, notification routing, silences, stale team references, PagerDuty/Slack destinations, coverage percentages | `references/monitor-coverage.md` |
| Dashboard hygiene | Empty/stale/unused dashboards, dashboard ownership, widget counts, teams without a dashboard | `references/dashboards.md` |
| Telemetry routing | The `routes` resource: unrouted logs, over-routed logs, route ownership/ranking, teams without a route | `references/routes.md` |
| Resource governance | Unused ingestion API keys, tag policy compliance, retention policy coverage/outliers | `references/resource-governance.md` |

## Workflow

1. **Pull the quality report first — it's free, pre-computed evidence spanning most of the classes below.** Quality reports are generated snapshots that score rules across logs, metrics, traces, resources, monitors, dashboards, routes, and ingestion keys in one pass; several rules map directly onto the classes below (resource governance's tag/retention-policy checks are the exception — quality reports don't score those yet, so that reference gets no seed evidence from this step). Pulling this before classifying or asking anything focuses the rest of the audit instead of starting from zero.

   ```bash
   tsuga quality-reports list --team <team> --rationale "..."
   ```

   - If the command errors on cluster selection, report the exact error and check `tsuga quality-reports list --help`; do not invent flags not shown by the installed CLI.
   - Omit `--team` only when nothing is scoped yet (the vague-request case in step 3) — a team-scoped call omits global rows, so prefer narrow when a team or service is already known, consistent with the narrow-before-broad rule everywhere else in this plugin.
   - Each row is one rule result: `ruleId`, `status` (`passed` / `failed` / `ignored`), `score`, `weight`, `owner` (team ID), `createdAt`, `recommendation`. `reportOverallScore` and `reportTotalWeight` repeat across every row from the same `reportId` — read them once, don't re-derive per row.
   - Treat `min(rows.createdAt)` as the report generation time; flag it if older than 48 hours. This is a stored snapshot, not a live view — say so in output.
   - `status: ignored` means a human explicitly suppressed that rule. Report it separately from `failed`; never fold it into a pass count.
   - **Carry each row's `recommendation` text into the reference's Recommended Actions close to verbatim.** It's computed server-side per team/rule and is already more specific than anything worth re-deriving — exact attribute names, exact Collector processor names, exact bad values found (e.g. `user_id` → `user.id`), team-scoped counts. Paraphrasing it into generic advice throws away precision that's already correct.
   - **Prioritize failing rows by estimated impact, not by list order.** The product UI shows "Estimated impact" (approximate team-score lift from fixing one rule) but doesn't expose it as an API/CLI field. Since a failed row scores `0`, approximate it yourself: `weight / reportTotalWeight` ≈ the score improvement from fixing that one rule. Treat this as directional — it isn't confirmed to match the UI's exact internal formula — but it's enough to answer "which one should I fix first."
   - If the user is asking what a quality report *is* or how scoring works, rather than requesting an audit, fetch `tsuga docs get account-and-settings/quality-reports` for the concept. Don't fetch it for remediation guidance — the `recommendation` field per row already covers that, fresher and more specifically than the doc's prose.

   Route `failed` (and `ignored`, reported separately) rows to a class by `ruleId`:

   | `ruleId` family | Class |
   |---|---|
   | `no-empty-dashboards`, `no-stale-dashboards`, `no-unused-dashboards` | Dashboard hygiene |
   | `monitor-has-notification`, `no-orphan-monitors`, `no-redundant-monitors`, `no-flapping-monitors`, `no-noisy-group-monitors`, `no-long-alert-monitors` | Monitor & alerting coverage |
   | `team-has-route`, `unrouted-logs`, `no-over-routed-logs` | Telemetry routing — these are about the `routes` resource (who owns incoming data), not about monitors or notification-rules; don't lump them into monitor & alerting coverage even though the word "routing" is shared with notification routing. |
   | `service-name-present`, `host-name-present`, `metric-usage`, `metric-unit-consistency`, `no-absent-log-fields`, `no-error-logs-as-info`, `no-debug-logs-in-prod`, `no-duplicate-attr-values`, `no-multiline-logs`, `no-future-dated-logs`, `no-orphan-spans`, `inconsistent-attribute-naming`, `use-standard-attributes`, `k8s-*`, `db-*`, `otel-collector-self-metrics` | Telemetry quality |
   | `no-unused-ingestion-api-keys` | Resource governance |
   | `no-unused-operation-api-keys`, or anything else that doesn't match a class above | Not owned by a reference yet — no CLI resource exists to manage or list operation API keys, so this stays report-only. Report it directly in a top-level "Other Quality Report Findings" note rather than forcing it into a class. |

   This list reflects the rule catalog observed at authoring time — quality-report rules evolve, so if an unfamiliar `ruleId` shows up, read its `recommendation` text to classify it rather than assuming it doesn't map to anything.

2. **Classify the request.** Check it against the keyword lists in the Audit Classes table (and this skill's own description). If it clearly names one class, skip straight to step 4 for that reference.

3. **If the request is broad or doesn't indicate a class** — e.g. "audit my tsuga setup," "audit everything," "how healthy is my Tsuga config" — ask before proceeding, using the failing-row counts from step 1 to make the choice concrete instead of abstract:

   > Which would you like audited? (Quality report shows N failing telemetry rules, M failing monitor rules, K failing dashboard rules, R failing routing rules, G failing governance rules for this scope.)
   > 1. **Telemetry quality** — logs/metrics/traces shape, naming, cardinality, correlation
   > 2. **Monitor & alerting coverage** — which services have monitors, notification routing, silences
   > 3. **Dashboard hygiene** — empty, stale, or unused dashboards, dashboard ownership
   > 4. **Telemetry routing** — unrouted or over-routed logs, route ownership
   > 5. **Resource governance** — unused ingestion keys, tag policy compliance, retention coverage
   > 6. **Everything / full sweep**

   Wait for the answer. Don't guess at scope beyond what's already in the request — the reference workflows each have their own required-input prompts for service/team/window, so only resolve the *class* here.

4. **Load the matching reference file(s) and follow them exactly**, handing each the quality-report rows from step 1 that route to its class as seed evidence. Each reference owns its full procedure — required inputs, docs lookups, evidence rules, safety/mutation gates, output template. Do not summarize, skip, or re-derive steps from memory instead of reading the reference; they encode CLI quirks and evidence requirements that aren't obvious from the class name alone. A reference should still independently corroborate a quality-report finding with its own CLI evidence before presenting it as confirmed — except where a reference explicitly says a rule has no CLI equivalent (e.g. dashboard view counts), in which case label it as report-only evidence.

5. **Full sweep** (user picks "everything"): run each reference's workflow independently against the same scope (same service/team/window where applicable), then present one combined report:

   ```markdown
   # Combined Tsuga Audit

   ## Cross-Class Observations
   <connections between the audits worth calling out — e.g. a noisy/high-cardinality metric from the telemetry-quality pass that also has no monitor coverage, a stale dashboard that's the only dashboard for a team, or a team with no route AND no monitor for the same service>

   ## Telemetry Quality
   <that reference's own Output Template, filled in>

   ## Monitor & Alerting Coverage
   <that reference's own Output Template, filled in>

   ## Dashboard Hygiene
   <that reference's own Output Template, filled in>

   ## Telemetry Routing
   <that reference's own Output Template, filled in>

   ## Resource Governance
   <that reference's own Output Template, filled in>

   ## Other Quality Report Findings
   <failed/ignored rows whose ruleId didn't map to any class above, if any>
   ```

   If one class's workflow needs input the others don't (e.g. a time window is meaningful for telemetry quality but optional for resource governance), resolve each independently rather than forcing a single set of inputs on all five.

## Related Skills / Next Steps

- `tsuga-cli` — underlying CLI syntax every reference depends on.
- `tsuga-debug-telemetry-ingestion` — missing/sparse telemetry or broken propagation; run before a telemetry-quality audit if data isn't arriving at all.
- `otel-instrumentation` — apply confirmed-language SDK/span/metric fixes after a telemetry-quality audit identifies a fix surface.
- `otel-collector` — fix Collector transforms, routing, redaction, or enrichment affecting signal quality.
- `signal-choice-advisor` — redesign signal choice, semantic names, or high-cardinality attributes found by a telemetry-quality audit.
- `tsuga-investigate-service-health` — check current health when a coverage audit finds a gap.
- `tsuga-build-dashboard` — fix, rebuild, or repopulate a dashboard flagged by a dashboard-hygiene audit.
