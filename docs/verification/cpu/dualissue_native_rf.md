# Native dual register storage diagnostic

v10 preserves the six-word candidate performance: SRAM 1222884 cycles,
4.088695 CoreMark/MHz; Cache-on DDR model 1604946 cycles, 3.115370/MHz.
GCC15.2-O2, five-iteration RTL estimates, not official or board results.
Complete loaded images and WB/store streams match v8.

The local dual-native path uses two writer banks and four read replicas per
bank (128 RAM32X2DP), with 62 resettable live-value metadata FF. Port0 wins
same-address simultaneous writes. Known-address qualification preserves
unknown read default0 and unknown write ignore; synchronous reset-X is tested.
No equivalence is claimed for Z write data, before reset or forced X metadata.
Single-mode and the existing vendor parameter switch are unchanged.

8200 storage checks, write-corruption negative, 24448 single/dual operand
checks, ordered exceptions and IRQ self-checks pass. Actual native synthesis
retains two-level data/address hold chains. The RF maps to392LUT/62FF;
CPU-only is8884LUT/4078FF/752distributed-RAM LUT(included)/4APM/0DRM.

Fresh original10ns/no-region PDS completed: native0/verifier2;783output
hashes verified. Slow setup/hold/MPW=-1.536/+0.109/+3.655ns;
Fast=+1.345/+0.100/+4.202ns. The actual worst path is fetch1 instruction
through RA bypass and exec0 branch comparison to FIFO payload CE (14levels,
logic1.909ns/route9.172ns). **100MHz has not passed.**

v11 combines the same native RF with the separately verified FIFO enable
predecode. SRAM/Cache-on images, full traces and cycles match v10. Original
10ns PDS also completed: Slow=-1.522/+0.117/+3.655ns,
Fast=+1.644/+0.083/+4.202ns; native0/verifier2,503outputs verified.
CPU-only8812LUT/4078FF/752RAM-LUT(included)/4APM/0DRM. The actual worst
launch signal is pipe1 E1 opcode bit7 (packed cell is named bit8), through
RB bypass and branch compare to issue.pc_x_q[2] (11levels,
logic2.111ns/route9.027ns). New mapping/layout; still no100MHz acceptance.

[Native evidence](dualissue_native_rf.json), [combined evidence](dualissue_native_enable.json).
