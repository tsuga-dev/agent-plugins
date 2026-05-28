# OpenTelemetry Collector

The data-plane for your telemetry. If the Collector is sick, downstream data in Tsuga is wrong or missing. Healthy: accepted ≈ sent across signals, refused / failed near zero, exporter queues bounded, no dropped records.

When "my data disappeared," suspect the Collector before the backend.

## Incident shapes

- **Receiver refusing** — `receiver_refused_*` > 0 → receiver returning error upstream; data lost or retried
- **Receiver failing** — `receiver_failed_*` > 0 → internal failure; data lost
- **Export send failure** — `exporter_send_failed_*` > 0 → backend rejecting; queue fills then drops
- **Export enqueue failure** — `exporter_enqueue_failed_*` > 0 → queue full; data dropped (classic signature when backend is down/slow)
- **Processor dropped** — `processor_dropped_*` > 0 → processor (batch / filter / memory_limiter) dropped data
- **Queue saturation** — `exporter_queue_size` near `queue_capacity` → next failure = drop

## Key metrics

Grouped by pipeline stage. Each signal (traces / metrics / logs) has separate counters.

| Metric | Unit | Signal |
|---|---|---|
| `otelcol_receiver_accepted_spans_total` | count | Spans accepted |
| `otelcol_receiver_accepted_metric_points_total` | count | Metric points accepted |
| `otelcol_receiver_accepted_log_records_total` | count | Log records accepted |
| `otelcol_receiver_refused_*_total` | count | Refused (producer error) |
| `otelcol_receiver_failed_*_total` | count | Receiver-side failures |
| `otelcol_processor_accepted_*` / `outgoing_items_total` | count | Processor flow |
| `otelcol_processor_dropped_*` | count | Processor drops |
| `otelcol_processor_batch_batch_send_size` | size | Batch output size |
| `otelcol_processor_batch_timeout_trigger_send_total` | count | Batches sent on timeout |
| `otelcol_exporter_sent_*_total` | count | Exported successfully |
| `otelcol_exporter_send_failed_*_total` | count | Export failures |
| `otelcol_exporter_enqueue_failed_*_total` | count | Queue-full failures |
| `otelcol_exporter_queue_size` / `queue_capacity` | count | Queue state |

## Derived signals

- `exporter_sent / receiver_accepted` per signal — pipeline efficiency. < 1.0 = loss.
- `receiver_refused / (accepted + refused)` — refusal rate. Any sustained = upstream producers seeing errors.
- `exporter_enqueue_failed / exporter_sent` — enqueue-fail rate. Any sustained = data loss.
- `queue_size / queue_capacity` — utilization. Near 1 = next failure is enqueue failure.
- `exporter_send_failed` trend — backend health signal.

## Log patterns

Collector logs:

- `Exporting failed. Dropping data` — data loss at exporter
- `Exporter error` / `exporter failed to send` — backend rejection
- `Memory usage is about to exceed limit` — memory_limiter activating
- `Too many spans/metrics dropped due to the backoff period` — rate limiter dropping
- `Rejecting data, it will be dropped` — processor rejects
- `Failed to scrape Prometheus endpoint` — scrape receiver unhealthy
- `Context deadline exceeded` — downstream timeout
- `connection refused` / `unable to read TLS config` — network / TLS

## Gotchas

- The Collector must be instrumented for its own metrics to appear. If the Collector's metrics go to the same pipeline it serves, a broken pipeline hides its own metrics. Run a separate monitoring path for the Collector itself.
- `memory_limiter` drops data intentionally to avoid OOM. Protective but visible as loss. Pairing with larger exporter queue masks the issue.
- `batch` processor accumulates before sending. `batch_timeout_trigger_send_total` dominant = batches are time-bounded (low traffic or batch too large).
- Multi-pipeline configurations (per signal or tenant) can have one healthy and another broken. Filter by pipeline / exporter label.
- Protocol-specific footguns: OTLP gRPC vs HTTP/protobuf vs HTTP/JSON have different failure modes (TLS version mismatch affects one protocol, not another).
