# Trace Audit Workflow

Use this file for the operational audit sequence. This is process, not taxonomy.

## Audit Sequence

1. Confirm the service exists and has trace volume.
   - `tsuga services list`
   - Inspect `tracesCount24h`
   - If `tracesCount24h == 0`: stop and say there is no trace data to audit

2. Inventory span names before interpreting any single span.
   - Use grouped span-name aggregation first
   - Goal: understand the dominant trace shape, not just one surprising example
   - Canonical query pattern:

```bash
tsuga aggregation scalar -d '{
  "timeRange": {"from": <unix_from>, "to": <unix_to>},
  "dataSource": "traces",
  "queries": [
    {
      "id": "q1",
      "aggregate": {"type": "count"},
      "filter": "context.service.name:<service>"
    }
  ],
  "groupBy": [{"fields": ["span.name"], "limit": 50}],
  "formula": "q1"
}'
```

3. Sample traces/spans for structure.
   - Inspect:
     - `resourceAttributes`
     - `span.kind`
     - `statusCode`
     - basic parent/child relationships if available
   - Canonical query pattern:

```bash
tsuga traces search --query "context.service.name:<service>" --from <window> --max-results 10
```

4. Run classification before remediation.
   - Load `core-checks.md`
   - Load `classification.md`
   - Load `heuristics.md`
   - Decide:
     - span class
     - direction
     - likely source
     - correctness status

5. Reconstruct multi-service flow when traces cross services.
   - Explicitly identify:
     - upstream server span
     - downstream client span
     - downstream server span
     - child internal/framework spans below the downstream server span
   - Do this before calling anything an orphan, duplicate request, or propagation problem

6. Decide whether code context is needed.
   - Stop and ask for code context only when:
     - the finding is high-impact
     - the CLI evidence is ambiguous
     - the remediation depends on shared vs local implementation details

7. Route to fallback workflow if the trace tree is incomplete.
   - Load `tsuga-cli-fallbacks.md`

8. Only after classification, load `remediation-map.md` and optionally `casebook.md`.

9. Shape the final answer with `output-template.md`.

## Minimum Required Queries

Run these query types unless the user has already provided equivalent evidence:

### Service presence

```bash
tsuga services list
```

### Span inventory by name

```bash
tsuga aggregation scalar -d '{
  "timeRange": {"from": <unix_from>, "to": <unix_to>},
  "dataSource": "traces",
  "queries": [
    {
      "id": "q1",
      "aggregate": {"type": "count"},
      "filter": "context.service.name:<service>"
    }
  ],
  "groupBy": [{"fields": ["span.name"], "limit": 50}],
  "formula": "q1"
}'
```

### Span inventory by kind

```bash
tsuga aggregation scalar -d '{
  "timeRange": {"from": <unix_from>, "to": <unix_to>},
  "dataSource": "traces",
  "queries": [
    {
      "id": "q1",
      "aggregate": {"type": "count"},
      "filter": "context.service.name:<service>"
    }
  ],
  "groupBy": [{"fields": ["span.kind"], "limit": 10}],
  "formula": "q1"
}'
```

### Trace/span sampling

```bash
tsuga traces search --query "context.service.name:<service>" --from <window> --max-results 10
```

### Log cross-check for error/status alignment

```bash
tsuga logs search --query "context.service.name:<service>" --from <window> --max-results 10
```

### Optional status-code aggregation

```bash
tsuga aggregation scalar -d '{
  "timeRange": {"from": <unix_from>, "to": <unix_to>},
  "dataSource": "traces",
  "queries": [
    {
      "id": "q1",
      "aggregate": {"type": "count"},
      "filter": "context.service.name:<service>"
    }
  ],
  "groupBy": [{"fields": ["status_code"], "limit": 10}],
  "formula": "q1"
}'
```

Use these as canonical examples. Adjust grouping fields or filters only when the audit question requires it.

## When To Use Grouped Inventory vs Direct Search

Use grouped span-name inventory first when:
- the user reports "weird spans"
- the noisy pattern may be high-volume
- direct trace lookup is unreliable
- you need to distinguish dominant patterns from one-off anomalies

Use direct trace/span search first when:
- the user gives a specific trace ID
- the user references one exact span pattern
- the service has low volume and grouped inventory is less informative

If direct trace lookup fails or looks incomplete, fall back to grouped inventory rather than guessing.

## When To Cross-Check Logs

Cross-check logs when:
- traces show suspiciously few `statusCode:error` spans
- the user reports failures that are not obvious in traces
- you need to distinguish missing status handling from a healthy trace with noisy internals

Do not claim missing error status from one span sample if a log cross-check is feasible.

## When To Reconstruct Multi-Service Flow

Reconstruct the flow when:
- the trace clearly crosses services
- the suspicious span could belong to a downstream service
- the user is worried about propagation, duplicate requests, or orphans

Do not treat a child span in the downstream service as evidence of a second request without verifying the client/server pair first.

## When To Route Out

Route to `tsuga-debug-missing-trace-propagation` only when evidence supports broken linkage:
- missing/incorrect parent-child linkage
- unrelated trace IDs for one logical request
- callee spans exist but do not connect correctly to caller spans

Do not route out for:
- framework hook spans
- ASGI send/receive spans
- method-only outbound client names
- other valid-but-noisy instrumentation patterns

## Minimum Evidence Before Final Output

Before concluding, you should have:
- service existence and trace presence
- span inventory
- at least one sampled structure check
- a classification
- an explicit evidence label for each finding
