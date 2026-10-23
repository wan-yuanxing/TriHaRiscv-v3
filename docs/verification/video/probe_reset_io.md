# Video probe 复位释放和 I/O 输出寄存器

2026-10-23继续原125MHz收敛工作，基线为`ab63ea6`。本批只改组件验证外壳
及其生成/测试文件，没有更改`rtl/video/`产品RTL、CPU/NPU、ABI或当前板卡。
这不构成SoC复位架构交付、产品CDC单域复位恢复证明或板测。

原布局最差slow core setup为−2.102ns，路径由扫描输出FF到`core_scan_o`，
估计连线3.498ns；后续多条外部reset输入到产品CE路径也有负裕量。外壳
现为每域独立两级异步断言、同步释放：外部reset拉低立即清零同步链、扫描
寄存器及DUT；释放后第二个本域上升沿NBA更新后本域reset变高，第三个沿
才能扫描/捕获。停钟域不会被另一域释放。没有新增扫描位或稳态输出拍数。

core输出加port级`syn_useioff=1`。安装PDS的`scopeattr.tcl`将其定义为
Pango可用的I/O ring寄存器属性；native综合网表已转成`PAP_IO_REGISTER=TRUE`。
器件映射日志进一步明确：

```text
Flip-Flop "core_output_q[0]/opit_0_inv" has been packed in "OFF" of IOL "core_scan_o_obuf/opit_1" success.
```

因此本批具有真实I/O FF打包证据，不能仅因属性存在就宣称时序通过。core8ns、
pixel25ns、I/O max2/min0.5ns、setup0.1/hold0.05ns、四条首级false path和
十二条稳定束6ns例外都保持，不新增reset例外、全局异步切断或虚构板级pin。

| 完整默认采显扫描组件综合 | 改前 | 改后 |
|---|---:|---:|
| LUT | 26842 | 26881 |
| FF | 44677 | 44681 |
| DRM | 69.5 | 69.5 |

综合快照只改变probe RTL/FDC/manifest及生成器；全部产品源与上一版相同。
native网表保留四个`GTP_DFF_C`，stage0的D固定1、stage1的D连接stage0，
两域CLK分别保持。没有把同步链折叠成一个触发器。

普通Python与`-O`各12项unit通过，每轮实际编译执行11个RTL场景：逐位映射
2250次检查、3个接线/优先级故障变体、真实默认DUT reset/idle、2723写/2883读
shadow字节测试、独立reset TB及4个reset故障变体。reset TB不读取同步链，
检查停钟异步断言、错相释放、两沿保持、第三沿工作、单域短脉冲及域间隔离。
stub只用于可控边界/复位测试；真实默认DUT idle单列，未冒充完整协议流量。
独立审查未发现RTL/约束问题，明确保留产品CDC单域运行中复位的覆盖限制。

旧实现已先触发`PROBE_RESET core not held/cleared`预期失败。开发过程中还
保留了两份失败：local reset命名与pixel端口冲突导致编译错误；映射测试在
两沿准备期提前发送walking-one，错误接线变体未被检测。分别修正命名和
在准备期后再发送原有逐位激励，最终全部7个有效编译故障变体被拒绝。

证据由[机器摘要](evidence/probe_reset_io.json)定位：包含ordinary/-O实际日志、
源码/工具/产物哈希、RED、综合报告、I/O打包原文、四个同步FF连接以及冻结
布局身份。新布局继续使用seed4/performance和`report_place_timing`估计连线
模型。未取得最终routed DB和完整双corner STA前，`timing_closed=false`。

两份先前的seed11 route locator仍标记running，但日志分别停在迭代31
（26908个未布通net，overlay版本）和36（30369个，static-AW版本），没有
最终routed DB/STA。仅作为当前文件状态观察，不推断进程退出原因，也不把
旧running值当作当前确实仍执行。原数据库/源/locator均未改写。

同seed4/performance、原预算的布局测量已完成：
`build/video/probe_reset_io_place/20261023T015604_685417Z`。采用
`report_place_timing`估计连线，不能替代routed STA。

| 检查 | F4c5e改前 | 本批改后 |
|---|---:|---:|
| slow core setup | −2.102 ns | −1.720 ns |
| slow pixel setup | +0.295 ns | +1.896 ns |
| fast core setup | −1.565 ns | −0.869 ns |
| slow core hold | −0.027 ns | −0.027 ns |
| slow core recovery | +0.785 ns | +2.074 ns |
| slow core removal | +0.338 ns | +0.397 ns |

slow core setup改善0.382ns，负裕量端点11454→1167、TNS−4265.597→−409.002ns。
slow hold最差值没有改善，失败端点反而2→6、THS−0.035→−0.143ns；不以
setup改善掩盖hold仍失败。所有双corner、五类检查均留存于机器摘要和原报告。

最差setup已转到产品`u_display/u_mmio/u_guard/lane[3]`→`lane[1]/CE`，9级，
lane[3]扇出1030，估计连线7.567ns占约81%。因此扫描输出问题已移出最差
路径，但产品显示记录校验仍需拆分动态lane选择和错误判定。下一批先对该
真实内部路径做流水/共享运算验证，再启动新版本完整route，避免把本批
负裕量布局或旧版未完成route冒充125MHz签核。

证据收集脚本的独立审查还补齐了快照/当前源码/仿真之间的绑定、布局输入与
工具及报告哈希、unit源码/Python锁定。ordinary/-O在补齐后重新封存。前后
原始快照保持字节哈希；基线Git核对仅对既有`video_display_mmio.sv`记录了
CRLF→LF差异，没有放宽硬件内容比较。collector定稿后重新生成机器摘要，
不能以先前保存摘要中的旧collector哈希交付。
