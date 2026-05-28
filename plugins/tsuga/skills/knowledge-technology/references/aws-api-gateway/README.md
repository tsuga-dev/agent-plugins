# AWS API Gateway Integration Context Bundle

## Metadata
**Technology:** AWS API Gateway
**Deployment:** managed
**Environment:** prod
**Persona:** SRE Dev and ops
**Telemetry preference:** mixed
**Integration scope:** core service only
**Primary use-case:** reliability and performance

## How to use this bundle
Read `01_aws-api-gateway_metrics.csv` first for the Stage 1 source of truth on API Gateway request, error, latency, and cache metrics. Read `02_aws-api-gateway_dashboard_plan.yaml` next for the concrete dashboard structure, widget intent, derived signals, explanation notes, triage chains, and playbooks.

Use `03_aws-api-gateway_state.yaml` for machine-readable assumptions, unknowns, metric-prefix status, and Stage 4 log-intel handoff. Use `04_aws-api-gateway_memory.md` for the narrative handoff that tells Stage 2 what to verify first. Stage 2 will create `05_aws-api-gateway_metric_catalog.csv` as the discovered Tsuga metric catalog for reconciliation and coverage checks. Stage 4 should read this file's `Log intelligence (Stage 4 handoff)` section and the `03_aws-api-gateway_state.yaml` `log_intel` block before attempting log-route creation.

## What it is and what "good" looks like
### Confirmed by sources
Amazon API Gateway is AWS's managed API front door for REST, HTTP, and WebSocket APIs. The metric family documented in the `AWS/ApiGateway` namespace exposes stage and method execution signals such as total request count, 4XX and 5XX errors, total latency, integration latency, and cache hits or misses when stage caching is enabled. API Gateway can also emit execution logs, custom access logs, detailed metrics, and X-Ray traces at the stage level. [Metrics and dimensions](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-metrics-and-dimensions.html), [Set up logging](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html), [Set up X-Ray](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-enabling-xray.html)

Good operational posture for API Gateway means request volume stays near expected baseline, 5XX errors remain near zero, 4XX increases are explainable by caller behavior instead of platform changes, and end-to-end latency tracks integration latency closely without unexplained gateway overhead. If caching is enabled, cache hit ratio should be stable for cacheable routes and latency should improve without masking backend failures. [Metrics and dimensions](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-metrics-and-dimensions.html), [Cache settings](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-caching.html)

The three highest-value incident shapes are:
1. Traffic normal but 5XX rises: start in `apigw-server-faults`.
2. Traffic stable but latency rises: start in `apigw-latency-path`.
3. Traffic drop or route skew: start in `apigw-traffic-demand`.

Execution logging and access logging are independent knobs. Detailed metrics are optional and matter because method and resource-level breakdowns are far more useful than a single stage aggregate during incident triage. [Set up logging](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html)

### Best-practice inference
This bundle intentionally centers the REST API execution surface because the documented `AWS/ApiGateway` metrics that map cleanly to the user-provided namespace hint (`aws_apigateway_latency`) are the stage and method metrics used for REST API monitoring. If the workspace later shows HTTP API or WebSocket-specific families, Stage 2 should widen the catalog, but Stage 1 should not invent them.

A healthy first-response dashboard for API Gateway should separate three ownership domains quickly: caller mistakes (4XX), gateway or integration failures (5XX), and latency spent inside API Gateway versus latency spent waiting on the backend. That split is more actionable than a single generic "availability" card because it tells the on-call whether to page application owners, client owners, or platform operators.

## Key concepts
### Glossary
| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| API Gateway stage | Named deployment environment such as `prod` or `staging` | Smallest reliable first-response scope for most incidents | apigw-traffic-demand |
| REST API execution metric | CloudWatch metric emitted for request processing at API or method level | Core signal source for RED dashboarding | apigw-traffic-demand |
| Count | Number of API requests in a period | Primary traffic denominator for all error ratios | apigw-traffic-demand |
| 4XXError | Client-visible requests ending in 4xx | Caller contract, auth, throttling, or validation symptom | apigw-client-faults |
| 5XXError | Requests ending in 5xx | Gateway, integration, or backend failure signal | apigw-server-faults |
| Latency | End-to-end API Gateway request time in milliseconds | User-perceived latency headline | apigw-latency-path |
| IntegrationLatency | Time API Gateway waits on backend integration in milliseconds | Backend latency component | apigw-latency-path |
| Gateway overhead | Latency not spent in the backend integration | Mapping, auth, request/response handling, or gateway-side work | apigw-latency-path |
| Detailed metrics | Optional per-stage, per-method, per-resource metrics | Enables route-level and method-level breakdowns | apigw-traffic-demand |
| Stage cache | Optional API Gateway response cache | Can reduce backend calls and user latency | apigw-cache-efficiency |
| Method dimension | HTTP method such as `GET` or `POST` | Helps separate read-heavy from write-heavy route behavior | apigw-traffic-demand |
| Resource dimension | API resource path or route template | Best route-level breakdown when available | apigw-traffic-demand |
| ApiName dimension | Human-readable API name | Primary multi-API grouping key | apigw-traffic-demand |
| Stage dimension | Deployment stage name | Safe filter and grouping key for isolating prod incidents | apigw-traffic-demand |
| Access log | Custom log line built from `$context` variables | Best request-level log substrate for Stage 4 | apigw-server-faults |
| Execution log | API Gateway-managed CloudWatch Logs execution traces | Best for request lifecycle debugging and auth/mapping failures | apigw-server-faults |
| Extended request ID | API Gateway-generated unique request identifier | Strong correlation handle for logs and support cases | apigw-server-faults |
| Integration status | Backend or Lambda proxy integration status code in access logs | Distinguishes gateway wrapper status from backend status | apigw-server-faults |
| Canary release | Small-percent stage deployment receiving a subset of traffic | Important because metrics and logs may split between base and canary | apigw-traffic-demand |
| Active tracing | X-Ray tracing enabled on a stage | Adds latency-path context outside metrics | apigw-latency-path |
| Lambda proxy integration | Common API Gateway integration mode for Lambda-backed APIs | Changes interpretation of integration status fields | apigw-server-faults |
| Throttling | Request rejection due to quotas, usage plans, or backend protection | Often appears to callers as a 4xx pattern rather than 5xx | apigw-client-faults |

### Concept Map
Client -> sends request to -> API Gateway stage (why: every incident starts with whether the stage is accepting work)
API Gateway stage -> exposes -> Count (why: traffic baseline is the denominator for health ratios)
API Gateway stage -> emits -> 4XXError (why: caller-visible failure can rise even when the platform is healthy)
API Gateway stage -> emits -> 5XXError (why: server-side failure is the clearest outage signal)
API Gateway stage -> measures -> Latency (why: this is closest to user-perceived request time)
API Gateway stage -> measures -> IntegrationLatency (why: this isolates backend wait time inside the end-to-end request)
Latency -> minus -> IntegrationLatency (why: the difference approximates gateway-side overhead)
API Gateway stage -> optionally enables -> Detailed metrics (why: route and method drilldown is needed for triage)
Detailed metrics -> add dimensions -> ApiName/Stage/Resource/Method (why: these are the safe bounded breakdown keys)
API Gateway stage -> optionally enables -> Stage cache (why: cache hits reduce backend traffic and latency)
API Gateway stage -> forwards request to -> Integration target (why: backends own most of IntegrationLatency)
Integration target -> returns status/bytes to -> API Gateway (why: backend behavior influences 5xx and latency patterns)
API Gateway mapping/auth/request processing -> contributes to -> Gateway overhead (why: overhead growth without backend growth suggests gateway-side work)
Canary request routing -> splits traffic between -> base stage and canary path (why: metric and log interpretation can differ during rollout)
API Gateway stage -> writes -> Execution logs (why: execution logs explain request lifecycle and mapping/auth problems)
API Gateway stage -> writes -> Access logs (why: access logs are the cleanest request-level Stage 4 source)
Access logs -> include -> requestId and extendedRequestId (why: request-level correlation depends on a stable ID)
Access logs -> include -> integrationStatus and integrationLatency (why: backend root cause can be separated from gateway wrapper behavior)
X-Ray tracing -> correlates -> API Gateway and downstream services (why: latency-path analysis is stronger with traces)
ApiName -> maps to -> context.apiname (why: multi-API estates need a bounded primary ownership key)
Stage -> maps to -> context.stage (why: prod and staging must be split cleanly)
Method -> maps to -> context.method (why: GET and POST often have different latency and cache behavior)
Resource -> maps to -> context.resource (why: one hot route can dominate error or latency patterns)
Environment and team tags -> map to -> context.env and context.team (why: global dashboard filters need tenant and owner scoping)

### Entities and dimensions
| Entity/Dimension | Why useful | Cardinality risk | Safe top-N suggestion | Do NOT group-by guidance |
|---|---|---|---|---|
| `context.apiname` | Primary API ownership and grouping key | Low | 20 | Use first before method or resource splits |
| `context.stage` | Separates prod, staging, or canary-adjacent environments | Low | 10 | Prefer as a global filter before chart splits |
| `context.resource` | Best path-level hot spot isolation | Medium | 20 | Avoid raw URL paths if the pipeline uses untemplated values |
| `context.method` | Distinguishes reads from writes and mutation-heavy traffic | Low | 8 | Use alongside API or resource, not alone, for context |
| `context.apiid` | Stable identifier when names are duplicated | Low | 20 | Keep as fallback when `context.apiname` is absent |
| `context.cloud.region` | Multi-region isolation | Low | 10 | Better as a global filter than a chart series in single-region estates |
| `context.cloud.account.id` | Multi-account ownership and blast radius | Low | 10 | Prefer filter over timeseries split |
| `context.env` | Environment isolation | Low | 5 | Keep as a dashboard filter |
| `context.team` | Ownership boundary | Low | 10 | Keep as a dashboard filter |
| `context.domainname` | Useful when custom domains front multiple APIs | Medium | 10 | Do not rely on it unless Stage 2 confirms consistent tagging |
| `context.requestid` | Request-level correlation key | Very high | 0 | Never use in metric group-bys |
| `context.extendedrequestid` | Stronger API Gateway-generated request identifier | Very high | 0 | Never use in metric group-bys |
| `context.canary` | Distinguishes canary and base traffic during rollout | Low | 2 | Only use if Stage 2 confirms the field exists |

### Tsuga field mapping
#### Confirmed by sources
| Vendor/exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| ApiName | `context.apiname` | Must-exist |
| Stage | `context.stage` | Must-exist |
| Method | `context.method` | Strongly preferred |
| Resource | `context.resource` | Strongly preferred |
| API identifier | `context.apiid` | Optional |
| Environment tag | `context.env` | Must-exist |
| Team tag | `context.team` | Must-exist |

AWS documents `ApiName`, `Stage`, `Resource`, and `Method` as dimensions for the `AWS/ApiGateway` metric family, especially when detailed metrics are enabled. [Metrics and dimensions](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-metrics-and-dimensions.html)

#### Best-practice inference
If the Tsuga pipeline uses standard semantic keys instead of AWS dimension names, `context.resource` may appear as a normalized route key and `context.method` may align to an HTTP semantic field. If `context.apiname` is not present, `context.apiid` or `context.scope.name` is the safest fallback. Stage 2 must confirm the actual field inventory before dashboard filters are frozen.

## Golden signals
### Confirmed by sources
| Signal | What it means for API Gateway | Typical causes when it degrades | Best telemetry sources | What people page on | Section questions |
|---|---|---|---|---|---|
| Traffic | Request demand reaching the stage and each route | upstream traffic drop, client outage, DNS/routing issue, canary split effects | `Count`, access logs | sudden request collapse or skewed route concentration | Is traffic arriving? Which API, stage, or route changed shape? |
| Errors | Caller-visible 4xx and platform/backend 5xx failures | auth failures, usage-plan throttling, contract drift, backend outage, mapping failures | `4XXError`, `5XXError`, execution logs, access logs | sustained 5xx, sudden 4xx wave after deploy, one-route failure concentration | Are failures client-driven or server-driven? Which route owns them? |
| Latency | Total request time and backend contribution | slow backend, cold dependency, increased gateway processing, auth/mapping changes, cache regression | `Latency`, `IntegrationLatency`, X-Ray, access logs | p95/p99-like latency growth, gateway overhead drift | Is the backend slow, or is API Gateway adding overhead? |
| Saturation | API Gateway has no single CPU widget here, so saturation is inferred from rising latency, growing 4xx/5xx, and cache misses under load | quota pressure, throttling, route hot spots, backend strain, canary imbalance | `Count`, errors, latency, cache metrics, execution logs | traffic stable but latency and 5xx rising, backend amplified by cache misses | Is the request path keeping up with demand? Is cache loss amplifying load? |

### Best-practice inference
For API Gateway, RED is the right primary dashboard story. Saturation is not a first-class direct metric in this family, so the dashboard should treat saturation as a compound pattern: same or rising request rate, rising latency, and rising server-side faults. In this workspace the cache metrics are absent, so cache-driven saturation analysis must remain gated rather than assumed.

## Telemetry sources
### Confirmed by sources
| Source type | How collected | What it provides | Pros/cons | Common pitfalls |
|---|---|---|---|---|
| CloudWatch execution metrics | Native `AWS/ApiGateway` namespace | Count, 4xx, 5xx, latency, integration latency, cache hit and miss counts | Canonical request KPI source; low setup overhead | Detailed metrics are optional, so route breakdowns may be absent |
| Detailed stage metrics | Stage setting in API Gateway | ApiName, Stage, Resource, Method-level breakdowns | Best metric drilldown for incidents | If disabled, you get only coarse aggregate visibility |
| Execution logs | Stage logging to CloudWatch Logs | Request lifecycle and execution-path troubleshooting | Best for mapping, auth, and integration errors | Data tracing can expose sensitive payloads and is not recommended for prod |
| Custom access logs | Stage access-log format built from `$context` variables | Structured request records with status, request IDs, integration metadata | Best Stage 4 log substrate | Must include requestId or extendedRequestId; schema is only as good as the configured template |
| Stage cache metrics | Native metrics when caching is enabled | Cache hit and miss metrics | Useful for cache-efficiency analysis | Absent entirely when caching is off |
| X-Ray traces | Optional stage active tracing | End-to-end latency path and downstream trace linkage | Best latency-path evidence beyond metrics | REST API only; not all stages enable it |

Detailed metrics, execution logs, access logs, stage cache, and X-Ray are all optional per-stage capabilities, so "no data" frequently means "feature disabled" rather than "zero events." [Set up logging](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html), [Cache settings](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-caching.html), [Set up X-Ray](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-enabling-xray.html)

### Best-practice inference
If a workspace only exports `aws_apigateway_latency` and not sibling count or error metrics, the dashboard should degrade to a latency-centric health surface and explicitly call out the missing denominator problem. A latency-only API Gateway dashboard is still useful, but it cannot honestly answer RED questions by itself.

## Log intelligence (Stage 4 handoff)
### Confirmed by sources
1. Log sources matrix

| Source | Access path | Typical format | Structured vs unstructured | Evidence |
|---|---|---|---|---|
| Execution logs | CloudWatch Logs group `API-Gateway-Execution-Logs_{rest-api-id}/{stage_name}` | API Gateway execution trace lines | Semi-structured text | [Set up logging](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html) |
| Access logs | Custom CloudWatch Logs destination chosen on the stage | JSON, CLF, XML, or CSV depending on template | Structured if JSON, otherwise semi-structured | [Set up logging](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html) |
| Canary access and execution logs | Same as base logs with `/Canary` suffix behavior | Same as base format, split for canary traffic | Same as configured format | [Canary release](https://docs.aws.amazon.com/apigateway/latest/developerguide/canary-release.html) |

2. Known log formats

- `API Gateway access log (JSON template)`
  - Sample line: `{"requestId":"$context.requestId","extendedRequestId":"$context.extendedRequestId","apiId":"$context.apiId","stage":"$context.stage","resourcePath":"$context.resourcePath","httpMethod":"$context.httpMethod","status":"$context.status","integrationStatus":"$context.integration.status","integrationLatency":"$context.integrationLatency","responseLatency":"$context.responseLatency"}`
  - Delimiter and shape notes: JSON object if the stage uses a JSON template; exact keys depend on the selected `$context` variables.
  - Timestamp pattern: configurable if included in the template.
  - Quoting behavior: valid JSON quoting if the template is authored correctly.
  - Optional fields: canary, authorizer, integration, and identity fields depend on configuration and request path. [Access logging variables](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-variables-for-access-logging.html), [Set up logging](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html)

- `API Gateway execution log`
  - Sample line: `Extended Request Id: <id> API Key: <value> Stage: <stage> Method request path: <path> Method completed with status: <code>`
  - Delimiter and shape notes: line-oriented text emitted by API Gateway internals; shape varies by event type.
  - Timestamp pattern: CloudWatch Logs event timestamp.
  - Quoting behavior: free-form text, not guaranteed JSON.
  - Optional fields: data tracing adds request or response payload details and should be treated as sensitive. [Set up logging](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html)

3. Candidate query filters for Stage 4

- Precise: `context.service.name:"aws-apigateway" AND context.stage:* AND (context.apiname:* OR context.apiid:*)`
  - Rationale: targets normalized API Gateway request logs while requiring stage scope.
  - Risk: depends on the actual service-name normalization in the current Tsuga pipeline.
- Fallback: `"API-Gateway-Execution-Logs" OR ("integrationLatency" AND "requestId" AND "stage")`
  - Rationale: catches both raw execution logs and common JSON access-log templates.
  - Risk: can overmatch setup or synthetic log lines if the workspace has multiple API Gateway logging conventions.

4. Attribute mapping hints

| Raw field | Suggested Tsuga key | Confidence | Notes |
|---|---|---|---|
| `$context.requestId` | `context.requestid` | High | Required in access log format or use extendedRequestId |
| `$context.extendedRequestId` | `context.extendedrequestid` | High | Better unique API Gateway identifier |
| `$context.apiId` | `context.apiid` | High | Stable API identifier |
| `$context.apiId` or API name tag | `context.apiname` | Medium | Depends on whether API name is logged directly or enriched later |
| `$context.stage` | `context.stage` | High | Best first log filter |
| `$context.resourcePath` | `context.resource` | High | Safer than raw URL when available |
| `$context.httpMethod` | `context.method` | High | Bounded and highly useful |
| `$context.status` | `context.status_code` | High | Client-visible response code |
| `$context.integration.status` | `context.integration_status` | Medium | Important for Lambda proxy and backend separation |
| `$context.integrationLatency` | `context.integration_latency_ms` | High | Maps directly to latency-path analysis |
| `$context.responseLatency` | `context.latency_ms` | High | Useful when request-level latency logs are present |
| `$context.isCanaryRequest` | `context.canary` | Medium | Present only when canary is enabled |

5. Parsing risks

- Access log shape is entirely template-defined, so one team's JSON schema may not match another team's CSV or CLF schema.
- Execution logs are semi-structured and event-type-dependent, so a single parser is unlikely to fit every line without split processors.
- `$context.requestId` can be overridden by clients; use `$context.extendedRequestId` when uniqueness matters.
- Data tracing may log sensitive request or response details; Stage 4 should avoid assuming payload fields are safe to retain.
- Canary deployments can duplicate log destinations with `/Canary` suffix behavior and split apparent traffic unexpectedly.

### Best-practice inference
If both access logs and execution logs are present, Stage 4 should prefer access logs as the primary structured route and treat execution logs as a secondary troubleshooting stream. Execution logs are better for lifecycle debugging, but access logs produce more stable attribute extraction for dashboards and log pivots.

## Caveats and footguns
- **[apigw-traffic-demand]** `Count` is the denominator for most RED formulas; if it is missing, error-rate and success-rate widgets should gate instead of backfilling from errors alone. (Inference)
- **[apigw-traffic-demand]** Detailed metrics are optional, so missing `Method` or `Resource` breakdowns often mean stage settings are coarse rather than route traffic being zero. ([Set up logging](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html))
- **[apigw-traffic-demand]** A canary release can split traffic and logs between base and canary paths, which can make a normal traffic shift look like a production drop. ([Canary release](https://docs.aws.amazon.com/apigateway/latest/developerguide/canary-release.html))
- **[apigw-traffic-demand]** `ApiName` is human-readable and can be renamed; keep `apiId` available as a fallback identity key. (Inference)
- **[apigw-client-faults]** `4XXError` is not purely "bad clients"; usage-plan throttling, auth failures, or request-validation mistakes can all look like caller faults at the metric layer. ([Metrics and dimensions](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-metrics-and-dimensions.html))
- **[apigw-client-faults]** A deployment that tightens auth or request validation can create a clean 4xx spike with no backend incident at all. (Inference)
- **[apigw-client-faults]** If route-level dimensions are absent, a global 4xx spike can hide that only one method or one resource changed behavior. (Inference)
- **[apigw-client-faults]** Treat client-fault ratios carefully during sharp traffic drops because a few repeated bad requests can dominate the percentage. (Inference)
- **[apigw-server-faults]** `5XXError` is the clearest outage signal in this family and should not be averaged away into a low-resolution widget. (Inference)
- **[apigw-server-faults]** Lambda proxy integrations can return both integration status and function status details; do not assume one field alone tells the full backend story. ([Access logging variables](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-variables-for-access-logging.html))
- **[apigw-server-faults]** Execution logs and access logs are independent; having one does not imply the other exists. ([Set up logging](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html))
- **[apigw-server-faults]** `$context.requestId` can be client-overridden, so request-level investigations should prefer `$context.extendedRequestId` when possible. ([Set up logging](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html))
- **[apigw-latency-path]** `Latency` includes the full API Gateway request path, while `IntegrationLatency` covers backend wait time; subtracting them is useful, but it is still an approximation of gateway overhead rather than a first-class AWS metric. (Inference)
- **[apigw-latency-path]** A flat `IntegrationLatency` with rising `Latency` points to gateway-side work, policy changes, or request transformation overhead, not necessarily a backend outage. (Inference)
- **[apigw-latency-path]** X-Ray tracing is optional and REST-only, so a missing trace view does not prove tracing is broken. ([Set up X-Ray](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-enabling-xray.html))
- **[apigw-latency-path]** If only average latency is present in Tsuga, tail latency incidents can be partially hidden. Stage 2 should verify whether percentiles are available on the discovered metric type. (Inference)
- **[apigw-cache-efficiency]** Cache metrics exist only when stage caching is enabled. Missing cache metrics do not mean zero cache usage; they usually mean the feature is off. ([Cache settings](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-caching.html))
- **[apigw-cache-efficiency]** Cache hit ratio only makes sense for cacheable methods and resources; mixing write routes into the denominator can make healthy caches look ineffective. (Inference)
- **[apigw-cache-efficiency]** A cache flush or deployment can produce a temporary miss spike without any backend regression. ([Cache settings](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-caching.html))
- **[apigw-cache-efficiency]** Canary traffic can use separate cache behavior, so cache hit changes during rollout may reflect split cache warming rather than broad regression. ([Canary release](https://docs.aws.amazon.com/apigateway/latest/developerguide/canary-release.html))
- **[apigw-traffic-demand, apigw-client-faults, apigw-server-faults]** The current bundle standardizes Count and error widgets on `sum + per-second` so every rate-style panel uses the same function choice. (Current bundle decision)
- **[apigw-server-faults, apigw-latency-path]** Data tracing is tempting during incidents, but AWS explicitly advises against using it in production because sensitive data can be logged. ([Set up logging](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html))

## Confirmed Tsuga prefixes
- `aws_apigateway_` - **CONFIRMED** (5/5 live metrics present in Tsuga: `aws_apigateway_count`, `aws_apigateway_4xx_error`, `aws_apigateway_5xx_error`, `aws_apigateway_latency`, `aws_apigateway_integration_latency`)

## Discovery status
Discovery complete in Stage 2.

- Confirmed live metric count: 5
- Confirmed live metrics: `aws_apigateway_count`, `aws_apigateway_4xx_error`, `aws_apigateway_5xx_error`, `aws_apigateway_latency`, `aws_apigateway_integration_latency`
- Cache metrics for stage caching are currently absent from this workspace.
- Confirmed context fields on all live metrics: `context.apiname`, `context.stage`, `context.method`, `context.resource`, `context.env`, `context.team`, `context.cloud.region`, `context.cloud.account.id`
- Live Tsuga metadata reports all five metrics as `summary` with `cumulative` temporality and `avg|sum|count|min|max` capabilities

## Top sources
- https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-metrics-and-dimensions.html - Canonical metric names, dimensions, and cache-metric semantics for the `AWS/ApiGateway` namespace.
- https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html - Primary source for execution logging, access logging, detailed metrics, and log-group behavior.
- https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-variables-for-access-logging.html - Canonical list of `$context` fields used to design Stage 4 access-log parsing.
- https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-caching.html - Defines stage caching behavior for API Gateway and why cache metrics require explicit stage caching.
- https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-enabling-xray.html - Explains stage-level X-Ray support and its operational prerequisites.
- https://docs.aws.amazon.com/xray/latest/devguide/xray-services-apigateway.html - Cross-check for API Gateway active tracing behavior and the REST-only caveat.
- https://docs.aws.amazon.com/apigateway/latest/developerguide/canary-release.html - Important for canary-specific logs, metrics interpretation, and cache behavior during rollout.
- https://docs.aws.amazon.com/apigateway/latest/developerguide/create-canary-deployment.html - Additional canary-stage operational detail used to frame rollout-related traffic shifts.
- https://docs.aws.amazon.com/apigateway/latest/developerguide/how-to-deploy-api.html - Deployment and stage lifecycle context that informs stage-based scoping and incident interpretation.
- https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-logging.html - Useful contrast source to keep the bundle honest about REST versus HTTP API logging surfaces.
