# Database Playbook

For Postgres / MySQL / RDS / Aurora / connection-pool symptoms. Common trap: treating the loudest metric (usually CPU) as the cause.

Concrete metrics + queries in `$knowledge-technology/postgres.md`, `/mysql.md`, `/aws-rds.md`. This file is reasoning disambiguation only.

## Connection exhaustion vs CPU saturation

- `active_connections` ≥ 95% of `max_connections` → `resource_exhaustion` via connection exhaustion. High CPU = secondary symptom of accumulated idle sessions.
- Both near 100% → look for **one shared cause** (pool leak holding scan-heavy queries), not two problems.
- Single bad query driving CPU ≈ 100% with connections + storage healthy → `resource_exhaustion` via CPU saturation. Check missing indexes, full-table scans, ReadIOPS spike.

## Storage exhaustion

- `FreeStorageSpace → 0` blocks all writes; WriteIOPS collapses, WriteLatency spikes.
- Metric missing? Infer from: WriteIOPS collapse + WriteLatency spike + RDS event "ran out of storage space".

## Checkpoint storm / VACUUM FREEZE

High CPU + dominant `LWLock:BufferMapping` wait + massive WriteIOPS = I/O storm from checkpointing. Category `resource_exhaustion` (I/O), NOT `code_defect`. CPU is downstream.

## Replication lag

- Write-heavy primary exceeds replica replay → `ReplicaLag` spikes. Cause = write workload on primary, `resource_exhaustion`.
- A concurrent analytics query on the replica may cause high CPU but doesn't explain lag. Don't pin on CPU when the failing metric is `ReplicaLag`.
- `ReplicaLag` missing? Infer from RDS events ("exceeded 900s") + high `TransactionLogsGeneration`.

## Compositional faults

Two independent workloads causing two separate faults simultaneously (e.g. analytics SELECT → CPU saturation AND audit_log INSERT → storage exhaustion) — identify BOTH. Do NOT merge them into a single "IOPS fault" or single `resource_exhaustion` line.

Protocol when compositional:
- Explicitly state "two independent, coincidental faults" in the verdict.
- Provide evidence for each cause separately (analytics query evidence, audit_log query evidence).
- Trace each causal chain separately in `Causal chain`.
- Category stays `resource_exhaustion` with a multi-part ROOT_CAUSE describing both.

Connection growth during a blocked-writer incident = symptom of queued writes, NOT connection exhaustion. Similarly, `ReplicaLag` growth during a primary write burst is a downstream symptom, not an independent fault. NEVER diagnose `connection_exhaustion` when connections spike because writes are blocked.

## Misleading context

- RDS event timestamps: ignore historical events (maintenance, failover, promotion) from hours before the incident.
- Oscillating metrics within normal bounds (connections 55-65%, CPU 40-70%, no errors) = `healthy`. Briefly-crossed threshold that autoscaling recovered before investigation = stale alert, `healthy`.

## Causal chain skeletons

- Connection leak: new PR → driver skips release on early-return → idle sessions grow → max_connections hit.
- Missing index: new query path → full scan → ReadIOPS spike → CPU saturation → latency → upstream timeouts.
- Checkpoint storm: VACUUM FREEZE → massive WAL → checkpoint flush → I/O saturation → all queries slow.
