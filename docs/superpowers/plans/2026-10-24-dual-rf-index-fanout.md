# Local read-index fanout diagnostic

> Execute inline using superpowers:executing-plans and requesting-code-review. Existing isolated worktree and user-authorized independent PDS only.

**Goal:** Test the measured v26 FIFO-head read-index routing bottleneck without changing any functional state, cycle, pipeline stage or 100MHz constraint.

**Architecture:** Alias each FIFO head's ten bits [24:15] through a wire annotated `/* synthesis syn_maxfan=16 */`, then reconstruct the original complete instruction with a concatenation. No ports or state change. This exactly preserves every output bit, including reset, flush-hold, inactive and X/Z history. PDS ADS User Guide 搂5.13 explicitly supports net attributes and driver replication. An alias may canonicalize into the original net; replication is a measured hypothesis, not assumed.

**Alternative:** If native replication does not occur or does not split RAM address load, use a separate candidate with twenty documented `syn_preserve=1` exact-history index registers. Never clear flush/idle differently to prevent merging; 搂5.15 supports identical-register retention directly.

**Files:** Candidate `build/cpu/dual-rf-index-fanout-reconstructed-v27/rtl/cpu/triha_decode.v`; full22-source patch/manifest `docs/verification/cpu/dualissue_rf_index_fanout_{diagnostic.patch,sources.json}`; evidence `dualissue_rf_index_fanout.json`; existing queue and complete SoC/Cache benches.

- [x] Verify documented attribute syntax and parent actual launch/fanout. Reconstruct v26; change only the single exact output expression below, preserving all other22-source bytes.

```verilog
wire [9:0] read_index0_w /* synthesis syn_maxfan=16 */;
wire [9:0] read_index1_w /* synthesis syn_maxfan=16 */;
assign read_index0_w=data_q[0][24:15];
assign read_index1_w=data_q[1][24:15];
assign data0_out_o={data_q[0][WIDTH/2-1:25],read_index0_w,data_q[0][14:0]};
assign data1_out_o={data_q[1][WIDTH/2-1:25],read_index1_w,data_q[1][14:0]};
```

- [x] Run existing complete151bit+18metadata oracle in MULDIV1/0 and EXTRA1, plus its corruption negative. Run fresh SRAM/CoreMark+profile and Cache-on DDR five-iteration measurements and compare complete images/WB/store/profile to v26.

```powershell
python scripts/cpu/run_dual_diagnostic.py --firmware-run build/cpu/firmware-coremark-20261023T1103533439788Z --cpu-dir build/cpu/dual-rf-index-fanout-reconstructed-v27/rtl/cpu --testbench tb/cpu/tb_decode_alu_control.v --top tb_decode_alu_control --marker ALU_META_ALIGNMENT_PASS
python scripts/cpu/run_dual_sram.py --test coremark --cpu-snapshot build/cpu/dual-rf-index-fanout-reconstructed-v27/rtl/cpu --candidate-manifest docs/verification/cpu/dualissue_rf_index_fanout_sources.json --profile
python scripts/cpu/run_cache.py --test coremark --iterations 5 --issue-mode dual --cpu-snapshot build/cpu/dual-rf-index-fanout-reconstructed-v27/rtl/cpu
```

- [x] Freeze same-source/image physical package with original10ns/IO/hold/multicorner and existing I/O packing attribute, no region; independent review all22-source identities and terminal evidence. Launch private PDS with20minute PNR/25minute outer budget and `-AllowConcurrentPds`.
- [x] Inspect native Q replication, actual read-address loads/driver fanout and u_core-only area. Verify real source/output/transport hashes, compile/synthesize/map/PNR/report marks and Slow/Fast setup/hold/MPW with consistent performance slack. All six and >4 must pass on the same candidate; otherwise continue from actual critical path. Do not touch production, integration, board or serial.

Independent source/terminal/package review passed. Original10ns/noRegion20min PDS launched privately; actual topology and final six STA pending. Same short4.030288 SRAM and3.084289 Cache-on estimates/complete streams/profile preserved.

Actual terminal: native0/verification2, all frozen input/output/transport/helper hashes rechecked. Slow/Fast setup -.792/+2.667ns, hold +.114/+.099ns, MPW +3.655/+4.202ns. CPU-only8887LUT/4182FF/752RAM-LUT(included)/4APM/0DRM.70 identical-history Q copies actually retained, every relevant Q <=16 primitive pins, all32RAM address pins per bit retained; groups mix banks and other logic. Worst path is now nativeRF source_q25 -> bank read selection -> scalar zero -> branch-pair permission -> FIFO remaining -> 117-load CE.100MHz remains unmet;6ps difference fromv26 is not material improvement.
