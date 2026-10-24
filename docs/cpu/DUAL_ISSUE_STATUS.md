# 双发射独立路线状态

更新：2026-10-23。工作树 `D:/FPGA/TriHaRiscv-cpu-dualissue-windows`，
分支 `cpu/dualissue-windows`，基线 `340bcc2`。主工程和 SoC 集成继续各自推进。

已完成现有六级顺序双发射路径的缓存封装接通及模拟功能基线。默认仍为单发射。
固定 RV32IM/CSR、BTB512/BHT512/RAS4、I/D 各 16KiB/两路/32B 行，D 写回/写分配。
共享 LSU/乘除法资源与现有接口不变。

同一加载程序、GCC15.2 `-O2`、五次 CoreMark、相同 AXI DDR 数字模型下，
单/双周期 2,014,969 / 1,781,952，短测 CoreMark/MHz 2.481428 / 2.805912，
吞吐提升 13.076503%。WB 观测 IPC 0.718844 / 0.812843，不是架构 `minstret`。
完整计时 WB/store 除已核实的绝对起始时间外相同；CRC 和破坏负例通过。
这是 RTL 仿真，非官方或板级分数。

当前门槛是原生 CPU-only 资源及真实后布线 100MHz；二者均 UNKNOWN，
尚未开始本路线 PDS 或板测。待集成任务的 PDS 工作释放工具后，先用现有
CPU-only 单/双映射比较 FF 四读两写寄存器堆成本，再决定 Pango RAM 适配。
不把旧单发射时序或整板面积作为新双发射的验收结果。

完整证据及重现命令：[模拟基线](../verification/cpu/dualissue_cached_baseline.md)。
后续准入需继续覆盖精确异常/中断、依赖与共享资源互锁、ISA、完整 Cache
维护语义，以及多 corner 物理时序；本功能基线不替代这些门槛。

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
分数与父版相同。无区域约束20分钟原100MHz物理包已准备，独立评审通过，PDS已启动，尚无本轮最终STA。
