# CPU operand hazard optimization

2026-10-20. Execute inline with writing-plans, executing-plans and TDD. User authorized optimization without more complex branch prediction. Existing isolated branch cpu/windows-baseline; parent be225f5 and cpu-bpu512-o2-lut-serial-ready-20261020 remain deployable backups.

**Goal:** Reduce avoidable issue stalls while retaining six-stage single issue, RV32IM/CSR, BTB512/BHT512/RAS4, GShare=0, GCC -O2, 32KiB SRAM and actual 100MHz/multicorner/IO/hold requirements. Preserve Windows native tools and CPU-only CoreMark/LUTs. Do not touch main-project Video, original vendor bytes, COM12, Flash or merge/push.

**Architecture:** Qualify scoreboard reads with architectural register use rather than raw instruction fields. Standard RV32 opcode classes identify real rs1/rs2/rd uses; illegal/fetch-fault and unhandled classes retain conservative checks. x0 never creates a data dependency. Keep WAW, dual-lane RAW/WAW, LSU/pipe stalls, squash, IRQ and explicit load/store-to-multiply/divide/CSR interlock. The latter must remain an unconditional scheduling gate: its old all-ones scoreboard cannot be bypassed by a new no-register mask. Operand values, stages and bypass latency do not change.

## 1. Capture baseline and failing contract

- [x] Add timed-window-only counters and architectural completion/store traces to tb/soc/tb_cpu_coremark.v; freeze copies through scripts/soc/run_board.py. The exclusive counters must sum to measured cycles; no production counters or benchmark algorithm edits.
- [x] Run `python scripts/soc/run_board.py --test coremark --cpu-area-directory build/soc/cpu-area-20261020T062141773767Z`. Expect parent 1690888 cycles, correct CRC and 5912 LUT denominator; record actual false-dependency candidates.
- [x] Add tb/cpu/tb_issue_dependencies.v and `run_redirect.ps1 -Test dependencies`. Concrete instruction vectors assert immediate-field non-dependencies, true rs1/rs2/WAW, x0, both lanes, unit interlocks and cancellation. Run against unchanged RTL and observe a failure on an independent ADDI after a load.

## 2. Implement and check architectural behavior

- [x] Modify only rtl/cpu/triha_issue.v and its rtl/cpu/ADAPTATIONS.json binding. Add a local three-bit register-use function; OP-IMM/load/JALR=101, U/JAL=100, store/branch=011, register ALU=111, CSR-register=101, CSR-immediate=100; illegal/fault/default=111. Qualify each nonzero scoreboard index with its use bit. Keep the unit interlock as a separate common gate for both lanes.
- [x] Run positive dependency contract and true-source hazard corruption negative; run existing payload/lane/parallel-read components. Run ordered WB/store/synchronous-exception comparison under single/dual modes and three backpressure seeds, with IRQ checked separately. Do not use cycle-by-cycle equivalence for a deliberate scheduling change.
- [x] Repeat identical-O2 board CoreMark with observer; compare ordered valid WB PC/opcode/rd/value and real accepted store payload to parent. Compare benchmark cycles, CRC and stall distribution; do not call WB observations fully ISA-proven retirement.

## 3. Measure and deploy only an accepted candidate

- [x] Measure CPU-only native area with scripts/soc/measure_cpu_area.py; bind the actual LUT denominator into fresh positive/CRC-negative board CoreMark builds. Final measurement may change software output, so rerun both after area measurement.
- [x] Run actual board PDS through scripts/soc/run_board_route.ps1 with unchanged 100MHz/IO/hold/multicorner constraints; independently review output hashes, setup/hold/MPW and reset checks. Only a passing route may produce a release package.
- [x] If architectural tests, performance/area comparison and actual timing support adoption, package and perform already-authorized volatile Program/Verify with scripts/soc/program_board.py. Leave COM12 to the user and keep full physical CoreMark score pending UART. Keep all failed diagnostics and parent package.
- [x] Save docs/verification/cpu/operand_hazard.json and .md, update STATUS, verify original vendor/adaptation bindings and staged bytes, then commit/tag. Report measured gains and remaining limitations.

## Measured scope adjustment

Parent ROI 1690888 cycles: 1448453 issued/completion observations, 91852 frontend bubbles, 150574 dependency stalls, only 35 false-dependency candidates. Ordered trace adjacency independently accounts for 103559 real load dependencies and 46980 real multiply dependencies (plus 35 false). Operand-use candidate maps to 5929 LUT versus parent5912. Do not promote a candidate that spends area for negligible gain. Evaluate installed GCC scheduling profiles at the same -O2/ISA/ABI, without algorithm changes or new tools, before further RTL datapath changes. CPU predictor remains unchanged. Any software profile must be printed in actual compiler flags and pass CRC, real timing and physical Program/Verify before deployment.

Operand-use candidate saved1690853 cycles (+0.002070%) but worsened CoreMark/LUTs0.284662%; rejected without PNR. Both installed GCC scheduling profiles produced exactly1690888 cycles; flags were actually printed and CRC passed, so neither was adopted and their optional production switches were removed.

## 4. Existing multiplier E1 low-word bypass

- [x] Semantic RED with tb/cpu/tb_issue_mul_forward.v: dependent ADDI must issue and receive the actual product instead of waiting; original gate actually rejects it. Test1024 numeric products plus high-word/load/cancel/hold controls, and corrupt the real product for a negative.
- [x] Tap existing triha_multiplier mult_result_w[31:0]; keep its result_e2_q architectural writeback and all hold/reset state. Propagate one32-bit connection through triha_cpu and qualify E1 forwarding only for single issue, SUPPORT_MUL_BYPASS and the actual E1 MUL opcode. MULH/MULHSU/MULHU, loads and dual issue retain the previous policy; no new multiplier arithmetic or stage is introduced.
- [x] Run existing multiply arithmetic and ordered exception/store/WB checks, measure CPU-only area, bind the new denominator into positive/CRC-negative identical-O2 CoreMark and compare timed instruction/store observations. Require real100MHz board STA before adoption; if timing fails, keep deployed parent and preserve actual failure.

Full-width early bypass removed46980 cycles but actual100MHz route failed setup−1.130ns on APM→ALU, so it was not packaged. Narrow refinement uses the shared low×low partial product of four signed17-bit products; it adds no fifth APM. Only unsigned16×16 low-word MUL can issue early, covering44460 observed dependencies. Full signed/unsigned33-bit product reconstruction retains registered architectural writeback; the arithmetic carry shift uses a separate signed wire. Corrected4096-vector arithmetic, narrow/wide and both-word forwarding, real product/E2 corruption negatives, three-seed ordered checks and two-boot self-test passed. Native CPU area5945LUT/3528FF/688distributed-RAM-LUT/0DRM/4APM; remaining gates are final metric-bound CoreMark and actual100MHz STA.

## Final acceptance

Adopted only the shared narrow-MUL bypass plus cycle-equivalent parallel memory-response selection; operand-use and compiler-tuning prototypes were rejected with evidence. Final nativeCPU5933LUT/3528FF/688distributed-RAM-LUT/0DRM/4APM. Positive/CRC-negative final1646428cycles,short3.036877410CoreMark/MHz,+2.700391% throughput,+2.336881% CoreMark/LUTs. Actual100MHz seed1route0824200693298Z passedSlow/Fast setup+0.113/+1.821ns,hold+0.160/+0.101ns,MPW+3.655/+4.202ns with every originalFDC hash preserved. Independent review and volatileProgram/Verify passed forcpu_coremark_6ff82025b53d; COM12 was not opened. Full physicalCoreMark remains pending userUART. Evidence:docs/verification/cpu/operand_hazard.md andjson. All earlier failed/prototype runs remain underbuild.
