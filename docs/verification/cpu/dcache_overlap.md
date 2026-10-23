# D Cache registered-response overlap

Implemented 2026-10-22; terminal verification finalized 2026-10-23.
Parent `43e0428`, preserved by tag
`cpu-before-dcache-overlap-20261022`. Work remains in the isolated CPU worktree
on `cpu/windows-baseline`; main-project sources and the deployed board image
are unchanged. This candidate builds on the accepted write-back design.

## Change

During a successful cached-load RESPONSE, the old response stays in data/tag
registers while the next request can be accepted on the completion edge.
Synchronous tag/data RAM ports read that incoming address for the next lookup.
The resident-load initiation interval is two cycles instead of three.
There is no direct Cache RAM to CPU bypass, extra cache storage, removal of a
load return register, predictor change, or change to the six-stage single-issue
CPU architecture. STORE_UPDATE, error, uncached and maintenance responses are
still serialized. Dirty-line writeback and private/shared attributes are intact.

## Functional evidence

The independent public-interface overlap test fails on the parent at
`build/cpu/cache-overlap-20261022T143520075231Z` with the missing acceptance
check. The candidate passes at
`build/cpu/cache-overlap-20261022T150939844789Z` (142 checks), including twelve continuously
offered loads, different sets/tags/words, same-set tag conflicts, registered
data/tag stability, byte store, failed overlapped load with a held younger
store, uncached read, and line/full maintenance.

Permanent joint test `build/cpu/cache-joint-20261022T144759614566Z` forces the
internal FENCE.I flush to be accepted on an original cached-load response edge
and checks that CPU receives exactly the original data/tag/ack. The internal
flush completion stays hidden. An independent reviewer reproduced this corner
in `build/cpu/review-overlap-fence-20261022T144900568792Z` and found no actionable
RTL defect. Real CPU faults, byte operations and self-modifying code pass at
`build/cpu/cache-cpu-20261022T144020156496Z`; write-back regression passes at
`build/cpu/cache-writeback-20261022T144020816377Z`; registered load boundary
check passes at `build/cpu/cache-components-20261022T144023080609Z`.

Real local SoC and native-DDR system tests pass at
`build/cpu/cache-soc-runtime-20261022T144143291882Z` and
`build/cpu/ddr-system-20261022T145159469180Z`. Two-boot board-wrapper digital
self-test passes at `build/cpu/ddr-board-20261022T144146642977Z`.
Corruption negatives return failure. These are digital tests, not board tests.

## Same-payload performance

Independent frozen profile/trace comparison:
`build/cpu/ddr-overlap-review-20261022T145315703760Z/result.json`.
Candidate: `build/cpu/ddr-coremark-20261022T144143278308Z`.
Five iterations, identical loaded CoreMark program, GCC15.2 `-O2`, no LTO,
same 100MHz/native-DDR model and unchanged memory transaction counts.

| Metric | Write-back parent | Response-overlap candidate |
|---|---:|---:|
| Cycles | 2,158,431 | 2,018,576 |
| Short RTL CoreMark/MHz estimate | 2.316497493 | 2.476993683 |
| Timed WB observations | 1,448,453 | 1,448,453 |
| Timed store observations | 70,840 | 70,840 |
| Response-edge acceptances | 0 | 75,408 |
| Native read commands | 226 | 226 |
| Native writes | 0 | 0 |

139,855 fewer cycles; modeled throughput +6.928399%. Complete normalized WB
and store streams match, with only the absolute start timestamp excluded.
Standard CRCs match. The observer now restarts classification on each accepted
request, rather than requiring an IDLE gap. It is not synthesized. Digital
DDR clock-phase differences slightly change waiting occupancy despite the
same native events; no physical memory latency measurement is implied.

## Resources and physical gate

Native area run `build/cpu/ddr-board-route-20261022T145158660561Z`:

| Hierarchy | Parent LUT/FF | Candidate LUT/FF | DRM/APM |
|---|---:|---:|---:|
| CPU only | 6459 / 3562 | 6507 / 3562 | 0 / 4 |
| Cache/transport | 671 / 807 | 668 / 807 | 11 / 0 |

CPU distributed RAM LUTs remain 688, already included in CPU LUT total.
The CPU RTL itself is unchanged; 48 extra CPU LUTs reflect synthesis in the
changed handshake context, not a new CPU feature. The five-run UART carries
prior 6459-LUT metadata for comparison; the full image uses the new measured
6507-LUT denominator.

Complete implementation: `build/cpu/ddr-board-route-20261022T150815081810Z`.
Compile, synthesis, device mapping, routing and timing-report generation all
completed successfully. Independent frozen source/tool/evidence/output and
final timing review:
`build/cpu/ddr-board-route-20261022T150815081810Z-independent-review.json`.

| CPU post-route slack | Slow | Fast |
|---|---:|---:|
| Setup | +0.309 ns | +3.551 ns |
| Hold | +0.151 ns | +0.099 ns |
| Recovery | +4.907 ns | +6.546 ns |
| Removal | +0.177 ns | +0.102 ns |
| Minimum pulse width | +3.655 ns | +4.202 ns |

All clock domains pass setup/hold/recovery/removal/MPW, including the DDR PHY
clock MPW margin of +0.035ns in both corners. All 60 Gray max-delay paths and
20 Slow/Fast skew groups pass; worst skew slack +1.211ns, largest actual skew
0.789ns under the original 2ns requirement. CPU performance slack is +0.309ns
and agrees with the worst setup path. The worst CPU path starts in the boot
ROM and ends at execution result bit 8. Its full endpoints are in the review.
The original 100MHz, IO, hold and multi-corner constraints are unchanged.
Relative to the write-back parent's +0.134ns setup, this new netlist/layout has
0.175ns more margin; no higher frequency has been tested or admitted.

## Prepared release and final checks

`build/soc/releases/cpu_ddr_coremark_on_478149ee9e63` contains the bitstream,
matching mask, routed database, constraints, actual timing reports and review,
and 5000-iteration GCC15.2 `-O2`/no-LTO CoreMark. CPU-only UART denominator is
6507; UART also prints CoreMark/LUTs. Matching one-iteration digital preflight:
`build/cpu/ddr-coremark-20261022T150520126974Z`.
Bitstream SHA256:
`478149ee9e631ca60590c5d8b8d63c1a245924823613b98f3c59a5530554f561`.

Package result: `build/cpu/ddr-board-package-20261022T154526724916Z/result.json`.
The final terminal audit rechecked frozen functional evidence and expected
negative failures, the same-payload comparison, actual post-route review and
every packaged file hash. Machine-readable index: `dcache_overlap.json`.
Final regressions pass: 69 CPU Python tests, 45 SoC Python tests, cache-original
preflight and `git diff --check`.

Final independent source review found no actionable issue in response ownership,
FENCE.I collision handling, profiling or same-payload comparison. It independently
checked both frozen hash sets, the complete normalized WB/store streams and all
16 release-file hashes. The corrupt-data negative fails during warmup, proving
oracle rejection; overlap behavior is exercised by the parent missing-feature
failure and the continuous ordered-response scoreboard.

This is a standalone CPU/DDR physical checkpoint. The current board remains
on `cpu_ddr_coremark_on_32019ccd2f69`; the candidate has no physical CoreMark
score or DDR-training acceptance. No board download, COM12 access, Flash write
or main-worktree modification occurred. Next validation is a full 5000-iteration
board run using the prepared image, before selecting further optimizations.
