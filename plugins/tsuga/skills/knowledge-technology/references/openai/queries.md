# OpenAI API

LLM API consumption. Metrics cover client-side duration, token usage, costs, rate-limit headroom, errors, batch state, TTFT. Healthy: low error rate, latency within SLO, rate-limit headroom, predictable cost.

## Incident shapes

- **429 rate limiting** — `rate_limit_remaining_requests` / `remaining_tokens` drop to 0 → traffic spike or tier too low
- **5xx from OpenAI** — provider degradation
- **Latency regression** — `operation.duration` p95 spikes → provider slowdown, model change, or bigger contexts
- **Cost runaway** — `costs api amount.value` jumps → prompt-size bug or loop
- **Token-usage anomaly** — input/output tokens shift without request-count change → model or client change
- **Batch API backlog** — batch requests piling up

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `gen_ai.client.operation.duration` | s | Per-call duration |
| `gen_ai.client.token.usage` | tokens | Input / output / total |
| `gen_ai.client.generation.choices` | count | Completion choices per call |
| `openai usage api input_tokens` | tokens | Aggregate input tokens |
| `openai usage api output_tokens` | tokens | Aggregate output tokens |
| `openai usage api input_cached_tokens` | tokens | Cache hits |
| `openai usage api input_audio_tokens` / `output_audio_tokens` | tokens | Audio models |
| `openai usage api num_model_requests` | count | Requests per model |
| `openai costs api amount.value` | $ | Dollar cost |
| `openai error responses by status_code` | count | Error distribution |
| `openai rate limit remaining requests` | count | Headroom (RPM) |
| `openai rate limit remaining tokens` | count | Headroom (TPM) |
| `openai batch requests` | count | Batch API state |
| `openai latency to first token` | ms | TTFT; user-perceived latency for streaming |

## Derived signals

- `error responses / num_model_requests` — error rate. Baseline near 0.
- `1 - (remaining_requests / limit)` — rate-limit pressure. Collapse = imminent 429.
- `input_cached_tokens / (input_tokens + input_cached_tokens)` — cache-hit ratio. Higher = cheaper + faster.
- `output_tokens / num_model_requests` — avg output length. Jump with stable input = model-side change.
- `latency_to_first_token` p95 — TTFT. Often the critical SLO for streaming apps.

## Log patterns

SDK-side:

- `openai.RateLimitError` / `status 429` — rate limit
- `openai.APIStatusError` / `5xx` — provider error
- `openai.APITimeoutError` — client timeout (network or long generation)
- `openai.APIConnectionError` — network error
- `openai.BadRequestError` / `400` — invalid request (context too long, bad param)
- `openai.AuthenticationError` / `401` — key issue (usually rotation)
- `openai.PermissionDeniedError` / `403` — account restriction / org change
- `"reason":"length"` stop reason — output hit max_tokens (user sees truncation)
- `"content_filter"` stop reason — moderation blocked

## Gotchas

- Rate limits are per (org, model, window). A spike on one model doesn't affect others.
- Usage API lags real-time by minutes. For real-time cost alerting, use SDK-local counters.
- `operation.duration` includes streaming time; slow call may be slow streaming (long output) vs slow start (TTFT). Separate.
- Moderation / content-filter blocks are 200 responses with `stop_reason="content_filter"`, not errors. Not in 4xx/5xx stream.
- Batch API is async; a request "in progress" for hours is normal.
- Function-calling / structured-output can silently add thousands of input tokens per call without client-code changes.
