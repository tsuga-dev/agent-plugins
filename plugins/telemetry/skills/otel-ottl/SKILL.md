---
name: otel-ottl
description: "Use for any OTTL expression or Collector transformation task — redacting PII, dropping spans by condition, enriching attributes, renaming fields in transform/filter/routing processors."
---

# OTel Transformation Language (OTTL) Reference

> **Last verified:** 2026-03-23 | Collector version: `otelcol-contrib` v0.146.0+

## When to Use This Skill

- Writing OTTL statements for `transform`, `filter`, or `routing` processors/connectors
- Redacting sensitive data in the Collector pipeline
- Dropping spans, logs, or metrics based on conditions
- Enriching telemetry with computed or derived attributes
- Writing conditions for `tailsamplingprocessor` OTTL policies

## Components That Use OTTL

| Component | Type | Purpose |
|-----------|------|---------|
| `transform` processor | Processor | Modify telemetry fields; side-effect functions |
| `filter` processor | Processor | Drop items matching conditions |
| ~~`attributes` processor~~ | — | Uses its own key/value DSL, NOT OTTL |
| ~~`span` processor~~ | — | Uses its own config DSL, NOT OTTL |
| `routing` connector | Connector | Route to different pipelines based on conditions |
| `count` connector | Connector | Count telemetry items matching conditions |
| `signaltometrics` connector | Connector | Generate metrics from spans/logs |

## OTTL Syntax Reference

### Path Expressions

Access telemetry fields using dot notation:

```
span.name                              # Span name
span.kind                              # Span kind (integer)
span.status.code                       # Status code
span.attributes["http.method"]         # Span attribute by key
span.attributes["http.request.header.authorization"]
resource.attributes["service.name"]    # Resource attribute
instrumentation_scope.name              # Instrumentation scope name
log.body.string                        # Log body as string
log.severity_number                    # Log severity
datapoint.attributes["http.route"]     # Metric datapoint attribute
```

### Contexts

Each pipeline signal type has its own context:

| Signal | Available Contexts |
|--------|-------------------|
| Traces | `resource`, `scope`, `span`, `spanevent` |
| Metrics | `resource`, `scope`, `metric`, `datapoint` |
| Logs | `resource`, `scope`, `log` |
| Profiles | `resource`, `scope`, `profile` |

### Operators

```
==      equality check
!=      not equal
>       greater than
<       less than
>=      greater than or equal
<=      less than or equal
and     logical AND
or      logical OR
not     logical NOT
+       addition
-       subtraction
*       multiplication
/       division
```

Note: OTTL has no `=` operator. Assignment is performed via the `set()` function.

### Function Categories

**Converters** (PascalCase names — pure, no side effects — use in conditions and assignments):
```
ToUpperCase(value)
ToLowerCase(value)
Substring(value, offset, length)
Concat([value1, value2, ...], delimiter)
IsMatch(value, pattern)       # Regex match — returns bool
SHA256(value)                 # Hash to SHA-256 hex string
Now()                         # Current timestamp
Int(value)                    # Convert to integer
String(value)                 # Convert to string
```

**Editors** (lowercase names — side effects — use as statements):
```
set(target, value)
delete_key(target, key)
delete_matching_keys(target, pattern)
limit(target, limit, priority_keys)    # Limit attribute count
replace_pattern(target, regex, replacement)
replace_all_patterns(target, mode, regex, replacement)  # mode: "key" or "value"
keep_keys(target, keys)
merge_maps(target, source, strategy)
```

### where Clause (Conditional Transforms)

Apply a statement only when a condition is true:

```
set(span.attributes["http.request.header.authorization"], "REDACTED") where span.attributes["http.request.header.authorization"] != nil
```

**Always use `where` with `nil` checks for optional attributes** — accessing a nil attribute path throws an error.

### nil vs null

OTTL uses `nil`, not `null`.

**BAD:**
```
where span.attributes["user.email"] != null
```
**GOOD:**
```
where span.attributes["user.email"] != nil
```

## Common Patterns

### Redact Authorization Headers

```yaml
processors:
  transform:
    error_mode: ignore
    trace_statements:
      - context: span
        statements:
          - set(span.attributes["http.request.header.authorization"], "REDACTED") where span.attributes["http.request.header.authorization"] != nil
          - set(span.attributes["http.request.header.cookie"], "REDACTED") where span.attributes["http.request.header.cookie"] != nil
          - set(span.attributes["http.response.header.set-cookie"], "REDACTED") where span.attributes["http.response.header.set-cookie"] != nil
```

### Redact Credit Card Numbers via Regex

```yaml
        statements:
          - replace_pattern(log.body.string, "\\b(\\d{4})\\d{5,11}(\\d{4})\\b", "$$1****$$2")
```

Note: `$$` escapes a literal `$` in replacement strings.

### Hash Email Addresses

```yaml
        statements:
          - set(span.attributes["user.email"], SHA256(span.attributes["user.email"])) where span.attributes["user.email"] != nil
```

### Drop Health Check Spans

```yaml
processors:
  filter:
    error_mode: ignore
    trace_conditions:
      - span.attributes["http.route"] == "/health"
      - span.attributes["http.route"] == "/healthz"
      - span.attributes["http.route"] == "/ready"
      - span.attributes["http.target"] == "/metrics"
```

### Drop Low-Priority Logs

```yaml
processors:
  filter:
    error_mode: ignore
    log_conditions:
      - log.severity_number < SEVERITY_NUMBER_WARN and IsMatch(resource.attributes["service.name"], "^noise-service$")
```

### Backfill Missing Timestamps

```yaml
        statements:
          - set(log.observed_time_unix_nano, UnixNano(Now())) where log.observed_time_unix_nano == 0
```

### Enrich with Environment Tag

```yaml
        statements:
          - set(resource.attributes["deployment.environment.name"], "production") where resource.attributes["deployment.environment.name"] == nil
```

### Truncate Long DB Queries

```yaml
        statements:
          - set(span.attributes["db.query.text"], Concat([Substring(span.attributes["db.query.text"], 0, 500), "..."], "")) where span.attributes["db.query.text"] != nil and Len(span.attributes["db.query.text"]) > 500
```

### Drop High-Cardinality Metric Dimensions

```yaml
processors:
  transform:
    error_mode: ignore
    metric_statements:
      - context: datapoint
        statements:
          - delete_key(datapoint.attributes, "user.id") where datapoint.attributes["user.id"] != nil
```

## Error Modes

| Mode | Behavior | When to Use |
|------|----------|-------------|
| `propagate` | Stop processing item on error; return error to pipeline | Default; use in development to catch mistakes |
| `ignore` | Log error and continue processing item | **Production** — ensures one bad item doesn't block pipeline |
| `silent` | Continue processing; no error log | Use only if error noise is understood |

**Always use `error_mode: ignore` in production Collector configurations.**

## Transform Processor Structure

```yaml
processors:
  transform:
    error_mode: ignore
    trace_statements:
      - context: span
        statements:
          - <statement1>
          - <statement2>
      - context: resource
        statements:
          - <statement3>
    metric_statements:
      - context: datapoint
        statements:
          - <statement4>
    log_statements:
      - context: log
        statements:
          - <statement5>
```

## Performance Notes

- OTTL statements compile once at Collector startup — no per-item compilation cost
- Use `where` clauses to skip items early — avoids unnecessary function calls
- `IsMatch` (regex) is more expensive than equality checks — use `==` when possible
- `delete_key` is cheaper than `set(attr, "REDACTED")` if you don't need the key preserved

## Limitations

- OTTL cannot create new spans, metrics, or log records — only modify or drop existing ones
- No looping constructs — OTTL is purely expression-based
- `SHA256` is one-way — you cannot recover original values; document what was hashed
- Collector-side redaction is a safety net; app-level is the first line of defense (see `references/sensitive-data.md` in per-language skills)
