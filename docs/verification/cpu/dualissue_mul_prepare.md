# Shared multiplier payload preparation diagnostic

v8 retains SRAM **1,222,884cycles /4.088695 CoreMark/MHz** and Cache-on modeled
DDR **1,604,946cycles /3.115370/MHz**, GCC15.2-O2. Loaded images, complete
WB/store streams and SRAM profile are identical to v7. These are five-iteration
RTL estimates, not official or board scores. Actual100MHz remains unaccepted.

The v7 final report fixes hold but fails setup-2.014ns. Its actual worst path
starts fetch0 opcode[17], goes through RA bypass and exec0 branch comparison,
then late pipe1_mux_mul_r selects shared MUL opcode/data/sign before native
APM inputX19. It has17levels,2.763ns logic/8.581ns routing.

v8 reuses the LSU separation already checked in this work: static unit classes
select possible B multiplier payload before actual issue permission. Seven
payload fields move together. A MUL retains A; a real B MUL only pairs with
eligible A exec/LSU/branch. Original issue gates, producer tags, hold, arithmetic,
writeback and early-forward qualification remain unchanged. Non-MUL A firing
previously drove mul_valid1 and now0; the multiplier ignores this input and
there is no other consumer. The port itself is not claimed cycle-equivalent.
A MUL under IRQ may still have valid1, while original IRQ logic clears its
real producer tag. Inactive arithmetic may change without a valid producer.

Directed parent RED detects data waiting for branch permission. Current38check
GREEN covers prepared payload, four MUL sign modes through real clocks and
producer tags, B real narrow product0x61d78, the following consumer's actual
issue/accept and captured E1 opcode/valid, hold data/tag alignment, and taken,
hazard, IRQ, squash and A-MUL+IRQ cancellation without fictitious forwarding.
Invalid B/class-X valid is zero. Corrupting the actual prepared RA is detected.
Ordered single/dual, synchronous exception/store and IRQ self-checks pass.
The unit test controls fetch classes and source data; full CPU traces separately
cover real instruction execution. It is not an exhaustive ISA proof.

Independent review verified sources, manifests, exact complete traces and
physical binding. Fresh original10ns/IO/hold/multicorner PDS is running at
`build/cpu/dual-mul-prepare-physical-v8`, no region, PNR20min/outer1500s.
CPU-only synthesis is10173LUT/5008FF/624RAM-LUT(included)/4APM/0DRM.
Final routed setup/hold/MPW and frozen-output checks remain mandatory.

[Bound evidence](dualissue_mul_prepare.json). Production RTL, integration and
board/serial state remain unchanged.
