# HAProxy

L4/L7 load balancer. Healthy: backends active, zero failed health checks, bounded response time, low 5xx rate, queue depth ≈ 0.

## Incident shapes

- **Backend unhealthy** — active_servers drops, check_failures rise → backend sick, not HAProxy
- **Queue backpressure** — `current_queue > 0` sustained → backend can't keep up
- **Backend errors** — `response_errors_total` / `connection_errors_total` rise → backend misbehaving
- **Session saturation** — `current_sessions / limit_sessions` → 1.0 → new connections rejected
- **Redispatches** — retry on different backend after first failed → backend flakiness

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `haproxy_backend_active_servers` | count | Drop = health-check failures |
| `haproxy_backend_backup_servers` | count | Standby in use |
| `haproxy_backend_status` | 0/1 | 1=UP, 0=DOWN (all servers failed) |
| `haproxy_server_status` | 0/1 | Per-server |
| `haproxy_server_check_failures_total` | count | Health-check failures |
| `haproxy_backend_current_queue` | count | Requests waiting for backend slot |
| `haproxy_backend_downtime_seconds_total` | seconds | Cumulative downtime |
| `haproxy_frontend_connections_total` | count | New-connection rate |
| `haproxy_frontend_current_sessions` / `limit_sessions` | count | Sessions + ceiling |
| `haproxy_frontend_request_errors_total` | count | Frontend errors |
| `haproxy_frontend_requests_denied_total` | count | ACL denies |
| `haproxy_backend_connection_errors_total` | count | Connect to backend failures |
| `haproxy_backend_response_errors_total` | count | Backend response protocol errors |
| `haproxy_backend_retry_warnings_total` | count | Same-server retries |
| `haproxy_backend_redispatch_warnings_total` | count | Cross-server retries |
| `haproxy_backend_http_responses_total{code=5xx}` | count | Backend 5xx |
| `haproxy_backend_connect_time_average_seconds` | s | Backend connect latency |
| `haproxy_backend_queue_time_average_seconds` | s | Queue wait |
| `haproxy_backend_response_time_average_seconds` | s | Backend response |

## Derived signals

- `current_sessions / limit_sessions` — session utilization. > 0.85 sustained = capacity headroom running out.
- `retry + redispatch` rate — retry pressure. Any sustained = backend flakiness.
- `connect_time + queue_time + response_time` split — locates the dominant latency phase.

## Log patterns

- `SC--` — session closed before request (client abort)
- `SD--` — session closed by server with data
- `sH--` / `SH--` — server reset / aborted
- `NOSRV` — no server available
- `Server X is DOWN` / `UP` — health transitions
- `Backend X has no server available` — all backends failed
- HTTP codes in access logs: 502 / 503 / 504 distinguish connect / no-server / timeout

## Gotchas

- Access-log timers are in ms typically. `-1` means the phase didn't complete.
- `backend_status = 0` = ALL servers failed, not just one. Use `server_status` per-server.
- Session limits are per-process. Multi-process (nbthread) shares per-thread; true utilization needs config.
- `redispatch_warnings` counts attempts, not distinct failed requests. High rate ≠ many requests failed.
- Weighted backends skew traffic; per-server error analysis without knowing weights can mislead.
