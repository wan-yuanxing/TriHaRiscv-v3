# Dual-issue cached baseline implementation plan

> Execute sequentially in the independent dual-issue worktree using the
> writing-plans, test-driven-development and verification-before-completion
> workflows. The user has authorized continuation of this workstream.

**Goal:** Validate the existing dual-issue CPU behind the accepted cache
boundary and obtain a same-software performance baseline.

**Architecture:** Existing six-stage dual pipeline and shared memory interface;
parameterize the cached wrapper and its test harness, preserving default zero.

**Tech Stack:** Verilog, Windows PowerShell/Python, ModelSim, GCC15.2 `-O2`.

- [x] Create independent worktree at fixed accepted CPU revision.
- [x] Run single/dual smoke with two rejected negatives.
- [x] Complete same-ELF TCM CoreMark/runtime/WB-probe comparisons and record
  actual metrics and limitations.
- [x] Add a failing cached dual CPU test before changing production wrapper.
  The existing TB must reject a requested dual mode while the core remains
  hardwired to zero; preserve the real RED result.
- [x] Add `DUAL_ISSUE=0` to `rtl/cpu/triha_cached_core.v` and forward it to
  `triha_core`. Update only that derived-file receipt in CACHE_ADAPTATIONS.
- [x] Extend `tb/soc/tb_cpu_cache_cpu.v` and `scripts/cpu/run_cache.py` with
  explicit mode selection, actual parameter checks, paired-issue checks and
  both-lane WB observation. Leave unrelated component cases single-mode.
- [x] Run cached CPU and -O2 CoreMark in both modes; compare loaded ELF segments,
  CRCs and ordered WB/store observations. Run an actual corruption negative.
- [x] Run relevant preflight/Python checks and independent source/test review.
- [x] Save baseline evidence under `docs/verification/cpu/` and commit only
  this workstream's explicit paths. Keep physical acceptance as a later gate.

## 2026-10-23 verification checkpoint

Cached single/dual CoreMark5 now passes at 2,014,969 / 1,781,952 cycles,
same loaded program and identical ordered WB/store tails after the independently
checked initial cycle timestamp. Throughput gain is 13.076503%; WB-observation
IPC is 0.718844 / 0.812843. These are short RTL results, not board/official scores.

An old lower-write coverage assertion rejected a resident write-back working
set. Preserve both original failures and the instrumented RED. Require real
Cache data-RAM store updates, retain lower-write coverage for directed/uncached
cases, and rerun CoreMark plus CRC/data negatives. Those checks have completed.
No production Cache behavior was changed.

Independent review and 74 Python tests pass. CPU-only native area and actual
100MHz remain UNKNOWN; this batch does not launch PDS while the independent
SoC integration task is preparing its physical implementation. Full evidence:
`docs/verification/cpu/dualissue_cached_baseline.md` and `.json`.
