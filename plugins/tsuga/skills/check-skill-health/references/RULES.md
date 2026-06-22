<!-- skill-lint: allow-forbidden-examples — this file documents the forbidden patterns as teaching examples -->

# RULES — why each automated check exists, and how to fix a violation

One entry per script. If a check fails, read the corresponding entry and fix the root cause — do not suppress the check.

## check-frontmatter.sh

**Checks:** `name:` field, `description:` field, description word count.

**Why:** the description is the *only* thing the agent sees at skill-selection time. Everything else in the skill is loaded after the selection decision has already been made. A vague description means the skill never fires.

**How to fix a FAIL:**
- Missing frontmatter → add `---` delimiters at top of SKILL.md with `name:` and `description:` fields.
- Description < 30 words → too thin to carry triggers. Add 3–5 concrete trigger phrases (service names, error patterns, tool mentions). Target 50–120 words.
- Description > 200 words → dumping procedure into the metadata. Move the how-to into the body; keep the description to _what_ and _when_.
- Description 30–50 or 120–200 words (WARN) → usable but tighten if trivial.

**Reference:** OpenAI's skill-authoring guidance says the description is used for discovery and should be explicit about triggers, ~100 words.

## check-skill-length.sh

**Checks:**
- SKILL.md body ≤ 500 lines.
- references/ depth ≤ 1 level (exempt for `knowledge-company`'s teams/services taxonomy).
- Bundle size ≤ 15 MB.
- No "When to use" heading in the body.

**Why:** SKILL.md is loaded in full into context once the skill is selected. Every extra line in SKILL.md costs tokens on every invocation. Move long content to `references/`, which are loaded only when referenced.

**How to fix a FAIL:**
- Body > 500 lines → pull the bulk into `references/<topic>.md` and replace with a pointer in SKILL.md. Rule of thumb: if a section is > 40 lines, it belongs in a reference.
- Deep references → flatten. Prefer `references/topic.md` over `references/area/subarea/topic.md`. The `knowledge-company` skill's hierarchical `teams/<team>/services/<service>/` is a known exception because the taxonomy mirrors the telemetry data model; cross-links from SKILL.md still resolve in one step.
- Bundle > 15 MB → prune old references, remove committed-by-accident binaries (check with `find <skill> -size +1M`).
- "When to use" in body (WARN) → move the trigger logic to the frontmatter description. The body is loaded after selection; anything in it can't influence selection.

## check-forbidden-tokens.sh

**Checks:** 6 patterns that have bitten us before.

1. **MCP-tool verb prefixes** (`search-logs`, `aggregate-timeseries`, etc.) — these are not runnable `tsuga` CLI commands. Subagents with access to MCP tools write them naturally.
2. **MCP-tool argument shape** (`query=`, `from=-`, `to=now`, `limit=`, …) — same problem. The real CLI uses `--query`, `--from`, `--to`, `--max-results`.
3. **`rtk` prefix** — the RTK hook is transparent; writing `rtk tsuga …` in docs is noise.
4. **Singular resource verbs** (`tsuga monitor get` instead of `tsuga monitors get`). The CLI follows `tsuga <resources-plural> <verb>`.
5. **`tsuga spans search`** — no such command. It's `tsuga traces search`.
6. **`--limit`** — not a flag. It's `--max-results`.

**Why:** the single most expensive bug class in the first build. Subagents emit plausible-looking pseudo-CLI, the document looks right on review, and it breaks when a real user tries to copy-paste.

**How to fix a FAIL:** do NOT hand-edit the generated file. Go back to the subagent template / prompt, fix the rule, regenerate the affected files. Use the `build-knowledge-company` skill's CLI translation contract for the full command-shape rules.

## check-incident-history.sh

**Checks (only fires if target is an incident-history skill):**
- Every `INC-*/` has SUMMARY.md + metadata.json.
- Every metadata.json parses + has `incident_id`, `declared_at`, `last_iso`.
- Every SUMMARY.md has the canonical heading set (Incident at a glance, Timeline, Paging surface, Diagnostic path, Root cause, Remediation, Lessons).
- `_inventory.csv` row count == folder count.

**Why:**
- `entrypoint.sh` reads `metadata.json` to filter future incidents via `SNAPSHOT_AT - 20 min` cutoff. Missing required fields → the incident gets silently dropped.
- Retrieval depends on stable section names. Adding a section or renaming a heading breaks analogue search.
- The inventory is the quick-access index for the investigation runtime's retrieval. A stale row count means orphaned entries.

**How to fix a FAIL:** regenerate the specific INC-id via the `build-incident-history` skill. Don't hand-edit.

## check-knowledge-company.sh

**Checks (only fires if target is a knowledge-company skill):**
- Required top-level files present: `COMPANY_GENERAL_KNOWLEDGE.md`, `COMPANY_TELEMETRY_KNOWLEDGE.md`.
- `RAW_TELEMETRY_KNOWLEDGE.md` *not* present (folded into COMPANY_TELEMETRY after distillation).
- Every `teams/<team>/` has TEAM_KNOWLEDGE.md.
- Every `teams/<team>/services/<service>/` has SERVICE_KNOWLEDGE.md.
- SERVICE_KNOWLEDGE.md canonical sections present.
- TEAM_KNOWLEDGE.md basic sections present (warn only).
- File paths referenced from SKILL.md resolve (warn only).

**Why:** same logic — retrieval and cross-linking are section-name-stable. The "must not exist" check on RAW_TELEMETRY guards against regression — it used to be a separate file and was folded in during a distillation pass.

**How to fix a FAIL:** regenerate the affected service/team via the `build-knowledge-company` skill.

## sample-execute-commands.sh (opt-in)

**Checks:** picks up to N SERVICE_KNOWLEDGE.md files, extracts the first `tsuga` command from each, and verifies that each command is a single read-only `tsuga` command with no shell metacharacters.

**Why:** all the other checks are structural — they confirm the file *looks* right. This check catches generated dossiers that would ask an agent to run mutating commands, shell pipelines, redirects, or copied MCP pseudo-syntax.

**Why opt-in:** samples generated service dossiers and can fail archives that otherwise pass structural checks. It does not touch prod, require auth, or spend query quota.

**How to fix a FAIL:**
- Single file fails → regenerate that SERVICE_KNOWLEDGE.md.
- Multiple files fail with the same error shape → the template or CLI translation rules are wrong. Fix the template, regenerate the batch.
- If a live query check is needed, do it manually with explicit approval and a copied read-only command.

## When a WARN is acceptable

Warnings are informational. They may be fine in context:
- Description 120–200 words: OK if the skill genuinely needs extra trigger vocabulary (e.g., `knowledge-company` listing 10+ service names).
- SKILL.md body 400–500 lines: OK if the body is mostly layout + reference links and trimming would hurt clarity.
- Nested references dirs (outside of knowledge-company's exemption): evaluate case-by-case. If the nesting mirrors data structure (e.g., per-customer configs), it's usually fine.

WARN ≠ "ignore". It means "is this intentional? document why in a comment if so."
