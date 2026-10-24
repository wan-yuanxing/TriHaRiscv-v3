# Carry ALU control through the existing instruction queue

**Goal:** Split the actual v25 late priority decode -> operand mux -> ALU path at the existing frontend queue boundary, retaining six stages and cycles.

**Architecture:** Prepare9bits per instruction: original ALU operation4, operand-A source2, operand-B source3. Capture them with the same queue payload, pass through frontend/issue using the same A/B instruction selector, and use them directly in the existing execution input muxes. Reuse the original ALU datapath. Opcode/funct cases exactly match original masks, including immediate shift bit25. All encoded controls are known after reset even for X/Z opcodes because exact-case/IF priority skips unknown matches, as the old decoder did. Reset opcode0 maps control0. EXTRA_DECODE_STAGE uses a combinational compatibility encoding after its unchanged queue, so its latency remains unchanged.

Current actual v25 class topology shortened6->4 native nodes, but final setup-.914ns (IO), firstCPU-.892ns now instruction29 -> execution priority decode -> operandA mux -> ALU. Source rewriting alone has reached another stage boundary; moving compact control before that boundary follows ordinary early-decode/execute separation. No stall, predictor, queue handshake, ALU arithmetic or branch behavior is changed.

**Tech stack:** Existing Windows Verilog/ModelSim/PDS/GCC15.2 -O2.

- [x] Full137bit clocked execution oracle against original module, parent baseline/negative, then real predecoded-control and control-corruption negative. Check all relevant17binary decode bits and X/Z support where practical.
- [x] Add pure9bit encoder, queue payload and explicit frontend/issue control ports. Use original procedural A selection; zero/hold/flush/inactive history stays aligned. Execution legacy parameter default0 remains only for independent component/reference use; actual CPU instances select predecoded mode statically so legacy hardware is removed.
- [x] Whole151bit decoder, coherent component control/operand alignment, ordered/IRQ and full SRAM/Cache-on images/WB/store/profile comparisons. Forced raw opcodes without matching metadata are outside the new invariant and require coherent test stimulus.
- [x] Independent port/alignment/encoding and frozen original10ns/noRegion/noIO20min physical review before PDS.
- [x] Actual control metadata/late-decoder elimination, CPU-only resources and final six STA checks. Do not promote production RTL or operate board/integration.

Independent source/terminal/package review passed. Original10ns/noRegion/noIO20min PDS launched privately; actual topology and final six STA pending. Same short4.030288 SRAM and3.084289 Cache-on estimates/complete streams/profile preserved.

Same-source IO-only variant independently reviewed and launched in parallel (existing syn_useioff, no region/no timing exception) because actual prior debug outputs repeatedly failed. Its terminal is recorded separately; native source and measured ELF match the original v26 exactly.

Both routes finished with native0/verification2; all frozen input/output and actual transport hashes rechecked. Original Slow/Fast setup -1.187/+2.019ns, hold +0.114/+0.102ns, MPW +3.655/+4.202ns. I/O-only setup -0.798/+2.795ns, hold +0.066/+0.030ns, same MPW. Neither satisfies 100MHz. CPU-only synthesis8860LUT/4112FF/752RAM-LUT(included)/4APM/0DRM.

Actual native compile selects predecode on both execution instances; all54 new queue bits survive with INIT0 and control drives execution inputs, eliminating the former opcode priority chain. Original launch fetch1_instr_w[21] fanout62/first-route2.132ns; I/O launch fetch1_instr_w[20] fanout61/first-route1.421ns. Both pass through native RF read/forwarding to branch-dependent control. The7ps difference from prior bestv20 is not a meaningful frequency benefit. Next diagnose this measured address fanout without changing stages, cycles or inactive payload history.
