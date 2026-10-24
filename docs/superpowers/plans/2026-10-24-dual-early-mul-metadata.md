# Early multiplier eligibility metadata

**Goal:** Remove wide post-E1 low-MUL opcode/operand-width qualification from
the actual early-MUL -> scalar-zero -> FIFO critical path (-1.110ns).
**Architecture:** At the existing E1 capture, carry the exact opcode-low-MUL
predicate as one extra bit per pipeline. At the multiplier's existing operand
capture, carry the exact two upper16-zero checks as one bit. Keep all actual
MUL/IRQ/valid producer gating and data/partial-product math unchanged.
Three metadata FF, no new stage, cycle, prediction or port validity meaning.
**Tech stack:** Existing native Windows Verilog/ModelSim/PDS/GCC15.2-O2.

Insert metadata assignments inside original capture/reset/bubble blocks so
hold/flush/unknown-condition behavior cannot diverge. The MUL operand block
uses else-if(hold) else capture, so hold=X captures operands and its metadata;
the result block uses if(~hold) and still holds on X. Preserve both. Width
ready resets1 because reset operands are zero; opcode-low-MUL resets0 because
reset opcode0 is not MUL. Do not change early_low_valid's public semantics.

- [x] Clocked pipe metadata oracle against original stored opcode predicate,
      including all MUL variants/other ops, ignored-bit X/Z, opcode-mask X/Z,
      reset/hold/flush/IRQ. Parent baseline then new output corruption.
- [x] Clocked multiplier all3-output golden-original oracle with boundary
      cross product, all MUL variants/other opcodes, X/Z, reset/hold/valid.
- [x] Build-only v19 changes pipe_ctrl output/register, two issue hookups and
      multiplier scalar property register; preserve all original data state.
- [x] Coherent real B-MUL/early-consumer test, pending/packet/oracle, ordered/
      IRQ and fresh SRAM/Cache full image/stream/performance/profile match.
- [x] Preserve/reconstruct22-source patch; independent state/flag/corner proof
      and original10ns/no-region binding before private PDS.
- [ ] Confirm3FF metadata survives actual mapping; final all six STA and same
      >4/MHz performance gate remain mandatory. No production promotion.

Clocked40003 pipe and41027 complete multiplier outputs/boundaries pass;
corruption negatives fail as expected. Full SRAM/Cache streams/profile and
ordered/IRQ match v18. Physical53011127... reviewed; original10ns private PDS
launched. Actual total FF delta may differ if dead old opcode bits disappear.
