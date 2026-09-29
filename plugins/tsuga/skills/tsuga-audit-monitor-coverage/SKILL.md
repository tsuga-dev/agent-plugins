---
name: tsuga-audit-monitor-coverage
description: "Audits Tsuga alerting configuration for coverage and routing gaps, separating exact service matches from glob, env, cluster and team-scoped coverage. Use when asked to check monitor coverage, services without monitors or SLOs, alerting gaps, notification routing, notification rules, silences, stale team references, PagerDuty or Slack destinations, teams without configured alerts, monitor ownership, monitor filters, log-error-pattern coverage, SLO alert coverage, active or inactive routing rules, coverage summaries or coverage percentages. This is a configuration audit, never live firing state. For reading or editing a single monitor, use tsuga-cli instead."
---

# Audit Monitor Coverage

Answer two questions from configuration alone: which services nothing watches, and which monitors
reach nobody. Both are snapshots of config. Nothing here shows whether an alert fired, or would.

## Required Inputs

- **Scope** — defaults to every service, and can narrow to one team, service or env. `services list`
  takes no filter flags, so a narrower scope is a local filter over the same rows.

Pull each list at the largest page the CLI allows. The paging flags are in
`account-and-settings/ai-access/tsuga-cli`. Nothing in the JSON on stdout carries a total, so the
returned row count **is** the total unless the truncation line appeared. When it did, take the total
from it: `Showing 2 of 91 (offset 0). Use --limit … --offset 2 …`. Confirm the scope with the user
before auditing more than 100 services.

A `services list` row is one (service, env) pair, so a service running in three environments is
three rows. State which denominator the percentages use.

## Where a service name lives

`monitors list` returns a union discriminated by `configuration.type`, and the service sits
somewhere different in each shape:

- `metric`, `log`, `trace`, `anomaly-log`, `anomaly-metric`, `anomaly-trace` — in
  `configuration.queries[].filter`, a query string; read `context.service.name:` out of it
- `log-error-pattern` and `log-error-pattern-increase` — both in
  `configuration.filter.services[]`, beside the required `configuration.filter.env` and the
  optional `configuration.filter.teamIds[]`. They watch different failures: the first fires on a
  new pattern, the second on a volume spike in an existing one, so a service carrying only one is
  uncovered for the other. Count them separately.
- `certificate-expiry` — nowhere; it watches certificates, never a service

`filter.services` and `filter.teamIds` are both optional and a real monitor often carries only one
of them. A log-error-pattern monitor scoped by team alone has no `services` key: that is coverage of
every service those teams own, not zero coverage.

A metric monitor may filter on a metric label instead of `context.service.name` — a Prometheus
`service_name`, or a cloud provider's own dimension. The key in the filter may not be spelled the way
the sender emitted it. `data-collection/guides/default-mapping-for-opentelemetry-formats` has the
rule. Count such a filter as naming the service, and say which key matched.

SLOs cover services the same way and alert through the same rules. Fetch
`tsuga docs get references/slos/overview` when the audit includes them, and count an SLO as coverage
on the conditions that page sets.

## Exact versus indirect

Exact coverage: the filter names the service, quoted or not, with no wildcard —
`context.service.name:checkout`.

Everything else is *possible or indirect coverage*, reported in its own section with the match basis
written out:

- a glob — `context.service.name:web-*` covers `web-admin` only once you expand it
- env, namespace, `context.cluster_id`, or the monitor's own `clusterIds[]` — scope that names no service
- a log-error-pattern monitor scoped only by `teamIds`

Never fold indirect coverage into the covered count. Someone deciding whether to add a monitor needs
the two separated.

To narrow before parsing, `monitors list -d '{"filters":{"searchQuery":{"value":"checkout"}}}'`
matches server-side against monitor ID, name, **query filters** and aggregate fields. It is a
case-insensitive substring and wildcards in it are literal, so `api` also returns `api-gateway`
monitors. It never reads `configuration.filter.services[]`, so a log-error-pattern monitor naming the
service only there is missing from the result and the service reads as uncovered. Use it to reach one
monitor, never to build the set a coverage count is computed from.

## Routing

`tsuga docs get alert/notifications/rules` states how a rule matches a transition — team, priority,
status, cluster, additional filters, and the rule that an empty filter matches every value on that
dimension. Fetch it instead of re-deriving it. Three things decide an audit:

- Every rule has at least one destination — `targets` carries `minItems: 1`, so the API rejects a
  rule without one and the app blocks it earlier. Read `targets` to say *where* an alert goes; do not
  audit for an empty one, and do not report its absence as a routing gap.
- Adaptive rules are a separate resource with no public endpoint, so every surface that reads rules
  programmatically returns standard rules only and drops adaptive ones without saying so. Never
  assert nobody is paged: report the finding as "no standard rule matches".
- `teamsFilter` is a union on `type`. `teams[]` exists only when `type` is `specific-teams`;
  `all-teams` and `all-public-teams` carry no array and cover their whole scope. Reading
  `teamsFilter.teams` unconditionally invents a gap on every rule of the other two types.

A team ID in a `specific-teams` filter that `teams list` does not return is a stale reference. Join
on team **ID**: `teams list` gives `{id, name, visibility}`, and `visibility` is what decides whether
`all-public-teams` reaches a team. A service's `teams[].team` is an observed team *name* from
telemetry with its own refresh lag, so resolve it through `teams list` before comparing it to
anything on a monitor or rule.

Cross-check rather than replace: `tsuga quality-reports list --team <team-name>` carries one
`monitor-has-notification` row per team, computed server-side with the real matcher. It shares the
adaptive-rule blind spot.

## Silences

`tsuga docs get alert/notifications/silences` ("Schedules and statuses") separates enabled from
expired and says which schedule type carries what. Fetch it instead of guessing.
`notification-silences list` returns every silence, expired ones included, and takes no pagination
flags, so filter to the active ones yourself. Report `schedule.endTime` for a one-time silence, and
the weekly windows plus `schedule.timeZone` for a recurring one. `schedule.timeZone` is UTC when
absent.

## Evidence Rules

- "No coverage" = no exact `context.service.name` match, no `filter.services` entry, no SLO naming it.
- "Routing gap" = no active standard rule holding a target matches.
- A filter shape you cannot parse is reported as unknown, never as uncovered.

## Safety

- Creating monitors or notification rules mutates. Show the full proposed list with the reason for
  each, wait for explicit confirmation, then apply only what was confirmed.
- Build payloads from `tsuga monitors create --generate-skeleton` and
  `tsuga notification-rules create --generate-skeleton`. Fetch `api/createMonitor` or
  `api/createNotificationRule` only when a field's meaning, enum or response shape is unclear.
- Never state that a monitor is firing, or that a gap has caused a missed alert.

## Output Template

````
## Monitor Coverage Audit
Scope: <all services / team <name> / service <name>> | As of: <query timestamp>

## Summary
(service, env) pairs audited: <N> | Exact coverage: <N> (<pct>%) | No coverage: <N>
Teams with monitors but no matching standard rule: <N> | Active silences: <N>

## Uncovered
| Service | Env | Team | Nearest indirect match |
|---|---|---|---|

## Possible or Indirect Coverage
- <monitor or SLO name>: <filter value> — matched on <glob / env / namespace / cluster / team> (owner: <team>)

## Routing Gaps
| Team | Issue |
|---|---|
| <team> | Monitors owned, no active standard rule with a target matches |
| <team> | Rule <name> references team ID <id>, absent from `teams list` |

## Active Silences
- <name>: <scope>, <one-time until endTime / recurring weekly, timezone>

## Suggested Remediation
<proposed monitors and rules, each with the gap it closes — awaiting confirmation>
````

## Limitations

- Services are a telemetry-derived inventory, not an ownership registry.
- Routing gaps are bounded by "standard rules only" — adaptive rules are invisible to the CLI.
- A monitor or rule created after the query is not in the result.

## Related Skills / Next Steps

- `tsuga docs get references/slos/overview` — SLO coverage and how SLO alerts route
- `tsuga-cli` — evidence citation, query-timestamp reporting, quality-report staleness and
  confirm-before-mutating all apply here and are not repeated above
- `tsuga-investigate-service-health` — check the current health of a service found uncovered
- `tsuga-debug-telemetry-ingestion` — a service missing from `services list` is an ingestion
  question, not a coverage one
