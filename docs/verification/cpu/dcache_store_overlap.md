# Different-set D Cache store-overlap diagnostic

2026-10-23. Parent `febadb3`, backup `cpu-before-store-overlap-20261023`.
Experiment completed and **not selected** at the resource-efficiency gate.
Production RTL, cache manifest, runner selection and simulation-only profiler
are restored byte-for-byte to the admitted parent. The board retains the
newly measured parent image `cpu_ddr_coremark_on_478149ee9e63`.

## Design and functional result

The candidate accepts an ordinary load/store during a successful cached
STORE_UPDATE only when its set differs from the completing store. The old
write bytes, way, address and dirty tag still update on that edge, while the
other synchronous RAM port reads the successor. Same-set and maintenance
successors wait; load-response overlap remains intact. No load register or
clock/IO/hold constraint is removed, and no forwarded dirty-data mux is added.

Public-interface test RED on unchanged parent:
`build/cpu/cache-store-overlap-20261023T020630079640Z`.
Final candidate GREEN,384checks:
`build/cpu/cache-store-overlap-20261023T021810002396Z`.
Coverage includes both ways, byte stores, same/different words/tags/sets,
load/store/miss successors, dirty eviction failure/retry, shared/uncached
successors, maintenance, failed refill/retry with an independently required
new lower read, malformed address and simultaneous read/write, held younger
store rejection, and reset immediately after the store/successor edge.

Prior load-overlap, registered-load, writeback, joint/FENCE.I, real CPU,
bypass CPU/SoC, native DDR and digital two-boot plus four supervisor tests
pass. Store-data, CPU-data and board-readback corruption negatives are rejected;
the component corruption negative fails during warmup. Independent review
found no RTL defect; its failed-refill oracle coverage finding was fixed and
rechecked in the final384-check run. These are bounded digital tests.

## Same-payload model comparison

Frozen comparison:
`build/cpu/ddr-store-overlap-review-20261023T021445729961Z/result.json`.
Parent `build/cpu/ddr-coremark-20261022T144143278308Z`; candidate
`build/cpu/ddr-coremark-20261023T020824984650Z`.

| Five-iteration RTL/native-DDR result | Parent | Candidate |
|---|---:|---:|
| Cycles | 2,018,576 | 2,003,870 |
| Short CoreMark/MHz estimate | 2.476993683 | 2.495171842 |
| Load-edge acceptances | 75,408 | 76,293 |
| Store-edge acceptances | 0 | 9,972 |
| Same-set store-edge waits | not instrumented | 3,085 |
| Native read commands | 226 | 226 |
| Native writes | 0 | 0 |

14,706 fewer cycles; modeled throughput+0.73387994%. Exactly the same loaded
GCC15.2-O2/no-LTO program, cache requests/misses and native event counts.
Complete normalized1,448,453WB and70,840store observation streams match;
only absolute initial timestamp values are excluded. Store/load scheduling
interactions mean cycles saved are not simply the store-edge count.
These short results are not physical or official scores. The UART denominator
6507 in this test is prior metadata, not the candidate's mapped CPU area.

## Resource gate and selection

Same-boundary native area:
parent `build/cpu/ddr-board-route-20261022T145158660561Z`,
candidate `build/cpu/ddr-board-route-20261023T021433808724Z`.
Compile/synthesis/dev_map all complete with unchanged frozen inputs/outputs.
ROM/SRAM bytes and normalized hardware Tcl match. The only changed compiled
hardware file is `triha_dcache.v`; ELF debug metadata differs but is not a
synthesis input. DDR/CDC/board fixtures are excluded from CPU-only figures.

| Hierarchy | Parent LUT/FF | Candidate LUT/FF | DRM/APM |
|---|---:|---:|---:|
| CPU only | 6507 / 3562 | 6571 / 3562 | 0 / 4 |
| Cache/transport | 668 / 807 | 677 / 807 | 11 / 0 |

CPU distributed RAM LUT688 remains included in total CPU LUTs. The CPU RTL
itself is unchanged; the ready/handshake context changes synthesis results.
CPU-LUT efficiency falls0.24724444%; CPU+cache efficiency falls0.28068590%.
The small modeled gain does not improve either area-efficiency metric, so the
experiment ends before full PNR. Candidate actual100MHz is **UNKNOWN / NOT RUN**;
it is neither a timing failure nor a timing pass. No candidate package or
board programming was performed.

## Replay and retained state

Complete experiment sources and frozen evidence remain in build. Versioned
`dcache_store_overlap_diagnostic.patch` reconstructs the experiment from a
clean `febadb3` checkout; do not apply it directly to the advanced branch.
Patch application and every resulting candidate byte were checked in an
isolated replay directory. Archive manifest:
`build/cpu/store-overlap-archive-20261023/result.json`.
Parsers retain backward-compatible support for reading the archived observations;
no store-overlap hardware or unused feature parameter remains in production.

Terminal audit: `build/cpu/review-store-overlap-terminal-20261023.py`.
Machine-readable index: `dcache_store_overlap.json`.
After restoration the complete admitted parent's actual100MHz source/tool/
evidence/output bindings and release hashes pass again. CPU Slow/Fast setup
+0.309/+3.551ns; all hold/MPW/CDC checks pass. The parent's new actual board
score249.743516780 is independently recorded in `dcache_overlap_board.md/.json`.
COM12 is released, no Flash written, main worktree untouched.

Next performance work should instrument the remaining LSU stalls in more detail
before choosing another data-path change; the measured parent is the base.
