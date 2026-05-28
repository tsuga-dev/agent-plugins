# Kubernetes runbooks

Concrete remediation recipes for the seven most common Kubernetes failure modes.

Each runbook is **advisory** — these skills are read-only by default. Any step that would change cluster state must follow the mutation gate: show the exact command, explain why, wait for explicit user confirmation ("yes"), only then apply. The `Destructive` and `Human` columns let an operator scan for "safe + automatable" steps at a glance: `Destructive` = changes cluster state, `Human` = requires explicit confirmation before running.

Reasoning context (when each runbook applies, what counts as cause vs. symptom) lives in the incident-investigation kubernetes playbook (`$incident-investigation/references/playbooks/kubernetes.md`). Metric / log signal definitions live in this folder's `queries.md`.

Placeholders:
- `<POD>` — pod name · `<DEP>` — deployment name · `<NS>` — namespace · `<NODE>` — node name
- `<NEW_LIMIT>` / `<NEW_REQUEST>` — target memory in Mi · `<APP_LABEL>` — pod label selector

---

## CrashLoopBackOff Recovery

Severity: **SEV2** · Category: `crashloop` · Triggers: `CrashLoopBackOff`, restart_count > 5, container `waiting` with reason `CrashLoopBackOff`

**Diagnose**
- Pod describe for exit codes (`1` = app error, `137` = OOM, `143` = SIGTERM)
- Previous container logs for panic / exception / fatal
- Recently deployed → rollback candidate
- Resource limits (memory too low → silent OOM → exit 137)

**Steps**

| # | Command | Why | Destructive | Human |
|---|---|---|---|---|
| 1 | `kubectl logs <POD> -n <NS> --previous --tail=100` | Get crashing-container logs | no | no |
| 2 | `kubectl describe pod <POD> -n <NS>` | Exact exit code + reason | no | no |
| 3 | *(no command)* | If exit 137: patch memory limit. If exit 1: check config/secrets. | no | yes |
| 4 | `kubectl rollout restart deployment/<DEP> -n <NS>` | Fresh pods | no | yes |
| 5 | `kubectl rollout history deployment/<DEP> -n <NS>` | Consider rollback if restart didn't help | no | yes |
| 6 | `kubectl delete pod <POD> -n <NS> --force --grace-period=0` | Last resort; controller recreates | yes | yes |

**Notes**
- Exit 137 ≈ OOM → raise memory limit
- Exit 1 ≈ application error → read logs for the exception
- Exit 143 ≈ SIGTERM → liveness probe likely too strict
- Prefer rollout restart over force delete

---

## OOMKilled Recovery

Severity: **SEV2** · Category: `oom` · Triggers: `OOMKilled`, `exit_code == 137`, `kube_pod_container_status_last_terminated_reason == OOMKilled`

**Diagnose**
- Current memory limits vs. observed usage
- Logs for memory-leak signature (growing heap, GC pressure)
- Spiky (JVM, Python GC) vs. linear growth (true leak)
- Node-level memory pressure

**Steps**

| # | Command | Why | Destructive | Human |
|---|---|---|---|---|
| 1 | `kubectl logs <POD> -n <NS> --previous --tail=200` | Pre-OOM logs | no | no |
| 2 | `kubectl describe deployment <DEP> -n <NS>` | Current limits + replicas | no | no |
| 3 | `kubectl set resources deployment/<DEP> -n <NS> --limits=memory=<NEW_LIMIT>Mi --requests=memory=<NEW_REQUEST>Mi` | Raise limit by ~50% | no | yes |
| 4 | `kubectl rollout restart deployment/<DEP> -n <NS>` | Apply new limits | no | yes |
| 5 | `kubectl top pod -n <NS> -l app=<APP_LABEL>` | Monitor for regrowth | no | yes |

**Notes**
- JVM: set `-Xmx` to ~75% of memory limit
- Python: watch for list / dict accumulation
- If a leak is suspected, capture a heap dump before restarting
- Long-term fix: add a VPA (Vertical Pod Autoscaler) for right-sizing

---

## ImagePullBackOff Recovery

Severity: **SEV2** · Category: `image_pull` · Triggers: `ImagePullBackOff`, `ErrImagePull`, event reason `Failed` with image-pull message

**Diagnose**
- Image tag actually exists in the registry
- `imagePullSecret` is configured and valid on the SA
- Node has network reachability to the registry
- Rate limiting (Docker Hub 429 for unauthenticated)

**Steps**

| # | Command | Why | Destructive | Human |
|---|---|---|---|---|
| 1 | `kubectl describe pod <POD> -n <NS>` | Exact registry error | no | no |
| 2 | `kubectl get serviceaccount default -n <NS> -o yaml` | Is a pull secret attached? | no | no |
| 3 | `kubectl get secrets -n <NS> --field-selector type=kubernetes.io/dockerconfigjson` | List registry creds in the NS | no | no |
| 4 | `kubectl create secret docker-registry regcred --docker-server=<REGISTRY> --docker-username=<USER> --docker-password=<PASS> -n <NS>` | Create secret if missing | no | yes |
| 5 | `kubectl patch serviceaccount default -n <NS> -p '{"imagePullSecrets":[{"name":"regcred"}]}'` | Attach secret to SA | no | yes |
| 6 | `kubectl delete pod <POD> -n <NS>` | Trigger a fresh pull | yes | yes |

**Notes**
- Docker Hub: 100 pulls / 6h for unauthenticated users
- Pin to image digests, not `:latest`, for reproducibility
- A private registry mirror sidesteps rate limits

---

## Pending Pods Recovery

Severity: **SEV2** · Category: `pending` · Triggers: pod phase `Pending`, `FailedScheduling`, insufficient cpu/memory events

**Diagnose**
- `FailedScheduling` reason (insufficient resources, taints, affinity)
- Node allocatable vs. requested
- Namespace `ResourceQuota` headroom
- `nodeSelector` / taints / tolerations mismatch
- PVC binding status

**Steps**

| # | Command | Why | Destructive | Human |
|---|---|---|---|---|
| 1 | `kubectl describe pod <POD> -n <NS>` | Scheduling failure reason | no | no |
| 2 | `kubectl describe resourcequota -n <NS>` | Namespace quota usage | no | no |
| 3 | `kubectl describe nodes \| grep -A5 'Allocated resources'` | Per-node allocatable headroom | no | no |
| 4 | `kubectl get pvc -n <NS>` | PVC binding status if storage-bound | no | no |
| 5 | *(no command)* | If quota exceeded: request bump or reduce non-critical replicas. If resource pressure: scale cluster or shift workloads. | no | yes |
| 6 | `kubectl scale deployment/<LOW_PRIORITY_DEP> --replicas=0 -n <NS>` | Free resources by stopping a lower-priority workload | yes | yes |

**Notes**
- `FailedScheduling: Insufficient memory` → nodes lack allocatable RAM
- `FailedScheduling: node(s) had taint` → pod needs tolerations
- PVC `Pending` → storage class may not support the zone/region

---

## Node Not Ready Recovery

Severity: **SEV1** · Category: `node_not_ready` · Triggers: node condition `Ready == False` or `Unknown`, event reason `NodeNotReady`

**Diagnose**
- Node conditions (`MemoryPressure`, `DiskPressure`, `PIDPressure`, `NetworkUnavailable`)
- Kubelet logs on the node
- Node reachability (ping / SSH)
- Single node vs. cluster-wide

**Steps**

| # | Command | Why | Destructive | Human |
|---|---|---|---|---|
| 1 | `kubectl describe node <NODE>` | Full conditions | no | no |
| 2 | `kubectl get events --field-selector involvedObject.name=<NODE>` | Recent node events | no | no |
| 3 | `kubectl cordon <NODE>` | Stop new scheduling immediately | no | yes |
| 4 | `kubectl get pods --all-namespaces --field-selector spec.nodeName=<NODE>` | Inventory pods on the bad node | no | no |
| 5 | *(no command — SSH)* | If disk pressure: `df -h` then prune images (`crictl rmi --prune` or `docker system prune`) | no | yes |
| 6 | `kubectl drain <NODE> --ignore-daemonsets --delete-emptydir-data --force` | Reschedule pods if node is unrecoverable | yes | yes |

**Notes**
- Always cordon before draining
- Check for special taints before draining
- Managed clusters (EKS / GKE / AKS): prefer cloud-provider node-restart over manual drain
- `DiskPressure` → inspect `/var/lib/kubelet` and container image storage first

---

## Disk Pressure Recovery

Severity: **SEV1** · Category: `disk_pressure` · Triggers: node condition `DiskPressure == True`, pod eviction reason `Evicted`, high ephemeral-storage usage

**Diagnose**
- Which node has the pressure
- What's consuming disk (images, logs, data volumes, emptyDir)
- Any pods already evicted
- PVCs that are full

**Steps**

| # | Command | Why | Destructive | Human |
|---|---|---|---|---|
| 1 | `kubectl get nodes -o custom-columns=NAME:.metadata.name,DISK:.status.conditions[?(@.type=="DiskPressure")].status` | List nodes under disk pressure | no | no |
| 2 | `kubectl get pods -n <NS> --field-selector status.phase=Failed -o wide` | Already-evicted pods | no | no |
| 3 | `kubectl delete pods -n <NS> --field-selector status.phase=Failed` | Clear evicted-pod entries | yes | yes |
| 4 | `kubectl cordon <NODE>` | Stop new scheduling on the affected node | no | yes |
| 5 | *(no command — SSH)* | `crictl rmi --prune` (containerd) or `docker system prune -af` (docker) | yes | yes |
| 6 | `kubectl uncordon <NODE>` | Bring node back into scheduling | no | yes |

**Notes**
- Container images are usually the biggest disk consumer on nodes
- Set `imagePullPolicy: Always` to avoid stale cached images
- Add `ephemeral-storage` limits per-pod to prevent single-pod disk abuse
- Recurring? Look at node autoscaling or larger disks

---

## High CPU Usage Recovery

Severity: **SEV2** · Category: `high_cpu` · Triggers: pod CPU > 80% of limit, node CPU > 90%, CPU throttling > 50%

**Diagnose**
- Top CPU consumers
- Spike correlated with traffic (check error rate / latency)
- Recent deploy (code regression)
- HPA keeping up?

**Steps**

| # | Command | Why | Destructive | Human |
|---|---|---|---|---|
| 1 | `kubectl top pods -n <NS> --sort-by=cpu` | Identify top consumers | no | no |
| 2 | `kubectl get hpa -n <NS>` | Is autoscaling engaged? | no | no |
| 3 | `kubectl scale deployment/<DEP> --replicas=<N+2> -n <NS>` | Emergency scale above HPA max | no | yes |
| 4 | `kubectl scale deployment/<DEP> --replicas=<CURRENT+2> -n <NS>` | Manual scale if no HPA | no | yes |
| 5 | `kubectl rollout restart deployment/<DEP> -n <NS>` | Recover if a runaway process is stuck | no | yes |
| 6 | `kubectl set resources deployment/<DEP> -n <NS> --limits=cpu=<LIMIT>m` | Cap per-pod CPU so one pod can't starve the node | no | yes |

**Notes**
- CPU throttling ≠ OOM — throttled pods are slow, not killed
- CPU limits too low can *cause* artificial throttling
- HPA target around 70% CPU gives proactive headroom
- Reproducible spike → profile the application

---

## How to use these runbooks in an investigation

These runbooks are **remediation recipes**, not investigation steps. The investigation orchestrator (`$incident-investigation`) is still responsible for:

1. Classifying the incident mode (outage_RCA vs monitoring_watch vs …).
2. Anchoring on the firing monitor and replaying its query (`tsuga monitors get <id>`).
3. Tying the telemetry signal to its emitting `file:line` via codebase-grep.
4. Producing the verdict + causal chain.

A runbook from this file enters the picture **only after** a confirmed (or "most likely") root cause matches the runbook's category. Cite it in the verdict's `Remediation` section like so:

```
Remediation:
  Stop the bleeding: kubectl rollout restart deployment/<DEP> -n <NS>
    (runbook: CrashLoopBackOff Recovery step 4 — safe, human-confirmed)
  Likely root fix: raise container memory limit; see CrashLoopBackOff Recovery step 3
  Verify before acting: exit code in `kubectl describe pod` confirms 137 (OOM) vs 1 (app error)
```

Never pick a runbook by name — pick it by the validated `category` field of the verdict (`crashloop`, `oom`, `image_pull`, `pending`, `node_not_ready`, `disk_pressure`, `high_cpu`). If no category matches cleanly, return remediation as freeform prose rather than forcing a runbook fit.
