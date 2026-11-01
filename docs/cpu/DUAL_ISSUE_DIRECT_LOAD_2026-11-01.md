# 双发射 v81：B 路直接加载前递

95MHz 的 v78 完整版本已经保留，Git 标签为
`cpu-dual-sram-95mhz-20261101`，另有 534 文件的完整冻结运行归档。
归档 SHA256 为 `f5480495ec71eb680aff55ea953a631a0301cc3cc214395654493035e8db53d8`。
见[保留记录](../verification/cpu/dualissue_95mhz_preserved.json)。

本轮从 v78 独立派生，目标为原 100MHz，不叠加 v79/v80，不改变流水级或停顿。
边界仍为六级顺序双发射、8KiB ROM/32KiB SRAM/MMIO、外部时钟；不接 Cache/DDR。
所有修改留在独立 CPU 工作树的可重建候选中，主工程和板卡配置不变。

## 改动和验证

95MHz 实际最差路径为 SRAM 返回，经 LSU 格式化、共享 E2 结果选择、B 路操作数
选择进入 ALU，setup +0.438ns。本轮在两路 pipe 控制器中导出原来的 memory
选择条件与独立非 memory 结果，将 B 的 ra/rb memory 数据直接展开到最终旁路
选择。A 路、原共享 E2 输出和全部发射/异常/提交控制不变。

仅修改候选 `triha_issue.v` 和 `triha_pipe_ctrl.v`。保留原过程式标签覆盖顺序、
x0 最终覆盖和 X/Z 数据语义，没有新增 RTL 状态。补丁与 22 个源文件哈希可独立
重建，见 `docs/verification/cpu/dualissue_direct_load_forward_sources.json`。

已完成验证：

- 抽取真实 B 操作数及 E2 表达式，四种 LOAD/MUL bypass 配置各 33,794 项检查。
  覆盖 64 个标签命中组合、x0、未知标签、控制优先级和 X/Z 载荷。
- 污染共享 E2 数据时旧实现按预期失败，候选 33,795 项通过；真正破坏输出 bit0
  的负例仍被检出。
- ordered、IRQ/mret 单/双模式、真实 E1 recovery、LSU 组件和实际指令程序通过。
- 完整 `-O2` SRAM CoreMark：1,221,907 cycles、1,448,448 observed WB，
  observed IPC 1.1853995435，短测 CoreMark/MHz 4.0919644457。
  CRC 为 e9f5/e714/1fd7/8e3a。完整 WB/store、ROM/SRAM、profile 与 v78 相同。
  这是 RTL 短测，尚无新增板测或官方分数。
- 新鲜证据审计逐一核验 8 组运行的 374 个输出、输入及工具/来源哈希；
  同时核验保留的 95MHz 归档 SHA256。

## 实际映射

原生 compile/synthesize/dev_map 通过。CPU-only 为
**9736 LUT / 4977 FF / 752 RAM-LUT（已含于 LUT）/ 4 APM / 0 DRM**，
不计 SRAM/MMIO 夹具。对 v78 原 100MHz 9856/4975 为 −120 LUT/+2 FF；
RTL 没有新增状态，工具映射的复制可改变 FF 数，不把面积变化当时序收益。

实际 ADS 网表 B ra/rb 的 64 位全部消费对应 memory 数据位，检测到的 shared E2
数据依赖为 0，未知图节点为 0。注入旧依赖和断开 memory 数据的两个负例均 HOLD；
旧 v78 有 60 位 shared E2 依赖，检查器也 HOLD。

RF 实际输出端口和 early-multiply 实际接口作为组件边界，另检查 RF 输入没有
shared E2 数据。这是连线检查，不证明完整 RF 语义，也不能替代 STA。
早期保守检查的 HOLD 记录全部保留。此前分支预比较、完整地址结果、BTB 块内写许可
和 SRAM CE 结构门槛均通过。

## 100MHz 物理验收

运行目录：`build/cpu/dual-direct-load-io-physical-v81`。
原 10ns/IO/hold/multicorner、seed1，PNR 600 秒、完整外层 900 秒。
完整新 compile/synthesize/dev_map/place/route，无旧数据库导入。
PDS 与集成侧使用独立工作目录和私有 TEMP，不停止其他任务。

本次 route 的重新综合网表也已单独检查：B ra/rb 全 64 位 PASS，
shared E2 data hits 0、unknown 0，CPU-only 仍为 9736 LUT/4977 FF。

## 终态：100MHz 未通过，不采用 v81

完整 PDS 用时 408.227 秒，五阶段全部成功、原生退出 0；验收器退出 2。
主详细布线第 153 次迭代达到 0 条未布通网络，随后完成 hold 修复。
独立核验 30 个冻结输入、398 个输出、执行工具快照和实际报告，source unchanged。

| 检查 | Slow/ns | Fast/ns |
|---|---:|---:|
| Setup | **−0.951** | +2.676 |
| Hold | +0.053 | +0.024 |
| 最小脉宽 | +3.655 | +4.202 |

实际周期 10.0000ns、100.0000MHz；performance slack 与最差 setup 一致。
357 个 Slow setup 端点违例，TNS −80.809ns。相对 v78 同 10ns 的 −0.175ns
回退 0.776ns；这是新网表/新布局的整体结果。局部数据路径连线变短并未带来
全核收敛，不能用面积下降或局部连接检查替代时序。

实际最差路径从 FIFO `head0_q[23]`（opcode bit3）出发，经过源寄存器使用角色
译码、pending producer 许可、fetch0_accept，返回 FIFO `head0_q_copy[43]`。
共 9 级，logic 1.592ns、route 8.961ns（84.914%）；accept 扇出 130、后续头部
选择网络扇出 201。新瓶颈为队头到发射许可再到队头的组合控制环。

保留 v81 失败记录及功能证据，不提升默认 RTL，不重跑 v81 或扫描 seed。
已通过的 95MHz v78 完整归档不变。下一步先分析在原队列采样点预存源寄存器
使用角色，或带吞吐量核算的弹性出队边界；不引入全局 load-return 等待级。

终态证据：[dualissue_direct_load_forward.json](../verification/cpu/dualissue_direct_load_forward.json)。
实际报告：[triha_minimal_soc.rtr](../../build/cpu/dual-direct-load-io-physical-v81/report_timing/triha_minimal_soc.rtr)。
