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

Execution update, 2026-10-22: two cached private-DDR board runs and one
shared-uncached board run completed with valid5000-iteration CRC/duration.
The user explicitly selected the shared-address comparison after compile-time
Cache-off failed DDR initialization. It retains Cache hardware and uses a
different link address/attribute; it is not same-address Cache off/on.
Result:84.374480817 versus10.231936873CoreMark. See
docs/verification/cpu/id_cache_board_coremark_comparison.md/.json.

DDR startup remains unresolved: reset-held Program/Verify preceded one valid
shared run but did not prevent an init failure on cached-image restoration.
Keep the cached e5503c690208 image programmed/verified. The user requested
serial-assistant ownership and brief KEY0 reset instead of prolonged manual
holding; automatic capture is closed. Do not reopen COM12 or reprogram while
the user inspects it. No Flash or main-worktree changes.
