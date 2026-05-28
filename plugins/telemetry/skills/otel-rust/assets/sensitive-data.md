# Sensitive Data Guidance for OTel Instrumentation

> **First line of defense:** Application-level exclusion is preferred over Collector-side redaction.
> Collector-side OTTL redaction (see `otel-ottl` skill) is a safety net, not the primary control.

## Never Instrument — No Exceptions

These data types must NEVER appear in span attributes, metric dimensions, log fields, or resource attributes:

| Category | Examples |
|----------|---------|
| Credentials | Passwords, PINs, private keys, API keys, bearer tokens, OAuth client secrets |
| Authentication headers | `Authorization`, `Cookie`, `Set-Cookie`, `X-API-Key`, `X-Auth-Token` |
| Payment data | Credit card numbers, CVV codes, full PANs, bank account numbers |
| Government identifiers | SSN, passport numbers, national ID numbers, driver's license numbers |
| Health/medical | Diagnoses, medications, procedure codes, insurance IDs |
| Biometric | Facial recognition data, fingerprints, voiceprints |
| Private messaging | Message bodies, chat content, email body content |

## High-Risk — Evaluate Before Instrumenting

These require explicit evaluation before adding to telemetry:

### user.id / enduser.id

**OK:** Opaque UUID assigned at account creation (e.g., `a7f3b2c1-...`)
**NOT OK:** Username, email address, phone number, or any PII-derived identifier

```
// BAD
span.setAttribute("user.id", user.email)
span.setAttribute("user.id", user.username)

// GOOD (if using opaque UUID)
span.setAttribute("user.id", user.uuid)  // Only if truly opaque
```

### Client IP Addresses

- Full IP addresses are PII in many jurisdictions (GDPR, CCPA)
- Truncate last octet before storing: `192.168.1.x` (IPv4) or last 64 bits (IPv6)
- Or use a hash if you need to correlate without storing raw IPs

### url.full — Strip Sensitive Query Parameters

```
// BAD
span.setAttribute("url.full", request.url)  // May contain ?token=xxx&password=yyy

// GOOD — strip or redact sensitive params
sanitizedUrl = stripQueryParams(request.url, ["token", "password", "api_key", "secret"])
span.setAttribute("url.full", sanitizedUrl)
```

### db.query.text — Only Safe with Parameterized Queries

**Never record literal SQL with user-supplied values:**
```
// BAD — user data in SQL
span.setAttribute("db.query.text", "SELECT * FROM users WHERE email = '" + email + "'")

// GOOD — parameterized query template only
span.setAttribute("db.query.text", "SELECT * FROM users WHERE email = $1")
```

Check your ORM/DB library for a configuration option to sanitize queries (e.g., `dbStatementSerializer` in Node.js OTel DB instrumentation).

### Structured Logs — Never Spread Request Objects

```
// BAD — spreads entire request including headers, body, auth tokens
logger.info("Request received", { request: req })

// GOOD — explicitly pick safe fields
logger.info("Request received", {
    method: req.method,
    path: req.path,
    user_id: req.user?.id,  // Only if opaque UUID
    request_id: req.id,
})
```

## URL Sanitization Patterns

When recording URLs in spans or logs, always sanitize first:

1. **Strip query string entirely** (simplest): record only `url.path`, never `url.full`
2. **Redact known sensitive params**: maintain a deny-list of parameter names to redact
3. **Allow-list approach** (safest): only keep known-safe query params; drop everything else

```
// Allow-list approach
safeParams = ["page", "limit", "sort", "filter"]
sanitized = keepOnlyParams(url, safeParams)
```

## Collector-Side Redaction as Safety Net

Even with app-level controls, add Collector-side redaction for defense in depth. See the `otel-ottl` skill for patterns:

- Redact auth headers: `set(span.attributes["http.request.header.authorization"], "REDACTED") where ...`
- Hash emails: `set(span.attributes["user.email"], SHA256(...)) where ...`
- Regex redaction for credit card patterns

## Compliance Context

| Regulation | Key Constraint |
|-----------|---------------|
| GDPR | Any data that can identify an EU resident is personal data; minimize collection |
| CCPA | IP addresses, user IDs, browsing behavior are "personal information" |
| PCI DSS | Cardholder data (PANs, CVVs) must not appear in logs or traces |
| HIPAA | Protected Health Information (PHI) must not be in observability systems |

When in doubt: **do not instrument**. It is far easier to add telemetry later than to purge PII from a distributed observability backend.
