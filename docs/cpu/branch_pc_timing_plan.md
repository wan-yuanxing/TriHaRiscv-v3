# CPU branch next-PC timing optimization

2026-10-20. Execute inline using writing-plans, executing-plans, systematic-debugging and TDD. The user approved the preceding recommendation to shorten the local-load/branch/next-PC path. Existing isolated CPU branch is retained; dc00f80 and cpu-narrow-mul-100mhz-20261020 preserve the deployed release.

**Goal:** Improve actual post-route frequency headroom without adding stalls, changing six-stage single issue, RV32IM/CSR, predictor512/512/4 with GShare=0, GCC-O2/noLTO or local-memory protocol. Keep native Windows tools, CPU-only area accounting and the original100MHz IO/hold/multicorner acceptance. No COM12, Flash, main-project Video, merge or push.

**Architecture:** First isolate the existing sequential PC and selected branch target as useful kept arithmetic results, following the existing issue-PC boundary technique. Register the original conditional choice after these results. No change to branch comparisons, priorities, invalid-slot payload, reset, hold or latency in the first candidate. The actual ADS netlist must show no branch_taken dependency entering PC carry cells. Only then spend a bounded full route. If physical evidence requires comparator changes, treat them as a separate measured candidate with the same semantic gates.

## 1. Baseline and executable contracts

- [x] Save cpu-before-branch-pc-20261020 at dc00f80. Record the parent100MHz setup+0.113/+1.821ns, hold+0.160/+0.101ns and MPW+3.655/+4.202ns. Parent timed CoreMark1646428cycles/1448453WB observations,5933CPU LUT.
- [x] Generalize scripts/cpu/check_pc_carry.py with explicit module and late-request arguments, preserving its original defaults. Run it on the actual parent's biriscv_exec synthesized module with branch_taken_r as the late request; require a real structural failure. This is a conservative local structural diagnostic, not STA.
- [x] Add tb/cpu/tb_exec_branch.v and run_redirect.ps1 -Test execbranch. Compare every public combinational/registered output against the frozen original for structured branch/ALU instructions, overflow/sign boundaries, random operands/PCs, reset, valid/invalid, hold and X/Z. Inject a real PC register corruption and require rejection. Baseline miter selects the original module; candidate selects triha_exec.

## 2. Minimal maintained derivative

- [x] Create rtl/cpu/triha_exec.v from the frozen original, retaining its notice; rename only the module and add kept sequential/branch target arithmetic boundaries before the unchanged next-PC selection. Connect both execution lanes in triha_cpu.v. Bind the derivative and integration hashes in ADAPTATIONS.json; update explicit portable and PDS source lists, leaving original vendor bytes intact.
- [x] Run execution miter positive/negative, three-seed ordered WB/store/synchronous-exception single/dual comparison and separate IRQ. Require cycle-equivalent CoreMark/CRC and two-boot system checks.
- [x] Measure actual CPU-only area; inspect the new ADS PC carry cone before routing. Bind the fresh LUT denominator into the positive/CRC-negative O2 CoreMark firmware.

## 3. Physical acceptance and delivery

- [ ] Execute one complete native100MHz board route with the unchanged parent FDC and original constraints; verify input/output hashes, all stage markers, actual Slow/Fast setup/hold/MPW, recovery/removal and performance slack. No seed sweep to hide a new critical path.
- [ ] If actual timing gives useful headroom, extend the existing board clock configuration/generation and its tests for one exact feasible higher frequency, keeping UART and cycle-counter reporting consistent. Generate and verify the actual PLL, firmware and complete higher-frequency post-route result. No frequency claim from estimated Fmax.
- [ ] Adopt/package/program only a beneficial fully accepted candidate, using already-authorized volatile Program/Verify and leaving COM12 to the user. Otherwise retain the deployed parent and preserve the measured diagnostic. Save docs/verification/cpu/branch_pc_timing.json and .md and update STATUS, verify frozen sources/staged bytes, then commit/tag a concrete outcome.

## 4. Actual path follow-up: parallel ALU decode

Candidate A completed original100MHz STA:Slow/Fast setup+0.149/+1.777ns,hold+0.152/+0.100ns,MPW+3.655/+4.202ns; independent review passed. This is only0.036ns better and adds12LUT, so is not deployed. The new actual worst path is FIFO rd_ptr->opcode[14]->ALU operand selection->result register,11logic levels and7.584ns routing(80.356%). Branch-comparator prototype is therefore retained as a separate unintegrated diagnostic, not blindly bundled.

- [ ] Preserve candidate A sources and measurements in its frozen map/route directories. Replace repeated priority assignments inside triha_exec's ALU decode with mutually exclusive operation flags, independently grouped operand sources and parallel function encoding. Keep exact instruction-mask eligibility; procedural if classification handles X/Z as before, and exact-case payload selection preserves selected Z bits. Do not broaden illegal-opcode behavior.
- [ ] Use the existing80001-vector public-interface miter and corruption negative, then recheck ordered CPU/IRQ, system, CPU-only area, exact-O2 CoreMark and actual original-constraint route. Require actual useful timing/area evidence before deployment or a higher-clock experiment. All stage/state/latency contracts remain fixed.

## 5. Select the measured comparison-sharing candidate

Candidate B (parallel ALU decode) passed all semantic/CoreMark gates but original100MHz route0911028939497Z failed setup-0.082ns,4endpoints, with CPU5987LUT. Independent review confirms no deployment. It does not replace the parent.

Candidate C restores the original ALU decode, retaining only candidate A's kept PC arithmetic and sharing the signed BLT/BGE flag, deleting the reverse-subtraction helper. A frozen build-only copy mapped5903LUT/3530FF/688distributedRAM/0DRM/4APM (30 fewer LUT than deployed parent); full80001-vector miter including X/Z passed. Reference pinned comparison-flag pattern is recorded in ADAPTATIONS.json, no external source/compiler imported. Now run the same full maintained-root validation, metric-bound CoreMark and one actual100MHz route before adoption. No relaxed constraints or predictor changes.

## 6. Bounded final physical comparison

Candidate C seed1 completed but100MHz setup is-0.029ns at5issue-PC CE endpoints; Slow/Fast hold+0.070/+0.035ns,MPW+3.655/+4.202ns. The critical path is still SRAM-return->branch compare->PC CE; clock skew-0.222ns versus parent-0.101ns contributes to this near-boundary failure. It is not accepted or programmed.

Permit exactly one bounded same-source physical comparison:placement seed8 and native hold-fix budget10(instead of5), preserving all actual100MHz/IO/hold/multicorner FDC bytes and complete functional evidence. This updates the earlier no-seed-sweep plan: it is one explicit placement/hold comparison after a29ps miss, not an open-ended search or a frequency claim. All corners, reset and performance checks must still pass. Stop this round if it fails; retain deployed dc00f80 and freeze the next design discussion around earlier PC enable/predecode. Do not lower100MHz or deploy a timing failure.

## 7. Close the actual board indicator path

The bounded C comparison(seed8/hold10) has no internal CPU timing violations, but the full system still fails one Slow setup endpoint:exit_code[5]->LED3,-0.081ns. All original IO constraints remain required. This is a distinct board-output issue, so stop changing CPU RTL and register the paired pass/fail LED decode at the existing board boundary. Indicators gain exactly one CPU clock of latency and retain asynchronous reset; heartbeat/reset LED, UART, CPU stages and software timing remain unchanged. Two board FF are excluded from CPU-only LUT/FF accounting.

- [x] Add a directed registered-indicator contract to tb/soc/tb_cpu_board.v:both nonzero/zero exit codes and done transitions must wait for a clock; captured outputs and asynchronous reset must match. The unchanged top actually fails at352ns (board-system-20261020T093242300926Z).
- [x] Implement two status LED FF in fpga/pg2l100h/rtl/triha_cpu_board_top.v. No CPU/vendor/benchmark changes.
- [ ] Complete two-boot system, fresh CPU-only map, metric-bound positive/CRC-negative CoreMark and unchanged-cycle trace comparison.
- [ ] Run at most the two existing placements1/8 with hold-fix10 and identical original constraints; verify every actual final corner and input/output. Adopt only a complete passing system result, else retain deployed parent. Do not initiate further CPU/seed experiments in this round.

## Round disposition

The final board-boundary fix passes functional/metric gates but both allowed final routes fail setup(-0.292/-0.162ns). No candidate is adopted. All original production RTL,filelists,adaptation manifest,board top and modified test runner/testbench are restored to dc00f80;new rejected RTL is removed from active sources and preserved only in build snapshots. Fresh independent parent review passes the original100MHz again. No programming or new package. The round is closed with diagnostic evidence and reusable structural checker tests,not a claimed CPU speedup. Higher-frequency work was not attempted because100MHz candidate acceptance failed. Follow-up requires earlier decode/enable design rather than further physical trials.
