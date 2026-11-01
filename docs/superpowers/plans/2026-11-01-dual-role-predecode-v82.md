# Source-use Predecode v82 Implementation Plan

> Execute inline with superpowers:executing-plans; no new subagents. The user authorized continued100MHz optimization while retaining95MHz.

**Goal:** Remove opcode-to-register-role decode from the actual dequeue permission path, preserving six stages, cycles, semantics and original100MHz constraints.

**Architecture:** Derive independently from retained v78. Carry the three source-use role bits with each queued instruction. Reuse the existing generic FIFO data width: encode the role bits inverted above each32bit opcode (35bit word,70bit input). This puts roles in the same unconditional bulk-update path as opcode, including flush/invalid history; reset zero decodes to the original opcode0 role111. Keep existing info/CSR flush hold semantics. In issue, select the A raw role using the existing procedural payload selector, then apply the original invalid/fault qualification. B uses its own raw role. EXTRA_DECODE_STAGE retains combinational role decode for compatibility. No pipeline stage, stop or state-machine change.

**Alternatives:** Repeating v81 is rejected. Registering a new dequeue boundary could break the loop but may exceed the2.30% cycle budget for>4/MHz; defer it. Queue metadata predecode targets the actual reported opcode decode with no architectural latency, but its physical benefit remains unproven.

**Files:** candidate-only triha_decode.v (predecode/capture), triha_frontend.v and triha_cpu.v (explicit wiring), triha_issue.v (late qualification); reusable checks in scripts/cpu and tb/cpu. Candidate patch/manifest and evidence in docs/verification/cpu. Default RTL and other worktrees unchanged.

- [x] Write extracted real-role comparison and late-opcode poison test; parent semantic PASS/poison FAIL, genuine damaged-role negative detected.
- [x] Reconstruct v78 in a new build directory and implement only the listed changes, including the inverted reset encoding and bulk flush history.
- [x] Test all1024 relevant opcode/funct combinations, qualification X/Z and selected payload X/Z. Test actual decode FIFO roles against its actual visible opcode through reset/flush/backpressure/B-only, EXTRA0/1 and a real capture corruption negative.
- [x] Run ordered/IRQ single/dual and actual E1 recovery; run full-O2 SRAM CoreMark once with complete WB/store/profile equality to v78.
- [x] Freeze byte-replay patch/22source manifest and independently reconstruct; require all hash bindings.
- [x] Run native compile/synthesize/dev_map; verify the actual A/B role cones stop at queued role bits and qualification metadata without raw opcode decode; unknown support HOLD. Recheck CPU-only area and prior memory/predictor/branch gates.
- [x] Only after all gates pass, prepare one fresh original10ns/IO/hold/multicorner seed1 PNR. No repeat or seed sweep. Six final corner checks, report/performance consistency and frozen hashes decide acceptance.
- [x] Record final result and retain95MHz unchanged regardless of outcome. No board programming or integration changes.

Self-review: The bulk rather than info placement is necessary: FIFO opcode changes on flush while old info/CSR holds. Inverted encoding is necessary because reset opcode0 has role111. Qualification uses procedural known-true guards exactly as the old function; no ternary weakening of X/Z behavior.

Terminal: original100MHz TIMING_FAIL. Setup Slow/Fast -0.994/+2.520ns, hold +0.112/+0.099ns, MPW +3.655/+4.202ns.41 Slow endpoints fail,38 external reset to BTB WADDR and3 branch recovery CE at-0.100ns.408 outputs/30 inputs verified; no repeat PNR or default promotion.
