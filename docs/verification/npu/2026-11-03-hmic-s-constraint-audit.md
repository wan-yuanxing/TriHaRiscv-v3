# HMIC_S 三项集成约束核查

2026-11-03 18:13（Asia/Shanghai）。依据用户提供的官方
[HMIC_S IP User Guide UG042003 V1.14](https://www.pangomicro.com/en/uploads/17503246_1729499157.pdf)
印刷页62–64（PDF页63–65）核查。表2-1包含PG2L100H/FBG676。
工程实际使用PDS 2022.2-SP6.4、Logos2 HMIC_S1.10；以该实例的哈希锁定生成文件作为逐项比较基准。

结果：三项集成检查通过，不构成整机时序或板级电气验收。

| 检查 | 实际证据与结果 |
| --- | --- |
| 优先布线RCF | 原始`pnr/ddr3_test.rcf`两条规则仅重定位层级；正式文件及已布线副本一致。实际日志逐条执行成功，并记录`Rcf routing step 1 processed 2 nets`。不是仅检查文件存在。 |
| FDC时钟和内部位置 | 六条派生时钟、两条厂商multicycle、四条0.4ns uncertainty、四条厂商时钟分组，共16条命令与原始生成文件一致。ref_clk为8ns；最终报告中DDR相关时钟均存在。CPD及两个gate的最终物理位置与原始位置一致，gate采用映射后PCF表达。 |
| 综合器格式 | `build.tcl`与`synth.log`均确认`synthesize -ads`，日志记录成功；当前采用原始ADS命名方式，无OEM格式混用。 |

最终物理位置：

- CPD：`DDRPHY_CPD_369_466`。
- gate[0]：`CLMA_357_354 FF3`。
- gate[1]：`CLMA_357_660 FF3`。

507条有效DDR/参考时钟引脚属性与原始板卡FDC一致。需单列版本差异：原始板卡
HMIC_S1.10约束中的数据/差分电平为HSTL15_I/HSTL15D_I，V1.14通用说明列出SSTL。
本次确认来源和继承关系，不声明两者电气等价；板级验收前仍须核实生成PAD、终端与VREF
实际配置。未将新手册通用示例直接替换旧版实例配置，未改RTL、频率或任何约束。

已完成首版route的DDR bank相关时钟对在慢/快角setup、hold均通过，最窄setup为+0.034ns。
125MHz应用域-0.933ns最差路径属于显示guard；100MHz计算域为-0.716ns，另有3条像素域
SRB时钟路径未达到200ps额外hold阈值。因此不能据此忽略违例或超频。

证据：

- `build/video/hmic_s_audit_20261103_checked/result.json`：输入哈希、逐项断言、最终位置和DDR时钟对数值。
- 同目录`routed_phy.pcf`与`locations.log`：直接读取已布线数据库，未重新布线。
- 同目录`clock_summary.txt`：最终时钟命中证据。
- `build/video/pds/face_first_box_route_20261103/build.log`：RCF执行及网络处理记录。
- `build/video/pds/20261103T085038_859482Z/synth.log`：ADS实际执行记录。
- 手册SHA256：`2e51af026135aa26a4677259ff971c207da4ce5d107b76e64dac6bf105d5e368`。

本核查针对已完成的首版布线；当前源约束与其冻结副本一致。后续新布局布线仍须重新验证
时钟、匹配、gate sites及全部慢快角时序，不能复用本结果宣称新候选闭合。

## 补充：厂商包内例程的综合与最终布线报告

针对“例程似乎也不能通过时序”，直接从原始`2_9_ddr3_test.rar`核对保存的报告。
报告所属工程为包内`ipcore/ddr3_test/pnr`的`test_ddr`，不是本次重新运行的结果，
也不能代替用户另一个例程工程或当前整机的验收。压缩包SHA256为
`2d5a28f5a32e694a88e91f80acdfb117ba0bf5c41a64b5f7c3726ae67c7bb6cf`；8个提取文件哈希全部复核一致。

| 阶段 | 最差setup | 最差hold | 结论 |
| --- | --- | --- | --- |
| 综合，慢角 | +2.213 ns | -0.805 ns，53个失败端点 | `Some Constraints Violated` |
| 最终布线，慢角 | +0.932 ns | +0.139 ns | 所有已报告检查零失败 |
| 最终布线，快角 | +3.218 ns | +0.102 ns | 所有已报告检查零失败 |

最终报告日期为2025-01-06 16:23:10，PDS 2022.2-SP6.4 build146967，器件
PG2L100H/-6/FBG676。慢/快角recovery、removal、pulse也均零失败；综合报告的快角
表为空，不将空表计为通过。DDR bank相关时钟对最小hold为+0.109 ns，区别于全局+0.102 ns。

原始PDS工程第519行开启`fix_hold_violation`；PRR第15、17行和route日志确认实际执行hold
修复，最终日志第882行记录第119轮零未布线，第976行记录成功。最终RTR第53行为
`All Constraints Met`。这说明该历史例程的综合hold违例经物理实现后消除，不能将综合
违例直接认定为最终失败，也不能将尚未修复的最终违例当作可忽略项。

最终报告仍有112条外部I/O未约束警告；通过结论仅适用于报告覆盖的约束，不代表完整板级
电气验收。未新跑例程、未改RTL或约束、未下载；当前主工程仍未物理时序闭合。

原始报告、`extraction.json`、只读核验脚本`summarize.py`及机器摘要`result.json`保存于
`build/video/vendor_ddr_timing_audit_20261103/`。当前无PDS/Python/ModelSim活动运行，
台账`active_runs`为空；下一工程步骤仍为已定位的CPU响应至CSR数据选择路径审查。
