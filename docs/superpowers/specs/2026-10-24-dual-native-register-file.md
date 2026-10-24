# Native dual register storage experiment

Continue actual100MHz closure from v8, the best six-word4.088695/MHz candidate
(-1.348ns). v9 count predecode worsened layout/setup to-2.258ns and is rejected.
Repeated small control changes expose different paths across a broad FF/mux
network. Next change storage implementation, preserving six stages and all
architectural timing. No change to production/integration or toolchain.

Use the already present two-writer/two-bank live-value selection structure in
the frozen vendor register file as design reference, while reusing this
project's existing GTP_RAM32X2DP and two-LUT minimum-delay pattern. Keep the
vendor file unchanged, SUPPORT_REGFILE_XILINX=0 and existing parallel operands.
The local wrapper receives a dual-native branch; single storage stays intact.

Each write bank replicates32words*32bits for4 asynchronous read ports:
128 RAM32X2DP logical primitives total. A31bit written mask preserves zero
after synchronous reset; a31bit live-bank table records newest writer. Current
FF behavior gives port0 priority on same address, unlike the reference's
port1 priority, so per-word procedural metadata updates retain port0 priority.
Both banks may still write on a collision. No address-inequality gate on port1.

Synchronous reset changes visible RF data only at a clock edge. RAM contents
need not reset; output uses written mask, not raw reset. Exact known address
qualification preserves unknown-read default0 and unknown-write ignore.
Procedural reset normalization preserves the original if(reset) behavior
when reset is unknown. Write data X is supported; write data Z is outside
the real CPU datapath contract because native LUT hold gates convert it to X.
No equivalence claim before the first reset edge or for forced metadata X.

Two write ports each share existing two-level native hold data gates across
their four read replicas; use corresponding address hold gates too. Read-bank
selection and written qualifier remain asynchronous; no extra main stage.
Estimated saving is roughly930 FF from replacing992 data FF with62 metadata
FF, but actual LUT/RAM/FF and timing must come from native reports.

The independent architectural 2W4R oracle already passes current FF storage:
port0 collision priority, bank alternation, synchronous reset before/after edge,
unknown read/write addresses, unknown reset and data X. The candidate must pass
the same oracle and corruption negative, actual issue/bypass tests, full ordered
and IRQ, and exact SRAM/Cache-on image/stream/cycle comparisons. Then fresh
original10ns/IO/hold/multicorner no-region PDS decides physical admission.
