# AWS ECS

Managed container orchestrator (EC2 or Fargate capacity). Healthy: running tasks = desired, no restart loops, CPU/memory within reservation.

## Incident shapes

- **Task restart loop** — `ecs_containerinsights_restart_count` climbs → bad deploy, missing secret, failed health check
- **Scheduler starvation** — `ecs_containerinsights_desired_task_count > ecs_containerinsights_running_task_count` → cluster lacks capacity
- **Memory pressure / OOM** — `ecs_containerinsights_memory_utilized / ecs_containerinsights_memory_reserved → 1.0` → OOM-killed
- **CPU throttling** — `ecs_containerinsights_cpu_utilized / ecs_containerinsights_cpu_reserved → 1.0` sustained → requests queue
- **Ephemeral-storage exhaustion** — Fargate ephemeral disk full → ENOSPC
- **Deployment stuck** — `ecs_containerinsights_deployment_count > 1` long → new revision never goes healthy

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `ecs_containerinsights_running_task_count` | count | Tasks in RUNNING |
| `ecs_containerinsights_pending_task_count` | count | Waiting to be placed |
| `ecs_containerinsights_desired_task_count` | count | Target from service |
| `ecs_containerinsights_deployment_count` | count | > 1 = in-progress rollout |
| `ecs_containerinsights_restart_count` | count | Delta-over-window = restart count |
| `aws_ecs_cpu_utilization` | % | Cluster-level |
| `aws_ecs_memory_utilization` | % | Cluster-level |
| `ecs_containerinsights_cpu_utilized` / `ecs_containerinsights_cpu_reserved` | cpu-units | Per-task / service |
| `ecs_containerinsights_memory_utilized` / `ecs_containerinsights_memory_reserved` | bytes | Per-task / service |
| `aws_ecs_cpu_reservation` / `aws_ecs_memory_reservation` | % | Cluster reservation pressure |
| `ecs_containerinsights_ephemeral_storage_utilized` / `Reserved` | bytes | Fargate ephemeral disk |
| `aws_ecs_ebs_filesystem_utilization` | % | EBS-backed tasks |
| `ecs_containerinsights_network_rx_bytes` / `TxBytes` | bytes | Per-task traffic |

## Derived signals

- `ecs_containerinsights_running_task_count / ecs_containerinsights_desired_task_count` — readiness. < 1.0 after rollout = stuck.
- `ecs_containerinsights_memory_utilized / ecs_containerinsights_memory_reserved` — saturation. > 0.85 sustained = OOM risk.
- `ecs_containerinsights_cpu_utilized / ecs_containerinsights_cpu_reserved` — CPU saturation. > 0.8 + throttling = under-provisioned.
- `aws_ecs_cpu_reservation + aws_ecs_memory_reservation` — cluster reservation pressure. Near 100% = no placement headroom.
- `Δ ecs_containerinsights_restart_count` over 5m — any steady positive = unhealthy service.

## Log patterns

- `Essential container in task exited` — essential container died; task stops
- `Unable to place a task because no container instance met all of its requirements` — scheduler can't fit
- `OutOfMemory: Container killed by the kernel` — OOM
- `CannotPullContainerError` — image pull failed
- `ResourceInitializationError: unable to pull secrets or registry auth` — secrets/ECR auth
- `Task failed ELB health checks` — health-check failure
- `exited with code 137` — SIGKILL (usually OOM)
- `exited with code 139` — SIGSEGV

## Gotchas

- `ecs_containerinsights_running_task_count == ecs_containerinsights_desired_task_count` doesn't prove health; tasks can flip RUNNING between crashes. Check `ecs_containerinsights_restart_count` delta too.
- Fargate vs EC2 expose different metric subsets. Fargate has no instance-level metrics.
- Cluster-level `aws_ecs_cpu_utilization` averages across instances; one hot instance can hide.
- Soft vs hard memory limits: soft is unlimited when cluster has headroom. Under-provisioned soft limits are a common silent failure.
- During scale-down, `ecs_containerinsights_running_task_count > ecs_containerinsights_desired_task_count` is normal, not an incident.
