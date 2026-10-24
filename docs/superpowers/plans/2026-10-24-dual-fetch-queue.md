# Dual fetch queue implementation plan

> Execute inline with executing-plans and verification-before-completion;
> request independent review at the candidate/physical boundary.

**Goal:** Reduce compact-FIFO routing cost, then measure extra capacity without
adding an issue-to-fetch combinational ready path.

**Architecture:** Fixed destination entries select one of three static older
sources, then accepted input append has priority. Six-word depth is a separate
candidate so structural timing and performance effects can be assessed.

**Tech stack:** Windows Verilog, ModelSim, existing GCC15.2-O2 and PDS.

- [x] Passive actual SRAM profile: queue occupancy and response backpressure;
      preserve1253888cycle/full-stream parent comparison.
- [x] Extend `tb/cpu/tb_fifo_cross_pair.v` with parameterized capacity and
      unknown pop/pred coverage; run the original4word parent oracle.
- [x] Add a separate same-capacity reference comparison test: unchanged
      inactive slots, reset, flush and every sideband. Preserve corrupt negative.
- [x] Create `build/cpu/dual-fifo-entry-v6/rtl/cpu` from selected v5b; modify
      only `triha_decode.v` compact storage. Keep immutable parent snapshot.
- [x] Verify fixed-entry candidate against both oracles and full ordered/IRQ,
      SRAM and Cache-on runs. Freeze a full-base patch and source manifest.
- [x] Create a separate6word depth candidate, change both decode FIFO
      instantiations explicitly to `.DEPTH(3)`; count is already3bits.
- [x] Run capacity6 expectation on old parent to demonstrate RED; run new
      GREEN and corrupt metadata negative. Extend passive occupancy to8words.
- [x] Measure actualSRAM-O2 and Cache-on, compare complete normalized
      WB/store streams. Reject if no benefit or if functional contract fails.
- [x] Evaluate v5b terminal actual STA; choose the measured reviewed FIFO
      candidate for fresh no-region20min original-FDC PDS.
- [x] Verify all frozen inputs/output hashes and actual Slow/Fast six timing
      checks, performance consistency and CPU-only synth resources.
- [ ] Record actual results, commit narrowly; no target admission until the
      same physical candidate exceeds4/MHz and passes100MHz.

## Actual terminal continuation: scalar squash and BTB minimum delay

Six-word route completed with setup-2.228ns and Slow/Fast hold-0.068/-0.060ns.
The actual setup path starts valid_e2_q through wide exception selection/OR,
squash and queue update. Hold is training FF straight to native BTB WADDR0.
Continue these measured paths before the independently researched native RF.

- [x] Exhaustive scalar/vector exception oracle on parent;65536 known cases.
- [x] In an isolated v7 snapshot, pre-reduce both exception sources and select
      scalar in the same original procedural if/else. Preserve full vector/WB.
- [x] Extend scalar oracle with X/Z selector, unknown exceptions and stall
      history. GREEN and corrupted-squash negative observed.
- [x] Per BTB bank/block use two kept native LUT gates on each of5 WADDR bits:
      address AND metadata_we, then AND not reset. All actual target writes
      imply metadata_we; keep original RADDR, WE and valid updates.
- [x] Existing independent512-entry oracle GREEN; corrupt one actual local
      WADDR bit and observe wrong-target failure. Functional identity alone
      does not prove minimum-delay improvement.
- [x] Verify complete SRAM/Cache-on traces against v6b, cycles and images.
- [x] Review complete v7 package; fresh original-FDC20min PDS started.
- [ ] Inspect actual mapping for160 native hold gates/local write fanout and
      scalar OR use. Recheck every final corner setup/hold/MPW and hashes.

## Actual v7 continuation: shared multiplier payload

- [x] v7 final647output hashes/STA: hold+0.111/+0.091ns fixed; setup-2.014ns.
- [x] Actual path is branch comparison to late MUL payload/sign/APM input;
      apply the already validated early LSU payload/real permission separation.
- [x] Parent RED, real-clock A/B capture/38checks, consumer issue/accept/E1
      capture, four sign modes, hold, cancellation and actual RA corruption.
- [x] Reconstruct v8 from full patch; complete SRAM/Cache-on images, cycles,
      profile and WB/store remain identical to v7. Ordered/IRQ PASS.
- [x] Independent source/evidence/physical binding review; fresh original
      10ns/no-region20min PDS started for v8.
- [x] Inspect v8 final actual six STA checks,485output hashes: setup-1.348ns,
      hold/MPW pass; next actual path is late pop->remaining arithmetic->FIFO CE.

## Constant occupancy enable predecode v9

- [x] Expand append/survivor enables into constant C comparisons selected by
      normalized removal0/1/2; retain original procedural priority and history.
- [x] DEPTH2/3 full-state4006/word4005, corrupt-head negative, ordered/IRQ and
      complete SRAM/Cache-on comparisons; cycles and observations unchanged.
- [x] Independent formula/source/hash/physical package review; original10ns
      no-region20min PDS started for v9.
- [ ] Inspect v9 final six STA rows, all hashes, CPU-only resources and path.
