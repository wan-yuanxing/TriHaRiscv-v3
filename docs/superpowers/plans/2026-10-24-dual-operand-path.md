# Dual operand path execution

- [x] Inspect actual parent -3.015ns path and select minimal payload experiment.
- [x] B raw v1 directed RED/GREEN/broken and ordered/IRQ checks.
- [x] Reproduce actual SRAM cycles and compare full WB/store plus loaded images.
- [x] Freeze v1 sources and launch independent original-constraint PDS.
- [x] Reuse existing 2W4R ports for v2 parallel A operands; preserve single mode.
- [x] Correct dual RF unknown-index oracle to existing numeric-case zero default;
      distinguish these initial oracle failures from valid RED records.
- [x] v2 directed RED/GREEN/broken, single compatibility, ordered/IRQ checks.
- [x] Reproduce v2 SRAM cycles and full trace equality; independent review.
- [x] Verify v1 terminal output hashes and actual timing, then run v2.
- [x] Verify v2 actual timing/CPU-only synthesis resources and next real path.
- [ ] Exceed 4/MHz with same candidate passing actual 100MHz; no full acceptance yet.

## Completed routing and continuation

- [x] Verify v1 native flow completed: -4.045ns, worse than parent.
- [x] Verify v2 native flow completed: -2.654ns, improved but timing FAIL.
- [x] Split older and same-packet hazards; preserve four-state indexed-write semantics.
- [x] New packet oracle and real active permission checks (8207), corruption negative, ordered/IRQ and full SRAM trace equality.
- [x] v3b10min PNR times out during hold repair; record native1 and no final margin.
- [x] Fresh same-RTL v3b20min flow finishes: -2.212ns, native0/acceptance2.
- [x] Same v3b Cache-on DDR rerun/complete trace compare: 3.078298/MHz.
- [x] Bind existing compact physical region FDC with same RTL/firmware/original timing constraints; start 20min experiment.
- [x] Verify compact timeout/output hashes: no final STA, main detailed97/4458; reject region.
- [x] Relative word-position selection v4: directed/ordered/IRQ and full SRAM streams.
- [x] Verify v4 final original-FDC route/output hashes: setup-2.124ns, CPU-only10100LUT.
- [x] Trace actual v4 launch net ctrl_wb_q[7] (packed PC-named cell is not PC data).
- [x] v5 early LSU payload preparation, then v5b invalid-B unknown-class RED/GREEN fix.
- [x] v5b actual SRAM and Cache-on whole-stream comparisons; cycles unchanged.
- [x] v5b independent admission review; fresh no-region20min PDS started.
- [x] Inspect v5b final six STA rows and next real path: setup-1.692ns, FIFO update; original100MHz/IO/hold.
- [ ] Achieve both actual100MHz and >4/MHz; currently neither combined gate is met.
