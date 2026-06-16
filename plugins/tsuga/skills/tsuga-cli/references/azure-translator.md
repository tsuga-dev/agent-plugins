# `az` CLI → `tsuga` Translator

For subscriptions wired to an Azure Monitor → Tsuga pipeline, most read-only `az monitor metrics tail` and CLI metric queries have a `tsuga aggregation` equivalent.

Documentation queries for Cloud Resources inventory and Azure setup:

```bash
tsuga docs get categorize/cloud-resources
tsuga docs get integrations/azure/index
tsuga docs get integrations/azure/how-to-connect-an-azure-subscription-to-cloud-resources
tsuga docs get integrations/azure/azure-services-through-opentelemetry
```

Azure Monitor pre-computes statistical aggregates server-side, so metric names embed the aggregate suffix:

```
azure_<metric>_{minimum|maximum|average|total|count}
```

Pick the suffix matching what you want — `_maximum` for saturation, `_average` for baselines, `_total` for sums. Re-aggregating with `tsuga aggregation scalar` then combines values across resources.

## What's queryable

Azure Monitor metrics for any resource published into the export pipeline. Service coverage matches what Azure Monitor exposes — VM/VMSS, AKS, ServiceBus, Storage accounts, SQL/PostgreSQL Flexible Server, Application Gateway, Event Hub, Cosmos DB, Container Apps, etc.

What's **not** ingested:

- Azure resource spec / configuration (`az vm show`, `az aks show`, `az network nic show`, …).
- Activity logs (resource provider events).
- Azure AD / RBAC / role assignments. Refuse, point at `az`.

To search by service:

```bash
tsuga metrics list --from -1h | jq -r '.[].name' | grep '^azure_' | grep -i <service>
```

Also two AKS-specific families to know about:

- `azure_kube_*` — AKS apiserver / kubelet metrics (CPU/memory allocatable, pod-phase, etc.).
- `azure_node_*` — AKS node-level (disk usage, network in/out, memory working set).

Prefer the portable `k8s.*` family for k8s metrics; the `azure_*` AKS family carries Azure subscription/RG context.

## Standard attributes (every azure_* metric)

```
context.cloud.provider                "azure"
context.cloud_account_id              Azure subscription id (UUID)
context.cloud_region                  e.g. "francecentral", "swedencentral"
context.resource_group                Azure resource group name
context.azuremonitor.subscription_id  duplicate of cloud_account_id
context.azuremonitor.tenant_id        Azure AD tenant id
context.azuremonitor.resource_id      full ARM resource id (/subscriptions/.../providers/...)
context.name                          short resource name
context.type                          Azure resource type
context.timegrain                     publish granularity (PT1M, PT5M, PT1H)
context.unit                          source unit
```

For AKS, `context.metadata_*` tags are also exposed (`metadata_node`, `metadata_nodepool`, `metadata_vmname`, etc.) — sourced from VMSS / VM tags.

## Worked examples

### VM / VMSS — CPU

```bash
NOW=$(date +%s); FROM=$((NOW - 1800))
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"max",field:"azure_percentage_cpu_maximum"}}],
  groupBy:[{fields:["context.name"],limit:10}]
}')"
```

`context.name` is the short VM / scale-set name. For full ARM addressing use `context.azuremonitor.resource_id`.

### ServiceBus — dead-letter depth

```bash
NOW=$(date +%s); FROM=$((NOW - 1800))
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"max",field:"azure_deadletteredmessages_minimum"}}],
  groupBy:[{fields:["context.name"],limit:10}]
}')"
```

Related: `azure_activemessages_minimum` (queue depth), `azure_incomingmessages_total` (producer rate), `azure_outgoingmessages_total` (consumer rate), `azure_messages_minimum` (total).

Use `_minimum` for depth (latest sampled minimum), `_total` for rates.

### Storage account — used capacity

```bash
NOW=$(date +%s); FROM=$((NOW - 7200))   # storage publishes hourly (PT1H)
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"max",field:"azure_usedcapacity_average"}}],
  groupBy:[{fields:["context.name"],limit:5}]
}')"
```

Storage account metrics publish on PT1H — windows shorter than ~2h often return empty.

### Multi-dimensional grouping — subscription × resource group

```bash
NOW=$(date +%s); FROM=$((NOW - 1800))
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"max",field:"azure_percentage_cpu_maximum"}}],
  groupBy:[
    {fields:["context.azuremonitor.subscription_id"],limit:3},
    {fields:["context.resource_group"],limit:3}
  ]
}')"
```

**Separate `groupBy` entries**, not multi-field arrays.

## AKS — Kubernetes metrics

AKS clusters ingest the OTel `k8s.*` family. Use the `kubectl` translator pattern with `context.k8s.cluster.name:<aks-cluster>`:

```bash
NOW=$(date +%s); FROM=$((NOW - 600))
tsuga aggregation scalar -d "$(jq -n --argjson from $FROM --argjson to $NOW '{
  timeRange:{from:$from,to:$to},
  dataSource:"metrics",
  queries:[{aggregate:{type:"max",field:"k8s.pod.cpu.usage"},filter:"context.k8s.cluster.name:<aks-cluster>"}],
  groupBy:[{fields:["context.k8s.pod.name"],limit:5}]
}')"
```

See `${CLAUDE_PLUGIN_ROOT}/skills/tsuga-cli/references/kubectl-translator.md`.

## Gotchas specific to Azure

1. **Pick the right aggregate suffix**. `azure_percentage_cpu` exists as `_average`, `_count`, `_maximum`, `_minimum`, `_total` — each is a separate metric definition. `_minimum`/`_maximum` are sampled extremes within Azure's pre-aggregation window (usually 1m); re-aggregating with `tsuga aggregation scalar` `type:"max"` then folds across resources.
2. **`prometheus_azure_*` mirror exists** for many metrics. Prefer the bare `azure_*` form — the `prometheus_` mirror is normalized differently and sometimes appends the unit (`_Bytes`, `_Count`).
3. **Publish cadence varies wildly** — 1m for compute, 5m for some platform services, 1h for storage. If a query returns empty, widen `--from` first.
4. **One field per `groupBy` entry**. Multi-field arrays fail with `400 must NOT have more than 1 items` — use multiple entries.
5. **`context.name` is short, `context.azuremonitor.resource_id` is canonical**. Two VMs in different resource groups can share a short name; group on `azuremonitor.resource_id` if name collisions matter.
6. **Subscription id is the canonical cloud account**. `context.cloud_account_id` and `context.azuremonitor.subscription_id` are the same value.

## What's not coverable

| `az` verb | Reason |
|---|---|
| `az vm show` / `az aks show` / `az sql db show` / any `show` | Spec data; not ingested |
| `az monitor activity-log list` | Activity log not wired |
| `az role assignment list` / `az ad ...` | Identity, out of scope |
| `az servicebus message ...` | Data plane |
| Anything that writes / mutates | By design |
