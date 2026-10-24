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
- [ ] Extend `tb/cpu/tb_fifo_cross_pair.v` with parameterized capacity and
      unknown pop/pred coverage; run the original4word parent oracle.
- [ ] Add a separate same-capacity reference comparison test: unchanged
      inactive slots, reset, flush and every sideband. Preserve corrupt negative.
- [ ] Create `build/cpu/dual-fifo-entry-v6/rtl/cpu` from selected v5b; modify
      only `triha_decode.v` compact storage. Keep immutable parent snapshot.
- [ ] Verify fixed-entry candidate against both oracles and full ordered/IRQ,
      SRAM and Cache-on runs. Freeze a full-base patch and source manifest.
- [ ] Create a separate6word depth candidate, change both decode FIFO
      instantiations explicitly to `.DEPTH(3)`; count is already3bits.
- [ ] Run capacity6 expectation on old parent to demonstrate RED; run new
      GREEN and corrupt metadata negative. Extend passive occupancy to8words.
- [ ] Measure actualSRAM-O2 and Cache-on, compare complete normalized
      WB/store streams. Reject if no benefit or if functional contract fails.
- [ ] Evaluate v5b terminal actual STA; choose the measured reviewed FIFO
      candidate for fresh no-region20min original-FDC PDS.
- [ ] Verify all frozen inputs/output hashes and actual Slow/Fast six timing
      checks, performance consistency and CPU-only synth resources.
- [ ] Record actual results, commit narrowly; no target admission until the
      same physical candidate exceeds4/MHz and passes100MHz.
