# Redis

In-memory KV store, single-threaded command loop. Healthy: stable throughput, low rejections, memory under control, bounded tail latency.

## Incident shapes

- **Memory pressure / eviction storm** — `used_memory` near `maxmemory`, evictions rise → check memory
- **Latency regression** — one O(N) command blocks the loop → check slowlog + command mix
- **Connection admission failure** — `rejected_connections` rises as `connected_clients` hits cap → check connections
- **Persistence spikes** — `BGSAVE` / `BGREWRITEAOF` fork overhead → check `latest_fork_usec`

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `redis.uptime` | seconds | Reset = restart / crash |
| `redis.clients.connected` | clients | Connection-utilization numerator |
| `redis.clients.blocked` | clients | Consumer bottleneck indicator |
| `redis.connections.rejected` | count/s | Any nonzero = admission failure |
| `redis.memory.used` | bytes | Memory-utilization numerator |
| `redis.memory.rss` | bytes | Compare to `used` for fragmentation |
| `redis.memory.fragmentation_ratio` | ratio | > 1.5 = waste; < 1 = swap risk |
| `redis.commands.processed` | cmds/s | Throughput (monotonic counter; use per-second) |
| `redis.keyspace.hits` / `misses` | 1/s | Hit-ratio components |
| `redis.keys.evicted` | 1/s | Cache: expected in moderation; datastore: never |
| `redis.keys.expired` | 1/s | Burst expirations can spike latency |
| `redis.cpu.sys_seconds_total` | cpu-s/s | Main-thread CPU |
| `redis.latest_fork_usec` | μs | Last fork duration; spikes during BGSAVE |
| `redis.replication.offset` | offset | Primary vs replica; delta = lag |

## Derived signals

- `clients.connected / maxclients` — connection utilization. Alert > 0.85.
- `keyspace.hits / (hits + misses)` — hit ratio. Cache: > 0.95.
- `memory.used / maxmemory` — memory utilization. Cache: > 0.85 → eviction imminent.
- `memory.rss / memory.used` — fragmentation. 1.0-1.5 healthy.

## Log patterns

- `OOM command not allowed when used memory > 'maxmemory'` — memory cap hit under `noeviction`
- `MISCONF Redis is configured to save RDB snapshots` — persistence failure blocks writes
- `Error condition on socket for SYNC: Connection reset by peer` — replication broke
- `LOADING Redis is loading the dataset in memory` — startup state; clients see errors
- `Background saving started` / `terminated with success` — BGSAVE lifecycle

## Gotchas

- `commands.processed` is monotonic; use `per-second`. Don't trend the instantaneous `commands` gauge.
- Clustered Redis: group by `context.scope` to see per-node pressure. Cluster average hides hot nodes.
- `used_memory` excludes allocator overhead; `rss` includes it. Alerting only on `used_memory` misses swap risk.
- `keys.evicted = 0` does NOT prove health under `noeviction` policy — writes may be silently failing with OOM.
- Blocking commands (`BLPOP`, `WAIT`, `XREAD BLOCK`) are normal for some workloads. `clients.blocked > 0` isn't automatically bad.
