# AWS API Gateway

Managed HTTP / REST / WebSocket edge. Fronts Lambda, HTTP backends, VPC-link targets. Healthy: low 4xx + 5xx, latency bounded, integration latency ≪ total.

## Incident shapes

- **Integration failure** — `aws_apigateway_5xx_error` spikes, `aws_apigateway_integration_latency` high → backend sick
- **Client errors** — `aws_apigateway_4xx_error` spikes → client bug, schema change, auth, or 429 throttle
- **aws_apigateway_latency regression** — `aws_apigateway_latency` p95 climbs; split into `aws_apigateway_integration_latency` (backend) vs gateway overhead
- **Throttling** — 429s from stage/account throttle settings (infer from 4xx detail)
- **Authorizer timeouts** — custom Lambda authorizer slow → 5xx with low aws_apigateway_integration_latency but high aws_apigateway_latency

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `aws_apigateway_count` | requests | Total rate |
| `aws_apigateway_4xx_error` | count | Client errors (incl. 429) |
| `aws_apigateway_5xx_error` | count | Server errors (usually integration / authorizer) |
| `aws_apigateway_latency` | ms | End-to-end (gateway + integration) |
| `aws_apigateway_integration_latency` | ms | Integration (backend) only |

Metric set is small; most investigation goes through access logs.

## Derived signals

- `(aws_apigateway_4xx_error + aws_apigateway_5xx_error) / aws_apigateway_count` — error rate. Baseline < 0.01 typically.
- `aws_apigateway_latency - aws_apigateway_integration_latency` — gateway overhead. Normally < 20ms; spike here without backend movement = authorizer / gateway-side.
- `p99(aws_apigateway_latency) / p50(aws_apigateway_latency)` — > 10 = long-tail regression.

## Log patterns

API Gateway access logs (CloudWatch):

- `"status":"5\d\d"` — 5xx response
- `"errorMessage":` — integration-level error
- `"integrationStatus":"504"` — integration timeout
- `"authorizerError":` — authorizer failure
- `"throttled":true` — stage/account throttle
- `"integrationLatency":` very high — backend slow

## Gotchas

- `aws_apigateway_4xx_error` lumps 429 throttles, 403 auth failures, and 400 bad-request. Don't interpret a 4xx spike as "client bug" without checking log status codes.
- `aws_apigateway_integration_latency` is only populated when there's an integration. MOCK integrations or authorizer rejections leave it absent.
- Per-stage and per-account throttles coexist. Stage limits are in stage config; account limits are soft.
- Caching hides misses: `aws_apigateway_count` increments on cached response but `aws_apigateway_integration_latency` doesn't. `aws_apigateway_count` vs backend call rate divergence = cache hit rate.
- Websocket and REST APIs have different metric semantics; confirm API type before reasoning.
