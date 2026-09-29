---
name: incident-investigation
description: "Runs a full incident investigation: classifies the incident mode, anchors on the monitor that fired, spawns parallel telemetry, change-correlation, codebase-grep and challenger branches, holds hypotheses behind evidence gates, and publishes an investigation record and proofs dashboard. Use for active-incident investigation, post-incident RCA, or recurring-degradation triage, when a monitor fires, a customer reports slow, errored or missing telemetry, or an incident is declared. It enforces a strict time discipline so no evidence postdating the declaration reaches the verdict. For a quick single-service health check with no RCA, use tsuga-investigate-service-health instead."
---

# Incident Investigation

Primary entry point. Read-only for everything **except the two standing deliverables** — the Tsuga investigation record and the proofs dashboard (`references/incident-response/investigation-record`) — which every concluded investigation publishes by default (skip conditions in step 10). All other mutations require an explicit user ask.

## How to read this skill

Read selectively based on your role. Every `references/incident-response/...` path below is a page served by Tsuga, not a local file. Fetch one with `tsuga docs get <path> | jq -r .content`; these pages are path-addressed only and never appear in `tsuga docs search`.

- **Orchestrator (primary agent running the whole investigation):** everything here is yours except the branch pages, which the subagents own. You spawn them at step 5 and synthesize their outputs at step 8/9.
- **Telemetry-sweep subagent:** fetch `references/incident-response/branch-telemetry-sweep` — that page is everything you need. Skip the workflow, ledger, gate and verdict.
- **Change-correlation subagent:** fetch `references/incident-response/branch-change-correlation` — that page is yours.
- **Codebase-grep subagent:** you're spawned with one verbatim signal (error string, metric name, log pattern). Grep the codebases mounted in this container for that literal string; return the `file:line` and ~5 lines of surrounding context (the enclosing function + nearby conditions that trigger the emission). Nothing else. You do not interpret — you locate.
- **Challenger subagent:** you're spawned with the leading hypothesis and the current evidence. Name the single piece of evidence that would most cleanly falsify it, and say whether it's been checked. Do not build competing hypotheses; just falsify.

Each branch page ends with its own output contract; the orchestrator synthesizes those into the final verdict.

## Inputs

Minimum viable case:

- what is broken
- when it started (the incident's `declared_at` is your "now")
- scope: service, cluster, customer, env, or monitor

Accept a human summary or a case manifest (`references/incident-response/case-manifest`). If scope is unclear, ask for the smallest missing fact — do not launch a generic sweep.

## Time discipline (hard rule)

**Treat `declared_at` as the present.** The investigation must produce the conclusion a responder could have reached at the moment the page fired, not the one a historian can see after the fix shipped.

- **Do not read commits, PRs, merges, issues, or code review comments dated at or after `declared_at`.** Not to "verify" a hypothesis. Not to "confirm" a PR's diff. Not to quote a fix PR's title or body. Seeing the fix is not allowed to influence — or validate — the causal chain you return. Treat any PR that postdates `declared_at` and lands in front of you anyway as invisible: it is the answer key, not evidence.
- This rule overrides every branch. The change-correlation page carries the `git` / `$gh` time bounds that enforce it.
- If you genuinely cannot reach a verdict without peeking past `declared_at`, return `insufficient evidence` with the probes you would run next. That outcome is strictly better than a causal chain contaminated by hindsight.

Citing any PR / commit / merge dated at or after `declared_at` in your final verdict invalidates the result. Verdict must state, once, what its latest cited change is and confirm that date is `< declared_at`.

## Anti-patterns

Check these during synthesis:

1. **Solve the wrong task.** Setup / migration / monitoring / alert-cleanup channels are not outage RCA.
2. **Confuse symptom with cause.** 5xx, queue lag, empty graphs = the broken layer, not the trigger.
3. **Overfit to loudest telemetry.** A loud error stream can be unrelated to the reported symptom.
4. **Skip `what changed?`** Deploys, config drift, key rotation, quotas, schema changes explain most incidents.
5. **Trust alert semantics too quickly.** A monitor or graph gap is not proof of outage or persistence.
6. **Close uncertainty too early.** One noisy surface ≠ one explanation. Keep alternatives alive.
7. **Return non-answers.** Placeholder chatter is worse than a narrow honest next step.
8. **Merged ≠ deployed.** A merged PR is not evidence the change reached the affected environment.
9. **Blame a PR without tracing the signal to its emitting code.** A PR that merged in the right window and touches "the right area" is a candidate, not a confirmation. Pin each verbatim signal (error string, metric name, log pattern) to the `file:line` that emits it _first_, then check whether the PR's diff modifies that exact path.
10. **Skip the monitor's own query.** If the case came from a monitor firing, that monitor's filter + threshold IS the first `Saw` of your diagnostic path. Pull it with `tsuga monitors get <id>` before running broader log searches.
11. **Read the error string literally.** Re-read the raw verbatim error before building a narrative around it. The gate's literal-signal check (step 7) is the full version.
12. **Empty metric series is not a measured zero.** No points can mean the metric is not emitted for that scope, a wrong name, or a scrape gap. Before a hypothesis dies on "the metric shows nothing", confirm the metric emits for that scope at all, or switch to a signal that answers the same question.
13. **Rank ambient telemetry above human hints.** What a human already told you about the case outranks whatever is loudest in the data.
14. **Treat `mitigated` as `fixed`.** A restored service is not a removed cause. Record the mitigation and keep the root fix open.
15. **Let a prior-incident analogue override the raw signal.** When an analogue suggests a cause but this case's literal error string or metric shape contradicts it, trust the literal signal. Same bug class ≠ same bug instance.

## Workflow

### 1. Classify incident mode

Pick one: `outage_RCA` | `monitoring_watch` | `setup_onboarding` | `migration_decommission` | `targeted_subtask` | `validation_noise`.

Non-outage modes skip the full telemetry sweep and produce task-shaped output.

**Healthy-signature fast-path.** Before defaulting to `outage_RCA`, scan the case for these early-exit signals:

- Monitor state is `resolved` / `normal` / `ok` AND no downstream user-visible impact in the case hints → pick `monitoring_watch`, verdict `healthy` after ONE confirmation query. Do not spawn branches.
- Alert severity is `info` / `none` / empty AND no explicit customer complaint → `validation_noise`.
- `resolved_at − declared_at < 2 min` with no user-visible-impact hint → self-resolved stale alert; verdict `healthy`.
- Symptom is phrased "works for some customers but not others" WITHOUT a specific affected tenant / cluster / region → insufficient scope; ask for the partition before sweeping.

Fast-path triage is cheap: one probe, one classification, publish. Silence after verification IS a valid healthy signal (no errors found = no problem) — just say so explicitly in the verdict and cite the query that confirmed it.

### 2. Build case board

Track six fields, separate:

- reported symptom
- user-visible impact
- mitigation status — is impact still ongoing, and what (if anything) has already stopped it?
- human hints already present
- recent change candidates
- missing facts

Do not let `failing subsystem` silently replace `root cause`.

For an active incident with ongoing impact, mitigation is the first question, not the last. Identify the fastest action that restores service — rollback, failover, scale, flag flip — and surface it early, in parallel with the RCA; never gate stopping the bleeding on a completed root cause. Mitigation actions postdate `declared_at`; that does not violate Time discipline — they document the response and never feed the causal chain.

Then open a Tsuga investigation record (beta) so progress is visible while you work. This is a default deliverable — create it without asking, unless the user opted out. Check the environment first: `tsuga config` for the active key, and pass `--cluster <id>` explicitly on every call (`tsuga clusters list` to confirm the id) — `tsuga config` does not report the cluster.

```bash
tsuga investigations create -d '{
  "name": "<INC-id>: <symptom, a few words> — investigating",
  "slug": "<inc-id>-<symptom-in-kebab-case>",
  "owner": "<owning-team-id>",
  "contentMd": "## Investigating\n\n<case board: symptom, impact, hints, change candidates, missing facts>",
  "linkedAssets": [{"type": "monitor", "id": "<fired-monitor-id>"}]
}'
```

`name`, `slug` and `owner` are required on create — `tsuga investigations create --generate-skeleton` cannot show you that, so build the body from the fields above. (If the skeleton call errors out instead of printing JSON, that is the CLI defect, not a bad payload.) `slug` is immutable, kebab-case and org-unique; emit the same value in your own telemetry so the record links back to this run.

Keep the returned `id`: you update this record at checkpoints and finish it at step 10. Field-by-field rules, the `contentMd` template and the environment-hygiene checks live in `references/incident-response/investigation-record`. A 403 means the key lacks `investigation` write, or write on the owning team you passed — skip the record, run the investigation as normal, never retry or block on it, and name the skip in the verdict's `Deliverables:` line.

### 3. Anchor from the broken monitor (if the case cites one)

If the alert or case manifest references a monitor ID, `tsuga monitors get <monitor-id>` **first** — the monitor's own filter + threshold + groupBy IS the telemetry shape that crossed, by definition.

Treat the monitor query as the first entry in the diagnostic path:
`Saw: monitor <id> "<name>" crossed threshold <N>` → `Check: <monitor filter + aggregation>` → `Confirms: <actual value in bad window vs control>`.

Then re-run that same query against the incident window AND a control window — confirm the cross, quantify the delta. This pins the investigation to the exact signal that fired the page, not a rediscovered one. Do **not** start with a broad `logs search` when a specific monitor query is already framed for you.

### 4. Load domain playbook (if scope matches)

One sentence of matching is enough to load one. Zero is fine. All-of-them-from-fear is not.

- DB / RDS / Postgres / MySQL / connections / replication → `references/incident-response/playbooks/database`
- Kubernetes / pod / OOM / CrashLoopBackOff / node → `references/incident-response/playbooks/kubernetes`
- Deploy / config drift / flag / IAM / key rotation → `references/incident-response/playbooks/deploy-drift`
- Queue / pub-sub / lag / backpressure → `references/incident-response/playbooks/queue-backpressure`
- Cert / TLS / SSO / OAuth / credentials → `references/incident-response/playbooks/auth-tls`
- Data quality / schema / upstream API / empty output → `references/incident-response/playbooks/data-quality`

If scope names a specific tech (Postgres, Redis, Kafka, …), the telemetry branch loads its `$knowledge-technology` reference. You don't need to orchestrate that.

### 5. Plan parallel branches — spawn subagents generously

Disjoint goals, run concurrently. Each branch is its own subagent; do not serialize.

- **telemetry sweep** — spawn against `references/incident-response/branch-telemetry-sweep`.
- **change correlation** — spawn against `references/incident-response/branch-change-correlation`.
- **history** — `$incident-history` (prior incident archive mining, if mounted).
- **codebase-grep** — the emphasis branch. One subagent per verbatim signal the telemetry sweep surfaces; 5 signals → 5 parallel greps. Brief them per the role list at the top of this skill.
- **challenger** — one subagent against the leading hypothesis, same role list.

Spawning a grep per signal is what turns change correlation from "PRs touching this directory" into "PRs touching the line that emits this signal" — a much stronger mechanism, and cheap enough that skipping it is never the economical choice.

Merge results as they land; don't wait on all.

**Cost discipline.** Prefer cheap, high-signal probes before expensive ones:

- `logs new-error-patterns` / `logs error-pattern-increases` (cheap — pre-computed) before `logs search`
- `logs patterns` (bounded cluster) before `logs search --query '*'` (unbounded scan)
- `aggregation scalar` before `aggregation timeseries` at broad group-by limits
- `services get` for the trace request rate (req/s) and error rate (%) over the last hour, plus team / env / versions, before drilling into per-log detail — it returns no counts and no log volume; use `aggregation scalar` for those
- `grep -rn` across codebases (cheap, parallel) before elaborate change-correlation hypotheses

A broad `logs search` with no service / team scope is the most expensive move — save it for when you have a specific error string to chase.

### 6. Hypothesis ledger

Per candidate cause, record:

- symptom it explains
- evidence supporting (with source tag)
- evidence against
- fit with recent changes (what PR, what `file:line` from codebase-grep)
- fastest falsification step

Carry ≥ 2 candidates until one is confirmed or alternatives are falsified.

**Steelman alternatives.** For each non-leading candidate, write one sentence: _"what evidence would I need to see to promote this to the leading hypothesis?"_ If any of those sentences describes a probe you haven't run yet AND it's cheap, run it before committing to the current leader.

### 7. Evidence-gap gate (loop or publish)

Before locking a verdict, run this check on the leading hypothesis:

1. **Evidence breadth.** Does it have ≥ 2 independent evidence types (e.g. `tsuga_logs` + `tsuga_aggregation`, or `tsuga_aggregation` + `gh_pr`)? A single-source confirmation is too fragile for `confirmed`.
2. **Strongest falsifier.** Name the single piece of evidence that would most cleanly disprove it. Have you checked for it?
3. **Alternative closure.** For the second-ranked hypothesis: do you have a specific signal that rules it out, or are you just deprioritizing by gut feel?
4. **Literal signal check.** Re-read the raw verbatim error / metric shape / log pattern. Does its literal wording contradict your leading hypothesis? If the error says "expected a sequence" and your hypothesis doesn't explain why the payload was a map, the literal signal is pointing somewhere you haven't looked — restart from the literal reading.
5. **Codebase pin.** For the leading hypothesis, do you have a `file:line` where the observed signal is emitted (from the codebase-grep branch)? If not, spawn that grep now — it's cheap and usually decisive.

If any answer is no AND the missing check is cheap (one more `aggregation`, `logs patterns`, or codebase grep), **loop back to the relevant branch for that specific query** before assigning the verdict. Don't run a second full sweep — run one targeted probe.

If the missing check is expensive or the signal is genuinely unreachable, state that explicitly in `Open unknowns` and downgrade verdict to `most likely` or `insufficient evidence`.

If you opened an investigation record in step 2, push a progress update at each gate pass — current leading hypothesis, what was just checked, what's next, and (for an active incident) the mitigation status:

```bash
tsuga investigations update <id> -d '{"name": "<same name>", "owner": "<owning-team-id>", "contentMd": "## Investigating\n\n<current state>"}'
```

### 8. Validate claims

Run this procedure on every `Validated claim` before publishing:

1. Read the `[evidence: <source>]` tag.
2. Grep the session's tool outputs for the quoted value (exact count, timestamp, error string, identifier).
3. Three outcomes:
   - **Found verbatim** → keep as validated.
   - **Present but paraphrased** (e.g. claim says "~1k errors", tool showed `1247`) → rewrite claim with the exact value, keep validated.
   - **Not found** → demote to `Non-validated` and say what would confirm it.

**Mechanistic-fit check for `[evidence: local_git]` / `[evidence: gh_pr]` claims.** Temporal correlation + surface match is necessary but NOT sufficient. A claim that a PR caused the incident needs:

- The PR's diff changes function `F`.
- Function `F` emits observation `O` (confirmed via codebase-grep).
- Observation `O` is what the telemetry actually recorded.

If the diff is "in the same area" but you can't trace `diff → emitter → observation`, downgrade the verdict from `confirmed root cause` to `most likely` and flag `mechanism not fully traced` in Open unknowns.

Hallucinated citations are worse than missing ones. When in doubt, demote.

### 9. Assign verdict + category

**Verdict** (pick one):

- `confirmed root cause` — ≥ 2 evidence types AND (direct artifact OR clear trigger with strong symptom alignment)
- `most likely root cause`
- `symptom diagnosis only` — subsystem known, trigger unknown
- `not an RCA task`
- `insufficient evidence`

**Category** (pick one, orthogonal to verdict):

- `configuration_error` — wrong value, missing env, flag flip, IAM mismatch
- `code_defect` — bug in recently shipped code
- `data_quality` — malformed input, schema drift, upstream API change
- `resource_exhaustion` — memory, CPU, connections, disk, quota, FDs
- `dependency_failure` — upstream service, DNS, auth provider, 3rd-party API
- `infrastructure` — node, network, cloud provider, cert expiry
- `healthy` — alert stale, metric normal, self-recovered
- `unknown` — insufficient evidence to categorize

### 10. Publish deliverables (default, not optional)

Verdict assigned → publish the two durable artifacts. Full spec and templates: `references/incident-response/investigation-record`.

1. **Proofs dashboard** — one graph per validated telemetry claim, assertion-style graph names, every query probe-verified before create.
2. **Final investigation record** — one last `tsuga investigations update <id>` that replaces the in-progress notes with the structured document, NOT a dump of the chat verdict. The name drops the "investigating" suffix.

These ship by default — do not ask permission for them. The reference page lists the only sanctioned skip reasons; whichever applies, name it in the chat verdict's `Deliverables:` line. An unexplained skip is a contract violation.

## Output contract

Return these sections in order. Write `(none)` if a section is empty — never `TBD`.

```
Verdict: <one label>
Confidence: <low | medium | high>
Category: <one category>

Headline:
<one sentence, < 120 chars, paste-ready for Slack>

Causal chain:
- <trigger>
- <propagation>
- <symptom>
(If only symptom is known, say so. Don't invent a trigger.)

Validated claims:
- <claim> [evidence: tsuga_logs | tsuga_traces | tsuga_aggregation | tsuga_monitors | gh_pr | gh_run | gh_release | local_git | incident_archive | service_metadata]
- ...

Non-validated claims:
- <inference — state what evidence would confirm / refute>

Alternatives considered:
- <hypothesis — why deprioritized or falsified>

What changed:
- <timestamp | repo | artifact type | surface | fit>

Latest cited change:
<type> <id> @ <date> — < declared_at>

Mitigation & action items:
  Status: <mitigated | not yet mitigated | none needed> — <what restored service, or why impact is still ongoing>
  Mitigation (stop the bleeding): <fastest action that restores service before the cause is fixed — rollback, failover, scale, flag flip; or (none needed)>
  Root fix: <durable change that removes the cause>
  Follow-ups: <preventive work — monitor, runbook, test; or (none)>
  Verify: <observable signal that proves the fix addressed the cause, not just quieted the symptom>

Open unknowns:
- <what you couldn't answer + what would unblock it>

Deliverables:
  Investigation record: <id + deep link | skipped — reason>
  Proofs dashboard: <id + deep link | skipped — reason>
```

## Evidence rules

- Every `Validated claim` carries an `[evidence: <source>]` tag from the allowed list.
- Quote exact counts / timestamps / error strings / identifiers. Write `1247 errors`, not `thousands of errors`.
- Domain knowledge INTERPRETS evidence; it does not SUPPLY it. If telemetry is missing, name the signal.
- Never cite file paths / SHAs / line numbers that did not appear in branch output.
- `tsuga_monitors` is a clue about signal semantics, not live incident truth.

## References

Load when needed:

- `references/incident-response/branch-telemetry-sweep` — telemetry-sweep subagent procedure
- `references/incident-response/branch-change-correlation` — change-correlation subagent procedure
- `references/incident-response/investigation-record` — durable deliverables (record + proofs dashboard) spec + templates
- `references/incident-response/case-manifest` — JSON shape for structured case input
- `references/incident-response/playbooks/` — domain disambiguation guides (step 4 lists the six)

`tsuga` command shape, query syntax, safety rules and aggregation invariants come from the `tsuga-cli` skill and `tsuga <command> --help`; this skill does not restate them.
