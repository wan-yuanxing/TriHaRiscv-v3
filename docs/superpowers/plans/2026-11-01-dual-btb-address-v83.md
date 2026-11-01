# BTB Write-address Control Isolation v83

> Execute inline. Continue the authorized100MHz optimization;95MHz remains preserved. No new subagents, pipeline stages, reset-release policy, timing exceptions or board work.

**Goal:** Remove the real raw-reset/train dependency from BTB RAM WADDR, preserving actual write events and the two-step minimum-delay structure.

**Parent:** Fully measured v82 diagnostic (not an accepted100MHz baseline). It has38 raw-reset-to-BTB-address failures and3 other branch CE failures at-0.100ns. Carry its verified role predecode; no v81 change.

**Design:** For each32-row block, the first address LUT remains address-bit AND predicate, but predicate is only write_row[7:6]==block/2. The second remains first AND NOT predicate, with predicate write_row[5]!=block%2. An actual block write implies both predicates select that block, so the written low5bit address is unchanged. Inactive addresses may differ; native RAM models do not write when WE is0/X/Z. Existing metadata/tag/target WEs and valid-bit reset remain unchanged. No reset or train in the new address Boolean cone. Keep both physical LUT boundaries and verify actual mapping; a collapsed delay chain is HOLD, not permission to relax hold.

- [x] Test extracted real two-LUT chains before implementation: parent enabled-address semantics PASS; independent-control poison fails. Include a genuine enabled-address bit corruption negative.
- [x] Create a new v82-derived candidate, change only triha_btb.v, freeze full22source patch/manifest and reconstruct independently.
- [x] Run new truth-table test plus existing complete BTB/WE/four-state/alias tests against the frozen parent. Keep all WE and read ports identical.
- [x] Run ordered/IRQ/E1 recovery and one full-O2 SRAM CoreMark; quantify all cycle/profile/WB/store differences honestly.
- [x] Native compile/map: actual624 RAM WADDRs must have no raw reset/train dependency or unknown support,80 double-LUT boundaries retained; prior WE/local-tag and CPU gates pass. Negative controls must fail.

Actual mapping:9845LUT/5001FF,624 address cones isolated. ADS shares identical first stages between adjacent blocks;40 named first stages feed80 distinct two-stage outputs. The graph check binds the frozen identical-half expression and rejects a true collapsed-stage negative(79/80). Old named-boundary HOLD retained. Actual predictor invalidate is tied0 in frozen frontend; removed rst_i name is bound to actual nt_rst_ni/top reset instead. Original100MHz PNR executed once; terminal acceptance below.
- [x] Only then one fresh original100MHz/IO/hold/multicorner seed1 PNR. Actual six corner checks and full frozen hashes decide acceptance; preserve all rejected results and95MHz.

Terminal:100MHz PASS, actual10.0000ns. Setup Slow/Fast+0.307/+2.753ns, hold+0.114/+0.103ns, MPW+3.655/+4.202ns; all zero failing endpoints. Native/runner0,135 main detailed iterations to0.30 frozen inputs/362 outputs verified. Actual route remapping checked separately.1221907cycles and full traces unchanged; shortRTL4.091964/MHz, no board/official claim. Retain95MHz and freeze this accepted100MHz implementation.
