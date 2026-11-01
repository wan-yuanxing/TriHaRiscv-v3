# 双发射 CPU 95MHz 实现

2026-11-01 用户允许小幅降低主频，以先取得实际时序通过。本轮选择 95MHz，
相对原 100MHz 降低 5%。使用 v78 的六级顺序双发射 CPU、片上 ROM/SRAM/MMIO，
不接 Cache 或 DDR。v79/v80 时序回退候选不叠加。

## 范围和约束

- 原始 v78 100MHz 结果保持：Slow setup −0.175ns，仍为 FAIL。
- 新目录 `build/cpu/dual-sram-command-95mhz-physical-20261101` 完整重新执行
  compile/synthesize/dev_map/PNR/report_timing；PNR 600 秒、外层 900 秒、seed1。
- 30 个冻结输入中，仅 `cpu_minimal_soc.fdc` 的 `create_clock` 周期
  10.000 → 10.526315789ns 改变。RTL、ROM/SRAM/ELF、I/O 延迟、hold、时钟
  uncertainty、IO register packing、multicorner 和实现选项保持一致。
- 默认工具入口仍是 100MHz；新增显式 `--clock-hz 95000000`。验证器要求频率、
  周期、冻结 FDC 一致，除周期以外的约束变动一律拒绝，并读取实际报告的周期。
  16 项工具测试通过，包含重新计算哈希后篡改 I/O 约束仍被拒绝的负例。
- v78 完整 RTL SRAM CoreMark 与轨迹复用，源文件/固件哈希一致：1,221,907 周期、
  1,448,448 observed WB、观察 IPC 1.185400、短测 4.091964/MHz，`-O2`。
  这不是官方 CoreMark 分数或新增板测。
- 同周期数线性估算的绝对短测性能：100MHz 409.196445 → 95MHz 388.736622，
  下降 5%。每 MHz 分数不用于掩盖绝对吞吐变化。

## 复用旧路由的诊断

先验证了 PDS `report_timing -input_db_file`。工具实际导入原 routed ADF 后
保留其 10ns 时钟；项目新 FDC 未生效，报告仍是 100MHz/−0.175ns。周期检查器
据此拒绝本次尝试，未将算术换算或工具成功标记作为 95MHz 验收。
诊断保留在 `build/cpu/dual-v78-frequency-95-20261101`，探索脚本保存在
`build/cpu/frequency-tool-help2-20261101/rejected_recheck_route_frequency.py`。
随后采用上面的全新 95MHz 实现。

## 最终结果：95MHz 通过

新 compile/synthesize/dev_map 已完成。CPU-only 9,719 LUT / 4,975 FF / 752 RAM-LUT
（已计入 LUT）/ 4 APM / 0 DRM，排除 SRAM/MMIO 夹具。对 v78 原 100MHz 映射为
−137 LUT、FF 不变；这不是时序收益。

完整 PDS 用时 333.059 秒，compile/synthesize/dev_map/PNR/report_timing 五阶段
全部成功，原生退出 0。主详细布线 216 次迭代到 0 未布通网络。

| 检查 | Slow/ns | Fast/ns |
|---|---:|---:|
| Setup | **+0.438** | +3.165 |
| Hold | +0.013 | **0.000** |
| 最小脉宽 | +3.918 | +4.465 |

全部 corner 违例数为 0；报告声明 All Constraints Met，performance slack 与
最差 setup 均为 +0.438ns，Recovery/Removal 也无违例。Fast hold 按报告为
0.000ns，仅表示工具判定通过，不能称为有正余量。

PDS 将请求的 10.526315789ns 量化为实际 **10.5260ns**，报告频率
**95.0029MHz**，略严于名义 95MHz。本轮最初验收器的 0.0001ns 容差拒绝了这
0.000315789ns 差异，原 `result.json` 保留 `FAIL`/退出 1，不覆盖原始记录。
随后修正报告解析器：仅接受与请求周期按 1ps 量化一致的实际周期，并同时核对
波形、performance 中的频率/周期和六项时序，不再只匹配写死的 100MHz。
新增量化/伪造频率/缺失参数拒绝测试和原 100MHz 解析回归均通过。

独立终态核验保存在 `build/cpu/dual-v78-95mhz-final-audit-20261101`，结论为
`95MHZ_TIMING_PASS`：30 个冻结输入、524 个运行输出、原执行器工具快照、
v78 全部旧输出和原仿真 122 个输出哈希均验证。当前报告解析器读取旧 v78
100MHz 报告仍得到 −0.175ns/FAIL；100MHz 不会因此改称通过。

最差 setup 是 SRAM→B 路 ALU `result_q[24]`，余量 +0.438ns，详见原报告。
新映射和布局有变化，不能将相对旧 v78 的余量变化全部归因为放宽周期。
95MHz 通过后本轮停止，不继续扫描更高频率或重复 PNR。

本轮验收边界是外部供给时钟的 CPU+ROM/SRAM/MMIO；未生成或下载板卡镜像。
后续板级 PLL、UART 分频和固件时钟常量应统一配置为实际频率后再做长跑测量。

证据：[dualissue_95mhz.json](../verification/cpu/dualissue_95mhz.json)。
原始报告：[triha_minimal_soc.rtr](../../build/cpu/dual-sram-command-95mhz-physical-20261101/report_timing/triha_minimal_soc.rtr)。

复现入口：

```powershell
python scripts/cpu/prepare_dual_physical.py build/cpu/dual-sram/coremark-20261027T075648276873Z build/cpu/NEW_95MHZ_RUN --io-registers --clock-hz 95000000
pwsh -NoProfile -File scripts/cpu/run_dual_route.ps1 -PreparedDirectory build/cpu/NEW_95MHZ_RUN -Execute
```

`NEW_95MHZ_RUN` 必须是全新目录；已有完成记录不可覆盖，不重复本轮 PNR。
