# Resource Attributes — Go OTel SDK

> **Last verified:** 2026-03-23 | SDK v1.42.0, semconv v1.27.0

Resource attributes identify the origin of telemetry. They are set once at SDK initialization and do NOT change per-operation. This file covers what to set, how to set it in Go, and how to audit what Tsuga actually sees.

---

## Required and Recommended Attributes

| Attribute | Priority | How set in Go |
|---|---|---|
| `service.name` | **Required** | `semconv.ServiceName("my-service")` or `OTEL_SERVICE_NAME` env |
| `service.version` | Strongly recommended | `semconv.ServiceVersion("1.0.0")` or `OTEL_RESOURCE_ATTRIBUTES` |
| `service.namespace` | Optional | `semconv.ServiceNamespace("payments")` |
| `service.instance.id` | Recommended | SDK auto-generates or set explicitly |
| `telemetry.sdk.name` | Auto (SDK sets) | `opentelemetry` — absence = SDK init gap |
| `telemetry.sdk.language` | Auto (SDK sets) | `go` |
| `telemetry.sdk.version` | Auto (SDK sets) | SDK version string |
| `deployment.environment.name` | Strongly recommended | `semconv.DeploymentEnvironmentName("production")` |
| `process.pid`, `process.runtime.*` | Recommended | Requires `resource.WithProcess()` option — NOT included by `resource.Default()` |
| `host.name`, `host.arch` | Recommended | Requires `resource.WithHost()` option — NOT included by `resource.Default()` |
| `k8s.pod.name`, `k8s.namespace.name`, `k8s.node.name` | Auto (K8s detector) | Requires `k8sresource` detector; see note below |
| `cloud.provider`, `cloud.region` | Auto (cloud detector) | Requires cloud-specific detector package |

> **Deprecated:** `deployment.environment` (without `.name`) was deprecated in OTel semconv 1.27.0. Use `deployment.environment.name` in all new and updated instrumentation.

> **K8s and cloud detectors:** `resource.Default()` does not include K8s or cloud attrs automatically. Add them via `go.opentelemetry.io/contrib/detectors/aws/ec2`, `go.opentelemetry.io/contrib/detectors/gcp`, or the K8s downward API. For K8s pod/namespace injection via env vars, see `otel-instrumentation` → `references/k8s-deployment.md`.

---

## Resolve resource attribute values

Before writing any code, determine the correct values. Start with Step 1 and stop at the first match.

### service.name

| Step | Where to look | How |
|---|---|---|
| 1a | `OTEL_SERVICE_NAME` already set | Search Dockerfile, docker-compose.yml, .env, k8s manifests, Makefile for `OTEL_SERVICE_NAME` — if found, **stop**; the value is already correct |
| 1b | Other service name env var | Search the same files for any env var whose name suggests a service identity — common patterns: `SERVICE_NAME`, `APP_NAME`, `APPLICATION_NAME`, `SVC_NAME`, or anything matching `*_NAME`, `*_SERVICE`, `*_APP` — if found, use its value as `OTEL_SERVICE_NAME` |
| 2 | Language manifest | `go.mod` module path — use the last segment (e.g. `github.com/acme/order-service` → `order-service`) |
| 3 | Directory name | Use the service directory name as fallback |

> **Step 1b:** The found variable holds the right value but the OTel SDK only reads `OTEL_SERVICE_NAME`. Set `OTEL_SERVICE_NAME=<value-of-found-var>` in the same launch context — do not rename the existing variable.

> **Multi-service projects:** Each service must have a distinct `OTEL_SERVICE_NAME`. In a monorepo, run step 2 per service directory — never reuse the same name across services.

**Format:** Convert to kebab-case — `OrderService` → `order-service`, `user_api` → `user-api`. Never embed environment in the name (`my-app-production` → BAD; use `deployment.environment.name` separately).

**Where to set it** — use whatever launch mechanism the project already has:

| Project has | Where to add it |
|---|---|
| `Dockerfile` | `ENV OTEL_SERVICE_NAME=<name>` |
| `docker-compose.yml` | under `environment:` |
| Kubernetes manifest | under `env:` in container spec |
| Shell script / Makefile | prepend to the run command |
| None of the above | inline: `OTEL_SERVICE_NAME=<name> <start-command>` |

### service.version

Resolve at build/deploy time — never hardcode in application source.
Priority: CI/CD version variable (`GITHUB_SHA`, `CI_COMMIT_TAG`) → `git describe --tags --always` (no standard manifest version field in Go).

### deployment.environment.name

Priority: existing OTel config → `APP_ENV` or `ENVIRONMENT` → Kubernetes namespace name.

---

## Setting Attributes Programmatically

```go
import (
    "go.opentelemetry.io/otel/sdk/resource"
    semconv "go.opentelemetry.io/otel/semconv/v1.27.0"
)

// GOOD: resource.Merge(resource.Default(), ...) — inherits SDK-detected attrs
// resource.Default() includes: telemetry.sdk.*, service.name=unknown_service, env var detector
// For host/process attrs, use resource.New(ctx, resource.WithHost(), resource.WithProcess()) and merge
res, err := resource.Merge(
    resource.Default(),
    resource.NewWithAttributes(
        semconv.SchemaURL,
        semconv.ServiceName("my-service"),         // overrides unknown_service default
        semconv.ServiceVersion("1.2.3"),
        semconv.DeploymentEnvironmentNameKey.String("production"),
    ),
)

// BAD: resource.New() without resource.Default() loses telemetry.sdk.* attrs
res, err := resource.New(ctx,
    resource.WithFromEnv(),   // misses telemetry.sdk.* auto-detectors
)
```

---

## Setting Attributes via Environment Variables

Prefer env vars for deployment-time configuration so service identity can change without a code deploy:

```bash
OTEL_SERVICE_NAME=my-service                              # sets service.name
OTEL_RESOURCE_ATTRIBUTES=service.version=1.2.3,deployment.environment.name=production,service.namespace=payments
```

> `resource.Default()` reads `OTEL_SERVICE_NAME` and `OTEL_RESOURCE_ATTRIBUTES` automatically. No code change needed to update these values.

**Priority:** Env var `OTEL_SERVICE_NAME` overrides `semconv.ServiceName(...)` set in code when both are present.

---

## Audit Workflow

Run this 3-step audit to confirm what Tsuga actually sees for a service.

### Step 1 — Sample spans for resource attributes

```bash
tsuga spans search --query "context.service.name:<your-service>" --max-results 3
```

Examine `resourceAttributes` in the returned spans. Note which attributes are present, absent, or use the deprecated `deployment.environment` key (without `.name`).

### Step 2 — Check required attributes

For each sampled span, verify:

| Check | Pass | Fail |
|---|---|---|
| `service.name` present | ✅ | ❌ Critical — spans not queryable by service |
| `service.version` present | ✅ | ⚠️ Add to SDK init or env |
| `deployment.environment.name` present | ✅ | ⚠️ Add to SDK init or env |
| `telemetry.sdk.name` = `opentelemetry` | ✅ | ⚠️ SDK may not be initialized |
| `deployment.environment` key present (no `.name`) | ❌ Deprecated | Rename to `.name` |

### Step 3 — Supplemental check via logs

If `resourceAttributes` is empty on sampled spans (can happen with gateway/infra spans):

```bash
tsuga logs search --query "context.service.name:<your-service>" --max-results 3
```

Examine `context.*` fields — they reflect the same OTel resource attributes: `context.service.name`, `context.service.version`, `context.telemetry.sdk.name`, `context.deployment.environment.name`.

---

## Fix Patterns

### Missing service.name

Set `OTEL_SERVICE_NAME` in the launch environment — see **Resolve resource attribute values** above to determine the correct value and where to set it.

### Missing service.version

```go
semconv.ServiceVersion("1.2.3")
// or: OTEL_RESOURCE_ATTRIBUTES=service.version=1.2.3
```

### Deprecated deployment.environment → deployment.environment.name

```go
// BAD
attribute.String("deployment.environment", "production")

// GOOD
semconv.DeploymentEnvironmentNameKey.String("production")
// which sets key: deployment.environment.name
```

### Missing telemetry.sdk.* (auto-attrs not present)

Root cause: either `resource.Default()` is not used, or SDK init is missing entirely. Verify:

1. `resource.Default()` is called (or `resource.Merge(resource.Default(), ...)`)
2. `otel.SetTracerProvider(tp)` is called before any `otel.Tracer()` calls
3. The `res` variable is passed to `sdktrace.WithResource(res)` and `sdkmetric.WithResource(res)`

---

## Mutation Gate

Before applying any code change to SDK init:

1. Show the proposed diff with a brief explanation
2. Wait for explicit user confirmation ("yes" / "no")
3. Apply only after confirmation

After deploy: `tsuga spans search --query "context.service.name:<your-service>"` and verify `resourceAttributes` contains the updated keys.
