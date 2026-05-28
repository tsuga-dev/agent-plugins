# Kubernetes

Container orchestration. Healthy: pods ready = desired, restart rates ≈ 0, no pending pods, nodes `Ready`, no steady `CrashLoopBackOff` / `OOMKilled`.

## Incident shapes

- **CrashLoopBackOff** — pod fails to start or crashes early → check events + pod logs
- **OOMKilled storm** — memory pressure (leak, traffic, payload) → check memory saturation
- **Pod scheduling stuck** — `FailedScheduling` events → capacity or affinity
- **Readiness probe failure sweep** — new pods never ready → check probe target
- **Node-level failure** — multiple pods on one node fail → suspect node, not pods

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `k8s.pod.phase` (phase) | gauge | `Pending > 0` sustained = scheduling problem |
| `k8s.pod.ready` | bool | Numerator for deployment readiness |
| `k8s.container.restarts` | count | Delta over window = restart count |
| `k8s.container.last_terminated_reason` | label | `OOMKilled` / `Error` / `Completed` |
| `k8s.container.memory.usage` | bytes | Per-container memory |
| `k8s.container.memory.limit` | bytes | Memory ceiling |
| `k8s.container.cpu.usage` | cpu-s/s | Per-container CPU |
| `k8s.container.cpu.limit` | cpu-s/s | CPU ceiling (if set) |
| `k8s.deployment.replicas_ready` / `replicas_desired` | count | Rollout health |
| `k8s.node.condition` (type) | gauge | `Ready=1` + `MemoryPressure=0` + `DiskPressure=0` expected |
| `k8s.node.allocatable.memory` / `cpu` | — | Scheduling capacity |
| `k8s.hpa.current_replicas` / `desired_replicas` | count | Divergence = scaling stuck |

## Derived signals

- `replicas_ready / replicas_desired` — readiness ratio. < 1.0 after rollout = stuck deployment.
- Derivative of `container.restarts` over 5m — restart rate. Any steady positive on steady-state = abnormal.
- `container.memory.usage / container.memory.limit` — memory saturation. > 0.85 = OOM risk.
- `container.cpu.usage / container.cpu.limit` — CPU saturation. > 0.8 with throttling = under-provisioned.
- Failing pods grouped by node: spread > 1 on one node and ≈1 elsewhere = node suspect.

## Log patterns

- `Back-off restarting failed container` — CrashLoopBackOff parent event
- `Readiness probe failed: HTTP probe failed with statuscode: N` — probe target sick
- `Liveness probe failed` — service hung or probe too strict
- `OOMKilled` — memory cap hit
- `Failed to pull image` / `ImagePullBackOff` — registry / auth / tag issue
- `FailedScheduling: 0/N nodes are available` — capacity or affinity
- `Evicted: The node was low on resource` — node-level pressure
- `NetworkUnavailable` / `NodeNotReady` — node infra problem

## Gotchas

- `last_terminated_reason` is point-in-time: a pod that OOMed 2h ago still reports `OOMKilled` even if healthy since. Cross-check with restart-count delta in the window.
- `OOMKilled` can be symptom (payload explosion, upstream response growth) rather than cause (leak). Correlate with response size / memory trend.
- `kubectl rollout restart` in the window is a human response, not a trigger. Find who ran it.
- `FailedScheduling` with 0 nodes available = `resource_exhaustion`; with N nodes mismatching taints = `configuration_error`.
- Readiness failures cascade: one pod not ready → traffic shifts → overloads peers → more not-ready. Original trigger is usually upstream of the probe.
