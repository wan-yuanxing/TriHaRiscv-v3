# Registered bypass tags diagnostic plan

**Goal:** Shorten the measured masked destination-index to forwarding decision
without adding a pipeline stage or changing the above4/MHz execution policy.
**Architecture:** Carry the qualified five-bit tag as parallel metadata in E1,
E2 and WB. Preserve original opcode/control/valid registers and commit outputs.
**Tech stack:** Existing Windows Verilog/ModelSim/GCC15.2-O2/PDS, isolated build.

The v12 actual path starts pipe1 WB opcode[7]. Native LUT N618_2/N618_5 mixes
source index, opcode destination, valid_wb and ctrl_wb RD_VALID before operand
selection. This is followed by zero comparison and FIFO update. v13 separately
removes the tail arithmetic. An alternative PC priority change has stronger
composition assumptions; changing branch policy again risks falling below4.
Registering existing stage metadata costs at most30FF across two pipelines,
keeps latency and all opcodes/results unchanged, and targets the measured head.

- [x] Add `tb/cpu/tb_pipe_registered_tags.v`: clock the unchanged pipeline from
      reset with randomized normal/fault/IRQ/hold/flush and X/Z input patterns.
      After every edge compare all three tags to the exact old expressions
      over original control/valid/opcode state. No forced internal metadata.
- [x] Confirm original expression baseline passes and corrupt-output negative
      fails; no claim of functional RED for a behavior-preserving refactor.
- [x] In a fresh build-only candidate from v13, register the masked E1 tag at
      the same issue capture. Register E2 tag with exactly original interrupt
      versus frontend exception priority and valid update. Register WB tag
      with the exact original memory-fault case and procedural exception gate.
      Reset/hold/flush follow each original stage; no forced-metadata equivalence.
- [x] Run tag oracle and negative, integrated zero-pair and ordered/IRQ checks;
      compare full SRAM/Cache images, WB/store, cycles/profile to v13.
- [x] Preserve full-base patch/22source manifest and fresh reconstruction.
- [x] Review source/state semantics and original10ns/no-region physical binding.
- [x] Route privately after admission; final six STA rows and same-source
      >4/MHz gate remain required. Do not promote or program the board.

## Parent selection update

v13 final setup-2.659ns regressed from v12-1.276ns, while all functionality
and cycles matched. Preserve v14 combined package unexecuted. Prefer v14b:
same registered tags, only restore exact v12 decode/FIFO bytes. Repeat fresh
SRAM and Cache-on measurement binding and integrated ordered/IRQ checks.

Fresh v14b SRAM/Cache complete images, WB/store, cycles and profile match v12.
Independent physical binding review PASS; private original10ns PDS launched.

v14b native flow0, timing verifier2; final setup-1.629ns, hold/MPW PASS.
Qualified tags all mapped to30FF; CPU8629LUT/4108FF. New measured path is
fetch1 index through forwarding priority and general branch to pc_x (18levels).
