# Scalar exception and native BTB write-address diagnostic

The six-word candidate preserves4.088695/MHz SRAM short RTL performance but
failed actual100MHz: Slow setup-2.228ns and Slow/Fast hold-0.068/-0.060ns.
Do not use its performance alone as acceptance.

Its worst setup path is registered E2valid through the wide selected exception
vector/reduction, squash, issue slot validity and FIFO movement. v7 reduces
memory and saved exception sources independently, then selects the scalar in
the same original procedural if/else used by the full exception vector. This
keeps selector-X/Z behavior, exact exception encoding, WB and squash history.
It adds no state or main pipeline stage. The full vector remains available to
writeback; kept early scalar nets are a physical experiment, not a timing claim.

The observed hold failure is a training packet FF directly driving a native
BTB WADDR bit, fan824. v7 places two existing native LUT hold gates per address
bit per32row block. First gate qualifies with metadata_we, second with not
reset. All actual target writes also imply metadata_we, so enabled addresses
are unchanged. Read ports, independent training tag RADDR, WE and valid stay.
The16blocks each have5bits/two gates,160 LUT6 before optimization. Local output
loads are expected39 native RAMs but must be checked in mapped/route evidence.

The exception oracle passes65,547 checks: all65536 known combinations of both
6bit exceptions and16 selectors, plus X/Z selector/exception and history stall
checks. Corrupt squash is detected. The independent512entry BTB oracle passes
10066 checks including293 collisions and150 target retains; corrupting actual
block2 WADDR0 is detected. Gate bypass would remain functionally identical,
so functional PASS cannot certify minimum delay or mapping preservation.

The measured v7 SRAM result is **1,222,884cycles /4.088695/MHz**,
exactly the six-word parent. Cache-on modeled DDR is1,604,946cycles/3.115370.
Loaded images, complete WB/store streams, and every SRAM profile field match
the six-word parent exactly. GCC15.2-O2, five iterations; not official or board
scores. Ordered single/dual and IRQ checks pass. This does not replace full
ISA proof or physical acceptance.

Original10ns/IO/hold/multicorner no-region physical implementation is running at
`build/cpu/dual-control-hold-physical-v7`; independent source/evidence admission review passed.
PNR20minutes/outer1500seconds. Final setup/hold/MPW and actual mapped hold gates
will decide this experiment. Production RTL and integration remain unchanged.

[Bound machine evidence](dualissue_control_hold.json).

Native synthesis VM graph check finds both bank definitions: all80write-address
bits retain two LUT levels from raw low address, each with39 WADDR loads.
The160logical gates pack into76 named LUT cells. This is synthesis-stage
connectivity, not final routed minimum delay. CPU-only synthesis is
10141LUT/5008FF/624RAM-LUT(included)/4APM/0DRM; actual STA still pending.
