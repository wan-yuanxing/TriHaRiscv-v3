# Dual operand timing experiments — 2026-10-24

Actual original-constraint 100MHz routing, in the isolated CPU worktree.
**No candidate has met 100MHz or the combined >4/MHz acceptance target.**
Production RTL, board configuration and SoC integration sources are unchanged.

| Candidate | Slow setup | CPU synthesis LUT | CPU synthesis FF | Result |
|---|---:|---:|---:|---|
| Frozen parent | -3.015ns | 10190 | 4916 | Timing FAIL |
| B raw payload v1 | -4.045ns | 10376 | 4916 | Rejected as a timing improvement |
| Two-slot parallel operands v2 | -2.654ns | 10120 | 4916 | Improved, timing FAIL |
| Independent packet hazards v3b, 10min | Unknown | 10154 | 4916 | PNR timeout during hold repair |
| Same v3b RTL, fresh 20min flow | -2.212ns | 10154 | 4916 | Improved, timing FAIL |
| Relative position select v4 | -2.124ns | 10100 | 4916 | Best completed, timing FAIL |
| Early LSU payload v5b | -1.692ns | 9965 | 4916 | Best completed, timing FAIL |

The v3b completed report gives Slow hold +0.133ns/MPW +3.655ns and Fast
setup +1.733ns/hold +0.103ns/MPW +4.202ns. Performance slack equals the
worst setup. PDS exited0; timing verifier exited2. The 10min attempt exited1
with Flow-0232 during hold repair and has no final STA report. The fresh
20min attempt is not evidence of fixed-placement or fixed-routing equivalence.

Area above comes only from the synthesize report's u_core hierarchy. The
LUT count already includes 624 distributed RAM LUTs; each also has 4 APM
and 0 DRM36K-equivalent. It is not
whole-system mapped area or final routed CPU area. ROM/SRAM/MMIO are excluded.
The same RF storage is retained; the v2/v3b dual path reuses existing B reads.

All selected candidates reproduce actual 32KiB synchronous SRAM CoreMark5:
1,253,888 cycles / 1,448,448 WB observations / 70,839 stores,
**3.987597/MHz**, GCC15.2 -O2. Loaded ROM/SRAM images, full measured WB/store
traces and every profile category are identical to the parent. The v3b
Cache-on DDR model rerun gives 1,624,274 cycles / **3.078298/MHz**, with full
traces and measurement equal to the Cache-on parent. These are short RTL
estimates, not official CoreMark or board scores. DDR Cache-off is excluded.

The parent PC→RF read/bypass→exec1 branch path was removed by raw B payload
and parallel A reads. Independent older-producer and same-packet RAW/WAW
checks then shorten the Aaccept→busy-table→B-query→queue-update chain.
The v3b worst path was issue.pc_x_q[19]→exec0.result_q[23]: 11 logic levels,
1.857ns logic and 9.898ns routing (84.2%). Accordingly, the next experiment
used the existing CPU compact-region constraint before changing more RTL.
Its same-RTL package is preserved under build/cpu/dual-hazard-factored-compact-physical-v3b.
Only the existing PAP_REGION/syn_useioff FDC was added; original clock/IO/hold
constraints and 20min/1500s bounds remain identical.

Verification includes address/operand parent RED, candidate GREEN and data
corruption negatives; single-mode compatibility; actual ordered retirement,
store, synchronous exception and IRQ checks; indexed-write packet-hazard
oracle (including unknown allocation/index); and explicit active B gating
for invalid slots, stall, IRQ, cancellation, RAW/WAW and x0. The final hazard
checker completes 8207 checks. Operand-only tests hold squash; the active
permission extension and ordered tests cover execution separately. IRQ runs
are self-checks, not exact IRQ golden/candidate stream equivalence.

Initial A oracle runs incorrectly expected the single-mode RAM unknown-index
behavior in the dual FF RF; these failures are retained but excluded from
RED evidence. The unfixed v3 Boolean experiment is diagnostic-only; v3b's
procedural qualifier and exact known-index case preserve old four-state
indexed-write semantics. The old scoreboard-corruption negative no longer
breaks the independent guard, so the new negative corrupts the actual guard.

Independent review found and resolved budget-field pairing/bool issues before
starting the compact package. Default old packages remain 10min/900s; explicit
new budgets must include both fields. All helper, source and output bindings
are saved. The Windows PDS runs use private work/TEMP/log directories and
never stop other task processes. Runtime may vary due to shared hardware.

Detailed hashes, run paths, timing rows and coverage limits:
[JSON evidence](dualissue_operand_timing.json).

## Compact result and relative-position continuation

The compact attempt hit its20min PNR timeout (native1) with main detailed
iteration97/4458 unrouted, and has no final timing report. The region
constraint is rejected for the current candidate; it is not a timing gain.

The subsequent v4 candidate uses relative word position for payload selection:
`pc_x_q[2] == fetch0_pc_i[2]`. Full PC match remains the execution-validity
authority. The actual FIFO defines valid second output only for two occupied,
contiguous PCs, so a valid A instruction is selected exactly as before.
A simulation-only assertion rejects a valid noncontiguous second input.
This is a closed FIFO/issue contract, not arbitrary unconstrained port-level
behavior. Unmatched-cycle payload changes are intentional; actual firing stays
address-qualified. High-PC mismatch, cross-packet head positions, corruption,
actual contiguity violation, ordered/IRQ and full SRAM streams are checked.
The initial generated-TB compile error is excluded from RED evidence.

v4 real SRAM again measures1253888cycles/3.987597 CoreMark/MHz short estimate,
with exact parent WB/store/profile and loaded images. Original unregionalized
PDS completed under build/cpu/dual-position-select-physical-v4. Actual final
Slow setup/hold/MPW are -2.124/+0.128/+3.655ns; Fast +1.753/+0.102/+4.202ns.
Native PDS exit0, timing verifier2, all515 frozen outputs verified. CPU synthesis
u_core is10100LUT/4916FF/624RAM-LUT(included)/4APM/0DRM; new map and placement.
No performance or frequency admission is claimed.

The v4 runtime contract assertion checks the known noncontiguous negative; it
does not reject every artificially forced unknown-PC pattern. Actual FIFO
valid1 cannot be definitely1 for those unknown patterns. The transformation
relies on the closed FIFO/issue contract, not this debug assertion alone.

## LSU payload preparation v5b

The actual v4 path launches ctrl_wb_q[7], despite the packed cell's pc_wb_q
name. WB bypass feeds exec0 branch compare, late pipe1_mux_lsu_r then selects
the complete LSU opcode before store alignment/data capture:14levels,
2.499ns logic/9.066ns routing. It is not a PC-data-to-LSU dependency.

v5 prepares possible B LSU payload from static classes before late issue
permission. A LSU and A CSR cache maintenance retain A. Only actual issue may
authorize memory effects. Review found an invalid B/class-X valid-propagation
edge in the first draft; an observed failing test records it. Selected v5b
qualifies valid with actual A LSU/CSR issue or B LSU issue, preserving IRQ
inhibition and CSR DFLUSH/DWRITEBACK/DINVALIDATE. The early selector relies on
the actual decoder's class/payload contract; arbitrary inconsistent flags are
not claimed equivalent.

Directed14checks, unauthorized-store corruption negative, ordered and IRQ
self-checks pass. Actual SRAM1253888cycles and Cache-on1624274cycles remain
unchanged, with loaded images and complete measured WB/store streams matching
their parents. `build/cpu/lsu-prepare-v5b-comparison.json` binds these comparisons.
Independent source/evidence review passed. Original-FDC no-region20min PDS
completed under build/cpu/dual-lsu-prepare-physical-v5b: Slow setup/hold/MPW
-1.692/+0.154/+3.655ns, Fast +2.087/+0.100/+4.202ns. Native exit0/verifier2;
681 frozen outputs verified. CPU-only synthesis9965LUT/4916FF/624RAM-LUT
(included)/4APM/0DRM. New mapping and placement;100MHz remains unaccepted.

The worst real path is now fetch1 instruction[15] through operand bypass and
exec0 branch comparison to FIFO compaction/capture:12levels,2.022ns logic and
9.177ns routing. The next experiment replaces dynamic destination compaction
with fixed entry muxes while retaining the four-word contract, then measures
six words separately. No pop-dependent ready path is introduced.
