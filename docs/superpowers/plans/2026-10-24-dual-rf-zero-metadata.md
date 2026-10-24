# Retain architectural register zero metadata at writeback

> Execute inline with superpowers:executing-plans, test-driven-development and requesting-code-review in the existing isolated worktree.

**Goal:** Remove the actual v27 source_q -> wide RF bank mux -> zero reduction -> branch-pair/FIFO CE path while preserving six stages, all cycles and >4 SRAM short estimate.

**Architecture:** In the native dual RF, store31 scalar `zero_q` bits beside the existing per-word written/source state. Synchronous reset sets each flag1. The exact existing rd0-before-rd1 priority captures `(rd_value_i==32'b0)` at the same edge; unknown destinations skip exactly as before. Reads default1 for x0/unknown addresses and read the scalar for known nonzero indices. Reset-reachable invariant: an unwritten register's flag is1; full data RF read remains unchanged. This moves a pure reduction to an existing producer boundary, following the already-used prepared-scalar scheme. Four scalar outputs feed only the existing `forward_raw_zero` RF fallback; all producer priority, data forwarding, branch execution, tags, hazards and issue gates stay unchanged. Single/vendor modes derive scalar outputs directly from their unchanged data outputs.

**Inputs:** v27 exact source manifest; original10ns/IO/hold/multicorner and existing IO packing. Do not combine untested FIFO enable schemes. No production/integration/board/serial changes.

**Files:** New `tb/cpu/tb_regfile_zero_metadata.v`; candidate `build/cpu/dual-rf-zero-metadata-reconstructed-v28/rtl/cpu/{triha_regfile.v,triha_issue.v}`; full22-source patch/manifest/evidence under `docs/verification/cpu/dualissue_rf_zero_metadata*`.

- [x] Write independent architectural RF oracle with synchronous reset, rd0 collision priority, all four reads, all addresses, x0, X/Z addresses, partial-X/Z data, idle/hold and reset-X. Compare full128bit data plus4zero bits before/after edges; run against parent to observe missing new scalar interface. Add actual zero-state corruption negative.
- [x] Add four output ports. Within `g_dual_native.g_live`, use the exact existing reset/write branches to update `zero_q[register_index]` to1/on-reset or the selected write data's equality-to-zero. Read defaults1 with known-index procedural guards. Native single/vendor fallback equals original full data==0. Connect all actual lower/upper/dual/single-parallel RF instances; replace only four `forward_raw_zero` RF arguments. Preserve fallback for nonparallel configuration.
- [x] Run new oracle positive/negative, parent independent storage check, existing exhaustive prepared-zero forward/selector oracle in dual/single and its negative, pending/branch checks with coherent RF or bypass stimulus. Fresh ordered/IRQ and full SRAM/Cache-on images/WB/store/profile must match parent exactly. Forced raw metadata tests do not replace natural full-core alignment.
- [x] Freeze same measured source/ELF in private IO-only original100MHz20min/1500s physical package; independently review source/reset/Xdata semantics and all evidence hashes. Launch separate PDS only after review.
- [x] Confirm native flags actually retained/drive actual zero selection and wide bank data no longer feeds RF fallback scalar cone. Check CPU-only area and complete final six corner STA/performance consistency plus frozen input/output/actual exit hashes. All must pass with >4 on this candidate; otherwise continue from the real worst path.

Independent source/terminal/package review passed. Original10ns/noRegion20min PDS launched privately; actual topology and final six STA pending. Same short4.030288 SRAM and3.084289 Cache-on estimates/complete streams/profile preserved.

Physical terminal rechecked: native0/verification2, Slow/Fast setup -1.249/+2.851ns, hold +.110/+.099ns, MPW +3.655/+4.202ns. u_core8775LUT/4222FF/752RAM-LUT(included)/4APM/0DRM. All frozen input/output/actual-exit/helper/stage marks verified. Actual31 metadata FF retained; full effective native cone audit still being completed. Worst is now fetch1 opcode4 -> branch class -> LSU payload -> load/address/store format -> mem_data_wr,9levels logic1.405/route9.490ns. No timing closure; v27 remains better.

Independent effective native cone audit completed: all four forward-zero outputs use31zero_q/31written_q and known-address qualification; no source_q or RF RAM DO drivers remain. Actual WB reduction reuses existing WB scalar. The40FF delta is31metadata+9additional index copies. Complete audit is hash-bound in the evidence JSON.
