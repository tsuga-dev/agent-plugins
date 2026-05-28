# Quickwit

Cloud-native search and log analytics engine. Data on object storage (S3/GCS). Pipeline: Metastore → Indexer → Searcher → Object Storage. Healthy: ingestion keeping up, bounded merges, low search latency, bounded WAL.

## Incident shapes

- **Ingestion backpressure** — `indexing_backpressure_micros` climbs → WAL fills, producers throttled
- **WAL saturation** — `ingest_wal_disk_used_bytes` / `wal_memory_used_bytes` near limit → ingests rejected
- **Merge storm** — `ongoing_merge_operations + pending_merge_operations` spike → search degrades
- **Search latency regression** — `leaf_searches_splits_total` high, metastore gRPC p99 spikes
- **Metastore bottleneck** — metastore saturating → all indexers and searchers affected
- **Cache miss pressure** — `cache_cache_misses_total` rising → object-storage GET volume up, slow search

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `quickwit_indexing_processed_bytes` | bytes | Indexed volume |
| `quickwit_indexing_processed_docs_total` | count | Indexed docs |
| `quickwit_write_bytes` | bytes | Bytes written to splits |
| `quickwit_search_leaf_searches_splits_total` | count | Splits touched by leaf search (high = wide) |
| `quickwit_ingest_grpc_requests_total` | count | Ingest gRPC calls |
| `quickwit_metastore_grpc_requests_total` | count | Metastore gRPC calls |
| `quickwit_ingest_grpc_request_duration_seconds` | s | Ingest RPC latency |
| `quickwit_metastore_grpc_request_duration_seconds` | s | Metastore RPC latency |
| `quickwit_indexing_backpressure_micros` | μs | Rising = can't keep up |
| `quickwit_memory_allocated_bytes` / `resident_bytes` | bytes | Memory |
| `quickwit_indexing_ongoing_merge_operations` / `pending_merge_operations` | count | Merge state |
| `quickwit_ingest_grpc_requests_in_flight` | count | Concurrent ingest |
| `quickwit_ingest_wal_disk_used_bytes` / `wal_memory_used_bytes` | bytes | WAL usage |
| `quickwit_storage_object_storage_gets_total` / `puts_total` | count | S3 GET / PUT |
| `quickwit_cache_cache_hits_total` / `misses_total` | count | Cache |

## Derived signals

- Derivative of `indexing_processed_bytes` — ingestion throughput.
- `indexing_backpressure_micros` — any sustained positive = flow control engaged.
- `ongoing + pending merge_operations` — merge backlog. High sustained = merges can't keep up.
- `cache_hits / (hits + misses)` — cache hit ratio.
- `metastore_grpc_request_duration_seconds` p99 — metastore health (often Postgres).

## Log patterns

- `ingest queue is full` — WAL pressure
- `metastore request timed out` — metastore DB slowness
- `merge failed` — merge worker errors
- `object storage request failed` — S3/GCS errors
- `indexer panicked` — indexer crash
- `searcher failed to fetch split` — cache miss + fetch failure
- `rate limited by object storage` — S3 throttling

## Gotchas

- Designed around object storage; searches hit S3/GCS. Object-storage / IAM issues cascade into ingest and search problems that look internal.
- Metastore is Postgres-backed; metastore latency spikes often trace to Postgres (see `postgres.md`).
- Merges are expensive. Ingesting faster than merge capacity causes search-time split explosion — queries touch many small splits.
- WAL is disk- AND memory-bounded; filling either throttles ingest. Tune both.
- Ingest API is at-least-once; duplicates under retry are possible.
