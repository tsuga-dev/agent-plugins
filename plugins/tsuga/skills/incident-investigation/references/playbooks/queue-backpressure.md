# Queue & Backpressure Playbook

For Kafka / RabbitMQ / SQS / Pub/Sub / Kinesis / Celery / Sidekiq / bounded channels.

Concrete metrics in `$knowledge-technology/kafka.md`, `/rabbitmq.md`, `/aws-sqs.md`, `/gcp-pubsub.md`. This file is reasoning disambiguation only.

## Producer vs consumer

- Lag growing + flat produce rate → consumer-side problem (slow processing, crash loop, DB dependency).
- Lag growing + spiking produce rate → producer-side burst or correct-but-insufficient capacity.
- Lag growing + falling produce rate + consume at zero → consumer is dead. Check worker health before assuming capacity.

## Consumer: slow vs crashed vs stuck

- Slow: consumer consuming < produce rate. Check per-message time + downstream (DB, HTTP call).
- Crashed: zero consumption. Check worker pod/process, lock contention, poison messages.
- Stuck: alive but waits forever (DB txn, HTTP with no timeout). Worse than crashed — monitoring often doesn't catch.

## Poison message

One unprocessable message blocking a partition / queue is a common trap:
- Kafka: partition stuck at one offset. Check per-partition lag, not aggregate.
- SQS: retry storm of one message. Check `ApproximateReceiveCount` outliers.
- DLQ growing → poison-message signal.

Category: `data_quality` (bad input) or `code_defect` (bad handler), not `resource_exhaustion`.

## Fan-out amplification

One upstream event → N downstream jobs. A 10× upstream spike can be 100× downstream. Check amplification before blaming the worker.

## Broker vs application

- Broker healthy (low CPU, normal replication, no disconnects) + app lag growing → application problem.
- Broker unhealthy → infrastructure problem, not worker sizing.

## Misleading context

- Lag spike during deploy can be the expected rolling-restart pause, not an incident. Check deploy timestamps.
- Aggregate lag hides stuck partitions. Always drill per-partition.
- Queue "clearing" may be retention dropping messages (data loss), not workers catching up.

## Causal chain skeletons

- Slow consumer: new PR adds a DB call per message → DB P95 climbs → worker throughput halves → lag grows linearly.
- Poison message: producer schema change → deserializer throws → retry storm → worker CPU spikes → aggregate lag grows.
- Broker disk: broker disk fills → writes throttle → producers block → upstream queues fill → cascading timeout.
