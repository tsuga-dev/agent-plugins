# AWS Lambda Integration Context Bundle

## Metadata
**Technology:** AWS Lambda  
**Deployment:** managed  
**Environment:** prod  
**Persona:** SRE Dev and ops  
**Telemetry preference:** mixed  
**Integration scope:** core service only  
**Primary use-case:** reliability and performance

## How to use this bundle
- Use `01_aws-lambda_metrics.csv` as the source of truth for Lambda metrics, safe aggregations, and grouping advice.
- Use `02_aws-lambda_dashboard_plan.yaml` for the section model, widgets, derived signals, triage chains, and playbooks.
- Use `03_aws-lambda_state.yaml` for machine-readable unknowns, field-mapping risks, and Stage 2 verification priorities.
- Use `04_aws-lambda_memory.md` for the human-readable handoff narrative and tradeoffs from Stage 1.
- Stage 2 will create `05_aws-lambda_metric_catalog.csv` as the discovered Tsuga inventory used for reconciliation and coverage checks.
- Stage 4 should read this file's `Log intelligence (Stage 4 handoff)` section and `03_aws-lambda_state.yaml` `log_intel` first before proposing any log route.

## What it is and what "good" looks like
### Confirmed by sources
AWS Lambda is AWS's managed function runtime: work arrives through synchronous requests, asynchronous invokes, or event source mappings, then Lambda schedules execution environments, enforces concurrency limits, and emits CloudWatch metrics for invocations, failures, latency, async delivery, and stream lag. Good operational posture means successful invocations dominate total demand, throttles stay rare, execution duration stays inside the workload's expected envelope, concurrency remains below account or reserved limits, and async or stream-backed sources do not accumulate age or lag. AWS documents the primary service metrics in the Lambda monitoring guide and separates concurrency, async, event source mapping, and performance signals explicitly.  
Sources: https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics-types.html, https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html, https://docs.aws.amazon.com/lambda/latest/dg/provisioned-concurrency.html

### Best-practice inference
- Incident shape 1: customer-facing invocation failures or throttles. Start with `invoke-health`, then move to `concurrency-throttling`.
- Incident shape 2: slow executions or runtime-tail growth without outright errors. Start with `latency-runtime`, then compare with `concurrency-throttling`.
- Incident shape 3: async or stream-trigger backlog growth. Start with `async-delivery` for async invokes or `stream-consumers` for queue/stream sources.
- Paging intent: use dashboards to split demand, code/runtime failure, concurrency exhaustion, and backlog amplification before touching service-specific downstream dashboards.

## Key concepts
### Glossary
| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| Invocation | A single request accepted by Lambda for execution | Baseline demand and denominator for failure ratios | invoke-health |
| Error | A function invocation that returns an error to Lambda | Direct customer-impact or workload-failure symptom | invoke-health |
| Throttle | An invocation rejected because concurrency capacity was unavailable | Capacity exhaustion symptom, often account or reserved-limit related | concurrency-throttling |
| Duration | Time spent running handler code, excluding some init semantics | Main execution latency signal | latency-runtime |
| Concurrent execution | Number of in-flight function executions | Primary saturation indicator | concurrency-throttling |
| Reserved concurrency | Capacity reserved for one function and removed from the shared pool | Isolation and blast-radius control | concurrency-throttling |
| Unreserved pool | Shared account concurrency left after reservations | Hidden coupling across functions | concurrency-throttling |
| Provisioned concurrency | Pre-initialized execution environments kept warm | Cold-start mitigation and latency control | provisioned-concurrency |
| Spillover | Invocations that exceeded provisioned capacity and fell back to on-demand | Loss of provisioned-latency guarantee | provisioned-concurrency |
| Async invocation | Invocation mode where Lambda queues work before executing it | Backlog and delayed-delivery risk | async-delivery |
| Async event age | Age of the oldest event in Lambda's async queue | Queueing pressure and delayed processing symptom | async-delivery |
| Destination failure | Failure to write async outcome to the configured destination | Post-processing reliability issue | async-delivery |
| Dead-letter error | Failure when sending a failed async event to DLQ | Loss of failure evidence and replay path | async-delivery |
| Recursive invocation drop | Invocations Lambda drops to break recursive loops | Severe logic or event wiring bug | invoke-health |
| Event source mapping | Lambda poller binding between a stream/queue and a function | Ownership point for iterator age and lag | stream-consumers |
| Iterator age | Age of the last processed record for stream-based sources | Consumer lag symptom for Kinesis/DynamoDB Streams | stream-consumers |
| Offset lag | Kafka offset lag observed by the mapping | Backlog depth for Kafka/MSK consumers | stream-consumers |
| Oversized record | Kafka record that exceeded Lambda event size constraints | Silent throughput loss if ignored | stream-consumers |
| Post-runtime extensions duration | Time spent after handler completion while extensions finish | Tail-latency drag from agents/extensions | latency-runtime |
| Execution version | Version or alias actually executed | Needed to separate rollout issues from global failure | latency-runtime |
| Function resource | Qualified function ARN or alias form exported with metrics | Stable identity for alias/version drilldown | concurrency-throttling |
| Log group | CloudWatch Logs stream `/aws/lambda/<function>` for Lambda execution logs | Main Stage 4 log route source | async-delivery |

### Concept Map
```text
Caller -> invokes -> Lambda function (why: demand enters execution path)
Async producer -> enqueues -> Lambda async queue (why: delivery can succeed before execution starts)
Stream or queue source -> feeds -> event source mapping (why: poller health determines backlog)
Event source mapping -> dispatches -> Lambda execution environment (why: iterator age rises when dispatch cannot keep up)
Lambda scheduler -> allocates -> concurrent executions (why: saturation happens before code runs)
Reserved concurrency -> carves out -> function-specific capacity (why: one hot function can be isolated)
Provisioned concurrency -> pre-warms -> execution environments (why: latency variability drops when capacity is ready)
Provisioned concurrency spillover -> indicates -> on-demand fallback (why: latency protection is being exceeded)
Invocation -> results in -> success or error (why: top-level health split)
Invocation demand -> competes for -> account concurrency pool (why: throttles can be cross-function, not local)
Function code -> emits -> duration distribution (why: runtime or dependency slowness surfaces here)
Extensions -> add tail time to -> post-runtime extensions duration (why: agents can slow completion without code change)
Async queue backlog -> increases -> async event age (why: delayed processing hurts timeliness)
Async failures -> attempt delivery to -> destination or DLQ (why: failure evidence must not be lost)
Kinesis or DynamoDB stream backlog -> increases -> iterator age (why: consumer is behind real time)
Kafka backlog -> increases -> offset lag (why: partition progress is behind head)
FunctionName + Resource + ExecutedVersion -> map to -> ownership and rollout slices (why: isolate alias/version regressions)
context.env + context.team -> map to -> operational ownership (why: global filtering and incident routing)
context.cloud.region + context.cloud.account.id -> map to -> blast radius (why: regional/account isolation)
CloudWatch Logs -> contain -> START/END/REPORT and application logs (why: Stage 4 can correlate metrics to failures)
```

### Entities and dimensions
| Entity/Dimension | Why useful | Cardinality risk | Safe top-N | Do NOT group-by guidance |
|---|---|---|---|---|
| `context.functionname` | Primary Lambda ownership key in Tsuga discovery | Low | 20 | Use as the first grouping level before any resource split |
| `context.resource` | Distinguishes alias-qualified or qualified resources | Medium | 15 | Avoid mixing with request IDs or log stream names |
| `context.cloud.account.id` | Multi-account blast-radius split | Low | 10 | Use for account-pool widgets, not per-function charts |
| `context.cloud.region` | Regional blast-radius isolation | Low | 12 | Prefer as global filter in single-region accounts |
| `context.env` | Environment segmentation | Low | 5 | Global filter only |
| `context.team` | Team ownership routing | Low | 10 | Global filter only |
| `context.cloud.provider` | Confirms provider family | Low | 3 | Rarely worth chart space |
| `context.resource` | Alias/resource drilldown for rollouts | Medium | 15 | Prefer after function grouping |
| `context.source` | Exporter provenance | Low | 5 | Debug-only; not an operational group-by |
| `context.unit` | Metric unit tag | Low | 3 | Never group by |
| Provisioned-concurrency dimensions | Not discovered in Tsuga | Unknown | Unknown | Keep the section gated instead of guessing |
| Stream mapping dimensions | Not discovered in Tsuga | Unknown | Unknown | Keep stream-consumer section gated instead of guessing |

### Tsuga field mapping
| Vendor/exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| FunctionName | `context.functionname` | Must-exist |
| Resource | `context.resource` | Optional but preferred |
| ExecutedVersion | `Unknown` | Optional and not discovered in Tsuga |
| EventSourceMappingUUID | `Unknown` | Optional and not discovered in Tsuga |
| AWS Region | `context.cloud.region` | Optional but preferred |
| AWS Account ID | `context.cloud.account.id` | Optional |
| Environment tag | `context.env` | Must-exist |
| Team tag | `context.team` | Must-exist |

#### Confirmed by sources
AWS documents FunctionName, Resource, ExecutedVersion, and EventSourceMappingUUID as Lambda metric dimensions, and the service semantics cleanly map them to function, version, and event-source slices that a dashboard needs.  
Sources: https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics-view.html, https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics-types.html

#### Best-practice inference
Stage 2 discovery confirmed `context.functionname` and `context.resource`, but did not discover version or event-source-mapping keys. Provisioned-concurrency and stream-consumer sections should stay explicitly gated until those richer dimensions appear.

## Golden signals
### Confirmed by sources
| Signal | Lambda meaning | Typical degradations | Best telemetry sources | What people page on | Section questions |
|---|---|---|---|---|---|
| Traffic | Accepted Lambda demand across sync, async, and event-source flows | traffic drop, demand spike, missing async intake | `Invocations`, `AsyncEventsReceived` | sudden invocation collapse or unexpected surge | Are functions receiving work? Is demand shape normal? |
| Errors | Code failures, delivery failures, throttles, recursive drops | bad deploy, dependency outage, concurrency exhaustion | `Errors`, `Throttles`, `DestinationDeliveryFailures`, `DeadLetterErrors`, `RecursiveInvocationsDropped` | errors or throttles rise against stable demand | Are failures from code, capacity, or delivery plumbing? |
| Latency | Execution time and backlog wait before processing | slow dependencies, heavy payloads, backlog accumulation | `Duration`, `PostRuntimeExtensionsDuration`, `AsyncEventAge`, `IteratorAge`, `OffsetLag` | latency tails or consumer lag rising | Is work slow to execute or just waiting to start? |
| Saturation | Capacity headroom for on-demand or provisioned concurrency | account limit pressure, insufficient provisioned warm pool | `ConcurrentExecutions`, `ProvisionedConcurrentExecutions`, `ProvisionedConcurrencyUtilization`, `ProvisionedConcurrencySpilloverInvocations` | concurrency and spillover rise before user-visible failure | Are we running out of execution capacity? |

### Best-practice inference
For Lambda, backlog age is often more actionable than raw invocation count during incidents because delayed work can hide behind normal request volume.

## Telemetry sources
### Confirmed by sources
| Source type | How collected | What it provides | Pros/cons | Common pitfalls |
|---|---|---|---|---|
| CloudWatch Lambda service metrics | Native AWS namespace `AWS/Lambda` | Canonical invocation, error, latency, async, and concurrency signals | Best source for service health; limited request context | Some metrics are feature-gated and absent unless the invocation mode is used |
| CloudWatch Logs for function log groups | `/aws/lambda/<function-name>` | START/END/REPORT lines plus app logs | Best source for request-level failure details | Log formats vary by runtime and advanced logging mode |
| Telemetry API to extensions | Runtime/extension API stream | Platform events and lifecycle timing | Strong for extension-aware diagnostics | Only available if extensions are present and configured |
| Lambda Insights | Optional enhanced monitoring extension | Memory, CPU, network, and system telemetry | Useful for deep runtime analysis | Not a guaranteed baseline; do not assume it exists |

### Best-practice inference
Treat service metrics as the baseline dashboard contract and keep Lambda Insights out of the core dashboard unless Stage 2 discovers the metrics.  
Sources: https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics-types.html, https://docs.aws.amazon.com/lambda/latest/dg/monitoring-cloudwatchlogs-logformat.html, https://docs.aws.amazon.com/lambda/latest/dg/runtimes-telemetry-api.html, https://docs.aws.amazon.com/lambda/latest/dg/monitoring-insights.html

## Log intelligence (Stage 4 handoff)
### Confirmed by sources
**Log sources matrix**

| Source | Access path | Typical format | Structured vs unstructured | Evidence |
|---|---|---|---|---|
| Function execution logs | CloudWatch Logs group `/aws/lambda/<function-name>` | START / END / REPORT platform lines + application output | Mixed | https://docs.aws.amazon.com/lambda/latest/dg/monitoring-cloudwatchlogs-logformat.html |
| Advanced logging controls | Same CloudWatch Logs destination | JSON platform and application logs when enabled for supported runtimes | Structured | https://docs.aws.amazon.com/lambda/latest/dg/monitoring-cloudwatchlogs-logformat.html |
| Telemetry API stream to extension | Local runtime API subscriber | JSON events such as platform start/report/runtime statuses | Structured | https://docs.aws.amazon.com/lambda/latest/dg/runtimes-telemetry-api.html |
| Lambda Insights logs | `/aws/lambda-insights` extension output | Embedded metrics and diagnostics records | Structured-ish | https://docs.aws.amazon.com/lambda/latest/dg/monitoring-insights.html |

**Known log formats**

1. Standard text platform lines  
   Sample line: `REPORT RequestId: 11111111-1111-1111-1111-111111111111 Duration: 933.59 ms Billed Duration: 934 ms Memory Size: 128 MB Max Memory Used: 94 MB Init Duration: 203.12 ms`  
   Shape notes: space-delimited key/value fragments, fixed uppercase prefix, optional `Init Duration`, request ID repeats across START/END/REPORT. Timestamp comes from CloudWatch event envelope, not the line body. Quoting is minimal.  
   Evidence: https://docs.aws.amazon.com/lambda/latest/dg/monitoring-cloudwatchlogs-logformat.html

2. JSON platform report lines with advanced logging controls  
   Sample shape: `{"time":"2024-03-13T18:56:24.046Z","type":"platform.report","record":{"requestId":"...","metrics":{"durationMs":..., "billedDurationMs":..., "memorySizeMB":..., "maxMemoryUsedMB":...}}}`  
   Shape notes: nested JSON with explicit event type and metrics object. Timestamp is embedded. Optional fields depend on runtime and logging settings.  
   Evidence: https://docs.aws.amazon.com/lambda/latest/dg/monitoring-cloudwatchlogs-logformat.html

**Candidate query filters for Stage 4**
- Precise: `context.log.group:/aws/lambda/* AND context.functionname:*`  
  Rationale: narrow to Lambda execution log groups while requiring function identity.  
  Risk: depends on Tsuga preserving the CloudWatch log group field.
- Broader fallback: `message:(START RequestId OR REPORT RequestId OR Task timed out OR Process exited before completing request)`  
  Rationale: catches standard Lambda platform lines even if log-group metadata is missing.  
  Risk: can match unrelated copied log text.

**Attribute mapping hints**

| Raw field | Suggested Tsuga key | Confidence | Notes |
|---|---|---|---|
| CloudWatch log group `/aws/lambda/<fn>` | `context.functionname` | High | Derive `<fn>` from suffix if explicit function field is absent |
| `RequestId` | `context.aws.lambda.request_id` | High | Shared across START/END/REPORT lines |
| `Duration` / `durationMs` | `context.aws.lambda.duration_ms` | High | Useful for log-to-metric spot checks |
| `Billed Duration` / `billedDurationMs` | `context.aws.lambda.billed_duration_ms` | Medium | Cost-adjacent but not a Stage 1 core metric |
| `Memory Size` | `context.aws.lambda.memory_size_mb` | Medium | Good for tuning and outlier analysis |
| `Max Memory Used` | `context.aws.lambda.max_memory_used_mb` | Medium | Useful for memory headroom correlation |
| JSON `type` | `context.aws.lambda.platform_event_type` | Medium | Important when parsing Telemetry API or JSON platform logs |

**Parsing risks**
- Standard text and JSON platform logs can coexist during rollout or across runtimes.
- REPORT lines have optional fields such as `Init Duration`, so rigid token counts will break.
- Application logs may include embedded JSON strings or multiline stack traces.
- Telemetry API event schemas differ from CloudWatch platform text lines; do not reuse one parser blindly.
- Timezone handling should use CloudWatch envelope timestamps when parsing classic text lines.

### Best-practice inference
If Tsuga already extracts function identity from CloudWatch metadata, prefer the discovered `context.functionname` field over parsing it from the log group string. If not, derive function name from `/aws/lambda/<function>` and keep request ID extraction separate from app-log parsing.

## Caveats and footguns
- **[invoke-health]** `Invocations` count accepted requests, not completed successes; pair with `Errors` and `Throttles` before declaring health. (https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics-types.html)
- **[invoke-health]** `Errors` does not cover throttled invokes because throttles are tracked separately. (https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics-types.html)
- **[invoke-health, concurrency-throttling]** `Throttles` can come from account concurrency exhaustion rather than one unhealthy function. (https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html)
- **[latency-runtime]** `Duration` excludes cold-start init time in older interpretations but user experience can still include init-related delay; keep deployment and init context in mind. (Inference)
- **[latency-runtime]** `PostRuntimeExtensionsDuration` can rise because of observability agents, not business logic regressions. (https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics-types.html)
- **[provisioned-concurrency]** `ProvisionedConcurrencyUtilization` is meaningless when provisioned concurrency is not configured. (https://docs.aws.amazon.com/lambda/latest/dg/provisioned-concurrency.html)
- **[provisioned-concurrency]** `ProvisionedConcurrencySpilloverInvocations` indicates loss of warm-capacity guarantees, not necessarily outright failure. (https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics-types.html)
- **[async-delivery]** Async metrics only appear for asynchronous invocation flows; zero data may mean the mode is unused, not broken. (https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics-types.html)
- **[async-delivery]** `AsyncEventAge` can rise while `Invocations` still look normal because the queue delays work before execution starts. (https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics-types.html)
- **[async-delivery]** `DestinationDeliveryFailures` and `DeadLetterErrors` are delivery-pipeline problems after execution, not function-code latency metrics. (https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics-types.html)
- **[invoke-health]** `RecursiveInvocationsDropped` is rare but severe; even a small non-zero value is usually a wiring defect, not normal noise. (https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics-types.html)
- **[stream-consumers]** `IteratorAge` is only relevant for Kinesis and DynamoDB Streams event source mappings. (https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics-types.html)
- **[stream-consumers]** `OffsetLag` and `OversizedRecordCount` are Kafka-specific; gate the section rather than showing zeros for non-Kafka consumers. (https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics-types.html)
- **[stream-consumers]** Grouping by partition, shard, or request ID would explode cardinality; prefer event source mapping UUID or function name. (Inference)
- **[concurrency-throttling]** `ConcurrentExecutions` is a level, not a rate; never apply `rate` to it. (https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics-types.html)
- **[concurrency-throttling]** Reserved concurrency can protect one function while starving the unreserved pool for others, so global account symptoms can hide behind healthy local charts. (https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html)
- **[latency-runtime]** Average duration can hide tail spikes; deep dive should prefer max or percentile-like views where the Tsuga metric family supports it. (Inference)
- **[invoke-health, latency-runtime]** ExecutedVersion matters during rollouts; aggregating all aliases together can dilute a bad canary or version-specific regression. (https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics-view.html)
- **[async-delivery, stream-consumers]** Backlog age is often the customer-visible symptom before error counts move. (Inference)
- **[invoke-health, async-delivery]** Standard log lines and JSON logs can coexist, so Stage 4 parsers must branch by shape instead of assuming one format. (https://docs.aws.amazon.com/lambda/latest/dg/monitoring-cloudwatchlogs-logformat.html)

## Confirmed Tsuga prefixes
- `aws_lambda*` — **CONFIRMED** (11 metrics present in Tsuga from `tools/tsuga_search_metrics.py '^aws_lambda.*'`)

## Discovery status
Discovery: completed in Stage 2.
- Metrics found: 11 total
- Confirmed against Stage 1 inventory: 11
- Missing from Stage 1 vendor expectations: 10 optional or disabled metrics
- Unexpected but useful metrics added: `aws_lambda_claimed_account_concurrency`, `aws_lambda_unreserved_concurrent_executions`
- Confirmed Tsuga function key: `context.functionname`
- Confirmed Tsuga resource key: `context.resource`

## Top sources
1. https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics-types.html  
   Why: canonical Lambda metric names, dimensions, and feature-gated metric families.
2. https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics-view.html  
   Why: metric dimension behavior and console viewing model for FunctionName, Resource, and ExecutedVersion.
3. https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html  
   Why: concurrency semantics, reserved concurrency behavior, and account-pool interactions.
4. https://docs.aws.amazon.com/lambda/latest/dg/provisioned-concurrency.html  
   Why: provisioned concurrency semantics and operational tradeoffs.
5. https://docs.aws.amazon.com/lambda/latest/dg/monitoring-cloudwatchlogs-logformat.html  
   Why: official Lambda log formats for standard and JSON modes.
6. https://docs.aws.amazon.com/lambda/latest/dg/runtimes-telemetry-api.html  
   Why: platform telemetry event model for extension-aware logging.
7. https://docs.aws.amazon.com/lambda/latest/dg/monitoring-insights.html  
   Why: optional Lambda Insights telemetry and why it should be gated.
8. https://docs.aws.amazon.com/lambda/latest/dg/invocation-async.html  
   Why: async invocation semantics and why age/delivery metrics matter operationally.
9. https://docs.aws.amazon.com/lambda/latest/dg/invocation-recursion.html  
   Why: recursive loop detection and drop semantics.
10. https://docs.aws.amazon.com/lambda/latest/dg/with-msk-process.html  
   Why: Kafka-backed Lambda consumption context for offset lag and consumer backlog interpretation.
