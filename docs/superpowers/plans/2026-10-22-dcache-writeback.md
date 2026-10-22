# D Cache write-back implementation plan

## Goal

Change only the private DDR data-cache policy from blocking write-through/no-write-allocate to blocking write-back/write-allocate. Shared DDR, MMIO, local memory, the registered load-return boundary, and the 100 MHz timing constraints remain unchanged. Existing board release `cpu_ddr_coremark_on_32019ccd2f69` remains the rollback point.

## Files and responsibilities

- `config/cpu_cache.json`, `scripts/cpu/check_cache.py`, `scripts/cpu/run_cache.py`: make write-back and write-allocate an explicit, validated policy.
- `rtl/cpu/triha_dcache_tag_ram.v`: preserve native synchronous RAM inference while adding valid/dirty/tag storage.
- `rtl/cpu/triha_dcache.v`: adapt the recorded upstream write-back controller, retaining TriHa private-range gating, error propagation, registered load response, maintenance ordering, and dirty-data retention on failed writeback.
- `rtl/soc/triha_cpu_cache_axi.v`: preserve the accepted scalar-write transport. Initially a dirty line is written as eight response-checked 32-bit writes. Burst packing can be measured later if dirty eviction bandwidth becomes a bottleneck; it is unnecessary for eliminating per-store DDR traffic and would enlarge this correctness/timing change.
- `rtl/cpu/CACHE_ADAPTATIONS.json`, `config/cpu_cache_sources.f`, and generated source manifests: record derived hashes and the unchanged upstream originals.
- `tb/cpu/tb_cpu_cache.v`, `tb/soc/tb_cpu_cache_axi.v`, `tb/soc/tb_cpu_cache_joint.v`, `tb/soc/tb_cpu_cache_cpu.v`: test dirty hits, write allocation, eviction, maintenance, uncached bypass, backpressure, and errors using a backing-memory oracle separate from cache state.
- `tb/soc/cpu_ddr_coremark_profile.vh`, `scripts/cpu/ddr_profile.py`, and related tests: count cache stores, dirty writeback lines, scalar uncached writes, and refills separately.
- `docs/verification/cpu/ddr_performance.md` and a new status record: report exact traces and distinguish RTL/model results from physical board results.

## Red/green steps

1. Extend preflight tests to accept only the explicit write-back/write-allocate policy and reject malformed policy values or shared-range cacheability.
2. Add failing component tests for a store miss allocating a line, repeated store hits producing no lower write, dirty eviction writing the victim line, failed writeback retaining the dirty line, and flush/writeback completion ordering.
3. Reuse transport tests for byte masks, backpressure, B response errors, and ID/protocol errors; add dirty-line word sequencing/error-retention tests at the cache boundary.
4. Implement the smallest controller/transport changes to make those tests pass without changing the load response register boundary.
5. Add CPU/SoC tests for private write coalescing, shared and MMIO bypass, FENCE.I visibility, DMA clean/invalidate handoff, and reset/error recovery.
6. Run component, transport, joint, CPU, and exact-window CoreMark comparisons. Record lower transaction counts and CRC identity.
7. Run native CPU-only mapping and the bounded 100 MHz post-route flow with the original IO/hold/multicorner constraints. Do not call tool completion timing closure.
8. Keep the existing board image unless a later explicit board-programming request authorizes replacement.

## Acceptance

The change is admissible only when all new tests pass, the same CoreMark payload has zero CRC errors, external writes fall below the write-through baseline, source/input/output hashes are frozen, and the actual post-route Slow/Fast setup, hold, and pulse-width checks all pass. If routing or timing fails, retain the current board release and report the measured failure without weakening constraints.

## Execution checkpoint

Implemented and functionally/physically verified 2026-10-22. Actual 100MHz
post-route Slow/Fast setup +0.134/+3.629ns; hold +0.153/+0.100ns; pulse width
+3.655/+4.202ns; all clocks, reset checks and Gray delay/skew pass.
Five-iteration same-payload native-DDR RTL cycles 3,899,101 -> 2,158,431;
timed lower writes 70,840 -> 0; architectural WB/store traces agree except
initial absolute timestamp. Native CPU-only 6,459 LUT / 3,562 FF; cache and
transport 671 LUT / 807 FF / 11 DRM. New release prepared; prior board image
preserved. Details: `../../verification/cpu/dcache_writeback.md` and JSON.
