<!-- skill-lint: allow-forbidden-examples — this prompt enumerates forbidden patterns for the agent to avoid -->

# RECOMMENDED_PROMPT — ready-to-paste prompt for bootstrapping knowledge-company

Copy the block below verbatim into Claude (or Codex) when you're ready to bootstrap or refresh the `knowledge-company` skill. Substitute the `<…>` placeholders before pasting.

**Important:** `incident-history` must be built first. `knowledge-company`'s service dossiers cross-link to prior incidents, and the service-scoring step in Phase 3 uses incident references as one of the ranking signals.

---

## Prompt to paste

```
You are bootstrapping the runtime `knowledge-company` skill for this repository. Follow both skills below end-to-end in a single session. Do not declare done until the health check passes.

Repo root: <absolute path to your investigation-agent checkout, e.g. /Users/me/projects/my-investigation-agent>
Codebase checkouts: <absolute dir holding the company's main code repos locally, e.g. /Users/me/projects/my-investigation-agent/repos or /Users/me/dev/acme-co>
  Expected children: one subdir per backing repo, e.g. typescript/, rust/, python/, infra-as-code/
Optional raw docs: <absolute path to architecture / team charters / runbooks, e.g. /Users/me/projects/my-investigation-agent/inputs/raw-docs>
Tsuga CLI: must be authenticated (run `tsuga config` to confirm).
Tsuga MCP tools: must be available to your subagents for live discovery + live probes.

Preconditions — verify before touching anything:
1. `skills/incident-history/` is already built and non-empty (≥1 INC-* folder with SUMMARY.md). If not, run `$build-incident-history` first — see its RECOMMENDED_PROMPT.md. `knowledge-company` cross-links to incidents; don't fake that dependency.
2. `tsuga teams list`, `tsuga services list`, `tsuga monitors list`, `tsuga dashboards list` all return non-empty results. If any are empty, fix CLI auth.
3. `tsuga aggregation scalar -f <q>` works end-to-end. Test with a trivial count query before fanning out.

Phase 1 — build:
Use the `$build-knowledge-company` skill. Specifically:
1. Read `${CLAUDE_PLUGIN_ROOT}/skills/build-knowledge-company/SKILL.md` and every file under `${CLAUDE_PLUGIN_ROOT}/skills/build-knowledge-company/references/`.
2. Execute the phases in `PROCEDURE.md` in order. Do NOT skip Phase 0 (access check), Phase 3 (service scoring — derive the list from live data, don't hardcode it), Phase 4 (per-service helper extraction into `/tmp/service-data/<svc>/`), or Phase 8 (verification).
3. Phases 5 (top-level docs) and 6 (per-team dossiers) — YOU write these directly, not subagents. They need cross-team visibility.
4. Phase 7 — fan out one subagent per service in `/tmp/services-to-dossier.txt`. Batches of 8–12 in parallel. Prompt template is in `SUBAGENT_PROMPT.md`; copy verbatim, substitute `{svc}`, `{team}`, `{team_id}`, `{company}`, `{N}`.
5. Each subagent must: read the service template + CLI translation + lessons docs, run the 4 live probes named in `SUBAGENT_PROMPT.md`, then write the dossier and run its own verification grep before declaring done.

Phase 2 — health check:
Use the `$check-skill-health` skill. Specifically:
1. Run `${CLAUDE_PLUGIN_ROOT}/skills/check-skill-health/scripts/lint-all.sh skills/knowledge-company/` (structural checks, offline).
2. Then run with live execution: `${CLAUDE_PLUGIN_ROOT}/skills/check-skill-health/scripts/lint-all.sh --execute skills/knowledge-company/` (samples 5 random SERVICE_KNOWLEDGE.md files and runs the first `tsuga` command from each against prod telemetry).
3. If any FAIL: do NOT hand-edit the affected file. Fix the root cause in the template / subagent prompt / lessons doc, regenerate the affected services via subagent, re-run both lint passes. Iterate until `lint-all.sh --execute` returns exit code 0.
4. WARNs are informational — read them, decide whether to fix or annotate.

Phase 3 — report:
Return a concise summary:
- Service count dossiered + team count + byte size of the output tree.
- Any lint failures and what you did about them.
- Any services whose helper inputs (`/tmp/service-data/<svc>/{monitors,dashboards}.json` + incident-files.txt) were empty at collect time — these should have explicit low-confidence notes. List them.
- Any live-data vs task-brief discrepancies you documented in service Confidence notes.
- The commit (or staged diff).

Hard rules for the whole flow:
- Every `tsuga` command must be real CLI. Forbidden: MCP-tool pseudo-syntax (`search-logs`, `aggregate-*`, `query=`, `from=-`, `limit=`), `rtk` prefix, singular resource verbs (`tsuga monitor get` — it's `tsuga monitors get`), `tsuga spans search` (it's `tsuga traces search`), `--limit` (it's `--max-results`). Full translation contract in `${CLAUDE_PLUGIN_ROOT}/skills/build-knowledge-company/references/CLI_TRANSLATION.md`.
- Live data overrides the task brief. If the brief says service X does foo and live logs show it does bar, trust the logs and document the discrepancy in the service's Confidence note.
- No duplication from top-level docs. Pointers only.
- No invented metric names, monitor IDs, dashboard IDs. Ground everything in `tsuga metrics list` / `tsuga monitors list` / `tsuga dashboards list` output.
- `RAW_TELEMETRY_KNOWLEDGE.md` must NOT exist in the output tree — its content is folded into `COMPANY_TELEMETRY_KNOWLEDGE.md`. If you find yourself creating it, stop.
- Do not touch `skills/incident-history/` or any other skill.
- If the taxonomy discovery in Phase 3 surfaces <15 or >60 services, STOP and ask — the scoring rule is probably wrong for this deployment.
```

---

## Where to put local data

Live-probe inputs come from the Tsuga CLI directly — no file drops needed for the core flow. The optional inputs are:

1. **Codebase checkouts.** Ideally have local clones of the relevant GitHub repos so subagents can grep code paths when filling in Upstream/downstream + Log-shape sections. Path: any absolute dir, passed in the prompt. A worked layout is a single parent directory with one subdir per backing-language repo (e.g. `typescript/`, `rust/`, `python/`, `infra-as-code/`).
2. **`inputs/raw-docs/`** at the repo root — architecture notes, team charters, runbooks. Only if the top-level COMPANY_GENERAL_KNOWLEDGE.md can't be written from `tsuga teams list` + ambient knowledge alone. Not committed; add to `.gitignore`.
3. **`inputs/codebase-repos.json`** — authoritative repo → team mapping, if you want to override what the `context.team` telemetry tag infers. Shape is documented in `references/INPUT_LAYOUT.md`.

If none of 2–3 exist, the skill still builds — Phase 5 synthesizes the top-level docs from live discovery. The result is thinner but correct.

## Operator notes

- **First bootstrap** with ~30 services in parallel takes 60–90 minutes. The long pole is individual subagent latency, not aggregate compute.
- **Refresh** — if only a few services changed, pass a filtered `/tmp/services-to-dossier.txt` (e.g., `grep '^web-' /tmp/services-to-dossier.txt > /tmp/to-rebuild.txt`) to regenerate only those.
- **CLI version bump** — if the `tsuga` CLI changes syntax, re-run with `--execute` will catch the drift. Fix `CLI_TRANSLATION.md`, regenerate all services.
- **Rate limits** — subagent batches of 8–12 is the sweet spot for the MCP tier. Narrower wastes wall-clock; wider risks 429s.
