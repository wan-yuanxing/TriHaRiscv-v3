# Cache / DDR CoreMark physical measurement

2026-10-22. User approved: complete standalone DDR board checks first, then
measure Cache off/on CoreMark at 100MHz, GCC15.2 -O2, no LTO. Work stays on
cpu/windows-baseline; no main-worktree edits, Flash, merge, push or new tools.
The prior SRAM deployment package stays immutable; volatile board replacement
and read-only COM12 capture are now authorized for this measurement.

1. Revalidate stage5 route and all diagnostic-package hashes. Start UART capture
   before volatile Program/Verify of the identified PG2L100H. Require actual
   DDR ready, private/shared 8192-byte checks and FENCE.I, then repeat with KEY0.
   Any failure blocks CoreMark hardware measurement until diagnosed.
2. Reuse existing CoreMark sources, port and native DDR board boundary. Execute
   code and work data from private DDR, with SRAM startup/copy before timing.
   Keep loaded benchmark bytes, placement, compiler flags, predictor and clock
   identical across Cache off/on; avoid adding UART output to the timed region.
   Require native short simulation/CRC negative and actual 100MHz physical
   admission of each hardware image before programming it.
3. Measure at least ten seconds per physical run with valid standard CRCs.
   Record raw UART, cycles, instruction count/its precise observation scope,
   CoreMark, CoreMark/MHz and CoreMark/LUTs. Bind area to the exact image;
   report CPU-only and CPU+Cache denominators separately. Preserve the old
   SRAM result as a different-memory baseline, not a Cache on/off comparison.

Stage5: docs/verification/cpu/id_cache_stage5.md/.json. This plan does not
admit shared CPU/NPU/Video fabric or substitute simulation for physical DDR.
