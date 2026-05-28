# Apache HTTP Server

Classic web server / reverse proxy. Healthy: `apache_up=1`, busy workers below total, idle dominant, low error rate.

## Incident shapes

- **Worker exhaustion** — busy workers near total → queue / refusal
- **CPU-bound workers** — cpuload climbs with heavy request mix (often PHP-FPM or mod_php)
- **Process storm** — scoreboard shows many `S` / `G` states → bad restart cycle
- **Upstream slowness** (reverse proxy) — workers held waiting on backend
- **Exporter scrape failure** — `apache_up=0` could be either Apache down OR stub_status unreachable

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `apache_up` | 0/1 | Exporter reachability |
| `apache_uptime_seconds_total` | seconds | Reset = restart |
| `apache_workers` (state=busy) | count | Busy workers |
| `apache_workers` (state=idle) | count | Idle workers |
| `apache_connections` | count | Total open connections |
| `apache_processes` | count | Server processes |
| `apache_accesses_total` | count | Cumulative request count |
| `apache_sent_kilobytes_total` | KiB | Cumulative bytes sent |
| `apache_duration_ms_total` | ms | Cumulative total duration |
| `apache_cpu_time_ms_total` | ms | Cumulative worker CPU |
| `apache_cpuload` | % | CPU load estimate |
| `apache_scoreboard` | count/state | Per-state worker counts |

## Derived signals

- `busy / (busy + idle)` — worker saturation. > 0.85 sustained = request queueing.
- `Δaccesses_total / Δt` — request rate.
- `Δduration_ms_total / Δaccesses_total` — avg request duration.
- `Δcpu_time_ms_total / Δaccesses_total` — avg CPU time per request. Rising = heavier workload.

## Log patterns

- `[mpm_event:error] AH00484: server reached MaxRequestWorkers setting` — worker cap hit
- `[proxy:error] AH00940: HTTP: disabled connection` — upstream repeatedly failing
- `[proxy:error] AH01102: error reading status line` — backend hangup
- `[core:error] AH00045: child process %d still did not exit` — hung worker
- `[ssl:error] SSL Library Error` — TLS issue
- `[authz_core:error] AH01630: client denied` — ACL denying
- Segfault / signal errors — worker crash

## Gotchas

- Scoreboard string encodes per-slot state. Collected as separate counters, slot detail is lost. Use raw `server-status?refresh=1` for pathological cases.
- Keep-alive workers (state) are held for idle connections. `workers{state=keepalive}` dominant = new requests may queue even when workers "look idle."
- MPM modes (prefork / worker / event) have different worker semantics; tuning assumptions change.
- Access-log-only analysis misses hung workers, SSL errors, and backend issues. Use error log for those.
- Behind LB/CDN, `X-Forwarded-For` is real client IP; direct IP is the proxy.
