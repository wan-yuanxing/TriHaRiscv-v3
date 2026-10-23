# D Cache Store Overlap Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans in this existing
> isolated worktree; request independent review at the final checkpoint.

**Goal:** Reduce conflict-free cached-store completion bubbles with measured
CoreMark and resource benefit while retaining actual 100MHz admission.

**Architecture:** Keep registered load responses. Add STORE_UPDATE acceptance
only for an ordinary request to a different cache set. Same-set, maintenance,
error and uncached completing transactions retain the serial path.

**Tech Stack:** Windows PowerShell/Python, Verilog, ModelSim, PDS, RISC-V GCC15.2.

## Tasks

- [x] Preserve `febadb3` with `cpu-before-store-overlap-20261023`; independently
  review and physically capture release `cpu_ddr_coremark_on_478149ee9e63`.
  Entry: `python scripts/cpu/capture_ddr_coremark.py
  build/soc/releases/cpu_ddr_coremark_on_478149ee9e63 --seconds 180`.
- [x] Add `tb/cpu/tb_cpu_dcache_store_overlap.v`, explicitly selected by
  `scripts/cpu/run_cache.py --test store-overlap`. Use public data/tag/accept/ack
  checks with a shadow-memory oracle and synchronous native RAM. First require
  a failure on the missing store-response acceptance in unchanged parent RTL.
- [x] In `rtl/cpu/triha_dcache.v`, OR the following condition into
  `accept_phase_w`, then update only its derived manifest SHA256:

  ```verilog
  state_q == STORE_UPDATE && cacheable_q && !response_error_q &&
  !mem_flush_i && !mem_writeback_i && !mem_invalidate_i &&
  mem_addr_i[12:5] != addr_q[12:5]
  ```

  Existing request capture and synchronous read address selection then serve
  the next LOOKUP; old write address/data/way stay selected by current state.
- [x] Run the new test to PASS; run prior `overlap`, `writeback`, `components
  --store-response-check`, `joint`, `cpu`, bypass CPU, SoC and native DDR
  tests. Corrupt-data negatives must still be rejected.
- [x] Add a separate store-edge counter to the simulation-only profiler in
  `tb/soc/cpu_ddr_coremark_profile.vh`, and parse/check it in
  `scripts/cpu/ddr_profile.py` with an explicit unit test. Keep historical
  load-overlap parsing and results readable.
- [x] Run five-iteration `scripts/cpu/run_ddr_coremark.py --iterations 5 --profile` against
  the same payload. Extend `scripts/cpu/review_ddr_writeback.py` with a distinct
  store-overlap comparison mode: matching policies/events/traces, positive
  store-edge count and strictly lower cycles. Save rejection/no-gain if not met.
- [x] If useful, run native area, use the measured CPU LUT denominator to build
  5000-iteration firmware and matching one-iteration preflight, then use
  `scripts/cpu/run_ddr_board_route.py --firmware-dir <full> --coremark-preflight
  <short>`. Independently review final actual timing before packaging.
- [x] Request code/evidence review; rerun applicable Python/preflight checks,
  audit frozen evidence, update `docs/verification/cpu/dcache_store_overlap.md`
  and JSON plus `docs/cpu/STATUS.md`, and commit only this CPU work. Preserve
  main worktree and all immutable releases. Leave COM12 released at completion.

## Execution outcome

All test/comparison/resource gates and final evidence review are complete.
The conditional full-implementation step was evaluated and skipped at the
resource gate: CPU-LUT efficiency decreased0.24724444% for0.73387994% modeled
throughput gain. No candidate timing or deployment claim. The current parent
was physically measured and retained; source restoration and patch replay are
verified. New component RTL/test/runner/profiler changes are archived in the
replay patch rather than left active. Backward-compatible historical evidence
parsers remain. See `docs/verification/cpu/dcache_store_overlap.md/.json` and
`dcache_overlap_board.md/.json` for complete result bindings.
