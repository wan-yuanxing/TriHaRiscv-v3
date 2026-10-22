# CPU I/D Cache implementation plan

> Execute inline with executing-plans and test-driven-development. User has already selected same-batch I/D Cache implementation; no agents or new worktree. Design: `docs/cpu/id_cache_design.md`.

**Goal:** A reusable, jointly verified I/D Cache subsystem for the existing single-issue CPU and current SoC DDR contract.

**Architecture:** Fixed two-way 16KiB/32B-line caches, synchronous block RAM, blocking write-through/no-write-allocate D, private-DDR attributes and shared 128-bit AXI lower boundary. Keep production minimal/board targets intact until admission.

**Tools:** Installed Windows Python, ModelSim2020.4, PDS2022.2 and GCC15.2; no WSL or HDL generator.

## 1. Preserve and bind

- [x] Tag `e4eae68` as `cpu-before-id-cache-20261021`; verify the existing isolated CPU branch and clean production baseline.
- [x] Freeze reference files at revision `6af9c4be5a0807d368eaad5e49af52322e31d073` in build, compare Git blob identities and preserve seven selected original files under a separate cache manifest. Unused originals remain only in build; original28core/ninebenchmark files are unchanged.
- [x] Add explicit `config/cpu_cache.json`, `config/cpu_cache_sources.f` and `fpga/pg2l100h/project/cpu_cache.json`; validate geometry and private/shared DDR bounds in the native runner. Add CPU+Cache mapping target `cpu_cached_core.json`. Report bare-core/cache/total context separately; fixtures excluded.

## 2. Native paired component harness

- [x] Create `scripts/cpu/run_cache.py` with independent timestamped build directories, frozen input copies, native process timeouts, exact command/exit records, output hashes and source/external stability checks. Reuse installed ModelSim and existing Tcl exit policy. Missing-module RED recorded before import/adaptation.
- [x] Add `tb/cpu/tb_cpu_cache.v`: independent memory bytes and transaction counters; I64/D32 requests, D11-bit tag, blocked lower response, fill/hit/replacement, partial strobes, read/write failures, invalidate and simultaneous I/D traffic. Successful run requires both I and D hit/miss coverage. Corrupted data returns failure.
- [x] Run component RED, positive and corruption negative. Final positive also covers a D flush held through an owned refill and verifies the freshly filled line is invalidated after maintenance.

## 3. Adapt the matched I/D controllers

- [x] Import selected originals and license. Create I/D controllers and synchronous RAM wrappers with explicit adaptation/hash bindings. I retains lookup/refill; D specializes tag/replacement/RAM organization for write-through completion and removes dirty/writeback behavior. PDS's rejected unused second RAM writer was specialized to the actual lookup-only port.
- [x] Hold lower store response40cycles in components and30cycles in transport; reject premature completion; require write-error invalidation and no write-miss refill/allocation. Native positives/negatives preserved.
- [x] Exercise every refill-error position, ways/conflicts, I flush during refill, held D flush, and reset after drain. Actual RED exposed stale I-cache valid publication and dropped flush; both repaired and retested. Original hashes verified.

## 4. Lower transport and joint subsystem

- [x] Create AXI128 transport and isolated test, with missing-module RED. Test two-beat refills, scalar lanes/strobes, two-word uncached fetch, VALID stability, errors, ID/LAST quarantine and4KiB geometry. Non-DDR requests cannot be widened onto DDR.
- [x] Add fair I/D arbitration; joint bench exercises misses/stores, shared accesses and changed shared instructions. Add `triha_ifetch_uncached.v`; shared instruction accesses cannot allocate in I-cache.
- [x] Native compile/synthesize/dev_map passed after correcting single-writer RAM inference and isolating internal buses from package pins. Actual block primitives used, no latches or distributed cache data RAM; serial area fixtures separately reported. Mapping is not100MHz timing admission.

## 5. CPU/SoC integration

- [x] Add an opt-in cached subsystem target, retaining existing local ROM/SRAM and board target sources. `triha_cached_soc` and `triha_cpu_memory_router` retain response owners/pending counts across local/DDR/status changes; shared accesses bypass Cache, maintenance is address-independent, and DDR init/fault never masks accepted lower transactions. Native router and actual ROM/SRAM/DDR CPU programs pass with Cache enabled/bypassed. This closes the local-system routing step, not real DDR/CDC or physical admission.
- [x] Add `triha_cached_core.v`, real software and native CPU tests for DDR execution, byte load/store, shared attributes, access faults and FENCE.I. Cache on/off observed identical154WB/ninestores, including younger-store cancellation after load error. The enclosing local-memory/MMIO step was subsequently completed in stage2.
- [x] Measure same-O2/noLTO five-iteration CoreMark with identical loaded ELF segments/program placement and fixed lower-memory model. Non-loaded source-path `.strtab` differs and is explicitly checked. Cycles10646732→4699674; throughput+126.541926%; standard CRCs and one-iteration CRC negative verified. Preserve SRAM results separately.
- [ ] Add timed hit/miss event observations and finish system-level performance/physical admission. Existing counters measure actual lower transactions and directed hits; do not present them as a complete hardware performance CSR implementation.

## 6. Physical and integration admission

- [x] Measure bare-core, Cache/transport and combined resources with native PDS. Run one original100MHz complete implementation and independent frozen-binding/Slow-Fast setup/hold/MPW review. Stage5 closes the standalone physical target; all failed intermediate evidence is retained. Shared-fabric/board gates remain separate.
- [ ] Bind the actual main-project DDR version and integrate through its existing shared fabric/CDC boundary; independently validate write visibility and reset with other masters before claiming system closure. Do not modify or copy another route's implementation silently.
- [x] Update `docs/cpu/STATUS.md` and `docs/verification/cpu/id_cache.*`, commit only this CPU work. Stage5 records the standalone physical checkpoint; integration/board gates below remain open. Retain known-good release; no automatic programming, COM12, Flash, merge or push.

Checkpoint2026-10-21: `docs/verification/cpu/id_cache_stage1.md/.json` binds functional and native-area results; accepted image unchanged. CPU+Cache context6890LUT/4326FF/688RAM-LUT(included)/11DRM36K-equivalent/4APM; same-boundary bypass6632/4096/688/0/4. Actual100MHz and realDDR/board gates remain open.

Second checkpoint2026-10-21: `docs/verification/cpu/id_cache_stage2.md/.json` binds complete local routing, two-mode real software, UART and platform/access-fault handling, negative checks and native mapping. Local CPU+Cache+ROM/SRAM/MMIO is7180LUT/4431FF/27.5DRM/4APM excluding scan fixture; CPU6434LUT, Cache/transport519LUT, local memory183LUT, routing44LUT in this synthesis context. Current main-project DDR bridge has changed since this worktree snapshot; bind its actual version before integration. CPU100MHz vs DDR125MHz CDC, shared fabric/other-master visibility, actual post-route100MHz and board validation remain open. Do not use the area fixture for frequency acceptance.

## 7. Clock-boundary and pinned DDR bridge checkpoint

- [x] Pin four DDR dependencies to immutable commit8635a91626d87eb7573beba5ea805a5f6043bb8a and exact bytes in `config/cpu_ddr.json`; extract Git objects to each build with `prepare_ddr.py`, without overwriting this worktree's older Video files or reading another checkout's changing files.
- [x] Add five independent elastic FIFO channels in `triha_axi128_cdc.v`, reuse the pinned FIFO unchanged, and keep online/fault separate from transaction ownership. One global reset asserts both local reset pipes; each clock releases its own pipe synchronously.
- [x] Independently check all channel payload bits, ordering, arbitrary backpressure and live reset at nominal100/125MHz plus two inverse stress ratios. Corruption/watchdog negatives return1.
- [x] Compose `triha_cpu_ddr.v`: local cached CPU, CDC and the pinned exclusive native bridge. Actual existing O2 software passes with Cache on/off; all22 successful stores wait for native write plus readback; real bridge init-loss and three CPU access faults are observed. Reset after an accepted native write and before CPU completion, then successfully restart the entire program.
- [x] Run native compile/synthesize/dev_map and independently re-read frozen files, actual elaboration, output hashes and CPU/Cache/CDC/bridge area. `docs/verification/cpu/id_cache_stage3.md/.json` records10671LUT/7942FF/33.5DRM/4APM excluding scan logic; CPU6218LUT, Cache514LUT, CDC67LUT/153FF/6DRM, bridge3691LUT/3358FF. Context differs from stage2; do not claim a core optimization.
- [x] Bind the physical DDR controller/clock/pin top and reviewed CDC physical constraints, then run the original100MHz multi-corner post-route checks. Stage5 passes actual all-clock summaries plus native XML Gray max/min skew groups. No area fixture is a timing boundary.
- [ ] Integrate CPU/NPU/Video arbitration upstream of the one native bridge and prove other-master write visibility. The exclusive CPU wrapper is not that shared fabric. Board admission remains separate; no automatic programming or COM12 access.

## 8. Standalone physical DDR board boundary

- [x] Bind the canonical71 DDR pins/PHY constraints and priority nets, one shared differential reference buffer, actual HIGH-bandwidth CPU PLL and exact74-source generated DDR IP in an explicit hardware manifest. Digital substitutes never enter the hardware filelist.
- [x] Add free-clock startup/init/clock/PLL supervision and an actual O2 standalone firmware image. Two software boots each test private/shared8KiB and changed executable private instructions through FENCE.I. Four fault monitors and real native readback-corruption rejection pass.
- [x] Correct PDS wide-cell versus mapped-bit Gray selectors; independently verify20 three-bit selections and six first-stage synchronizer selections. Keep only scoped asynchronous control exceptions; second-stage D paths remain timed.
- [x] Reproduce unsynchronized board-state release with an executable failing check; use local two-stage free/DDR releases for LEDs, heartbeat and fault synchronizers. Repeat all board digital tests after the repair.
- [x] Run two fresh complete compile/synthesize/dev_map/place/route/report_timing implementations under original100MHz/IO/hold/multicorner budgets. Independently re-read bindings, actual stages, all clock summaries, CPU-only hierarchy and max-delay paths. Stage4 records actual failures, not admission.
- [x] Close the actual remaining CPU setup path (-0.155ns/two endpoints), vendor phase-adjust FSM reset recovery (five endpoints), and explicitly verify Gray skew. Stage5 uses reference-clock reset release with stricter clock relationships; CPU RTL/cycles/ISA/predictor are unchanged. Native XML supplies complete skew evidence, not an inference from max-delay.
- [ ] Shared-fabric/other-master visibility, physical DDR training and board admission remain separate gates. The previous deployment stays intact; no COM12, programming, Flash, merge or push.

Stage5 checkpoint2026-10-22: actual standalone CPU100MHz/DDR125MHz implementation passed all constrained clocks and corners, including recovery/removal and all Gray groups. CPU setup+0.213/+3.617ns, hold+0.136/+0.082ns, MPW+3.655/+4.202ns; worst skew slack+0.966ns. Two real software boots/four fault cases and corruption negative pass with the new reference release. Timing-admitted diagnostic bitstream/mask/ELF/images/reports are packaged as`cpu_ddr_board_189c51babb73`; no board operation. Details and frozen hashes:`docs/verification/cpu/id_cache_stage5.md/.json`.
