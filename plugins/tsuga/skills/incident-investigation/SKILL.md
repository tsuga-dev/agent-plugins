---
name: incident-investigation
description: "Primary entry point for active-incident investigation, post-incident RCA, or recurring-degradation triage. Use when a monitor fires, a customer reports slow / errored / missing telemetry, an incident is declared (P1–P5), or someone asks 'what's wrong with X right now?'. Coordinates parallel evidence branches — telemetry sweep (`tsuga` CLI), change correlation (git / gh), analogue search, codebase-grep, challenger review — tracking hypotheses behind evidence gates, and produces an operator-ready verdict with cited evidence plus two durable deliverables by default: a Tsuga investigation record and a proofs dashboard."
---

# Incident Investigation

Primary entry point. Read-only for everything **except the two standing deliverables** — the Tsuga investigation record and the proofs dashboard ([references/investigation-record.md](./references/investigation-record.md)) — which every concluded investigation publishes by default (skip conditions in step 10). All other mutations require an explicit user ask.

## How to read this skill

This skill covers the full investigation loop — orchestrator-level workflow AND the detailed procedures for each parallel branch. Read selectively based on your role:

- **Orchestrator (primary agent running the whole investigation):** read Anti-patterns → Workflow (steps 1-10) → Output contract → Evidence rules → Guardrails, plus [references/investigation-record.md](./references/investigation-record.md) for the two durable deliverables you publish at step 10. You spawn subagents at step 5 and synthesize their outputs at step 8/9. The branch procedures live in their own reference files; the subagents own those — you don't read them.
- **Telemetry-sweep subagent:** read [references/branch-telemetry-sweep.md](./references/branch-telemetry-sweep.md) — that file is everything you need. Skip the workflow, ledger, gate, verdict, and the change-correlation branch.
- **Change-correlation subagent:** read [references/branch-change-correlation.md](./references/branch-change-correlation.md) — that file is yours.
- **Codebase-grep subagent:** you're spawned with one verbatim signal (error string, metric name, log pattern). Grep the mounted codebases under `{{CODEBASES_DIR}}` for that literal string; return the `file:line` and ~5 lines of surrounding context (the enclosing function + nearby conditions that trigger the emission). Nothing else. You do not interpret — you locate.
- **Challenger subagent:** you're spawned with the leading hypothesis and the current evidence. Name the single piece of evidence that would most cleanly falsify it, and say whether it's been checked. Do not build competing hypotheses; just falsify.

Subagents return branch-shaped output (their section's Branch output contract). The orchestrator synthesizes them into the final verdict.

## Inputs

Minimum viable case:

- what is broken
- when it started (the incident's `declared_at` is your "now")
- scope: service, cluster, customer, env, or monitor

Accept a human summary or a case manifest ([references/case-manifest.md](./references/case-manifest.md)). If scope is unclear, ask for the smallest missing fact — do not launch a generic sweep.

## Time discipline (hard rule)

**Treat `declared_at` as the present.** The investigation must produce the conclusion a responder could have reached at the moment the page fired, not the one a historian can see after the fix shipped.

- **Do not read commits, PRs, merges, issues, or code review comments dated at or after `declared_at`.** Not to "verify" a hypothesis. Not to "confirm" a PR's diff. Not to quote a fix PR's title or body. Seeing the fix is not allowed to influence — or validate — the causal chain you return.
- Git: `git log --until=<declared_at>`, `git log --before=<declared_at>`, or inspect only commits whose author/commit date is strictly before it.
- GitHub: when listing PRs via `$gh`, filter to `merged:<<declared_at>` (or `created:<<declared_at>` when arguing about what existed to be deployed). Treat any PR you happen to see that postdates `declared_at` as invisible.
- This rule overrides the change-correlation branch. A post-incident PR that "obviously" describes the root cause is the answer key, not evidence.
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
11. **Read the error string literally.** Before building a narrative, re-read the raw verbatim error. If the text says `"invalid type: map, expected a sequence"`, the payload being an array is the first thing to check — don't stack indirections on top. If literal reading contradicts your hypothesis, restart from the literal reading.
12. **Empty metric series is not a measured zero.** A query that returns no points can mean the metric is not emitted for that scope, a wrong name, or a scrape gap, not a healthy value. Before a hypothesis dies on "the metric shows nothing", confirm the metric actually emits for that scope (does another cluster or scope return it?) or switch to a signal that answers the same question.

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

Then open a Tsuga investigation record (beta) so progress is visible while you work. This is a default deliverable — create it without asking, unless the user opted out. Check the environment first (`tsuga config` — right key, right cluster; see the hygiene notes in [references/investigation-record.md](./references/investigation-record.md)):

```bash
tsuga investigations create -d '{
  "name": "<INC-id>: <symptom, a few words> — investigating",
  "owner": "<owning-team-id>",
  "contentMd": "## Investigating\n\n<case board: symptom, impact, hints, change candidates, missing facts>",
  "linkedAssets": [{"type": "monitor", "id": "<fired-monitor-id>"}]
}'
```

Keep `name` short — the app displays it everywhere; never restate it inside `contentMd`. Keep the returned `id` — you will update this record at checkpoints and finish it at step 10 with the structured document from [references/investigation-record.md](./references/investigation-record.md). Updates are full PUTs: always resend `name` and `owner` (omitted optional fields keep their current values). If the call returns 403 the key lacks the `investigations` permission: skip it silently and run the investigation as normal; never block on it.

### 3. Anchor from the broken monitor (if the case cites one)

If the alert or case manifest references a monitor ID, pull it **first** — the monitor's own filter + threshold + groupBy IS the telemetry shape that crossed, by definition.

```
tsuga monitors get <monitor-id>
```

Treat the monitor query as the first entry in the diagnostic path:
`Saw: monitor <id> "<name>" crossed threshold <N>` → `Check: <monitor filter + aggregation>` → `Confirms: <actual value in bad window vs control>`.

Then re-run that same query against the incident window AND a control window — confirm the cross, quantify the delta. This pins the investigation to the exact signal that fired the page, not a rediscovered one. Do **not** start with a broad `logs search` when a specific monitor query is already framed for you.

### 4. Load domain playbook (if scope matches)

One sentence of matching is enough to load one. Zero is fine. All-of-them-from-fear is not.

- DB / RDS / Postgres / MySQL / connections / replication → [playbooks/database.md](./references/playbooks/database.md)
- Kubernetes / pod / OOM / CrashLoopBackOff / node → [playbooks/kubernetes.md](./references/playbooks/kubernetes.md)
- Deploy / config drift / flag / IAM / key rotation → [playbooks/deploy-drift.md](./references/playbooks/deploy-drift.md)
- Queue / pub-sub / lag / backpressure → [playbooks/queue-backpressure.md](./references/playbooks/queue-backpressure.md)
- Cert / TLS / SSO / OAuth / credentials → [playbooks/auth-tls.md](./references/playbooks/auth-tls.md)
- Data quality / schema / upstream API / empty output → [playbooks/data-quality.md](./references/playbooks/data-quality.md)

If scope names a specific tech (Postgres, Redis, Kafka, …), the telemetry branch loads its `$knowledge-technology` reference. You don't need to orchestrate that.

### 5. Plan parallel branches — spawn subagents generously

Disjoint goals, run concurrently. Each branch is its own subagent; do not serialize.

- **telemetry sweep** — Tsuga evidence, monitor anchor, config-threshold preflight, surface verbatim signals. Procedure: [references/branch-telemetry-sweep.md](./references/branch-telemetry-sweep.md).
- **change correlation** — local git + `$gh`, strict mechanism fit (diff must touch emitter line). Procedure: [references/branch-change-correlation.md](./references/branch-change-correlation.md).
- **history** — `$incident-history` (prior incident archive mining, if mounted).
- **codebase-grep** — the emphasis branch. For every distinct verbatim signal the telemetry sweep surfaces (error string, log pattern, metric name, monitor filter), spawn **one subagent per signal** that greps the mounted codebases under `{{CODEBASES_DIR}}` to find the `file:line` where that signal is emitted. Output: file path, surrounding function context, nearby conditions that trigger the emission. 5 signals → 5 parallel greps — this scales linearly and each one returns a sharp pin, not a vague area.
- **challenger** — attack the leading hypothesis. Its job is to name the single piece of evidence that would falsify the leader and say whether it's been checked.

**Why codebase-grep matters.** Knowing _where_ a signal is emitted lets you:

- verify mechanistic fit (does a candidate PR's diff actually touch this `file:line`?)
- understand _what conditions_ trigger the emission (look at the enclosing `if` / `match` / error-handling block)
- narrow change-correlation from "PRs in the area" to "PRs modifying this specific function."

Without this, you're matching PRs by directory. With it, you're matching PRs by the emitting code path — a much stronger mechanism.

Merge results as they land; don't wait on all.

**Cost discipline.** Prefer cheap, high-signal probes before expensive ones:

- `logs new-error-patterns` / `logs error-pattern-increases` (cheap — pre-computed) before `logs search`
- `logs patterns` (bounded cluster) before `logs search --query '*'` (unbounded scan)
- `aggregation scalar` before `aggregation timeseries` at broad group-by limits
- `services get` for 24h counters before drilling into per-log detail
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

Verdict assigned → publish the two durable artifacts. Full spec and templates: [references/investigation-record.md](./references/investigation-record.md).

1. **Proofs dashboard** — one graph per validated telemetry claim, assertion-style graph names, every query probe-verified before create, tagged with the incident id, owned by the affected team.
2. **Final investigation record** — replace the in-progress notes with the structured document (Summary / Key facts / Timeline / Symptoms / Contributing causes / Mitigation & action items / Open questions / Falsified along the way / Lessons learned draft). Deep-link every ID, use absolute time windows on evidence links, populate `linkedAssets` (dashboard, service, fired monitor).

These ship by default — do not ask permission for them. The only reasons to skip: the user explicitly said not to; the verdict is a fast-path `healthy`/`validation_noise` close; the key lacks the permission (403); the verdict has zero telemetry claims to graph (dashboard only); or — rarely — your own judgment that the artifact adds nothing. Whichever applies, name it in the chat verdict's `Deliverables:` line; an unexplained skip is a contract violation.

## Branch procedures (subagent references)

Each parallel branch from step 5 has its own procedure file. The orchestrator does not read these inline — it spawns a subagent and points it at the file:

- **telemetry sweep** → [references/branch-telemetry-sweep.md](./references/branch-telemetry-sweep.md) — Tsuga evidence, monitor anchor, config-threshold preflight, verbatim-signal surfacing, completeness check.
- **change correlation** → [references/branch-change-correlation.md](./references/branch-change-correlation.md) — time-bounded git + `$gh`, strict `diff → emitter → observation` mechanism fit, candidate classification.

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

### Finish the investigation record (beta)

End with one last clean update that replaces the in-progress notes with the **structured document** from [references/investigation-record.md](./references/investigation-record.md) — NOT a dump of the chat verdict. The name drops the "investigating" suffix and stays short (the app displays it; don't repeat it in `contentMd`):

```bash
tsuga investigations update <id> -d '{
  "name": "<INC-id>: <symptom, a few words>",
  "owner": "<owning-team-id>",
  "contentMd": "<structured document: Summary / Key facts / Timeline / Symptoms / Contributing causes / Mitigation & action items / Open questions / Falsified along the way / Lessons learned draft>",
  "linkedAssets": [<dashboard, service, fired monitor>]
}'
```

Beta — the API will likely change. Any 403 means the key lacks the `investigations` permission: skip the record entirely and say so; never retry or block the verdict on it.

## Evidence rules

- Every `Validated claim` carries an `[evidence: <source>]` tag from the allowed list.
- Quote exact counts / timestamps / error strings / identifiers. Write `1247 errors`, not `thousands of errors`.
- Domain knowledge INTERPRETS evidence; it does not SUPPLY it. If telemetry is missing, name the signal.
- Never cite file paths / SHAs / line numbers that did not appear in branch output.
- `tsuga_monitors` is a clue about signal semantics, not live incident truth.

## Guardrails

- **Record + dashboard are deliverables, not extras.** Default close-out (step 10); skipping either needs a named reason in the verdict's `Deliverables:` line.
- Classify task before triage.
- Ask `what changed?` early.
- Human hints before ambient telemetry noise.
- Separate symptom / subsystem / trigger.
- Preserve uncertainty when evidence is thin.
- `merged` ≠ `deployed`. `subsystem` ≠ `root cause`. `symptom` ≠ `trigger`. `mitigated` ≠ `fixed` — a restored service is not a removed cause; record the mitigation and keep the root fix open.
- **Raw signal overrides analogue.** When a prior-incident analogue suggests a cause but the current case's literal error string / metric shape contradicts it, trust the literal signal. Same bug class ≠ same bug instance.
- **Every verbatim signal gets a codebase pin** before it feeds into change-correlation. No pin → don't blame a PR yet.

## References

Load when needed:

- [references/branch-telemetry-sweep.md](./references/branch-telemetry-sweep.md) — telemetry-sweep subagent procedure
- [references/branch-change-correlation.md](./references/branch-change-correlation.md) — change-correlation subagent procedure
- [references/investigation-record.md](./references/investigation-record.md) — durable deliverables (record + proofs dashboard) spec + templates
- [references/case-manifest.md](./references/case-manifest.md) — JSON shape for structured case input
- [references/playbooks/](./references/playbooks/) — domain disambiguation guides
- [references/tsuga-rules.md](./references/tsuga-rules.md) — `tsuga` command patterns for the telemetry branch
