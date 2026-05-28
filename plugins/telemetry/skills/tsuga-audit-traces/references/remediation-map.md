# Remediation Map

Use this file after classification. It maps span problem classes to likely fix paths.

| Finding class | Likely source | Recommended action | Recommended fix location | Scope of impact | Next inspection target |
|---|---|---|---|---|---|
| ASGI send/receive noise | Framework auto-instrumentation | Suppress if low-value and trace readability suffers | Framework instrumentation config | Usually service-specific, unless shared bootstrap wraps all apps the same way | Python/FastAPI or ASGI setup |
| Method-only outbound HTTP client spans | Library default instrumentation or shared helper | Improve outbound client span naming | Shared HTTP client instrumentation or helper | Often multi-service if the client wrapper is shared | Shared client bootstrap / reqwest-tracing setup |
| `pg.connect` / `pg-pool.connect` noise | Library default DB instrumentation | Suppress if query spans already provide enough visibility | Shared DB instrumentation config | All services using the same DB instrumentation setup | OTel bootstrap / DB instrumentation config |
| Custom wrapper span like `db.connect-tenant` | Local manual instrumentation or shared helper | Delete unless it measures real work or adds meaningful semantics | Helper/manual instrumentation site | Local if route-specific; broader if shared helper | Wrapper helper or local span creation code |
| Fastify hook spans like `onRequest`, `onSend`, `onResponse` | Framework auto-instrumentation or overlap | Filter/suppress if they dominate and add no request-level insight | Framework instrumentation config or overlap cleanup | All services using the same Fastify bootstrap if shared | Fastify setup, shared plugin registration, overlapping instrumentation |
| High-cardinality span name | Local manual naming or bad templates | Rename to low-cardinality template and move dynamic values to attributes | Manual span construction or framework route naming config | Usually local, sometimes shared route helper | Span builder / route registration |
| Broken parent-child linkage | Missing/incorrect propagation | Route to propagation debugging | Cross-service transport boundary | Potentially broad if shared transport/client setup is wrong | `tsuga-debug-missing-trace-propagation` |

## Specific Guidance Notes

### Python ASGI Noise

If the service is Python/FastAPI/ASGI and `http receive` / `http send` spans are valid but low-value, recommend:

```python
exclude_spans=["receive", "send"]
```

Use this only when the spans are clearly framework-generated child spans and are not providing meaningful debugging value.

### Rust Outbound HTTP Naming

If outbound client spans are named only by method and metadata points to shared `reqwest` instrumentation defaults, recommend inspecting shared span-builder/naming code rather than patching individual call sites first.

### DB Connect Noise

If connect spans are frequent and query spans already show useful DB work, recommend checking instrumentation settings and preferring connection-span suppression for general-purpose tracing.

### Custom Wrapper Spans

Delete custom wrapper spans only when they fail the low-value rubric. Keep them if they:
- mark an important business boundary
- carry meaningful attributes
- improve interpretation of the trace tree

### Fix Location Rule

Always say where the fix likely lives:
- shared bootstrap
- shared helper
- framework config
- local route/helper code
- transport propagation boundary

Do not stop at "this looks noisy."
