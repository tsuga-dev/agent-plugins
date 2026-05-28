# AWS Firehose Integration Context Bundle

## Metadata

**Technology:** Amazon Data Firehose (formerly Amazon Kinesis Data Firehose)
**Deployment:** managed
**Environment:** prod
**Persona:** SRE Dev and ops
**Telemetry preference:** Prometheus CloudWatch Exporter (CONFIRMED — Stage 2 discovery)
**Integration scope:** core service only
**Primary use-case:** reliability and performance
**Destination (this org):** HTTP endpoint (CONFIRMED — DeliveryToS3.* metrics absent; delivery_to_http_endpoint_* metrics present)
**Stage 2 discovery:** COMPLETED 2026-03-16

---

## How to use this bundle

- `01_aws-firehose_metrics.csv` — source-of-truth for all metric names, units, temporality, safe aggregations, and group-bys. Use this as the widget data layer.
- `02_aws-firehose_dashboard_plan.yaml` — dashboard blueprint: sections, widgets, derived signals, explanation notes, triage chains, and playbooks.
- `03_aws-firehose_state.yaml` — machine-readable stage status, confirmed/inferred namespace prefixes, assumptions, and the unknowns list that Stage 2 must resolve.
- `04_aws-firehose_memory.md` — human-readable Stage 1 summary, key tradeoffs, and Stage 2 priority checks.
- Stage 2 will create `05_aws-firehose_metric_catalog.csv` — discovered metric inventory with attribute keys and AI-curated descriptions for reconciliation and coverage checks.
- Stage 4: read "Log intelligence (Stage 4 handoff)" section below and `03_aws-firehose_state.yaml` → `log_intel` before designing log routes.

---

## What it is and what "good" looks like

Amazon Data Firehose is a fully managed streaming ETL service that reliably ingests and delivers streaming data to storage and analytics destinations (Amazon S3, Redshift, OpenSearch Service, OpenSearch Serverless, Splunk, Snowflake, HTTP endpoints, and custom destinations). It handles buffering, compression, encryption, format conversion, and optional Lambda transformation. Producers write to a Delivery Stream via PutRecord/PutRecordBatch API calls or connect Kinesis Data Streams / MSK (Kafka) as a managed source.

**What "good" looks like (this org — HTTP endpoint destination, Prometheus CloudWatch Exporter):**
- `aws_firehose_delivery_to_http_endpoint_data_freshness` (Max) stays flat and low (well below buffer interval × 2 — typically below 120s for a 60s buffer)
- `aws_firehose_delivery_to_http_endpoint_processed_bytes` ≈ `aws_firehose_delivery_to_http_endpoint_bytes` (HTTP Endpoint Retry Rate near 0%)
- `aws_firehose_throttled_records` = 0 (no records rejected at ingestion — critical: throttled records are silently dropped)
- `aws_firehose_incoming_records` tracks expected application throughput (flat or predictable growth)
- `aws_firehose_failed_validation_records` = 0 (no MSK/Kafka schema validation failures)
- No KMS error metrics non-zero (all four kms_key_* metrics stay at 0)
- `aws_firehose_put_record_batch_latency` stays low (< 500ms average under normal load)

**Paging intent (symptom-level only):**
- Page if `aws_firehose_delivery_to_http_endpoint_data_freshness` (Max) climbs significantly above the buffer interval — records are not reaching the HTTP endpoint
- Page if `aws_firehose_throttled_records` is sustained non-zero — data is being permanently lost (not retried)
- Page if any KMS error metric is non-zero — all delivery is blocked until KMS is fixed
- Page if `aws_firehose_failed_validation_records` spikes — MSK/Kafka records are being silently discarded

**Top 3 incident shapes (updated for HTTP endpoint destination):**

1. **Delivery stall** (`aws_firehose_delivery_to_http_endpoint_data_freshness` climbing, HTTP Endpoint Retry Rate rising) → Start at "Delivery Freshness" section; check HTTP endpoint availability and response codes in CloudWatch error logs (`/aws/kinesisfirehose/{stream-name}`). KMS errors take priority — check Total KMS Errors first.
2. **Ingestion throttling** (`aws_firehose_throttled_records` non-zero) → Start at "Ingestion" section; notify producers immediately (data loss in progress); file AWS Service Quotas increase. Note: BytesPerSecondLimit/RecordsPerSecondLimit not exported by org's collector — use Throttle Rate as the primary saturation signal.
3. **MSK/Kafka schema validation failure** (`aws_firehose_failed_validation_records` non-zero) → Check `context.sourcepartitionid` in the Failed Validation widget to identify the failing Kafka partition; coordinate with producer team on schema alignment. Lambda transformation failures are not applicable (Lambda not enabled on this org's streams).

**Confirmed by sources:**
- DataFreshness as primary operational signal: https://docs.aws.amazon.com/firehose/latest/dev/monitoring-with-cloudwatch-metrics.html
- KMS errors as immediate delivery-blocker: https://docs.aws.amazon.com/firehose/latest/dev/encryption.html
- ThrottledRecords as silent data-loss indicator: AWS Firehose Developer Guide, Monitoring section

**Best-practice inference:**
- "Good DataFreshness" threshold = buffer interval × retry buffer (inferred from standard Firehose buffer configuration patterns)
- Lambda 5-minute hard timeout as the critical alert threshold (inferred from AWS Lambda limits documentation)

---

## Key concepts

### Glossary

| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| Delivery Stream | The named Firehose resource — a configured pipeline from source to destination with buffering, transformation, and compression settings. | Primary group-by dimension in all widgets. One stream = one pipeline. | All sections |
| DataFreshness | The age in seconds of the oldest record currently held by Firehose that has not yet been delivered. | THE primary SRE signal. Rising DataFreshness = data backlog. Use Maximum stat for worst-case. | delivery-freshness |
| Buffer Interval | Configurable time limit (60s–900s) after which Firehose flushes buffered data to the destination, even if the buffer size is not reached. | Baseline for DataFreshness. Healthy DataFreshness ≤ buffer interval × 2. | delivery-freshness |
| Buffer Size | Configurable data size limit (varies by destination) that triggers a flush when reached before the buffer interval. | Affects how frequently S3 objects are created. Smaller = more frequent small objects. | delivery-throughput |
| Direct PUT | Data ingestion method where producers call PutRecord/PutRecordBatch API directly on the Delivery Stream. | Source for IncomingRecords/IncomingBytes. Throttling occurs here if limits exceeded. | ingestion |
| Kinesis Data Streams (source) | Optional: use a Kinesis Data Stream as the Firehose source instead of Direct PUT. Firehose reads from the stream. | Adds KinesisMillisBehindLatest as a separate freshness signal. Throttling at GetRecords level. | ingestion |
| MSK (Kafka) source | Optional: use an Amazon MSK Kafka cluster as the Firehose source. | Adds KafkaOffsetLag as freshness signal. Similar pattern to Kinesis source. | ingestion |
| ThrottledRecords | Records rejected by Firehose because ingestion rate exceeded service limits. These records are NOT retried — they are silently dropped by the service. | Non-zero = data loss. The producer must retry dropped records itself. Critical to alert on. | ingestion |
| BytesPerSecondLimit | Current service-side throughput limit for the delivery stream (bytes/s before throttling occurs). | Compare against IncomingBytes rate to see headroom. Approaching limit = imminent throttling. | ingestion |
| RecordsPerSecondLimit | Current service-side records/sec limit for the delivery stream. | Similar to BytesPerSecondLimit but for record count. | ingestion |
| Lambda Transformation | Optional feature: Firehose invokes an AWS Lambda function to transform each record batch before delivery. | Adds ExecuteProcessing.* and SucceedProcessing.* metrics. Duration limit = 5 minutes hard. | transformation |
| ExecuteProcessing.Success | Ratio (0–1) of successful Lambda invocations to total invocations over the period. Average stat gives the success rate. | Drop below 1.0 = Lambda transformation errors. Key signal for transformation health. | transformation |
| Format Conversion | Optional feature: Firehose converts record format from JSON to Apache Parquet or ORC before S3 delivery. Requires a Glue Data Catalog schema. | Adds FailedConversion.* and SucceedConversion.* metrics. Failures = records routed to error S3 prefix. | transformation |
| Dynamic Partitioning | Optional feature: Firehose routes records to different S3 prefixes based on data content (using JQ or inline parsing). | Adds PartitionCount and PartitionCountExceeded metrics. Hard limit: 500 active partitions. | backup-limits |
| DeliveryToS3.Success | Count (Sum) or ratio (Average 0–1) of successful S3 PUT commands. Use Average stat to get success rate. | Average near 1.0 = healthy. Dropping = delivery failures. Use Sum to count absolute PUT successes. | delivery-errors |
| Backup to S3 | When Lambda transformation or Redshift delivery is enabled, Firehose can write source records to a backup S3 bucket. BackupToS3.* metrics track this. | BackupToS3.DataFreshness is a secondary freshness signal for transformation pipelines. | backup-limits |
| KMS Encryption | Optional: Firehose can encrypt data at rest using AWS KMS. KMS errors immediately block all delivery. | KMS* metrics: any non-zero value = all delivery blocked. Highest severity failure. | delivery-errors |
| Error Output S3 Prefix | When delivery fails after all retries (or format conversion fails), records are written to a special error prefix in S3. These records need manual reprocessing. | Not directly metriced — you discover this via CloudWatch error logs and DataFreshness. | delivery-errors |
| Retry Duration | Configurable window (0–7200s) during which Firehose retries failed deliveries before routing to the error prefix. | Affects how long DataFreshness will climb before records are abandoned to the error prefix. | delivery-freshness |
| PutRecordBatch | Bulk PUT API call: up to 500 records or 4 MiB per call. More efficient than PutRecord for high-throughput producers. | Source for IncomingPutRequests metric. Throttled at same limits as PutRecord. | ingestion |
| Delivery Stream ARN | Globally unique AWS identifier for the stream. | Used as resource identifier in IAM policies and CloudWatch dimensions. | — |
| KinesisMillisBehindLatest | When Kinesis Data Streams is the source: age (ms) of the last-read Firehose record relative to the newest record in the Kinesis stream. | Critical freshness signal for Kinesis-sourced streams. Rising = Firehose falling behind. | ingestion |
| JQ Processing | When dynamic partitioning is enabled, Firehose uses JQ expressions to extract partition keys from records. JQProcessing.Duration tracks execution time. | Slow JQ = slower partitioning, potential DataFreshness impact. | backup-limits |
| Redshift COPY | When Redshift is the destination, Firehose buffers to an intermediate S3 location then issues a Redshift COPY command. DeliveryToRedshift.Success tracks success of these COPY commands. | COPY failures → DataFreshness climbs + BackupToS3.DataFreshness climbs. | delivery-errors |
| ObjectCount | S3 objects delivered per period (dynamic partitioning only). Higher partition count = more objects per buffer flush. | Rising ObjectCount with flat DataFreshness = healthy high-partition throughput. | backup-limits |

---

### Concept Map

```
Producer (app/service) -> PutRecord/PutRecordBatch API -> Delivery Stream (ingestion layer)
Producer -> Kinesis Data Stream (source) -> Delivery Stream reads via GetRecords (Kinesis source mode)
Producer -> MSK/Kafka (source) -> Delivery Stream reads via Kafka consumer (MSK source mode)

Delivery Stream -> buffer (size/interval threshold) -> triggers flush
Delivery Stream ingestion -> ThrottledRecords if IncomingBytes > BytesPerSecondLimit (why: service limits; throttled records are silently dropped)
Delivery Stream -> optionally invokes Lambda (transformation layer) -> ExecuteProcessing.* metrics
Lambda transformation -> ExecuteProcessing.Duration approaches 5-min limit -> timeout failure path
Lambda failure -> records can route to error prefix or delivery blocked (why: transformation required)

Delivery Stream buffer -> DeliveryToS3 (primary S3 destination)
DeliveryToS3 failure -> retry window (configurable) -> retry exhausted -> error prefix in S3
DeliveryToS3 delivery blocked -> DataFreshness climbs -> oldest record age grows
DataFreshness climbing -> leading indicator of all delivery problems (why: any blocker increases record age)

Delivery Stream -> optionally BackupToS3 (when Lambda transform enabled or Redshift destination)
BackupToS3 failure -> BackupToS3.DataFreshness climbs (why: backup independently buffered)

Delivery Stream -> optionally format conversion (JSON→Parquet/ORC via Glue schema)
Format conversion failure -> FailedConversion.Records -> records to error prefix (why: schema mismatch)

Delivery Stream -> optionally Dynamic Partitioning -> PartitionCount (hard limit 500)
PartitionCount approaching 500 -> PartitionCountExceeded=1 -> overflow records to default prefix (why: partition limit breached)

KMS encryption enabled -> KMS key must be accessible for all delivery operations
KMS key problem -> KMSKey* metrics non-zero -> ALL delivery blocked immediately (why: encryption required for every write)

Delivery Stream -> CloudWatch error logs -> /aws/kinesisfirehose/{stream-name}
CloudWatch error logs -> DestinationDelivery stream (destination errors)
CloudWatch error logs -> BackupDelivery stream (backup S3 errors, if backup enabled)
```

---

### Entities and dimensions

| Entity | Why useful | Cardinality risk | Safe top-N | Notes |
|---|---|---|---|---|
| `DeliveryStreamName` | Primary triage dimension — every metric belongs to one stream. Breakdown by stream reveals which pipeline is affected. | Medium (10s–100s of streams per org) | 10 | Safe for group-by in all sections |
| `context.cloud.region` | Delivery to S3/Redshift is region-scoped; cross-region delivery adds latency. Useful for multi-region setups. | Low (AWS regions in use) | 10 | Safe for group-by |
| `context.cloud.account.id` | Multi-account orgs need to separate streams by account. Critical for cost attribution. | Low (few accounts per org) | 10 | Safe for group-by |
| `context.env` | Separate prod/staging/dev streams — baseline freshness and throughput differ. | Low | 5 | Always include as global filter |
| `context.team` | Different teams own different pipelines. Team-level aggregation for SLO tracking. | Low | 10 | Always include as global filter |
| Destination type | S3 / Redshift / OpenSearch / Splunk / Snowflake / HTTP — different SLA characteristics. | Very low (fixed per stream) | N/A | Not a CloudWatch dimension; encode in stream naming convention or use separate dashboard filters |
| Source type | Direct PUT / Kinesis / MSK — changes which metrics are available. | Very low | N/A | Not a CloudWatch dimension; changes available metrics |
| Lambda function name | If Lambda transformation enabled, function ARN is a Lambda-level dimension, not a Firehose dimension. | Low–medium | 10 | Not in Firehose CloudWatch namespace — look in AWS/Lambda namespace |
| S3 bucket | Delivery destination bucket — not a CloudWatch dimension for Firehose metrics. | N/A | N/A | Do NOT group by S3 bucket in Firehose metrics; track via S3 metrics separately |
| AWS account + region | Full stream identity is account + region + stream name | Low | N/A | Compound key for multi-org setups |
| Partition key (dynamic partitioning) | Partition routing key — not a CloudWatch dimension | N/A | N/A | Track via PartitionCount, not by key value |
| Error code | Delivery error codes from CloudWatch Logs | Low–medium | N/A | Only available in log data, not metrics namespace |
| Retry attempt | Retry attempt number — not exposed as a CloudWatch dimension | N/A | N/A | Not available as a metric dimension |

---

### Tsuga field mapping

| Vendor/exporter dimension | Confirmed context.* key | Must-exist vs optional | Stage 2 status |
|---|---|---|---|
| `DeliveryStreamName` (CloudWatch dimension) | `context.deliverystreamname` | Must-exist (primary group-by) | **CONFIRMED** via get-metric attribute inspection |
| MSK/Kafka source partition | `context.sourcepartitionid` | Optional (only on failed_validation_records) | **CONFIRMED** present on aws_firehose_failed_validation_records |
| AWS Account ID (implicit in CW data) | `context.cloud.account.id` | Must-exist for multi-account | Confirmed in catalog |
| AWS Region (implicit in CW data) | `context.cloud.region` | Must-exist for multi-region | Confirmed in catalog |
| — (from `.env`) | `context.env` | Must-exist (global filter) | Confirmed in catalog |
| — (from `.env`) | `context.team` | Must-exist (global filter) | Confirmed in catalog |

**Stage 2 correction:** The assumed attribute key `context.aws.firehose.delivery_stream_name` was incorrect. The actual Tsuga attribute key is **`context.deliverystreamname`** (snake_case, no OTel aws prefix — consistent with Prometheus CloudWatch Exporter label conventions). All widget group_by fields updated in `02_aws-firehose_dashboard_plan.yaml`.

---

## Golden signals

### Traffic — How much data is flowing?

**For Firehose:** Traffic = ingestion rate (records and bytes entering the delivery stream).
- **Why it matters:** Unexpected traffic drops or spikes are the first sign of producer failure or runaway event generation.
- **Typical causes of degradation:** Producer outage (traffic drops to zero), retry storm (traffic spikes), application deployment (traffic pattern change).
- **Best telemetry (confirmed):** `aws_firehose_incoming_records` (sum + rate), `aws_firehose_put_record_batch_bytes` (sum + rate, proxy for IncomingBytes — `IncomingBytes` not exported by this org's collector).
- **What people page on:** Traffic drops to zero while expected producers are running (producer failure), or sudden spike combined with throttling.
- **Section questions:** "Is data flowing in at the expected rate?" / "Are producers hitting ingestion limits?"

**Confirmed by sources:** https://docs.aws.amazon.com/firehose/latest/dev/monitoring-with-cloudwatch-metrics.html
**Best-practice inference:** Traffic → zero combined with DataFreshness staying flat (not rising) indicates no new data, not a delivery block.

---

### Errors — Are delivery failures occurring?

**For Firehose:** Errors = delivery failures (S3 PUT failures, Lambda invocation failures, format conversion failures, KMS errors, throttled records).
- **Why it matters:** Failed deliveries result in data loss (records routed to error S3 prefix after retry exhaustion). ThrottledRecords at ingestion are silently lost.
- **Typical causes:** IAM permission issues (S3 bucket policy, Lambda execution role), destination unavailability, Lambda function bugs, schema mismatches, KMS key revocation.
- **Best telemetry (confirmed):** `aws_firehose_throttled_records` (sum + rate), KMS error metrics (`aws_firehose_kms_key_*`), `aws_firehose_failed_validation_records` (sum + rate). Note: `DeliveryToS3.Success` absent (S3 not destination); use HTTP Endpoint Retry Rate signal (processed_bytes vs delivery_bytes) for endpoint-level error detection. Lambda and format conversion metrics absent (features not enabled).
- **What people page on:** Success rate dropping, ThrottledRecords non-zero (data loss), any KMS error.
- **Section questions:** "Are delivery failures occurring?" / "Are records being lost to the error prefix?"

**Confirmed by sources:** ThrottledRecords data loss behavior documented at https://docs.aws.amazon.com/firehose/latest/dev/monitoring-with-cloudwatch-metrics.html
**Best-practice inference:** KMS errors blocking all delivery; IAM failures as leading cause of permission errors.

---

### Latency / Freshness — Is data being delivered on time?

**For Firehose:** Latency = DataFreshness — the age of the oldest undelivered record.
- **Why it matters for Firehose (not generic latency):** DataFreshness is the canonical end-to-end delivery lag signal. A rising freshness value means data is piling up and not reaching its destination. Unlike traditional request latency, this is the "queue depth clock" — it tells you how stale the destination is.
- **Why `DataFreshness` beats other signals:** It's a leading indicator of ALL delivery problems (permission errors, destination issues, Lambda failures, retry exhaustion) before records are lost.
- **Typical causes of degradation:** Destination unreachable (IAM, network, destination outage), Lambda transformation failures or timeouts, retry loops from transient errors, KMS key issues.
- **Best telemetry (confirmed):** `aws_firehose_delivery_to_http_endpoint_data_freshness` (max aggregation) — always use Maximum stat for worst-case SLO tracking. This org uses HTTP endpoint; the S3 variant (`DeliveryToS3.DataFreshness`) is absent.
- **What people page on:** DataFreshness exceeds configured retry duration (data is about to be abandoned to error prefix).
- **Section questions:** "Is data reaching the destination on time?" / "What is the age of the oldest undelivered record?"

**Confirmed by sources:** DataFreshness as primary Firehose operational signal: https://docs.aws.amazon.com/firehose/latest/dev/monitoring-with-cloudwatch-metrics.html
**Best-practice inference:** Alert threshold = retry duration (default 300s); severe = DataFreshness > 900s.

---

### Saturation — Are we approaching service limits?

**For Firehose:** Saturation = proximity to ingestion limits + delivery stream resource utilization.
- **Why it matters:** ThrottledRecords = data is already being lost. `BytesPerSecondLimit` and `RecordsPerSecondLimit` show headroom before throttling starts.
- **Typical causes:** Traffic growth without limit increase requests, uncontrolled retry storm from a broken producer, poorly configured dynamic partitioning hitting the 500-partition limit.
- **Best telemetry (confirmed):** `aws_firehose_throttled_records` (sum + rate) — the only available saturation signal (Throttle Rate % derived signal). `BytesPerSecondLimit`, `RecordsPerSecondLimit`, and `PartitionCount` are not exported by this org's collector and are absent from Tsuga.
- **What people page on:** ThrottledRecords sustained non-zero, PartitionCountExceeded = 1.
- **Section questions:** "Are service limits being hit?" / "How much headroom remains before throttling?"

**Confirmed by sources:** Throttling behavior at https://docs.aws.amazon.com/firehose/latest/dev/limits.html
**Best-practice inference:** Partition limit of 500 from service limits documentation.

---

## Telemetry sources

| Source type | How collected | What it provides | Pros/Cons | Common pitfalls |
|---|---|---|---|---|
| **CloudWatch Metric Streams (recommended)** | CloudWatch Metric Streams → OpenTelemetry/Firehose → Tsuga (OTel OTLP ingestion). Metrics are pushed in near real-time (sub-1-minute). | All AWS/Firehose metrics with full dimension metadata. OTel format: metric names as `amazonaws.com/AWS/Firehose/{MetricName}`, type=SUMMARY. | Pro: near real-time, low latency, no polling. Con: Metric Stream itself requires setup; metrics arrive as OTel SUMMARY type (sum, count, min, max quantiles available). | SUMMARY type requires careful aggregation selection in Tsuga. The `sum` stat quantile=0 gives min, quantile=1 gives max. CloudWatch rollup period is 1 minute. |
| **Prometheus CloudWatch Exporter** | Prometheus scrape of `cloudwatch_exporter` → Tsuga Prometheus receiver | Same CloudWatch metrics as above, but in Prometheus format: `aws_firehose_{metric_snake_case}_{statistic}` (e.g., `aws_firehose_incoming_bytes_sum`). Type=gauge. | Pro: familiar Prometheus semantics, per-statistic metrics. Con: polling introduces 1-minute+ lag; adds Prometheus infrastructure overhead. | CloudWatch API polling incurs costs. Metrics are pre-aggregated gauges, not raw events — do NOT use `rate()` on the `_sum` suffix metrics as if they were Prometheus counters. |
| **AWS CloudWatch Console** | Manual dashboard (not Tsuga) | All metrics with visual charts | Pro: zero setup. Con: not for programmatic alerting or cross-service correlation. | Monitoring gaps between CloudWatch console and Tsuga — different sampling/rendering. |

**Optional features that change available metrics:**
- Lambda transformation enabled → adds `ExecuteProcessing.*`, `SucceedProcessing.*`
- Format conversion enabled → adds `SucceedConversion.*`, `FailedConversion.*`
- Dynamic partitioning enabled → adds `PartitionCount`, `PartitionCountExceeded`, `JQProcessing.Duration`, `ActivePartitionsLimit`
- Kinesis Data Streams source → adds `DataReadFromKinesisStream.*`, `KinesisMillisBehindLatest`, `ThrottledGetRecords`, `ThrottledGetShardIterator`
- MSK (Kafka) source → adds `DataReadFromSource.*`, `KafkaOffsetLag`, `SourceThrottled.Delay`
- KMS encryption enabled → adds `KMSKeyAccessDenied`, `KMSKeyDisabled`, `KMSKeyInvalidState`, `KMSKeyNotFound`
- S3 Backup enabled → adds `BackupToS3.*`
- CloudWatch Logs source with decompression → adds `OutputDecompressedBytes.*`, `OutputDecompressedRecords.*`
- Snowflake destination → adds `DeliveryToSnowflake.*`

**What "no data" usually means per source:**
- `IncomingBytes/Records` = 0: no producers are writing to the stream (producer outage, stream not being used, or wrong stream name selected)
- `DeliveryToS3.*` missing entirely: stream may not have S3 as a destination, or metric collection is not enabled
- `ExecuteProcessing.*` missing: Lambda transformation not enabled for this stream
- `FailedConversion.*` missing: format conversion not enabled for this stream
- `KMS*` metrics missing: SSE with KMS not enabled

**Confirmed by sources:** Metric Streams encoding as SUMMARY: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-metric-streams-formats-opentelemetry-translation.html
**Best-practice inference:** Prometheus CloudWatch Exporter gauge behavior described as industry convention.

---

## Log intelligence (Stage 4 handoff)

### Confirmed by sources

**Log sources matrix:**

| Source | Access path | Typical format | Structured vs unstructured | Evidence |
|---|---|---|---|---|
| Firehose error logs | CloudWatch Logs group: `/aws/kinesisfirehose/{delivery-stream-name}` | JSON-like error objects (error code + message + action) | Semi-structured: error code dot-notation, free-text message | https://docs.aws.amazon.com/firehose/latest/dev/troubleshooting.html |
| Log stream: DestinationDelivery | Within above log group — destination delivery errors | Error code + message + timestamp | Semi-structured | AWS Firehose Developer Guide |
| Log stream: BackupDelivery | Within above log group — S3 backup errors (if backup enabled) | Same as DestinationDelivery | Semi-structured | AWS Firehose Developer Guide |

**Known log formats (confirmed):**

Firehose error logs in CloudWatch Logs are NOT standard structured JSON. Each log event is a text record containing:
```
{
    "deliveryStreamARN": "arn:aws:firehose:us-east-1:123456789012:deliverystream/my-stream",
    "destination": "arn:aws:s3:::my-bucket",
    "deliveryStreamVersionId": 1,
    "message": "The S3 bucket is not accessible. Ensure that the bucket exists and the role has access to the bucket.",
    "errorCode": "S3.AccessDenied",
    "processor": "s3-destination"
}
```
- Timestamp: provided by CloudWatch Logs (not embedded in the message)
- Each log event = one error occurrence
- Error code format: `Service.ErrorType` (e.g., `S3.AccessDenied`, `Lambda.InvokeLimitExceeded`)
- Messages are English prose (variable length, no fixed delimiter)

**Candidate query filters for Stage 4:**

- **Precise:** `context.aws.log_group:/aws/kinesisfirehose/` — targets Firehose error log groups only. Risk: low (all Firehose error logs in the org, filtered by stream name if needed).
- **Broader fallback:** `context.aws.log_group:kinesisfirehose` — catches variations in log group naming. Risk: may match other Kinesis-related log groups.

**Attribute mapping hints:**

| Raw field | Suggested Tsuga key | Confidence | Notes |
|---|---|---|---|
| `errorCode` | `error.type` | High | Standard OTel attribute for error category |
| `deliveryStreamARN` | `aws.firehose.delivery_stream_arn` | Medium | Follows OTel AWS semconv pattern |
| `destination` | `aws.firehose.destination` | Medium | ARN of the destination resource |
| `message` | `message` (body) | High | Log message field |
| `processor` | `aws.firehose.processor` | Low | Internal processor name; low operational value |
| CloudWatch log group name | `context.aws.log_group` | High | Standard Tsuga/OTel CloudWatch Log attribute |
| CloudWatch stream name | `context.aws.log_stream` | High | Standard Tsuga/OTel CloudWatch Log attribute |

**Parsing risks:**
- Firehose samples error logs at high failure rates — you will NOT see every error in CloudWatch Logs during large-scale failures.
- The log format is AWS-internal and can change between regions or service versions without notice.
- `deliveryStreamARN` may be split across log entries (truncation possible for very long ARNs in some edge cases).
- CloudWatch Logs logging is opt-in (must be configured on the stream) — logs may simply not exist for streams that didn't enable it.
- No per-record delivery log — only error events. Normal successful deliveries produce no log output.

### Best-practice inference

- Error code (`errorCode`) is the highest-value extracted field for alerting on log routes — it disambiguates the failure type.
- Parsing `deliveryStreamARN` to extract stream name (last segment after `/`) gives a higher-cardinality but more useful attribute than the full ARN.
- Lambda transformation errors will also appear in `/aws/lambda/{function-name}` log groups — NOT in the Firehose log group. A separate log route for Lambda may be needed to capture transformation errors.

---

## Caveats and footguns

- **[ingestion]** `ThrottledRecords` non-zero = data is already lost. Firehose does NOT retry throttled records — the producer must retry on its own. This is unlike most retry semantics. (Confirmed: https://docs.aws.amazon.com/firehose/latest/dev/monitoring-with-cloudwatch-metrics.html)
- **[ingestion]** `IncomingBytes` and `IncomingRecords` exclude throttled records — they count only successfully accepted records. So a drop in `IncomingRecords` could mean either producers slowed down OR throttling is happening. Always check `ThrottledRecords` alongside. (Confirmed: AWS documentation)
- **[delivery-freshness]** Always use **Maximum** statistic for `DataFreshness` alerting, not Average. Average hides worst-case records; a single stuck record can cause data loss without triggering an Average-based alert. (Best-practice inference)
- **[delivery-freshness]** DataFreshness will naturally be near the buffer interval under normal conditions — it's not zero even when healthy. "Alarming" starts when freshness exceeds buffer interval × (1 + retry count factor). (Confirmed: AWS documentation behavior description)
- **[delivery-freshness]** When DataFreshness drops sharply to zero, it may mean the stream is idle (no records in flight), not that delivery improved. Always correlate with `IncomingRecords`. (Best-practice inference)
- **[delivery-throughput, delivery-freshness]** `DeliveryToS3.Records` is the number of records in each S3 PUT, NOT the number of successful PUTs. With batching, a single PUT delivers many records. Do not compare `IncomingRecords` to `DeliveryToS3.Records` within short windows — they will not match due to buffering. (Confirmed: AWS documentation)
- **[delivery-errors]** `DeliveryToS3.Success` has two valid interpretations depending on the CloudWatch statistic used: **Sum** = count of successful S3 PUT operations; **Average** = success rate (0–1). Always clarify which stat you're using. Use Average for ratio-based signals; Sum for absolute operation counts. (Confirmed: AWS CloudWatch documentation)
- **[transformation]** Lambda transformation has a **5-minute hard timeout** per batch. If `ExecuteProcessing.Duration` (Max) approaches 300,000 ms, delivery will fail. There is no graceful partial failure — the entire batch fails. (Confirmed: AWS Lambda limits documentation)
- **[transformation]** Lambda transformation failures can cause `DataFreshness` to climb even when the destination is healthy — the bottleneck is in the transformation layer, not delivery. Check `ExecuteProcessing.Success` when DataFreshness rises unexpectedly. (Best-practice inference)
- **[transformation]** `SucceedProcessing.Records` and `SucceedProcessing.Bytes` only count records that successfully passed through Lambda. Records that Lambda returned with `Dropped` status are NOT counted here and are silently excluded from delivery. (Confirmed: AWS documentation)
- **[delivery-errors]** KMS key errors (`KMSKeyAccessDenied`, etc.) block ALL delivery immediately — not just for new records, but for any buffered data that requires encryption before writing. These must be treated as P1 incidents. (Confirmed: https://docs.aws.amazon.com/firehose/latest/dev/encryption.html)
- **[transformation]** Format conversion (JSON → Parquet/ORC) requires a Glue Data Catalog table schema. If the schema evolves and records don't match, `FailedConversion.Records` will rise. Failed records go to a `processing-failed/` error prefix in S3 — they are NOT retried. (Confirmed: AWS documentation)
- **[backup-limits]** `PartitionCount` approaching 500 means `PartitionCountExceeded` = 1, causing records to overflow to the default S3 prefix. This is a soft data routing failure — data is not lost but is incorrectly partitioned, which breaks downstream assumptions. (Confirmed: service limits documentation)
- **[ingestion]** `BytesPerSecondLimit` is a live metric representing the current service quota, not a static value. If your account has requested quota increases, this value will reflect the new limit. Do not hardcode thresholds — compare dynamically. (Best-practice inference)
- **[delivery-freshness, delivery-errors]** Firehose retries delivery for a configurable retry duration (default varies by destination; S3 default is 0s but backup can be configured up to 7200s). During retry, DataFreshness climbs. After retry exhaustion, records go to error prefix and DataFreshness resets. DataFreshness resetting doesn't mean the problem is fixed — it may mean data was abandoned. (Confirmed: AWS documentation)
- **[ingestion]** CloudWatch Metric Streams deliver metrics as SUMMARY type (not counter or gauge). This affects aggregation options in Tsuga — `sum` and `count` from SUMMARY are available, as well as min (quantile=0) and max (quantile=1). Treat Sum-based metrics (IncomingBytes, IncomingRecords) as pre-aggregated delta counters: `average` or `sum` aggregation, with `per-second` post-function if delta. (Confirmed: CloudWatch Metric Streams OTel format documentation)
- **[delivery-throughput]** `DeliveryToS3.ObjectCount` is only available when dynamic partitioning is enabled. Do not gate the entire delivery-throughput section on this metric — it's supplemental, not core. (Confirmed: AWS documentation)
- **[delivery-errors, ingestion]** CloudWatch error logs are sampled at high failure rates. During a catastrophic delivery failure affecting many streams simultaneously, not all errors will be logged. Metrics (`DataFreshness`, `DeliveryToS3.Success`) are the reliable signal; logs are for root cause analysis after the alert fires. (Confirmed: AWS documentation)
- **[ingestion]** `IncomingPutRequests` counts successful API calls — a single PutRecordBatch call counts as 1 request regardless of the number of records it contains. Use `IncomingRecords` for data volume, `IncomingPutRequests` for API throughput. (Confirmed: AWS documentation)
- **[delivery-freshness]** When Kinesis Data Streams is the source, `KinesisMillisBehindLatest` is a separate freshness signal that measures how far behind Firehose is in reading from the source stream. This can grow independently of `DataFreshness` (destination-side freshness). Both can be elevated simultaneously or independently. (Confirmed: AWS documentation)
- **[delivery-errors]** `DeliveryToRedshift.Success` (Average) approaching 0 while `BackupToS3.DataFreshness` is low indicates the Redshift COPY commands are failing but records are being safely staged in S3. Records can be manually re-COPYed. This is recoverable, unlike S3-destination failures where records go to the error prefix. (Best-practice inference)
- **[ingestion]** Direct PUT and Kinesis-source streams have different throttle mechanisms. For Kinesis-source streams, throttling appears as `ThrottledGetRecords`/`ThrottledGetShardIterator`, NOT as `ThrottledRecords` (which is for Direct PUT). These are in separate metric rows. (Confirmed: AWS documentation)

---

## Confirmed Tsuga prefixes

- `aws_firehose_*` — **CONFIRMED** (Stage 2 discovery via `tsuga_search_metrics.py "firehose"` — 15 matching metrics found with this prefix)

**Prefix format:** Prometheus CloudWatch Exporter snake_case. No statistic suffixes — each metric is a SUMMARY type with sum/count/min/max quantiles available. Not the OTel dot-format (`aws.firehose.*`) and not the CW Metric Streams format.

**Ruled out:** `aws.firehose.*` (OTel dots — not present), `amazonaws.com/AWS/Firehose/*` (CW Metric Streams format — not present).

**15 confirmed metrics in Tsuga:**
1. `aws_firehose_incoming_records`
2. `aws_firehose_throttled_records`
3. `aws_firehose_put_record_batch_bytes`
4. `aws_firehose_put_record_batch_records`
5. `aws_firehose_put_record_batch_requests`
6. `aws_firehose_put_record_batch_latency`
7. `aws_firehose_delivery_to_http_endpoint_data_freshness`
8. `aws_firehose_delivery_to_http_endpoint_bytes`
9. `aws_firehose_delivery_to_http_endpoint_records`
10. `aws_firehose_delivery_to_http_endpoint_processed_bytes`
11. `aws_firehose_failed_validation_records`
12. `aws_firehose_kms_key_access_denied`
13. `aws_firehose_kms_key_disabled`
14. `aws_firehose_kms_key_invalid_state`
15. `aws_firehose_kms_key_not_found`

**Key discovery findings:**
- Destination is **HTTP endpoint** (not S3) — all `DeliveryToS3.*` metrics absent
- **MSK/Kafka is the source** (inferred from presence of `aws_firehose_failed_validation_records`)
- Lambda transformation **not enabled** — `ExecuteProcessing.*` absent
- Format conversion **not enabled** — `FailedConversion.*` absent
- `IncomingBytes` **not exported** — use `aws_firehose_put_record_batch_bytes` as proxy

---

## Discovery status

**Stage 2 discovery: COMPLETED** (2026-03-16)

Discovered via `tsuga_search_metrics.py "firehose"` scanning 3433 total metrics. All unknowns from Stage 1 (u_01 through u_07) resolved. Metric catalog bootstrapped: `05_aws-firehose_metric_catalog.csv` (15 metrics, 0 quality gate errors).

---

## Top sources

1. https://docs.aws.amazon.com/firehose/latest/dev/monitoring-with-cloudwatch-metrics.html — Authoritative AWS Firehose CloudWatch metrics reference: complete list of all metrics with statistics, units, dimensions, and feature requirements.
2. https://docs.aws.amazon.com/firehose/latest/dev/what-is-this-service.html — Amazon Data Firehose product overview: architecture, delivery stream concepts, source/destination types.
3. https://docs.aws.amazon.com/firehose/latest/dev/limits.html — Service limits and quotas: BytesPerSecondLimit values, partition limits, Lambda timeout, retry duration bounds.
4. https://docs.aws.amazon.com/firehose/latest/dev/data-transformation.html — Lambda transformation feature: record format, failure handling, timeout behavior, backup S3 bucket semantics.
5. https://docs.aws.amazon.com/firehose/latest/dev/record-format-conversion.html — Format conversion (JSON→Parquet/ORC): Glue schema requirements, FailedConversion behavior, error prefix routing.
6. https://docs.aws.amazon.com/firehose/latest/dev/dynamic-partitioning.html — Dynamic partitioning: JQ expressions, partition count limits, PartitionCountExceeded behavior.
7. https://docs.aws.amazon.com/firehose/latest/dev/encryption.html — KMS encryption: how KMS errors block all delivery, key access requirements.
8. https://docs.aws.amazon.com/firehose/latest/dev/troubleshooting.html — Troubleshooting guide: error log format, error code taxonomy, CloudWatch Logs setup for Firehose.
9. https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-metric-streams-formats-opentelemetry-translation.html — CloudWatch Metric Streams → OTel format: SUMMARY type encoding, metric name format, quantile encoding.
10. https://docs.aws.amazon.com/firehose/latest/dev/basic-deliver.html — S3 delivery configuration: buffer size, buffer interval, retry duration, S3 prefix patterns, backup bucket behavior.
