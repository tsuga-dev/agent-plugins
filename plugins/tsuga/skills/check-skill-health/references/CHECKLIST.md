# CHECKLIST — human review rubric (the rules a script can't enforce)

The `scripts/` in this skill catch every mechanical violation. Before shipping a skill, also walk through this checklist by eye. Each item is a judgment call — no script can substitute.

## Trigger quality (rule 1)

- [ ] Does the description name the specific service / data shape / task the skill should fire on, not just a topic?
- [ ] Would an agent reading the description know _when_ to pick this skill over a similar one?
- [ ] Are there concrete trigger words (service names, error patterns, tool mentions) an agent can match against?

**Failure pattern:** generic description like "helps investigate Tsuga problems". Fix: add 3–5 specific triggers ("service name like `api-gateway`, `data-intake`, `bridge` appears", "a P1 monitor fires on the monitoring pipeline").

## Scope (rule 4)

- [ ] Does this skill do one job with one output shape?
- [ ] Is anything here that would be easier to factor out into a sibling skill?
- [ ] If the skill is large, is it because the domain requires it (e.g., per-service dossiers), or because it's sprawling?

**Failure pattern:** one skill covering "investigation + knowledge + cli driving + history". Split into four.

## Scripts vs prose (rule 6)

- [ ] Is anything in the skill body describing step-by-step deterministic work that would be more reliable as a script?
- [ ] Are there `bash` code blocks the reader is expected to run verbatim? Those should live in `scripts/`, not inline.
- [ ] Is any validation / transform / packaging done in prose? Move to a script.

**Failure pattern:** 20 lines of "do A, then do B, then do C, then verify D". Fix: `scripts/do-all.sh` + a one-line prose mention.

## Imperative instructions (rule 9)

- [ ] Do the action-section verbs start with imperatives ("Read", "Extract", "Validate") not descriptions ("The agent should read…")?
- [ ] Are conditional branches crisp ("If X, do Y") not vague ("When necessary, consider Y")?

**Failure pattern:** passive voice. Fix: rewrite as direct commands.

## Guardrails (rule 11)

- [ ] What does the skill say to do when required input is missing?
- [ ] What if a connector (MCP, CLI, API) is unavailable?
- [ ] What if the confidence is low? Does the skill tell the agent to stop and ask, or does it let it invent?
- [ ] What does "done" look like? Is there an explicit exit condition?

**Failure pattern:** no mention of failure modes. Fix: add a "When this fails" section enumerating 3–5 common breakages.

## Examples over prose (rule 12)

- [ ] Count the examples — is there at least one per major operation the skill describes?
- [ ] Are the examples concrete (real input, real output shape) or abstract ("something like …")?
- [ ] If the skill produces structured output, is there a minimal sample showing the exact format?

**Failure pattern:** long paragraphs explaining format rules. Fix: add a 10-line sample.

## Tested on real prompts (rule 13)

- [ ] Has this skill been run end-to-end on at least 3 real tasks?
- [ ] Did the agent pick it up correctly from the description alone?
- [ ] Were any of the references unused (dead weight)?
- [ ] Were any of the references missed when they should've been loaded (progressive-loading failure)?

**Failure pattern:** shipping without dogfooding. Fix: run it against 3 representative inputs, iterate.

## Narrative coherence (our addition — not in the 15 rules)

- [ ] Read the top-level SKILL.md cover-to-cover. Does the layout + when-to-read-what + shell-commands flow sensibly?
- [ ] Pick 3 random reference files. Do they explain why they exist, not just what they contain?
- [ ] Pick 3 random SERVICE_KNOWLEDGE.md (if applicable). Do they read like they were written with the live service in front of the author, or like generic templates?

**Failure pattern:** "valid-looking but vacuous" content. Fix: regenerate the affected subagent batch with tightened prompt.

## Cross-skill hygiene

- [ ] Does this skill link its boundary with sibling skills (`$knowledge-technology`, `$incident-history`, etc.)?
- [ ] Does it duplicate content from sibling skills? Replace with pointer.
- [ ] Are the paths in cross-references correct? (The scripts catch broken file refs; this is about *semantic* appropriateness of the pointer.)

## After a red pass

If any item in this checklist fails, fix the root cause in the skill's templates, don't hand-patch individual files. Regenerate. This keeps the skill reproducible.
