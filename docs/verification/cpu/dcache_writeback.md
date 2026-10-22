# Private DDR D Cache write-back checkpoint

2026-10-22. Candidate: `D:/FPGA/TriHaRiscv-cpu-windows`, branch
`cpu/windows-baseline`. Backup `cpu-before-writeback-20261022` points to
`942e405`. Board remains on `cpu_ddr_coremark_on_32019ccd2f69`; this work
does not access COM12, program the FPGA, or write Flash.

## Behavior and maintenance ABI

Private DDR `0x80000000..0x81ffffff` now uses blocking write-back and write
allocation. Geometry stays 16KiB D, two ways, 256 sets, 32-byte lines,
synchronous RAM. I Cache, six-stage single-issue CPU, predictor, GCC `-O2`
without LTO, and registered load return are unchanged. Shared DDR
`0x82000000..0x87ffffff` and MMIO remain uncached.

A cached store updates bytes and sets dirty locally. A dirty victim is written
as eight scalar words through the accepted AXI/DDR write-and-readback path.
Its dirty tag is cleared only after all eight real lower responses succeed.
On failure the entire cached line stays valid and dirty, refill does not start,
and the owning operation receives an error. Earlier words may already have
reached DDR; retry writes the entire line. This coalesces repeated stores;
it does not introduce a posted DDR buffer or a new burst-write transport.

| Operation | Meaning | Completion |
|---|---|---|
| CSR `0x3a1`, address in source register | Clean matching line; retain valid | After all dirty words acknowledged; absent/clean is a no-op |
| CSR `0x3a2`, address in source register | Discard matching line, including dirty data | After invalidation; no writeback |
| CSR `0x3a0` | Clean/invalidate all sets and ways | After complete sweep, or first writeback error |
| `FENCE.I` | Drain prior D ownership, clean/invalidate D, then invalidate I | DDR fetch/data acceptance blocked until complete |

Before handing private cached data to DMA, clean every affected line and
execute `fence rw,rw` before publishing ownership. After an external writer
finishes, discard affected lines before CPU reads; do not clean stale dirty
data over DMA output. Shared DDR needs no cache maintenance but still needs
ordering/ownership. Actual shared CPU/NPU/Video integration is a separate gate.

FENCE.I has no lower error-response channel. A failed internal clean raises a
sticky protocol fault and blocks new DDR fetch/data until coordinated reset;
it never resumes with stale instructions. Reset starts a destructive cache
epoch. Software must clean before a planned reset if data must survive.
An unresponsive external bus can still require system supervision/reset.

## Functional evidence

- `build/cpu/cache-writeback-20261022T134735986736Z`: all 15 byte masks;
  all eight writeback-error positions; retry, dirty/failed replacement,
  complete/failed flush, lowest/highest set, clean idempotence, discard after
  external writes, shared bypass, failed write allocation and coordinated reset.
  This test against saved write-through RTL fails at the first allocation check.
- `build/cpu/cache-joint-20261022T134735253426Z`: paired I/D, FENCE.I visibility,
  fence arriving during a D allocation, failed-FENCE.I fail-stop and reset recovery.
- `build/cpu/cache-writeback-20261022T135351701454Z`: deliberate corrupt-data
  negative returns failure on an architectural load mismatch. The prior missing
  fault parameter was caught in independent review and fixed. Registered-load
  validation mode passes in `build/cpu/cache-components-20261022T134539112956Z`.
- `build/cpu/cache-cpu-20261022T132758910433Z`: real CPU self-modifying code,
  maintenance, allocation faults and younger-store cancellation; bypass mode:
  `build/cpu/cache-cpu-20261022T133248944646Z`.
- `build/cpu/cache-soc-runtime-20261022T133040560919Z`: real local SoC runtime;
  `build/cpu/ddr-system-20261022T133513190889Z`: native DDR and coordinated live
  reset. Monitors check actual external writes, each still requiring native
  masked readback, rather than requiring DDR traffic for every cached store.
- `build/cpu/ddr-board-20261022T135003212875Z`: two-boot board-wrapper digital
  self-test. No-init, init-loss, stopped-DDR-clock and CPU-PLL-loss also pass.
  Digital substitutes do not establish physical training or board acceptance.
  Full six-case independent review, including real shared-store readback
  corruption rejection: `build/cpu/ddr-writeback-board-digital-review-20261022.json`.

## Same-payload digital CoreMark

Five iterations, GCC15.2, `-O2`, no LTO, identical loaded payload and native DDR
model. Independent comparison:
`build/cpu/ddr-writeback-review-20261022T133834923712Z/result.json`.

| Observation | Write-through | Write-back |
|---|---:|---:|
| Timed cycles | 3,899,101 | 2,158,431 |
| Short CoreMark/MHz estimate | 1.282346879 | 2.316497493 |
| CPU store observations | 70,840 | 70,840 |
| Lower writes in timed window | 70,840 | 0 |
| Native read commands in timed window | 71,082 | 226 |

Cycles fall 44.642855%; modeled throughput rises 80.645154%. All 1,448,453 WB
and 70,840 store observations match except the initial absolute timestamp.
Standard CRCs match. These are short RTL/model results, not official or board
scores. Dirty data remains cached at timer stop; explicit maintenance/eviction
visibility is separately tested. Profile counts now distinguish writeback words,
uncached writes and write allocations while retaining historical WT parsing.

## Resources and physical gate

Native mapping: `build/cpu/ddr-board-route-20261022T133145884093Z`.
CPU only: 6,459 LUT / 3,562 FF / 688 distributed RAM LUT included / 0 DRM /
4 APM. Cache plus transport: 671 LUT / 807 FF / 11 DRM. Context-specific
hierarchy is separate from DDR, CDC, board supervision and fixtures.
The five-iteration diagnostic's UART retained prior 6,477-LUT metadata;
it is not a new physical LUT-efficiency result.

The 5,000-iteration build uses the new 6,459 CPU-only denominator. Actual
post-route 100MHz passes in `build/cpu/ddr-board-route-20261022T134054417226Z`.
Independent frozen-input/output/tool/stage review:
`build/cpu/ddr-board-route-20261022T134054417226Z-independent-review.json`.

| CPU timing slack | Slow | Fast |
|---|---:|---:|
| Setup | +0.134 ns | +3.629 ns |
| Hold | +0.153 ns | +0.100 ns |
| Minimum pulse width | +3.655 ns | +4.202 ns |

All clock domains' setup/hold/recovery/removal/MPW summaries pass. All 60 Gray
max-delay paths and all 20 Slow/Fast skew groups pass; worst skew slack is
+1.323ns, largest actual skew 0.677ns under the original 2ns constraint.
Performance slack agrees with worst CPU setup. No IO, hold, clock or corner
constraint was relaxed. Compared with the WT parent setup +0.314ns, margin is
smaller by 0.180ns, with a new netlist and layout; no Fmax increase is claimed.
This is the standalone CPU/DDR physical boundary, not shared-SoC or board-score
acceptance. The deployed board image remains unchanged.

## Prepared release

`build/soc/releases/cpu_ddr_coremark_on_418eb7d376c5` contains the timing-admitted
write-back image, its verification mask, full 5,000-iteration `-O2` CoreMark,
ELFs/maps, frozen routed database, constraints and timing review. Bitstream
SHA256 is `418eb7d376c50c68dd5914dfb4374f8fb26df3c8f0ea909e0d8f0ba84ae3d178`.
UART prints CPU-only LUT denominator 6,459 and CoreMark/LUTs. Generation and
package-copy hashes were rechecked. No board download or physical score is
part of this implementation checkpoint. Machine-readable evidence is in
`dcache_writeback.json`.
