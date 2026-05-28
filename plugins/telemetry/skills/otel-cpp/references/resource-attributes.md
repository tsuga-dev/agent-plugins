# Resource Attributes — C++ OTel

> **Last verified:** 2026-03-23 | SDK: `opentelemetry-cpp` 1.26.0

## Required and Recommended Attributes

| Attribute | Required | Set via | Example |
|-----------|----------|---------|---------|
| `service.name` | **Yes** | `std::getenv("OTEL_SERVICE_NAME")` in init code | `web-backend` |
| `service.version` | Strongly recommended | Code (read from env or build-time constant) | `1.4.2` |
| `service.namespace` | Optional | Code | `payments` |
| `deployment.environment.name` | Strongly recommended | Code (read from env) | `production` |
| `telemetry.sdk.name` | Set by SDK | automatic | `opentelemetry` |
| `telemetry.sdk.version` | Set by SDK | automatic | `1.16.1` |

> **Deprecated:** `deployment.environment` (without `.name`) was deprecated in OTel semconv 1.27.0.
> Use `deployment.environment.name` in all new instrumentation.

## Resolve resource attribute values

Before writing any code, determine the correct values. Start with Step 1 and stop at the first match.

### service.name

| Step | Where to look | How |
|---|---|---|
| 1a | `OTEL_SERVICE_NAME` already set | Search Dockerfile, docker-compose.yml, .env, k8s manifests, Makefile for `OTEL_SERVICE_NAME` — if found, **stop**; the value is already correct |
| 1b | Other service name env var | Search the same files for any env var whose name suggests a service identity — common patterns: `SERVICE_NAME`, `APP_NAME`, `APPLICATION_NAME`, `SVC_NAME`, or anything matching `*_NAME`, `*_SERVICE`, `*_APP` — if found, use its value as `OTEL_SERVICE_NAME` |
| 2 | Language manifest | `CMakeLists.txt` `project()` name |
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
Priority: CI/CD version variable (`GITHUB_SHA`, `CI_COMMIT_TAG`) → `CMakeLists.txt` `project(... VERSION x.y.z ...)` → `git describe --tags --always`.

### deployment.environment.name

Priority: existing OTel config → `APP_ENV` → Kubernetes namespace name.

---

## SDK-Native Resource Config

`Resource::Create()` accepts an initializer list of key-value pairs. While the C++ SDK (v1.15+) auto-reads exporter-level `OTEL_*` vars, resource-level vars like `OTEL_SERVICE_NAME` and `OTEL_RESOURCE_ATTRIBUTES` are **not** auto-read into `Resource::Create()` — you must call `std::getenv()` explicitly for those.

```cpp
#include "opentelemetry/sdk/resource/resource.h"
#include <cstdlib>
#include <string>

namespace resource = opentelemetry::sdk::resource;

// GOOD — read env vars manually and pass into Resource::Create()
const char* svc_name_env = std::getenv("OTEL_SERVICE_NAME");
std::string svc_name = svc_name_env ? svc_name_env : "my-service";

const char* svc_ver_env = std::getenv("SERVICE_VERSION");
std::string svc_version = svc_ver_env ? svc_ver_env : "unknown";

const char* env_name_env = std::getenv("DEPLOYMENT_ENVIRONMENT");
std::string env_name = env_name_env ? env_name_env : "production";

auto sdk_resource = resource::Resource::Create({
    {"service.name",               svc_name},
    {"service.version",            svc_version},
    {"deployment.environment.name", env_name},
});

// BAD — hardcoded service name requires recompile to change
auto sdk_resource = resource::Resource::Create({
    {"service.name", "my-service"},   // cannot change without recompile
});
```

## Code-Defined Merge Pattern

Merge multiple resource fragments (e.g., base resource + K8s identity read from downward API):

```cpp
// Base resource from env vars
auto base_resource = resource::Resource::Create({
    {"service.name",               svc_name},
    {"service.version",            svc_version},
    {"deployment.environment.name", env_name},
});

// K8s identity resource (populated from downward API env vars)
const char* node_name = std::getenv("K8S_NODE_NAME");
const char* pod_name  = std::getenv("K8S_POD_NAME");
const char* ns_name   = std::getenv("K8S_NAMESPACE");

resource::ResourceAttributes k8s_attrs;
if (node_name) k8s_attrs["k8s.node.name"]      = std::string(node_name);
if (pod_name)  k8s_attrs["k8s.pod.name"]       = std::string(pod_name);
if (ns_name)   k8s_attrs["k8s.namespace.name"] = std::string(ns_name);

auto k8s_resource = resource::Resource::Create(k8s_attrs);

// Merge: right-side values win on conflict
auto sdk_resource = base_resource.Merge(k8s_resource);
```

## Kubernetes Downward API Injection

Inject pod identity into the container environment, then read in C++ init code:

```yaml
# Deployment spec — env section
env:
  - name: OTEL_SERVICE_NAME
    value: "web-backend"
  - name: SERVICE_VERSION
    valueFrom:
      configMapKeyRef:
        name: app-config
        key: version
  - name: DEPLOYMENT_ENVIRONMENT
    value: "production"
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

## Audit Workflow

**Step 1 — Check what service name is arriving in Tsuga:**

```bash
tsuga spans search --query "context.service.name:*" --max-results 10
```

**Step 2 — Check resource attributes on a span:**

```bash
tsuga spans search --query "context.service.name:<your-service>" --max-results 1
# Inspect: service.version, deployment.environment.name present?
```

**Step 3 — Check the running service's env vars:**

```bash
# Kubernetes
kubectl exec -n <namespace> <pod> -- env | grep -E "OTEL|SERVICE|DEPLOYMENT"

# Docker
docker inspect <container> | grep -A 30 '"Env"'
```

## Fix Patterns

| Finding | Fix |
|---------|-----|
| `service.name = unknown_service` | Read `OTEL_SERVICE_NAME` via `std::getenv()` and pass into `Resource::Create()` |
| `service.name` hardcoded in source | Move to `std::getenv("OTEL_SERVICE_NAME")` with fallback |
| `deployment.environment` (old key) | Replace with `deployment.environment.name` in `Resource::Create()` |
| Missing `service.version` | Add a `SERVICE_VERSION` env var; read in init and include in resource |
| `service.name` contains env or version | Strip env/version; use `deployment.environment.name` and `service.version` separately |
| No K8s pod identity on spans | Add K8s downward API env vars and merge K8s resource as shown above |

## Mutation Gate

Before modifying `Resource::Create()` calls in source files:
1. Show proposed change (diff or code block)
2. Wait for explicit user confirmation
3. Apply only after confirmation
