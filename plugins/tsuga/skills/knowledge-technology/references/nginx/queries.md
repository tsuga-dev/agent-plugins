# NGINX

HTTP server / reverse proxy / ingress. Healthy: `nginx_up=1`, accepted ≈ handled, active well below limits, waiting (idle keep-alive) dominant.

## Incident shapes

- **Overload** — active up, waiting down, writing spikes → upstream slow or traffic up
- **Connection drops** — accepted diverges from handled → `worker_connections` hit or backpressure
- **NGINX down / unreachable** — `nginx_up=0` → check if actually down OR exporter scrape is broken
- **Upstream latency bleed-through** — nginx metrics fine, app 5xx spikes → check app logs, not nginx

## Key metrics

stub_status exposes 8 core metrics. Richer signals come from access logs.

| Metric | Unit | Signal |
|---|---|---|
| `nginx_up` | 0/1 | Scrape reachable (0 ≠ nginx down, could be exporter) |
| `nginx_connections_accepted` | counter | Accepted since start |
| `nginx_connections_handled` | counter | Processed to completion |
| `nginx_connections_active` | gauge | Current open |
| `nginx_connections_reading` | gauge | Reading request headers; spike = slow clients |
| `nginx_connections_writing` | gauge | Writing response; spike = slow upstream / large payloads |
| `nginx_connections_waiting` | gauge | Idle keep-alive; should dominate |
| `nginx_http_requests_total` | counter | Per-second = request rate |

## Derived signals

- `(Δaccepted - Δhandled) / Δaccepted` — drop rate. Any sustained positive value = drops.
- `connections_active / (worker_processes * worker_connections)` — utilization. Config knowledge needed.
- `connections_waiting / connections_active` — keep-alive pool health. Collapse to 0 = every connection busy.
- `connections_writing / connections_reading` — writing≫reading = upstream slow.

## Log patterns

Access / error log:

- `upstream timed out (110: Connection timed out)` — upstream slow/dead
- `connect() failed (111: Connection refused)` — upstream not listening
- `no live upstreams while connecting to upstream` — all backends marked down
- `upstream prematurely closed connection` — upstream crashed / reset
- `client intended to send too large body` — exceeded `client_max_body_size`
- `worker_connections are not enough` — raise limit or scale horizontally
- `SSL_do_handshake() failed` — TLS negotiation
- `recv() failed (104: Connection reset by peer)` — spike = network issue

## Gotchas

- `nginx_up = 0` can mean exporter scrape failure, not nginx down. Cross-check with access-log volume.
- stub_status counters reset on reload/restart. Use `per-second`, not absolute reads.
- `worker_connections` limit is not in stub_status; keep it in team docs.
- NGINX metrics look healthy while users suffer: check per-upstream response times from access logs.
- A single bad backend in a pool causes intermittent `no live upstreams`. Group log search by upstream address.
