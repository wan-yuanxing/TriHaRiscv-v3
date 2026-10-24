# Keep branch target arithmetic ahead of the decision

**Goal:** Cut the actual v20 I/O-pack route's late BEQ decision -> PC carry chain without changing any behavior, latency or state.

**Architecture:** The execution RTL already expresses branch target addition independently, but native mapping re-factors the final branch/PC+4 choice into a carry chain. Keep the complete target and sequential PC+4 result nets before the existing ternary. Retain all12 public execution outputs,137bits, original unknown-condition merge, reset/valid/hold behavior, immediate/JALR alignment and branch policy. This follows the ordinary separate target-address calculation and branch-decision mux; no new predictor or stage.

**Tech stack:** Existing Windows Verilog/ModelSim/PDS/GCC15.2 -O2.

Evidence: v20 original best -0.805ns launches RF written metadata through B signed branch; independent I/O-pack v20 -1.198ns launches PC selection through A operand forwarding/BEQ and then5carry groups into execution PC. Both are real post-route original10ns failures. The current experiment isolates the latter address-arithmetic mapping problem; the other RF path may remain. Original timing budgets and no-region stay fixed; no I/O packing for the first v21 route, which uses the better original physical parent option.

- [x] Reuse complete137-bit execution oracle on parent and a PC-specific corruption negative; existing BGE negative remains.
- [x] Reconstruct v20 into isolated v21; keep2complete result nets and change only their consumers. Preserve22-source patch/manifest.
- [x] Complete137-bit oracle/negatives, packet/pending/coherent B-MUL, ordered/IRQ and fresh SRAM/Cache-on full stream/profile comparison.
- [x] Independent source/evidence/frozen-package review, then new original10ns private PDS.
- [x] Actual mapping must retain arithmetic results before late decision; final six timing checks plus same-source >4/MHz remain mandatory.

Independent source/terminal/package review passed. Original10ns/noRegion/noIO20min PDS launched privately; actual topology and final six STA pending. Same short4.030288 SRAM and3.084289 Cache-on estimates/complete streams/profile preserved.

Terminal original10ns: -1.168ns setup; native0/verifier2, 427 outputs rehashed. CPU-only {'lut': 8772, 'ff': 4055, 'distributed_ram': 752, 'apm': 4, 'drm36k_equivalent': 0.0}. All scores/streams unchanged,100MHz failed; no adoption or production promotion. See bound JSON for all six exact rows.
