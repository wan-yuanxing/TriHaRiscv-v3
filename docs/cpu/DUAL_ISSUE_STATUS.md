# 双发射独立路线状态

更新：2026-10-27。工作树 `D:/FPGA/TriHaRiscv-cpu-dualissue-windows`，分支 `cpu/dualissue-windows`。

最新v72（从v70派生）LSU符号扩展前零属性已通过409604项组件/E2检查、真实双路加载程序、完整CoreMark及原生映射。短测仍4.091964/MHz，全部WB/store/profile不变；CPU-only9514 LUT/4911 FF。映射确认零属性绕过格式化后的32位结果，但**未PNR、100MHz未通过**。下一步针对B立即移位数据入口，并保留分支恢复CE问题；不叠加HOLD的v71。见[v72记录](DUAL_ISSUE_LSU_ZERO_2026-10-27.md)。

最新v71目标预比较完成组件41151检查、完整CoreMark/轨迹和原生映射。短测仍4.091964/MHz，CPU-only9583 LUT/4905 FF；目标到recover连接未显示缩短，增加27 LUT，因此**结构筛选HOLD，不启动PNR**。同时修复网表检查器对LUT6D固定选择输入的保守误报，13项测试PASS。实际时序仍以v70 FAIL和最佳v57 FAIL记录为准。见[v71记录](DUAL_ISSUE_TARGET_COMPARE_2026-10-27.md)。

最新v70同步乘法零标志完成：短测4.091964/MHz及完整WB/store/profile不变，CPU-only9556 LUT/4907 FF；组件206622检查、消费者8000检查、实际双路指令及真实侧带负例PASS。实际映射消除了零比较的APM依赖，但原100MHz后布线仍FAIL：setup **-0.192/+2.647ns**，hold **+0.111/+0.082ns**，MPW **+3.655/+4.202ns**。11个Slow setup端点；native0/runner2，392输出已核。剩余为分支恢复→fetch CE与SRAM返回链。未提升默认RTL，最佳v57 -0.009ns仍FAIL。详见[v70记录](DUAL_ISSUE_MUL_ZERO_PLAN_2026-10-27.md)。

最新v69分离ROM双口实验已完成但不采用：完整SRAM短测仍为4.091964/MHz，CPU-only9709 LUT/4906 FF；原100MHz后布线setup **-0.275/+2.835ns**，hold **+0.103/+0.063ns**，MPW **+3.655/+4.202ns**。9个Slow setup端点违例，native0/runner2，394输出与冻结输入全部核验。8条违例来自乘法结果→零比较/配对→FIFO头，另1条队头→ALU；不重复ROM映射实验，先核验该组合链的结构方案。最佳v57 -0.009ns仍为FAIL。见[v69终态](DUAL_ISSUE_ROM_SPLIT_2026-10-26.md)。

最新v68b逻辑ROM映射实验**拒绝采用**：功能/完整CoreMark仍等周期4.091964/MHz，但原约束
后布线setup **−1.376/+2.639ns**，Slow违例108端点，弱于v67。hold/MPW通过。
native0/runner2，476输出及冻结输入已核；CPU-only9703LUT/4908FF。两个ROM口映射变化
影响全局优化，不能以局部4LUT/4FF/0DRM推导整核性能。保留v67和最佳v57，不重跑该候选。
详见[v68b终态](DUAL_ISSUE_ROM_MAPPING_2026-10-26.md)。

最新终态v67：内部selector更新与外部门控分离，异步清零/X-Z fallback保留；完整SRAM
CoreMark、WB/store/profile与v65一致，4.091964/MHz。原约束布线完成但TIMING_FAIL：
setup Slow/Fast **−0.218/+2.835ns**，hold **+0.103/+0.064ns**，MPW **+3.655/+4.202ns**。
剩3个Slow setup端点；native0/runner2，444输出与冻结输入已核。CPU-only9581LUT/4908FF。
最差为ROM数据口→LSU/旁路→B路ALU，不是ROM取指使能；不重复同候选布线。
详见[v67终态](DUAL_ISSUE_MEMORY_CONTROL_2026-10-26.md)。最佳v57 −0.009ns仍保留，100MHz尚未通过。

最新进展v65：分支恢复预比较通过完整SRAM等周期/全轨迹核验，仍为4.091964/MHz；
原生compile/synthesize/dev_map通过，CPU-only9584LUT/4908FF。映射保留预比较，
FIFO1356个后端D/CE全层级检查通过。修正了双输出LUT的保守支持误报，并保留真实破坏负例。
本候选**未执行PNR，100MHz未通过**；先完成memory复位/ROM使能两条路径验证。
见[v65阶段记录](DUAL_ISSUE_RECOVERY_COMPARE_2026-10-26.md)。

v66 ROM使能隔离：组件473项与父版对照通过，异步复位/释放首拍/挂起SRAM时切ROM/四态输入已覆盖；
原生综合映射通过，实际ROM CEB锥36节点不含LSU维护或collision，注入flush负例被拒绝。
仅此局部锥通过，整图别名歧义尚未处理；v66完整CPU回归及复位→selector CE仍待完成，未PNR。
证据见[ROM控制检查](../verification/cpu/dualissue_rom_control.json)。

最新结构检查：v64 已实现两字头部副本＋只因入队写入的环形后端。完整 SRAM CoreMark、
全部 WB/store/profile 与 v57 完全一致（1221907周期、4.091964/MHz）；106个合法组合和20821步
oracle、对齐两配置、有序/IRQ、真实数据负例通过。全层级位连接核查1356个后端D/CE引脚，
在FF/同步RAM状态边界以内没有pop支持，未知节点为0，跨层隐藏pop负例拒绝。

本结构只运行了一次原约束物理试验，**仍为TIMING_FAIL**：setup Slow/Fast **−0.396/+2.660ns**，
hold **+0.112/+0.100ns**，脉宽 **+3.655/+4.202ns**；native0/runner2，442输出/30输入与五阶段标记核验。
CPU-only **9535 LUT/4908 FF/752已含RAM-LUT/4APM/0DRM**。比最佳v57多141LUT、256FF。
报告列出的FIFO端点最差+0.060ns，但剩余8个违例分布在复位→memory CE、分支恢复→CSR异常、
LSU flush→ROM CE三条控制链。不能把FIFO局部改善当成整核通过，也不能只修复复位就宣称问题解决。
保留v57为最佳完成物理基线；v64未提升默认RTL，没有第二次自动布线。
见[本轮记录](DUAL_ISSUE_HEAD_RING_RESULT_2026-10-26.md)及[完整证据](../verification/cpu/dualissue_head_ring.json)。

当前只推进**不带 Cache、不接 DDR 的 SRAM/TCM 版本**。六级顺序双发射、RV32IM/CSR，
BTB512/BHT512/RAS4、GShare 关闭；共享 LSU/MUL/DIV。变量移位在 A，B 保留立即移位。
A 分支可与 B ALU 推测配对，E1 恢复/故障取消年轻结果；B 副作用配对继续受互锁限制。

六字最佳版 v57 Windows GCC15.2 `-O2` 五次迭代：**1221907 周期、4.091964 CoreMark/MHz**，
WB 观察 IPC **1.185400**。CRC 通过，计时窗包含1448448条WB、70839条store。这是 RTL 短测，非官方分数或板级结果；观察 IPC 不是架构 minstret。

**100MHz 尚未通过。**最佳完成版 v57 原10ns/IO/hold/multicorner：setup Slow/Fast
**-0.009/+2.663ns**，hold **+0.107/+0.100ns**，脉宽 **+3.655/+4.202ns**。
原生退出0、验收器退出2，416个输出与冻结输入已核；seed8对照回退到-0.489ns，不继续扫seed。
v58 分组连续性比较终态 -0.442ns；v59 旧占用目的位置前译码 -0.689ns，均未达标。
v60 保守限制 E1 MUL 相关的分支+B副作用配对，完整 CoreMark 等周期；实际报告 setup
**-0.547/+2.716ns**、hold **+0.114/+0.108ns**、脉宽 **+3.655/+4.202ns**。
v60 原外层进程已消失，原始 result 保留 RUNNING，原生/外层退出码均**未知**；另存终态审计，
核对输入、现有输出和五阶段成功标记，不伪造退出0。最差为 E1 分支/异常到 FIFO 更新。

v61 返回最佳 v57，只给 `triha_fetch_fifo` 增加 ADS 文档5.17支持的模块属性
`syn_reduce_controlset_size=192`。去除此一注释后全部 CPU 字节还原 v57。
三项组件回归与新完整 SRAM 运行通过；独立原约束 PDS 已终态：setup **-0.468/+2.667ns**，hold **+0.114/+0.103ns**，
脉宽 **+3.655/+4.202ns**，native0/runner2，292个输出与冻结输入通过独立核验。
控制组实验增加资源且时序弱于 v57，**不采用**。
实际综合核实 FIFO 十三个17–147 FF的 CE 控制组已移到 D 逻辑，控制组总数597→584；
FIFO 映射中使能 FF 已消除。这些是映射结果，不能称频率收益。
v61 CPU-only 综合 **9773 LUT/4685 FF/752 RAM-LUT（已含LUT）/4 APM/0 DRM**，
较 v57 的9394 LUT/4652 FF增加379 LUT/33 FF；不包含 ROM/SRAM/MMIO 夹具。

v62 试验重新基于 v57，排除 v58–v61 试验，只提前计算 FIFO 四种完整更新载荷，
晚出队只作最终选择。7168 状态 oracle、算术隔离红绿/真实数据负例、两译码配置对齐、
恢复/异常、有序/IRQ及新完整 SRAM 均通过，独立源码/证据评审通过。
原生综合网表1856个实际候选位的组合上游均不含pop0/pop1，真实 LUT 输入破坏负例可检出；
此局部拓扑核验不是 STA。CPU-only **10711 LUT/4702 FF/752 RAM-LUT（已含LUT）/4 APM/0 DRM**，
相对 v57 增加1317 LUT/50 FF。原约束独立PDS已结束：setup **-1.315/+2.386ns**、hold **+0.112/+0.074ns**、
脉宽 **+3.655/+4.202ns**，native0/runner2，500个输出/冻结输入已核。
最差rst_ni→data_accept→issue/出队→FIFO，出队负载达到696；面积/总时序均回退，不采用。
见[v62候选](../verification/cpu/dualissue_fifo_prepared_values.json)。

v63 五字容量对照已完成：**1224859 周期/4.082102 CoreMark/MHz**，WB观察IPC1.182543，
较六字周期+2952（+0.241590%）。完整镜像相同，仅归一化已核实首个cycle CSR及started存储，
其余1448447条WB/70838条store完全相同。实际容量、保留双字空间、EXTRA0/1对齐、
有序异常/IRQ及负例通过。**没有启动v63 PDS，资源/时序UNKNOWN**。
根据用户对迭代效率的质疑，先冻结最佳版并完成[方法复盘](DUAL_ISSUE_TIMING_REVIEW_2026-10-26.md)，
后续先做结构与时序预算审查，再决定下一次物理准入；不直接继续试凑，不降低100MHz要求。

默认 `rtl/cpu` 未替换，候选由完整生产基线补丁/manifest 重建。
本独立分支的 `rtl/soc/triha_soc_memory.v` 含指令冲突请求槽，主工程/集成工作树未修改，未上板。
已知旧未对齐 mtval 报告源PC；未声称完整 ISA、任意未知PC或 invalid bulk 全总线证明。

见[当前实验](../verification/cpu/dualissue_fifo_controlset.json)、
[最佳完成版](../verification/cpu/dualissue_btb_qualified_kind.json)、
[v60终态](../verification/cpu/dualissue_mul_branch_pair_policy.json)及
[物理汇总](../verification/cpu/dualissue_operand_timing.json)。
下文保留历史批次；历史Cache/DDR记录不代表继续执行这些路线。

v21至v29均未完成100MHz验收。v26已在原队列中保存ALU控制，原生映射确认旧晚译码消失、
54个新元数据FF保留；实际最差路径转为头部RF读地址的高扇出、旁路、分支到队列更新。
全部原100MHz/IO/hold/multicorner预算不变。v27局部读索引syn_maxfan16已终态，70个复制Q确实把目标负载拆至每Q≤16，
但setup仍−0.792ns；最差已转nativeRF bank选择→零判断→队列使能。
v28把31个寄存器零标志保存在原写回边界，原数据/旁路/发射规则保持；新完整SRAM/Cache-on
镜像、轨迹、周期/profile相同，有序/IRQ及真实RF四态分支对照通过。实际后布线setup−1.249ns，
hold+0.110/+0.099ns、脉宽+3.655/+4.202ns，native0/verifier2；CPU8775LUT/4222FF，100MHz仍未过。
真实最差转指令类别→LSU载荷→store格式；v29将剩余五个静态类别随原队列保存，完整队列与
新整核SRAM/Cache-on/有序/IRQ均通过且周期/轨迹不变；IO版setup−0.763ns、原始版−0.895ns，
两版hold/MPW通过，native0/verifier2。30类别元数据FF及实际LSU选择cone均已核验。
同源compact+IO终态setup−1.222ns且hold−0.078/−0.066ns，不采用。v30合法性/CSR前移完整
四态、队列/有序/IRQ及整核性能/轨迹通过，6legalFF与实际CSR/invalidcone已核，但后布线setup
−1.238ns仍未过；主瓶颈是SRAM返回→E2旁路→分支比较→PC。
v31通过增加分支等待切断路径，但SRAM降到3.672145/MHz，已淘汰。v32复用已有
转发零值标志驱动两路BEQ/BNE-x0执行，无新增周期；完整SRAM/Cache-on镜像和
WB/store均与v30逐字节一致，保持4.030288/3.084289。两通道及四态回归通过，
原10ns两套独立PDS已结束：默认setup−0.943ns，I/O打包−0.539ns，
两套hold/MPW均通过。仍未达到100MHz。v33只加工具支持的局部syn_maxfan16
属性，复用v32全部功能；SRAM/Cache完整镜像及WB/store逐字节相同，
原10ns/I/O映射PDS已结束，setup−0.909ns回退，淘汰v33。v34实际复制成功但setup−1.007ns，淘汰。v35只将有符号分支比较改为
符号判定+31bit比较，整核镜像与轨迹相同，但setup−0.974ns未过。
v36基于v35把RF所有者/已写位改为两银行有效位，组件与整核通过，setup−0.662ns仍未过。
v32/v36种子8对照分别−0.960/−0.706ns，均不采用。
此历史阶段最佳v32−0.539ns；ADS retiming诊断setup−1.095ns且FF+1905，淘汰。
v37/v38分组相等比较均通过完整整核，实际carry链消除，
但setup−0.776/−1.209ns仍未过。整核中部区域因容量检查失败；
数据通路区域v32/v37也分别−0.723/−0.995ns未过。
v39局部PC寄存已等周期/等轨迹通过，但setup−1.758ns，淘汰。
v40已终态：FF后端setup−1.248ns，CPU10052LUT/5311FF，均弱于v32，淘汰。详见
[v32证据](../verification/cpu/dualissue_branch_zero_exec.json)。
见[零标志终态](../verification/cpu/dualissue_rf_zero_metadata.json)、
[类别队列I/O版](../verification/cpu/dualissue_queued_unit_classes.json)与
[同源原始I/O版](../verification/cpu/dualissue_queued_unit_classes_original.json)。
用户已授权独立PDS并行，使用私有目录/TEMP/日志；主工程、集成、板卡和串口未动。
最新终态见[ALU控制](../verification/cpu/dualissue_queued_alu_control.json)和
[同源I/O变体](../verification/cpu/dualissue_queued_alu_control_io.json)。
最新终态见[读索引扇出诊断](../verification/cpu/dualissue_rf_index_fanout.json)。

更广的ISA、异常/IRQ及Cache维护准入仍需按部署阶段完成；当前隔离功能回归和物理诊断
不能替代板级SoC验收。初始模拟基线及历史命令见
[模拟基线](../verification/cpu/dualissue_cached_baseline.md)。

## TCM 主目标与 Cache 对照（2026-10-23）

用户明确最高性能目标以 SRAM/TCM 为主，要求超过 4 CoreMark/MHz。
已完成 DDR Cache-off/on 四组短测；双发射分别为 0.459042 / 2.805912。
TCM 双发射基线 3.543019，隔离窄 MUL 转发候选 3.658271，尚未达标。
候选全计时 WB/store 对照及定向、有序执行、中断自检通过，生产 RTL 保持不变。
详见 [TCM 诊断](../verification/cpu/dualissue_tcm_profile.md) 与
[Cache 矩阵](../verification/cpu/dualissue_cache_matrix.md)。

## 配对优化短测达到门槛（2026-10-23）

隔离候选TCM **1,249,840周期 / 4.000512 CoreMark/MHz**，同固件-O2，
不带observer复现相同cycle；比双发射初始基线吞吐提高12.912533%。
DDR Cache开/关分别为3.078298 / 0.459491。完整WB/store、定向负例、
有序异常/IRQ回归和独立只读评审已完成。仅RTL短测达标，非官方/板级成绩；
CPU-only资源与实际100MHz仍UNKNOWN，生产RTL和集成工程未改。
见[配对优化证据](../verification/cpu/dualissue_pairing_performance.md)。

## 最新验收范围（2026-10-23）

用户明确实际时序通过才算通过：当前4.000512仅仿真短测候选，整体验收仍未通过。
后续只优化/测量SRAM/TCM和开启I/D Cache的DDR；DDR关闭Cache不再纳入，历史证据保留。
优先完成冻结候选的真实100MHz物理验收，再依据关键路径与停顿计数提高分数。
已核查旧run_route.ps1硬编码单发射，不能直接用于本候选；集成侧仍在推进PDS相关工作，
本轮未启动竞争性实现任务。

## 真实SRAM边界纠正（2026-10-23）

可综合本地SoC（8KiB ROM/32KiB SRAM/MMIO）双发射-O2短测1253888周期，
**3.987597/MHz，尚未超过4**；与此前128KiB仿真TCM为不同链接/存储边界。
物理快照已准备，原100MHz/IO/hold约束不变；集成PDS占用期间未执行本路线PDS。
见[物理准备证据](../verification/cpu/dualissue_sram_physical_preparation.md)。

## 真实SRAM停顿诊断与布线入口（2026-10-23）

非observer及两次observer均为1253888周期、3.987597/MHz；加载ROM/SRAM字节相同，
两次完整WB/store轨迹一致。取指空等82216周期，依赖等待123103周期；配对受阻中
79704次为共享LSU冲突、237834次为同对真实RAW，不能直接放宽互锁。
下一步量化取指队列占用和满队列回压，再决定是否修改RTL。
`run_dual_route.ps1`已完成预检及冻结绑定/报告解析单测，实际PDS路径尚未执行；
当前100MHz、CPU-only面积均UNKNOWN，整体验收未通过。详见
[SRAM诊断](../verification/cpu/dualissue_sram_profile.md)。

## 首轮独立PDS终态（2026-10-24核验）

用户允许与集成侧并行启动；已加入显式AllowConcurrentPds选项与私有TEMP/TMP。
实际启动时未发现其他PDS，因此本轮验证了独立运行，未实证双实例同时负载。
PDS完整compile/synthesize/map/place/route/report成功，实际耗时469.074秒，
原生PDS退出0；验收器因时序FAIL退出2，冻结输入和输出哈希均已核验。
Slow setup -3.015ns、hold 0.000ns、MPW +3.655ns；Fast setup +1.827ns、
hold +0.103ns、MPW +4.202ns。100MHz尚未通过。
最差路径从取指FIFO头PC，经payload选择、寄存器索引/操作数选择与旁路、
第二执行通道分支判断，到分支PC寄存器；25级逻辑，逻辑3.720ns/布线8.984ns。
下一步优先切短该控制与操作数选择链，不能仅靠扩大队列提高仿真分数。
整系统10328LUT/5005FF/16.5DRM/4APM不属于CPU-only统计；核面积待单独提取。
原始报告和哈希见[物理终态证据](../verification/cpu/dualissue_sram_route.json)。

## 操作数与依赖路径后布线实验（2026-10-24）

已完成三组RTL诊断：B raw v1最差-4.045ns，双槽并行读取v2为-2.654ns，
四态兼容的同包依赖分解v3b完整后布线为-2.212ns（比父版-3.015改善0.803ns）。
v3b两corner hold/MPW均通过，100MHz仍未通过。其10分钟前测在hold修复时
触发工具超时（native exit1，无最终STA），20分钟新跑工具exit0/验收exit2。
CPU-only综合10154LUT/4916FF/624分布式RAM LUT/4APM，排除ROM/SRAM/MMIO。
真实SRAM与Cache-on DDR短测分别3.987597/3.078298 CoreMark/MHz，周期和完整轨迹
均与各自parent相同；本批未提高分数。同RTL紧凑区域约束实验已结束，
输入只新增工程既有compact FDC，原100MHz/IO/hold不变，PNR20分钟/外层25分钟。
详见[实验报告](../verification/cpu/dualissue_operand_timing.md)。整体验收尚未通过。

紧凑区域实验已因PNR20分钟超时结束：main detailed最后97次/4458未布通，
native exit1，无最终STA，放弃该区域约束。随后v4依据FIFO有效second必须连续
的不变量，将payload raw选择缩为相对PC[2]，完整PC比较继续决定执行valid。
契约断言/跨包位置/未命中/负例/整核与完整SRAM轨迹通过，周期不变。
无区域约束的v4 PDS已完成，目录build/cpu/dual-position-select-physical-v4。
Slow setup/hold/MPW为-2.124/+0.128/+3.655ns，Fast为+1.753/+0.102/+4.202ns；
原生PDS0/验收2，515项输出哈希已核验。CPU-only综合10100LUT/4916FF/4APM，
LUT包含624个分布式RAM LUT，CPU无DRM；新网表/布局，100MHz仍未通过。

实际最差路径是WB控制旁路→A分支比较→晚到的B LSU payload选择→store格式→LSU寄存器；
起点物理cell虽名pc_wb_q，实际launch net是ctrl_wb_q[7]，不能按PC数据路径分析。
v5b提前准备LSU payload并保留实际issue许可，已修复invalid-B/class-X门控，
CSR三类Cache维护保留A。定向/负例/ordered/IRQ、真实SRAM及Cache-on完整轨迹均通过，
分数与父版相同。无区域约束20分钟原100MHz PDS已完成：Slow setup-1.692ns、
hold+0.154ns、MPW+3.655ns，Fast setup+2.087ns、hold+0.100ns、MPW+4.202ns。
原生0/验收2，681项输出哈希核验；CPU-only9965LUT/4916FF/4APM，LUT含624RAM-LUT。
当前最好setup仍负，100MHz尚未通过。下一实测路径为fetch1指令→旁路/分支→FIFO更新，
继续固定表项写入实现诊断，并将六word容量作为独立性能实验。

## 固定表项取指队列与六word短测（2026-10-24）

同容量固定表项实现保留完整队列状态/有效与idle历史，SRAM/Cache-on周期不变。
独立六word候选真实32KiB SRAM为1222884周期、短测**4.088695 CoreMark/MHz**，
关闭observer复现相同周期；较四word少31004周期。Cache-on DDR模型为1604946周期、
3.115370/MHz。完整WB/store除已验证的初始cycle与started存储外一致，WB观察IPC1.184452，
不等于架构minstret，不是板级或官方分数。
完整队列状态与独立顺序oracle、容量RED/GREEN/负例、整核有序/IRQ及独立评审通过。
原100MHz/IO/hold约束、无区域约束的新PDS已完成，但Slow setup-2.228ns、
Slow/Fast hold-0.068/-0.060ns失败，MPW通过；CPU-only10039LUT/5008FF，含624RAM-LUT。
原生PDS0/验收2，757项输出核验。当前最差是异常取消→队列更新；hold违例为BTB写地址。
继续按真实路径处理，**整体目标仍未通过**。详见[取指队列证据](../verification/cpu/dualissue_fetch_queue.md)。

针对实际异常取消和BTB WADDR路径，v7将两路异常先OR再用原if/else选scalar，
并按block加入原生WADDR保持门。65547异常检查、10066 BTB检查、地址破坏负例、
ordered/IRQ及完整SRAM/Cache-on轨迹均通过；分数不变。独立评审和物理包预检通过，
原100MHz PDS已结束：setup-2.014ns、Slow/Fast hold+0.111/+0.091ns；MPW通过。
综合阶段确认全部80地址位为两级LUT、局部WADDR扇出39，
尚不能替代实际时序。见[本轮核验](../verification/cpu/dualissue_control_hold.md)。

v7实际hold违例已消除，setup仍未过。新的最差路径是分支结果到共享MUL载荷选择，
v8复用LSU已验证的提前数据选择/实际发射许可分离；真实时钟标签/窄乘积消费/四类符号、
取消/hold、整核与完整轨迹均通过，分数不变。原100MHz物理核验已完成：setup-1.348ns、Slow/Fast hold+0.113/+0.102ns、MPW通过；
原生0/验收2、485项输出核验，setup仍未过。新的实际路径落在FIFO剩余数计算到宽payload CE。

v9将宽payload的append/survivor使能改为常数占用译码，原剩余数算术仅留小计数器。
DEPTH2/3完整state/独立顺序模型、负例、整核有序/IRQ和完整SRAM/Cache-on对照通过，
周期不变。独立评审后新原100MHz/no-region PDS已结束，setup-2.258ns，单独采用该方案未改善时序。
见[当前FIFO使能实验](../verification/cpu/dualissue_fifo_enable.md)。


## 原生寄存器堆与分支配对诊断（2026-10-24）

v10原生2W4R寄存器堆保留完整SRAM/Cache-on性能与轨迹，CPU-only由v8的
10173LUT/5008FF降为8884LUT/4078FF；LUT含752个分布式RAM LUT，另4APM/0DRM。
新100MHz后布线Slow setup-1.536ns，hold/MPW通过；v11加FIFO使能预译码后为
8812LUT/4078FF，setup-1.522ns，hold/MPW通过。两个候选均尚未通过100MHz，
不能把面积下降或仿真4.088695/MHz当整体验收。见[原生存储证据](../verification/cpu/dualissue_native_rf.md)。

当前v12仅让BEQ/BNE且带x0源的A分支使用literal-zero判断配对，其他A分支单独发射；
完整分支执行及异常/RAW/WAW/IRQ门控保持。SRAM1240606周期、短测4.030288/MHz，
Cache-on DDR模型1621119周期、3.084289/MHz；各1448448写回/70839存储完整对照通过，
仅验证过的初始绝对cycle及对应started存储归一化。6166定向检查、负例、有序异常及IRQ
自检通过；独立评审通过，原10ns/no-region/20min PDS已结束：Slow setup-1.276ns、hold+0.115ns、MPW+3.655ns；Fast为+1.788/+0.088/+4.202ns。原生0/验收2，787输出核验，100MHz尚未通过。
这些仍是五次迭代RTL估计，非官方分数/板测，观察IPC不是架构minstret。
生产RTL和集成工程未变，整体验收仍未通过。见[本轮证据](../verification/cpu/dualissue_zero_pair.json)。


v12新关键路径为WB操作码bit7→RA旁路→literal-zero判断→FIFO remove_b→剩余数算术→entry1载荷捕获，11级、logic1.584ns/route9.347ns。下一v13仅组合已验证的FIFO使能预译码，保持v12分支策略和原生RF；重新核对性能与完整轨迹后再跑原约束。

v13新整核/IRQ和完整SRAM/Cache对照均通过，周期/所有轨迹/profile与v12完全一致；独立评审后已启动原10ns/no-region/20min PDS。并行v14仅注册同级E1/E2/WB合格目的标签以去除晚到mask，原表达式时钟可达oracle40003检查及负例通过，整核/IRQ及完整SRAM/Cache性能/轨迹均与v13相同，独立物理准入评审待完成。


v13最终原10ns时序退步：Slow setup-2.659/hold+0.112/MPW+3.655ns，Fast+1.459/+0.100/+4.202ns；CPU-only8772LUT/4078FF。native0/verifier2，553输出核验。实际路径为fetch0指令→旁路→通用分支比较→issue.pc_x_q。拒绝把该FIFO组合当时序策略，v14已准备但暂不执行PDS；v14b将相同寄存标签改动放回v12更好的FIFO父版，重新测量绑定。


v14b相对v12仅寄存同级合格标签，恢复原FIFO；新完整SRAM/Cache镜像、WB/store、周期/profile与v12完全相同。独立源码与冻结物理包评审通过，原10ns/no-region/20min PDS已启动。尚未通过100MHz，不提升生产RTL。见[寄存标签证据](../verification/cpu/dualissue_registered_tags_simple.json)。


v14b原10ns已终态：Slow setup-1.629/hold+0.112/MPW+3.655ns，Fast+1.884/+0.099/+4.202ns；native0/verifier2，529输出核验。CPU-only8629LUT/4108FF/752RAM-LUT(included)/4APM/0DRM，30个标签FF实际映射保留。新实际路径为fetch1源索引→旁路选择→通用分支比较→pc_x，18级、logic2.877ns/route8.265ns，100MHz仍未通过。


v15仅将已有onehot旁路输出改为单比特reverse-case，RF默认/x0及所选XZ数据传递保持。parent与新单/双24448项检查及负例、zero6166、有序/IRQ均通过；独立评审确认onehot前提。新SRAM/Cache完整镜像、WB/store、周期及profile与v14b精确相同，独立物理绑定评审通过，原10ns/no-region20min PDS已启动；属性效果与时序仍待实际报告。


v15 PDS确实采纳4处parallel_case，但最终setup-2.213ns；Slow hold+0.110/Fast+0.098、MPW通过，native0/verifier2，685输出核验。CPU-only8679LUT/4108FF。该表示法未改善物理结果，实际零分支→FIFO最差-2.213ns，通用分支→pc_x另有-1.881ns；保留失败记录，不选为改进。下一诊断回到v14b，针对BGE额外greater+equality合并改用!less。


v16保留vendor，局部执行derivative把BGE改为!signed_LT并删除unused_GT；全12输出/137bit40139检查及known-taken负控、zero/ordered/IRQ与完整SRAM/Cache对照通过。两类短测仍4.030288/3.084289，独立评审后原10ns/no-region20min PDS已启动。该build候选把局部module分组在CPU翻译单元，未提升生产RTL；准入后才独立拆文件维护。


v16原100MHz终态setup-1.346ns（比v14b-1.629改善0.283ns，新网表/布局），Slow/Fast hold+0.107/+0.049ns，MPW+3.655/+4.202ns均通过；native0/verifier2、453输出核验。CPU-only8668LUT/4108FF。最差已转为wide RB→zero比较→FIFO CE；v17仅前移scalar零标志，dual/single各84288对照、负控及active zero6166通过，完整性能/轨迹和独立评审运行中。


v17 scalar零标志前移已完成真正独立31×64×4payload×2zero-source×BEQ/BNE×2word交叉，parent/dual/single各227136 PASS，负控有效。整核、IRQ及运行镜像/完整WB/store/周期/profile完全同v16；独立准入评审后启动原10ns/no-region20min PDS，最终时序待验收。ELF元数据可不同，物理包绑定v17本次自己的ELF。


v17最终setup-1.741ns，Slow/Fast hold+0.109/+0.083、MPW通过，native0/verifier2，551输出核验；CPU-only8902LUT/4108FF。零helper实际使用scalar flags，最差已转E1 opcode31→early MUL decode→older scoreboard32bit插入/索引读取→issue→FIFO；下一v18以少数producer tag直接比较替换真实许可对32bit位图的读回，保留索引X/Z行为与无状态/等周期约束。


v18以4个pending producer tag直接比较替换6处真实bitmap读取，不加state/cycle。原indexed-bitmap oracle在4种bypass配置parent/new各32773 PASS，actual-accept及branch-pair负控有效，使用真实pending记录的6166分支/乘法用例通过，旧测试保留。运行镜像/完整WB/store/周期/profile均同v17，独立原10ns/no-region20min包评审通过后PDS已启动。


v18最终setup-1.110ns，为当前最佳；Slow/Fast hold+0.113/+0.100、MPW通过。native0/verifier2、511输出核验；CPU-only8692LUT/4108FF，较v17少210LUT。新最差为pipe1_opcode_e1[30]→MUL低字类型译码→early_mul(98fanout)→scalarzero→FIFO。下一v19在原采样点寄存low-MUL类型（每pipe1bit）和共享宽度可用性（1bit），无新流水级/周期。


v19在原capture/reset/hold/bubble块内寄存2个pipe低MUL类型位及1个共享宽度ready位，保持ready reset1及holdX/Z原采样语义。pipe40003和multiplier全65bit41027对照/负控通过，actual B-MUL/earlyconsumer6166、pending32773、有序/IRQ及完整SRAM/Cache镜像/轨迹/周期/profile均与v18相同。独立评审后原10ns/no-region20min PDS已启动，最终时序待核。

v19最终原10ns未通过：Slow setup-1.765ns为done_o端口，首条CPU路径-1.693ns为pc_x[2]→A目的标签选择→同包RAW/WAW比较→FIFO CE；Fast setup+1.025ns，Slow/Fast hold+0.114/+0.100ns、MPW+3.655/+4.202ns通过。native0/verifier2、563输出哈希已核。CPU-only8736LUT/4052FF/752RAM-LUT(included)/4APM/0DRM；3个预期元数据FF均保留，旧opcode位优化使总FF-56。下一v20把两种raw-fetch目的依赖提前计算后选scalar，保持原发射/四态语义及全部约束；端口违例仍须一起解决。


v20同包RAW/WAW提前到raw-fetch标量，parent/new各48768检查及负控通过；pending32773、实际B-MUL6166、有序/IRQ及完整SRAM/Cache镜像/写回/存储/profile均与v19相同。SRAM短测4.030288/MHz，Cache-on DDR模型3.084289/MHz。两套原10ns/no-region物理包独立评审后并行启动，第二套仅复用syn_useioff打包已有输出FF；原始IO/hold/multicorner预算字节不变。实际时序待验收，生产RTL未变。见[本轮证据](../verification/cpu/dualissue_packet_dependency.json)。


v20两套已终态：原方案setup-0.805ns为当前最好，Slow/Fast hold+0.118/+0.102ns、MPW+3.655/+4.202ns；I/O方案setup-1.198ns、hold+0.117/+0.100ns，MPW同值。均native0/verifier2，513/434输出已核；CPU-only8710LUT/4052FF。I/O输出FF实际打包成功，但新映射/布局整体未改善，仍按原方案作物理父版。原方案最差RF written有效标志→B源读/旁路→有符号分支→issue PC；I/O方案另显示分支判断后仍进入PC加法carry。下一步分离诊断完整地址结果保留和原生RF live-bank编码，不合并未测候选、不加周期。


v21完整target/PC+4结果保留与v22原生RF live-bank编码为两个独立v20父版诊断；前者全137bit执行输出/PC负控、后者8200存储与bank归属/写入负控、完整操作数单/双模式均通过。两者有序/IRQ和新SRAM/Cache-on运行镜像、完整轨迹、周期/profile均与v20相同。独立源码和冻结包评审后分别启动原10ns/no-region/noIO20min PDS；实际映射与最终六项时序待核，不合并未测改动。


v21终态setup-1.168ns、Slow/Fast hold-0.075/-0.064ns，MPW通过，CPU8772LUT/4055FF；提前完整地址结果的映射确实形成最终mux，但整体验收退步。v22终态setup-1.114ns、hold+0.059/+0.030ns，MPW通过，CPU8687LUT/4052FF；最差转为PC选择→分支→issue PC，route8.682ns占82%。均native0/verifier2，未超过v20-0.805ns，不采用。下一v23复用v20准确RTL/固件和已有compact区域/IO属性，时钟/IO/hold预算保持；区域增量对照同源IO版-1.198ns，最终实际时序仍须全部通过。


v23 exact-v20 compact物理包58c1910a...经独立核验后启动。只新增已有CPU区域和输出FF打包属性，原10ns/IO/hold/multicorner预算保持字节相同。该区域增量对照v20 IO版-1.198ns，原无属性最好-0.805ns仍保留；待实际报告，不能将区域利用率当频率验收。


v23最终setup-1.283ns、Slow/Fast hold+0.098/+0.056ns、MPW+3.655/+4.202ns，native0/verifier2，区域试验未改善。实际fetch1 opcode2→exec类别→LSU payload→load/address/store格式为11级、logic1.923/route9.007ns。下一v24复用已有CSR输入decoder与同队列info，把exec位在原采样点前算好（预计6FF），不改变阶段/周期、其余类别/CSR/invalid/idle历史；已开始完整对照。


v24仅在已有队列info中加入exec类别位；整151bit/12005步对照在MULDIV1/0与EXTRA1均通过，旧/新exec输出破坏负例有效；packet48768、B-MUL6166、有序/IRQ与新完整SRAM/Cache镜像/轨迹/周期/profile均同v20。独立源码与原10ns/no-region/noIO物理包8ff0f7f3...评审后启动，实际元数据FF/映射/后布线结果待核。


v24原10ns终态setup-0.909ns、Slow/Fast hold+0.111/+0.100ns、MPW+3.655/+4.202ns；native0/verifier2，CPU8773LUT/4058FF。6个exec元数据FF实际保留且供给issue/LSU，最差转入队SRAM指令25→预译码5LUT→metadataFF。下一v25按原mask分组opcode/funct，保留I-shift bit25忽略与所有四态结果；17相关位全131072二态组合和X/Z共290336项对照通过。


v25按精确opcode/funct掩码分组的组合分类器已完成290336项二态全集/选定X/Z对照、负控、整151bit三配置、packet48768、B-MUL6166及有序/IRQ。新SRAM/Cache运行镜像、完整轨迹、周期/profile均同v20，仍4.030288/3.084289短估计。独立源码与物理包795f966f...终核后，原10ns/no-region/noIO20min PDS已启动；实际拓扑、资源和最终六项时序待验收。


v25已终态：Slow setup-0.914ns（首条CPU-0.892ns），Slow/Fast hold+0.111/+0.099ns，MPW+3.655/+4.202ns；CPU8816LUT/4058FF，native0/verifier2。精确组合分组实际6→4节点，但晚ALU控制仍在关键路径。

v26将9bit ALU控制随原队列保存，54元数据FF与两路真实exec静态选择已核实；完整二态/选定四态、队列、对齐、负控与整核轨迹/性能同v20。原版setup-1.187ns，I/O版-0.798ns；两corner hold/MPW通过，均native0/verifier2、全部冻结输入/输出和传输哈希核验。CPU-only8860LUT/4112FF/752RAM-LUT(included)/4APM/0DRM。最差转为fetch1指令索引[21/20]扇出62/61→RF读取/旁路/分支；下一按工具文档局部复制扇出，保留所有reset/flush/idle历史。100MHz仍未通过，不提升生产RTL。


v32将已有转发零值标志接入两路执行单元的BEQ/BNE-x0判断，无新增流水级。修复了初版仅连接通道0的问题，移除掩盖悬空输入的回退和临时打印。两通道连接红/绿测试、10000组四态分支比较、540400项实际RF/转发标志检查及负控、有序异常/IRQ通过。SRAM 1240606周期、4.030288/MHz；Cache-on 1621119周期、3.084289/MHz；与v30运行镜像及完整WB/store逐字节一致，均为短RTL估计。可重建补丁已核验，原10ns/I/O/hold约束20分钟PDS运行中，尚未通过时序。证据见[零值分支执行](../verification/cpu/dualissue_branch_zero_exec.json)。

v31历史记录审计：实际完整WB/store文件不相同（首个差异为cycle CSR读值及其存储），已撤回未核实的完全一致说法；同固件CRC PASS但周期+9.75%，仍淘汰。已修复其完整生产基线补丁并实测可重建，未改历史运行文件。


v32两套终态及全部冻结输入/输出哈希已核：I/O setup Slow/Fast−0.539/+2.835ns，hold+0.118/+0.101ns，MPW+3.655/+4.202ns；默认setup−0.943/+2.023ns，hold+0.123/+0.103ns，MPW同值。native0/verifier2。CPU-only8869LUT/4252FF/752RAM-LUT(included)/4APM/0DRM。I/O最差为pipe1 E1标签→转发选择→有符号分支比较→pc_x，17级，logic2.657ns/route7.339ns。未宣称100MHz通过。


v33只在raw forwarding hit/select、branch_taken_r增加ADS手册5.13支持的syn_maxfan16。去除三处注释后逐字符还原v32；新SRAM/Cache完整镜像、WB/store和周期均相同。独立只读审查允许隔离PDS诊断，不代表生产准入；实际复制效果待映射核验。见[局部扇出证据](../verification/cpu/dualissue_forward_control_fanout.json)。


v33终态：Slow/Fast setup−0.909/+2.840ns、hold+0.113/+0.100ns、MPW+3.655/+4.202ns；native0/verifier2、全部冻结输入/输出已核。CPU-only8871LUT/4252FF/752RAM-LUT(included)/4APM/0DRM。编译器识别三处新属性，但函数内hit/select属性未保留在综合网表；branch_taken部分复制且carry驱动网络有未复制警告。相比v32 setup退步0.370ns，因此不采用。下一步须先把目标匹配/选择网络显式暴露到模块边界并在综合后验证真正复制，或另行验证分支比较器结构；不盲目重复当前属性方案。


v34基于v32，把四路转发匹配/独热选择暴露为模块级网络，并使用ADS支持的syn_maxfan16；共享同一组已消除未知匹配的hit给数据与zero属性。540400实际RF/转发四态检查、破坏优先级负控、有序/IRQ均通过，独立源码/证据审查无阻塞。完整SRAM/Cache固件及WB/store逐字节同v32，分数保持4.030288/3.084289。原10ns/I/O/hold约束20分钟独立PDS已启动，实际映射与终态时序待核。见[显式转发控制证据](../verification/cpu/dualissue_forward_explicit_controls.json)。


v34终态setup Slow/Fast−1.007/+2.682ns，hold+0.098/+0.058ns、MPW+3.655/+4.202ns，native0/verifier2。关键N3168在综合中确实分成15/16/10负载，57个受约束scalar均≤16，但setup仍退步；CPU-only8868LUT/4256FF/752RAM-LUT(included)/4APM/0DRM。冻结输入/输出已核，不采用。

v35回到v32，仅改less_than_signed：异号按符号，同号仅比较低31bit，未知符号保留X。用原v32完整branch模块作独立clocked oracle，全137bit输出40139次对照/负控及有序/IRQ通过，独立审查无阻塞。新完整SRAM/Cache镜像和WB/store逐字节相同，4.030288/3.084289短RTL分数不变。原10ns/I/O/hold的20分钟PDS已启动。见[分支符号比较证据](../verification/cpu/dualissue_branch_sign_compare.json)。


v35终态setup Slow/Fast−0.974/+2.682ns、hold+0.113/+0.100ns、MPW+3.655/+4.202ns，native0/verifier2，完整冻结输入/输出已核。CPU-only8837LUT/4252FF/752RAM-LUT(included)/4APM/0DRM。旧32bit分支减法消失；最差written_q[7]→RF资格/银行选择→转发→比较→PC，逻辑13级/2.159ns，布线8.294ns。仍不及v32−0.539ns。

v36沿用双银行LVT拓扑，只重编码62个有效/所有者状态位：reset00、port0写01、port1写10，port0同地址优先。读数据直接case选银行，zero属性按live0|live1资格保持；RAM与hold gates未改。独立RF oracle20195次、实际RF/转发540400次及错误银行负控、有序/IRQ通过。独立审查限定同步复位后可达状态等价。整核SRAM/Cache完整镜像和WB/store同v35，4.030288/3.084289短RTL分数不变；原10ns独立PDS启动。见[RF银行有效位证据](../verification/cpu/dualissue_regfile_bank_valid.json)。


v36种子1终态setup Slow/Fast−0.662/+2.631ns，hold+0.111/+0.100ns、MPW+3.655/+4.202ns，native0/verifier2，冻结输入/输出已核。CPU-only8979LUT/4256FF/752RAM-LUT(included)/4APM/0DRM。比v35改善0.312ns，仍未通过。复用工程已有种子8方案，对v32和v36各做一次有界对照；新准备脚本只允许种子1/8，默认Tcl逐字不变，12项冻结/预算/参数检查通过；两套输入与原Tcl仅种子不同（目录规范化后），不改变约束或放松验收。


种子8两套终态均失败：v32 setup Slow/Fast−0.960/+2.667ns、hold+0.116/+0.102ns；v36−0.706/+2.795ns、hold+0.115/+0.102ns；MPW均+3.655/+4.202ns。冻结输入/输出已核。保留种子1最佳，不扩展种子搜索。

同源v32启动一次ADS原生-retiming诊断，源码/固件/FDC/IO/hold/seed1均同最佳包，规范化目录后Tcl仅综合选项不同。默认Tcl保持原字节，14项参数/冻结/兼容检查通过。尚未验证实际移动与综合后语义，不能凭工具PASS或RTL测试宣称准入；需核查日志/netlist和最终时序。


原生retiming终态：Slow/Fast setup−1.095/+2.667ns、hold+0.082/+0.108ns、MPW+3.655/+4.202ns。CPU-only8871LUT/6157FF/752RAM-LUT(included)/4APM/0DRM，冻结输入/输出已核。时序更差且FF增加1905，因此拒绝，不花费完整综合网表CoreMark仿真、不作重定时功能准入。

v37/v38回到v36，通用BEQ/BNE比较改为保持中间结果的XOR/归约相等分组，分别8×4bit与11×3bit（末组共同补零，适配六输入LUT）。均全137bit输出40139对照/漏高位负控、有序/IRQ及独立审查通过，无新增状态/周期。v37完整SRAM/Cache镜像和WB/store同v36，4.030288/3.084289；独立原10ns PDS启动。v38完整仿真待结束。实际LUT/carry拓扑与最终STA待核，不以syn_keep请求代替映射证据。


v37/v38分组比较终态：setup Slow/Fast分别−0.776/+2.723ns、−1.209/+2.842ns；hold分别+0.107/+0.101ns、+0.113/+0.083ns；MPW均+3.655/+4.202ns。CPU-only8948LUT/4256FF与8961LUT/4257FF，均752RAM-LUT(included)/4APM/0DRM；全部冻结输入/输出已核。carry等值链消除但布线仍主导，不采用为已收敛设计。

当前各对v32和v37运行一次中部PAP_REGION(0,64,100,149)对照，区域尺寸同旧upperquarter试验，已有IO寄存器打包保留；全部基础FDC/RTL/固件/seed1及预算不变，无timing exception。PAP逻辑坐标不得直接当CLMA物理坐标；实际区域使用与setup/hold/MPW待最终报告核验。见[区域对照](../verification/cpu/dualissue_central_region.json)。


整核中部区域两套均在约束检查失败，native/runner1，无最终时序。首批容量失败位于u_frontend/u_npc，不能据此报告时序收益。原始错误及输出哈希保留。改为仅u_issue/u_exec0/gen_dual_exec.u_exec1/u_div/u_lsu/u_frontend/u_decode同一区域，排除3118LUT预测器与硬乘法器；所选层级约4762LUT。v32/v37两套原RTL/固件/基础FDC/seed1预算不变，实际区域容量与布线待验收。


数据通路区域两套终态：v32 setup Slow/Fast−0.723/+2.663ns、hold+0.082/+0.046ns；v37−0.995/+2.647ns、hold+0.119/+0.072ns；MPW均+3.655/+4.202ns。区域通过容量与布线但不改善最佳结果，全部冻结输出已核，不采用。

真实分支画像：v32计时窗266022条件分支（147132 taken/118890 not-taken），20309 JAL/18198 JALR，20530 PC mismatch episodes，独立WB opcode计数完全一致，新增observer后完整trace/程序保持。若仅每恢复额外1cycle估算3.964679/MHz，不能作为解决方案；该估算不是新架构实测。

v39局部MUX重定时：四组候选PC与onehot选择同沿寄存，visiblePC严格保持CSR>EX1>EX0>+8>+4>hold优先级。独立单PC oracle20005周期（控制/目标/异步reset XZ、回绕）与错CSR选择负控、有序/IRQ、RF转发540400检查通过；独立审查无RTL阻塞。原版试验两次因测试刺激同tick reset多次赋值/force传播竞争失败，修正后parent与candidate均通过，失败日志保留。新完整SRAM/Cache镜像/WB/store同v32，仍1240606/1621119cycles，4.030288/3.084289短RTL分数；PDS原10ns预算启动。原PC存储32bit→名义132bit，输出mux可能造成新关键路径，必须核实实际映射及全部corner，未作准入。见[局部PC重定时](../verification/cpu/dualissue_pc_candidate_registers.json)。


v39终态setup Slow/Fast−1.758/+2.700ns、hold+0.112/+0.100ns、MPW+3.655/+4.202ns，native0/verifier2，冻结输入/输出已核。候选PC/选择FF实际保留，CPU-only8815LUT/4360FF/752RAM-LUT(included)/4APM/0DRM。旧branch到32bitPC写口路径移动，但新最差FIFO data_q[1][4]→消费/shift控制→data_q[2][19]，故不采用。

v40基于最佳v32，仅双发射RF改为复用已有vendor FF后端（同步reset、port0写优先），保留31个zero元数据。输入mask&ffffffff保持原生RAM门对Z→X写数据语义。最初函数隐式读取zero_q导致地址不变时flag陈旧，独立组件实测检出；改为全部显式函数输入，保留bad快照/失败记录。固定版RF20195、转发540400及metadata损坏负控、有序/IRQ通过，独立审查限定至少经历一次同步复位；复位前输出不等价、不作声明。单发射/Xilinx路径未改。完整SRAM/Cache仿真运行中。


v40固定版完整SRAM/Cache固件及WB/store同v32，1240606/1621119cycles、4.030288/3.084289短RTL分数保持。原10ns/I/O/hold/multicorner/seed1，20分钟独立PDS已启动。CPU-only映射与最终STA待核，仍不提升生产RTL。见[FF后端对照](../verification/cpu/dualissue_regfile_ff_zero.json)。


v40终态：Slow/Fast setup−1.248/+2.647ns、hold+0.107/+0.102ns、MPW+3.655/+4.202ns，native0/verifier2。全部冻结输出已核，CPU-only10052LUT/5311FF/624RAM-LUT(included)/4APM/0DRM。最差pipe1 E2标签→分支/PC。时序与资源均弱于v32，不采用。下一步验证取指预测下一PC的同事务传递，再试E1寄存操作数上的分支恢复边界；不放宽100MHz，不提升生产RTL。


v43只增加合法A分支+B ALU推测配对，E1恢复/故障取消B的E2载荷和标签，不允许新增推测LSU/MUL/分支/CSR。真实wrong-path ALU退休负控检出，有序/IRQ及完整SRAM通过，周期1226007、**4.078280/MHz**、WB IPC1.181435；1448448WB与70839store除绝对初始cycle相同。v44进一步把同拍flush会覆盖的队列dequeue计算从最终recovery取消门控前取出，执行/外部副作用仍取消；1024定向dequeue独立性、恢复/故障/目标寄存器消费及有序/IRQ已过，完整SRAM在跑。两版未作时序通过声明。


v44完整SRAM已PASS，1226007cycles/4.078280/MHz/WB IPC1.181435，ROM/SRAM及全部WB/store与v43逐字相同。完整ELF只.strtab不同，全部allocated sections相同；不称整个ELF相同。原100MHz20分钟PDS已开始，CPU-only综合9324LUT/4601FF/752RAM-LUT(included)/4APM/0DRM，最终STA待验。额外seed173随机访存/IRQ也PASS，seed97单/双发射双模式有序对照也PASS。见[队列恢复解耦证据](../verification/cpu/dualissue_e1_queue_ready.json)。


v44终态：Slow/Fast setup−1.035/+2.571ns，hold+0.118/+0.110ns、MPW+3.655/+4.202ns，native0/verifier2，完整冻结哈希已核。关键已转LSU pending→SRAM同址写冲突→取指active_q使能，6级/logic0.971ns/route9.637ns。v45只把derived fetch的activation等待策略从REGISTER_REDIRECT复用MMU机制中拆开：实际MMU0沿用vendor非MMU分支激活原则，保持寄存redirect/请求握手/旧响应丢弃；实际MMU1保持原等待策略。启动不accept、后续背压/flush及丢弃破坏负控、有序/IRQ已过，新SRAM在跑。


v45完整SRAM再次通过，1226007cycles、4.078280/MHz，完整ROM/SRAM/WB/store与v44逐字相同。原10ns20分钟独立PDS已启动。独立审查限定当前有限延迟且取指无副作用的SRAM边界：启动背压释放时可能接受旧PC请求，必须靠既有branch_w/branch_d_q丢弃其响应；不是取指请求轨迹等价，也不是未来外部不可响应/有副作用接口的准入。实际MMU1等待条件保持。见[启动策略证据](../verification/cpu/dualissue_fetch_activation.json)。


v45终态setup−0.883/+2.836ns，hold+0.117/+0.100ns，MPW+3.655/+4.202ns；启动feedback已除，最差B RF读→74负载移位量。v46仅ALU输入B syn_maxfan16，实际两ALU各53条网络、每条≤16，完整性能/轨迹不变，但setup−1.015/+2.696ns，hold+0.089/+0.050ns，MPW同值；最差A PC字选择179负载→源数选择→移位，不继续盲调属性。v47变量移位统一A、B立即移位直接取指令shamt，3种寄存移位/3种B立即配对、44096四态ALU及真实调度破坏负控、有序/IRQ和完整SRAM全部PASS，1226007cycles/4.078280/MHz，完整镜像/WB/store相同；尚未单独布线。v48继承v47，把请求PC bit2留在既有PC/skid，FIFO先对齐首个有效字，A固定队头、失配重定向；上半字/预测/不同上下指令/fault侧带/背压/EXTRA0与1及负控、整核有序/IRQ/恢复已过，新SRAM在跑。


### 2026-10-27 v73 rs1 移位旁路：HOLD

组件全输出对照及故障负例通过；完整SRAM CoreMark与v72保持1221907周期、短测4.091964/MHz，WB/store/profile一致。原生三阶段通过，CPU核9726LUT/4932FF，比v72+212/+21。局部直接移位连接保留，但整条关键路径改善UNKNOWN；不启动PNR、不叠加到默认基线。独立审查确认HOLD。详见[本轮记录](DUAL_ISSUE_SHIFT_DATA_2026-10-27.md)。100MHz仍未通过。


### 2026-10-27 v74 提前条件目标：实际时序未通过

完整功能与SRAM短测保持4.091964/MHz，CPU核9516LUT/4975FF。实际原100MHz布线Slow/Fast setup -0.297/+2.639ns，hold +0.031/+0.013ns，MPW通过。408输出核验，8个Slow违例。旧recovery CE离开违例列表，但控制清零被吸入新目标carry形成4个端点；另有SRAM CE、A结果及CSR异常路径。详见[记录](DUAL_ISSUE_EARLY_TARGET_2026-10-27.md)。不提升默认版；下一v75仅保留纯sum边界，先检查实际carry支持。


### 2026-10-27 v75 纯目标sum：局部结构有效，整体时序FAIL

完整SRAM仍4.091964/MHz短估算，CPU核9527LUT/4975FF。实际100MHz Slow/Fast setup -0.409/+2.663ns，hold +0.111/+0.102ns，MPW通过，356输出核验。新目标carry控制依赖确实消除且无目标寄存器违例，但22端点转为11个BTB target WE和11个B恢复CE；整体比v74退步，不提升默认。下一针对BTB写口tag读/比较/使能与B恢复控制，保留策略周期，不扫seed。详见[本轮证据](DUAL_ISSUE_TARGET_SUM_2026-10-27.md)。
