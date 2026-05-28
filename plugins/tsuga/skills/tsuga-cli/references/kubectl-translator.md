# `kubectl` → `tsuga` Translator

Most read-only `kubectl` reads have a `tsuga` equivalent. Tsuga ingests four classes of Kubernetes signal from clusters running the Alloy + OTel collector stack:

1. **Container logs** — `tsuga logs search --query 'context.k8s.pod.name:…'`
2. **K8s events** — `event.domain:k8s` + structured `object.*` block
3. **K8s object snapshots** — full PodSpec / Deployment / Node objects under `k8s.resource.name:<kind>`
4. **K8s metrics** — `k8s.pod.*`, `k8s.node.*`, `k8s.deployment.*`, etc.

## Cluster scoping

- `--cluster` selects the **tsuga regional endpoint**, not the data scope. Multi-cluster tenants get the same data from any endpoint.
- Filter the data with `context.cluster_id:<kube-cluster-name>` (e.g. `prod-mtc`, `staging-mtc`). `context.k8s.cluster.name` is the same value; both work.
- Drop the cluster filter to query cross-cluster.

## Object snapshots — `kubectl get -o yaml` / `kubectl describe`

The OTel `k8sobjectsreceiver` ships full API objects as log records at `k8s.resource.name:<kind>`.

Kinds typically ingested: `pods`, `events`, `nodes`, `deployments`, `replicasets`, `statefulsets`, `daemonsets`.

Kinds NOT in the receiver config (so 0 records, not "0 because empty"): `services`, `ingresses`, `configmaps`, `secrets`, `serviceaccounts`, `horizontalpodautoscalers`, `jobs`, `cronjobs`, `persistentvolumes`, `persistentvolumeclaims`, RBAC kinds. HPAs / jobs / cronjobs exist as **metrics**, not objects.

To check what your cluster actually ships:

```bash
tsuga logs search --query 'k8s.resource.name:*' --max-results 200 --from -1h \
  | jq -r '.logs[].k8s.resource.name' | sort -u
```

### `kubectl get pods` / `kubectl describe pod`

```bash
tsuga logs search \
  --query 'context.cluster_id:<cluster> AND k8s.resource.name:pods AND object.metadata.namespace:<ns>' \
  --max-results 200 --from -10m \
  | jq -r '.logs | unique_by(.object.metadata.uid) | .[]
           | "\(.object.metadata.name)\t\(.object.status.phase)\t\(.object.status.podIP // "-")\t\(.object.spec.nodeName // "-")"'
```

The `.object` payload is the full Kubernetes API object — `spec`, `status`, `conditions`, `containerStatuses[].restartCount`, `containerStatuses[].lastState.terminated.{reason,exitCode,finishedAt}`, `spec.containers[].resources.{requests,limits}`.

Flag mapping:

| `kubectl` flag | `tsuga` modification |
|---|---|
| `-n <ns>` | append `AND object.metadata.namespace:<ns>` |
| `-A` | drop the namespace clause |
| `-l app=X` | append `AND context.kube_app_name:X` (only `app` label is indexed) |
| `--field-selector status.phase=Running` | append `AND object.status.phase:Running` |
| `-o wide` / `-o yaml` | already present in `.object`, just project differently |

Not mapped: `-w` (no streaming today), arbitrary labels (only `app` is indexed as `context.kube_app_name`).

### `kubectl get events`

```bash
tsuga logs search \
  --query 'context.cluster_id:<cluster> AND event.domain:k8s AND object.type:Warning' \
  --max-results 50 --from -1h \
  | jq -r '.logs[] | "\(.object.lastTimestamp)\t\(.object.type)/\(.object.reason)\t\(.object.involvedObject.name)\t\(.object.message)"'
```

Useful filter shapes:

| Want | Filter |
|---|---|
| Events for one pod | `event.domain:k8s AND object.involvedObject.name:<pod>` |
| Only warnings | `event.domain:k8s AND object.type:Warning` |
| CrashLoopBackOff | `event.domain:k8s AND object.reason:BackOff` |
| Unhealthy probes | `event.domain:k8s AND object.reason:Unhealthy` |
| Image pull failures | `event.domain:k8s AND object.reason:Failed AND object.message:*pull*` |
| FailedScheduling | `event.domain:k8s AND object.reason:FailedScheduling` |

### `kubectl get nodes` / `kubectl describe node`

```bash
tsuga logs search \
  --query 'context.cluster_id:<cluster> AND k8s.resource.name:nodes AND object.metadata.name:<node>' \
  --max-results 1 --from -10m
```

`.object` contains labels, taints, addresses, `status.nodeInfo` (kubelet version, OS, runtime), `status.conditions`.

### `kubectl get deployments` / `kubectl describe deployment`

```bash
tsuga logs search \
  --query 'context.cluster_id:<cluster> AND k8s.resource.name:deployments AND object.metadata.namespace:<ns>' \
  --max-results 50 --from -10m \
  | jq -r '.logs[] | "\(.object.metadata.name)\t\(.object.status.availableReplicas // 0)/\(.object.spec.replicas)\t\(.object.spec.template.spec.containers[0].image)"'
```

Full pod template (image, env, resources, probes) is under `.object.spec.template`.

## Container logs — `kubectl logs`

```bash
tsuga logs search \
  --query 'context.cluster_id:<cluster> AND context.k8s.namespace.name:<ns> AND context.k8s.pod.name:<pod>' \
  --max-results 50 --from -10m
```

Improvements over `kubectl logs`:

- **Wildcard pod names**: `context.k8s.pod.name:<deploy>-*` queries every replica in one call.
- **Cross-restart**: every restart instance is in the log store; `--previous` only sees one.
- **Tabular output**: add `-o tsv --fields timestamp,level,context.k8s.pod.name,message`.

Flag mapping:

| `kubectl` flag | `tsuga` modification |
|---|---|
| `-n <ns>` | append `AND context.k8s.namespace.name:<ns>` |
| `-c <container>` | append `AND context.k8s.container.name:<container>` |
| `--tail=<N>` | `--max-results <N>` |
| `--since=<dur>` | `--from -<dur>` |
| `--previous` | widen `--from` past the previous container's death |
| `-f` | not supported today |

## Pod / node metrics — `kubectl top`

`kubectl top` is a point-in-time scrape. Tsuga has the same data as a timeseries.

```bash
NOW=$(date +%s); FROM=$((NOW - 600))
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[
    {aggregate:{type:"max",field:"k8s.pod.cpu.usage"},    filter:"context.k8s.cluster.name:<cluster>"},
    {aggregate:{type:"max",field:"k8s.pod.memory.working_set"}, filter:"context.k8s.cluster.name:<cluster>"}
  ],
  groupBy:[{fields:["context.k8s.pod.name"],limit:50}]
}')" \
  | jq -r '.results
           | group_by(.group["context.k8s.pod.name"])
           | map({pod: .[0].group["context.k8s.pod.name"],
                  cpu_m: ((.[]|select(.id=="q1").value)*1000|floor),
                  mem_mi: ((.[]|select(.id=="q2").value)/1048576|floor)})
           | sort_by(-.cpu_m)[]
           | "\(.pod)\t\(.cpu_m)m\t\(.mem_mi)Mi"'
```

Units: `k8s.pod.cpu.usage` is in **cores** (multiply by 1000 for millicores); `k8s.pod.memory.working_set` is in **bytes**.

For historical ramp (no `kubectl` equivalent): use `tsuga aggregation timeseries` with `"aggregationWindow": "5m"`.

Native metric inventory (preferred over the legacy `prometheus_k8s_*` mirror):

- **Pod** — `k8s.pod.cpu.usage`, `k8s.pod.cpu.time`, `k8s.pod.memory.{usage,available,rss,working_set,page_faults,major_page_faults}`, `k8s.pod.filesystem.{usage,available,capacity}`, `k8s.pod.network.{io,errors}`, `k8s.pod.phase`
- **Container** — `k8s.container.{cpu,memory}_{request,limit}`, `k8s.container.ready`, `k8s.container.restarts`, `k8s.container.status.reason` (string-valued)
- **Node** — `k8s.node.cpu.{usage,time}`, `k8s.node.memory.*`, `k8s.node.filesystem.*`, `k8s.node.network.*`, `k8s.node.allocatable_{cpu,memory,ephemeral_storage,pods}`, `k8s.node.condition_{ready,disk_pressure,memory_pressure,pid_pressure}`
- **Workload** — `k8s.deployment.{available,desired}`, `k8s.statefulset.{current,desired,ready,updated}_pods`, `k8s.daemonset.{current,desired,ready,misscheduled}_scheduled_nodes`, `k8s.hpa.{current,desired,min,max}_replicas`, `k8s.job.*`, `k8s.cronjob.active_jobs`

Common attributes on every metric: `context.k8s.cluster.name`, `context.k8s.namespace.name`, `context.k8s.pod.name`, `context.k8s.container.name`, `context.k8s.deployment.name`, `context.k8s.node.name`, `context.env`, `context.cloud`, `context.team`.

## Aggregation API gotchas

1. **`groupBy` is top-level**, never inside `queries[]`.
2. **Multi-dimensional groupBy must use multiple entries**, NOT multiple fields in one entry:
   - ❌ `"groupBy": [{"fields": ["context.queuename", "context.cloud_region"], "limit": 3}]` → `400 must NOT have more than 1 items`
   - ✅ `"groupBy": [{"fields": ["context.queuename"], "limit": 3}, {"fields": ["context.cloud_region"], "limit": 3}]`
3. **`timeRange` uses Unix seconds**, integers. ISO strings or relative shorthand are rejected.
4. **`dataSource` and `formula` are body-level**. Query items do not have `id` or `dataSource`.
5. **`count` is the only aggregate that doesn't need `field`**, and it's invalid on `dataSource:"metrics"` (use `sum`).
6. **`avg` is not a valid aggregate type** — use `average`. (`tsuga metrics get` returns `"capabilities": ["avg", …]` but the type value to send is the full word `average`.)

## What kubectl does that Tsuga cannot do today

| `kubectl` | Why no Tsuga equivalent |
|---|---|
| `kubectl get services` / `ingresses` / `configmaps` / `secrets` | Object kind not in the receiver config |
| `kubectl get hpa` / `jobs` / `cronjobs` (spec) | Only metrics, not the API object |
| `kubectl get pv` / `pvc` | Not ingested |
| `kubectl explain` / `cluster-info` / `api-resources` | Apiserver discovery, not telemetry |
| `kubectl exec` / `port-forward` / `cp` / `apply` / `delete` | Mutation / data plane, by design |
| `kubectl logs -f` | No streaming in the CLI today |

Adding a kind (e.g. `services`) is a collector-config change, not architectural.

## Worked example — OOMKilled investigation

Canonical "could the whole investigation happen in Tsuga?" walkthrough. 9 kubectl commands → 4 tsuga commands.

```bash
# 1. Which pods restarted, reason + exit code + memory limit
tsuga logs search \
  --query 'context.cluster_id:<cluster> AND k8s.resource.name:pods AND object.metadata.name:<deploy>-*' \
  --max-results 20 --from -30m \
  | jq -r '.logs[] | .object as $p | $p.status.containerStatuses[]? |
           "\($p.metadata.name)\t\(.restartCount)\t\(.lastState.terminated.reason // "n/a")\texit=\(.lastState.terminated.exitCode // "-")\tmem=\($p.spec.containers[0].resources.limits.memory // "?")"'

# 2. Event timeline for one pod
tsuga logs search \
  --query 'context.cluster_id:<cluster> AND event.domain:k8s AND object.involvedObject.name:<pod>' \
  --max-results 50 --from -30m \
  | jq -r '.logs[] | "\(.object.lastTimestamp)  \(.object.type)/\(.object.reason)\t\(.object.message)"'

# 3. Pre-OOM logs
tsuga logs search \
  --query 'context.cluster_id:<cluster> AND context.k8s.pod.name:<pod> AND level:ERROR' \
  --max-results 50 --from -30m

# 4. Memory ramp (no kubectl equivalent)
NOW=$(date +%s); FROM=$((NOW - 1800))
tsuga aggregation timeseries -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"max",field:"k8s.pod.memory.working_set"},
            filter:"context.k8s.cluster.name:<cluster> AND context.k8s.namespace.name:<ns> AND context.k8s.pod.name:<deploy>-*"}],
  groupBy:[{fields:["context.k8s.pod.name"],limit:5}],
  aggregationWindow:"5m"
}')"
```

Step 4 is strictly better than `kubectl top pod`: shows the ramp, the cliff, and the new climb in one chart. `kubectl top` is point-in-time only.

## Cross-cluster

Find every OOMKilled container across **all** clusters in the last hour (no `kubectl` equivalent — `kubectl` is bound to one context):

```bash
tsuga logs search \
  --query 'k8s.resource.name:pods AND object.status.containerStatuses.lastState.terminated.reason:OOMKilled' \
  --max-results 50 --from -1h \
  | jq -r '.logs[] | "\(.context.cluster_id)\t\(.object.metadata.namespace)/\(.object.metadata.name)"' \
  | sort -u
```
