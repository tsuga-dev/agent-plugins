# Tsuga CLI Fallbacks

Use this file when direct trace lookup, trace-tree reconstruction, or targeted trace ID searches are weak, failing, or incomplete.

## Fallback Sequence

1. Start with grouped span-name aggregation for the service and time window.
2. Run targeted span searches by:
   - service name
   - suspicious span name
   - span kind
3. Reconstruct likely relationships from:
   - dominant span names
   - direction
   - dependency metadata
   - repeated parent/server naming patterns
4. Use repo/code inspection only to confirm likely source or fix location, not to invent trace evidence.

## Alternative Query Patterns

Use grouped inventory to answer:
- what span names dominate?
- are the suspicious spans common or isolated?
- are the names high-cardinality or low-information?

Use targeted searches to answer:
- are these spans `client`, `server`, or `internal`?
- what dependency/framework metadata is present?
- are there matching upstream/downstream pairs?

## How To Label Inferred Conclusions

If a conclusion comes from clean CLI evidence:
- label `source: tsuga CLI`

If a conclusion comes from code inspection:
- label `source: code analysis`

If the tree is incomplete and you infer the most likely explanation:
- label `source: inferred from partial trace evidence`

Do not hide inference behind definitive language.

## Confidence Language

Use wording like:
- "verified" when the trace structure directly supports the finding
- "likely" when the pattern matches but some structure is inferred
- "possible" when the evidence is weak and code inspection is still required

## Combining CLI and Code Evidence

Allowed pattern:
- Tsuga shows the symptom class
- code analysis identifies the likely source or shared fix location

Not allowed pattern:
- code structure alone is used to claim a trace symptom that Tsuga did not show

## When To Escalate Limitations

Explicitly note limitations when:
- trace ID search returns errors or incomplete results
- the tree view is partial
- the service has mixed instrumentation layers and Tsuga cannot identify the source layer alone

State what is observed, what is inferred, and what would require code inspection.
