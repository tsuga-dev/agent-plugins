# `aws` CLI -> `tsuga` Translator

Use this for read-only CloudWatch metric equivalents in Tsuga. During skill execution, emit `tsuga` commands only. Do not add shell pipes, JSON processors, AWS CLI commands, or mutation commands.

## What Is Queryable

Queryable: CloudWatch metrics that are included in the account's metric stream.

Not queryable through this translator:

- AWS object spec/config from `aws * describe-*`
- CloudWatch Logs unless separately shipped into Tsuga
- IAM, IaC, audit events, or data-plane reads
- Anything that writes or mutates

## Metric Naming

Tsuga registers AWS metrics as `aws_<service>_<metric>` with CloudWatch dimensions exposed as lowercased `context.<dimensionkey>` attributes.

Standard AWS attributes commonly include `context.cloud_account_id`, `context.cloud_region`, `context.cloud.provider`, `context.aws.exporter.arn`, and, for EKS-tagged metrics, `context.cluster_id`. Use `context.cloud_account_id` as the canonical cross-account scope key.

To enumerate available AWS metrics:

```bash
tsuga metrics list --from <from> --to <to>
```

Manually inspect returned metric names beginning with `aws_`. Confirm a specific metric with:

```bash
tsuga metrics get <aws_metric_name> --from <from> --to <to>
```

## Common Dimensions

| Metric prefix | Common dimensions |
|---|---|
| `aws_sqs_*` | `context.queuename` |
| `aws_applicationelb_*` | `context.loadbalancer`, `context.targetgroup`, `context.availabilityzone` |
| `aws_networkelb_*` | `context.loadbalancer`, `context.availabilityzone` |
| `aws_rds_*` | `context.dbinstanceidentifier`, `context.dbclusteridentifier` |
| `aws_ec2_*` | `context.instanceid` |
| `aws_ebs_*` | `context.volumeid` |
| `aws_s3_*` | `context.bucketname`, `context.storagetype`, `context.filterid` |
| `aws_lambda_*` | `context.functionname`, `context.resource` |
| `aws_ecs_*` | `context.clustername`, `context.servicename` |
| `aws_natgateway_*` | `context.natgatewayid` |
| `aws_firehose_*` | `context.deliverystreamname` |
| `aws_kinesis_*` | `context.streamname` |
| `aws_eks_*` | `context.clustername` |
| `aws_logs_*` | `context.loggroupname` |
| `aws_kms_*` | `context.keyarn`, `context.operation` |
| `aws_certificatemanager_*` | `context.certificatearn` |
| `aws_ecr_*` | `context.repositoryname` |
| `aws_sns_*` | `context.topicname` |
| `aws_states_*` | `context.statemachinearn` |
| Other known `aws_*` namespaces | `aws_secretsmanager_*`, `aws_ses_*`, `aws_events_*`, `aws_bedrock_*`, `aws_cloudwatch_*`, `aws_config_*`, `aws_guardduty_*`, `aws_efs_*`, `aws_timestream_*`, `aws_acmprivateca_*`, `aws_privatelinkendpoints_*`, `aws_privatelinkservices_*`, `aws_scheduler_*`, `aws_ssm_runcommand_*`; confirm attributes with `tsuga metrics get`. |

## Name Examples

| CloudWatch UI | Tsuga metric |
|---|---|
| `RequestCount` | `aws_applicationelb_request_count` |
| `HTTPCode_Target_5XX_Count` | `aws_applicationelb_http_code_target_5xx_count` |
| `CPUUtilization` (RDS) | `aws_rds_cpu_utilization` |
| `ApproximateNumberOfMessagesVisible` | `aws_sqs_approximate_number_of_messages_visible` |
| `ApproximateAgeOfOldestMessage` | `aws_sqs_approximate_age_of_oldest_message` |

## Aggregate Type Pitfalls

- Valid aggregate types include `count`, `unique-count`, `average`, `max`, `min`, `sum`, and `percentile`.
- Many CloudWatch metrics arrive as `summary`; summaries do not support `percentile`.
- `count` is invalid on `dataSource:"metrics"`; use an aggregate over a metric field instead.
- Always confirm metric `type`, `temporality`, `unit`, and attributes with `tsuga metrics get`.

## Aggregation Template

Use this shape with one row from the use-case map. Confirm metric presence and attributes with `tsuga metrics get <metric> --from <from> --to <to>` before relying on it.

```bash
tsuga aggregation scalar -d '{
  "timeRange": {"from": <from_unix>, "to": <to_unix>},
  "dataSource": "metrics",
  "queries": [
    {"aggregate": {"type": "<aggregate>", "field": "<metric>"}}
  ],
  "groupBy": [{"fields": ["<dimension>"], "limit": 10}],
  "formula": "q1"
}'
```

For rows with multiple metrics, run the same shape once per metric unless the user explicitly asks for a combined formula.

## Use-Case Map

| Use case | Metric(s) | Aggregate | Group by | Notes |
|---|---|---|---|---|
| SQS queue depth | `aws_sqs_approximate_number_of_messages_visible` | `max` | `context.queuename` | Queue backlog by queue. |
| RDS CPU by instance | `aws_rds_cpu_utilization` | `max` | `context.dbinstanceidentifier` | Saturation signal by DB instance. |
| ALB target 5xx by load balancer | `aws_applicationelb_http_code_target_5xx_count` | `sum` | `context.loadbalancer` | Error total over the window. |
| RDS connections / free storage | `aws_rds_database_connections`, `aws_rds_free_storage_space` | `max`, `min` | `context.dbinstanceidentifier` | Aurora may use `context.dbclusteridentifier`. |
| RDS replica lag | `aws_rds_rds_to_aurora_postgre_sql_replica_lag`, `aws_rds_oldest_replication_slot_lag` | `max` | `context.dbinstanceidentifier` | Confirm exact metric name; do not assume generic `aws_rds_replica_lag`. |
| ALB request / latency / unhealthy hosts | `aws_applicationelb_request_count`, `aws_applicationelb_target_response_time`, `aws_applicationelb_un_healthy_host_count` | `sum`, `average` or `max`, `max` | `context.loadbalancer` or `context.targetgroup` | Latency is a summary; do not use `percentile`. Keep `un_healthy` spelling. |
| NLB active flows | `aws_networkelb_active_flow_count` | `max` | `context.loadbalancer` | Use `max`, not `sum`. |
| EC2 CPU / network | `aws_ec2_cpu_utilization`, `aws_ec2_network_in` | `max`, `sum` | `context.instanceid` | Use a window long enough for CloudWatch publish lag. |
| EBS IOPS / read latency / burst | `aws_ebs_volume_avg_iops`, `aws_ebs_volume_avg_read_latency`, `aws_ebs_burst_balance` | `average`, `max`, `min` | `context.volumeid` | Metric-catalog dependent; confirm first. |
| S3 bucket size by storage class | `aws_s3_bucket_size_bytes` | `max` | `context.bucketname`, then `context.storagetype` | S3 storage metrics publish daily; use a 24h+ window. |
| Lambda invocations / errors / duration / throttles | `aws_lambda_invocations`, `aws_lambda_errors`, `aws_lambda_duration`, `aws_lambda_throttles` | `sum`, `sum`, `max` or `average`, `sum` | `context.functionname` | Duration is a summary; do not use `percentile`. |
| Firehose incoming / throttled | `aws_firehose_incoming_records`, `aws_firehose_throttled_records` | `sum` | `context.deliverystreamname` | `sum` is total over the window. |
| NAT bytes / drops | `aws_natgateway_bytes_out_to_destination`, `aws_natgateway_packets_drop_count` | `sum` | `context.natgatewayid` | `sum` is total over the window. |
| Kinesis iterator age | `aws_kinesis_get_records_iterator_age` | `max` | `context.streamname` | Shard-level data may add `context.shardid`. |
| EKS apiserver requests | `aws_eks_apiserver_request_total` | `sum` | `context.clustername` | Counter-style metric; avoid high-cardinality label grouping by default. |

## Safety

- Use explicit `--from`/`--to` or Unix-second `timeRange`.
- Do not claim resource inventory from metrics alone; idle resources may be absent.
- Refuse AWS spec/IAM/data-plane/mutation requests from this skill and point the user to the appropriate AWS tooling.
