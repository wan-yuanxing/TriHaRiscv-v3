# Native dual register storage execution

Execute inline using existing isolated worktree and verification/review steps.

- [x] Reject v9 as timing strategy; preserve v8 baseline and all actual reports.
- [x] Review frozen two-bank/LVT reference, original FF priority/reset/read
      semantics, and installed native primitive/write-hold pattern.
- [x] Independent2W4R architectural oracle passes original FF storage.
- [x] In `build/cpu/dual-native-rf-v10/rtl/cpu/triha_regfile.v`, add local
      dual-native branch with2banks*4copies*16 RAM32X2DP,31written/31src FF.
      Keep original single and vendor-switch branches unchanged.
- [x] Implement exact known-address qualification and per-word priority0
      metadata updates; shared per-write native data/address hold gates.
- [x] Run oracle/negative, RF and issue forwarding checks, actual ordered/IRQ;
      address any real failures before performance or PDS.
- [x] Preserve full-base patch/22-source manifest, reconstruct, run actual
      SRAM/Cache-on and compare complete loaded images/streams/cycles to v8.
- [x] Independent source/evidence/physical review and fresh original10ns,
      no-region20min PDS; verify actual native RAM mapping and CPU-only area.
- [x] Final six STA rows, hashes, actual minimum delays and worst paths inspected.
      v10/v11 timing FAIL; no admission. Only same candidate above4/MHz and
      actual100MHz qualifies.
