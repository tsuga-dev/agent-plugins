# Envoy

L7 proxy, usually sidecar or edge. Metrics are per-listener and per-cluster.

## Incident shapes

- **Upstream connect failures** — `upstream_cx_connect_fail` / `connect_timeout` rise → upstream or network
- **Upstream 5xx** — `upstream_rq_5xx` rises → upstream errors bubble
- **Pool overflow** — `upstream_rq_pending_overflow > 0` → Envoy dropped due to connection-pool saturation
- **Per-try timeouts** — `upstream_rq_per_try_timeout` rises → individual attempts timing out
- **Listener admission reject** — `downstream_cx_overflow` / `overload_reject` → admission rejecting
- **Memory pressure** — `server.memory_allocated` growing = leak or large buffers

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `server.live` | 0/1 | Envoy health |
| `server.uptime` | seconds | Reset on restart |
| `server.memory_allocated` / `memory_heap_size` | bytes | Memory posture |
| `server.concurrency` | count | Worker threads |
| `listener.<name>.downstream_cx_total` / `active` | count | Downstream connections |
| `listener.<name>.downstream_cx_overflow` | count | Admission rejection |
| `listener.<name>.downstream_cx_overload_reject` | count | Overload-manager rejections |
| `cluster.<name>.upstream_cx_active` | count | Upstream connections |
| `cluster.<name>.upstream_cx_connect_fail` | count | Upstream connect failures |
| `cluster.<name>.upstream_cx_connect_timeout` | count | Upstream connect timeouts |
| `cluster.<name>.upstream_rq_total` | count | Upstream requests |
| `cluster.<name>.upstream_rq_2xx` / `4xx` / `5xx` | count | Status buckets |
| `cluster.<name>.upstream_rq_timeout` | count | Request timeouts |
| `cluster.<name>.upstream_rq_pending_overflow` | count | Pool saturation drops |
| `cluster.<name>.upstream_rq_retry` / `retry_success` | count | Retry state |
| `cluster.<name>.upstream_rq_per_try_timeout` | count | Per-attempt timeouts |

## Derived signals

- `upstream_rq_5xx / upstream_rq_total` — upstream error rate. Baseline < 0.01.
- `upstream_rq_retry / upstream_rq_total` — retry rate. > 0.05 sustained = flaky upstream.
- `upstream_rq_retry_success / upstream_rq_retry` — retry effectiveness. Low = retries not helping.
- `upstream_rq_pending_overflow / upstream_rq_total` — pool saturation. Any sustained = pool too small or upstream slow.

## Log patterns

Envoy access-log response flags:

- `UH` — no healthy upstream
- `UF` — upstream connection failure
- `UT` — upstream request timeout
- `UC` — upstream connection terminated before response
- `UR` — upstream remote reset
- `URX` — retries exhausted
- `LR` — local connection reset
- `DC` — downstream client disconnected
- `OM` — overload manager active
- `RL` — rate limit service active

## Gotchas

- Metric names embed dynamic cluster / listener names. Configure labelling for filtering.
- Stats sink is async; metrics can lag a few seconds.
- `retry_success` counts in `rq_total` already (double-count risk in naive ratios).
- `downstream_cx_overflow=0` doesn't prove no admission problem; slow-upstream backpressure shows elsewhere.
- Connection pooling is per-cluster-per-worker-thread. Per-worker saturation can be invisible in aggregates.
