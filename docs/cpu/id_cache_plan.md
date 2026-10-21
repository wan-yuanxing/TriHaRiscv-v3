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

- [ ] Add an opt-in cached subsystem target, retaining existing local ROM/SRAM and board target sources. Route private DDR through Cache and shared/MMIO through uncached completion paths. Preserve tags and ordering across local/DDR target changes; no speculative store acknowledgments.
- [x] Add `triha_cached_core.v`, real software and native CPU tests for DDR execution, byte load/store, shared attributes, access faults and FENCE.I. Cache on/off observed identical154WB/ninestores, including younger-store cancellation after load error. DDR-only CPU boundary is complete; enclosing local-memory/MMIO routing is still the preceding open step.
- [x] Measure same-O2/noLTO five-iteration CoreMark with identical loaded ELF segments/program placement and fixed lower-memory model. Non-loaded source-path `.strtab` differs and is explicitly checked. Cycles10646732→4699674; throughput+126.541926%; standard CRCs and one-iteration CRC negative verified. Preserve SRAM results separately.
- [ ] Add timed hit/miss event observations and finish system-level performance/physical admission. Existing counters measure actual lower transactions and directed hits; do not present them as a complete hardware performance CSR implementation.

## 6. Physical and integration admission

- [ ] Measure bare-core, Cache/transport and combined resources with native PDS. Run one original100MHz complete implementation and independent frozen-binding/Slow-Fast setup/hold/MPW review. Preserve failed intermediate evidence; no timing claims from synthesis estimates.
- [ ] Bind the actual main-project DDR version and integrate through its existing shared fabric/CDC boundary; independently validate write visibility and reset with other masters before claiming system closure. Do not modify or copy another route's implementation silently.
- [ ] Update `docs/cpu/STATUS.md` and `docs/verification/cpu/id_cache.*`, commit only this CPU work. Retain known-good release; no automatic programming, COM12, Flash, merge or push.

Checkpoint2026-10-21: `docs/verification/cpu/id_cache_stage1.md/.json` binds functional and native-area results; accepted image unchanged. CPU+Cache context6890LUT/4326FF/688RAM-LUT(included)/11DRM36K-equivalent/4APM; same-boundary bypass6632/4096/688/0/4. Actual100MHz and realDDR/board gates remain open.
