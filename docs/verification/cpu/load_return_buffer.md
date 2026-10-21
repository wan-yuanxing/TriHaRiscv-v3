# CPU load-return buffer evaluation

2026-10-21. **Not selected: resource efficiency regressed.** Production RTL, software, configurations, tests and runners were restored to the deployed `dc00f80` bytes. The existing release remains `build/soc/releases/cpu_coremark_6ff82025b53d`. This experiment was not routed, packaged or programmed.

The optional 32-entry completed-load buffer reduced actual short RTL CoreMark dependency stalls, but its measured CPU cost exceeded its throughput benefit. Stop this candidate at the synthesis/performance gate instead of spending another physical implementation run. This is a resource decision, not a timing failure; candidate 100MHz timing remains **unverified**.

| Measurement | Accepted parent | Buffer prototype | Change |
|---|---:|---:|---:|
| Timed cycles, 5 iterations | 1,646,428 | 1,621,293 | −25,135 |
| Dependency stall cycles | 106,114 | 80,979 | −25,135 |
| CoreMark/MHz, short RTL | 3.036877410 | 3.083958297 | +1.550306% throughput |
| CPU LUTs, includes distributed RAM subset | 5,933 | 6,178 | +245 / +4.129445% |
| CPU FF | 3,528 | 3,561 | +33 |
| Distributed RAM LUT subset | 688 | 708 | +20, already included above |
| CPU DRM / APM | 0 / 4 | 0 / 4 | unchanged |
| CoreMark/LUT, nominal 100MHz short RTL | 0.051186203 | 0.049918393 | −2.476859% |

Compiler: native Windows RISC-V GCC 15.2.0, `-march=rv32im_zicsr -mabi=ilp32 -std=gnu99 -O2 -mcmodel=medany -mno-relax -msmall-data-limit=0 -ffreestanding -fno-builtin -ffunction-sections -fdata-sections -nostdlib -Wl,--gc-sections`, no LTO. The result JSON preserves complete actual compiler/link commands, defines, inputs and tools. CoreMark algorithms and the 2,000-byte data configuration were unchanged. Standard CRCs were `e9f5/e714/1fd7/8e3a`.

These are five-iteration **RTL simulation** measurements, not physical board scores or official CoreMark submissions. The 5,000-iteration firmware was built but not executed. The prototype's nominal 100MHz normalization does not establish post-route timing or deployed CoreMark/LUT.

## What was tested

The prototype added a default-off, single-issue-only local SRAM forwarding aid: 32 entries of complete 32-bit load response words, 8-bit local tags and resettable valid bits. Storage reused the project's existing native asynchronous RAM pattern. The fixed 32KiB local SRAM window was explicit. Only successful aligned load completions filled entries; accepted stores invalidated their indexed entry, and reset/maintenance/error invalidated all. Every load still sent its original real request and used the original completion/fault path. A qualified current-E1 hit could supply the existing dependency forwarding mux. Prediction remained BTB512/BHT512/RAS4 with GShare off; six stages, RV32IM/CSR and single issue were unchanged.

Read-only replay accounted for 103,559 genuine adjacent load dependencies; only 210 were store-data-only. Reusing the existing held 64-bit SRAM return had zero adjacent load-use savings. The 32-entry buffer's optimistic trace upper bound was 25,360 saved cycles; actual savings were 25,135. Thus a larger performance gain from this exact organization is not supported by the trace. The buffer hierarchy alone used 101 LUT/32 FF/20 distributed RAM LUTs; total CPU growth was 245 LUT, so hierarchy cost cannot replace the whole-CPU denominator.

Component buffer, LSU formatting/fault/backpressure/store invalidation and issue forwarding tests passed. Each has a real missing-feature RED and a corruption negative that returned failure. The existing narrow-MUL forwarding regression passed. Final ordered comparisons used three backpressure seeds plus a separate IRQ run, each with the same newly built ELF for candidate and golden. Candidate single issue actually exercised 30 early-load hits in every run; dual issue correctly kept the feature disabled. The repeated-load stimulus was necessary because the original stress loop invalidated the entry with a store before each load. Initial zero-hit coverage failures and intermediate compile/oracle errors remain in their original build directories.

The two-boot board-system RTL test passed. CoreMark positive passed; the CRC-corruption negative reported `errors=1`, software exit 1 and host exit 1. All 1,448,453 timed WB observations and 70,840 actual stores matched the parent in order and value except the first absolute `rdcycle` sample and its stored value, which legitimately changed. The comparison validates the exact instruction/address prefixes of those two exceptions before excluding only their values. It is not byte-identical raw trace equivalence or complete architectural retirement proof.

Known admission gaps remain: no complete ISA/coherence proof, and no integrated whole-CPU proof of cached-hit forwarding followed by real-load error cancellation of a younger store. Component tests cover the real fault path but do not close that combined scenario. The candidate is rejected before physical admission; these gaps are not waived.

## Evidence and restoration

The companion [JSON](load_return_buffer.json) binds all 14 prototype input files, 18 terminal results, 721 frozen outputs, trace comparisons, actual hit counts and the analysis records. Original vendor 28 and benchmark 9 files were rehashed against their manifests without changes.

Key native run directories, relative to this CPU worktree:

- Area: `build/soc/cpu-area-20261021T015421928153Z`.
- CoreMark positive / CRC negative: `build/soc/board-coremark-20261021T060956731420Z` / `board-coremark-20261021T061006284909Z`.
- Two boots: `build/soc/board-system-20261021T015421945645Z`.
- Ordered seeds/IRQ: `build/cpu/redirect-ordered-20261021T0612008068215Z`, `0612116389566Z`, `0612213077633Z`, `0612306264244Z`.
- Exact prototype snapshot and analysis: `build/soc/load-return-buffer-prototype/`.

The tracked [replay patch](load_return_buffer_replay.patch) contains all prototype RTL, source-list/adaptation changes, directed tests, runner changes and stress stimulus. Its base is `2de418c`, backed up as `cpu-before-load-return-buffer-20261020`. `git apply --check` passed after restoration. It is an archival experiment, not an approved production change.

After restoration, independent review of the original route `build/soc/board-route-20261020T0824200693298Z` passed again with current production bindings: Slow/Fast setup +0.113/+1.821ns, hold +0.160/+0.101ns, minimum pulse width +3.655/+4.202ns, recovery/removal clean. This revalidates the existing 100MHz result, not a new route or board execution. Review: `build/soc/load-buffer-restored-parent-review.json`. The 44 SoC Python checks and four PC arithmetic checks passed after restoration.

The CPU branch and worktree are retained. No main-project/Video changes, COM12 access, Flash operation, merge or push occurred. Further optimization should start from this measured parent and establish a useful performance/area bound before another RTL or physical experiment; do not enlarge this buffer or remove real load/fault interlocks merely to improve the benchmark.
