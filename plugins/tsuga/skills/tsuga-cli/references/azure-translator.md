# `az` CLI -> `tsuga` Translator

Use this for read-only Azure Monitor metric equivalents in Tsuga. During skill execution, emit `tsuga` commands only. Do not add shell pipes, JSON processors, Azure CLI commands, or mutation commands.

## Metric Naming

Azure Monitor pre-computes statistical aggregates, so Tsuga metric names include the source aggregate suffix:

```text
azure_<metric>_{minimum|maximum|average|total|count}
```

Pick the suffix matching the question: `_maximum` for saturation, `_average` for baselines, `_total` for sums, `_minimum` for depth-style gauges when Azure emits that shape.

## What Is Queryable

Queryable: Azure Monitor metrics published into the export pipeline.

Not queryable:

- Azure resource spec/config from `az * show`
- Activity logs unless separately ingested
- Azure AD/RBAC/role assignments
- Data-plane reads or mutations

Discover available Azure metrics with:

```bash
tsuga metrics list --from <from> --to <to>
```

Manually inspect metric names beginning with `azure_`, then confirm attributes with:

```bash
tsuga metrics get <azure_metric_name> --from <from> --to <to>
```

## Standard Attributes

- `context.cloud.provider`
- `context.cloud_account_id`
- `context.cloud_region`
- `context.resource_group`
- `context.azuremonitor.subscription_id`
- `context.azuremonitor.tenant_id`
- `context.azuremonitor.resource_id`
- `context.name`
- `context.type`
- `context.timegrain`
- `context.unit`

## Azure Coverage Notes

| Family | Metric hints / dimensions |
|---|---|
| VM / VMSS | `azure_percentage_cpu_*`; group by `context.name` or `context.azuremonitor.resource_id`. |
| AKS | `azure_kube_*`, `azure_node_*`; prefer portable `k8s.*` metrics unless subscription, resource-group, or `context.metadata_*` tag context matters. |
| ServiceBus | `azure_deadletteredmessages_*`, `azure_activemessages_*`, `azure_incomingmessages_*`, `azure_outgoingmessages_*`; group by `context.name`. |
| Storage | `azure_usedcapacity_*`; group by `context.name`; storage metrics may publish hourly. |
| SQL/PostgreSQL Flexible Server, Application Gateway, Event Hub, Cosmos DB, Container Apps | Exact `azure_*` names depend on Azure metric name plus aggregate suffix; confirm with `tsuga metrics list` and `tsuga metrics get`. |

## Aggregation Template

Use this shape with one row from the use-case map. Confirm metric presence and attributes with `tsuga metrics get <azure_metric_name> --from <from> --to <to>` before relying on it.

```bash
tsuga aggregation scalar -d '{
  "timeRange": {"from": <from_unix>, "to": <to_unix>},
  "dataSource": "metrics",
  "queries": [
    {"aggregate": {"type": "<aggregate>", "field": "<metric>"}}
  ],
  "groupBy": [{"fields": ["<dimension>"], "limit": <limit>}],
  "formula": "q1"
}'
```

For filtered cases, add `"filter": "<filter>"` inside the query object. For multiple dimensions, use separate `groupBy` entries.

## Use-Case Map

| Use case | Metric | Aggregate | Group by | Filter / notes |
|---|---|---|---|---|
| VM / VMSS CPU | `azure_percentage_cpu_maximum` | `max` | `context.name` | Use `context.azuremonitor.resource_id` if names collide. |
| ServiceBus dead-letter depth | `azure_deadletteredmessages_minimum` | `max` | `context.name` | Depth-style gauge; confirm suffix with `metrics get`. |
| Storage account used capacity | `azure_usedcapacity_average` | `max` | `context.name` | Storage metrics may publish hourly; use about a 2h+ window. |
| Subscription x resource group | `azure_percentage_cpu_maximum` | `max` | `context.azuremonitor.subscription_id`, then `context.resource_group` | Use separate `groupBy` entries, not one multi-field entry. |
| AKS pod CPU | `k8s.pod.cpu.usage` | `max` | `context.k8s.pod.name` | Filter `context.k8s.cluster.name:<aks-cluster>`; prefer portable Kubernetes metrics when present. |

## Gotchas

- Use separate `groupBy` entries; each `fields` array should contain one field.
- `context.name` is short and can collide; `context.azuremonitor.resource_id` is the canonical ARM identity.
- AKS may expose `context.metadata_*` tags such as node, nodepool, and VM name; confirm per metric with `tsuga metrics get`.
- Prefer bare `azure_*` metrics over `prometheus_azure_*` mirrors unless `tsuga metrics get` proves the mirror has the shape you need; mirrors can be normalized differently.

## Safety

- Use explicit `--from`/`--to` or Unix-second `timeRange`.
- Do not infer Azure resource inventory from metrics alone; idle resources may be absent.
- Refuse Azure spec/RBAC/data-plane/mutation requests from this skill and point the user to Azure tooling.
