---
name: tsuga-debug-no-data
description: "Use when signals are absent, OTLP export looks broken, the service isn't visible in Tsuga, or data was flowing and then stopped."
---

# Debug: No Data in Tsuga

> **Last verified:** 2026-03-21

## When to Use

"Why is no telemetry showing up?", "My traces aren't in Tsuga", "OTLP export is broken", "Service not found in Tsuga", "Metrics are missing after deploy", "I deployed the OTel SDK but nothing shows up"

## Required Inputs

- **Service name** (required — ask if missing)
- **Language/runtime** (required — ask if missing)
- **Which signals are missing** (optional; default: investigate all three)
- **Deployment type** (optional: container/k8s/serverless/local — affects endpoint config)

## Workflow

Documentation queries for Tsuga ingestion, endpoint, and validation behavior:

```bash
tsuga docs get data-collection/guides/how-to-troubleshoot-missing-telemetry
tsuga docs get data-collection/opentelemetry/configure-otlp-export
tsuga docs get account-and-settings/api-keys
```

### Step 1: Identify what is missing

```bash
tsuga services list
```

- If service not found at all → skip to Step 4 (endpoint/auth likely misconfigured)
- If found: note `logsCount24h`, `tracesCount24h`, and `sources[]`
- Classify: missing traces only / missing metrics only / missing logs only / all missing

### Step 2: Validate service.name resource attribute

```bash
tsuga spans search --query "context.service.name:<name>" --max-results 3
```

If no results but service is in the list: check `service.name` spelling. The attribute value must exactly match what is configured in OTEL_SERVICE_NAME or SDK resource.

### Step 3: Validate OTLP protocol and endpoint

Check:
- Is the endpoint using port 4317 (gRPC) or port 4318 (HTTP)?
- Is `OTEL_EXPORTER_OTLP_PROTOCOL` set explicitly? (default varies by SDK)
- Is `OTEL_EXPORTER_OTLP_ENDPOINT` set? (required for Tsuga)
- Is the Tsuga ingestion key header present?

**Common misconfigurations by signal:**

| Signal | Variable | Note |
|---|---|---|
| All | `OTEL_EXPORTER_OTLP_ENDPOINT` | Must be set; no default for Tsuga |
| All | `OTEL_EXPORTER_OTLP_HEADERS` | Must include `tsuga-ingestion-key=<key>` |
| All | `OTEL_EXPORTER_OTLP_PROTOCOL` | `grpc` for 4317, `http/protobuf` for 4318 |
| Traces only | `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | Overrides the base endpoint for traces |
| Metrics only | `OTEL_EXPORTER_OTLP_METRICS_ENDPOINT` | Overrides the base endpoint for metrics |
| Logs only | `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT` | Overrides the base endpoint for logs |

**Tsuga endpoint pattern:**
```bash
OTEL_EXPORTER_OTLP_ENDPOINT=https://ingest.<region>.tsuga.cloud:443
OTEL_EXPORTER_OTLP_HEADERS=tsuga-ingestion-key=<your-ingestion-key>
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
```

### Step 4: Check sampling configuration

If traces are missing but service is found:
```bash
tsuga spans search --query "context.service.name:<name>" --from -1h --max-results 3
```

Check: Is `OTEL_TRACES_SAMPLER` set to `always_off`? Is a custom sampler dropping all spans?

### Step 5: Check SDK shutdown / flush on SIGTERM

A common cause of missing spans: the process exits before the batch exporter flushes. Check:
- Is there a SIGTERM handler that calls SDK shutdown?
- In serverless environments: is the shutdown timeout sufficient?

Language-specific shutdown patterns: see `otel-<lang>` → `references/troubleshooting.md`

### Step 6: Check network / TLS / auth

For Tsuga cloud endpoints (HTTPS/443):
- Is TLS configured correctly? (gRPC exporters need secure channel for port 443)
- Is the ingestion key header correct? (header name: `tsuga-ingestion-key`)
- Is the service running in a network that can reach `ingest.<region>.tsuga.cloud`?

For local/dev (plaintext):
- gRPC exporters: endpoint should be `host:port` without scheme (e.g., `localhost:4317`)
- HTTP exporters: endpoint should include scheme (e.g., `http://localhost:4318`)

### Step 7: Run telemetry smoke test

```bash
# Use a wider window than default
tsuga logs search --query "context.service.name:<name>" --from -1h --max-results 5
tsuga spans search --query "context.service.name:<name>" --from -1h --max-results 5
```

If still nothing: see Step 8.

### Step 8: Route to language-specific troubleshooting

If all checks pass but data is still missing, load the language-specific troubleshooting guide:
- `otel-<lang>` → `references/troubleshooting.md`

Common language-specific issues:
- **Node.js**: SDK loaded after app code (auto-instrumentation misses patches)
- **Java**: Agent JAR not on classpath, JVM flag missing `-javaagent:`
- **Go**: gRPC endpoint specified with `http://` scheme (scheme not allowed for gRPC)
- **PHP**: Missing PSR-18 HTTP client (`php-http/guzzle7-adapter`)
- **Rust**: Missing `rt-tokio` feature on `opentelemetry_sdk`

## Evidence Requirements

- Service presence finding = `tsuga services list` result (service found / not found)
- Signal gap = `logsCount24h` / `tracesCount24h` values from `tsuga services get`
- Endpoint finding = user-provided env vars (ask user to share if not visible)
- Network finding = result of test span search with wider window

## Output Template

```
## Debug: No Data in Tsuga — <service>

## Signal Status
| Signal | Status | Evidence |
|---|---|---|
| Traces | ❌ Missing / ⚠️ Sparse / ✅ Present | <evidence> |
| Metrics | ❌ Missing / ⚠️ Sparse / ✅ Present | <evidence> |
| Logs | ❌ Missing / ⚠️ Sparse / ✅ Present | <evidence> |

## Most Likely Root Cause
<single most likely issue with reasoning>

## Diagnosis Steps Completed
1. ✅/❌ Service in registry
2. ✅/❌ service.name attribute valid
3. ✅/❌ OTLP endpoint configured
4. ✅/❌ Auth header present
5. ✅/❌ Sampling not blocking
6. ✅/❌ SDK shutdown configured
7. ✅/❌ Network accessible

## Recommended Fix
<specific actionable steps for the identified root cause>

## Next Step
Run `tsuga-smoke-test` for <service> after applying the fix to confirm signals arrive.

## Limitations
- Endpoint and auth configuration cannot be verified directly — the agent relies on user-provided env var values
- Network access from deployment environment cannot be tested from the CLI
- SDK version mismatches may require inspecting dependency manifests
```

## Safety Rules

- Never reproduce ingestion keys or auth tokens found in environment variable values
- Do not claim data "will" arrive — state that it "should" arrive after the fix and recommend smoke test verification
- If `context.sensitive == "true"` appears in any search result: stop field-level inspection
- Advisory only — this skill diagnoses and recommends; it does not modify configuration or source files

## Related Skills / Next Steps
- `tsuga-smoke-test` — run after applying the fix to verify signals arrive
- `otel-<lang>` → `references/troubleshooting.md` — language-specific deep troubleshooting
- `tsuga-debug-missing-trace-propagation` — if signals arrive but traces don't link across services
- `otel-instrumentation` — full cross-signal audit once signals are flowing (routes to per-lang `references/audit-checklist.md`)
