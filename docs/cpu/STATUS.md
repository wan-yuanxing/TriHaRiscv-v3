D-Cache 响应重叠优化（2026-10-23）：成功 cached load 的响应周期可接纳下一请求，保留返回寄存器，驻留 load 启动间隔由3拍降为2拍。相同 GCC15.2/-O2/无LTO 载荷的5次 RTL/native-DDR CoreMark 周期2158431→2018576，短测2.316497493→2.476993683/MHz，模型吞吐+6.928399%；完整WB/store观察流及外部访存计数一致。实际100MHz后布线独立复核通过：CPU Slow/Fast setup +0.309/+3.551ns、hold +0.151/+0.099ns、MPW +3.655/+4.202ns；全部时钟域和Gray约束通过。CPU-only6507LUT/3562FF/688RAM-LUT已含/0DRM/4APM（相对父版+48LUT），Cache/传输668LUT/807FF/11DRM。5000次镜像 cpu_ddr_coremark_on_478149ee9e63 已打包并核验，UART的CPU-LUT分母为6507；尚未上板，不能作为板测分数。69项CPU与45项SoC Python回归、专项正负例和终态绑定通过。备份 cpu-before-dcache-overlap-20261022，证据见 docs/verification/cpu/dcache_overlap.md/.json。主工程未修改，板上仍保留 cpu_ddr_coremark_on_32019ccd2f69，COM12未访问、Flash未写。下一步为新版5000次板测。以下为历史检查点。

Write-back 候选（2026-10-22）：私有 DDR 改为写回/写分配，共享 DDR/MMIO 继续不缓存，CPU 六级单发射、预测器、100MHz 和 GCC -O2 不变。组件、联合 I/D、真实 CPU、FENCE.I、SoC 和原生 DDR 测试通过。五次同程序数字模型周期 3899101→2158431（减少44.642855%，吞吐+80.645154%），70840次CPU store在计时区间不再产生外部写，完整观察流一致；不是实际板测分数。CPU-only 原生映射6459LUT/3562FF，Cache/传输671LUT/807FF/11DRM；实际100MHz后布线及完整冻结证据复核通过（Slow/Fast setup +0.134/+3.629ns，hold +0.153/+0.100ns，脉宽 +3.655/+4.202ns，全部Gray检查通过）。备份cpu-before-writeback-20261022；已生成cpu_ddr_coremark_on_418eb7d376c5的5000次CoreMark镜像（CPU-LUT分母6459），尚未上板；板上保留上一已验证镜像、COM12未占用。合同和证据见 docs/verification/cpu/dcache_writeback.md/.json。以下为历史已部署检查点。

最新 DDR store 优化版已完成实际上板 CoreMark 验收。PG2L100H/00602899 易失 Program/Verify 均成功，当前保留 cpu_ddr_coremark_on_32019ccd2f69，未写 Flash；COM12 已释放。独立原始 UART 捕获的 5000 次结果为 5,779,800,133 周期、57.79800133 秒、86.508181684 CoreMark、0.865081817/MHz、0.013356211/CPU LUT6477，标准 CRC 和 BOARD_PASS 通过。相比用户此前有效板测 84.374476888，吞吐 +2.528851%，CPU-LUT 效率 +3.811055%；两版 DDR 可加载程序字节完全相同，GCC15.2/-O2/无LTO 不变。该实际提升小于数字模型的 +4.578979%，以板测为准。CPU-only6477LUT/3562FF/688RAM-LUT已含/0DRM/4APM，Cache/传输492LUT/763FF/11DRM；实际100MHz后布线和完整哈希再核验通过。本次自动启动正常、无按键操作；原始记录含下载期间的一个不完整启动和一个完整跑分，不作为两次成功启动或重复训练稳定性证明。详细绑定见 docs/verification/cpu/ddr_store_response_board.md 及 JSON。此前性能实现及失败试验见 ddr_performance.md/.json；未合入主工程。

以下为此前的板测对照及启动失败历史，均保留：

最新DDR板测对照已取得有效结果，但启动可靠性未解决。带Cache的5000次CoreMark实际两次为84.374481/84.374478，0.843745/MHz；保留相同Cache硬件、使用共享区不缓存属性的实际结果为10.231937，0.102319/MHz、488.666033秒。两者CPU-only均6558LUT，CRC和至少10秒检查通过，吞吐比8.246189；地址0x80000000/0x82000000、属性和重新链接载荷不同，不是同地址编译期Cache开关对照，非官方提交。编译期Cache=0没有有效板测分数。共享区一次保持复位下载后跑分通过，但恢复缓存镜像的同流程又出现init失败，不能宣称找到通用修复。当前缓存镜像e5503c690208已完成Program/Verify，最新自动启动FAIL，内部原因未知。用户改为自行打开串口助手短按复位查看，COM12已释放，不再要求长按、不再自动下载或占用串口。原SRAM发布包十文件未变；未写Flash。完整绑定见docs/verification/cpu/id_cache_board_coremark_comparison.md及JSON。

# TriHa CPU 状态

更新：2026-10-23。分支 `cpu/windows-baseline`，工作树 `D:/FPGA/TriHaRiscv-cpu-windows`。

以下为逐阶段历史；当前板测、镜像和未解决问题以上述最新记录为准。

缓存CPU独立DDR板级目标已通过实际100MHz后布线准入。控制器复位改由常开125MHz参考时钟的两级寄存器同步释放，并删除此前未承载逻辑的ref_clk整域异步分组，恢复ref→DDR的真实recovery/removal检查；不是扩大豁免。新完整实现CPU Slow/Fast setup +0.213/+3.617ns，hold +0.136/+0.082ns，MPW +3.655/+4.202ns；全部时钟域setup/hold/recovery/removal/MPW无违例，performance slack一致。60条Gray max-delay通过；独立解析同次原生XML，逐行绑定10条FDC约束、每组max/min三位、两corner共20组，skew最差余量+0.966ns、最大实际1.034ns，原2ns要求不变。CPU/Cache RTL哈希与stage4相同，软件O2/无LTO不变；没有新增CoreMark或板级成绩。当前综合上下文CPU-only6558LUT/3562FF/688RAM-LUT已含/0DRM/4APM，不能把整板15825LUT算成CPU。独立诊断包`build/soc/releases/cpu_ddr_board_189c51babb73`已生成并校验，尚未下载、未访问串口、未验证实际DDR训练；原CoreMark部署包10项文件不变。50项Python及既有PDS/STA解析检查通过；见docs/verification/cpu/id_cache_stage5.md/.json。下一步为独立板级DDR验收和后续多主fabric/可见性接入；本目标仍独占native端口。

I/D Cache已接入独立CPU/DDR板级顶层：真实125→100MHz HIGH带宽PLL、固定DDR控制器/PHY、71个DDR管脚和五通道CDC。真实O2固件在数字IP替身下两次完成私有/共享各8KiB自检和FENCE.I，四类监测故障通过，数据损坏负例被实际CPU store异常拒绝。实际PDS两轮完整布通，最新CPU Slow setup -0.155ns/2端点，Fast +3.521ns，hold +0.158/+0.100ns，MPW +3.655/+4.202ns；仍未100MHz准入。新增本域同步释放修复了普通板级逻辑的跨域复位违例，保留PHY相位调整FSM五个recovery端点（Slow -8.198ns/Fast -4.539ns）待处理。60条Gray实际max-delay路径均通过，但没有独立skew结果，保持UNKNOWN。CPU-only6478LUT/3562FF/688RAM-LUT已含/0DRM/4APM；Cache523LUT/763FF/11DRM，CDC67LUT/153FF/6DRM，桥3634LUT/3354FF，整板目标15746LUT/13221FF/33.5DRM/4APM，不能把整板资源算成CPU。没有新CoreMark成绩、位流或板测，原部署包未改动。证据docs/verification/cpu/id_cache_stage4.md及JSON。下一步只针对真实FIFO读指针→执行单元路径、厂商FSM复位约束传播和完整Gray skew核验；共享fabric准入仍未完成。

I/D Cache已进一步接通CPU100MHz→五通道异步AXI→固定125MHz DDR桥的数字通路，仍未物理准入。配置固定Git提交和4项SHA256，构建直接抽取Git对象，不覆盖旧Video文件或主工程。三组比例的CDC逐位/顺序/背压/在途复位通过；真实CPU缓存开启/旁路均通过原O2软件，22次成功store均等待native写入及读回，三次访问异常和真实桥初始化丢失后本地执行正确；native写已接受、CPU未响应时协调复位后整套软件重启通过。四类损坏/超时负例实际退出1，68项Python回归和独立证据核验通过。PDS原生映射总计10671LUT/7942FF/816RAM-LUT已含/33.5DRM/4APM，排除夹具；本上下文CPU6218LUT/3563FF、Cache514LUT、CDC67LUT/153FF/6DRM、DDR桥3691LUT/3358FF。不同综合上下文不算CPU优化；定向诊断不是CoreMark，也不是物理DDR/CDC时序。真实DDR/PLL/管脚、CDC物理约束、实际100MHz后布线及共享fabric仍待准入。未访问COM12或编程，原包保留。证据docs/verification/cpu/id_cache_stage3.md及JSON。

I/D Cache 已继续完成本地SoC接入与原生映射节点，仍未准入部署。新增triha_cached_soc/triha_cpu_memory_router，原ROM/SRAM/UART/System保留；I/D分别记录响应拥有者及未完成数，跨目标请求等待排空，DDR就绪只门控新请求，已接受AXI继续完成。真实CPU在缓存开启/旁路均通过ROM→SRAM启动、私有/共享DDR代码、FENCE.I、UART和三次访问异常后本地继续执行；数据损坏/看门狗负例实际退出1，60项Python回归通过。完整子系统综合层次7180LUT/4431FF/688RAM-LUT已含/27.5DRM/4APM，CPU6434LUT、Cache及传输519LUT、原本地存储183LUT、新路由44LUT；串行面积夹具排除，不用于时序验收。实际100MHz、CPU100MHz到DDR125MHz的CDC、最新DDR版本/共享fabric及板测仍待完成；已只读发现主工程DDR桥比本工作树新，不能静默复用旧版。原部署包和主工程保持不变，未访问COM12。证据docs/verification/cpu/id_cache_stage2.md及JSON。

I/D Cache 同批实施已完成首个功能/映射节点，**尚未准入或部署**。六级单发射、原预测配置保持不变；I/D各16KiB/两路/32B行，D写直达/写不分配并等待真实下级响应，私有DDR可缓存、共享区及非DDR绕过缓存。组件、共享AXI128、真实CPU的FENCE.I/三类访问错误/年轻store取消、缓存开关有序观察和数据/CRC负例均有日志；44项既有SoC脚本与6项新预检通过。同一可加载程序和固定AXI数字模型下，-O2/无LTO五次CoreMark从10646732降到4699674周期，短RTL0.469627675→1.063903581/MHz，吞吐+126.541926%；联合层次综合资源6632→6890LUT、4096→4326FF、0→11DRM36K等效，688RAM-LUT已含总LUT、4APM不变。它不是实际DDR/板级/官方分数，不能与原SRAM3.036877410/MHz直接排名；原部署镜像保持不变。可加载镜像完全相同，ELF仅非加载源路径字符串不同；1448448条计时WB及70839次store仅起始绝对计时值不同。实际100MHz后布线、完整ROM/SRAM/MMIO路由、真实DDR/CDC及板测仍待完成，不能把映射或综合估计当时序通过。备份cpu-before-id-cache-20261021；证据docs/verification/cpu/id_cache_stage1.md及JSON，执行计划docs/cpu/id_cache_plan.md。

最新32项load返回缓冲实验已完成取舍，**不选用，生产源码已恢复dc00f80**。GCC15.2-O2/无LTO、六级单发射及BTB512/BHT512/RAS4不变；短RTL CoreMark从1646428降到1621293周期，少25135周期、吞吐+1.550306%，但CPU-only从5933增到6178LUT(+245/+4.129445%)，FF3528→3561，分布式RAM-LUT688→708(已含总LUT)，0DRM/4APM。短测CoreMark/MHz3.036877410→3.083958297，名义100MHz下CoreMark/LUT0.051186203→0.049918393，下降2.476859%，因此在资源/性能门槛处结束，不再布线；候选100MHz未验证，不能写成时序失败或通过。三种组件正例/损坏负例、窄MUL回归、三组背压有序single/dual及IRQ、两次启动、CoreMark正例和CRC负例均有真实日志；四组single实际各30次命中。1448453条WB观察和70840次store仅起始绝对计时值不同，其余逐条一致，不是完整退休/ISA证明；cached-hit后真实load错误对更年轻store的整核取消场景仍未闭合，未豁免准入。原版100MHz报告用恢复后的输入重新独立复核通过，44项SoC Python与4项PC算术检查通过；28个vendor和9个基准原件哈希不变。板上仍为cpu_coremark_6ff82025b53d，未访问COM12或重新编程。完整实验源码、分析和721项输出绑定保存在build，版本内复现补丁、JSON及说明见docs/verification/cpu/load_return_buffer.md；备份cpu-before-load-return-buffer-20261020。所有新跑分均为5次短RTL仿真，5000次固件仅构建，非官方或板测分数。后续从此保留版出发，先用真实停顿/资源上界筛选有收益的方向，避免扩大缓冲后再长时间布线。

最新预译码/PC使能优化已完成三组实际100MHz验证：预译码单独−0.088ns，提前PC使能单独−0.092ns，组合版setup+0.006/+1.752ns、hold+0.073/+0.038ns、脉宽+3.655/+4.202ns，全部corner与复位/冻结绑定独立复核通过。组合版CPU-only6009LUT/3564FF/688分布式RAM-LUT(包含在总数)/0DRM/4APM，CoreMark仍1646428周期、3.036877410/MHz，完整计时WB/store轨迹和停顿均与原版相同，CRC负例拒绝。它比原版5933LUT增加76、最差setup余量比+0.113ns更小，未带来性能收益，故不选用；全部生产源码/配置/测试/运行器已恢复dc00f80，原100MHz重新独立复核通过。板上镜像保持cpu_coremark_6ff82025b53d，没有访问COM12或重新编程。三个实验的原始结果、测试、完整复现补丁及绑定见docs/verification/cpu/alu_pc_combined_timing.md和配套JSON；备份cpu-before-alu-predecode-20261020。实际最终瓶颈回到SRAM返回→LSU格式/旁路→ALU结果。后续先研究真实load-use停顿与同步SRAM/LSU边界，不直接删除必要互锁，不继续堆叠译码或布局种子；本轮不再追加物理试验。所有CoreMark数为短RTL仿真，完整5000次实际串口分数仍待用户现场结果。

上一轮分支/PC清理诊断已结束，**没有准入的新RTL或部署镜像**。仅分离PC算术的方案100MHz通过但增加12LUT、周期不变；共享比较器可将CPU降至5903LUT，但原约束下setup−0.029ns，板级LED寄存修复后的最终两组仍−0.292/−0.162ns。所有功能、CoreMark及轨迹检查通过不替代时序验收。已恢复生产RTL及板级文件至dc00f80，重新独立核对原部署版100MHz通过；板上仍是cpu_coremark_6ff82025b53d，未重新编程、未打开COM12。试验源码/报告保存在build，清单见docs/verification/cpu/branch_pc_timing.md和json，备份cpu-before-branch-pc-20261020。最终两组最差路径分别落在前端RAS使能和ALU，提出前移预译码及PC/RAS使能生成的后续方向，预测算法和六级单发射规格保持不变。该轮未提高主频或实际跑分。

最新优化版已下载为`cpu_coremark_6ff82025b53d`，实际Program/Verify返回0，两项成功标记齐全，未写Flash、未打开COM12。六级单发射、RV32IM/CSR、BTB512/BHT512/RAS4及PC索引两位预测算法、GShare=0、GCC-O2/无LTO均不变。复用四个17位部分积，符合unsigned16×16条件的MUL可提前旁路，宽/高位乘法和双发射保留原等待策略；SRAM/ROM响应用预寄存独热字选择，仍为一周期，没有增加CPU状态级。

本轮5次短RTL CoreMark1646428周期，相比父版1690888少44460周期；CoreMark/MHz从2.957026升为3.036877（吞吐+2.700391%）。CPU-only5933LUT/3528FF/688distributed-RAM-LUT/0DRM/4APM，总LUT已含RAM子集，较父版5912增加21；100MHz短测CoreMark/LUTs从0.050017357升为0.051186203（+2.336881%）。1448453个计时窗口WB观察事件及70840次真实store与父版对照通过，仅起始绝对计时读值及其store不同；不是完整ISA退休证明。完整5000次板级分数仍待用户串口，不用短RTL估算代替。

最终实际100MHz后布线`board-route-20261020T0824200693298Z`通过：Slow/Fast setup +0.113/+1.821ns、hold +0.160/+0.101ns、MPW +3.655/+4.202ns；recovery/removal无违例，performance slack与最差setup一致，原全部FDC哈希不变。四类MUL/保持/复位、窄宽资格、真实损坏负例、三组背压single/dual有序异常/写回/store及独立IRQ、415项访存和父版逐周期接口对照、8KiB两次启动、CRC正负例及44项Python检查均有证据。假相关改动收益仅0.002%而损失LUT效率、两个编译调度模型无收益、全宽提前旁路−1.130ns及中间布局失败均保留，未下载这些失败版。证据`docs/verification/cpu/operand_hazard.md`及json；备份`cpu-narrow-mul-100mhz-20261020`。COM12/115200/8N1/无流控，KEY0重跑约17秒，串口新增分母5933。下面为逐阶段历史，非当前配置。

此前板上换为5000次、GCC-O2、BTB512/BHT512/RAS4的CoreMark串口镜像`cpu_coremark_224be86f8972`，实际Program/Verify返回0，未写Flash，下载流程未打开COM12。串口增加CPU core LUTs=5912及CoreMark/LUTs（当次实测CoreMark除以5912），分母仅CPU核，含688个distributed RAM LUT子集，不含SoC外围。六级单发射、PC索引两位BHT/GShare关闭，无I/D Cache。512项BTB改为两bank直接映射原生异步RAM，未增加查询拍；RF有效写入数据门修复hold，未改变有效写入和CoreMark周期。

本镜像重新完整100MHz后布线通过，Slow/Fast setup +0.037/+1.752ns、hold +0.152/+0.100ns、脉宽 +3.655/+4.202ns，原IO/hold/多corner约束不变；CPU-only5912LUT/3486FF/0DRM/4APM。5次RTL预检1690888周期、标准CRC正确，短测2.957026 CoreMark/MHz，CRC负例实际exit=1；这些不是板级分数。打开COM12、115200/8N1/无流控、文本接收，短按KEY0，等待约17秒，接收完整实测分数及BOARD_PASS。完整实物分数仍待用户串口记录。新证据见`docs/verification/cpu/bpu512_o2.md`及json。旧O3包、原自检包及其备份标签保留，下文为历史记录。

此前六级单发射CPU已通过真实板级PLL/管脚100MHz后布线，并完成HIGH带宽PLL修正版cpu_board_df5475cbb154的实际Program/Verify、8KiB软件自检、持续UART运行和实体KEY0重启。Slow/Fast setup +0.023/+1.752ns、hold +0.155/+0.100ns、脉宽 +3.655/+4.202ns，全部无违例。该历史版CPU-only5977LUT/5172FF/64distributedRAM/0DRM/4APM，RV32IM/CSR、BTB32/BHT512/RAS8开启，无I/D Cache。该版CoreMark短RTL为2.965896/MHz、WB观察IPC0.870694；不是官方或板级CoreMark。用户明确不用恢复Video，当前保留CPU易失配置，未写Flash。

最新现场验收见`docs/verification/cpu/board_system_physical.md`及board_system_physical_acceptance.json；HIGH版STA/package见board_pll_high_route.json和board_pll_high_package.json。原912cb8d/5f5eb8c89efd虽通过STA和Program/Verify，实物PLL未锁、软件未启动，已保留失败与独立时钟诊断，不能部署该旧包。原外供100MHz片上系统5c4229a及385项输出保持不变。独立CPU分支和工作树保留，不自动合入主工程、push或修改Video源码。以下为逐阶段历史。

## 本批交付

- 固定来源28文件导入，逐项SHA256匹配；许可证和来源清单位于 `rtl/cpu/vendor/`。
- `rtl/cpu/triha_core.v` 按旧风格封装六级CPU，默认单发射；复位极性、命名与完整总线握手绑定，不增加额外流水。
- Windows ModelSim2020.4 已完成编译/展开/实际执行。PowerShell入口按真实程序退出码、软件输出和发射配置判定，保存每轮哈希与日志。
- 显式filelist没有编译Xilinx原语文件或追踪模块；Pango原生资源、映射与后续隔离后布线见下文，100MHz尚未通过。
- 已按用户确认的RV32/ILP32要求安装Windows GCC15.2.0预编译包，SHA256匹配发布元数据。`check_toolchain.ps1`实际完成RV32I/ILP32和RV32IM_Zicsr/ILP32编译、链接及ELF32检查；探针软件未执行。
- CoreMark基准版本1.0的9个固定源码/许可文件已导入；源码补丁标签v1.01，Git blob与SHA256逐项核对。原始算法不变，平台移植与构建生成的formatter适配独立维护。
- 本机GCC实际生成并运行裸机软件，启动建立gp/sp、mtvec、关闭中断、清零BSS；ELF加载器先将TCM填0xa5再复制文件段，data/BSS自检在两模式通过。当前data由测试加载器直接装入VMA，不是ROM搬运启动。
- 已跑通CoreMark performance单/双模式和validation单模式；计时用真实cycle CSR，周期与仿真观察窗口一致，标准CRC全部匹配。

## 本机实际仿真

| 测试 | 结果 | 观察 |
|---|---|---|
| 单发射 | PASS | 程序退出0；3315周期、2151次issued、0配对 |
| 双发射 | PASS | 程序退出0；3118周期、2151次issued、274配对周期 |
| 实际失败程序 | 正确拒绝 | CPU通过CSR返回1；单独宿主入口返回1 |
| 周期超时 | 正确拒绝 | MAX_CYCLES=8，实际第9周期终止；单独宿主入口返回1 |

两个正例均有十项软件检查输出，包含乘除法、移位、比较、字/字节访问。观察范围仅是固定程序和指定配对检查；issued不是instret，不计算退休IPC，不作为CoreMark。四项运行输入在本次运行前后未变。

证据索引：`docs/verification/cpu/windows_baseline.json`。首个RED记录保留于build：封装缺失时vlog实际返回2。首次加入封装后程序完成，但`-onfinish stop`触发onbreak返回3；改为`-onfinish exit`后正常结束由宿主核对程序状态。负例证明宿主不会因模拟器返回0就接受失败程序。

## GCC固件与CoreMark短测

同一ELF、RV32IM_Zicsr/ILP32、GCC15.2.0、-O3、无LTO、2000字节总数据、5次迭代；使用128KiB测试TCM。完整编译参数、源/生成文件/ELF/日志哈希见`docs/verification/cpu/coremark.json`索引中的实际result.json。

| 模式 | 测量周期 | WB完成事件 | 观察IPC | CoreMark/MHz短测估算 |
|---|---:|---:|---:|---:|
| 六级单发射 | 1,659,900 | 1,467,843 | 0.884296 | 3.012230 |
| 六级双发射 | 1,380,497 | 1,467,843 | 1.063271 | 3.621884 |

双发射相对单发射周期减少16.832520%，相同模拟频率下吞吐提高20.239305%。两模式标准CRC均为seed e9f5、list e714、matrix 1fd7、state 8e3a。validation单模式1次迭代为333,416周期，CRC为18f2/e3c1/0747/8d84。

上述是RTL仿真，不是板级结果。5次短测保留“至少10秒”的原始警告，因此不能作为官方CoreMark分数。TCM时钟设置100MHz不等于Pango后布线100MHz已通过，也不能与旧工程不同编译器/存储/ISA配置的结果直接作性能结论。

IPC按两次cycle CSR读入边沿之间的WB完成事件/周期计算，不用issued替代。14条指令探针在两模式精确通过，包含循环、branch、store、load，双发射轨迹包含第二条完成通道；它只验证该计数器的定向范围。现核没有架构minstret实现，完整ISA、异常、取消和退休语义仍待证明。

新增负例均被宿主返回1正确拒绝：期望15而实际14的计数错误、非法指令（真实mtvec输出cause=2/value=ffffffff）、build副本中预期list CRC e714→e715（基准errors=1且程序退出1）。原始CoreMark文件保持不变。共同TB修改后的原始四项冒烟也已回归通过，产品CPU RTL未在本批改变。

## CPU-only Pango资源与映射（裁剪前基线）

Windows PDS2022.2-SP6.4自带ADS；器件PG2L100H/FBG676/-6。直接以`triha_core`为顶层，排除TCM、Cache、SoC、DDR、NPU、Video。两模式compile/synthesize/dev_map均成功，实际展开参数及全部冻结输入/输出哈希复核通过，CPU源文件与CoreMark测试相同。

| 配置 | 综合LUT | 映射LUT | FF | DRM36K | APM |
|---|---:|---:|---:|---:|---:|
| 六级单发射 | 8,819 | 8,819 | 6,113 | 0 | 4 |
| 六级双发射 | 10,192 | 10,191 | 6,298 | 0 | 4 |

面积口径为CPU顶层逻辑（包含复位极性适配的1个LUT），不包含测试存储或夹具。两模式均有224个独立IO原语，单独报告，不混入LUT/FF。双发射相对单发射映射LUT增加1,372（15.5573%）、FF增加185（3.0263%）；频率尚未实测，不能据此前短RTL吞吐直接得出板级性价比。

实际乘法器为一组33×33运算，映射成4个`GTP_APM_E2`，不是LUT乘法器。没有DRM或分布式RAM，当前通用寄存器堆与预测表使用FF/LUT。单发射映射中前端含4,565 LUT/3,740 FF，其中预测模块3,221 LUT/3,350 FF；这些是包含下级的层次统计，不能相加作总量。第二执行相关模块仍有1,131 LUT/32 FF，第二流水控制39 LUT/77 FF；模块名不能证明逻辑无用，需先核对分支、旁路、异常/取消依赖后再专化，禁止直接删除。

证据索引：`docs/verification/cpu/pango_resources.json`，原始snr、dmr与日志位于其中两轮独立运行目录。初轮`DUAL_ISSUE=1`格式被PDS静默忽略，实际展开为0，该轮已排除；改为名称/数值对并强制核对真实展开参数。最终解析器还验证缺失报告、错误标记、缺失/错误参数均被拒绝，工具缺失负例返回1。双发射映射继续优化掉1个LUT，综合与映射统计分别保留。

该基线FDC仅声明10ns组件时钟，没有正式CPU总线I/O和板级管脚约束，不能称100MHz通过。后续专化及隔离物理诊断见下节；不得降低100MHz目标或用综合估算替代实际时序。

## 单发射执行路径裁剪（当前版本）

在固定连接源码的派生Verilog`triha_cpu.v`中加入条件生成：单发射不生成第二执行单元，其输出接常量；双发射保留。原始vendor字节及许可未改，除模块名/说明与此条件生成外没有其他连接差异。共享CSR、异常、取消和第二流水控制保持原逻辑。

| 模式 | 父版映射LUT/FF | 当前映射LUT/FF | DRM/APM |
|---|---:|---:|---:|
| 六级单发射 | 8,819 / 6,113 | 7,709 / 6,017 | 0 / 4 |
| 六级双发射 | 10,191 / 6,298 | 10,511 / 6,298 | 0 / 4 |

单发射实际减少1,110 LUT（12.5865%）和96 FF，映射报告中第二执行单元已消失；保留的第二流水控制缩至7 LUT/13 FF。双发射仍有第二执行单元，实际LUT比父版增加320，FF不变；行为相同不能据此推断资源相同，本轮不宣称双发射面积收益。两模式均为CPU-only，不含TCM或SoC，224个IO仍单独统计。

定向差分验证在三组背压种子（37、1234567、271828）×单/双模式全部通过；逐周期比较全部核外部输出、有效WB载荷、预测更新和11项CSR状态。程序通过取指错误、非法指令、EBREAK、load/store未对齐、load/store总线错误、M-mode ECALL、外部IRQ及mret；每轮九类事件mask均为511，并实际发生取指/数据背压。单发射不活动通路断言通过。故意把双发射第二路写回清零，在第24周期被对照拒绝，宿主返回1。

本机GCC CoreMark两模式均与裁剪前等周期、等WB完成数、等标准CRC：单发射1,659,900周期/IPC0.884296/短测3.012230 CoreMark/MHz，双发射1,380,497周期/IPC1.063271/短测3.621884。validation单模式、startup两模式、14指令探针两模式和原四项冒烟回归通过。此为短RTL测量，不是官方分数；差分范围也不等于完整ISA/形式证明。

证据索引`docs/verification/cpu/single_exec_trim.json`保存冻结输入/输出哈希、父版绑定、实际差异检查、反例及资源报告。原CoreMark和Pango资源索引保留为父版基线。随后执行的隔离后布线见下节。

## 100MHz隔离后布线（实际失败）

冻结生产RTL为`3caa32d`，完整compile/synthesize/dev_map/pnr/report_timing成功，PDS实际返回0，约303秒结束；主详细布线第116次迭代到0未布通，随后完成hold修复。不是工具崩溃或超时。最终setup违例，状态为TIMING_FAIL，100MHz没有通过。

| 检查 | Slow角余量/ns | Fast角余量/ns |
|---|---:|---:|
| Setup | -15.557 | -7.704 |
| Hold | +0.126 | +0.104 |
| 最小脉宽 | +4.346 | +4.345 |

performance slack与最差setup一致。该轮采用CPU直接顶层、自动I/O布局；假定同钟输入/输出max2ns、min0.5ns、10ns时钟，声明setup/hold不确定度0.1/0.05ns（报告最差路径的有效setup不确定度为0.150ns），没有false path或multicycle例外。功能端口没有未约束的Timing-4086/4087通知。此边界不是正式SoC或板卡契约，不能把工具的频率估计当可部署主频。

最差路径从`data_error_i`进入共享异常/取消控制，经前端重定向和预测查找，终止于`u_cpu/u_frontend/u_fetch/pc_f_q[24]`。23级逻辑，逻辑延迟4.886ns、布线延迟21.343ns（81.372%）；`nt_data_error_i`网络11负载/5.704ns，`branch_info_request_w`网络52负载/4.227ns。需要同时检查接口管脚引入的外围长连线与核内反馈串联，不能仅归因于六级流水、器件或综合器。

另从同一冻结PNR数据库点选明确CLK/I4引脚，确认一条纯核内违例：译码FIFO的`rd_ptr_q[0]`寄存器→取指`pc_f_q[24]`寄存器，余量-8.827ns、21级逻辑，逻辑4.480ns/布线13.841ns。该定向报告没有过滤忽略通知，原数据库哈希未变；它只是一个核内反例，不是全核内最差余量。最初被工具忽略的集合过滤及超时的大集合查询均不用于结论。由此确认不能只调整外围IO位置，下一步重点分析前端重定向、预测查找和下一PC选择串联，并验证任何切断路径方案的退休、异常及CoreMark代价。

此轮完整I/O约束改变了工具映射选择，映射为7,123 LUT/6,017 FF/0 DRM/4 APM；它与前面时钟单独约束的7,709 LUT口径不同，不作为新增RTL面积优化。没有生成bitstream或编程板卡。冻结输入、实际输出及主详细布线结果已复核，索引为`docs/verification/cpu/route_100.json`，含最终报告和日志链接。

## 前端与宽数据控制链诊断（第3轮最优setup检查点）

保持六级主流水、单发射默认、RV32M/CSR、基础预测与旁路；外层MMU/SUPER关闭、100MHz及原完整I/O/hold约束不变。原始vendor字节及许可不变，维护派生连接清单升级为五项哈希绑定。三个独立步骤均完整重新compile/synthesize/dev_map/place/route，没有导入旧数据库。

1. 前端复用现有寄存重定向分支，取消即时重定向PC绕过到预测查找。内部fetch的SUPPORT_MMU选择仅复用该时序机制，外层地址翻译仍关闭，没有启用架构MMU。
2. issue按fetch有效信息和已注册期望PC选择指令/PC/fault载荷；取消、异常仍门控原发射有效位。此步骤单独未改善全局时序，不能称收益。
3. 乘法器和CSR宽数据寄存器采用现有执行单元的独立采样方式，保留hold、有效、异常、CSR读副作用和提交写控制。原乘法器不再需要的操作识别信号已删除。无新主流水级，后两步没有额外CoreMark周期。

同10ns、I/O max2/min0.5ns及原hold/multicorner约束的实际结果如下；各轮网表和布局不同。

| 轮次 | Slow/Fast setup /ns | Slow/Fast hold /ns | Slow/Fast脉宽 /ns | CPU LUT/FF |
|---|---:|---:|---:|---:|
| 父版完整I/O布线 | -15.557 / -7.704 | +0.126 / +0.104 | +4.346 / +4.345 | 7123 / 6017 |
| 寄存重定向 | -7.577 / -1.724 | +0.108 / +0.097 | +4.346 / +4.345 | 7744 / 6017 |
| 再分离issue载荷 | -7.776 / -1.923 | +0.107 / +0.102 | +4.346 / +4.345 | 8072 / 6017 |
| 再分离乘法/CSR宽数据（当前） | **-5.918 / -0.712** | +0.113 / +0.104 | +4.346 / +4.345 | **8057 / 6017** |

当前最差setup较父版改善9.639ns，但100MHz仍未通过。最新完整流程约258秒，主详细布线第157次迭代到0未布通，原生PDS返回0、宿主正确返回2/TIMING_FAIL。三轮DRM均0、APM均4；224个IO单独统计，不含测试存储、Cache或SoC。当前LUT比同完整I/O父版增加934（13.1125%），不能宣称面积优化。仅第一步的另一次时钟单独约束map为单/双7396/10041 LUT，不能混作当前候选或完整I/O的资源收益。

最新真正最差路径已完全位于核内：`u_issue/u_pipe0_ctrl/valid_e2_q`→异常/取消→预测BTB更新选择→`btb_target_q[11][16]`的CE；15级逻辑、逻辑2.015ns/布线13.320ns（86.860%）。这条全局最差路径直接证明外围I/O不是唯一问题。第二轮数据错误到APM/CSR路径已不再居首；下一步应把预测训练与取指/取消的组合反馈分开，而非继续任意调整布局参数。

新增独立存储按序测试：每次原核/候选执行独立维护镜像、接纳背压和0~3拍响应等待；三组种子×单/双发射的844次WB完成载荷、91次store和同步异常轨迹逐项相同。IRQ/mret另作自检，九类trap mask511通过；异步中断入口会随周期变化，不伪称IRQ逐条等价。旧重定向时序的逐周期事务/WB/预测/11项CSR状态对照也在三组×两模式通过。空闲地址变化不代表请求：`-CompareIdleBus`保留旧诊断并在无请求时暴露0→0x14差异，所有有效及停顿中的事务载荷仍严格比较。

前端、issue、乘法数据和CSR数据测试均保留先失败记录；四种乘法的独立整数模型完成129次值检查/42次hold。破坏真实load返回、乘法结果、第二路写回、CoreMark CRC的负例均正确拒绝。startup、14指令完成探针、四项冒烟及CoreMark validation通过。此范围仍不是完整ISA或形式证明。

| 模式 | 当前CoreMark周期 | WB完成事件 | 观察IPC | CoreMark/MHz短RTL估算 | 对父版周期代价 |
|---|---:|---:|---:|---:|---:|
| 单发射 | 1682255 | 1467843 | 0.872545 | 2.972201 | +1.346768% |
| 双发射 | 1390193 | 1467843 | 1.055856 | 3.596623 | +0.702356% |

三步骤的同ELF CoreMark均等周期、等WB事件数、等标准CRC；代价来自第一步的寄存重定向。仍是CoreMark1.0的5次迭代RTL短测，保留时长警告，不是官方分数或板级主频。单模式validation1次为337690周期，CRC通过；最终CPU核心仍未达到可部署验收条件。

证据索引：`docs/verification/cpu/frontend_timing.json`。第一轮PDS将逻辑表达式参数打印为1'b1，旧32位限定解析器返回FAIL；未回写旧result，另存只读核验收据，确认28项冻结输入、484项输出及实际最终报告。修正后的解析器还拒绝寄存选择关闭、误启外层MMU、错误位宽，并在后两轮实际运行使用。所有轮次保留源/输出哈希、实际阶段成功标记及报告，未编程板卡。

## 预测训练寄存诊断（第4轮）

完整70位训练事件在进入预测器前寄存一拍，误预测请求及不带误预测的taken/not-taken更新都逐拍保留；没有改六级主流水。四类call/return/jump/条件分支事件整包测试先RED后PASS，三种背压种子×单/双发射的同步异常按序对照、独立IRQ自检及旧时序逐周期回归均PASS。旧时序miter现在显式关闭REGISTER_REDIRECT和REGISTER_TRAINING；不能把它当新时序的逐周期证明。

同约束重新完整实现，原生返回0、布线173次主详细迭代到0未布通，实际setup Slow/Fast -6.552/-1.191ns，hold +0.122/+0.124ns，脉宽 +4.346/+4.345ns。CPU-only8286 LUT/6084 FF/0 DRM/4 APM，224 IO单独报告。比第3轮多229 LUT/67 FF且全局setup差0.634ns，**不是时序收敛或面积收益，不作为已验收部署版**。

CoreMark两模式仅各增加4周期：单1682259周期/观察IPC0.872543/短估算2.972194 CoreMark/MHz；双1390197/1.055853/3.596613。WB完成事件仍1467843、标准CRC相同，validation通过；这些仍是RTL短测。

第4轮最差从data_error_i到LSU mem_rd寄存器，11级逻辑，逻辑2.449ns/布线14.793ns；前两段网络分别5.660/3.895ns。集合筛选被PDS忽略、5926时钟引脚枚举查询180秒超时，均不用于核内结论。随后只从明确valid_e2_q/CLK起点查询，工具接受且冻结DB未变，确认到LSU mem_rd的纯核内违例-4.500ns；它是一个定向反例，不是全核内最差报告。由此下一步应将取消放到发射许可末端，避免取消先改变类别选择、再串过冒险检查及仲裁；仍必须关闭异常周期的新事务。

第4轮冻结证据：`docs/verification/cpu/training_timing.json`。第3轮最优setup检查点保留在提交2370a20，主工程未合并本批CPU。当前不得把工具成功或局部控制链切断当作100MHz通过。

## 末端取消诊断（第5轮）

issue的类别/寄存器冒险检查先独立计算候选资格，取消/CSR重定向在末端统一关闭fire/accept；原IRQ inhibit选择保持不变。定向RED捕获旧版取消会改变类别，修改后确认数据/类别保持、最终六类执行有效位关闭。三种背压种子×单/双模式的逐周期事务/WB/预测/11项CSR状态对照、独立存储按序异常对照和IRQ自检通过；真实load/第二路写回错误负例正确拒绝。CoreMark仍1682259/1390197周期，WB/CRC相同，startup、14指令探针、validation和四项冒烟通过，没有额外性能代价。

同完整I/O约束的CPU-only映射为7256 LUT/6084 FF/0 DRM/4 APM，较第4轮少1030 LUT；224 IO另计。但实际setup Slow/Fast **-10.564/-3.572ns**，hold +0.108/+0.103ns，脉宽 +4.346/+4.345ns，时序显著变差，不能称收敛。原生返回0，主详细布线429次迭代到0未布通；PNR8分41秒、完整流程603.513秒。

最差仍从data_error_i进入异常/取消，再到LSU mem_wr_q[2]：13级逻辑、逻辑2.517ns/布线18.747ns（88.163%）。逻辑面积减少不能推导物理时序改善。证据索引`docs/verification/cpu/late_cancel_timing.json`保留实际输入/输出、测试、报告和最差路径；所有旧结果不回写。

后续改为单因素物理布局诊断：相同RTL、时序FDC和seed1，只增加PDS官方PAP_REGION层次约束，尝试两个相邻时钟区域；运行入口`run_route.ps1 -Compact`。在工具转换绑定与实际最终时序核验前，不宣称区域约束生效或100MHz通过。规划见`docs/cpu/physical_compact_plan.md`。

## 同RTL区域布局诊断（第6轮）

第5轮RTL和原时序FDC逐项SHA256相同，只增加PAP_REGION物理约束。映射PCF生成10484个唯一CPU叶节点绑定，范围(0,64,100,199)，无固定site约束；映射报告也保存了各叶节点PAP_REGION。工具对层次对象给出“非GTP、可能不生效”的早期提示，并对已继承绑定给出2118条重复约束提示，均保留在日志；没有独立逐单元坐标审计，不用输入属性本身冒充验证。

原生返回0，150次主详细迭代到0未布通，PNR3分27秒、完整282.539秒。CPU映射仍7256 LUT/6084 FF/0 DRM/4 APM。实际setup Slow/Fast **-7.044/-1.567ns**，hold +0.113/+0.103ns，脉宽 +4.346/+4.345ns。比同RTL未约束区域第5轮改善3.520ns，但仍未通过100MHz；不能把布线耗时缩短当频率验收。

新最差路径从data_error_i经LSU返回值选择、E2旁路，进入除法器输入比较与初始减法，19级逻辑、逻辑3.569ns/布线14.204ns。源码确认LSU将fault地址和正常load数据复用同一个writeback总线，导致错误控制进入并不应消费的旁路数据。下一步分离旁路数据与fault提交载荷，保留原badaddr/mtval路径，不增加load返回寄存级。证据`docs/verification/cpu/compact_region_timing.json`绑定第5轮同RTL及实际区域转换/报告。

## Load旁路与fault载荷分离（第7轮）

LSU额外导出纯load数据，仅用于E2旁路；原writeback完成总线继续在fault时传badaddr，WB捕获、异常编码和mtval路径不变。旁路数据选择使用已注册E2有效位，目的tag、stall和提交门控仍按原逻辑工作；没有新增寄存级或load延迟。定向测试保留fault、ack、stall三类RED；修改后在错误数据为X时也确认WB无效/目的寄存器关闭、badaddr与mtval精确。三种种子×两模式逐周期事务/WB/预测/11项CSR状态、独立存储按序异常及IRQ通过，真实错误负例正确拒绝。

同区域/同10ns约束重新实现，CPU-only7289 LUT/6084 FF/0 DRM/4 APM，224 IO另计；比第6轮多33 LUT、FF不变。原生返回0，277次主详细迭代到0未布通，完整430.784秒。实际setup Slow/Fast **-4.918/-0.038ns**，hold +0.116/+0.104ns，脉宽 +4.346/+4.345ns，仍未通过100MHz。相对第6轮改善2.126ns，相对最早完整I/O基线改善10.639ns；不是部署验收完成。

CoreMark、WB事件数和CRC完全不变：单1682259/观察IPC0.872543/短估算2.972194，双1390197/1.055853/3.596613。startup、14指令探针、validation、冒烟与故障注入均符合预期；均为RTL测试。

新最差从data_error_i经过异常/取消和发射有效位，进入LSU地址格式选择及32位加法，终止于mem_addr_q[28]；17级逻辑、逻辑2.835ns/布线12.701ns。源码中地址格式由opcode_valid_i参与选择，宽请求数据也在错误时清零。下一步将请求地址/数据/属性与有效控制分开，仍须保持所有有效及停顿中的事务载荷，保持fault取消和精确异常。证据`docs/verification/cpu/load_bypass_timing.json`。

## LSU请求载荷与有效控制分离（第8轮）

地址格式和store数据仅由原始opcode决定，晚到的issue valid只限定最终读写控制。地址、写数据、cacheable使用原有65位寄存器独立采样；响应等待及未接纳请求继续hold，fault仍关闭原请求控制，FIFO badaddr/异常提交保持原路。没有新增寄存器级或load延迟。定向RED先捕获无效LW错误选用S型立即数；GREEN覆盖无效store无写使能、未接纳载荷保持及load fault取消/精确badaddr。三组背压种子×单/双模式的逐周期事务/WB/预测/CSR和按序同步异常对照、IRQ及实际故障注入均符合预期；15项正例和4项预期拒绝的实际输入/输出哈希均已核验。

CoreMark保持单1682259/双1390197周期、1467843次WB完成与标准CRC不变；单模式观察IPC0.872543、CoreMark/MHz短RTL估算2.972194。startup、14指令计数探针、validation和冒烟通过。仍非官方分数、完整ISA证明或板级结果。

同10ns、原完整IO/hold/multicorner和区域约束重新完整实现，原生PDS返回0，主详细布线139次迭代到0未布通，完整324.514秒；宿主正确记录return2/TIMING_FAIL。冻结29项输入、360项输出和独立只读复核一致。实际setup Slow/Fast **-4.631/-0.097ns**，hold +0.109/+0.122ns，脉宽 +4.346/+4.345ns；performance slack与最差setup一致。最差setup较第7轮改善0.287ns，但Fast角稍差，Slow违例端点2649→3991，**100MHz仍未通过**。

CPU-only映射8346 LUT/6084 FF/0 DRM/4 APM，224 IO另计；较父版LUT增加1057（14.5013%）、FF不变，不能称面积优化。层次归属中LSU为178→150 LUT、issue为1148→2243 LUT，其余模块也重新映射，不能把整个增量解释成LSU直接新增硬件。

新的全局最差为纯核内：译码FIFO rd_ptr_q[0]→完整PC匹配/载荷选择→寄存器读取→分支比较→issue pc_x_q[29]；23级逻辑，逻辑3.599ns/布线10.684ns。payload1_selected_w有1554负载，且路径包含3.364ns的专用线段。之前data_error→LSU地址格式链不再是本轮首要路径，不据此宣称它的所有路径都已通过。下一步将载荷lane选择与完整PC命中分开；依据现有FIFO固定pc0低三位000、pc1为100的契约，用已寄存期望PC的bit2选择数据，完整PC/valid/取消继续限定发射和accept。需先建立错PC、空lane、取消及奇偶lane的RED/GREEN，再做同样的事务/异常/CoreMark和实际STA核验，不新增主流水级、不降低约束。

证据索引：`docs/verification/cpu/request_payload_timing.json`，包含原始最终报告、实际退出码和独立复核路径。本批未合并主工程、未生成bitstream或编程板卡。

## 指令载荷lane与PC命中分离（第9轮，当前最优setup）

依据现有fetch FIFO固定pc0低三位000、pc1为100的对齐契约，直接由已注册期望PC的bit2选择opcode/PC/fault/分类数据；完整PC比较和fetch valid只限定发射资格及消费，原取消、IRQ inhibit和accept继续生效。去除三路宽数据零化选择和重复CSR invalid mux，没有新增寄存器级。最终同一测试/runner在冻结父版中RED，候选GREEN，覆盖错PC、空lane、取消、奇偶lane和完整fault载荷；三种背压×两模式逐周期及按序异常、IRQ、访存故障、17项正例与4项预期错误拒绝通过，输入输出哈希已核验。它们仍是定向仿真，不代替完整ISA证明。

两模式CoreMark周期、WB及CRC仍与第8轮完全相同；单1682259周期、观察IPC0.872543、短RTL估算2.972194 CoreMark/MHz，双1390197/1.055853/3.596613，非官方或板级结果。

同10ns及原IO/hold/multicorner、同区域约束完整重新实现，原生PDS返回0，宿主return2/TIMING_FAIL，主详细布线115次迭代达到0未布通，PNR2分52秒、完整247.215秒。冻结29项输入/312项输出及独立复核一致。setup Slow/Fast **-3.064/-0.045ns**，hold +0.106/+0.104ns，脉宽 +4.346/+4.345ns；performance一致，**100MHz仍未通过**。Slow最差比第8轮改善1.567ns，但违例端点3991→4156，不能把WNS改善概括为所有路径改善。

CPU-only7175 LUT/6084 FF/0 DRM/4 APM，224 IO另计；较第8轮减少1171 LUT（14.0307%）、FF不变，较第7轮也少114 LUT。issue层次归属2243→1119 LUT，未靠减流水级、去M扩展或降低时钟实现。

新的最差为FIFO指令源寄存器索引bit1→通用FF寄存器堆读出/旁路→JALR目标→issue pc_x_q[30]，10级逻辑、逻辑1.916ns/布线10.696ns（84.808%）。读地址位139负载/1.995ns，读选择网络39负载/1.280ns。下一步评估复用已有FPGA异步读分布式RAM结构及PDS原语，在单发射配置替代FF大mux，保留零读延迟、同步复位可见性、x0和写回/旁路语义；双发射保留已测实现。必须先用独立寄存器模型验证复位、连续写、同址读写及x0，并核对真实器件映射，不能把仿真模型当硬件映射证明。

证据：`docs/verification/cpu/lane_payload_timing.json`。未合并主工程、未编程板卡。

## 单发射异步读分布式寄存器堆（第10轮，资源诊断）

单发射采用原生32×2分布式RAM的两份32×32副本，各服务一个异步读口；31位已写标记在同步reset时清零，掩盖RAM残留内容，x0恒零，无新增读寄存级。单发射次写口必须为0，仿真断言验证此集成契约，不声称该后端具有通用双写语义；双发射回退原通用实现。适配哈希清单现在为8项，原始28文件不变。ModelSim直接读取已安装PDS的真实原语模型，前后SHA256绑定，不复制/改写工具模型，也未新增工具链。

组件独立数组oracle完成2458次读值检查，覆盖连续/同址写后读、两读口、x0、同步及热复位，真实输出损坏被拒绝。原FF组件映射1695 LUT/992 FF/0分布式RAM，实际资源目标RED；新组件115 LUT/31 FF/32分布式RAM单元，实际map GREEN。这是单发射组件边界及工具资源口径，不能直接拿其IO/四读口裁剪比例代替整核面积比较。整核三种背压×两模式的逐周期事务/WB/预测/CSR和按序异常、IRQ、请求保持/fault及负例通过，连同组件共20项正例、6项预期拒绝的输入输出及外部模型哈希核验通过。仍不是完整ISA/形式证明。

CoreMark、WB完成和CRC仍与第9轮完全相同：单1682259周期/观察IPC0.872543/短RTL估算2.972194 CoreMark/MHz，双1390197/1.055853/3.596613；startup、retire探针、validation和冒烟通过。非官方分数或板级结果。

原100MHz、完整IO/hold/multicorner及区域约束重新完整实现，CPU-only **6833 LUT/5123 FF/32分布式RAM单元/0 DRM/4 APM**，224 IO另计；比第9轮减少342 LUT、961 FF，未删M扩展或放宽约束。原生PDS返回0，主详细布线123次迭代到0未布通，完整217.667秒，宿主正确返回2/TIMING_FAIL；冻结30项输入/329项输出和独立核验一致。

| 实际检查 | Slow/ns | Fast/ns |
|---|---:|---:|
| setup | **-4.659** | **+0.071** |
| hold | +0.109 | +0.105 |
| 脉宽 | +4.346 | +4.345 |

Fast角setup已无违例，但Slow最差比第9轮变差1.595ns，100MHz仍未通过；第9轮保留为最优WNS检查点，不能将寄存器堆/面积改善等同全局时序收益。新的最差由data_ack_i经异常取消、div_opcode_valid进入除法器dividend_q[0]的CE：10级逻辑，逻辑1.902ns/布线13.378ns（87.552%），输入网23负载/4.490ns，除法有效位68负载、末端CE48负载。此前寄存器堆读出不再是本轮全局首要路径，但不宣称全部RF路径已通过。

下一步依据该真实路径分离除法器宽数据初始化与晚到启动有效位，保持原除法算法、缓存命中结果及精确输出周期。尤其不能在空闲采样时破坏上一运算的缓存tag/结果；需先建立DIV/DIVU/REM/REMU、零除、溢出、连续/重复运算和无效周期的独立整数oracle及对原模块逐周期对照，再接整核。

证据`docs/verification/cpu/distributed_regfile_timing.json`；新组件/整核源码已处于同一CPU工作树，尚未合并主工程，未生成bitstream或编程板卡。

## 复用原除法器的寄存入口（第11轮）

原除法器存在重复运算缓存和忙碌中重启语义，本轮不改写其迭代状态或缓存tag：新增完整144位载荷及有效位入口寄存，数据每拍独立采样，原模块保持字节不变。输出流严格延后一周期，仅DIV/REM延迟增加一拍，六个主流水级和load时序不变。实际综合裁去原模块未用的字段，整核FF增加82。

同一最终组件测试对原直接连接RED、对封装GREEN：308组四类整数运算（独立64位整数oracle，包含零除/溢出/负数）、16次缓存命中，加1000周期忙碌重启/连续有效和复位扰动，312次完成结果及完整valid流恰好移位一拍；真实输出损坏被拒绝。三种背压×单/双模式按序异常和IRQ、请求保持/fault、组件RF及整核20项正例/6项预期拒绝通过。旧逐周期miter明确REGISTER_REDIRECT/TRAINING/DIVIDER_INPUT均为0，只覆盖旧时序；不能把它称为新默认逐周期等价。新默认使用按序整核测试和除法器移位miter。

CoreMark性能测量区间仍为单1682259/双1390197周期、1467843次WB完成、CRC相同；观察IPC/短RTL估算仍0.872543/2.972194及1.055853/3.596613。startup、retire探针、validation、冒烟也通过。该基准区间没有观察到新增周期，不代表所有含DIV/REM程序没有那一拍代价；仍非官方分数或板级结果。

原100MHz、IO/hold/multicorner和区域约束完整新实现，展开日志及独立复核均确认CPU REGISTER_DIVIDER_INPUT=1、wrapper REGISTER_INPUT=1。CPU-only **6621 LUT/5205 FF/32分布式RAM单元/0 DRM/4 APM**，224 IO另计；比第10轮少212 LUT、多82 FF。原生返回0，宿主return2/TIMING_FAIL，主详细布线129次到0未布通，完整255.994秒；冻结31项输入/342项输出及独立复核一致。

实际setup Slow/Fast **-3.531/+0.622ns**，hold +0.101/+0.049ns，脉宽 +4.346/+4.345ns，performance一致。较第10轮Slow改善1.128ns（新网表/新布局），但仍比第9轮最优WNS差0.467ns，**100MHz未通过**。

最差转到data_ack→异常取消→前端flush→译码FIFO的pc_q写使能，末端89负载；10级逻辑，逻辑1.999ns/布线12.140ns。原FIFO将宽PC/指令数据写入放在flush控制分支之后；下一步只让空闲槽的宽payload提前采样，实际push、计数、指针、valid和分类/fault元数据保持原逻辑。满队列必须保持所有有效payload，空闲时不能改变原IRQ inhibit所依赖的元数据，也不新增延迟。

证据`docs/verification/cpu/divider_input_timing.json`。旧物理结果用新复核脚本读取时，入口寄存引入前须加`-LegacyDivider`；新运行默认严格要求寄存开启。未合并主工程或编程板卡。

## FIFO空槽宽载荷采样（第12轮）

复用原FIFO控制，只让wr_ptr指向的空槽在非满时采样PC/指令宽数据，独立于晚到push/flush；满队列和有效数据保持原行为。计数、指针、valid和fault/分类metadata仍按原控制更新。六级配置会在valid=0时对残留opcode输出原始CSR类别，原IRQ inhibit会读取此值；因此另存每word/entry一位历史CSR分类（共4位），只在原非flush入队时更新，保留原始decoder的分类，不让推测空槽数据改变中断行为。未新增主流水或FIFO延迟。

同一最终测试对原FIFO RED、新FIFO GREEN；2023个周期比较原全部控制/metadata、所有有效PC/数据和残留CSR类别，覆盖满/部分pop/flush及无效X载荷，真实损坏被拒绝。三种背压×单/双模式逐周期旧时序、按序同步异常和IRQ自检均通过；共21项正例/6项预期拒绝的输入输出核验通过，原始28文件保持不变。CoreMark周期/WB/CRC、startup、retire、validation和冒烟均与第11轮相同，非官方或板级结果。

同100MHz/IO/hold/multicorner和区域约束完整重新实现，CPU-only6690 LUT/5209 FF/32分布式RAM单元/0 DRM/4 APM，224 IO另计；比第11轮多69 LUT/4 FF。原生返回0、宿主return2/TIMING_FAIL，主详细布线93次到0未布通，完整226.471秒；冻结31项输入/270项输出及独立核验一致。

实际setup Slow/Fast **-6.770/-1.270ns**，hold +0.110/+0.100ns，脉宽 +4.346/+4.345ns。全局setup比父版变差，**100MHz仍未通过**，不将FIFO逻辑路径分离或布线耗时当收益。第9轮仍为最优WNS检查点；本轮为新网表和布局。

新的最差data_ack→stall→WB目的tag→操作数旁路→分支比较→issue pc_x_q[30]：24级逻辑，逻辑4.060ns/布线13.444ns。stall控制274负载，WB tag一位50负载。源码确认rd_wb/rd_e2同时用于实际提交/冒险及数据旁路，且包含当前stall/issue_stall限定。下一步仅为数据旁路导出由已注册valid/rd-valid/opcode决定的tag，提交、RF写口、scoreboard及stall/squash原控制不变；在可实际发射时两种tag必须相等，停顿/取消时不能借数据采样触发新事务。先做此不变量的定向验证，再运行整核回归与实际STA。

证据`docs/verification/cpu/fifo_payload_timing.json`。未合并主工程或编程板卡。

## 数据旁路tag与提交控制分离（第13轮）

仅为E2/WB操作数数据选择导出由已寄存valid、rd-valid及opcode决定的目的tag，移除当前stall/issue_stall对宽旁路选择的影响；原RF写地址、提交tag、scoreboard、异常及issue控制不变。实际发射时新旧tag必须相等，仿真断言在全部整核测试中启用。没有新增状态、流水级或load/分支延迟。

相同最终定向测试/runner在父版RED，候选GREEN，覆盖issue/memory stall、WB及E2 load旁路、恢复发射和fault取消。三种背压×两模式旧时序逐周期、新默认按序异常及IRQ、部件/固件/冒烟共22项正例、5项预期拒绝通过；RF部件复用输入仍匹配的既有结果，未将旧FIFO/DIV损坏负例计为本轮新执行。全部实际输入/外部原语/输出哈希核验通过。

CoreMark实际加载TCM镜像与父版相同，单1682259/双1390197周期、1467843次WB及CRC不变；单观察IPC0.872543、CoreMark/MHz短RTL估算2.972194，双1.055853/3.596613。ELF文件哈希不同，证据分别记录，不称同一ELF。startup、14指令探针、validation和冒烟符合预期；非官方分数、完整ISA证明或板测。

同10ns/原IO/hold/multicorner和区域约束完整实现，原生PDS返回0，宿主return2/TIMING_FAIL；252次主详细迭代到0未布通，完整250.952秒。31项冻结输入/588项输出及独立只读复核一致。CPU-only **6685 LUT/5209 FF/32分布式RAM单元/0 DRM/4 APM**，224 IO另计；比父版少5 LUT，FF不变。

| 实际检查 | Slow/ns | Fast/ns |
|---|---:|---:|
| setup | **-3.486** | **+1.027** |
| hold | +0.117 | +0.109 |
| 脉宽 | +4.346 | +4.345 |

performance slack一致，**100MHz仍未通过**。最差setup比第12轮改善3.284ns，但仍比第9轮最优-3.064ns差0.422ns；新网表/布局，不能将旁路控制分离概括为全局收益。Slow违例端点2779→2260，Fast本轮没有setup违例。

新最差为LSU请求FIFO地址低位→load返回格式/旁路→分支比较→issue pc_x_q[30]，17级逻辑，逻辑3.177ns/布线9.976ns。旁路网一段4.227ns，末端晚到branch request进入PC进位链。下一步核对真实映射及PC更新结构，优先检验常量增量提前计算、重定向只作末端选择；不增加load/分支周期或放宽约束。证据`docs/verification/cpu/bypass_tag_timing.json`。未合并主工程、未编程板卡。

## PC常量增量与重定向选择分离（第14轮）

实际ADS网表将重定向mux融合到PC常量加法每级carry，父版结构检查发现28个PC carry输出依赖branch/CSR request。提前计算PC+4并用ADS支持的syn_keep保留有实际用途的边界；PC+8只在双发射配置生成，避免属性保留单发射未用硬件。PC优先级、步长、寄存器与分支/load时序不变，不全局关闭资源共享。

同一结构检查对新实际网表为0处依赖；此检查保守处理LUT依赖、显式列出未展开子模块输出边界，只覆盖本层PC数据组合锥，不代替STA或跨层形式证明。独立PC oracle完成4101周期（4096组随机更新），覆盖并发优先级、reset/hold、低位及32位回绕，真实PC错误注入被拒绝。23项功能正例和6项预期拒绝的实际输入/外部原语/输出哈希核验通过。CoreMark实际加载TCM镜像、周期/WB/CRC及其余固件结果与父版相同，单观察IPC0.872543、短估算2.972194 CoreMark/MHz，仍非官方或板级结果。

同100MHz/原IO/hold/multicorner和区域约束重新完整实现，CPU-only **6713 LUT/5209 FF/32分布式RAM单元/0 DRM/4 APM**，224 IO另计；比第13轮多28 LUT、FF不变。原生返回0、宿主return2/TIMING_FAIL，159次主详细迭代到0未布通，完整252.369秒。31项冻结输入/402项输出和独立只读复核一致。

| 实际检查 | Slow/ns | Fast/ns |
|---|---:|---:|
| setup | **-3.247** | **+1.018** |
| hold | +0.107 | +0.099 |
| 脉宽 | +4.346 | +4.345 |

performance slack一致，**100MHz仍未通过**。最差setup较父版改善0.239ns，但比第9轮最优-3.064ns差0.183ns；新网表/布局，不能把结构诊断PASS当频率收益或部署通过。Slow违例端点2260→2262，亦不能声称全局路径均改善。

新最差为LSU请求队列rd_ptr→返回half选择→load旁路→下一次store地址/数据lane→mem_data_wr_q[27]，9级逻辑、逻辑1.590ns/布线11.297ns。下一步检查在原队列push/pop边界预计算完整队首寄存输出，消除读指针mux；必须保持包括无效残留值在内的原逐周期队列语义和load延迟，先做组件oracle再复核整核与实际STA。证据`docs/verification/cpu/pc_increment_timing.json`。未合并主工程、未编程板卡。

## LSU两表项队首寄存存储坐标（第15轮，物理回退）

复用原环形队列的接纳/pop/计数规则，仅在深度2时将两份36位存储改为相对于读头的head/tail，pop交换两份物理内容；移除读写指针，输出直接来自head FF。实际full时push仍拒绝、empty时pop仍忽略，空队列残留值也保留，其他深度保持原实现。没有增加payload状态、主流水级或load延迟。

对原固定FIFO的全部控制/36位输出（含无效残留）及独立有效流oracle，深度2/4各10001周期通过；覆盖reset、满/空同时push/pop和无效X输入。相同最终测试对原实现通过，真实输出错误注入被拒绝；实际ADS网表的36位输出由父版组合mux变为直接FF。整核/固件/组件24项正例和6项预期拒绝，全部实际输入/外部原语/输出哈希一致。CoreMark单1682259/双1390197周期、1467843次WB及CRC仍相同，短RTL估算与观察IPC不变，非官方或板级结果。

同100MHz/原IO/hold/multicorner和两区域约束完整重新实现，CPU-only **6806 LUT/5207 FF/32分布式RAM单元/0 DRM/4 APM**，224 IO另计；比第14轮+93 LUT/-2 FF，FIFO层次8→58 LUT、76→74 FF。不能将状态减少概括为面积优化。原生返回0，宿主return2/TIMING_FAIL，230次主详细迭代到0未布通，完整505.554秒，其中hold修复182秒。31项冻结输入/544项输出及独立复核一致。

| 实际检查 | Slow/ns | Fast/ns |
|---|---:|---:|
| setup | **-4.936** | **-0.103** |
| hold | +0.116 | +0.101 |
| 脉宽 | +4.346 | +4.345 |

performance一致，**100MHz仍未通过，且全局setup较父版恶化1.689ns**。Slow违例端点2262→2718、Fast新增1个setup违例；第9轮仍为历史最优WNS。本轮保留为有完整证据的诊断检查点，不把组合mux消除或功能通过当时序收益。

新最差data_rdata_i[23]→load格式/旁路→下次地址加法→mem_cacheable_q，15级逻辑、逻辑2.891ns/布线12.610ns；相关操作数连接两段2.665/3.466ns。下一步停止叠加RTL，冻结同一源码，单因素比较完整单时钟区域布局，原100MHz与所有IO/hold预算不变，单独核验实际报告。证据`docs/verification/cpu/lsu_head_timing.json`。未合并主工程、未编程板卡。

## 同RTL单时钟区域（第16轮，当前最优setup）

冻结第15轮RTL，仅将两个时钟区域改为一个完整(X0,Y3)区域，PAP_REGION(0,64,150,199)。23项RTL/头文件/清单及原10ns/IO/hold/multicorner FDC逐项SHA256相同，seed1和预算也不变。复用第15轮24项正例/6项预期拒绝，全部实际输入/外部原语/输出哈希重新核验，没有将复用记录称为新仿真。CoreMark测量和CPU配置均相同。

完整新实现，原生返回0，宿主return2/TIMING_FAIL，完整191.430秒。31项冻结输入/260项输出和独立复核一致；9359个唯一CPU叶节点区域绑定，原生clock report非IO时钟负载范围(4,63,150,198)位于目标区域内，没有独立逐单元坐标审计。CPU-only **6806 LUT/5207 FF/32分布式RAM单元/0 DRM/4 APM**与父版一致，224 IO另计。

| 实际检查 | Slow/ns | Fast/ns |
|---|---:|---:|
| setup | **-2.277** | **+0.318** |
| hold | +0.107 | +0.083 |
| 脉宽 | +4.346 | +4.345 |

performance一致，**100MHz仍未通过**。Slow较同RTL两区域第15轮改善2.659ns，较旧第9轮最优改善0.787ns，是当前最优WNS；Slow违例端点2718→2446，不能称所有路径已改善。新映射和新布局，不能声称固定网表/固定placement等价。

全局最差为地址寄存器→data_addr_o[25]外部pad，2级逻辑（主要包含IO buffer）、逻辑3.195ns/布线3.431ns；原2ns输出预算未变。前20条仍有PC→BTB选择→RAS CE核内setup -1.929ns，不称CPU核内部时序通过。下一步仅用PDS官方syn_useioff打包已有port连接FF，核对实际pack而不增加寄存级；同时保留核内预测路径为下一处RTL诊断目标。证据`docs/verification/cpu/single_clock_region_timing.json`。未合并主工程、未编程板卡。

## 官方现有IO FF打包（第17轮，物理回退）

同第16轮RTL/单时钟区域及全部时序预算，仅启用syn_useioff。实际map日志打包96个输出IO FF，其中62个复制原寄存器；CLM FF净减少34至5173，不是CPU面积节省。连同96个IO FF共5269 FF，比原CPU逻辑5207多62。LUT6806、32分布式RAM、0 DRM、4 APM及224 IO不变；资源口径明确区分CLM/IO，未把夹具资源混入CPU。

原生PDS返回0、宿主return2/TIMING_FAIL，完整338.229秒；32项冻结输入/389项输出和独立复核一致。实际setup Slow/Fast **-4.776/-0.552ns**，hold +0.056/+0.026ns，脉宽 +4.346/+4.345ns，performance一致。Slow较第16轮恶化2.499ns，100MHz仍未通过。该物理开关仅保留作诊断，**当前最优配置仍是第16轮SingleClockRegion，最差setup -2.277ns**。

新最差训练packet_q[38]→BTB匹配/优先写入选择→btb_target_q[5][13] CE，15级逻辑、逻辑2.264ns/布线12.105ns。结合第16轮也存在的BTB读选择→RAS CE -1.929ns，下一步检验预测器读写优先选择链；须保持原最高表项优先级、重复tag、训练/RAS/BHT行为及周期，先组件/整核/CoreMark验证，再以最佳单区域物理配置复核。功能记录仍为同RTL24正例/6预期拒绝哈希复用，不宣称新仿真或板测。证据`docs/verification/cpu/io_register_timing.json`、`io_register_diagnostic.md`。

## BTB独热并行选择和表项写入（第18轮，面积改善）

直接维护`triha_npc.v`，只改BTB读/写选择结构：精确PC优先、upper-word回退和最高表项优先独热mask，使用扁平Verilog AND/OR数据选择；命中直接写选中表项，miss仍按原LFSR分配。BTB32/BHT512/RAS8规模、预测与训练周期、全部状态机不变，无新流水。独热数据结构来源/版本及Apache/lowRISC通知保留在源码与清单，原始28文件不变，适配清单11项；正式filelist不再同时编入原NPC，仿真保留它作oracle。

组件32项普通BHT与4项GShare配置各4003周期，完整比较BTB/BHT/RAS/LFSR及输出；独立最高索引oracle覆盖重复tag、upper-word、无命中和X输入，真实预测输出错误被拒绝。整核/组件共26项唯一正例组和6项预期拒绝，输入/外部原语/输出核验一致。CoreMark实际TCM镜像、单1682259/双1390197周期、1467843 WB/CRC和其他固件结果与父版相同；观察IPC及短估算不变，非官方/板测/完整ISA证明。

同第16轮单区域和原100MHz/IO/hold/multicorner，完整新实现，CPU-only **6505 LUT/5207 FF/32分布式RAM单元/0 DRM/4 APM**，224 IO另计，较同区域父版少301 LUT（4.423%），FF不变。原生返回0、宿主return2/TIMING_FAIL，74次主详细迭代到0未布通，完整229.631秒。31项输入/232项输出和独立复核一致。

| 实际检查 | Slow/ns | Fast/ns |
|---|---:|---:|
| setup | **-2.756** | **-0.054** |
| hold | +0.109 | +0.109 |
| 脉宽 | +4.346 | +4.345 |

performance一致，**100MHz仍未通过**，全局setup较最佳第16轮恶化0.479ns；Slow违例端点2446→3171。新网表/布局，面积改善不能冒充频率收益。历史最佳仍保留第16轮-2.277ns，当前为另一个完整可复核的候选。

全局最差data_ack_i→data_wstrb_o[3]为外部组合控制；前20条仍有RAS数据路径-2.539ns和BHT CE -2.428ns。下一步只局部化各BHT表项的饱和转移，消除动态读计数再写使能的反馈链，保留规模、2bit状态、reset、taken优先级及周期，再用完整预测器miter/整核/CoreMark和原实际STA核验。证据`docs/verification/cpu/predictor_select_timing.json`。未合并主工程、未编程板卡。

## BHT表项本地饱和更新（第19轮）

只将动态地址读计数→饱和判断→动态写入，展开为各BHT表项的本地2bit转移，地址比较、reset=3、条件优先级和全部512项/预测周期不变。组件测试补齐512个写地址扫描及随机9bit训练，正式配置4515周期、小GShare配置4019周期，全部表状态、输出和独立查找oracle一致；真实预测输出错误被拒绝。26项唯一正例组、6项预期拒绝，全部输入/外部原语/输出核验。CoreMark仍单1682259/双1390197周期、1467843 WB及CRC相同，短RTL估算/观察IPC不变，非官方或板测。

同单区域、原100MHz/IO/hold/multicorner完整实现，CPU-only **6484 LUT/5207 FF/32分布式RAM单元/0 DRM/4 APM**，224 IO另计；比第18轮少21 LUT、FF不变。原生返回0、宿主return2/TIMING_FAIL，98次主详细迭代到0未布通，完整224.628秒；31项输入/280项输出和独立复核一致。

实际setup Slow/Fast **-4.375/-0.602ns**，hold +0.020/+0.004ns，脉宽 +4.346/+4.345ns，performance一致。100MHz仍未通过，全局最差比第18轮差1.619ns；Slow违例端点3171→2762并不能概括为时序收益。第16轮-2.277ns仍是历史最优。

最差inst_rdata_i[12]→FIFO csr_history_q[1][0]，新前20条也有多个ACK/error→外部端口，未包含BHT；不将缺席前20条称为全部BHT通过。已观察到自动IO分配随各轮映射变化，下一步冻结第16轮224个已映射IO位置，固定时序预算和当前RTL作独立物理对照，再判断剩余关键路径。此管脚表仅为隔离诊断，不是板级管脚方案。证据`docs/verification/cpu/predictor_counter_local_timing.json`。

## 仍需完成

- 正式RV32I/ACT4、CSR/异常/IRQ、背压与访存错误、flush/取消及退休观测。
- 正式CPU总线时序边界，以及当前后布线setup违例的100MHz收敛。
- 新主工程地址/外设、DDR/AXI、NPU/Video集成和板级运行。

主工程Video及技术报告修改保持原位；CPU实现尚未合入该分支。本批执行CPU原生综合/映射和隔离后布线，未生成bitstream或编程板卡。


## 2026-10-19 固定I/O终态与系统验收转向

固定224个裸核总线管脚及有效电气值与第16轮一致；完整PDS返回0，独立review判TIMING_FAIL。Slow/Fast setup −3.788/+0.152ns，hold +0.112/+0.100ns，脉宽 +4.346/+4.345ns。CPU-only 6484 LUT/5207 FF/32 distributed RAM/0 DRM/4 APM，224个IO另计。最差inst_rdata_i[3]到FIFO csr_history_q；内部预测反馈另有−3.247ns，不能全部归因于IO。首轮缺电气约束的native1失败保留。证据：`docs/verification/cpu/fixed_io_timing.json`。

用户已选择接入SRAM/总线后按实际系统边界验收。使用正式8KiB ROM（0x0）和32KiB SRAM（0x10000）、内部CPU总线。旧裸核记录保持失败；系统通过不能回写旧记录。CPU与SoC额外资源分开，100MHz、hold、多corner不降低，未做板测。


## 2026-10-19 最小ROM/SRAM系统首轮

新增显式triha_minimal_soc：CPU宽总线内部连接，8KiB启动窗口0x0跳至32KiB SRAM 0x10000；UART TX 0x10000000和调试系统寄存器0x20020000，未实现区域错误完成。未接DDR/Video/NPU/Timer，不是完整SoC或板级下载目标。地址由config/soc_map.json生成，--check与非法ELF/旧TCM地址拒绝检查通过。旧测试TCM保留。

ModelSim 301项总线检查、ROM启动SRAM固件、CoreMark四项CRC通过。坏读数据、timeout和真实CRC错误均拒绝。旧runtime在单/双模式回归PASS。CoreMark5次短RTL：2186751周期、1467843 WB事件、观察IPC0.671244、短测2.286497 CoreMark/MHz，比旧TCM多29.989%。输出中TCM stack文字为沿用的错误标签，实际32KiB SRAM地址和镜像已核验；非官方分数或板测。索引minimal_soc_simulation.json。

完整系统PDS原生返回0，宿主TIMING_FAIL；独立复核全部冻结哈希、阶段标记和报告。Slow/Fast setup −1.206/+1.480ns，hold +0.024/+0.006ns，MPW +3.655/+4.202ns。无例外，100MHz未通过。最差UART busy计数到TX端口−1.206ns；核内BTB[29][16]到fetch PC[3]−1.202ns（逻辑2.030ns/布线8.806ns）。不能仅归因于IO。

综合层次CPU6481LUT/5205FF/32distributedRAM/4APM；额外140LUT/122FF/16.5DRM36K等效。映射系统6621LUT/5327FF/16.5DRM/4APM/13IO，不能称CPU-only。DRM含16个36K和1个18K，SRAM因读口复制占16DRM；原生RAM映射/读前写参数已查，尚未执行原生模型RAM功能仿真。证据minimal_soc_route.json。下一步先处理实际UART输出组合门和预测长连线；本轮原始结果不改写。


## 2026-10-19 单拍本地总线与第二轮系统物理

删除额外返回数据寄存和响应空泡；同步RAM输出与tag/error直接逐拍对齐，UART单独锁存等待。协议检查366项，真实坏读和timeout拒绝，整核4类访问异常cause/address经UART核对。CoreMark 1685831cycles/1467843WB，观察IPC0.870694，短测2.965896 CoreMark/MHz；比旧TCM仅多0.212333%，四项CRC正确，非官方/板测。SRAM stack打印标签已更正。CPU流水与架构RTL不变。

UART移位寄存最低位直接连TX，不再串接busy门；CPU物理集中到完整时钟区，10个实际外部输出采用原生OREGIS。新布局/新系统总线不能把余量变化全归因单一因素。Slow/Fast setup −0.478/+2.833ns，hold +0.118/+0.100ns，MPW +3.655/+4.202ns。100MHz尚未通过，核内PC[7]→预测→PC[24]为−0.478ns、15级、逻辑2.362/布线7.782ns；RAS CE有−0.466ns。完整PDS0、宿主2，全部冻结输入/输出与独立报告核验。

系统映射6778LUT/5292 CLM FF/16.5DRM/4APM/13IO；10个IO FF另列，不把CLM FF净减当架构状态减少。综合层次CPU6606LUT/5173FF/32distributedRAM/4APM，存储总线172LUT/120FF/16.5DRM；CPU-only仍单列，映射变化不作RTL面积优化。

原生SRAM功能另已通过：同一RTL/镜像重新ADS综合映射16个DRM36K，用实际安装GTP模型执行每个4096地址的初始化、两读口、byte masks、read-before-write、读使能保持，共12296项；真实强制损坏在第1个地址被拒绝。两次缺库依赖的工具失败保留，补齐安装模型的LUT/UDP依赖后通过，未修改工具模型。这是组件综合网表仿真，不是整核后布线仿真。索引minimal_soc_pipeline.json；第二轮时序索引minimal_soc_compact_route.json。


## 2026-10-19 并行预测优先选择终态

精确PC和upper-word独热优先掩码并行计算，再走原fallback选择，避免连续的全表归约；不增加状态、周期或改变预测表尺寸。旧vendor28哈希保持，派生清单11项中只更新NPC记录。24组正例及5组预期拒绝的冻结哈希复核，三seed×两模式整核/按序store/同步异常、IRQ/mret、组件、CoreMark两模式、validation、runtime和14指令完成探针均通过。测试TCM仍single1682259/dual1390197cycles；系统SRAM仍1685831cycles/1467843WB、IPC0.870694、短测2.965896 CoreMark/MHz，均非官方分数/板测。4类系统访问异常再测PASS。索引minimal_soc_parallel_validation.json。

第三轮实际系统后布线Slow setup −0.183ns，仅4个端点/TNS−0.575ns（上轮248端点/TNS−39.679ns）；Fast setup +2.660ns，hold +0.107/+0.067ns，脉宽 +3.655/+4.202ns，100MHz仍未通过。最差PC[5]→RAS index CE，11级、逻辑2.165ns/布线7.572ns；另BTB训练CE −0.026ns。系统6829LUT/5292CLM FF/10IO FF/16.5DRM/4APM；CPU层次6658LUT/5173FF/32distributedRAM/4APM，额外171LUT/120FF。CPU比上轮多52LUT，不宣称面积改善。独立核验全部哈希、native0/runner2、同10ns预算和native RAM组件证据，索引minimal_soc_parallel_route.json。后续按剩余前端热点做局部布局对照，不改CPU或固件。


## 2026-10-19 局部前端布局对照

同RTL/同固件下将4264LUT前端局部放置(0,47,150,199)，未改善：Slow setup −0.202ns/33端点/TNS−3.003ns，Fast +2.614ns、hold +0.118/+0.106ns、脉宽 +3.655/+4.202ns。保留第三轮−0.183ns/4端点为较好检查点。两轮同样呈PC→预测反馈，布线占主导；此次结果不选为发布。核验见minimal_soc_frontend_route.json。

下一轮回到第三轮完整CPU时钟区，按ADS User Guide 5.13对实际PC查询inst_addr[2..31]施加syn_maxfan24，检查原生实际复制/缓冲及最终余量；仅工具物理/综合属性，RTL和10ns预算不改，不用布局估计声称通过。


## 2026-10-19 PC扇出24物理对照

原生PDS实际复制83个PC寄存器，各复制体INIT/CLK/C/CE/D与原位完全相同，独立网表审计通过；系统多35LUT/83FF。最终Slow setup−0.354ns/175端点/TNS−20.044ns，Fast+2.833ns、hold+0.145/+0.104ns、MPW+3.655/+4.202ns。工具0、宿主2，实际100MHz失败，不选此额外资源方案；证据minimal_soc_fanout_route.json。CPU层次6693LUT/5256FF，系统6864LUT/5375CLM FF/10IO FF/16.5DRM/4APM。

现回到第三轮compact配置（无前端子区域、无PC复制约束），保留同RTL/固件/10ns，仅用placement seed2作一次有界布局对照。运行目录route-20261019T1226524843811Z，终态未定；较好检查点仍为seed1的−0.183ns，不声称100MHz通过。


## 2026-10-19 seed2终态

仅更换placement seed2，实际Slow setup−0.184ns、23端点/TNS−2.148ns；Fast+2.660ns、hold+0.142/+0.105ns、脉宽+3.655/+4.202ns，未通过。最差LSU pending到SRAM CE/WE，同时前端RAS仍−0.170ns；不选seed2。较好检查点仍compact seed1的−0.183ns/4端点。独立核验见minimal_soc_seed2_route.json。布局/扇出对照已结束，下一步对原预测器全32位tag比较做等价共享/分组，并重测实际周期和时序。


## 2026-10-19 共享高tag/比较树终态

高29bit共享及三bit分组比较的逐拍NPC对照、320项四态原始等值oracle、三seed×两模式整核/按序store/异常、IRQ/mret、系统CoreMark与4类真实访问异常通过。SRAM CoreMark仍1685831周期/1467843WB、2.965896短估算/MHz。原vendor不变。CPU层次降为6175LUT/5173FF，系统6347LUT/5292CLM FF/10IO FF/16.5DRM/4APM；系统较前版少482LUT、FF不变。功能索引minimal_soc_tag_tree_validation.json。

实际新布局Slow setup−0.582ns/426端点/TNS−130.114ns，Fast+2.608ns、hold+0.116/+0.102ns、脉宽+3.655/+4.202ns，未通过。不能以资源下降声称时序收益。最差PC[0]→RAS动态地址→stack CE，11级、逻辑2.032/布线8.097ns；索引minimal_soc_tag_tree_route.json。后续共享两种查询相同的低两位tag，并将RAS动态地址写入改逐条目早期选择，保持原状态/周期与优先顺序。


## 2026-10-19 31bit公共查询/RAS条目写入终态

共享除bit2外全部31个tag位，RAS按候选早期索引逐条目写入；原指针优先顺序和payload表达式保留，新增确认return与预测call重叠定向用例及480项四态等值输出检查。NPC全状态、三seed×两模式整核/按序store/同步异常、IRQ/mret、4类系统访问异常、CoreMark均通过；SRAM短测仍1685831cycles/1467843WB、2.965896/MHz、观察IPC0.870694。功能索引minimal_soc_ras_entry_validation.json。

CPU层次6111LUT/5173FF/32distributedRAM/4APM；额外169LUT/120FF/16.5DRM。系统映射6280LUT/5292CLM FF/10IO FF/16.5DRM/4APM。完整物理Slow setup−0.017ns，仅2端点/TNS−0.034ns，Fast+2.820ns、hold+0.108/+0.100ns、MPW+3.655/+4.202ns，100MHz仍未通过。全部哈希/实际报告独立核验见minimal_soc_ras_entry_route.json。

最后路径LSU address→通用d_bad译码→取指stall→RAS条目CE；下一步仅在已命中SRAM时用等价本地写有效性检查，避免把ROM/MMIO/未映射译码串入碰撞抑制，不改变写入/error/响应/周期。


## 2026-10-19 100MHz片上系统最终PASS

SRAM已命中时只用本地有效性检查控制写入及I/D碰撞，通用ROM/MMIO错误译码保留在注册error响应路径。相同CPU、相同固件下功能/周期保持：415项总线检查、7种maintenance伴非法写、4类真实CPU访问异常、6项工具契约测试及坏数据拒绝通过。地址生成器拒绝实现窗口重叠；改写前先观察该拒绝测试RED。CoreMark仍1685831cycles/1467843WB、观察IPC0.870694、短测2.965896/MHz，非官方/板测。

实际PDS完整新流程返回0、宿主0、source_unchanged，全部输入/输出哈希和实际报告独立核验PASS。Slow/Fast setup+0.232/+2.833ns，hold+0.128/+0.104ns，MPW+3.655/+4.202ns，performance+0.232ns一致。100MHz与原IO/hold/uncertainty不变、无false path/MCP。冻结目录route-20261019T1301015447457Z，compact/seed1，无前端子区域和PC复制约束；最差ROM块RAM→CPU exec，已无违例。

CPU综合层次6080LUT/5205FF/32distributedRAM/0DRM/4APM；系统额外136LUT/88FF/16.5DRM。系统dev_map6216LUT/5292CLM FF/16.5DRM/4APM，13IO及10OREGIS另列。综合FF合计5293，dev_map优化1个，不能跨阶段混加。CPU源RTL未在最后一步改变，层次统计受整合及综合归属影响，不把跨层次FF转移当状态减少。

验收摘要minimal_soc_100mhz.md；绑定minimal_soc_acceptance.json；独立复核minimal_soc_local_decode_route.json；功能性能minimal_soc_local_decode_validation.json。原生SRAM综合网表12296项与损坏拒绝复用且同RTL/同镜像哈希绑定。没有完整系统门级仿真、板级PLL/管脚绑定、bitstream或板测，没有自动合入主工程。下一步正式板级最小系统，再接入DDR/Video/NPU。

## 2026-10-19 板级最小系统推进中

保留5c4229a及cpu-soc-100mhz-sta-20261019，通过基线不改写。本批新增板级Verilog封装、125MHz差分参考→100MHz真实PLL、KEY0协调复位、固定UART/LED管脚和8KiB软件自检；没有修改CPU RTL、发射/预测规模或片上总线周期。Windows原生环境不变。

数字前置通过：真实Pango PLL模型111项、相同固件两次整核启动和8KiB自检/串口/KEY0仿真、真实单字节初始化损坏被固件code1拒绝、配置工具8项、物理串口解析器6项。board_digital_validation.json重新核验全部源/工具/输出绑定，正负例PT_LOAD相同、故障镜像只差指定字节。尚未运行物理串口捕获。

板级后布线仍未通过：首轮−0.661ns并有Tcl报告提前读取错误；ROM区域seed1改善至−0.303ns/13端点，seed2−0.781ns；前端32×32容量失败，40×40布通但−0.897ns；关键路径优先路由单seed仍−0.303ns。均完整保留，未生成可交付位流。真实PLL报告总setup uncertainty0.250ns，原外供时钟为0.150ns；FDC预算未降低。

两组6候选已终态：build/soc/board-route-20261019T1421275069880Z选择seed8，最差−0.096ns、仅3端点；1431073056262Z选择seed13，−0.217ns。原网表最佳仍seed8。原100MHz/IO/hold约束、实际PLL不确定度均不降低。

随后1440308216288Z执行PDS定向布线迭代，最多3轮、前20路径、目标+0.2ns，实际最终−0.267ns/12端点，未选用；独立复核board_route_constraint_iteration.json。已在原通过设计的隔离副本上验证独立位流生成CLI：必须显式set_arch和传入完整路由ADF，生成bitstream+smsk成功，原通过目录全部输出哈希未变；此CLI测试不是板级位流或板测。

以上板级数字版本作独立Git检查点，尚未生成可交付板级位流、未Program/Verify或板测。下一步只对预测器读目标数据的组合结构做等价调整：两个原优先掩码分别复用现有独热MUX，再按原if优先级选择完整payload；策略、状态、表规模和周期不变，先验证完整预测器/整核/CoreMark，实际100MHz报告仍为唯一物理准入。

预测组合实验已完成：并行payload、LUT6平衡归约与标量valid两版均通过完整预测器状态/输出、三seed单/双有序执行、IRQ/mret、SRAM CoreMark与板级两次启动，CoreMark保持1685831/1467843。第一版CPU6264LUT/5172FF、后布线−0.678ns；第二版6404LUT/5172FF、−0.408ns，均未优于原网表最佳−0.096ns。验证与实际时序分别见board_payload_{late,balanced}_{validation,route}.json。实验作Git诊断检查点，尚未准入；随后恢复a9034b5的CPU源和清单，针对实际PC扇出作纯综合诊断，保持原版本作为部署候选。

板卡只读识别PG2L100H/00602899、DONE1，COM12可见；当前Video配置未替换。历史成功的video_raw_board_0cd4a546804b及同名smsk已核对恢复哈希。详情board_system_design.md、board_system_plan.md及docs/verification/cpu/board_system.md。主工程独立Video/技术报告工作不改动，未合入、未push。


## 2026-10-20 板级物理对照及下一步

已恢复a9034b5的原CPU源/11项派生清单，28个vendor文件不变。PC复制未改善（-0.536ns），高PFD PLL I1/M1/F8/O10仍精确100MHz，实际PDS uncertainty仍0.250ns，最差-0.096ns。相邻区域(0,64,100,149)容量失败（native1）；恢复原CPU/ROM区域(0,64,150,199)。合法详细布局迭代40次、Performance模式均仍-0.096ns；LUT6D策略0/2分别-0.673/-0.500ns；布局扩散系数0为-0.205ns，均未收敛。无频率、IO或hold约束放宽，没有位流/上板。首次迭代参数8被工具拒绝，已保留并增加合法10..50前置检查。

当前数字验证：实际PLL模型111项；整核两次启动/8KiB自检；真正损坏0x10640的一字节后固件code1拒绝，正负例ELF加载内容一致。配置9项、串口6项、选定路由DB绑定4项通过；见board_selected_digital_validation.json。

工具选项对照不再扩大。下一步仅在维护派生中将AUIPC/JAL/JALR的PC加法从通用ALU输入选择链移出，保持六级单发射、预测器规模、状态/复位/hold和周期不变。先执行原执行单元全输出对照和负例，再做整核退休/store/异常、CoreMark及板级正负例，最后以实际100MHz STA判断。原版及所有失败证据保留；本检查点仍不是可交付板级版。


## 2026-10-20 发射选择路径核对

PC加法等价实验通过完整执行单元/整核/CoreMark，但实际-0.442ns，已存7e9df4d/cpu-exec-pc-diagnostic-20261020后恢复原CPU，并从默认树删除该实验RTL/入口/TB，快照和标签保留。真实关键路径是issue PC[2]选择指令字→RF地址/读取→ALU，不是PC算术。

只复制该选择位的物理对照实际增加7FF；8个状态的D/CLK/CE/reset/init逐项一致，但全局setup恶化至-0.800ns，不选用。最后补齐种子3/16为-0.329/-0.233ns，原版最佳仍seed8的-0.096ns。所有约束保持、无bitstream/上板。

下一步复用两个既有原生2读口单写寄存器堆，分别固定读取两个取指槽，旁路优先级分别计算后再选择实际操作数。每拍仍只发射一条指令，不增加CPU状态级/周期或改变预测器。预计额外32个分布式RAM单元，实际CPU-only资源与后布线另测；不能提前声称频率收益。

## 2026-10-20 顺序PC计算与板级实际终态

上述并行RF、tag/payload归约、原生优先级、BHT双槽提前读已分别保留验证和物理记录；它们均未通过板级100MHz。本批在2eb3c34及cpu-board-pre-sequential-pc-20261020备份后，只保留共享PC+8早期组合结果，未增CPU状态或周期。14项运行/28个vendor/11项派生/5个安装模型哈希均核验，预测器与优先级坏输出及真正单字节损坏均被拒绝。CoreMark仍1685831周期/1467843WB观察、IPC0.870694、短测2.965896/MHz，非官方分数或板测。

新板级运行board-route-20261019T1806550427178Z完整布通，独立review PASS而timing_closed=false。Slow/Fast setup -0.212/+1.752ns、hold +0.154/+0.101ns、MPW +3.655/+4.202ns；Slow仅3个违例端点，TNS -0.442ns。CPU-only5934LUT/5172FF/64分布式RAM/0DRM/4APM。与BHT父版-0.586ns相比为新网表/新布局的整体结果，仍未超过原网表最佳-0.096ns。

最新路径FIFO读指针→rs2/旁路→ALU结果，读指针扇出141、首段0.990ns，三条违例同源。下一步只对该指针作有界官方syn_maxfan复制诊断，核对实际复制状态连接后重新STA；原100MHz/IO/hold/uncertainty保持。board_sequential_pc_validation.json及board_sequential_pc_route.json为本批证据。未生成CPU板级包，未Program/Verify，未修改主工程Video或技术报告。

## 2026-10-20 板级100MHz闭合及下载包

FIFO复制实际增加6FF，首段布线虽缩短，整体setup -0.438ns，已归档6bbf059/cpu-board-fifo-fanout-diagnostic-20261020并退出默认recipe。随后仅将六路旁路数据覆盖改为标签并行比较、独占优先级和case传递payload，保持x0、X/Z、状态和周期。扩展独立oracle至24448项，原版通过、坏输出拒绝、候选通过；三seed单/双有序WB/store/异常、IRQ/mret、完整预测器/训练、板级正负例和CoreMark通过。15项运行绑定、vendor28/派生11/安装模型5均核验。

首次实际STA已全通过，但位流生成命令因PowerShell数组内拼接缺括号被拆行而失败，原记录完整保留。回归测试真实复现4行而非2行，修复后5项发布检查通过；未改写旧FAIL。完整复跑board-route-20261019T1825066711298Z的compile/synthesize/dev_map/pnr/report_timing/gen_bit_stream均成功，宿主和3个原生调用均返回0、source_unchanged，46项输入、328项输出及实际管脚/PLL/最终STA独立复核通过。最差路径已为SRAM块RAM→执行结果，setup +0.023ns；不据此声称高于100MHz。

下载包build/soc/releases/cpu_board_5f5eb8c89efd包含位流、校验掩码、ELF/map、ROM/SRAM、最终报告及review/manifest/README，10项文件哈希通过。验收/备份标签cpu-board-100mhz-sta-20261020。下一步在获得临时替换当前Video配置的确认后，执行volatile Program/Verify、UART两次完整启动/ALIVE及KEY0现场验收，并恢复用户指定的Video包；不写Flash。当前不自动下载或宣称板测成功。

## 2026-10-20 实体板级启动与KEY0验收完成

用户授权Program/Verify，随后明确“不用恢复”。旧5f5eb8c89efd实际下载和回读校验成功，但KEY0后无CPU串口、LED全灭。独立27MHz观察诊断证明125MHz参考存在、KEY0松开，原OPTIMIZED带宽PLL始终不锁定，CPU复位未释放；仅增加PLL复位仍失败。保持其他诊断输入不变、只使用同板已验证DDR GPLL的HIGH带宽后，锁定和复位释放均正常，输出分频计数符合标称100MHz。完整原始对照和失败记录保留，见board_pll_bandwidth_fix.md及对应JSON。

正式修复3e73c28只改变PLL带宽配置及生成/核对入口，CPU RTL、分频、100MHz/IO/hold/multicorner不变。配置工具11项先RED后GREEN，真实模型111项、整核两次启动、损坏拒绝通过。新完整PDS运行board-route-20261020T0301376595393Z和独立review通过，所有余量与父版相同，位流df5475cbb154已打包；46输入/328输出及10项包文件绑定通过。旧CoreMark的完整输入/输出哈希仍相同，性能证据只按该RTL范围复用。

实际PG2L100H/00602899 Program/Verify返回0，COM12记录软件8KiB自检PASS。完成下载后约107.34秒连续运行，再按用户确认的实体KEY0重新自检，随后约53.17秒连续运行；总164条ALIVE（含下载窗口的两个初始启动epoch），每个epoch从seq0开始，序号和cycle差连续，无FAIL/TRAP。KEY0观察窗口在Program/Verify之后开启，只有一个新启动banner，没有新的JTAG操作。

现场证据board_system_physical_acceptance.json绑定位流/掩码、工具、实际JTAG日志、原始串口及用户按键确认；标签cpu-board-physical-pass-20261020。当前保留CPU易失配置，不恢复Video，不写Flash；主工程源码和独立Video/技术报告任务不改动、不自动合并。下一阶段接正式CPU MMIO互连及既有DDR/Video/NPU契约，完整ISA/异常、板级CoreMark和校准仪器测频仍是独立验收，不以本轮8KiB缓冲自检替代。
