# CPU predecode and early PC-enable: measured outcome

2026-10-20. The final combination passes actual100MHz post-route timing but is **not selected**: no CoreMark gain, more resources and less timing margin than the deployed CPU. Active CPU/SoC/board/software/configuration/test/runner sources were restored to dc00f80. Only the prior diagnostic structural tools remain from acc2537. No COM12 access, programming, Flash, main-project change, merge or push occurred.

| Candidate | CPU LUT | CPU FF | Worst actual100MHz setup | Outcome |
|---|---:|---:|---:|---|
| Deployed dc00f80 |5933|3528|+0.113ns|Retained|
| ALU predecode only |6002|3564|-0.088ns|7failing endpoints|
| Early issue-PC CE only |5970|3528|-0.092ns|1failing endpoint|
| Final combination |6009|3564|+0.006ns|Timing passes; no net benefit|

All use unchanged100MHz/IO/hold/multicorner constraints,seed1,hold-fix5 and fresh complete native implementation. CPU-only counts include688distributed-RAM LUT,0CPU DRM and4APM. Different netlists/layouts prevent attributing WNS differences to one cell. No seed sweep or relaxed constraint.

The nine-bit ALU descriptor is captured with each instruction in the existing FIFO, following original free-slot/flush/reset/invalid-payload/lane rules in both decoder configurations. Native PC CE uses CSR redirect or raw execution validity; D retains original priority and IRQ-suppressed-advance hold. Six stages, cycles and predictor algorithm remain fixed. Local final-map review confirms32PC FF and CE=CSR|raw-valid, ignoring shared-LUT IRQ/PC data pins; this is not full formal equivalence.

## Verification and metrics

Full137-output execution miter passes211073cases, including every opcode/funct3/funct7 combination, structured boundaries, illegal words,X/Z,reset and hold. Both FIFO latency modes and issue-width PC-enable tests pass. PC and ADDI-descriptor corruption are rejected. Three ordered WB/store/synchronous-exception seeds in single/dual mode, independent IRQ and two-boot8KiB system checks pass. All48existing Python checks pass after parent restoration.

Every candidate retains five-iteration-O2/noLTO CoreMark1646428cycles,1448453WB observations and70840real stores; complete timed WB/store hashes and exclusive stall counts equal deployed dc00f80. WB observations are not fully verified architectural instret. CoreMark/MHz remains3.036877410. At nominal100MHz, CoreMark/LUT falls0.051186203->0.050538815(-1.26477%); LUT rises76(+1.28097%),FF36. CRC faults produce errors1/exit1 and are rejected. Full5000firmware was built,not simulated or physically scored. These are RTL measurements,not official submissions or new board scores.

## Actual physical result

Route `build/soc/board-route-20261020T1216593867303Z`:native/host return0,frozen inputs/outputs,PLL/pins,stage and report checks all pass. Independent `build/soc/pc-combined-route-review.json` confirms `timing_closed=true`. Slow/Fast setup+0.006/+1.752ns,hold+0.073/+0.038ns,MPW+3.655/+4.202ns,recovery+3.488/+5.090ns,removal+0.443/+0.299ns. Performance slack matches worst setup. A bitstream was generated; no package or Program/Verify followed.

Final worst path:SRAM QA->parallel memory response->LSU load extension->E2 forwarding->ALU operand selection->result_q[18],9logic levels,2.895ns logic,6.557ns routing. Setup is only6ps,107ps below the retained parent's113ps. Estimated Fmax does not establish a higher accepted clock.

## Preservation and follow-up

`alu_pc_combined_replay.patch` reproduces15source/test/runner files from acc2537. `build/soc/alu-pc-combined-prototype/snapshot.json` preserves candidate hashes and17evidence-result bindings; both local map-checker scripts are copied beside it. `alu_pc_combined_timing.json` binds actual timing,metrics and review. Candidate inputs intentionally differ after restoration; replay from snapshots for candidate inspection. Fresh `build/soc/decode-pc-restored-parent-review.json` confirms original100MHz acceptance. Vendor28 and benchmark9 originals remain unchanged. The two standalone experiments have separate reports and replay patches.

No further physical trial in this round. Further performance work should first measure whether genuine load-use bubbles can be reduced at the existing synchronous-SRAM/LSU boundary without extending load-return->ALU timing, changing memory behavior or adding a stage. Do not simply remove its required interlock. Current deliverable remains the smaller,already programmed100MHz parent.
