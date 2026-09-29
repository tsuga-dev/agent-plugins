---
name: otel-collector
description: "Writes, reviews and debugs OpenTelemetry Collector configuration, enforcing processor ordering, receiver exposure and OTTL correctness, and gating every config change behind confirmation. Use when Collector YAML, Helm values, Kubernetes manifests, existing Collectors, OTLP exporters, receiver binding or exposure, pipeline topology, processors, OTTL expressions, transform, filter or routing processors, redaction, enrichment, batching, memory limiting, structured log parsing, Collector-to-Tsuga export problems, configuration review, rollout planning, or telemetry missing after a Collector rollout need attention. For application SDK code use otel-instrumentation instead."
---

# OTel Collector

Use this skill for Collector YAML, Helm values, pipeline topology, processors, receivers, exporters, deployment shape, Collector debugging, and OTTL transform/filter/routing/redaction work. Runtime docs are authoritative for component syntax, processor order, and Tsuga-specific config.

## Runtime Docs Lookup

For docs lookup rationale and docs-error behavior, follow `tsuga-cli`; examples omit `--rationale` for brevity.

Fetch the relevant docs before writing or reviewing Collector config:

| Need | Fetch |
|---|---|
| Deployment model, config validation command | `tsuga docs get data-collection/forward-to-tsuga/deploy-opentelemetry-collector` |
| Existing Collectors | `tsuga docs get data-collection/forward-to-tsuga/existing-collectors` |
| Component choice, processor order, connectors, stateful routing, container/file log parsing and `trace_id` promotion | `tsuga docs get data-collection/guides/collector-pipelines` |
| Receiver exposure, `memory_limiter`, batch/queue/retry sizing, scaling, Collector self-telemetry | `tsuga docs get data-collection/guides/how-to-operate-an-opentelemetry-collector` |
| Kubernetes chart | `tsuga docs get integrations/kubernetes/index` |
| OTLP export to Tsuga | `tsuga docs get data-collection/forward-to-tsuga/configure-otlp-export` |
| Resource attributes | `tsuga docs get data-collection/guides/how-to-add-resource-attributes` |
| OTel field mapping | `tsuga docs get data-collection/guides/default-mapping-for-opentelemetry-formats` |
| OTTL `transform`/`filter`, per-signal redaction rules | `tsuga docs get data-collection/guides/how-to-transform-and-redact-telemetry` |
| Shared masking policy with the `redaction` processor | `tsuga docs get data-collection/guides/how-to-use-the-opentelemetry-redaction-processor` |
| Missing telemetry | `tsuga docs get data-collection/guides/how-to-troubleshoot-missing-telemetry` |
| Validate arrival | `tsuga docs get data-collection/guides/how-to-validate-telemetry-arrival-in-tsuga` |

If the exact path is unclear:

```bash
tsuga docs search "OpenTelemetry Collector <topic>"
```

If docs are unavailable, stop and report the setup blocker. Do not invent Collector or OTTL syntax from memory.

## Mutation Gate

Before generating, editing, or writing Collector YAML, Helm values, Kubernetes manifests, config snippets, or source files:

1. Show the proposed diff or config block and the reason for it.
2. Wait for explicit confirmation (`yes`, `no`, or selected changes).
3. Apply only after confirmation.

Remote Kubernetes, Tsuga, customer, or prospect environment changes require a separate explicit approval and the exact command before execution.

## Source Reading Safety

`tsuga-cli` Safety covers CLI output handling and sensitive services. When reading config or source, add:

- Never read `.env`, `*.secret`, `*credentials*`, or `*token*`; if encountered, flag and stop.
- Never reproduce ingestion keys, operation keys, API keys, account IDs, tokens, or endpoint URLs found in config or source.
- Label findings as `source: code analysis`, `source: config review`, or `source: tsuga CLI`.

## Config Authoring Rules

Processor order, the `memory_limiter` position, receiver binding, and batch/queue sizing are stated on the pipelines and operating pages above. Follow those pages rather than a remembered order.

- Component types are snake_case. Take the exact spelling from the docs page or the component's `metadata.yaml` `type:`, never from its directory name in collector-contrib.
- Never write a real ingestion key, operation key, token, or account ID into a config. Use environment variables such as `${TSUGA_INGESTION_KEY}`, or a platform secret.
- Validate with `otelcol-contrib validate --config <file>`. `validate` only knows the components compiled into that binary, so run it with the distribution that is deployed. The Collector has no dry-run flag.
- On the Kubernetes chart the config lives inside the `OpenTelemetryCollector` resources, so `helm template` is the check: the render fails on a bad value or a collector image below the chart's floor. `validate` cannot read the rendered manifest — extract the collector config from it first if you want to run it.
- Print validation and rollout commands for an operator to run. This skill must not execute non-`tsuga` commands.

## OTTL Guardrails

The transform and redact page above states the `where ... != nil` guard, `error_mode: ignore`, and the rule against inventing attribute names. Beyond it:

- OTTL uses `nil`, not `null`.
- OTTL has no assignment operator. Every statement is a function call: `set()`, `delete_key()`, `replace_pattern()`, `keep_keys()`.
- Prefer exact equality over regex. Regex costs more per record and is easier to get subtly wrong.

## Output Template

```markdown
## Summary
## Evidence Used
## Signals / Findings
## Proposed Config
## Placement
## Verification
## Recommended Actions
## Limitations
```

## Related Skills / Next Steps

- `otel-instrumentation` - application SDK setup before traffic reaches the Collector.
- `signal-choice-advisor` - signal choice, semantic convention naming, and cardinality checks.
- `tsuga-debug-telemetry-ingestion` - verify arrival after Collector rollout or debug missing data.

## Limitations

- Collector and OTTL syntax are version-dependent; runtime docs and component READMEs are authoritative.
- This skill does not execute remote rollout commands without explicit approval.
