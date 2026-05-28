---
name: tsuga-audit-traces
description: "Use when asked to review trace quality, check span naming, audit instrumentation correctness, explain noisy or suspicious-looking spans, or improve trace readability for a service."
---

# Tsuga: Audit Traces

> **Requires live Tsuga connection.** This skill audits what Tsuga is actually receiving. For code-only review, see `otel-<lang>/references/audit-checklist.md`.

## Trigger

Use this skill when the user asks things like:
- "Are my spans named correctly?"
- "Review trace quality for service X"
- "Why do these spans look wrong?"
- "Are these duplicate requests or just instrumentation noise?"
- "Why do I see `http receive` / `http send` spans?"
- "Why are all my client spans just `GET` and `POST`?"

## Required Inputs

- **Service name** (required — ask if missing)
- **Time window** (optional; default: `-1h`)

## Routing Rule

Treat this skill as a thin router plus reporting contract.

Always load these references first:
- `references/workflow.md`
- `references/core-checks.md`
- `references/classification.md`
- `references/heuristics.md`

Load these references when needed:
- `references/remediation-map.md` when a pattern is classified and a fix path is needed
- `references/casebook.md` when a known recurring pattern seems to match
- `references/tsuga-cli-fallbacks.md` when direct trace lookup or clean tree reconstruction is weak/incomplete
- `references/output-template.md` before writing the final audit

## Core Workflow

1. Inventory the service's spans and resource identity using the workflow reference.
2. Classify the issue before diagnosing it:
   - span class
   - direction
   - likely source
   - correctness status
3. Distinguish:
   - verified bug
   - valid but noisy instrumentation
   - uncertain, requires code inspection
4. Load the matching remediation and case references only after classification.
5. Produce a structured finding with evidence source, fix surface, scope of impact, and confidence.

## Decision Rules

- Do not treat every odd-looking child span as a propagation bug.
- Do not treat every bad span name as high-cardinality naming; low-information names are a separate problem class.
- Do not recommend removal purely because a span is short or `0ms`.
- Do not conclude duplicate instrumentation without evidence.
- If parent/child linkage is actually broken, route to `tsuga-debug-missing-trace-propagation`.

## Evidence Requirements

- Label every finding as one of:
  - `source: tsuga CLI`
  - `source: code analysis`
  - `source: inferred from partial trace evidence`
- Separate observed evidence from interpretation.
- When trace reconstruction is incomplete, say so explicitly and use the fallback reference.
- Do not present a remediation path until the span/noise class is identified.

## Output Contract

The final audit must use the schema in `references/output-template.md`.

Every finding must include:
- Span class
- Direction
- Likely source
- Correctness status
- Recommended action
- Recommended fix location
- Scope of impact
- Evidence source

## Safety Rules

- Inspect span attribute names, not raw values.
- Never reproduce raw span attribute values in output.
- If `context.sensitive == "true"` appears in any record: note it and stop field-level inspection.
- Advisory only — propose changes, do not apply them.
- Validate existing instrumentation shape before claiming something is missing or duplicated.

## Related Skills / Next Steps

- `tsuga-debug-missing-trace-propagation` — if parent/child linkage is broken
- `otel-<lang>/references/audit-checklist.md` — code-side audit of span construction and status handling
- `otel-<lang>` — language-specific remediation patterns once the fix surface is known
- `tsuga-analyze-trace-latency` — if the trace problem is latency rather than quality/readability
