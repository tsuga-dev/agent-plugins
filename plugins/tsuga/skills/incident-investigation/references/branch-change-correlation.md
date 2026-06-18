# Branch: change correlation

You were spawned as a change-correlation subagent — this file is yours. Don't assign verdicts or synthesize root causes — produce the change timeline + candidate classifications (`mechanism_confirmed` / `mechanism_plausible` / `area_only` / `ruled_out`) for the orchestrator.

Answer: what changed, was it deployed, and could it plausibly cause the symptom?

## Inputs

- incident window
- at least one repo slug or local repo path. The container mounts its codebases at `{{CODEBASES_DIR}}/` — check there first for subdirectories (each is a git repo you can inspect with `git log`, `git diff`, `git blame`).

## Time-bound rule (hard)

**Nothing past `declared_at` is admissible.** Restrict every `git log`, `git show`, and `gh pr` call to strictly-before the incident start. Every shell you run in this branch must include the time bound:

- `git log --until="$DECLARED_AT" ...`
- `git log --before="$DECLARED_AT" ...`
- `gh pr list --search "merged:<$DECLARED_AT"`

A post-incident PR titled "Fix <exact symptom>" is the answer key leaking backward — do not use it, do not quote it, do not let it validate your leader. If you see one anyway (because a broad query returned it), drop it and rerun with the `--until` bound. Violating this invalidates the verdict.

## Procedure

1. **Map repos.** Case manifest > local paths > git remotes. Prioritize repos containing the affected service, cluster config, or incident hint.
2. **Collect the emitting `file:line` pins from codebase-grep.** The orchestrator spawns codebase-grep subagents for every verbatim signal in the telemetry output. Their results (one `file:line` per signal) are your highest-leverage inputs — each tells you exactly which source file a PR would need to touch to be a real candidate.
3. **Local git first — time-bounded.** Commits strictly before `declared_at`, files changed in config / helm / infra / auth / feature-flag / routing paths. Dirty working tree = not a safe proxy for the incident window. For each `file:line` from step 2, run `git log -L <line>,<line>:<file> --until=<declared_at>` to see which commits modified that specific line before the incident started.
4. **Then `$gh` — time-bounded.** Workflow runs, merged PRs, releases, commits, deployments with `merged:<<declared_at>` / `created:<<declared_at>` filters. A PR is a candidate only when it merged BEFORE `declared_at` AND a deploy completed between its merge and the incident start.
5. **Mechanism fit** per candidate — the strict version:
   - Does the PR's diff touch the `file:line` that emits the observed signal? **If no → not a candidate**, regardless of timing.
   - If yes: does the diff change the _condition that triggers emission_ or the _value being emitted_? Quote the relevant lines.
   - Does the timing align (merge → deploy → incident start)?
   - Is there a faster revert or verification step?
6. **Classify each candidate** as one of:
   - `mechanism_confirmed` — diff → emitter → observation traces cleanly.
   - `mechanism_plausible` — diff touches nearby code that could plausibly affect the observation; not directly on the emitter line.
   - `area_only` — diff is in the right repo / service but doesn't touch the emitter.
   - `ruled_out` — wrong surface or wrong timing.

## Branch output

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

## No-data fallback

If no repos are mounted (`ENABLE_CODEBASES=0`, no paths given) AND `$gh` is unavailable or returns nothing useful:

Return exactly:

```
Most relevant changes: (none — no repo / gh access)
Strongest causal candidate: (unavailable)
Best verification or rollback step: Operator should check deploy timestamps and config-change audit out-of-band.
```

Do not infer changes from telemetry alone. Do not cite PRs / SHAs / file paths that were not actually retrieved.

## Branch guardrails

- `merged` ≠ `deployed`.
- No blame without a traced mechanism: `diff → emitter → observation`. "Area match" is not a mechanism.
- Current checkout ≠ incident-window state.
- File paths, SHAs, PR numbers, run URLs over vague prose.
- Never skip codebase-grep. If the orchestrator didn't spawn it, spawn it yourself for the signals you're trying to explain before proposing a PR candidate.
