# CPU ALU predecode implementation plan

2026-10-20. User-approved continuation, executed inline using systematic-debugging, writing-plans, executing-plans and test-driven-development. Preserve acc2537 and the deployed dc00f80 release. No agents, WSL, serial-port access, Flash, main-tree edits, merge or push.

**Goal:** Move exact ALU operation/operand-source decoding before the existing fetch FIFO, keeping six stages, all cycle behavior, RV32IM/CSR, BTB512/BHT512/RAS4, PC-indexed prediction, GCC-O2/noLTO and original actual100MHz acceptance.

**Architecture:** A nine-bit descriptor encodes function4/A-source2/B-source3. Each FIFO lane carries descriptor plus its original32-bit instruction as one41-bit payload. Existing free-slot sampling, reset, flush and stale payload rules therefore apply identically. Both decoder latency modes compute descriptors at their FIFO inputs. Frontend/CPU/issue forward descriptor with exactly the same procedural lane selection as opcode. A maintained execution derivative selects operands from the descriptor; branch logic remains the frozen original. No predictor or PC/RAS change is bundled into this first experiment.

Alternatives: rearranging combinational decode after FIFO was already physically rejected; adding a stage changes latency and score. Predecode uses an existing boundary, trading36 FIFO payload bits against repeated post-FIFO comparisons. Area and timing benefit remain hypotheses until measured.

## Tasks

- [x] Back up current commit with a tag; establish executable full execution-interface miter and FIFO descriptor/raw-opcode alignment contracts before production edits. Missing descriptor functionality must fail. Reuse frozen original execution as independent oracle, include all opcode/function combinations, random operands, illegal instructions, X/Z, reset/hold/invalid and real corruption negatives.
- [x] Create `rtl/cpu/triha_alu_decode.v` and `triha_exec.v`, retaining the frozen source notice. Modify `triha_decode.v`, `triha_frontend.v`, `triha_issue.v`, `triha_cpu.v`, explicit filelists and `ADAPTATIONS.json`; never edit vendor originals. Use source0=zero,1=RA,2=U-immediate,3=PC; B0=zero,1=RB,2=I-immediate,3=shamt,4=U-immediate,5=constant4. Exact original mask priority and procedural unknown behavior are retained. Widen only the instantiated FIFO data width to82, not metadata history.
- [x] Run native ModelSim component positive/negative contracts, ordered single/dual WB/store/synchronous exception for seeds37/1234567/271828, separate IRQ, and two-boot board self-test. Any descriptor misalignment or execution difference rejects the design.
- [x] Measure CPU-only area using original board clock evidence. Run fresh metric-bound positive and CRC-negative five-iteration-O2 CoreMark. Require1646428cycles and complete timed WB/store trace hashes equal to the deployed parent; do not label WB observations architectural instret.
- [x] Execute one original-constraint100MHz full native route and independent review. Require all Slow/Fast setup/hold/MPW, reset, performance and frozen input/output bindings. Inspect the actual critical path. Tool completion or area saving does not establish frequency gain. Do not sweep seeds.
- [x] Adopt only a beneficial fully accepted result. Otherwise preserve replay/evidence, restore production sources and document the next boundary requiring work. Update status, verify28vendor/9CoreMark hashes and staged files, commit the concrete result. Leave current deployed image in place unless a beneficial accepted image is ready under existing volatile-program authorization.

Disposition: all functional/metric gates passed, but the single actual route fails Slow setup -0.088ns at7endpoints. Added69LUT/36FF with unchanged score is not adopted. Replay, immutable snapshot and independent review are retained; all production changes and experimental test/runner additions were restored to acc2537 before the next experiment. See `docs/verification/cpu/alu_predecode_timing.md` and `.json`.

Deferred PC/RAS investigation: the actual worst endpoint is issue PC CE after FIFO->bypass->branch comparison. A separate early-enable experiment is now specified in `pc_early_enable_plan.md`; preserve raw execution valid versus interrupt-suppressed advance, speculation/flush and all default/hold PC behavior. Do not infer timing from Boolean depth.

Final disposition: all planned gates and the bounded combination are complete. Combination physically passes100MHz but is not selected:6009LUT and+0.006ns versus deployed5933LUT and+0.113ns, with equal CoreMark cycles/traces. Production restored; no programming. See docs/verification/cpu/alu_pc_combined_timing.md.
