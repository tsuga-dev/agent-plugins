# JVM

Java / Kotlin / Scala / Clojure runtime. Healthy: memory growing and collecting cleanly, brief GC pauses, stable threads, reasonable CPU, FD headroom.

## Incident shapes

- **Memory leak / OOM** — `memory.used` grows + `memory.used_after_last_gc` also grows → GC can't reclaim
- **GC pause storms** — `gc.duration` p99 spikes → app pauses, requests stall
- **Thread leak** — `thread.count` grows unboundedly → pool / executor not shutting down
- **Class-load thrash** — `class.loaded - class.unloaded` grows → dynamic-class libs leaking
- **CPU saturation** — `cpu.recent_utilization ≈ 1` sustained → GC overhead, hot loop, or real work
- **Direct memory exhaustion** — `buffer.memory.used` near limit → off-heap leak (Netty, NIO)
- **FD exhaustion** — `file_descriptor.count / limit` near 1 → socket/file leak

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `jvm.memory.used` (pool) | bytes | Heap / non-heap per pool |
| `jvm.memory.committed` (pool) | bytes | Committed from OS |
| `jvm.memory.limit` (pool) | bytes | Max heap / non-heap |
| `jvm.memory.used_after_last_gc` (pool) | bytes | Post-GC survivors — growth = true leak |
| `jvm.gc.duration` (action, gc) | ms | GC pause duration |
| `jvm.thread.count` | count | Live threads; growth = leak |
| `jvm.class.loaded` / `unloaded` / `count` | count | Class load state |
| `jvm.cpu.time` | ns | Cumulative JVM CPU |
| `jvm.cpu.recent_utilization` | ratio | Recent JVM CPU |
| `jvm.system.cpu.utilization` | ratio | Host CPU |
| `jvm.system.cpu.load_1m` | load | Host load |
| `jvm.buffer.memory.used` / `limit` | bytes | Direct / mapped buffers |
| `jvm.buffer.count` | count | Buffer allocations |
| `jvm.file_descriptor.count` / `limit` | count | FD state |

## Derived signals

- `memory.used{heap} / memory.limit{heap}` — heap utilization. Near 1 sustained = GC overhead, OOM risk.
- Trend of `memory.used_after_last_gc` — leak indicator. Monotonic = leak.
- GC time / wallclock — GC overhead. > 0.1 sustained = GC starving the app.
- `thread.count` slope under steady workload — positive = leak.
- `1 - file_descriptor.count / file_descriptor.limit` — FD headroom. < 0.1 = accept errors soon.

## Log patterns

- `java.lang.OutOfMemoryError: Java heap space` — heap OOM
- `java.lang.OutOfMemoryError: Direct buffer memory` — off-heap OOM
- `java.lang.OutOfMemoryError: GC overhead limit exceeded` — GC > 98% CPU recovering < 2% heap
- `java.lang.OutOfMemoryError: unable to create native thread` — thread/OS limit
- `Full GC (Allocation Failure)` — full GC from heap pressure
- `Pause Young (G1 Evacuation Pause)` with high ms — long G1 pause
- `java.net.SocketException: Too many open files` — FD exhaustion
- `java.lang.StackOverflowError` — deep recursion

## Gotchas

- `memory.used` oscillates with GC; `used_after_last_gc` is the trending metric (removes the sawtooth).
- G1, ZGC, Shenandoah have very different pause profiles. Normal G1 (occasional 100ms) is abnormal on ZGC (sub-10ms).
- "Memory used" covers heap + managed non-heap. Direct / mapped buffers are in `buffer.memory.used` and leak independently.
- Pooled thread leaks may not show in `thread.count`; they show in CPU, scheduling latency, or stack dumps.
- Class-load growth with flat unload count = permgen/metaspace leak (dynamic-class libs like CGLib).
- K8s memory limits apply at the OS level. JVM `-Xmx` > pod memory limit → OOM-killed with no Java-side OOM.
