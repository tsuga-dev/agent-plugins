---
name: tsuga-audit-monitor-coverage
description: "Audits Tsuga alerting configuration for coverage and routing gaps, separating exact service matches from glob, env, cluster and team-scoped coverage. Use when asked to check monitor coverage, services without monitors or SLOs, alerting gaps, notification routing, notification rules, silences, stale team references, PagerDuty or Slack destinations, teams without configured alerts, monitor ownership, monitor filters, log-error-pattern coverage, SLO alert coverage, active or inactive routing rules, coverage summaries or coverage percentages. This is a configuration audit, never live firing state. For reading or editing a single monitor, use tsuga-cli instead."
---

# Audit Monitor Coverage

Answer two questions from configuration alone: which services nothing watches, and which monitors
reach nobody. Both are snapshots of config. Nothing here shows whether an alert fired, or would.

`tsuga docs get api/<operationId>` renders each request body field by field: what each filter
matches, enum values and their meanings, bounds and defaults. Fetch the page a step needs —
`api/queryServices`, `api/queryMonitors`, `api/createMonitor`, `api/createNotificationRule`,
`api/createAdaptiveNotificationRule`, `api/createNotificationSilence` — instead of re-deriving it. The sections below give only what those
pages do not say. None of them documents a response.

## Required Inputs

- **Scope** — defaults to every service, and can narrow to one team, service or env: narrow server-side
  with the `services list` filters.
  Set `--cluster` per cluster on a multi-cluster org, or the audit silently covers only the first
  cluster. A row is one (service, env) pair, so a service running in three environments is three
  rows: state which denominator the percentages use.

Pull each list at the largest page the CLI allows. Nothing in the JSON on stdout carries a total, so the
returned row count **is** the total unless the truncation line appeared. When it did, take the total
from it: `Showing 2 of 91 (offset 0). Use --limit … --offset 2 …`. Confirm the scope with the user
before auditing more than 100 services.

## Where a service name lives

`monitors list` returns a union discriminated by `configuration.type`. The `configuration` by-`type`
table shows which types carry `queries` and which carry `filter.services[]`.
What a coverage parse adds:

- In `configuration.queries[].filter`, a query string, read `context.service.name:` out of it.
- `log-error-pattern` and `log-error-pattern-increase` watch different failures, so a service
  carrying only one is uncovered for the other. Count them separately.
- `certificate-expiry` names no service.

A log-error-pattern monitor scoped by team alone has no `services` key: that is coverage of every
service those teams own in the monitor's `filter.env`, not zero coverage. It does not cover the same
service's rows in other environments.

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

To narrow before parsing, `monitors list --search-query checkout` matches server-side. What
the API page does not say: it does not match `configuration.filter.services[]`, so a
log-error-pattern monitor naming the service only there is missing from the result and the service
reads as uncovered. Use it to reach one monitor, never to build the set a coverage count is computed
from.

## Routing

`tsuga docs get alert/notifications/rules` states how a rule matches a transition — team, priority,
status, cluster, additional filters, and the rule that an empty filter matches every value on that
dimension. Fetch it instead of re-deriving it. Three things decide an audit:

- The API rejects a rule without a target, but older stored rules can still have `targets: []`, and
  such a rule sends nothing. Read `targets` to say *where* an alert goes, and count a rule with an
  empty one as matching nothing when you look for routing gaps.
- Adaptive rules are a separate resource: `tsuga adaptive-notification-rules list` returns them and
  `notification-rules list` never does. An adaptive rule routes the monitors and SLOs it lists in
  `monitorIds` / `sloIds`, whatever their team or priority; "Adaptive rules" on
  that page has where it pages. Pull both lists before calling a monitor unrouted.
- `teamsFilter.teams[]` exists only on `specific-teams` (the `teamsFilter` by-`type` table); `all-teams` and `all-public-teams` cover their whole scope. Reading
  `teamsFilter.teams` unconditionally invents a gap on every rule of the other two types.

A team ID in a `specific-teams` filter that `teams list` does not return is a stale reference. Join
on team **ID**: `teams list` gives `{id, name, visibility}`, and `visibility` is what decides whether
`all-public-teams` reaches a team. A service's `teams[].team` is an observed team *name* from
telemetry with its own refresh lag, so resolve it through `teams list` before comparing it to
anything on a monitor or rule.

Cross-check rather than replace: `tsuga quality-reports list --team <team-name>` carries one
`monitor-has-notification` row per team, computed server-side with the real matcher. It counts
standard rules only, so a monitor only an adaptive rule routes reads as uncovered there.

## Silences

`tsuga docs get alert/notifications/silences` ("Schedules and statuses") separates enabled from
expired and says which schedule type carries what. Fetch it instead of guessing.
`notification-silences list` returns every silence, expired ones included:
filter to the active ones yourself. Report `schedule.endTime` for a one-time
silence, and the weekly windows plus `schedule.timeZone` for a recurring one.

## Evidence Rules

- "No coverage" = no exact `context.service.name` match, no `filter.services` entry, no SLO naming it,
  and no indirect match (those go under possible or indirect coverage).
- "Routing gap" = no active standard rule matches and no active adaptive rule lists the monitor.
- A filter shape you cannot parse is reported as unknown, never as uncovered.

## Safety

- Creating monitors or notification rules mutates. Show the full proposed list with the reason for
  each, wait for explicit confirmation, then apply only what was confirmed.
- Build payloads from `tsuga monitors create --generate-skeleton` and
  `tsuga notification-rules create --generate-skeleton`.
- Never state that a monitor is firing, or that a gap has caused a missed alert.

## Output Template

````
## Monitor Coverage Audit
Scope: <all services / team <name> / service <name>> | As of: <query timestamp>

## Summary
(service, env) pairs audited: <N> | Exact coverage: <N> (<pct>%) | No coverage: <N>
Teams with monitors but no matching rule: <N> | Active silences: <N>

## Uncovered
| Service | Env | Team | Nearest indirect match |
|---|---|---|---|

## Possible or Indirect Coverage
- <monitor or SLO name>: <filter value> — matched on <glob / env / namespace / cluster / team> (owner: <team>)

## Routing Gaps
| Team | Issue |
|---|---|
| <team> | Monitors owned, no active standard or adaptive rule routes them |
| <team> | Rule <name> references team ID <id>, absent from `teams list` |

## Active Silences
- <name>: <scope>, <one-time until endTime / recurring weekly, timezone>

## Suggested Remediation
<proposed monitors and rules, each with the gap it closes — awaiting confirmation>
````

## Limitations

- Services are a telemetry-derived inventory, not an ownership registry.
- A monitor or rule created after the query is not in the result.

## Related Skills / Next Steps

- `tsuga-cli` — evidence citation, query-timestamp reporting, quality-report staleness and
  confirm-before-mutating all apply here and are not repeated above
- `tsuga-investigate-service-health` — check the current health of a service found uncovered
- `tsuga-debug-telemetry-ingestion` — a service missing from `services list` is an ingestion
  question, not a coverage one
