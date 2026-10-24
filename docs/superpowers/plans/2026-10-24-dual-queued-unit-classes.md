# Queue the remaining static execution-unit classes

> Execute inline with superpowers:executing-plans and requesting-code-review in the existing CPU worktree.

**Goal:** Remove v28's measured instruction4 -> branch classification -> LSU payload selection -> LSU formatting path without changing cycles, six stages, firmware or timing constraints.

**Architecture:** Reuse the existing original decoder instances before the FIFO. Retain their LSU/branch/MUL/DIV/rd_valid outputs as five additional info bits per word, alongside the already-queued exec/ALU fields. All five depend on the same stored opcode and constant SUPPORT_MULDIV, not live valid/fault. Reset opcode0 produces five zeroes. Use the exact existing payload transfer/reset/flush-hold history, increasing info12->17 (30RTL bits in six words). Feed the five existing output ports from that metadata, removing their live decoder fanout. Keep invalid/CSR special handling and EXTRA_DECODE_STAGE1 unchanged. No new external ports or pipeline stages.

**Files:** `build/cpu/dual-queued-unit-classes-reconstructed-v29/rtl/cpu/triha_decode.v` only relative to v28; full22-source manifest/patch/evidence under `docs/verification/cpu/dualissue_queued_unit_classes*`; new optional class-state negative in existing `tb/cpu/tb_decode_alu_control.v`.

- [x] Confirm original class outputs depend only on opcode/constant enable, and reset opcode0 yields0. Reconstruct frozen v28. Connect five outputs on each existing input decoder, pack bits[16:12], leave old12bits unchanged; use matching unpacked output aliases. Disconnect only five live class decoder output ports in the non-extra branch.
- [x] Run complete151bit+18ALU queue oracle in MULDIV1/0 and EXTRA1 and actual info[15] branch-state corruption negative. Add true four-state opcode support vectors if needed; reuse original decoder, do not rewrite masks. Verify new control state corruption fails the independent frozen parent output comparison.
- [x] Run new whole-core ordered/IRQ, SRAM/CoreMark+profile, Cache-on CoreMark and compare exact images/full WB/store/profile/measurements to v28. Existing RF scalar and coherent issue tests remain prerequisite evidence, not claims of new runs.
- [x] Freeze original10ns/IO/hold/multicorner+existing IO packing, no region,20min/1500s physical package. Independently review the exact source transformation and all evidence, then launch private PDS.
- [x] Confirm actual metadata FF and real issue/LSU class paths originate from queued bits, not old live opcode decode; measure CPU-only area. Verify full frozen inputs/outputs/transports, native stages and final Slow/Fast setup/hold/MPW/performance slack. >4 short score and all six timing checks must pass on this same candidate. No production/integration/board/serial changes.

Same-source original I/O-mapping variant is prepared separately without the optional IOFF attribute. All original clock/I/O/hold/multicorner budgets, RTL, ELF and loaded images match the IO variant. Its terminal is separate in `dualissue_queued_unit_classes_original.json`; private directories/TEMP/logs permit authorized concurrent PDS. This compares physical representations, not simulation performance or assumed timing improvement.

Independent source/terminal/package review passed. Original10ns/noRegion20min PDS launched privately; actual topology and final six STA pending. Same short4.030288 SRAM and3.084289 Cache-on estimates/complete streams/profile preserved.

Both base variants terminal-verified: native0/verification2. IO Slow/Fast setup -.763/+2.647ns, hold +.113/+.068ns, MPW +3.655/+4.202ns; original setup -.895/+2.012ns, hold +.110/+.103ns, same MPW. Complete source/output/actual-exit/helper/stage hashes rechecked. u_core8896LUT/4248FF/752RAM-LUT(included)/4APM/0DRM in both synth/map. All30 metadata FF retained with matched original queue control; actual A classes/LSU payload cone has no raw opcodeFF. No100MHz acceptance.

- [x] Complete same-source existing compact-region+IO physical-only diagnostic in dual-queued-unit-classes-compact-physical-v29, with original budgets and separate final records.

Compact+IO also failed: native0/verification2, Slow/Fast setup -1.222/+2.625ns, hold -.078/-.066ns, MPW +3.655/+4.202ns. Full terminal hashes checked. Worst paths start actual ROM/SRAM load data; compact did not fix the memory-return/forwarding path and introduced a hold violation. Not selected.
