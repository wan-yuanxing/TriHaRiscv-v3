# CPU stall analysis and optimization

2026-10-20. Parent be225f5 is preserved by cpu-before-operand-hazard-20261020. Six-stage single issue, 512/512/4 PC-indexed predictor, GShare=0, RV32IM/CSR, GCC15.2/O2, 32KiB local SRAM and 100MHz are unchanged. Windows-native tools only. COM12 is reserved for the user's terminal.

The timed observer resides only in tb/soc/tb_cpu_coremark.v; it does not add production LUT/FF or change benchmark timing. The mutually exclusive issue/stall categories sum to the exact software/observer rdcycle interval. Simultaneous causes are assigned in priority order; this is not an additive causal estimate. Ordered WB PC/opcode/rd/value observations and accepted store address/byte-enable/value are saved separately. WB events are not a claim of complete architectural retirement verification.

## Parent measurement

build/soc/board-coremark-20261020T071803030270Z: five-iteration RTL preflight PASS, 1690888 cycles, standard CRC e9f5/e714/1fd7/8e3a, 2.95702613065 CoreMark/MHz, 5912 CPU-only LUT. 5000-iteration firmware was built separately, not simulated. Full physical score remains pending the user's UART capture.

| Exclusive category | Cycles |
|---|---:|
| Issued | 1448453 |
| Frontend empty/wrong-PC | 91852 |
| Register dependency | 150574 |
| CSR pending | 9 |
| All other sampled categories | 0 |

Of dependency cycles, only35 have no architectural nonzero register dependency under the ISA field-use model. Independently examining adjacent ordered WB instructions yields exactly103559 real load dependencies,46980 real multiply dependencies and35 false dependencies. Thus a larger BTB or a new direction predictor is not part of this optimization.

## Rejected operand-use candidate

Frozen source is in build/soc/cpu-area-20261020T072433252651Z/src/rtl/cpu/triha_issue.v and its frozen ADAPTATIONS.json, not adopted into production RTL. Standard ISA register-use qualifiers remove irrelevant immediate fields and x0 from dependency checks. Actual RAW/WAW remain blocked; illegal/fetch-fault/default cases stay conservative. The original LSU-to-mul/div/CSR resource interlock is explicitly retained outside the scoreboard mask.

The original gate failed the new directed ADDI-independent-of-x5 contract. Candidate passed1437 checks in each single/dual mode, including44 ISA vectors swept across32 possible busy registers, true RAW/WAW, cancellation and no-register CSR interlock. Destroying the actual busy state caused the expected true-RAW failure. All existing payload/lane/parallel-read components passed. Ordered WB/store/synchronous-exception comparisons passed under single/dual modes and seeds37/1234567/271828; IRQ checks passed separately.

Candidate native area:5929 LUT/3486FF/688 distributed-RAM LUT/0DRM/4APM. The RAM LUT count is already contained in5929. Candidate CoreMark build/soc/board-coremark-20261020T072627970691Z passed CRC with1690853 cycles: exactly35 fewer cycles, +0.002070% throughput, but CoreMark/LUTs fell0.284662%. No PNR, package or programming was spent on this candidate. Production issue RTL and adaptation binding were restored byte-for-byte to parent; candidate evidence is preserved.

Parent/candidate timed WB/store streams differ only in the initial absolute rdcycle value and its store to the start-time variable. Subsequent architectural observations and accepted store payloads match. Those instrumentation values naturally change when startup runs faster; they must not be described as byte-identical full raw traces.

## Scheduling comparison

Use the installed compiler's existing single-issue pipeline scheduling profiles while keeping-O2, ISA/ABI, benchmark algorithms, data size, memory and hardware unchanged. Actual mtune flags must appear in both native command records and UART compiler flags. Only an improvement that passes CRC, duration policy, actual board post-route and volatile Program/Verify can replace the deployed package. Full physical CoreMark remains unmeasured until UART is supplied.

Both scheduling profiles actually passed CRC and produced exactly1690888 cycles with the same timed profile; no improvement. They were not adopted and their optional production switches were removed. Runs:build/soc/board-coremark-20261020T073213041355Z and073213056435Z. No new compiler installation or algorithm edit was made.

## Full-width early-MUL diagnostic (not deployable)

The existing multiplier's E1 product was connected to the established E1 forwarding network for single-issue low-word MUL. Architectural E2 writeback and all hold/reset state remained intact. High products, load interlocks and dual issue retained their original scheduling policy. Numeric/forwarding, fault-injection, three-seed ordered WB/store/synchronous-exception and separate IRQ tests passed.

CPU-only5996LUT/3496FF/688distributed-RAM-LUT/0DRM/4APM. Five-iteration CoreMark1643908 cycles,3.041532738/MHz,+2.857824% throughput and+1.416854% CoreMark/LUTs versus parent. Exactly46980 dependency stalls disappeared;1448453 timed WB observations and70840 stores matched parent except the initial absolute-cycle read and its start-time store. Positive and real CRC-failure runs are074316942000Z and074316941993Z.

Actual board route0748348838408Z completed, but100MHz failed:Slow/Fast setup−1.130/+1.821ns,hold+0.152/+0.099ns,MPW+3.655/+4.202ns. The worst path was multiplier APM→execution ALU result. This is a real new critical path, not a reason to relax constraints or rerun many placement seeds. No package or programming was performed.

## Shared narrow-product bypass

Operand reconstruction from the valid WB stream showed44460 of the46980 dependent low-word multiplies have both unsigned operands below65536;2520 need the wide path. The next implementation exposes the existing low×low partial product while retaining full-width registered writeback. It uses four signed17×17 partial products, rather than adding a fifth multiplier, and qualifies early forwarding only when both upper16-bit halves are zero. Wide MUL and all high-word operations retain their original waiting behavior. No branch-predictor algorithm, table size, ISA, memory latency or main pipeline stage count changes.

For A=Al+2^16 Ah and B=Bl+2^16 Bh, with signed17-bit high halves, form LL=AlBl,LH=AlBh,HL=AhBl,HH=AhBh. Let C=LL[31:16]+LH+HL. The65-bit product is{(HH+(C arithmetic-shift-right16))[32:0],C[15:0],LL[15:0]}. The signed carry shift has its own typed wire; an earlier mixed-sign expression failed the independent numeric test and is preserved in0756146159462Z. The corrected4096-vector test passed at0757077521693Z, including reset, invalid bubbles, holds and signed/high/low products. Narrow/wide eligibility and both fetch-word forwarding paths passed1032 checks at0757103883144Z; real product corruption and E2-result corruption were rejected at0757526117978Z and0757556735566Z. Final three-seed single/dual ordered comparisons and separate IRQ checks passed at0757526117601Z,0758026852447Z,0758120242386Z and0758222342313Z. Two-boot8KiB self-test passed atbuild/soc/board-system-20261020T075752352889Z.

Native area atbuild/soc/cpu-area-20261020T075752318269Z:5945LUT/3528FF/688distributed-RAM-LUT/0DRM/4APM. LUT count increases33 versus parent; distributed RAM LUTs are already included. Independent report parsing checks that EARLY_MUL_BYPASS is actually enabled at CPU and issue scopes, rejects missing/disabled/duplicate scopes, and preserves legacy report review for snapshots without this parameter. All44 Python checks and existing PDS parameter tests passed. Final CoreMark and physical acceptance are recorded in the accompanying JSON after their actual completion.

That intermediate memory selection passed CRC and gave1646428 cycles/3.036877410 CoreMark/MHz, but four bounded original-constraint routes did not close:seed1−0.139ns(4 setup endpoints),seed3−0.312ns with hold−0.037/−0.043ns,seed8−0.216ns,seed11−0.361ns. Slow/Fast MPW remained+3.655/+4.202ns. The best remaining path was synchronous SRAM output→word/target mux→LSU extension→forwarding→branch result; the original full-product APM path was removed from the worst path. Route indices are0804262673117Z,0804262742818Z,0809406772126Z and0809406870946Z. None was programmed.

## Parallel synchronous-memory response selection

The final refinement moves SRAM/ROM word and target decoding to the existing response-control registers. Four onehot bits select SRAM-low/high or ROM-low/high. The MMIO register is already zero on accepted memory transactions; merge these terms in parallel instead of cascading word and target priority muxes. No request, side effect, response-valid, tag, error, UART ownership, reset or one-cycle response timing changes. Existing memory tests passed415 checks; injected read corruption was rejected. An independent parent miter compares every public request-accept/valid/data/error/tag/UART/exit output every cycle under the same protocol oracle, also415 checks. The onehot and zero-MMIO-on-memory invariants are asserted in the testbench. Records:memory-20261020T081739889386Z,negative081556796307Z,memory-parent-miter-20261020T081742189189Z. Final two-boot self-test passed at081554739722Z.

Actual CPU hierarchy after this system change is5933LUT/3528FF/688distributed-RAM-LUT/0DRM/4APM; this is a fresh PDS hierarchy result, not subtraction from whole-system logic. Final CoreMark/CRC-negative runs081904735517Z and081904731166Z bind5933 into the firmware and retain1646428 cycles. Short RTL CoreMark/MHz3.036877410,CoreMark/LUTs0.051186203:throughput+2.700391%,LUT efficiency+2.336881%,CPU LUT+21(+0.355210%) versus parent. Complete timed WB/store comparisons pass except the explicitly identified initial absolute timer value. These are simulation measurements, not full physical CoreMark results.

## Deployed acceptance

Final seed1 full native runbuild/soc/board-route-20261020T0824200693298Z returned0,source_unchanged,actual5933CPU LUTs and all six actualcompile/synthesize/dev_map/PNR/report_timing/bitstream success markers. Independent report/input/output/tool/pin/PLL review passed; CPU and issue actual elaboratedEARLY_MUL_BYPASS=1. All original FDC bytes match the parent, including100MHz,IO,hold and multicorner requirements.

| Actual final check | Slow slack/ns | Fast slack/ns |
|---|---:|---:|
| Setup | +0.113 | +1.821 |
| Hold | +0.160 | +0.101 |
| Minimum pulse width | +3.655 | +4.202 |

Recovery/removal pass,performance slack+0.113ns matches the worst setup. This accepts100MHz only; no higher operating frequency or official score is claimed.

The final alternate seed8 run0824200755631Z also completed and was independently reviewed:setup+0.095/+1.752ns buthold−0.049/−0.049ns. It isTIMING_FAIL and was not packaged. Only the seed1 result above was selected; a positive setup value alone is not acceptance.

Releasebuild/soc/releases/cpu_coremark_6ff82025b53d:bitSHA2566ff82025b53d071827fb093a1f97dc417628f89fdc22db6dc0736eabd7404cd9,maskSHA2566b1ae6a18985198d20955dd4d18bc899c1d569c62a187a54ec9af92b060e1adf. ActualvolatileProgram/Verify atbuild/soc/board-coremark-program-20261020T082907336769Z passed:PG2L100H ID00602899,native return0,cfg_program/cfg_verify success. Flash unchanged; COM12 was not opened. Full physical5000-iteration score remainsAWAITING_USER_UART. UseCOM12/115200/8N1/no flow control,text reception,thenKEY0; expect about17seconds and accept onlyerrors=0,short=0,standard CRCs andCPU_COREMARK_BOARD_PASS. The final UART denominator is5933CPU LUTs.

Parent packagecpu_coremark_224be86f8972 and tagcpu-bpu512-o2-lut-serial-ready-20261020 remain preserved. New backup tagcpu-narrow-mul-100mhz-20261020 preserves implementation and evidence; no merge/push or main-project Video edits. Read the adjacentoperand_hazard.json for immutable run/result/package hashes, exact measurements and explicit unmeasured physical-score fields.
