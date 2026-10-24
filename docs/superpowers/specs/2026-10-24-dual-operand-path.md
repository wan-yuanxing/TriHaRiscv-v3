# Dual operand path timing experiment (2026-10-24)

Continue the authorized six-stage dual-issue 100MHz closure in the independent
CPU worktree. No new architectural stage, bypass priority, issue permission,
clock relaxation, or production RTL promotion is part of this experiment.

The parent actual postroute path starts at queue head PC and traverses a
32-bit PC equality, payload selection, B register index and RF/bypass logic,
branch comparison, then exec1 next-PC logic. Slow setup is -3.015ns.

Two bounded candidates isolate the suspected serialization:

1. B raw v1: B opcode/PC/fault always come from registered fetch slot1;
   existing B-valid, contiguous-PC, hazard and downstream valid gates authorize
   consumption. Invalid-cycle payload changes are intentional.
2. Parallel raw v2: retain v1; reuse existing four RF reads for both fetch
   slots, forward each A candidate independently with existing priority, then
   select the A operand after PC-match. The single-issue extra RF path is kept
   only for single issue. Dual mode reuses B reads, with no added RF copy.

First run an independent RF/forwarding oracle and address-independence check;
retain parent failure, candidate success and broken-data failure. The test
holds squash=1 and proves operand behavior; ordered full CPU runs separately
check execution, exceptions and interrupts. Then compare complete measured
SRAM WB/store streams and actual cycle partitions before fresh PDS.

Both candidates measure 1,253,888 cycles, 1,448,448 WB observations and 70,839
stores. Loaded ROM/SRAM and full measured WB/store are byte-identical to the
parent. The current short estimate remains 3.987597/MHz; this experiment
addresses timing and does not meet the >4 target yet.

Keep v1 and v2 sources as reproducible manifests plus full patches from the
unchanged production base. All generated candidates and PDS outputs remain
under build/cpu. Actual PDS six Slow/Fast setup/hold/MPW checks and final
performance slack decide timing acceptance. Record CPU hierarchy synthesis
area separately from whole-system mapped area and SRAM/ROM.
