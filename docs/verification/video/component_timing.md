# F4c5b Video 组件综合时序基线

本批只修改 PDS 诊断入口和验证文件，没有改产品 RTL、ABI、驱动、FDC 或板卡。
CPU 交付不阻塞本批；正式 CPU/fabric/DDR/CDC 合并与物理时序仍另验。

## 可复现入口

```powershell
python -m unittest discover -s tb/video -p 'test_pds_*.py'
python -O -m unittest discover -s tb/video -p 'test_pds_*.py'
python scripts/video/build_pds.py --target video_control_decode --stage synth --synth-timing pads
python scripts/video/build_pds.py --target video_control_decode --stage synth --synth-timing component
python scripts/video/build_pds.py --target video_display_record --stage synth --synth-timing component
python scripts/video/build_pds.py --target video_record_pipeline --stage synth --synth-timing component
```

默认不传 `--synth-timing` 时仍执行原来的 `synthesize -ads`。诊断只准用于以上
三个组件的 synth 阶段；板级目标和 route/bitstream 直接拒绝。pads 显式保留
自动 I/O 缓冲；component 使用 PDS 原生 `-disable_io_insertion`。两者都设置
`-max_path 20 -nworst 1`，未指定 from/to，不筛掉 reset、I/O、CDC 或其他检查。
PDS 按时钟和检查类别分别输出路径，实际总数可以超过 20。

所有构建使用显式 manifest、新目录和源快照；原 core 8 ns、pixel 25 ns、I/O
budget、标量同步器例外和稳定束 6 ns 不变。没有添加整组异步 false path。
改变 I/O 插入方式也可能改变映射，不能把 WNS 差值全部解释为减去了 pad 延迟。

## 结果与根因

| 目标 / I/O 模式 | LUT | FF | DRM | core setup | pixel setup | 最差 hold | 最差 removal |
|---|---:|---:|---:|---:|---:|---:|---:|
| control_decode / pads | 89 | 120 | 0 | −3.676 ns | — | −1.970 ns | −0.263 ns |
| control_decode / component | 91 | 120 | 0 | +1.255 ns | — | −2.375 ns | −2.055 ns |
| display_record / component | 26491 | 35278 | 68 | +0.311 ns | +11.549 ns | −2.875 ns | −1.393 ns |
| record_pipeline / component | 34718 | 42300 | 69.5 | +0.311 ns | +11.128 ns | −3.097 ns | −1.393 ns |

同源 pipeline 探索对照的 pads 综合仍是 core −3.337 ns、pixel +11.128 ns；
最差 setup 是 `rst_ni` 输入到 `src_ready` 输出。译码器 pads 最差也是 reset
输入到 READY 输出。组件模式去掉物理缓冲后的 setup 均非负，这批未据此修改 RTL。

两个大组件的内部最紧 setup 路径相同：RAW 描述符范围检查的 APM 乘法链，经
`record_bus_end` 和状态门控到 `u_link/state_reg[*]/CE`，7 级逻辑、+0.311 ns。
这是后续 PNR 或必要流水化的具体观察点；本批没有将组合 reset 门控直接改成
寄存器，也没有改变 VALID 保持、完成快照、ACK 或退休行为。

component 的 hold/removal 仍负，故所有结果的 `timing_closed=false`。
这是单 slow corner 综合估计，fast 表为空；没有布局布线、物理 clock tree、
I/O/DDR/CDC 签核或新位流。setup 为正不代表整机 125 MHz 已闭合。

## 验证门槛

25 项相关 Python 测试普通与 `-O` 均通过；实际 CLI 拒绝错误目标/阶段。
解析器要求声明时钟、五类 slow/fast 汇总、唯一关键字段和有限数值；检查端点
数、WNS/TNS、路径与汇总及 arrival/required/slack 的一致性。所有验收用显式
异常，未使用可被 `-O` 删除的 Python assert。

常规路径按精确 launch/capture 时钟对检查。PDS 的 datapath_only 记录不输出
时钟边沿，只能检查对应 capture group 所有适用 WNS 的保守下界，逐路径标为
`capture_group_lower_bound`；不声称已检查精确 CDC 对或全部未列出的路径。
关键路径清单和五类全量汇总分别记录。

独立审查发现并复测关闭两组 P2：路径/汇总或 TNS/WNS 矛盾，以及损坏行、重复
字段、未知时钟/空 fast 表、非有限数值的解析漏洞。8 项隔离变异均被拒绝。
真实工具日志与约束检查中的 warning 全部保留；组件没有物理引脚映射，这些
warning 不能当作板级电气验证。

探索过程中 `all_registers -cell` 返回 Tcl 对象句柄，直接传给 synthesize 被
工具忽略，结果不作为寄存器筛选证据。按 VM 字符串提取的首次名单漏掉 6 个
自动编码状态 FF（114/120），同样不作为完整基线。补齐 120/120 FF、无 critical
后，译码器单独寄存器路径 setup +5.312 ns、hold +0.753 ns，128 个端点；这只是
排除了 I/O/异步检查的有限诊断，没有替代上述所有路径报告。

原始定位、哈希、约束适用情况和最终审查见
[机器证据](evidence/component_timing.json)。后续先建立可布线的内部接口边界，
再在原频率和 CDC 约束下收敛 setup/hold/removal；必要流水化须另有协议回归。
