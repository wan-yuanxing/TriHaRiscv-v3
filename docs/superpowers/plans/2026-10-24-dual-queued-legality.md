# Retain legality with the existing instruction queue

> Execute inline with superpowers:executing-plans and requesting-code-review in the isolated CPU worktree.

**Goal:** Remove v29's actual opcode -> live invalid/CSR -> issue -> FIFO control path while preserving the complete four-state outputs, cycles and six stages.

**Architecture:** Keep current original hint decoder(valid0) for CSR base and static unit classes. Add an original decoder(valid1/fault0) before the queue, consuming the exact fault-masked payload, to obtain `illegal_in`. Store `legal_in=~illegal_in` in new info[17], with reset0 matching opcode0's illegality. Unpack matching history, set `invalid_out=valid_out && ~legal_history`, and reconstruct CSR as `csr_base_history | invalid_out | stored_faults`. This equals the former valid-dependent CSR ternary for all four scalar states. Remove both remaining post-queue decoders in EXTRA0; keep EXTRA1 unchanged. Six additional RTL metadata bits, no new external ports or cycles.

**Files:** New `tb/cpu/tb_csr_metadata_property.v`; candidate `build/cpu/dual-queued-legality-reconstructed-v30/rtl/cpu/triha_decode.v`; optional actual legality-bit corruption in `tb/cpu/tb_decode_alu_control.v`; full22-source patch/manifest/evidence under `docs/verification/cpu/dualissue_queued_legality*`.

- [x] Prove old CSR conditional and new scalar expression with all256 combinations of valid/baseCSR/illegal/fault in 0/1/X/Z; check invalid expression too, and run corruption negative.
- [x] Reconstruct v29; add legal metadata at existing capture/history location, reset legality0, original decoder valid1 without rewriting legal instruction masks or MULDIV gating. Remove only EXTRA0 post-decoders; maintain exact CSR/invalid output semantics.
- [x] Complete151+18 queue oracle MULDIV1/0 and EXTRA1, plus actual info[17] legality-state corruption negative; new natural ordered/IRQ, SRAM/profile and Cache-on runs must match complete images/WB/store/profile/measurements.
- [x] Independently review source/CSR four-state handling/frozen package, launch private original100MHz/IO/hold/multicorner20min/1500s PDS with existing IO packing. Do not alter production/integration/board/serial.
- [x] Verify actual legality FF/capture and absence of late opcode decode in CSR/invalid path, u_core area, frozen input/output/exit/stage hashes, final Slow/Fast setup/hold/MPW and consistent performance slack. All timing checks and >4 must pass on the same candidate; otherwise follow the actual remaining paths.

Independent source/terminal/package review passed. Original10ns/noRegion20min PDS launched privately; actual topology and final six STA pending. Same short4.030288 SRAM and3.084289 Cache-on estimates/complete streams/profile preserved.

Actual terminal: native0/verifier2; Slow/Fast setup -1.238/+2.612ns, hold +.092/+.054ns, MPW+3.655/+4.202ns. CPU8818LUT/4252FF/752RAM-LUT(included)/4APM/0DRM. Full frozen source/output/helper/transport and stage marks checked. All6legal FF survive with correct INIT0/control; late decoders removed, actual CSR/invalid cone has no raw opcode FF. Main remaining path is SRAM-return -> LSU format -> E2 bypass -> A wide BEQ -> PC, logic3.099ns/route7.632ns; RF index -> ALU also -1.193ns. No100MHz acceptance.
