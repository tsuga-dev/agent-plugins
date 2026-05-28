# Resource Attributes — .NET OTel

> **Last verified:** 2026-03-23 | SDK: OpenTelemetry NuGet 1.15.x / .NET 8+

## Required and Recommended Attributes

| Attribute | Required | Set via | Example |
|-----------|----------|---------|---------|
| `service.name` | **Yes** | `OTEL_SERVICE_NAME` env var (preferred) | `web-backend` |
| `service.version` | Strongly recommended | `OTEL_RESOURCE_ATTRIBUTES` or code | `1.4.2` |
| `service.namespace` | Optional | `OTEL_RESOURCE_ATTRIBUTES` or code | `payments` |
| `deployment.environment.name` | Strongly recommended | `OTEL_RESOURCE_ATTRIBUTES` | `production` |
| `telemetry.sdk.name` | Set by SDK | automatic | `opentelemetry` |
| `telemetry.sdk.version` | Set by SDK | automatic | `1.11.0` |

> **Deprecated:** `deployment.environment` (without `.name`) was deprecated in OTel semconv 1.27.0.
> Use `deployment.environment.name` in all new instrumentation. If you see `deployment.environment`
> in existing code, replace it.

## Resolve resource attribute values

Before writing any code, determine the correct values. Start with Step 1 and stop at the first match.

### service.name

| Step | Where to look | How |
|---|---|---|
| 1a | `OTEL_SERVICE_NAME` already set | Search Dockerfile, docker-compose.yml, .env, k8s manifests, Makefile for `OTEL_SERVICE_NAME` — if found, **stop**; the value is already correct |
| 1b | Other service name env var | Search the same files for any env var whose name suggests a service identity — common patterns: `SERVICE_NAME`, `APP_NAME`, `APPLICATION_NAME`, `SVC_NAME`, or anything matching `*_NAME`, `*_SERVICE`, `*_APP` — if found, use its value as `OTEL_SERVICE_NAME` |
| 2 | Language manifest | `*.csproj` `<AssemblyName>` (fallback: project directory name) |
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
Priority: CI/CD version variable (`GITHUB_SHA`, `CI_COMMIT_TAG`) → `*.csproj` `<Version>` or `<AssemblyVersion>` → `git describe --tags --always`.

### deployment.environment.name

Priority: existing OTel config → `ASPNETCORE_ENVIRONMENT` → Kubernetes namespace name.

---

## ResourceBuilder.CreateDefault() — Reads Env Vars Automatically

```csharp
// ResourceBuilder.CreateDefault() reads OTEL_SERVICE_NAME and OTEL_RESOURCE_ATTRIBUTES
// automatically. This is the correct starting point.
// .AddService() sets a code-level default; OTEL_SERVICE_NAME env var takes precedence when set.
var resourceBuilder = ResourceBuilder.CreateDefault();
```

To add code-defined attributes (e.g., `service.version` from assembly info):

```csharp
using OpenTelemetry.Resources;

// GOOD — start with CreateDefault() then add code-defined attributes
var resourceBuilder = ResourceBuilder.CreateDefault()
    .AddAttributes(new Dictionary<string, object>
    {
        ["service.version"] = typeof(Program).Assembly.GetName().Version?.ToString() ?? "unknown",
        ["service.namespace"] = "payments"
    });

// ACCEPTABLE — .AddService() provides a code-level default; OTEL_SERVICE_NAME overrides it at deploy time
var resourceBuilder = ResourceBuilder.CreateDefault()
    .AddService(serviceName: "web-backend");  // OK as fallback — env var wins when set
```

## Environment Variable Configuration (Preferred)

```bash
# Set service.name — required
OTEL_SERVICE_NAME=web-backend

# Set additional resource attributes
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=production,service.version=1.4.2,service.namespace=payments
```

Prefer env vars for deploy-time values — they can be changed without a code deploy or rebuild.

## Kubernetes Downward API Injection

Inject pod identity as resource attributes via the Kubernetes downward API:

```yaml
# Deployment spec (Kubernetes)
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

Then in code (or append to `OTEL_RESOURCE_ATTRIBUTES`):

```csharp
var resourceBuilder = ResourceBuilder.CreateDefault()
    .AddAttributes(new Dictionary<string, object>
    {
        ["k8s.node.name"]      = Environment.GetEnvironmentVariable("K8S_NODE_NAME") ?? string.Empty,
        ["k8s.pod.name"]       = Environment.GetEnvironmentVariable("K8S_POD_NAME") ?? string.Empty,
        ["k8s.namespace.name"] = Environment.GetEnvironmentVariable("K8S_NAMESPACE") ?? string.Empty
    });
```

## Audit Workflow

**Step 1 — Check what service name is arriving in Tsuga:**

```bash
tsuga spans search --query "context.service.name:*" --max-results 10
```

**Step 2 — Check resource attributes on a span:**

```bash
tsuga spans search --query "context.service.name:<your-service>" --max-results 1
# Look at the resource attributes in the output for service.version, deployment.environment.name
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
| `service.name` hardcoded via `.AddService()` | Remove `.AddService()`; use `ResourceBuilder.CreateDefault()` |
| `deployment.environment` (old key) | Replace with `deployment.environment.name` |
| Missing `service.version` | Add to `OTEL_RESOURCE_ATTRIBUTES=service.version=<version>` or `.AddAttributes()` |
| `service.name` contains env or version | Strip env/version; use `deployment.environment.name` and `service.version` separately |

## Mutation Gate

Before modifying `ResourceBuilder` setup in source files:
1. Show proposed change (diff or code block)
2. Wait for explicit user confirmation
3. Apply only after confirmation
