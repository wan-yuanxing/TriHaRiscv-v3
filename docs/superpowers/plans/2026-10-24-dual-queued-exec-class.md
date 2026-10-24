# Carry execution classification in the existing fetch queue

**Goal:** Cut actual v23 fetch1 opcode -> wide execution classification -> LSU payload/address/store-format path without adding a stage or cycle.

**Architecture:** Reuse the existing two input decoder instances that already prepare CSR history. Capture their exec outputs alongside fault bits in the current FIFO info payload (OPC_INFO_W2->3, six entries). Use that exact retained classification at each queue output, leaving all other post-queue decoding and CSR/invalid valid-gating intact. The decoder's exec output depends only on the stored opcode, so its value commutes with the existing queue's reset/shift/append/flush-history operations. Reset opcode0 has exec0. Extra-decode-stage mode is unchanged; no new public ports, queue behavior, issue policy, cache behavior or latency.

**Tech stack:** Existing native Windows Verilog/ModelSim/PDS/GCC15.2 -O2.

v23 region trial did not improve timing: setup-1.283ns, hold/MPW pass. Its actual path is fetch1 opcode bit2 -> classification (including issue_a_exec) -> lsu_payload_b(69loads) -> load address/store formatting. The new v24 reconstructs the better v20 RTL and original noRegion/noIO physical option, rather than stacking the failed physical experiment. This is the same frontend predecode/sideband pattern already present in EXTRA_DECODE_STAGE and CSR history, adapted to the existing capture boundary.

- [x] Whole151-bit output comparison against frozen v20 decoder+FIFO, including inactive output history, faults, X/Z opcodes and controls; parent PASS and exec corruption FAIL. Exercise MulDiv on/off and unchanged extra-stage mode.
- [x] Reconstruct v24 and connect input exec metadata, grow info by1, replace only output exec consumers. Preserve full22-source patch/manifest.
- [x] Decoder/FIFO, packet/coherent B-MUL, ordered/IRQ and new SRAM/Cache-on whole images/WB/store/profile comparisons, same cycles and >4/MHz.
- [x] Independent source/state and frozen physical package review; original10ns noRegion/noIO20min PDS.
- [ ] Actual metadata/decode mapping, CPU-only resources and final six STA checks; no production/board operation.

Independent source/terminal/package review passed. Original10ns/noRegion/noIO20min PDS launched privately; actual topology and final six STA pending. Same short4.030288 SRAM and3.084289 Cache-on estimates/complete streams/profile preserved.
