# Kubernetes Playbook

For pods, deployments, nodes, or cluster-level symptoms. Trap: pinning cause on the restart/pod event when the restart is itself a symptom.

Concrete metrics in `$knowledge-technology/kubernetes.md`. Remediation recipes per failure mode in `$knowledge-technology/kubernetes/runbooks.md` (CrashLoopBackOff, OOMKilled, ImagePullBackOff, Pending, NodeNotReady, DiskPressure, HighCPU). This file is reasoning disambiguation only — pick a runbook *after* the investigation validates the category, never before.

## Symptom vs root cause

- `CrashLoopBackOff` is symptom. Cause = bad config, missing secret, OOM, failed probe, broken dependency at startup, image pull failure, or corrupted volume.
- `OOMKilled` can be cause (leak, under-allocated limit) OR symptom (downstream returns huge response, payload explosion). Check memory trend + request/response size in the same window.
- Pod restart spike is not a root cause. Restarts are evidence something else failed — find that.

## Scheduling and probes

- `PodPending` + `FailedScheduling` → capacity or affinity problem (`resource_exhaustion` or `configuration_error`), not the pod.
- `Readiness probe failed` → pod started but can't serve. Check the probe target (usually `/health`); failure is upstream of probe config unless probe itself just changed.
- `Liveness probe failed` + restart loop → probe too strict (config) or service genuinely hung (code / dependency).

## Validation failures: configuration error vs data quality

When logs show the application validating incoming data against a configured list of required fields and a field in that list is missing from the data, the root cause is typically `configuration_error` — the required-fields list was misconfigured in the Job manifest, ConfigMap, or env vars — NOT `data_quality`.

Data quality issues manifest as **malformed values** or **corrupted records** (bad JSON, wrong types, null in non-null column). A mismatch between a configured field list and the data schema means the configuration was wrong relative to what the producer reliably emits, so `configuration_error` on the consumer side.

Counter-example: if the producer JUST changed its schema and the consumer's config is unchanged, it's `data_quality` (upstream API change). The distinction is "did the producer change, or did the config?"

## Node vs pod vs shared infra

- Many pods on same node failing → suspect node. Check `NodeReady`, disk pressure, kubelet health.
- Many pods across nodes in same deployment failing → suspect deployment (new image / config / secret).
- Many services on same node failing → suspect shared infra (node, network, control plane).

## Deploy correlation

- Pod failures right after a rollout → prime suspect is the new image or updated ConfigMap / Secret. Use `$incident-investigation` to find the PR / run.
- `ImagePullBackOff` post-rollout → registry auth, image tag typo, or registry outage. Check Deployment spec's image vs what's in the registry.

## Misleading context

- A single `OOMKilled` from 6h ago is noise if the current incident is a fresh 5xx spike.
- `Evicted` pods are node-level pressure symptom, not the application cause.
- `kubectl rollout restart` in the window is an operator response, not a trigger. Find who / why.

## Causal chain skeletons

- OOM: traffic spike OR payload growth → heap past limit → OOMKilled → restart → cold cache → latency → 5xx.
- Bad secret rotation: secret rotated → ConfigMap not redeployed → pods read stale → auth fails at startup → CrashLoopBackOff.
- Bad readiness probe: probe path changed in release → /health mismatch → pod never ready → rollout stuck → no new pods serve.

## Runbooks (post-verdict only)

Once the investigation has assigned a `category`, the matching runbook from `$knowledge-technology/kubernetes/runbooks.md` supplies concrete remediation steps. Map:

| `category` | Runbook |
|---|---|
| `crashloop` | CrashLoopBackOff Recovery |
| `oom` | OOMKilled Recovery |
| `image_pull` | ImagePullBackOff Recovery |
| `pending` | Pending Pods Recovery |
| `node_not_ready` | Node Not Ready Recovery |
| `disk_pressure` | Disk Pressure Recovery |
| `high_cpu` | High CPU Usage Recovery |

Pick a runbook only after the verdict; never let a runbook category force-fit the cause. Each step is tagged `Destructive` / `Human` — show the step + wait for explicit user confirmation before applying anything that changes cluster state.
