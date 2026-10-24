# FIFO enable predecode diagnostic

v9 preserves the complete six-word FIFO state and SRAM **4.088695/MHz**,
Cache-on DDR model **3.115370/MHz**, GCC15.2-O2. All loaded images, complete
WB/store streams and measurement/profile are identical to v8. These are
short RTL estimates, not official or board scores; actual100MHz fails.

v8's measured worst path ends at FIFO entry3 clock enable after late branch
permission and remaining-count arithmetic. Let C be registered occupancy and
k the normalized removal count0/1/2. Before late pop arrives, v9 compares C
to each constant entry position. Append-low expands C-k=e into three cases;
append-high expands C-k+1=e, with entry0 high impossible. Survivor is
`C>e+2 || (C==e+2 && k<2) || (C==e+1 && k==0)`.
Arithmetic remaining is retained only in the small count-register update.

Reset/flush, removal-X normalization, low/high/survivor procedural priority,
tuple shifts and inactive history remain unchanged. This is reset-reachable
state equivalence, not arbitrary forced counter recovery. Both DEPTH2/3
pass4006 complete-state and4005 independent-word checks; corrupt head fails.
Ordered single/dual, stores, synchronous exceptions and IRQ self-checks pass.
Independent review verifies formulas, source hashes, full streams and package.

Fresh original10ns/IO/hold/multicorner no-region PDS completed at
`build/cpu/dual-fifo-enable-physical-v9`, PNR20min/outer1500s. Slow setup/hold/MPW
=-2.258/+0.109/+3.655ns; Fast=+1.645/+0.104/+4.202ns. Native0/verifier2;
849outputs verified. CPU-only10055LUT/5008FF/624RAM-LUT(included)/4APM/0DRM.
The setup regression rejects this isolated candidate as a timing strategy. Production RTL, integration and board/serial state are unchanged.

[Bound evidence](dualissue_fifo_enable.json).
