---
name: incident-investigation
description: "Primary entry point for active-incident investigation, post-incident RCA, or recurring-degradation triage. Use when a monitor fires, a customer reports slow / errored / missing telemetry, an incident is declared (P1 through P5), or someone asks 'what's wrong with X right now?'. Coordinates parallel evidence branches — telemetry sweep (`tsuga` CLI), change correlation (git log / gh pr), analogue search (`$incident-history`), codebase-grep (local repos), challenger review — while tracking hypotheses and evidence gates. Classifies the investigation mode (known-symptom, novel-symptom, broad-degradation, cheat-check) up front so the branch plan matches the scope. Produces an operator-ready verdict with cited evidence, a time-bounded `Latest-cited-evidence:` trailer, and explicit 'insufficient evidence' output when probes don't converge."
---

# Incident Investigation

Primary entry point. Read-only unless the user explicitly asks for mutations.

## How to read this skill

This skill covers the full investigation loop — orchestrator-level workflow AND the detailed procedures for each parallel branch. Read selectively based on your role:

- **Orchestrator (primary agent running the whole investigation):** read Anti-patterns → Workflow (steps 1-9) → Output contract → Evidence rules → Guardrails. You spawn subagents at step 5 and synthesize their outputs at step 8/9. You do NOT need to re-read the full Branch procedures inline; the subagents own those.
- **Telemetry-sweep subagent:** jump to `## Branch: telemetry sweep`. Read its Procedure + Branch output + Branch guardrails. Skip everything above (workflow, ledger, gate, verdict) and the Change-correlation branch — those aren't your job.
- **Change-correlation subagent:** jump to `## Branch: change correlation`. Same — read only that section.
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
9. **Blame a PR without tracing the signal to its emitting code.** A PR that merged in the right window and touches "the right area" is a candidate, not a confirmation. Pin each verbatim signal (error string, metric name, log pattern) to the `file:line` that emits it *first*, then check whether the PR's diff modifies that exact path.
10. **Skip the monitor's own query.** If the case came from a monitor firing, that monitor's filter + threshold IS the first `Saw` of your diagnostic path. Pull it with `tsuga monitors get <id>` before running broader log searches.
11. **Read the error string literally.** Before building a narrative, re-read the raw verbatim error. If the text says `"invalid type: map, expected a sequence"`, the payload being an array is the first thing to check — don't stack indirections on top. If literal reading contradicts your hypothesis, restart from the literal reading.

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

Track five fields, separate:
- reported symptom
- user-visible impact
- human hints already present
- recent change candidates
- missing facts

Do not let `failing subsystem` silently replace `root cause`.

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

- **telemetry sweep** — Tsuga evidence, monitor anchor, config-threshold preflight, surface verbatim signals. Full procedure in [Branch: telemetry sweep](#branch-telemetry-sweep) below.
- **change correlation** — local git + `$gh`, strict mechanism fit (diff must touch emitter line). Full procedure in [Branch: change correlation](#branch-change-correlation) below.
- **history** — `$incident-history` (prior incident archive mining, if mounted).
- **codebase-grep** — the emphasis branch. For every distinct verbatim signal the telemetry sweep surfaces (error string, log pattern, metric name, monitor filter), spawn **one subagent per signal** that greps the mounted codebases under `{{CODEBASES_DIR}}` to find the `file:line` where that signal is emitted. Output: file path, surrounding function context, nearby conditions that trigger the emission. 5 signals → 5 parallel greps — this scales linearly and each one returns a sharp pin, not a vague area.
- **challenger** — attack the leading hypothesis. Its job is to name the single piece of evidence that would falsify the leader and say whether it's been checked.

**Why codebase-grep matters.** Knowing *where* a signal is emitted lets you:
- verify mechanistic fit (does a candidate PR's diff actually touch this `file:line`?)
- understand *what conditions* trigger the emission (look at the enclosing `if` / `match` / error-handling block)
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

**Steelman alternatives.** For each non-leading candidate, write one sentence: *"what evidence would I need to see to promote this to the leading hypothesis?"* If any of those sentences describes a probe you haven't run yet AND it's cheap, run it before committing to the current leader.

### 7. Evidence-gap gate (loop or publish)

Before locking a verdict, run this check on the leading hypothesis:

1. **Evidence breadth.** Does it have ≥ 2 independent evidence types (e.g. `tsuga_logs` + `tsuga_aggregation`, or `tsuga_aggregation` + `gh_pr`)? A single-source confirmation is too fragile for `confirmed`.
2. **Strongest falsifier.** Name the single piece of evidence that would most cleanly disprove it. Have you checked for it?
3. **Alternative closure.** For the second-ranked hypothesis: do you have a specific signal that rules it out, or are you just deprioritizing by gut feel?
4. **Literal signal check.** Re-read the raw verbatim error / metric shape / log pattern. Does its literal wording contradict your leading hypothesis? If the error says "expected a sequence" and your hypothesis doesn't explain why the payload was a map, the literal signal is pointing somewhere you haven't looked — restart from the literal reading.
5. **Codebase pin.** For the leading hypothesis, do you have a `file:line` where the observed signal is emitted (from the codebase-grep branch)? If not, spawn that grep now — it's cheap and usually decisive.

If any answer is no AND the missing check is cheap (one more `aggregation`, `logs patterns`, or codebase grep), **loop back to the relevant branch for that specific query** before assigning the verdict. Don't run a second full sweep — run one targeted probe.

If the missing check is expensive or the signal is genuinely unreachable, state that explicitly in `Open unknowns` and downgrade verdict to `most likely` or `insufficient evidence`.

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

## Branch: telemetry sweep

**Subagent scope:** if you were spawned as a telemetry-sweep subagent, this section + its Procedure + Branch output + Branch guardrails is everything you need. You don't synthesize a verdict; you surface facts + verbatim signals for codebase-grep + a completeness-check report.

Read-only evidence gathering from Tsuga. This branch does not declare root cause on its own — it produces facts the orchestrator synthesizes.

### Inputs

Time window, scope hint (service / cluster / env / customer / monitor), reported symptom. Missing scope → return only the discovery steps needed to resolve it.

### Procedure

1. **Monitor anchor (if the case cites a monitor).** `tsuga monitors get <monitor-id>` FIRST. Read the monitor's filter, aggregation, threshold, and groupBy — this IS the exact telemetry shape that crossed. Re-run the same query against the incident window AND a control window (same weekday + hour, 7 days earlier). Record the crossed value, the control value, and the ratio.
2. **Normalize scope.** `tsuga services list|get`. Capture canonical name, env, team, versions, sources, 24h log/trace counts.
3. **Normalize session.** Check `tsuga defaults`. Always set explicit `--from`, `--to`, `--max-results`. For `tsuga aggregation`, convert windows to epoch seconds.
4. **Load tech knowledge.** If scope names a known tech (Postgres, Redis, Kafka, …), load the matching `$knowledge-technology` reference to target the sweep.
5. **Config-threshold preflight (capacity-shaped symptoms).** If the reported symptom is capacity-shaped — queue lag, `CrashLoopBackOff`, `OOMKilled`, throttling, "too many", "insufficient" — spend one probe asking *"is there a single config knob that would fix this?"* before any elaborate change-correlation. Grep mounted codebases / helm / Pulumi for patterns like `*BatchSize`, `*PoolSize`, `*Concurrency`, `*MaxConnections`, `*FailureThreshold`, `*InFlightBatches`, `*MemPoolSize` scoped to the affected service.
6. **Evidence sweep.** Prefer in order:
   - `logs new-error-patterns` / `logs error-pattern-increases` (when team scope exists)
   - `logs patterns` to cluster failure shapes
   - `logs search` only after pattern discovery
   - `traces search` for exact failing spans
   - `aggregation scalar|timeseries` for counts, rates, comparisons
   - `monitors list|get` for signal semantics (not live truth)
   - `dashboards list|get` / `quality-reports list` as supporting context only
7. **Compare.** Bad window vs good control window. Affected entity vs sibling healthy entity when possible.
8. **Surface verbatim signals for codebase-grep.** As the sweep produces error strings, log patterns, metric names, and monitor filters, emit them as a distinct list at the end of the output — one per line. The orchestrator will spawn a codebase-grep subagent per entry to pin each signal to its emitting `file:line`. Do not try to explain what a signal *means* until its emitting code is found.
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

### No-data honesty

A metric or log pattern being absent is NOT equivalent to its value being zero. Causes of absence include receiver scope / permission issues, feature not enabled, instrumentation gap, or scrape failure.

When you checked and found nothing, say which: `(absent)` — did not appear in window `|` `(not instrumented)` — scope lacks the receiver `|` `(denied)` — permission error `|` `(empty)` — query ran, returned 0 rows. Never report silent absence as "metric is zero" in a Validated claim.

### Branch output

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

### Branch guardrails

- `metrics list|get` is metadata. Use `aggregation` for values.
- Monitor definitions are clues, not live truth.
- Do not claim deploy or config causality from Tsuga alone.
- Exact counts and windows > prose summaries.
- Stop at `symptom diagnosis only` when you can't tie the subsystem to a trigger.

More detail on `tsuga` command patterns: [references/tsuga-rules.md](./references/tsuga-rules.md).

## Branch: change correlation

**Subagent scope:** if you were spawned as a change-correlation subagent, this section is yours. Don't assign verdicts or synthesize root causes — produce the change timeline + candidate classifications (`mechanism_confirmed` / `mechanism_plausible` / `area_only` / `ruled_out`) for the orchestrator.

Answer: what changed, was it deployed, and could it plausibly cause the symptom?

### Inputs

- incident window
- at least one repo slug or local repo path. The container mounts its codebases at `{{CODEBASES_DIR}}/` — check there first for subdirectories (each is a git repo you can inspect with `git log`, `git diff`, `git blame`).

### Time-bound rule (hard)

**Nothing past `declared_at` is admissible.** Restrict every `git log`, `git show`, and `gh pr` call to strictly-before the incident start. Every shell you run in this branch must include the time bound:

- `git log --until="$DECLARED_AT" ...`
- `git log --before="$DECLARED_AT" ...`
- `gh pr list --search "merged:<$DECLARED_AT"`

A post-incident PR titled "Fix <exact symptom>" is the answer key leaking backward — do not use it, do not quote it, do not let it validate your leader. If you see one anyway (because a broad query returned it), drop it and rerun with the `--until` bound. Violating this invalidates the verdict.

### Procedure

1. **Map repos.** Case manifest > local paths > git remotes. Prioritize repos containing the affected service, cluster config, or incident hint.
2. **Collect the emitting `file:line` pins from codebase-grep.** The orchestrator spawns codebase-grep subagents for every verbatim signal in the telemetry output. Their results (one `file:line` per signal) are your highest-leverage inputs — each tells you exactly which source file a PR would need to touch to be a real candidate.
3. **Local git first — time-bounded.** Commits strictly before `declared_at`, files changed in config / helm / infra / auth / feature-flag / routing paths. Dirty working tree = not a safe proxy for the incident window. For each `file:line` from step 2, run `git log -L <line>,<line>:<file> --until=<declared_at>` to see which commits modified that specific line before the incident started.
4. **Then `$gh` — time-bounded.** Workflow runs, merged PRs, releases, commits, deployments with `merged:<<declared_at>` / `created:<<declared_at>` filters. A PR is a candidate only when it merged BEFORE `declared_at` AND a deploy completed between its merge and the incident start.
5. **Mechanism fit** per candidate — the strict version:
   - Does the PR's diff touch the `file:line` that emits the observed signal? **If no → not a candidate**, regardless of timing.
   - If yes: does the diff change the *condition that triggers emission* or the *value being emitted*? Quote the relevant lines.
   - Does the timing align (merge → deploy → incident start)?
   - Is there a faster revert or verification step?
6. **Classify each candidate** as one of:
   - `mechanism_confirmed` — diff → emitter → observation traces cleanly.
   - `mechanism_plausible` — diff touches nearby code that could plausibly affect the observation; not directly on the emitter line.
   - `area_only` — diff is in the right repo / service but doesn't touch the emitter.
   - `ruled_out` — wrong surface or wrong timing.

### Branch output

```
Most relevant changes:
  - <PR/SHA/tag> [evidence: gh_pr | gh_run | gh_release | gh_api | local_git]
    emitting signal: "<verbatim error/metric>"
    emitting file:line: <path>:<line>
    diff touches emitter line?: yes | no
    classification: mechanism_confirmed | mechanism_plausible | area_only | ruled_out
Strongest causal candidate:
  <change> — timestamp | artifact | surface | deploy status (deployed | merged only) | trace: diff→emitter→observation
Changes ruled out:
  - <change> — why it doesn't fit (wrong file, wrong surface, wrong timing, not deployed)
Best verification or rollback step:
  <concrete command or action>
```

Deploy status unknown? Say so explicitly and lower candidate confidence.
`area_only` classification? Say so explicitly — don't promote to "strongest candidate" without a mechanism trace.

### No-data fallback

If no repos are mounted (`ENABLE_CODEBASES=0`, no paths given) AND `$gh` is unavailable or returns nothing useful:

Return exactly:
```
Most relevant changes: (none — no repo / gh access)
Strongest causal candidate: (unavailable)
Best verification or rollback step: Operator should check deploy timestamps and config-change audit out-of-band.
```

Do not infer changes from telemetry alone. Do not cite PRs / SHAs / file paths that were not actually retrieved.

### Branch guardrails

- `merged` ≠ `deployed`.
- No blame without a traced mechanism: `diff → emitter → observation`. "Area match" is not a mechanism.
- Current checkout ≠ incident-window state.
- File paths, SHAs, PR numbers, run URLs over vague prose.
- Never skip codebase-grep. If the orchestrator didn't spawn it, spawn it yourself for the signals you're trying to explain before proposing a PR candidate.

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

Remediation:
  Stop the bleeding: <fastest restore action, or (none needed)>
  Likely root fix: <durable fix>
  Verify before acting: <confirm fix addresses root cause, not symptom>

Open unknowns:
- <what you couldn't answer + what would unblock it>
```

## Evidence rules

- Every `Validated claim` carries an `[evidence: <source>]` tag from the allowed list.
- Quote exact counts / timestamps / error strings / identifiers. Write `1247 errors`, not `thousands of errors`.
- Domain knowledge INTERPRETS evidence; it does not SUPPLY it. If telemetry is missing, name the signal.
- Never cite file paths / SHAs / line numbers that did not appear in branch output.
- `tsuga_monitors` is a clue about signal semantics, not live incident truth.

## Guardrails

- Classify task before triage.
- Ask `what changed?` early.
- Human hints before ambient telemetry noise.
- Separate symptom / subsystem / trigger.
- Preserve uncertainty when evidence is thin.
- `merged` ≠ `deployed`. `subsystem` ≠ `root cause`. `symptom` ≠ `trigger`.
- **Raw signal overrides analogue.** When a prior-incident analogue suggests a cause but the current case's literal error string / metric shape contradicts it, trust the literal signal. Same bug class ≠ same bug instance.
- **Every verbatim signal gets a codebase pin** before it feeds into change-correlation. No pin → don't blame a PR yet.

## References

Load when needed:
- [references/case-manifest.md](./references/case-manifest.md) — JSON shape for structured case input
- [references/playbooks/](./references/playbooks/) — domain disambiguation guides
- [references/tsuga-rules.md](./references/tsuga-rules.md) — `tsuga` command patterns for the telemetry branch
