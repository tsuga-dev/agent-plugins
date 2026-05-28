# LiteSpeed / OpenLiteSpeed

High-performance web server, common in WordPress / hosting. Healthy: `litespeed_up=1`, connections well below max, high cache hit ratio for cached vhosts.

## Incident shapes

- **Connection ceiling** — `current_http_connections` near `maximum_http_connections` → new connections rejected
- **SSL saturation** — `current_ssl_connections` near `maximum_ssl_connections` → TLS handshakes fail
- **Cache hit collapse** — `public_cache_hits_per_second_per_vhost` drops → backend / PHP-FPM spike
- **Per-app pool saturation** — external app pool full → requests queue
- **Exporter scrape failure** — `litespeed_up=0` → server down OR admin socket unreachable

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `litespeed_up` | 0/1 | Exporter reachability |
| `litespeed_current_http_connections` | count | Current HTTP |
| `litespeed_maximum_http_connections` | count | HTTP ceiling |
| `litespeed_current_ssl_connections` | count | Active TLS |
| `litespeed_maximum_ssl_connections` | count | TLS ceiling |
| `litespeed_current_idle_connections` | count | Keep-alive idle |
| `litespeed_incoming_http_bytes_per_second` | bytes/s | Inbound |
| `litespeed_outgoing_http_bytes_per_second` | bytes/s | Outbound |
| `litespeed_requests_per_second_per_vhost` | req/s | Per-vhost rate |
| `litespeed_current_requests_per_vhost` | count | In-flight per vhost |
| `litespeed_public_cache_hits_per_second_per_vhost` | hits/s | Public cache |
| `litespeed_private_cache_hits_per_second_per_vhost` | hits/s | Per-user cache |
| `litespeed_static_hits_per_second_per_vhost` | hits/s | Static-file hits |
| `litespeed_pool_max_connections_per_app` | count | Per-app pool max |

## Derived signals

- `current_http_connections / maximum_http_connections` — HTTP utilization. > 0.85 = alert.
- `current_ssl_connections / maximum_ssl_connections` — SSL utilization.
- `public_cache_hits / requests` per vhost — cache effectiveness.
- `pool_max / config_max` — per-app pool pressure.

## Log patterns

- `[ERROR] External app [name]: 503` — app pool exhausted / crashed
- `[ERROR] SSL handshake failed` — TLS negotiation
- `[WARN] Out of connection pool` — per-app saturation
- `[ERROR] Failed to connect to ExtApp` — PHP-FPM / backend unreachable
- `[WARN] Connection was closed by client` — client abort

## Gotchas

- LiteSpeed Enterprise vs OpenLiteSpeed differ in metrics; confirm which is running.
- Public-cache collapse + private-cache rise often = personalized pages (cookie / auth plugin change) replacing shared cache.
- External-app pools are per-vhost-per-app. One pool saturated while others idle — aggregate metrics hide this.
- `litespeed_up=0` often means admin-socket permission issue, not server down.
- Behind CDN (CloudFlare / Fastly), metrics reflect post-cache traffic. Origin load ≠ user-facing traffic.
