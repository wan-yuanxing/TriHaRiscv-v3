# Dual fetch queue experiment (2026-10-24)

Six-word fixed-entry candidate reaches **4.088695 CoreMark/MHz** in the actual
32KiB synchronous SRAM RTL model, GCC15.2 **-O2**, five iterations. Removing
the passive observer reproduces the same1,222,884cycles. **Actual100MHz
postroute acceptance remains pending.** This is not an official or board score.

| Actual loaded-program boundary | Four words | Six words | Short CoreMark/MHz, six words |
|---|---:|---:|---:|
|8KiB ROM/32KiB SRAM/MMIO|1,253,888cycles|1,222,884cycles|4.088695|
|Modeled AXI DDR, I/D Cache on|1,624,274cycles|1,604,946cycles|3.115370|

SRAM saves31,004cycles; throughput increases2.535318%. Measured WB observations
remain1,448,448 and stores70,839; WB observation IPC is1.184452, not architectural
`minstret`. The Cache-on comparison uses the same DDR model and Cache geometry.
DDR Cache-off is excluded.

The initial four-word run observed361315 cycles of response backpressure,
303185 while consuming words. Fixed destination writes first replace dynamic
multi-write compaction without changing capacity, state or benchmark cycles.
An independent six-word candidate then changes just the two decode FIFO depth
parameters. It retains conservative count-based accept; there is no new late
issue-to-fetch combinational ready path or main pipeline stage.

Each destination selects only its own, next or second-next old word. B-only
consumption preserves head0. Input append uses remaining count and has priority.
PC/data/fault/CSR metadata move together; inactive history and flush behavior
remain intact. The complete-state oracle freezes the old compact implementation;
it is supplemented by an independent ordered-word model. Four-state tests cover
pop/pred/push/flush and payload X. Equivalence is for reset-reachable state:
forcing count unknown/out-of-range does not preserve the old loop's recovery.

Both capacities pass4006 full-state checks and4005 independent word-stream
checks. Actual decode EXTRA=0/1 six-word capacity checks pass, with parent RED
and corrupt payload negatives. Ordered single/dual execution, stores, synchronous
exceptions and IRQ self-checks pass. IRQ is not an exact golden/candidate stream
comparison. Whole benchmark images match; only the verified initial cycle CSR
read and corresponding `started` store need normalization. The remaining
1,448,447 WB and70,838 store events match exactly for both memory boundaries.

Independent review verified source manifests/patch reconstruction, actual runs,
traces and the physical package. Fresh original10ns/IO/hold/multicorner PDS is
running under `build/cpu/dual-fifo-six-physical-v6b`, PNR20min/outer1500s,
no compact region. CPU-only resources for this candidate are pending. Previous
LSU preparation's -1.692ns/9965LUT cannot be used as this candidate's result.

[Bound evidence](dualissue_fetch_queue.json) includes exact run directories,
hashes, measurements, coverage limits and physical admission state. Production
CPU RTL, SoC integration, board and serial state remain unchanged.
