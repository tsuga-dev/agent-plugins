# Skill Authoring Template

Copy this file to `<skill-name>/SKILL.md` and fill in each section. Remove all `[placeholder]` markers before merging.

---

```
---
name: [skill-name]
description: [One sentence. What does this skill do? When should an agent trigger it? Be specific about trigger conditions.]
---
```

---

# [Skill Name]

> **Last verified:** YYYY-MM-DD | <any relevant version or CLI reference>

## When to Trigger

[List 3–5 specific user requests or contexts that should activate this skill. Be narrow enough that unrelated questions don't trigger it.]

- [trigger example 1]
- [trigger example 2]

## Required Inputs

- **[Input name]** (required): [Description. What to do if missing: stop and ask, or list candidates.]
- **[Input name]** (optional, default: [value]): [Description.]

## Workflow

[Number each step. Use concrete `tsuga` commands with realistic flag values. State what to do with the output before proceeding to the next step.]

1. [Step 1: command + what to extract from output]
2. [Step 2: depends on output of step 1]
3. [Step 3: ...]

**Parallel steps:** [If steps 2, 3, 4 are independent, note that they can run in parallel.]

## Evidence Requirements

[Define what constitutes a valid finding. Use specific thresholds, not vague language.]

- "[Condition X]" = [specific value from specific command], not assumed from [other source]
- "[Condition Y]" requires ≥2 corroborating signals; single signal = "consistent with," not proof

## Output Template

```
## [Skill Name]: <subject> (<from> → <to>)

## Summary
<one line>

## [Signal Section]
| Column | Column |
|---|---|
| ... | ... |

## Findings
- <finding with evidence citation: command + value>

## Recommended Actions
1. <specific next step>

## Limitations
- <limitation 1>
- <limitation 2>
```

## Related Skills / Next Steps
<!-- 2-4 entries. Format: `skill-name` — one sentence description of when to use it -->
- `<skill-name>` — <when to hand off to this skill>

## Framework Variants
<!-- Language skills: list key framework-specific notes or point to references/frameworks.md -->
See `references/frameworks.md` for framework-specific setup (Express, FastAPI, Spring Boot, etc.)

## Safety Rules

[Inline the rules from `AGENTS.md` § Skill authoring rules that are most relevant to this skill. Repeat them here so the skill is self-contained.]

- [Rule relevant to this skill]
- Never [specific forbidden action for this skill]
