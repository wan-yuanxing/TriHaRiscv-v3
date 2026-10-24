# Factor execution class by opcode and function fields

**Goal:** Shorten the actual v24 SRAM instruction -> input exec classification -> queue metadata path without state or latency changes.

**Architecture:** Reuse the exact original RV32 encoding masks, factored into opcode-major, funct3 and funct7/funct6 groups. Keep separate ALU-register, ALU-immediate and upper-immediate scalar cones before their final OR. The original decoder remains the independent oracle and handles CSR/other outputs unchanged. In particular immediate shifts use the original mask[31:26] (bit25 ignored), while register ALU uses[31:25]. Enumerate all funct3 equalities in RTL, including the otherwise two-state-complete register group, to preserve unknown/X/Z semantics. No new stage, state, prediction or queue behavior.

**Tech stack:** Existing native Windows Verilog/ModelSim/PDS/GCC15.2 -O2.

v24 actual setup-0.909ns, hold/MPW pass; worst SRAM bit25 -> input decoder5LUTlevels -> infoFF. Its exec metadata is confirmed live. This is the standard opcode/function-field decode hierarchy, preserving the original legal instruction set and mask quirks, rather than changing ISA acceptance. New v25 is based only on v24 and uses original10ns/noRegion/noIO physical options.

- [x] Existing v24 input exec signal against original decoder across all131072 known combinations of17 relevant bits; ignored-bit and X/Z checks plus corruption negative before implementation.
- [x] Implement factored combinational helper and use it only for the two input exec metadata bits; preserve22-source patch/manifest.
- [x] Exhaustive/directed/golden151-bit, packet/B-MUL, ordered/IRQ and full new SRAM/Cache-on image/stream/profile equivalence.
- [x] Independent mask/four-state and physical package review before new original10ns PDS.
- [ ] Actual kept decode topology, CPU-only area and final six STA acceptance plus same-source >4/MHz.

Independent source/terminal/package review passed. Original10ns/noRegion/noIO20min PDS launched privately; actual topology and final six STA pending. Same short4.030288 SRAM and3.084289 Cache-on estimates/complete streams/profile preserved.
