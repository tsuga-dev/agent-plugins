# OTel Collector — Sampling Strategy Rules

## Decision Table: Which Sampling Approach

| Goal | Approach | Skill Section |
|------|----------|--------------|
| Reduce volume by fixed % | Head sampling (probabilistic) | See below |
| Keep all errors + slow traces + baseline % | Tail sampling | See below |
| Route traces to specific backends by attribute | `loadbalancingexporter` | See below |
| No sampling needed | Don't add any — start without sampling, add when volume is a problem | — |

## Head Sampling (probabilistic)

**Use when:** Simple volume reduction is sufficient; you don't need to guarantee keeping specific traces.

**How it works:** Decision made at trace start, before outcome is known. Cannot guarantee keeping all error traces at low sample rates.

```yaml
processors:
  probabilistic_sampler:
    sampling_percentage: 10  # Keep 10% of traces
```

**Limitations:**
- At 10% sampling, ~10% of errors are kept — rare errors may be lost entirely
- Decision made before span outcome is known
- Scales horizontally without coordination

**When NOT to use:** If you need "always keep errors and slow traces" — use tail sampling instead.

## Tail Sampling (keep errors + slow + baseline)

**Use when:** You need policy-based sampling (always keep errors, always keep traces over 2s, keep 5% baseline).

**Architecture: Two-tier REQUIRED**

All spans of a single trace MUST reach the same Collector instance for tail sampling to work. This requires:

```
App pods → Agent DaemonSet (loadbalancingexporter) → Gateway Deployment (tailsamplingprocessor) → Backend
```

**Tier 1: Agent DaemonSet** (routes by trace ID)
```yaml
exporters:
  loadbalancing:
    protocol:
      otlp:
        tls:
          insecure: true
    resolver:
      dns:
        hostname: otelcol-gateway.monitoring.svc.cluster.local
        port: 4317
```

**Tier 2: Gateway Deployment** (evaluates complete traces)
```yaml
processors:
  tail_sampling:
    decision_wait: 10s           # Wait this long for all spans before deciding
    num_traces: 100000           # Max traces held in memory simultaneously
    expected_new_traces_per_sec: 1000
    policies:
      - name: keep-errors
        type: status_code
        status_code: {status_codes: [ERROR]}
      - name: keep-slow
        type: latency
        latency: {threshold_ms: 2000}
      - name: keep-baseline
        type: probabilistic
        probabilistic: {sampling_percentage: 5}
```

**Important:** If any span of a trace reaches a different Gateway instance, that trace will be dropped or appear incomplete. The `loadbalancingexporter` routes by `traceID` hash to ensure consistency.

## Tsuga Stance on Sampling

Both approaches are valid:
- SDK-level head sampling (in the application) — appropriate for high-volume services with simple needs
- Collector-level tail sampling — appropriate when policy-based decisions are needed

Do NOT adopt "Collector-only sampling" dogma. The right choice depends on volume, error sensitivity, and operational complexity tolerance.

## loadbalancingexporter (trace-aware routing)

Use when you need to route traces to specific backends based on trace attributes (e.g., route PCI traces to a compliant backend):

```yaml
exporters:
  loadbalancing:
    routing_key: traceID  # or "service" to route by service.name
    protocol:
      otlp:
        timeout: 1s
    resolver:
      static:
        hostnames: [backend-1:4317, backend-2:4317, backend-3:4317]
      # OR k8s:
      #   service: otelcol-gateway.monitoring
      #   ports:
      #     - 4317
```
