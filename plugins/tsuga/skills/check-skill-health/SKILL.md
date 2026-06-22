---
name: check-skill-health
description: "Use when linting Tsuga skill bundles after editing runtime skills, generated incident-history or knowledge-company archives, or skill references; use when checking frontmatter, SKILL.md length, forbidden Tsuga CLI patterns, cross-links, required sections, generated dossier structure, sampled read-only command shape, local reference validation, release readiness, or whether a skill tree is ready for review."
---
<!-- skill-lint: allow-forbidden-examples — this file documents the forbidden patterns as teaching examples -->

# check-skill-health

Automated health checks for the runtime skill bundles. Catches the mechanical violations so a human reviewer can focus on judgment-call issues (narrative quality, genuinely useful examples).

## Quick start

```bash
# Lint every skill found in the standard locations
${CLAUDE_PLUGIN_ROOT}/skills/check-skill-health/scripts/lint-all.sh

# Lint a specific skill dir
${CLAUDE_PLUGIN_ROOT}/skills/check-skill-health/scripts/lint-all.sh /Users/me/proj/skills/knowledge-company

# Include sampled command safety audit; this does not execute commands
${CLAUDE_PLUGIN_ROOT}/skills/check-skill-health/scripts/lint-all.sh --execute
```

## What it checks

Automated (pass/warn/fail):

- **Frontmatter** — `name:` and `description:` fields present; description 50–120 words (warn outside, fail outside 30–200).
- **SKILL.md length** — body ≤ 500 lines (warn at 400, fail at 500).
- **References depth** — warn if references/ has paths > 1 level deep (with an exemption for `knowledge-company`'s hierarchical teams/services taxonomy).
- **Bundle size** — fail at 15 MB.
- **Forbidden tokens** — MCP-tool pseudo-syntax (`search-logs`, `aggregate-timeseries`, `query=`, …), `rtk` prefix, wrong singular resource verbs (`tsuga monitor get`), `tsuga spans search`.
- **`incident-history` structure** — every INC-* folder has metadata.json + SUMMARY.md with canonical sections; `_inventory.csv` row count matches folder count.
- **`knowledge-company` structure** — top-level COMPANY_*.md present; every team dir has TEAM_KNOWLEDGE.md; every service dir has SERVICE_KNOWLEDGE.md with canonical sections.
- **Cross-links** — every file path referenced from SKILL.md resolves.

Opt-in (`--execute`):

- **Sampled command safety audit** — pick up to 5 SERVICE_KNOWLEDGE.md files, extract the first `tsuga` command from each, and verify it is a single read-only command with no shell metacharacters. It does not run the commands.

## What it does NOT check

Judgment-call rules (see [`references/CHECKLIST.md`](references/CHECKLIST.md) for the human-review rubric):

- "Is the description optimized for triggering?" — depends on downstream retrieval behavior.
- "Is this skill narrow enough?" — subjective scope question.
- "Are the examples genuinely useful?" — requires reading.
- "Would a real responder find this actionable?" — requires testing on real tasks.

A passing lint is necessary, not sufficient.

## Layout

```
check-skill-health/
├── SKILL.md                         ← this file
├── scripts/
│   ├── lint-all.sh                  ← orchestrator, runs every check
│   ├── check-frontmatter.sh         ← universal
│   ├── check-skill-length.sh        ← universal
│   ├── check-forbidden-tokens.sh    ← Tsuga-specific (MCP-pseudo-syntax + rtk + singular verbs)
│   ├── check-incident-history.sh    ← skill-specific (INC-*/SUMMARY.md + metadata.json)
│   ├── check-knowledge-company.sh   ← skill-specific (teams/services/ structure + canonical sections)
│   └── sample-execute-commands.sh   ← opt-in command safety audit; does not execute
└── references/
    ├── CHECKLIST.md                 ← the human-review rubric (non-automatable rules)
    └── RULES.md                     ← why each check exists + how to fix a violation
```

## Exit codes

- `0` — all checks PASS or WARN; no FAILs.
- `1` — at least one FAIL.
- `2` — script error (bad argument, missing file, etc.).

## Extending

Each script is standalone and can be dropped into another skill's lint flow. Shared argument contract: first arg is the skill directory, optional `--quiet` flag suppresses PASS lines.

## Related Skills / Next Steps

- `build-incident-history` - regenerate incident-history archives before checking them.
- `build-knowledge-company` - regenerate knowledge-company archives before checking them.
- `tsuga-cli` - validate command syntax and resource names when a lint failure cites CLI shape.

## Limitations

- Passing lint is not proof that a skill works under pressure; still review the workflow and run pressure scenarios.
- `--execute` is a historical flag name. It audits sampled command shape only and must not run live Tsuga queries.
- Generated archives can contain company-specific context; summarize findings and avoid reproducing sensitive values.
