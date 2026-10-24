# Prepare same-packet dependencies before A selection

**Goal:** Shorten the actual v19 PC-select -> A destination -> B dependency -> FIFO CE path without changing cycles or acceptance semantics.

**Architecture:** Compute the RAW/WAW dependency of B against each raw fetch destination in parallel. Select the scalar result with the same procedural A-payload selection (X/Z selects fetch1), then retain the original procedural allocation predicate. A zero or unknown destination allocates nothing; unknown B indices retain the original equality result. No new state or changes to pending producers, branch policy, FIFO, constraints or production RTL.

**Evidence:** v19 completed, native0/verifier2, original10ns. Global worst -1.765ns is done_o; first CPU path -1.693ns is pc_x[2] -> opcode0[9] -> N433 equality -> N439 same-packet hazard -> FIFO CE. Existing eligibility metadata survives mapping; CPU8736LUT/4052FF. A separate I/O failure remains part of acceptance. Repeating FIFO-enable predecode or adding pipeline latency was rejected based on prior physical/performance regressions.

**Tech stack:** Existing Windows Verilog, ModelSim, PDS, GCC15.2 -O2.

- [x] Independent raw-fetch/selected-destination bitmap oracle on parent; both PC positions/X/Z, all destination/source/role combinations, unknown alloc and indices. Corruption must fail.
- [x] Reconstruct v19 into private v20 and implement only scalar same-packet preparation. Preserve full-base patch and22-source manifest.
- [x] Oracle, pending tags, coherent B-MUL, ordered/IRQ and full SRAM/Cache-on images/WB/store/profile comparisons.
- [x] Independent source/evidence/package review before new private original10ns PDS.
- [x] Verify full input/output hashes, CPU-only mapping and actual six corner timing checks; continue from actual remaining path if failing.

Existing user authorization is to continue isolated timing closure until the same candidate passes timing and >4/MHz. No new architectural stage, toolchain, integration or board action is introduced.

Separately diagnose the observed output-register-to-pad path by explicitly reusing the existing `cpu_io_registers.fdc` option (`syn_useioff=1`), without the old compact-region option. Original clock/IO/hold constraints remain byte-identical. Extend only the physical package whitelist/CLI, with RED/GREEN package gates, then compare fresh no-attribute and I/O-packing routes of the same measured RTL if both packages pass review. Packing existing FFs adds no architectural state. This is distinct from the CPU RTL path improvement.

Both reviewed frozen packages launched independently: original54dad83e... and I/O e9d1254a..., private TEMP/output/logs. Waiting for actual mapping/STA, no timing acceptance.

Both terminal: original setup-0.805ns (best), Slow/Fast hold+0.118/+0.102ns and MPW+3.655/+4.202ns; Fast setup+1.939ns. I/O setup-1.198ns, hold+0.117/+0.100ns, MPW+3.655/+4.202ns; Fast setup+2.835ns. Native0/verifier2 for both,513/434outputs rehashed. CPU8710LUT/4052FF,752RAM-LUT included/4APM/0DRM. Same-source short4.030288/MHz retained;100MHz still failed. I/O FF packing actual success but not selected as overall improvement.
