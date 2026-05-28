# Resource Attributes — Python OTel

> **Last verified:** 2026-03-23 | SDK: `opentelemetry-sdk` 1.40.0

Resource attributes identify the origin of telemetry. They are set once at SDK init and attached to every span, metric, and log record. They do NOT change per-operation.

---

## Required and recommended attributes

| Attribute | Required | Example | Notes |
|-----------|----------|---------|-------|
| `service.name` | **Yes** | `"web-backend"` | Must be unique per service |
| `service.version` | Strongly recommended | `"1.4.2"` | Enables version-scoped queries |
| `service.namespace` | Optional | `"payments"` | Groups related services |
| `deployment.environment.name` | Strongly recommended | `"production"` | See deprecation note |
| `telemetry.sdk.name` | Auto-set by SDK | `"opentelemetry"` | Do not set manually |
| `telemetry.sdk.version` | Auto-set by SDK | `"1.40.0"` | Do not set manually |

> **Deprecated:** `deployment.environment` (without `.name`) is deprecated as of OTel semconv v1.27.0. Use `deployment.environment.name` in all new instrumentation.

---

## Resolve resource attribute values

Before writing any code, determine the correct values. Start with Step 1 and stop at the first match.

### service.name

| Step | Where to look | How |
|---|---|---|
| 1a | `OTEL_SERVICE_NAME` already set | Search Dockerfile, docker-compose.yml, .env, k8s manifests, Makefile for `OTEL_SERVICE_NAME` — if found, **stop**; the value is already correct |
| 1b | Other service name env var | Search the same files for any env var whose name suggests a service identity — common patterns: `SERVICE_NAME`, `APP_NAME`, `APPLICATION_NAME`, `SVC_NAME`, or anything matching `*_NAME`, `*_SERVICE`, `*_APP` — if found, use its value as `OTEL_SERVICE_NAME` |
| 2 | Language manifest | `pyproject.toml` `[project] name` or `[tool.poetry] name` (fallback: `setup.py`) |
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
Priority: CI/CD version variable (`GITHUB_SHA`, `CI_COMMIT_TAG`) → `pyproject.toml` `[project] version` → `git describe --tags --always`.

### deployment.environment.name

Priority: existing OTel config → `DJANGO_ENV`, `FLASK_ENV`, or `APP_ENV` → Kubernetes namespace name.

---

## Python idiom: `Resource.create()` (zero-arg, preferred)

`Resource.create()` without arguments automatically merges:
- `OTEL_SERVICE_NAME` env var → `service.name` attribute
- `OTEL_RESOURCE_ATTRIBUTES` env var → all listed attributes
- SDK-auto-populated attributes (`telemetry.sdk.*`, `process.*`)

```python
# BEST — driven entirely by environment; no code change needed at deploy time
resource = Resource.create()
```

```python
# ACCEPTABLE — code-defined defaults, env vars take precedence on conflict
# Use this only when you want in-code fallbacks that can be overridden at deploy
resource = Resource.create({"service.name": "web-backend", "service.version": "1.0.0"})
```

### Recommended env var configuration

```bash
OTEL_SERVICE_NAME=web-backend
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=production,service.version=1.4.2,service.namespace=payments
```

---

## `Resource.merge()` for composing multiple resource objects

```python
from opentelemetry.sdk.resources import Resource

base = Resource.create()
k8s_resource = Resource({
    "k8s.namespace.name": os.environ.get("K8S_NAMESPACE", ""),
    "k8s.pod.name": os.environ.get("K8S_POD_NAME", ""),
})
resource = base.merge(k8s_resource)
```

In `a.merge(b)`, the argument (`b`) attributes take precedence over the receiver (`a`) when both define the same key. `Resource.create()` already detects many attributes via built-in detectors; only use `Resource.merge()` when you need attributes from sources not covered by `OTEL_RESOURCE_ATTRIBUTES`.

---

## Kubernetes downward API injection

Inject pod identity at deploy time — no code change needed:

```yaml
# Deployment spec
env:
  - name: OTEL_SERVICE_NAME
    value: "web-backend"
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "deployment.environment.name=production,service.version=1.4.2"
  - name: K8S_POD_NAME
    valueFrom:
      fieldRef:
        fieldPath: metadata.name
  - name: K8S_NAMESPACE
    valueFrom:
      fieldRef:
        fieldPath: metadata.namespace
```

---

## Audit workflow

### Step 1 — Check what resource attributes arrive in Tsuga

```bash
tsuga spans search --query "context.service.name:my-service" --max-results 1
# Examine: service.name, service.version, deployment.environment.name
```

### Step 2 — Check required attributes

```bash
# Confirm service.name is set
tsuga spans search --query "context.service.name:my-service" --max-results 1

# Confirm deployment.environment.name is set (not the deprecated deployment.environment)
tsuga spans search --query "context.service.name:my-service deployment.environment.name:*" --max-results 1
```

### Step 3 — Check log correlation

```bash
tsuga logs search --query "context.service.name:my-service" --max-results 3
# Confirm service.name appears in log resource context
```

---

## Fix patterns

| Gap | Fix |
|-----|-----|
| `service.name` missing | Set `OTEL_SERVICE_NAME=my-service` |
| `service.name` hardcoded in code | Switch to `Resource.create()` (zero-arg) + `OTEL_SERVICE_NAME` |
| `deployment.environment.name` missing | Add to `OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=production` |
| Using deprecated `deployment.environment` | Replace with `deployment.environment.name` |
| `service.version` missing | Add `service.version=1.4.2` to `OTEL_RESOURCE_ATTRIBUTES` |
| Resource attributes differ between traces/metrics/logs | Ensure all providers use the same `resource = Resource.create()` instance |

---

## Mutation gate

Before modifying resource attribute configuration:

1. Show the proposed env var or code change
2. Confirm which environment (dev/staging/prod) will be affected
3. Wait for explicit user confirmation
4. Apply only after confirmation
