# Dual-issue performance implementation plan

> Execute in the existing independent worktree. Use test-driven development,
> systematic debugging and verification-before-completion for implementation.

**Goal:** Complete Cache-off/on comparisons and pursue >4 CoreMark/MHz on
the user-selected SRAM/TCM boundary with unchanged -O2.

**Architecture:** Keep the six-stage core, shared LSU/multiply and public
interfaces; first measure stalls and pair rejection before choosing RTL work.

**Tech Stack:** Existing Windows Python/PowerShell, Verilog, ModelSim, GCC/PDS.

- [x] Confirm target boundary: user selected SRAM/TCM maximum.
- [x] Launch actual single/dual DDR bypass CoreMark5 runs with existing runner.
- [x] Compare all four DDR results using loaded image and ordered WB/store
  evidence; publish the complete table with CRC/duration/memory scope.
- [x] Add passive `tb/cpu/tb_dual_profile.v` and native snapshot runner
  `scripts/cpu/run_tcm_profile.py`. Reuse the accepted firmware image. The
  observer counters must sum to actual rdcycle elapsed time and match WB.
- [x] Run baseline profile; classify genuine/unused-field dependencies,
  pairing and shared-resource limits. Check the profile is nonintrusive.
- [x] Select the measured minimum candidate, write a failing contract test,
  preserve baseline and candidate snapshots, then implement and rerun it.
- [x] Reject real hazard/data corruption, rerun ordered streams, exception/IRQ
  tests and same-program CoreMark. Retain only measured useful candidates.
- [x] Record actual scores and remaining gap to >4; no claim before measured.
- [ ] Assess CPU-only resources and original-constraint physical timing when
  PDS is free; preserve SoC/Video/NPU worktrees and board configuration.

## Measured continuation

- [x] Resolved not-taken branch pairing, directed RED/GREEN and corruption negative.
- [x] Cross-packet four-word queue with independent word/metadata and capacity oracle.
- [x] ISA role-qualified hazards, retaining genuine RAW/WAW and shared-unit waits.
- [x] TCM short estimate >4: 1249840 cycles, 4.000512/MHz; nonobserver reproduction.
- [x] Remeasure the same candidate with DDR Cache on/off; compare complete streams.
- [x] Explicit branch/LSU exception, pending-fetch IRQ and CSR idle-boundary checks.
- [x] Preserve a byte-reproducible diagnostic patch/manifest and independent review.
- [ ] Physical resource/timing admission and board scores; shared integration tools untouched.

## Latest scope correction

- DDR Cache-off is historical only; no further performance work or acceptance there.
- TCM >4 is provisional until actual postroute 100MHz passes for the same candidate.
- Prepare the dual-issue physical boundary; the old route runner only accepts single issue.
- Preserve active SoC physical work; do not infer tool availability from a single process snapshot.

## Real SRAM continuation

- [x] Bind the candidate to actual synthesizable ROM/SRAM/MMIO boundary.
- [x] Repeat nonobserver measurement with passive cycle and pair-rejection partitions.
- [x] Verify loaded images and repeated full WB/store trace equality.
- [x] Prepare frozen dual-route execution wrapper; preflight and parser checks only.
- [ ] Quantify queue occupancy/full-response backpressure before further RTL changes.
- [ ] Execute fresh PDS when integration has released the physical tools; extract CPU-only area.
- [ ] Meet >4/MHz and actual 100MHz with the same candidate; current SRAM 3.987597, timing UNKNOWN.
