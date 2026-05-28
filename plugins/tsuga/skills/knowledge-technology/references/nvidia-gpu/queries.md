# NVIDIA GPU (DCGM)

GPU-accelerated workloads: ML training, inference, graphics. Metrics from NVIDIA DCGM exporter. Healthy: utilization as expected, temperature within bounds, no XID errors, no row-remap failures.

## Incident shapes

- **XID error** — `DCGM_FI_DEV_XID_ERRORS` nonzero → hardware / driver fault
- **Memory exhaustion** — `DCGM_FI_DEV_FB_FREE → 0` → next CUDA alloc fails
- **Thermal throttling** — high `GPU_TEMP`, `SM_CLOCK` / `MEM_CLOCK` drops → performance degrades
- **ECC / row-remap failure** — `ROW_REMAP_FAILURE > 0` = hardware failing (replace GPU)
- **PCIe degradation** — `PCIE_REPLAY_COUNTER` climbs → link errors, bandwidth throttled
- **Underutilization** — `GPU_UTIL` low while app busy → CPU bottleneck or dataloader starved

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `DCGM_FI_DEV_GPU_UTIL` | % | SM utilization |
| `DCGM_FI_DEV_MEM_COPY_UTIL` | % | Memory-copy engine |
| `DCGM_FI_DEV_ENC_UTIL` / `DEC_UTIL` | % | Encoder / decoder (video) |
| `DCGM_FI_DEV_FB_USED` | MiB | VRAM in use |
| `DCGM_FI_DEV_FB_FREE` | MiB | VRAM free |
| `DCGM_FI_DEV_GPU_TEMP` | °C | Core temp |
| `DCGM_FI_DEV_MEMORY_TEMP` | °C | Memory temp |
| `DCGM_FI_DEV_SM_CLOCK` | MHz | SM clock; drops = throttle |
| `DCGM_FI_DEV_MEM_CLOCK` | MHz | Memory clock |
| `DCGM_FI_DEV_POWER_USAGE` | W | Power draw |
| `DCGM_FI_DEV_TOTAL_ENERGY_CONSUMPTION` | J | Cumulative energy |
| `DCGM_FI_DEV_XID_ERRORS` | count | Any nonzero = fault |
| `DCGM_FI_DEV_PCIE_REPLAY_COUNTER` | count | Any sustained = bad link |
| `DCGM_FI_DEV_CORRECTABLE_REMAPPED_ROWS` | count | Corrected rows |
| `DCGM_FI_DEV_UNCORRECTABLE_REMAPPED_ROWS` | count | Uncorrected; deterioration |
| `DCGM_FI_DEV_ROW_REMAP_FAILURE` | count | Replace GPU |
| `DCGM_FI_DEV_NVLINK_BANDWIDTH_TOTAL` | bytes/s | Multi-GPU NVLink |
| `DCGM_FI_PROF_PCIE_TX_BYTES` / `RX_BYTES` | bytes | PCIe throughput |

## Derived signals

- `FB_FREE / (FB_USED + FB_FREE)` — VRAM headroom. Near 0 = OOM imminent.
- `SM_CLOCK` drop at high `GPU_TEMP` = thermal throttle; at high `POWER_USAGE` = power cap.
- Derivative of XID / PCIE_REPLAY / UNCORRECTABLE_REMAPPED — any nonzero = hardware issue.
- `GPU_UTIL` during training — low = pipeline bottleneck (CPU, dataloader, small batch).

## Log patterns

Host dmesg / journal:

- `NVRM: Xid (PCI:...): N` — XID error (79=GPU fall-off, 13=GR exception, 31=MMU fault, 64=ECC)
- `NVRM: GPU ... has fallen off the bus` — GPU dropped PCIe; often needs node reboot
- `NVRM: Unrecoverable DMA buffer` — driver-level fault
- `NVIDIA-SMI has failed` — driver crash
- Workload: `CUDA out of memory` / `cuda.OutOfMemoryError` — framebuffer exhausted
- `CUDA error: unspecified launch failure` — corrupted kernel / race

## Gotchas

- XID errors are numeric IDs, not severities. Some benign (driver reset), some fatal (79). Keep a decoder handy.
- `GPU_UTIL` is a 1-second sample. Many short kernels can show high util with low FLOPs; use DCGM_FI_PROF_* for throughput.
- Framebuffer metrics include CUDA context overhead (~300MiB per process). OOM can hit even when FB_FREE looks safe with many small contexts stacking.
- MIG partitions expose per-partition metrics; aggregate at GPU level hides per-partition exhaustion.
- On time-sliced K8s GPUs, `GPU_UTIL` is sum across slots — slot bottlenecks may not be visible.
- `ROW_REMAP_FAILURE > 0` = replace the GPU. Don't try to keep scheduling workloads on it.
