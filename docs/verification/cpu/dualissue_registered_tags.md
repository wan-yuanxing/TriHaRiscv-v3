# Registered destination tag diagnostic

The v12 final path launches pipe1 WB opcode bit7. Actual N618_2/N618_5 LUTs
combine the destination index with valid_wb/ctrl_wb RD_VALID before comparing
it with the source index. This is upstream of bypass data selection and branch
pairing. The diagnostic carries the already qualified five-bit destination
beside each unchanged E1/E2/WB control/opcode state. No stage, instruction
latency, commit rule or branch policy is added or changed.

E1 masks at exactly the original issue capture. E2 retains original reset,
hold, squash and procedural IRQ-before-frontend-fault priority. At WB each
special memory-fault valid-clear case is nonzero and also clears RD_VALID;
the original procedural reduction gate therefore covers these cases. A
reduction of X follows the original case/default and if/else semantics.
Original opcode/control/valid and architectural commit outputs are unchanged.

The clocked checker compares new tags against the exact old expressions over
original unchanged stage state after each edge and late completion toggle.
It covers randomized faults/IRQ/reset/hold/flush and X/Z inputs, without
forcing internal metadata. Both original and new implementations pass40003
checks with10948/8770/8020 live E1/E2/WB samples. Output corruption fails at
sample4. This is a behavior-preserving refactor; no functional RED is claimed.
An initial declaration-order compile failure is excluded from functional
coverage. Randomized checks do not establish exhaustive fault or overlap
coverage, and arbitrary forced metadata/pre-reset operation is excluded.
Independent review also derives the three stage invariants from source.

v14 combined this with the exact FIFO enable predecode; full SRAM and Cache
images/traces/cycles/profile match v13. Its physical package stays unexecuted:
v13's measured setup-2.659ns is worse than v12-1.276ns. v14b restores exact
v12 FIFO bytes and keeps the same reviewed registered-tag source. Relative
to v12, only triha_pipe_ctrl.v changes. Fresh40003tag/6166pair, ordered and
IRQ checks pass. Fresh loaded images, complete1448448WB/70839store per mode,
measurement and SRAM profile match v12 exactly.

SRAM remains1240606cycles/4.030288 CoreMark/MHz, observed WB IPC1.167533;
Cache-on DDR model1621119cycles/3.084289MHz. GCC15.2-O2, five iterations;
these are RTL estimates, not official or board results. WB observation IPC
is not architectural minstret. CPU-only area and actual100MHz remain pending.

[Combined v14 evidence](dualissue_registered_tags.json),
[v14b source binding](dualissue_registered_tags_simple_sources.json).
