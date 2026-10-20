# CPU branch/PC optimization: no new deployment

2026-10-20. This bounded round is complete without adopting an RTL candidate. Production CPU/SoC/board/software/test sources are restored byte-for-byte to dc00f80. The deployed image remains cpu_coremark_6ff82025b53d; no programming, Flash write, COM12 access, merge or push occurred. Backup cpu-before-branch-pc-20261020 preserves the starting version. Only the reusable structural checker, its tests and diagnostic records are retained in Git.

A fresh independent review after restoration verified the original100MHz board result again:Slow/Fast setup+0.113/+1.821ns,hold+0.160/+0.101ns,MPW+3.655/+4.202ns,reset and performance checks pass. Current CPU-only resources remain5933LUT/3528FF/688distributed-RAM-LUT/0DRM/4APM. Distributed RAM LUTs are included in the total. Current short RTL CoreMark remains1646428cycles,3.036877410/MHz and0.051186203CoreMark/LUT at nominal100MHz. Full5000-iteration physical score is still pending the user's UART; no official score or higher operating frequency is claimed.

## What was measured

The actual parent path was SRAM return->load formatting/forwarding->signed branch compare->next-PC carry. Kept useful sequential/taken PC results removed all21 late-branch-dependent PC carry outputs in a conservative native-synthesis structural check. This does not prove timing. A common signed less-than flag for BLT/BGE removed the redundant reverse subtraction; the mature comparison-flag pattern is pinned separately in the JSON reference, without an external HDL/compiler environment.

| Candidate | CPU LUT | Actual worst100MHz setup/ns | Decision |
|---|---:|---:|---|
| Deployed parent |5933|+0.113|Retained; all checks pass|
| A:separate PC arithmetic |5945|+0.149|Not adopted:extra12LUT,no score gain|
| B:parallel ALU decode |5987|-0.082|Rejected,4failing setup endpoints|
| C:PC boundary+shared signed compare,seed1 |5903|-0.029|Rejected,5PC-enable endpoints|
| C:same CPU,seed8/hold10 |5903|-0.081|Rejected,sole failing endpoint is LED3|
| D:C plus registered status LEDs,seed1/hold10 |5903|-0.292|Rejected,34setup endpoints|
| D:same board fix,seed8/hold10 |5903|-0.162|Rejected,2setup endpoints|

All rows use the original100MHz/IO/hold/multicorner FDC bytes. Native compile/synthesis/map/PNR/report success is distinct from timing acceptance. Every completed route was independently reviewed while its live input hashes matched, and preserves its own immutable source snapshots/results. Later production restoration intentionally differs from rejected inputs; replay those from their snapshots.

The final D seed1 worst path is frontend.fetch.pc_f_q[6]->predictor.ras_index_q[0].CE. Final D seed8 worst is fetch FIFO ram_q[1][46]->execution.result_q[6]. These different cones, together with C's PC CE path, show that the remaining problem spans early decode, speculative frontend control and late enable generation. No further seed search was started.

## Functional and metric evidence

- Execution public-interface miter:80001 structured/random comparisons, signed/overflow boundaries, reset,hold,invalid slots and X/Z including selected-LUI-Z; real PC corruption is rejected. Three backpressure seeds(37,1234567,271828),both issue modes,ordered WB/store/synchronous exceptions and independent IRQ checks pass.
- C and D native area maps consistently show5903LUT/3530FF/688distributedRAM/0CPU DRM/4APM. The candidate's30LUT saving would improve short CoreMark/LUT by0.508216%, but this benefit is not deployed because full timing fails.
- C and final D positive/CRC-negative CoreMark runs retain1646428cycles,1448453WB observations and70840real stores. Entire timed WB/store hashes equal the deployed parent. Final D records:board-coremark-20261020T093553790821Z and093528726393Z. These are5-iteration RTL checks;5000-iteration release firmware was built,not simulated or physically scored. WB observations are not a full ISA retirement proof.
- D adds two board-only status FF,one clock of pass/fail indicator latency,asynchronous clear;CPU stages and UART timing do not change. The original combinational top fails the new contract at352ns(board-system-20261020T093242300926Z). Updated two-boot8KiB system093259792780Z passes all indicator/reset checks. The board fix is also reverted after final whole-system timing rejection.
- All28original CPU vendor files,9CoreMark originals and reviewed adaptation bindings were verified.44SoC Python tests and4structural checker tests pass. Checker regressions reject late-control arithmetic,unknown drivers and missing requested signals;original issue-module behavior is preserved.

The tracked branch_pc_rejected.patch preserves the rejected final source changes for review/replay without compiling them into production. Rejected final RTL/test/filelist bytes are archived in build/soc/branch-pc-final-prototype/snapshot.json. C's build-only complete replay tree is build/soc/branch-pc-compare-candidate;it is frozen evidence,not another maintained project. Final reports are under board-route-20261020T0939267219701Z and0939267219063Z. Exact result/review hashes and all corner values are in the adjacent JSON. Precondition failures(nonexistent old clock directory,incomplete initial scratch snapshot,a protected timestamp collision) are recorded separately and were never counted as passing hardware evidence.

## Next design step

Generate ALU operation/operand-source control before an existing decode register boundary. Evaluate PC/RAS enables from earlier validity,leaving late branch results to choose data. This requires explicit IRQ/flush and invalid-payload tests;the current issue logic can expose execution validity on interrupt cycles even when single_issue is suppressed,so simply replacing the enable with single_issue is unsafe. Preserve six-stage single issue,O2 and the existing predictor algorithm. The next step is not implemented or accepted by this record.
