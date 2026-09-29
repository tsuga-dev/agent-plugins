# LESSONS — the failure modes that ruin an incident archive

Read before running the procedure, and re-read before each subagent batch. Each entry is a rule a subagent breaks unless told not to.

## Command-shape mistakes

Every command a subagent writes into `## Diagnostic path` must be runnable `tsuga` CLI: no MCP-tool pseudo-syntax, no `rtk` prefix, plural resource names, `tsuga traces search` rather than `spans`, `--max-results` on telemetry searches and `--limit` only on the paginated resource lists.

The translation table, the aggregation body rules and the forbidden-token grep live in **`${CLAUDE_PLUGIN_ROOT}/skills/build-knowledge-company/references/CLI_TRANSLATION.md`**. That is the contract; do not restate it here and do not let a subagent work without it. `check-skill-health`'s `scripts/check-forbidden-tokens.sh` enforces it mechanically.

Flags a template cannot get from that file, because they are what `--help` prints: `tsuga logs search` and `tsuga traces search` take `--from`, `--to`, `--query`, `--max-results`; `tsuga aggregation scalar|timeseries` take only `-f`/`-d`/`--generate-skeleton`, so the time range lives in the JSON body.

## Content mistakes

### Empty inputs stay empty

If an incident's `tsuga/commands.txt` is missing or empty, the subagent must not invent a plausible-looking Diagnostic path. It writes the "no command log captured" note and a `## Confidence` section instead — the exact wording is in `SUBAGENT_PROMPT.md`.

An honest empty section beats hallucinated probes: the retrieval layer filters low-confidence entries out of analogue search, and it cannot filter confident fiction.

### Invented headings

`SUMMARY_TEMPLATE.md` fixes the section list. Subagents improvise otherwise, coining names like "Post-mortem debrief" or "Hot-take". If a section has no content, write one line ("None — no monitors paged during this incident") and keep the heading.

### Paraphrased Slack quotes

Analogue search depends on a reader recognizing a familiar phrase — "RDS failover started", "cannot find namespace", a specific customer name. Preserve the original wording. If the thread says "Alex ran the reconcile", it does not become "the on-call engineer triggered a reconcile".

### Post-incident PR content

An investigation runtime evaluated under a time-bound cheat-prevention block forbids the agent from reading PRs dated at or after `declared_at`. Pasting the resolution PR's diff, title or body into Root cause poisons those evaluation runs. Reference the PR number plus a one-line description. The responder's observations during the incident are fine; post-facto PR text is not.

### Service-name collisions

One service can carry two names in telemetry: the K8s-scraped workload name (`app-order-ingest`) and the OTel self-reported `OTEL_SERVICE_NAME` (`ingest`). A probe that matches only one form sees half the traffic. Use the OR idiom:

```bash
tsuga logs search --query "(context.service.name:app-order-ingest OR context.service.name:ingest) level:ERROR" --from=-1h --to now --max-results 100
```

If the responder's original probe used one form and missed a subset because of it, say so in that probe's `Finding:` line — it is the most common source of "we could not see half the problem".

### Engine roles are not first-party services

`indexer`, `searcher`, `metastore` and similar role names come from an embedded search/storage engine, not from a first-party service. They appear as `context.service.name:<role>` with a `tech` tag naming the engine. When an incident narrative uses one, spell out the role/service distinction or readers conflate them.

## Process mistakes

### Subagent self-reports are not evidence

"Fixed, 0 matches" means the subagent believes its own grep returned zero. Open 5–10 output files and check by eye:

- Does the Diagnostic path read as plausible probes, or as generic boilerplate?
- Do the cited monitor IDs and metric names exist? Run `tsuga monitors get <id>` on one at random.
- Is the narrative inside the template's length budget, or 80 lines of fluff?
