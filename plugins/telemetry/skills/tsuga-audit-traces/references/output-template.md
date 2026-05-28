# Trace Audit Output Template

Use this schema for the final response.

## Header

```text
## Trace Shape Audit: <service> (<from> → <to>)
tracesCount24h: <N> | Unique span names: <N> | Spans inspected: <N>
```

## Resource Identity

Include:
- `service.name`
- `service.version`
- `telemetry.sdk.name`

If resource identity is incomplete, say so explicitly before findings.

## Trace Interpretation

Use this section when the trace crosses services.

Include:
- upstream server span
- downstream client span
- downstream server span
- any suspicious child/internal spans under the downstream service

Purpose:
- prevent users from misreading downstream internal child spans as duplicate requests or broken propagation

## Findings Table

Use one row per finding.

| Span class | Span pattern | Direction | Likely source | Correctness status | Recommended action | Recommended fix location | Scope of impact | Evidence source |
|---|---|---|---|---|---|---|---|---|

## Recommended Actions

Use a short numbered list. Each item must:
- name the fix
- say where it likely lives
- state whether the recommendation is verified or inferred

## Limitations

Always include:
- whether trace reconstruction was complete or partial
- whether code inspection was performed
- whether conclusions were inferred from grouped evidence rather than a clean trace tree

## Wording Rules

- Separate evidence from interpretation.
- Do not say "broken" unless correctness is actually broken.
- Use "valid but noisy" for readability problems.
- Use "uncertain, requires code inspection" when Tsuga alone cannot locate the fix surface.
- Be explicit about scope:
  - one route
  - one service
  - all services using shared bootstrap/helper

## Confidence Labeling

Confidence can be expressed inline in prose. Suggested language:
- high confidence
- medium confidence
- lower confidence due to incomplete trace reconstruction
