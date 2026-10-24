# Prepared zero flags diagnostic

**Goal:** Remove wide forwarded-data selection followed by zero reduction from
measured zero-branch pairing -> FIFO update critical paths.
**Architecture:** Reduce RF and each candidate forwarded source to a one-bit
zero flag before late tag/priority/payload selection. Select the flag with
exact original priority and procedural unknown-tag behavior. Keep the actual
32-bit operand datapath and all issue/fault/IRQ/side-effect gates unchanged.
No new stage/state or cycles, no new branch prediction policy.
**Tech stack:** Existing Windows Verilog/ModelSim/PDS/GCC15.2-O2.

v12 actual worst setup-1.276ns and v15-2.213ns both cross wide operand
selection -> zero reduction -> FIFO update. Parallel property evaluation
before a mux uses the exact selected data predicate; preserve X/Z by directly
selecting one-bit equality results with the same procedural match priority.
x0 flag is1. Unknown index comparisons follow the original skipped-if rule.
For non-parallel operand configurations retain the original full-data check.

- [x] Extend an independent RF/forwarding oracle into a separate testbench,
      covering all64 hit masks,31 indices, both x0 positions, BEQ/BNE and
      selected zero/nonzero/partialX/partialZ payloads; parent and negative.
- [x] Build-only v17 from v16 adds prepared flags and changes zero helper only.
- [x] Run oracle/negative, actual branch-pair/LSU/MUL checks, ordered/IRQ;
      actual SRAM/Cache full traces/profile must match v16 exactly.
- [x] Preserve/reconstruct patch22/manifest; independently review full-data
      versus prepared-flag four-state equivalence and original10ns binding.
- [ ] Launch only after source/RTL/physical admission, check actual mapping
      and all final STA. Do not stop/restart v16 or modify its frozen helpers.

Expanded parent/dual/single227136 checks and corruption negative PASS as
expected; independent payload_type loop supersedes correlated84288matrix.
Full streams/profile and fresh performance match v16; review and original
10ns/no-region physical binding PASS, private PDS launched.
