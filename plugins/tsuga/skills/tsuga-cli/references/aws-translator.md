# `aws` CLI → `tsuga` Translator

For accounts wired to a CloudWatch metric stream → Firehose → Tsuga pipeline, most read-only `aws cloudwatch get-metric-statistics` and several `aws <service> get-*-attributes` calls have a `tsuga aggregation` equivalent.

Tsuga registers each metric as `aws_<service>_<metric>` (snake-case) with CloudWatch dimensions exposed as `context.<dimensionkey>` attributes, lowercased.

## What's queryable

What's **always** queryable: anything CloudWatch exposes as a metric and is included in the account's metric stream.

What's **not** ingested via this pipeline:

- AWS object spec/config (everything `aws ec2 describe-instances` / `aws rds describe-db-instances` returns) — no `awsobjectsreceiver` analogue today.
- CloudWatch **Logs** (`/aws/eks/<cluster>/cluster`, `/aws/containerinsights/*`, `/aws/lambda/*`). Different pipeline; not wired by default.
- IAM / IaC / mutation events. Refuse and point at the AWS CLI directly.

To enumerate the AWS service prefixes ingested into your tenant:

```bash
tsuga metrics list --from -1h | jq -r '.[].name' | grep '^aws_' \
  | awk -F'_' '{print $2}' | sort -u
```

Common prefixes: `applicationelb`, `networkelb`, `sqs`, `sns`, `rds`, `ec2`, `ebs`, `lambda`, `s3`, `firehose`, `kinesis`, `natgateway`, `eks`, `ecs`, `ecr`, `kms`, `secretsmanager`, `ses`, `states`, `events`, `bedrock`, `cloudwatch`, `config`, `guardduty`, `efs`, `timestream`, `acmprivateca`, `certificatemanager`, `privatelinkendpoints`, `privatelinkservices`, `scheduler`, `ssm-runcommand`.

## Standard attributes (every aws_* metric)

```
context.cloud_account_id    AWS account id
context.cloud_region        e.g. "eu-central-1"
context.cloud.provider      "aws"
context.aws.exporter.arn    metric-stream ARN
context.cluster_id          when sourced from an EKS-tagged metric
```

`context.cloud_account_id` is the canonical key for cross-account scoping.

## Per-service resource-id dimensions

Confirm per metric with `tsuga metrics get aws_<service>_<metric> | jq '.attributes'`. Common shapes:

| Service prefix | Resource dimension(s) |
|---|---|
| `aws_sqs_*` | `context.queuename` |
| `aws_applicationelb_*` | `context.loadbalancer`, `context.targetgroup`, `context.availabilityzone` |
| `aws_networkelb_*` | `context.loadbalancer`, `context.availabilityzone` (no `targetgroup` on NLB metrics) |
| `aws_rds_*` | `context.dbinstanceidentifier`, `context.dbclusteridentifier` (Aurora) |
| `aws_ec2_*` | `context.instanceid` |
| `aws_ebs_*` | `context.volumeid` |
| `aws_s3_*` | `context.bucketname`, `context.storagetype`, `context.filterid` |
| `aws_lambda_*` | `context.functionname`, `context.resource` |
| `aws_natgateway_*` | `context.natgatewayid` |
| `aws_firehose_*` | `context.deliverystreamname` |
| `aws_logs_*` | `context.loggroupname` |
| `aws_eks_*` | `context.clustername` |
| `aws_kms_*` | `context.keyarn`, `context.operation` |
| `aws_certificatemanager_*` | `context.certificatearn` |
| `aws_ecr_*` | `context.repositoryname` |
| `aws_sns_*` | `context.topicname` |
| `aws_states_*` | `context.statemachinearn` |
| `aws_ecs_*` | `context.clustername`, `context.servicename` |

For other services: `tsuga metrics get <name>` and read `.attributes[]`. CloudWatch dimensions become `context.*` attributes, lowercased.

## CloudWatch name → Tsuga name

Rule of thumb: CamelCase → snake_case, service prefix `aws_<service>_`. The exact mapping is the OTel CloudWatch receiver's normalization — `tsuga metrics list | grep <fragment>` if in doubt.

| CloudWatch UI | Tsuga field |
|---|---|
| `RequestCount` | `aws_applicationelb_request_count` |
| `HTTPCode_Target_5XX_Count` | `aws_applicationelb_http_code_target_5xx_count` |
| `CPUUtilization` (RDS) | `aws_rds_cpu_utilization` |
| `ActiveFlowCount` | `aws_networkelb_active_flow_count` |
| `ApproximateNumberOfMessagesVisible` | `aws_sqs_approximate_number_of_messages_visible` |
| `ApproximateAgeOfOldestMessage` | `aws_sqs_approximate_age_of_oldest_message` |

## Aggregate type pitfalls

- Valid type values: **`count`**, **`unique-count`**, **`average`**, **`max`**, **`min`**, **`sum`**, **`percentile`**. `avg` is not valid as a `type` — use `average`. (`tsuga metrics get` returns `capabilities` using the abbreviation `avg`, but the type value to send is the full word.)
- Many CloudWatch metrics arrive as **summary** type — `tsuga metrics get <name>` shows `"type": "summary"`. SQS depth, Lambda duration, ALB latency, etc. are summaries. Summaries support `count`/`average`/`sum`/`min`/`max`/`unique-count` but **not `percentile`** — calling `percentile` returns `400 percentile cannot be calculated for a summary`. Use `max` or `average` for latencies like `aws_applicationelb_target_response_time` and `aws_lambda_duration`.
- `percentile` works on `gauge` metrics that list it in `capabilities` (e.g. `k8s.pod.cpu.usage`) and on `traces`/`logs` numeric fields like `duration`.
- `count` is the only aggregate that doesn't take `field`, and it's invalid on `dataSource:"metrics"` (use `sum`).

## Worked examples

### SQS — queue depth

```bash
NOW=$(date +%s); FROM=$((NOW - 600))
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"max",field:"aws_sqs_approximate_number_of_messages_visible"}}],
  groupBy:[{fields:["context.queuename"],limit:30}]
}')"
```

Filter to DLQs only: add `"filter":"context.queuename:*-dlq"` inside the query.

Related: `aws_sqs_approximate_age_of_oldest_message` (consumer lag), `aws_sqs_approximate_number_of_messages_not_visible` (in-flight), `aws_sqs_number_of_messages_sent`/`_received`/`_deleted` (rates), `aws_sqs_number_of_empty_receives` (short-polling cost).

### RDS — top CPU / connections / replica lag / free storage

```bash
NOW=$(date +%s); FROM=$((NOW - 1800))
# CPU
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"max",field:"aws_rds_cpu_utilization"}}],
  groupBy:[{fields:["context.dbinstanceidentifier"],limit:5}]
}')"
# Connections (saturation)
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"max",field:"aws_rds_database_connections"}}],
  groupBy:[{fields:["context.dbinstanceidentifier"],limit:5}]
}')"
# Replica lag
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"max",field:"aws_rds_replica_lag"}}],
  groupBy:[{fields:["context.dbinstanceidentifier"],limit:5}]
}')"
# Free storage
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"min",field:"aws_rds_free_storage_space"}}],
  groupBy:[{fields:["context.dbinstanceidentifier"],limit:5}]
}')"
```

For Aurora group on `context.dbclusteridentifier`. Many engine-specific metrics exist (`aws_rds_blocked_transactions_count`, `aws_rds_aborted_clients`, `aws_rds_transactions_rolled_back`, etc.).

### ALB — request rate, 5xx, target latency, unhealthy hosts

```bash
NOW=$(date +%s); FROM=$((NOW - 600))
# Request count
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"sum",field:"aws_applicationelb_request_count"}}],
  groupBy:[{fields:["context.loadbalancer"],limit:5}]
}')"
# 5xx
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"sum",field:"aws_applicationelb_http_code_target_5xx_count"}}],
  groupBy:[{fields:["context.loadbalancer"],limit:5}]
}')"
# Latency — summary metric, use average or max (NOT percentile)
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"average",field:"aws_applicationelb_target_response_time"}}],
  groupBy:[{fields:["context.loadbalancer"],limit:5}]
}')"
# Unhealthy hosts by target group
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"max",field:"aws_applicationelb_un_healthy_host_count"}}],
  groupBy:[{fields:["context.targetgroup"],limit:10}]
}')"
```

For ALB `5xx_rate`, issue two queries (`5xx_count`, `request_count`) and divide client-side — `tsuga aggregation` has no metric math.

### NetworkELB

```bash
NOW=$(date +%s); FROM=$((NOW - 600))
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"sum",field:"aws_networkelb_active_flow_count"}}],
  groupBy:[{fields:["context.loadbalancer"],limit:5}]
}')"
```

Related: `aws_networkelb_processed_bytes`, `aws_networkelb_zonal_health_status`, `aws_networkelb_tcp_target_reset_count`.

### EC2 CPU + network

```bash
NOW=$(date +%s); FROM=$((NOW - 1800))   # ≥10m; CW publish lag
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"max",field:"aws_ec2_cpu_utilization"}}],
  groupBy:[{fields:["context.instanceid"],limit:5}]
}')"
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"sum",field:"aws_ec2_network_in"}}],
  groupBy:[{fields:["context.instanceid"],limit:5}]
}')"
```

### EBS — IOPS / latency / burst balance / queue length

```bash
NOW=$(date +%s); FROM=$((NOW - 1800))
# IOPS
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"average",field:"aws_ebs_volume_avg_iops"}}],
  groupBy:[{fields:["context.volumeid"],limit:5}]
}')"
# Read latency (summary — use max)
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"max",field:"aws_ebs_volume_avg_read_latency"}}],
  groupBy:[{fields:["context.volumeid"],limit:5}]
}')"
# Burst balance (alert when < 20%)
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"min",field:"aws_ebs_burst_balance"}}],
  groupBy:[{fields:["context.volumeid"],limit:5}]
}')"
# Queue length (latency proxy)
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"max",field:"aws_ebs_volume_queue_length"}}],
  groupBy:[{fields:["context.volumeid"],limit:5}]
}')"
```

### S3 — bucket size by storage class

S3 storage metrics publish daily — use `--from -24h` or longer:

```bash
NOW=$(date +%s); FROM=$((NOW - 86400))
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"max",field:"aws_s3_bucket_size_bytes"}}],
  groupBy:[
    {fields:["context.bucketname"],limit:5},
    {fields:["context.storagetype"],limit:3}
  ]
}')"
```

Other S3 metrics: `aws_s3_bytes_uploaded`, `aws_s3_bytes_downloaded`, `aws_s3_first_byte_latency`, `aws_s3_total_request_latency`, `aws_s3_list_requests`, `aws_s3_delete_requests`, `aws_s3_head_requests`.

### Lambda — invocations / errors / duration / throttles

```bash
NOW=$(date +%s); FROM=$((NOW - 1800))
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"sum",field:"aws_lambda_invocations"}}],
  groupBy:[{fields:["context.functionname"],limit:5}]
}')"
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"sum",field:"aws_lambda_errors"}}],
  groupBy:[{fields:["context.functionname"],limit:5}]
}')"
# Duration is summary type — use max, not percentile
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"max",field:"aws_lambda_duration"}}],
  groupBy:[{fields:["context.functionname"],limit:5}]
}')"
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"sum",field:"aws_lambda_throttles"}}],
  groupBy:[{fields:["context.functionname"],limit:5}]
}')"
# Concurrent executions (account-wide)
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"max",field:"aws_lambda_concurrent_executions"}}]
}')"
```

For error rate, divide `errors / invocations` client-side.

### Firehose — incoming / throttled

```bash
NOW=$(date +%s); FROM=$((NOW - 1800))
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"sum",field:"aws_firehose_incoming_records"}}],
  groupBy:[{fields:["context.deliverystreamname"],limit:5}]
}')"
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"sum",field:"aws_firehose_throttled_records"}}],
  groupBy:[{fields:["context.deliverystreamname"],limit:5}]
}')"
```

### NAT Gateway — throughput / drops

```bash
NOW=$(date +%s); FROM=$((NOW - 1800))
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"sum",field:"aws_natgateway_bytes_out_to_destination"}}],
  groupBy:[{fields:["context.natgatewayid"],limit:5}]
}')"
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"sum",field:"aws_natgateway_packets_drop_count"}}],
  groupBy:[{fields:["context.natgatewayid"],limit:5}]
}')"
```

Related: `aws_natgateway_connection_attempt_count`, `aws_natgateway_connection_established_count`, `aws_natgateway_peak_bytes_per_second`, `aws_natgateway_idle_timeout_count`.

### Kinesis — consumer lag

```bash
NOW=$(date +%s); FROM=$((NOW - 1800))
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"max",field:"aws_kinesis_get_records_iterator_age"}}]
}')"
```

`GetRecords iterator age` is the canonical consumer-lag signal — high values mean consumers are behind. Related: `aws_kinesis_incoming_records`, `aws_kinesis_write_provisioned_throughput_exceeded` (throttling).

### EKS apiserver

```bash
NOW=$(date +%s); FROM=$((NOW - 1800))
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"sum",field:"aws_eks_apiserver_request_total"}}],
  groupBy:[{fields:["context.clustername"],limit:5}]
}')"
```

Related: `aws_eks_scheduler_pending_pods_unschedulable`, `aws_eks_apiserver_flowcontrol_current_executing_seats`.

## Cross-cutting

### Multi-dimensional grouping

```bash
NOW=$(date +%s); FROM=$((NOW - 600))
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"sum",field:"aws_sqs_approximate_number_of_messages_visible"}}],
  groupBy:[
    {fields:["context.queuename"],   limit:3},
    {fields:["context.cloud_region"],limit:3}
  ]
}')"
```

One row per `(queuename, region)` pair — **separate `groupBy` entries**, one field each.

### CloudWatch dimension lowercasing

`QueueName` / `LoadBalancer` / `DBInstanceIdentifier` become `context.queuename` / `context.loadbalancer` / `context.dbinstanceidentifier`. Mixed-case won't match.

### Publish cadence

Most CloudWatch streams publish every 1 min, some (S3, billing) at 5 min or daily. Use `--from -10m` minimum for general metrics, `--from -24h+` for S3 storage. Inventory via `groupBy` is lossy — idle resources won't appear; for an authoritative inventory use the AWS API.

## What's not coverable

| `aws` verb | Reason |
|---|---|
| Any `describe-*` / spec read | Spec data; needs an `awsobjectsreceiver` |
| `aws elbv2 describe-target-health` | Target health is spec, not a metric |
| `aws logs tail` / `aws logs filter-log-events` | CloudWatch Logs ingestion not wired |
| `aws cloudtrail lookup-events` | Mutation events not wired |
| `aws iam *` / `aws sts *` | Identity, out of scope |
| Anything that writes / mutates | By design |
