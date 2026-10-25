# Dual branch boundary implementation plan

**Goal:** Preserve `-O2` SRAM performance above 4 CoreMark/MHz and close the original 10ns post-route constraints in an isolated candidate.

**Architecture:** Freeze the predictor's next PC on the accepted instruction request. Carry it through the existing response skid and each queued instruction without adding a pipeline stage. Then validate branch resolution from the existing E1 operand registers, using the frozen prediction for speculative PC advance and a qualified recovery event to cancel younger side effects.

**Tools:** Existing Windows ModelSim, PDS and RISC-V GCC. Production `rtl/cpu`, integration trees and board configuration are excluded.

## Evidence and first checkpoint

- [x] Audit v40 terminal outputs and record its rejection; v32 remains best at setup -0.539ns.
- [x] Add `tb/cpu/tb_prediction_metadata.v`: accepted-request oracle, variable response latency, changing live predictions, backpressure/skid, partial dequeue, flush and stale responses. Missing metadata must fail on the first valid queued instruction.
- [ ] Reconstruct v32 with `scripts/cpu/prepare_dual_candidate.py` into `build/cpu/dual-prediction-metadata-v41`.
- [ ] In that snapshot only, append a maintained renamed fetch derivative to `triha_frontend.v`; capture `next_pc_f_i` with `pc_d_q/pred_d_q`, extend the existing skid packet, and expose it to decode.
- [ ] Extend `triha_decode.v` and its FIFO payload by 32 bits per instruction. A predicted-taken word carries the frozen target; a non-taken word carries its own PC+4. Preserve dequeue/flush timing and EXTRA_DECODE_STAGE behavior.
- [ ] Run the new oracle with `HAS_METADATA=1`; a negative replacing stored metadata with the live predictor must fail. Compare existing frontend/ordered checks and full SRAM runs with v32. The already launched v41 Cache run is historical only; no further Cache/DDR work after the user scope change.
- [ ] Preserve a full production-base patch plus source hashes and independently review the changes.

## Branch boundary checkpoint

- [ ] Extend an independent branch oracle to compare actual outcome, target, call/return flags and four-state inputs against the frozen v32 module.
- [ ] Reuse E1 opcode/PC/operand registers for branch resolution. Move branch NPC/misalignment selection to the E1-to-E2 boundary. Preserve CSR/IRQ/fault priority and A-not-taken/B-LSU pairing.
- [ ] Advance expected PC from the selected instruction's stored prediction. On a real prediction mismatch, cancel younger issue/LSU requests, redirect, flush queued instructions, and handle a held branch once. Never stall away an older LSU completion.
- [ ] Run ordered branch/store/MMIO/IRQ/fault tests and a real wrong-path-store negative, then fresh full SRAM CoreMark. Record actual cycle changes; do not substitute the hypothetical recovery penalty for measurement.
- [ ] Only a candidate meeting functional/performance gates proceeds to a private original-constraint PDS run. Check frozen inputs/outputs, native exits, Slow/Fast setup/hold/MPW and performance consistency. No production promotion before all gates pass.

Run examples use `python scripts/cpu/run_dual_diagnostic.py --firmware-run build/cpu/firmware-coremark-20261023T1103533439788Z --cpu-dir <snapshot>/rtl/cpu --testbench tb/cpu/tb_prediction_metadata.v --top tb_prediction_metadata --marker PRED_METADATA_PASS --generic HAS_METADATA=1`, the existing SRAM/cache runners, and `run_dual_route.ps1 -AllowConcurrentPds`. Keep failed snapshots and logs.

Current checkpoint: v41 transport and v42 E1 boundary implemented and independently reviewed. SRAM4.029441/MHz passes; held-completion, wrong-path store negative and A/B misalignment tests pass. Original10ns PDS is running. Cache/DDR work is deferred by the user.

Follow-up from measured v42 STA: recovery gates queue accept before compaction, producing an18-level E1-to-queue-CE path and -0.607ns. v43 allows legal branch+ALU pairs only, clearing B E1->E2 state/tag on A recovery/fault; fresh SRAM4.078280/MHz and ordered/IRQ plus real no-kill negative pass. v44 computes normal queue dequeue before recovery cancellation because the same-edge flush overrides it; external execution remains cancelled. Compare full runtime/traces before a fresh original10ns PDS run. Keep CSR/fault priority and old LSU completion unchanged.

v44 final actual STA moved to local SRAM collision feedback→fetch activation (-1.035ns). v45 separates actual MMU activation policy from REGISTER_REDIRECT timing reuse. It is explicitly limited to current finite-response side-effect-free local instruction memory; delivery/drop checks and MMU1 compatibility pass. SRAM images/traces/cycles are identical; original10ns PDS is running. No further cache/DDR work.
