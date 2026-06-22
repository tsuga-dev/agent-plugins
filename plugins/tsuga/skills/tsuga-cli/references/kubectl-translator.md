# `kubectl` -> `tsuga` Translator

Use this as a read-only translation guide. During skill execution, emit `tsuga` commands only. Do not add shell pipes, JSON processors, `kubectl`, or mutation commands.

## What Tsuga Can See

- Container logs: `tsuga logs search --query "context.k8s.pod.name:<pod>" --from <from> --to <to> --max-results 10`
- Kubernetes events: `event.domain:k8s` plus `object.*` fields
- Kubernetes object snapshots: records with `k8s.resource.name:<kind>`
- Kubernetes metrics: `k8s.*` / container metric families exposed through `tsuga metrics list`

Kinds commonly present as object snapshots: `pods`, `events`, `nodes`, `deployments`, `replicasets`, `statefulsets`, `daemonsets`.

Kinds commonly absent as object snapshots: `services`, `ingresses`, `configmaps`, `secrets`, `serviceaccounts`, `horizontalpodautoscalers`, `jobs`, `cronjobs`, PV/PVC, and RBAC kinds. Some still appear as metrics.

## Cluster And Namespace Scoping

- `--cluster` selects the Tsuga regional endpoint, not the Kubernetes data scope.
- Scope data with `context.cluster_id:<cluster>` or `context.k8s.cluster.name:<cluster>`.
- Namespace filters use `object.metadata.namespace:<ns>` for object snapshots and `context.k8s.namespace.name:<ns>` for container logs.

## Common Reads

### Discover shipped object kinds

```bash
tsuga logs search --query "k8s.resource.name:*" --from <from> --to <to> --max-results 10
```

Inspect returned `k8s.resource.name` values. Use `tsuga logs patterns` when you need scale instead of raw samples.

### Pods in a namespace

```bash
tsuga logs search --query "context.cluster_id:<cluster> AND k8s.resource.name:pods AND object.metadata.namespace:<ns>" --from <from> --to <to> --max-results 10
```

Inspect `object.metadata.name`, `object.status.phase`, `object.status.podIP`, `object.spec.nodeName`, and `object.status.containerStatuses[]`.

Flag mapping:

| `kubectl` flag | `tsuga` modification |
|---|---|
| `-A` | drop the namespace clause |
| `-l app=X` | add `context.kube_app_name:X` when that label is indexed |
| `--field-selector status.phase=Running` | add `object.status.phase:Running` |

Arbitrary Kubernetes labels are not guaranteed to be indexed; inspect object snapshots before assuming a label filter exists.

### Warning events

```bash
tsuga logs search --query "context.cluster_id:<cluster> AND event.domain:k8s AND object.type:Warning" --from <from> --to <to> --max-results 10
```

Useful filters:

| Want | Filter |
|---|---|
| Events for one pod | `event.domain:k8s AND object.involvedObject.name:<pod>` |
| CrashLoopBackOff | `event.domain:k8s AND object.reason:BackOff` |
| Unhealthy probes | `event.domain:k8s AND object.reason:Unhealthy` |
| Image pull failures | `event.domain:k8s AND object.reason:Failed AND object.message:*pull*` |
| FailedScheduling | `event.domain:k8s AND object.reason:FailedScheduling` |

Summarize event structure. Do not reproduce raw event messages verbatim.

### Container logs

```bash
tsuga logs search --query "context.cluster_id:<cluster> AND context.k8s.namespace.name:<ns> AND context.k8s.pod.name:<pod>" --from <from> --to <to> --max-results 10
```

Flag mapping:

| `kubectl` flag | `tsuga` modification |
|---|---|
| `-n <ns>` | add `context.k8s.namespace.name:<ns>` |
| `-c <container>` | add `context.k8s.container.name:<container>` |
| `--tail=<N>` | use `--max-results <N>`, capped at 10 for raw samples |
| `--since=<dur>` | use explicit `--from` / `--to` |
| `--previous` | widen `--from` past the previous container death |
| `-f` | not supported |

### OOMKilled triage

```bash
tsuga logs search --query "context.k8s.cluster.name:<cluster> AND k8s.resource.name:pods AND object.metadata.namespace:<ns> AND object.metadata.name:<pod>" --from <from> --to <to> --max-results 10 --fields timestamp,object.status.containerStatuses,object.spec.containers,object.spec.nodeName
tsuga logs search --query "context.k8s.cluster.name:<cluster> AND event.domain:k8s AND object.involvedObject.name:<pod>" --from <from> --to <to> --max-results 10 --fields timestamp,object.type,object.reason,object.involvedObject.name
tsuga logs search --query "context.k8s.cluster.name:<cluster> AND context.k8s.namespace.name:<ns> AND context.k8s.pod.name:<pod> AND level:ERROR" --from <from> --to <to> --max-results 10
```

For cross-cluster OOM scope:

```bash
tsuga aggregation scalar -d '{
  "timeRange": {"from": <from_unix>, "to": <to_unix>},
  "dataSource": "logs",
  "queries": [
    {"aggregate": {"type": "count"}, "filter": "k8s.resource.name:pods AND object.status.containerStatuses.lastState.terminated.reason:OOMKilled"}
  ],
  "groupBy": [
    {"fields": ["context.k8s.cluster.name"], "limit": 20},
    {"fields": ["object.metadata.namespace"], "limit": 50},
    {"fields": ["object.metadata.name"], "limit": 100}
  ],
  "formula": "q1"
}'
```

### Pod CPU and memory

```bash
tsuga aggregation scalar -d '{
  "timeRange": {"from": <from_unix>, "to": <to_unix>},
  "dataSource": "metrics",
  "queries": [
    {"aggregate": {"type": "max", "field": "k8s.pod.cpu.usage"}, "filter": "context.k8s.cluster.name:<cluster> AND context.k8s.namespace.name:<ns>"}
  ],
  "groupBy": [{"fields": ["context.k8s.pod.name"], "limit": 20}],
  "formula": "q1"
}'
```

For memory, run a separate query:

```bash
tsuga aggregation scalar -d '{"timeRange":{"from":<from_unix>,"to":<to_unix>},"dataSource":"metrics","queries":[{"aggregate":{"type":"max","field":"k8s.pod.memory.usage"},"filter":"context.k8s.cluster.name:<cluster> AND context.k8s.namespace.name:<ns>"}],"groupBy":[{"fields":["context.k8s.pod.name"],"limit":20}],"formula":"q1"}'
```

### Nodes, deployments, and cross-restart logs

```bash
tsuga logs search --query "context.k8s.cluster.name:<cluster> AND k8s.resource.name:nodes AND object.metadata.name:<node>" --from <from> --to <to> --max-results 10 --fields timestamp,object.metadata.name,object.status.conditions,object.status.nodeInfo
tsuga logs search --query "context.k8s.cluster.name:<cluster> AND context.k8s.namespace.name:<ns> AND k8s.resource.name:replicasets AND object.metadata.ownerReferences.kind:Deployment AND object.metadata.ownerReferences.name:<deployment>" --from <from> --to <to> --max-results 10 --fields timestamp,object.metadata.name,object.metadata.annotations,object.status
tsuga logs search --query "context.k8s.cluster.name:<cluster> AND context.k8s.namespace.name:<ns> AND context.k8s.pod.name:<deploy>-*" --from <from> --to <to> --max-results 10 --fields timestamp,level,context.k8s.pod.name,context.k8s.pod.uid,context.k8s.container.name,message
```

### Metric inventory gotchas

Run `tsuga metrics get <metric> --from <from> --to <to>` before math. Useful native families include `k8s.pod.phase`, `k8s.pod.cpu.usage`, `k8s.pod.memory.usage`, `k8s.container.ready`, `k8s.container.restarts`, `k8s.container.status.reason`, `k8s.container.cpu_limit`, `k8s.container.cpu_request`, `k8s.container.memory_limit`, `k8s.container.memory_request`, `k8s.node.condition_ready`, `k8s.node.cpu.usage`, `k8s.node.memory.usage`, `k8s.deployment.available`, and `k8s.deployment.desired`.

Gotchas: `k8s.pod.phase` stores phase as the metric value, not a phase attribute. Request/limit ratios are meaningless when limits or requests are unset. Object-event details can be missing even when metric inventory exists.

## No Tsuga Equivalent

| `kubectl` | Reason |
|---|---|
| `kubectl get services` / `ingresses` / `configmaps` / `secrets` | Object kind often not ingested |
| `kubectl explain` / `cluster-info` / `api-resources` | Apiserver discovery, not telemetry |
| `kubectl exec` / `port-forward` / `cp` / `apply` / `delete` | Mutation or data plane, out of scope |
| `kubectl logs -f` | No streaming in the CLI |

## Safety

- Never execute Kubernetes commands from this skill.
- Raw log/event fetches stay at `--max-results 10`; use patterns or aggregation for scale.
- If `context.sensitive == "true"` appears, stop reproducing sample details.
