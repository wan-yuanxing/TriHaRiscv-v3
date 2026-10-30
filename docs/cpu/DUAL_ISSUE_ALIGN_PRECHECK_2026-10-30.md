# 分支目标对齐预判定 v80

从 v78 独立派生；未叠加 v79 FIFO 改动。只修改隔离候选的
`triha_issue.v`：条件分支、JAL、JALR 的目标低位先分别判定，再由原指令类型
优先级选择一位标量。issue fault 判定在方向为 1 时消费该标量，方向为 0
时不产生 fault，方向为 X/Z 时保留原 `taken && next_pc[1:0]!=0` 表达式。
JALR 的 bit0 清零语义、next-PC/预测比较、resolve/stall/flush/CSR 优先级和
流水周期保持一致。`pipe_ctrl` 的另一条对齐消费者保留。

候选位于 `build/cpu/dual-align-precheck-v80/rtl/cpu`；默认 RTL、集成主工程和
板卡未修改。完整可重建 patch/manifest 位于 `docs/verification/cpu/dualissue_align_precheck*`。
初次重建检查发现 Windows CRLF 和末行无换行的包装问题；已按原字节生成 patch，
第三个独立重建目录全部 22 个源文件哈希一致。此修正只影响 provenance 文件，
实际完成仿真的 CPU 源字节不变；仿真目录保留运行当时的 manifest 快照。

## 已完成验证

- 定向/随机四态分支及实际 issue fault/recovery 表达式对父版 28,005 次检查通过；
  包含非 taken 未对齐目标、JALR bit0/bit1、X/Z 方向和 stall/flush/CSR 门控。
  next-PC 低位污染使旧版失败，新候选通过；真实 alignment 标量破坏负例检出。
- ordered 和 IRQ/mret 单、双发射全部通过。整核恢复组件还覆盖延迟 load、
  恢复与旧 load 完成重叠、错误路径 store、A/B 未对齐异常、link 写回抑制和
  既有 CSR 载荷；这只是保留既有 mtval 行为，不宣称修复其 ISA 语义。
- 完整 SRAM CoreMark `-O2` 仍为 1,221,907 周期、1,448,448 observed WB，
  observed IPC 1.185400、短测 4.091964 CoreMark/MHz；CRC、profile、完整 WB/store
  轨迹与 v78 相同。这是 RTL 短测，非官方分数或板测。
- 新 native compile/synthesize/dev_map 通过，实际配置仍是六级、双发射、
  512 BTB/512 BHT/4 RAS、GShare=0。CPU-only 9,588 LUT / 4,976 FF / 752 RAM-LUT
  （已含在 LUT）/ 4 APM / 0 DRM，排除 SRAM/MMIO 夹具。对 v78 为 −268 LUT/+1 FF；
  RTL 没有新增状态，综合合并改变了实际 FF 计数。
- 实际网表的两路六个目标对齐标量仅依赖对应目标低位。JALR bit1 被综合为
  `register_misaligned_w`，按厂商 LUT/CARRY 真值逐一核验 16 个低位加法组合。
  实际 `mispredicted_r` 控制锥消费全部六个标量且不再经过 next-PC 低位选择；
  graph 注入晚路径/断开标量两个负例均 HOLD。该结论是结构检查，不是 STA。
- 原 BTB 256 个 WE/624 个 RAM 地址/80 个两级边界、16 个动态 SRAM CE、
  两路 64 个条件目标 FF 和 60 个 carry 纯 sum 边界均通过；原六个预测比较器
  仍被 recovery 消费。JALR 比较器的 bit1 cut 使用上面已证明的实际 sum 名称。

## 物理实现

本轮单次 fresh PNR 为 `build/cpu/dual-align-precheck-io-physical-v80`。
原 10ns、IO、hold、multicorner、seed1 和 IO register packing 不变；PNR 600 秒、
外层 900 秒。重新执行 compile/synthesize/dev_map/place/route/report_timing，
不导入旧数据库，不扫描 seed。

## 最终结果：不采用

完整 PDS 用时 363.684 秒，原生退出 0，验收器退出 2，**TIMING_FAIL**。
主详细布线 189 次迭代到 0 未布通；compile/synthesize/dev_map/PNR/report_timing
五阶段均成功，30 个冻结输入及 470 个输出哈希完整核验。

| 检查 | Slow/ns | Fast/ns |
|---|---:|---:|
| Setup | **−1.112** | +2.808 |
| Hold | +0.114 | +0.105 |
| 最小脉宽 | +3.655 | +4.202 |

Slow 有 24 个 setup 违例，TNS −7.816ns；performance slack 与最差 setup
均为 −1.112ns。对同 10ns 约束的 v78 −0.175ns 回退 **0.937ns**。
这是新网表和新布局，不能把面积下降或目标对齐锥变化归因为全核频率收益。
本轮实际 route 包也重查了 alignment、六类预测比较、BTB、SRAM CE 和纯 sum
结构，全部通过；CPU-only 仍为 9,588 LUT/4,976 FF。

实际最差路径：B 路 E1 目的标签 bit4 → 与取指源索引比较 → 旁路/配对许可 →
`fetch1_accept` → FIFO 更新选择 → `head1_q_copy[37] D`。
11 级，logic 1.416ns、route 9.444ns（86.961%）；`fetch1_accept` 实际扇出 239，
FIFO 内后续节点扇出 115/116。不能只靠减少 LUT 或再拆一次对齐表达式预测收敛。

24 条失败路径全部落在 FIFO 头部：10 条来自 E1 目的标签，14 条来自 A 路
分支方向/fault。后一组代表路径为物理 `operand_ra_e1_q[30]`，但实际逻辑网络
是 `pipe0_operand_ra_e1_w[29]`，经 `fault0_w`、`N15`、`fetch0_accept` 到头部，
该组最差 −0.775ns。目标低位预判定消除了方向后的低位选择，但方向本身仍须
门控 fault，仍与同周期 FIFO 更新相连。

**v80 不提升默认 RTL，不作为优于 v78 的基线，不重复本候选 PNR。100MHz 仍未通过。**
保留 v78 近期物理基线和历史 v57 −0.009ns（同样 FAIL）。下一步应先从 v78
分析 issue accept/dequeue 到 FIFO 更新的真实时序边界，评估解耦及吞吐代价，
再决定实现方式；不能据此回退成单发射或放宽约束。以本次 1,221,907 周期计，
短测保持 >4/MHz 的周期上限为 1,249,999，额外周期预算约 2.30%，需要实测。
下一候选尚未实现或启动。

原始报告：[triha_minimal_soc.rtr](../../build/cpu/dual-align-precheck-io-physical-v80/report_timing/triha_minimal_soc.rtr)。
完整证据：[dualissue_align_precheck.json](../verification/cpu/dualissue_align_precheck.json)。
