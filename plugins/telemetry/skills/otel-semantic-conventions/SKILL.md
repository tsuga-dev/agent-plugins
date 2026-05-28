---
name: otel-semantic-conventions
description: "Use before naming any span, metric, log, or resource attribute, and when migrating from old keys like deployment.environment — covers correct key names, placement (resource vs span vs metric), deprecated key migrations, and cardinality rules."
---

# OTel Semantic Conventions Reference

> **Last verified:** 2026-03-23 | Semconv version: 1.40.0

## When to Use This Skill

- Choosing an attribute name for a span, metric, resource, or log record
- Checking if a semantic convention exists for a domain (HTTP, DB, messaging, etc.)
- Migrating deprecated attribute names to current ones
- Understanding stability levels (stable vs experimental vs deprecated)
- Resolving "resource vs span attribute" placement questions

**Relationship to `signal-choice-advisor`:** This skill answers "what key name?"; `signal-choice-advisor` answers "what signal type?". Use both when both questions arise.

## Registry-First Rule

**Before inventing any attribute name, search the OTel Attribute Registry.**

Registry: https://opentelemetry.io/docs/specs/semconv/registry/attributes/

If a registry entry exists for your concept, use it — even if it's experimental. Inventing parallel names fragments observability tooling.

**BAD:** `span.setAttribute("http_method", "GET")`
**GOOD:** `span.setAttribute("http.request.method", "GET")`

**BAD:** `span.setAttribute("database_query", "SELECT ...")`
**GOOD:** `span.setAttribute("db.query.text", "SELECT ...")`

## Attribute Placement Decision Table

Where an attribute belongs determines how it's stored, indexed, and queried.

| Level | What Belongs Here | Examples |
|-------|------------------|---------|
| **Resource** | Identity + environment; stable for process lifetime | `service.name`, `service.version`, `deployment.environment.name`, `k8s.pod.name`, `host.name`, `cloud.region` |
| **Scope** | Identity of instrumentation library | `otel.scope.name`, `otel.scope.version` |
| **Span** | Request-specific context; varies per request | `http.request.method`, `db.operation.name`, `url.path`, `order.id`, `http.response.status_code` |
| **Span Event** | Point-in-time occurrences within a span | `exception.type`, `exception.message`, `exception.stacktrace` |
| **Log Record** | Structured log entry fields | `log.file.path`, `severity`, `trace_id`, `span_id` |
| **Metric Datapoint** | Low-cardinality dimensions ONLY | `http.request.method`, `http.response.status_code`, `http.route` |

## Common Attribute Placement Mistakes

### BAD: Kubernetes metadata on spans

```
// BAD: k8s.pod.name on every span — wastes storage, already on resource
span.setAttribute("k8s.pod.name", podName)

// GOOD: k8s.pod.name belongs on the resource (set once per process)
resource.setAttribute("k8s.pod.name", podName)
```

### BAD: service.name on spans

```
// BAD: service.name is a resource attribute — adding it to spans duplicates storage
span.setAttribute("service.name", "order-service")

// GOOD: set once via OTEL_SERVICE_NAME or SDK resource config
// Never set service.name on individual spans
```

### BAD: user.id as a metric dimension

```
// BAD: unbounded cardinality — one unique value per user
histogram.record(duration, {"user.id": userId})

// GOOD: user.id on spans (OK if opaque UUID); never on metric dimensions
span.setAttribute("user.id", userId)
histogram.record(duration, {"http.route": "/api/orders"})  // Only low-cardinality dims
```

### BAD: url.path as metric dimension

```
// BAD: /api/orders/123/items has unbounded cardinality
histogram.record(duration, {"url.path": request.path})

// GOOD: use parameterized http.route
histogram.record(duration, {"http.route": "/api/orders/{id}/items"})
```

## Must-Have Resource Attributes

| Attribute | Requirement | Notes |
|-----------|-------------|-------|
| `service.name` | **REQUIRED** | Use kebab-case; no environment suffix |
| `service.version` | Strongly recommended | Resolve at build time; never hardcode |
| `service.instance.id` | **REQUIRED** (Stable) | UUID v4 or derived from pod UID; must be unique per `service.namespace`+`service.name` pair |
| `deployment.environment.name` | Recommended | `production`, `staging`, `development`. **Note:** Development stability — attribute name may change |
| `k8s.pod.uid` | Required on Kubernetes | Used by `k8sattributes` processor for enrichment |

## Common Span Attributes by Domain

### HTTP (Server and Client)

| Attribute | Type | Notes |
|-----------|------|-------|
| `http.request.method` | string | GET, POST, PUT, DELETE, PATCH |
| `http.response.status_code` | int | 200, 404, 500 |
| `http.route` | string | Template: `/users/{id}` (not raw path) |
| `url.full` | string | Full URL including query string (CLIENT spans) |
| `url.path` | string | Path only, no query string |
| `server.address` | string | Hostname or IP of server |
| `server.port` | int | Port number |
| `network.protocol.version` | string | "1.1", "2" |

### Database

| Attribute | Type | Notes |
|-----------|------|-------|
| `db.system.name` | string | `postgresql`, `mysql`, `redis`, `mongodb` |
| `db.operation.name` | string | `SELECT`, `INSERT`, `UPDATE`, `FIND` |
| `db.collection.name` | string | Table or collection name |
| `db.query.text` | string | Query template only (no literal values — security risk) |
| `db.namespace` | string | Database name |
| `server.address` | string | DB host |
| `server.port` | int | DB port |

### Messaging (Queues, Topics)

| Attribute | Type | Notes |
|-----------|------|-------|
| `messaging.system` | string | `kafka`, `rabbitmq`, `aws_sqs`, `google_pubsub` |
| `messaging.destination.name` | string | Queue or topic name |
| `messaging.operation.type` | string | `create`, `send`, `receive`, `process`, `settle` |
| `messaging.message.id` | string | Message identifier |
| `messaging.batch.message_count` | int | For batch operations |

### Exceptions (Span Events)

| Attribute | Type | Notes |
|-----------|------|-------|
| `exception.type` | string | Exception class name |
| `exception.message` | string | Exception message |
| `exception.stacktrace` | string | Full stack trace |
| `exception.escaped` | bool | **Deprecated** — no longer recommended to record; handled exceptions should not use this attribute |

Use `span.recordException(error)` — the OTel SDK populates these automatically.

## Deprecated → Current Attribute Migration

| Deprecated | Current | Notes |
|-----------|---------|-------|
| `deployment.environment` | `deployment.environment.name` | Added `.name` suffix |
| `http.method` | `http.request.method` | Renamed |
| `http.status_code` | `http.response.status_code` | Renamed |
| `http.url` | `url.full` | Moved to `url.*` namespace |
| `http.target` | `url.path` + `url.query` | Split into two attributes |
| `net.host.name` | `server.address` | Renamed |
| `net.host.port` | `server.port` | Renamed |
| `net.peer.name` | `server.address` (client spans) / `client.address` (server spans) | Context-dependent: use `server.address` when instrumenting outbound calls, `client.address` when instrumenting inbound requests |
| `db.statement` | `db.query.text` | Renamed |
| `db.name` | `db.namespace` | Renamed |
| `enduser.role` | `user.roles` | Deprecated; use `user.roles` (array) instead |
| `enduser.scope` | *(removed, no replacement)* | Deprecated with no replacement |

> **Note:** `enduser.id` is NOT deprecated — it has Development status. Do not confuse it with `enduser.role`/`enduser.scope` which are deprecated. `user.id` exists as a separate Development-status attribute.

## Stability Levels

| Level | Meaning | Use in Production? |
|-------|---------|-------------------|
| **Stable** | Breaking changes will not occur | Yes |
| **Experimental** | May change in future semconv releases | Yes, but pin semconv version |
| **Deprecated** | Will be removed; use replacement | No — migrate to current name |

Stability varies by domain:
- **HTTP:** Stable since v1.23.0 (the first semconv domain to reach stability)
- **Database:** Stable since v1.33.0 (for core spans/metrics on PostgreSQL, MySQL, MariaDB, MS SQL Server)
- **Messaging:** Still **Development** status — not yet stable; attribute names may change

## Cardinality Rules for Metric Dimensions

Only use attributes as metric dimensions if their cardinality is bounded and known:

| Category | Cardinality | Use as metric dimension? |
|----------|------------|--------------------------|
| `http.request.method` | ~10 values | Yes |
| `http.response.status_code` | ~50 values | Yes (or group to 2xx/4xx/5xx) |
| `http.route` | ~100-1000 routes | Yes (if routes are parameterized) |
| `db.operation.name` | ~10 values | Yes |
| `db.system.name` | ~10 values | Yes |
| `user.id` | Unbounded | **Never** |
| `url.path` | Unbounded (without parameterization) | **Never** |
| `url.full` | Unbounded | **Never** |
| `order.id` | Unbounded | **Never** |

## Limitations

- Semantic conventions evolve; always verify the current version at opentelemetry.io/docs/specs/semconv/
- Experimental attributes may be renamed between semconv releases
- Some SDKs emit older (deprecated) attribute names via auto-instrumentation — check and pin SDK + semconv versions together
- This skill covers naming; `signal-choice-advisor` covers signal type selection
