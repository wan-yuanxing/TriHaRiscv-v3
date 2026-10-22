# I/D Cache：独立DDR目标100MHz后布线通过

2026-10-22，父提交`4076496`。在`cpu/windows-baseline`完成独立缓存CPU/DDR板级目标的实际100MHz后布线准入，**尚未下载或板测**。机器索引为`id_cache_stage5.json`；共享fabric、其他主端可见性及物理DDR训练仍是独立门槛。

## 修复与验证

stage4的free域启动信号直接释放DDR控制器复位，综合重编码后的PHY相位调整FSM留下五个跨域recovery端点。局部复位输入through试验无效；本轮FDC设置syn_preserve也被工具明确拒绝，未采用这些诊断。

本轮在原单一差分输入缓冲之后，仅为复位释放增加参考时钟全局缓冲和两个寄存器。它们由协调epoch异步清零，在常开125MHz参考的两个边沿后释放控制器。PHY的生成时钟在复位期间可能尚未存在，因此不能用等待DDR生成时钟的方式形成启动依赖环。CPU/Cache/CDC/桥仍参加同一协调断言，各域原有同步释放保持不变。

与此同时删除旧模板的ref_clk整域异步分组，让参考到派生DDR时钟的recovery/removal真正被检查；只新增free域到这两个异步释放寄存器C引脚的局部例外，未增加参考时钟到DDR的豁免。最终报告实际检查34个ref→DDR复位端点，两corner recovery+2.077/+4.838ns、removal+1.815/+0.480ns。综合网表明确保留两只GTP_DFF_C：相同参考时钟/清零/INIT0，第一级D=1、第二级D=第一级Q；最终ref_clk负载数2。

先增强测试台，旧版真实失败于`unsynchronized controller reset release`，再实施修复。最新O2固件和完整CPU在数字PLL/DDR替身下两次自检通过，各覆盖私有/共享8KiB和代码修改/FENCE.I；E0/E1/E4/E5故障监测通过，数据损坏被真实CPU store异常拒绝，宿主返回1。周期含UART和启动，不能当作CoreMark。CPU/Cache全部RTL与stage4输入哈希相同，未调整发射宽度、主流水级、预测器、编译优化或ISA功能。

## 实际时序

新执行完整compile/synthesize/dev_map/place/route/report_timing，无旧布局/路由导入。100MHz、CPU IO max2/min0.5ns、setup/hold uncertainty和多corner要求保持，实际PLL125→100MHz/HIGH带宽不变。PDS原生返回0；独立审核重新核对冻结输入、生成IP、工具、实际输出哈希及各阶段成功标记。原runner的REVIEW_REQUIRED/返回2仅表示等待独立审核，没有重写该原始记录；最终审核timing_status=PASS、timing_closed=true。

| CPU检查 | Slow | Fast |
|---|---:|---:|
| Setup | **+0.213ns** | **+3.617ns** |
| Hold | +0.136ns | +0.082ns |
| Recovery | +4.715ns | +6.444ns |
| Removal | +0.267ns | +0.164ns |
| 最小脉宽 | +3.655ns | +4.202ns |

最终所有受约束时钟域的上述五类汇总无违例，Design Summary为All Constraints Met，CPU performance slack与最差setup一致。不能把本次新布局相对旧版-0.155ns的变化单独解释为CPU优化；它是相同CPU RTL在新板级复位/时钟实现下的整体结果。100MHz是实际后布线要求，不是综合估计或实测振荡频率。

## Gray skew证据补齐

PDS纯文本报告没有输出skew细节，但**同次report_timing/rtr.db实际是XML**，含`report_timing_{slow,fast}_path_max_skew`两表。本轮独立解析原生文件，绑定每组标题的FDC行号及该行完整source/destination选择；每corner全部10组，每组max/min各三位，逐条检查只到同位第一同步级。再核对required/actual/slack数值一致及无负余量，没有从文本缺失或max-delay推断skew通过。

两corner共20组检查均通过，最大实际skew **1.034ns**，原要求2ns，最差余量 **+0.966ns**。60条datapath-only MaxDelay检查也全部通过8ns要求，最大报告数据路径1.134ns。新增八项XML正负检查覆盖缺corner/组/位、错约束行、错同步级、实际违例及不一致余量；空表、缺失和错误范围不会获得准入。

最终重新执行50项Python测试、生成文件一致性、28+9+7项原件校验及PDS/route报告检查，全部通过。独立复核重读74行最终时序汇总和全部冻结绑定；新包13项文件、旧部署包10项文件逐项SHA256一致。参与实现的33项CPU目录输入与stage4完全一致，全部受版本管理的CPU/SoC文件相对父提交也无差异。

## 资源与包

以下是本轮原生综合层次，RAM LUT已含总LUT，无扫描夹具，不把DDR周边算成CPU。与另一综合上下文不能直接宣称面积优化或退化。

| 范围 | LUT | FF | RAM LUT子集 | DRM36K等效 | APM |
|---|---:|---:|---:|---:|---:|
| CPU核 | **6558** | **3562** | 688 | 0 | 4 |
| I/D Cache及传输 | 519 | 763 | 0 | 11 | 0 |
| 五通道CDC | 67 | 153 | 0 | 6 | 0 |
| 固定DDR桥 | 3634 | 3354 | 128 | 0 | 0 |
| ROM/SRAM/MMIO | 153 | 89 | 0 | 16.5 | 0 |
| DDR控制器/PHY | 4690 | 5144 | 43 | 0 | 0 |
| 监测 | 111 | 105 | 0 | 0 | 0 |
| 其余互连/板级逻辑 | 93 | 53 | 0 | 0 | 0 |
| 整板目标 | **15825** | **13223** | **859** | **33.5** | **4** |

诊断包`build/soc/releases/cpu_ddr_board_189c51babb73`包含真实位流/匹配smsk、ELF/map、ROM/SRAM、原始后布线数据库、文本/XML报告、FDC、独立review和README/manifest。它来自已准入数据库的隔离副本，生成前后重新核对全部物理绑定；不覆盖旧包。过期/不匹配的stage4输入已被包入口实际拒绝。

该程序是独占native端口的破坏性诊断，覆盖私有0x80010000和共享0x87300000各8192字节，另在0x80001000执行FENCE.I代码测试。预计UART输出CPU_DDR_BOOT及CPU_DDR_PASS；这仍是预期行为，不是板上观测。本包未program/verify、未访问COM12、未写Flash，也未合并或push。旧CoreMark部署包10项文件保持原哈希。没有新实物或官方CoreMark分数。

## 复现及剩余范围

```powershell
python scripts/cpu/gen_ddr_board.py --check
python -m unittest discover -s scripts/cpu -p "test_*.py"
python scripts/cpu/run_ddr_board.py
python scripts/cpu/run_ddr_board_route.py --firmware-dir <最新boot目录>
python scripts/cpu/review_ddr_board.py --physical <最新route目录> --output <独立审核JSON>
python scripts/cpu/package_ddr_board.py --route-dir <最新route目录>
```

run_ddr_board的四种故障和损坏负例入口同stage4，机器索引定位全部最新运行。剩余工作是实体DDR训练/两次启动验收，以及随后CPU/NPU/Video共享fabric和跨主端写可见性；本轮通过不扩大为完整SoC或DDR外部AC/信号完整性签核。
