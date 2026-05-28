# Resource Attributes — Ruby OTel

> Last verified: 2026-03-23 | SDK: opentelemetry-sdk 1.10.0 / opentelemetry-exporter-otlp 0.32.0

## Required and Recommended Attributes

| Attribute | Required | Set via | Example |
|-----------|----------|---------|---------|
| `service.name` | **Yes** | `OTEL_SERVICE_NAME` env var (preferred) | `web-backend` |
| `service.version` | Strongly recommended | `OTEL_RESOURCE_ATTRIBUTES` or code | `1.4.2` |
| `service.namespace` | Optional | `OTEL_RESOURCE_ATTRIBUTES` or code | `payments` |
| `deployment.environment.name` | Strongly recommended | `OTEL_RESOURCE_ATTRIBUTES` | `production` |
| `telemetry.sdk.name` | Set by SDK | automatic | `opentelemetry` |
| `telemetry.sdk.version` | Set by SDK | automatic | `1.5.0` |

> **Deprecated:** `deployment.environment` (without `.name`) was deprecated in OTel semconv 1.27.0.
> Use `deployment.environment.name` in all new instrumentation. Queries using the old key will return no results in Tsuga.

## Resolve resource attribute values

Before writing any code, determine the correct values. Start with Step 1 and stop at the first match.

### service.name

| Step | Where to look | How |
|---|---|---|
| 1a | `OTEL_SERVICE_NAME` already set | Search Dockerfile, docker-compose.yml, .env, k8s manifests, Makefile for `OTEL_SERVICE_NAME` — if found, **stop**; the value is already correct |
| 1b | Other service name env var | Search the same files for any env var whose name suggests a service identity — common patterns: `SERVICE_NAME`, `APP_NAME`, `APPLICATION_NAME`, `SVC_NAME`, or anything matching `*_NAME`, `*_SERVICE`, `*_APP` — if found, use its value as `OTEL_SERVICE_NAME` |
| 2 | Language manifest | `*.gemspec` `spec.name` field |
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
Priority: CI/CD version variable (`GITHUB_SHA`, `CI_COMMIT_TAG`) → `*.gemspec` `spec.version` → `git describe --tags --always`.

### deployment.environment.name

Priority: existing OTel config → `RAILS_ENV` (Rails) or `APP_ENV` → Kubernetes namespace name.

---

## `Resource.create` — Reads Env Vars Automatically

The Ruby SDK reads `OTEL_SERVICE_NAME` and `OTEL_RESOURCE_ATTRIBUTES` automatically. Do not hardcode `service.name` in the configure block.

```ruby
# GOOD — reads OTEL_SERVICE_NAME from env; do NOT set c.service_name in code
OpenTelemetry::SDK.configure do |c|
  # service.version has no dedicated env var; set in code only if needed
  c.resource = OpenTelemetry::SDK::Resources::Resource.create(
    'service.version' => '1.0.0'
  )
  c.use_all
end

# BAD — service.name hardcoded; changing it requires a code deploy
OpenTelemetry::SDK.configure do |c|
  c.resource = OpenTelemetry::SDK::Resources::Resource.create(
    'service.name' => 'my-service'    # hardcoded — do not do this
  )
  c.use_all
end
```

## Environment Variable Configuration (Preferred)

```bash
# Set service.name — required
OTEL_SERVICE_NAME=web-backend

# Set additional resource attributes — deployment.environment.name is required
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=production,service.version=1.4.2,service.namespace=payments
```

Prefer env vars for deploy-time values — they can be changed without a code deploy and without rebuilding the container image.

## Kubernetes Downward API Injection

Inject pod identity as resource attributes via the Kubernetes downward API:

```yaml
# Deployment spec
env:
  - name: OTEL_SERVICE_NAME
    value: "web-backend"
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "deployment.environment.name=production,service.version=$(APP_VERSION)"
  - name: K8S_NODE_NAME
    valueFrom:
      fieldRef:
        fieldPath: spec.nodeName
  - name: K8S_POD_NAME
    valueFrom:
      fieldRef:
        fieldPath: metadata.name
  - name: K8S_NAMESPACE
    valueFrom:
      fieldRef:
        fieldPath: metadata.namespace
```

Then in your configure block:

```ruby
OpenTelemetry::SDK.configure do |c|
  k8s_attrs = {}
  k8s_attrs['k8s.node.name']      = ENV['K8S_NODE_NAME']      if ENV['K8S_NODE_NAME']
  k8s_attrs['k8s.pod.name']       = ENV['K8S_POD_NAME']       if ENV['K8S_POD_NAME']
  k8s_attrs['k8s.namespace.name'] = ENV['K8S_NAMESPACE']       if ENV['K8S_NAMESPACE']

  c.resource = OpenTelemetry::SDK::Resources::Resource.create(
    k8s_attrs.merge('service.version' => '1.0.0')
  )
  c.use_all
end
```

## Audit Workflow

**Step 1 — Check what service name is arriving in Tsuga:**

```bash
tsuga spans search --query "context.service.name:*" --max-results 10
```

**Step 2 — Check resource attributes on a span:**

```bash
tsuga spans search --query "context.service.name:<your-service>" --max-results 1
# Inspect output: service.version and deployment.environment.name present?
```

**Step 3 — Check the running service's env vars:**

```bash
# Kubernetes
kubectl exec -n <namespace> <pod> -- env | grep OTEL

# Docker
docker inspect <container> | grep -A20 '"Env"'
```

## Fix Patterns

| Finding | Fix |
|---------|-----|
| `service.name = unknown_service` | Set `OTEL_SERVICE_NAME` env var |
| `service.name` hardcoded via `c.resource` | Move to `OTEL_SERVICE_NAME`; remove from configure block |
| `deployment.environment` (old key) | Replace with `deployment.environment.name` in `OTEL_RESOURCE_ATTRIBUTES` |
| Missing `service.version` | Add to `OTEL_RESOURCE_ATTRIBUTES=service.version=<version>` or set in configure block |
| `service.name` contains env or version | Strip env/version; use `deployment.environment.name` and `service.version` separately |
| `deployment.environment.name` read from `Rails.env` in code | Move to `OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=production` |

## Mutation Gate

Before modifying resource setup in source files:
1. Show proposed change (diff or code block)
2. Wait for explicit user confirmation
3. Apply only after confirmation
