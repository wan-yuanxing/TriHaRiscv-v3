# TriHa CPU 开发与维护

主工程：`D:/FPGA/TriHaRiscv-main`。CPU 工作树：`D:/FPGA/TriHaRiscv-cpu-windows`，分支 `cpu/windows-baseline`。更新：2026-10-19。

Windows ModelSim基线、GCC裸机启动、CoreMark1.0短RTL测量和CPU-only Pango综合/映射已经建立，并完成首轮隔离后布线；100MHz setup尚未收敛，详见 [STATUS.md](STATUS.md)。正式SoC、完整ISA及板测仍需后续验收，主目录中的Video分支尚未合入本批CPU RTL。

## 目录与旧工程风格

用户确认：保留新主工程顶层，CPU 内部沿用旧工程的 Verilog 风格和职责划分。

| 位置 | 内容 |
|---|---|
| `rtl/cpu/triha_core.v` | CPU 产品封装，默认单发射，固定六级；完整导出取指/数据/缓存维护协议 |
| `rtl/cpu/triha_cpu.v`、`ADAPTATIONS.json` | 直接维护的内部连接派生Verilog及多文件差异哈希；单发射不生成第二执行单元，保留共享CSR/异常控制 |
| `rtl/cpu/triha_frontend.v`、`triha_issue.v` | 寄存重定向及issue数据/有效控制分离，六个主流水级不变 |
| `rtl/cpu/triha_multiplier.v`、`triha_csr.v` | 宽数据寄存器独立采样；原有效、hold、异常及提交写控制继续生效 |
| `rtl/cpu/triha_lsu.v`、`triha_pipe_ctrl.v` | 纯load旁路、fault提交与请求宽数据分离，保留精确badaddr/mtval和请求保持/取消门控 |
| `rtl/cpu/vendor/` | 固定来源源码、LICENSE、UPSTREAM.json、原始测试映像；保留原文件，不批量改名或重排 |
| `rtl/soc/` | 后续正式互连、外设、IRQ和系统集成；以新主工程接口为准 |
| `tb/cpu/tb_triha_core.v` | CPU 自校验 Verilog；软件退出、发射配置、配对依赖与超时检查 |
| `scripts/cpu/run.ps1`、`run_modelsim.do` | Windows 原生入口及 ModelSim 执行；每次独立运行目录 |
| `config/cpu_sources.f` | 显式仿真模块清单；不递归搜集所有 RTL |
| `sw/runtime/`、`sw/tests/` | 测试TCM启动/链接/输出/退出、data/BSS自检和14指令计数探针 |
| `sw/benchmarks/coremark/` | CoreMark1.0固定原始源码与独立平台适配；构建生成窄formatter适配 |
| `fpga/pg2l100h/project/cpu_core.json`、`constraints/cpu_core.fdc` | CPU-only综合/映射清单及10ns目标；正式板级/DDR继续沿用一套实现 |
| `docs/verification/cpu/` | 小型证据与原始结果索引 |
| `build/cpu/` | BIN、ModelSim work库、日志、结果JSON及后续PDS产物，Git忽略 |

新写 RTL 使用四空格缩进、ANSI端口、`clk_i/rst_ni`、`*_i/*_o`、`u_*` 实例、定宽常量和说明职责的文件头；时序逻辑非阻塞赋值，组合逻辑完整默认值。保持原工程 ctrl/pipeline/mmu 等职责划分习惯，需要实现时再建目录，不复制旧五级模块来凑六级，也不预建空目录。产品工程/目标/分支/提示统一使用 TriHa/CPU 命名，来源只在许可证与独立清单中维护。

## Windows 入口

使用已安装 PowerShell7 和 ModelSim2020.4，无需安装脚本依赖：

```powershell
Set-Location D:/FPGA/TriHaRiscv-cpu-windows
pwsh -NoProfile -File scripts/cpu/run.ps1 -Case all
pwsh -NoProfile -File scripts/cpu/run.ps1 -Case single
pwsh -NoProfile -File scripts/cpu/run.ps1 -Case dual
pwsh -NoProfile -File scripts/cpu/check_toolchain.ps1
pwsh -NoProfile -File scripts/cpu/run_firmware.ps1 -Program runtime -Mode both
pwsh -NoProfile -File scripts/cpu/run_firmware.ps1 -Program retire -Mode both
pwsh -NoProfile -File scripts/cpu/run_firmware.ps1 -Program coremark -Mode both -Iterations 5
pwsh -NoProfile -File scripts/cpu/run_firmware.ps1 -Program coremark -Mode single -RunKind validation -Iterations 1
pwsh -NoProfile -File scripts/cpu/test_pds_reports.ps1
pwsh -NoProfile -File scripts/cpu/run_pds.ps1 -Mode single -Stage map
pwsh -NoProfile -File scripts/cpu/run_pds.ps1 -Mode dual -Stage map
pwsh -NoProfile -File scripts/cpu/run_equivalence.ps1 -Mode both -Seed 37
pwsh -NoProfile -File scripts/cpu/test_route_reports.ps1
pwsh -NoProfile -File scripts/cpu/run_route.ps1
```

`-Case fail` 和 `-Case timeout` 是负例，单独执行预期返回1；`all`要求两个正例通过且两个负例被实际拒绝，才返回0。每次结果在输出显示的独立 `build/cpu/<case>-<UTC>/result.json`，日志与输入/输出哈希同行保存。ModelSim工具目录可用`-ModelSimBin`覆盖，单个原生进程默认墙钟上限60秒。

已安装 ModelSim 在 `D:/modeltech64_2020.4/win64/`，PDS 在 `D:/pango/PDS_2022.2-SP6.4/`，Windows GCC15.2.0在 `D:/AI_Tools/xpack-riscv-none-elf-gcc-15.2.0-1/`。GCC归档校验通过，实际RV32I/ILP32与RV32IM_Zicsr/ILP32编译、链接和ELF32检查通过；未改系统PATH，配置在`config/cpu_toolchain.json`，可用`TRIHA_RISCV_GCC`覆盖完整gcc.exe路径。

用户接受发行包实际前缀`riscv-none-elf-`，以RV32/ILP32能力为准。`run.ps1`使用固定冒烟ELF；`run_firmware.ps1`使用本机GCC编译、链接，再加载ELF的PT_LOAD到同一TCM模型。CoreMark基准版本为1.0，源码补丁标签为v1.01，固定版本及原始文件哈希单独记录于`sw/benchmarks/coremark/UPSTREAM.json`。主流程保持Windows + Codex + ModelSim + PDS + RISC-V GCC，无新增生成语言或WSL依赖。

固件入口每次建立`build/cpu/firmware-<program>-<UTC>/`，保存完整编译命令、ELF、反汇编、生成适配文件、ModelSim日志与前后输入哈希。默认单次仿真墙钟上限180秒、仿真周期上限2000万；这是短测入口。单/双模式共用一个ELF。`-Program runtime -Fault trap`、`-Program retire -Fault count`、`-Program coremark -Fault crc -Iterations 1`是负例，分别要求真实异常、计数不符、基准CRC错误被宿主以返回1拒绝。CRC负例仅修改build中的测试副本。

计时读取真实cycle CSR，软件ticks必须等于仿真观察到的两次读CSR区间。IPC使用该区间两路WB完成事件，定向探针验证14条动态指令（包含branch/store/load及双路完成），现核没有架构minstret实现；完整ISA/异常退休仍待验收。5次迭代不足官方最短10秒，保持原始短时长警告，只报告短RTL估算，不能作为官方CoreMark或100MHz物理时序证据。

## 功能与集成边界

硬件硬要求为Pango和RV32I，M/C/PMP/Cache/发射宽度结合实际性能与成本决定。当前候选固定RV32M/CSR、基础预测/旁路、六级、无SUPER/MMU、通用寄存器堆；DUAL_ISSUE仅用于同边界单/双发射评估，两种模式都跑测试。正式产品配置尚未冻结。

当前128KiB TCM和0x80000000入口只属于测试平台；正式Boot ROM/SRAM、DDR及MMIO按主工程契约维护。`docs/interfaces/ddr_wrapper.md`中的AXI128/HMIC256、时钟域、完成/错误及写后可见性规则继续适用。CPU不能复制或绕过Video维护的DDR实现。

开发工作树共享主仓库Git历史，后续以小范围提交集成。新建工作树不自动包含主目录未提交的Video/DDR修改，跨线接入前需核对其版本。旧工程仅用于来源与历史证据，新构建不跨目录依赖旧CPU、库或生成产物。

`run_pds.ps1`默认只综合，可用`-Stage map`继续器件映射；默认原生进程上限900秒。显式清单只包含核，冻结副本、日志、snr/dmr、实际参数和原语统计保存到`build/cpu/pds-<mode>-<UTC>/result.json`。可用`TRIHA_PDS_SHELL`或`-PdsShell`指定已安装工具。PDS Generics使用名称/数值对（`DUAL_ISSUE 1`），脚本必须从展开日志复核真实配置；综合和映射资源分别记录，因为工具可能在映射时继续优化。

单发射已条件裁剪第二执行单元；原始连接仅在差分测试中作父版。`run_equivalence.ps1`显式选择旧重定向/训练时序（REGISTER_REDIRECT=0、REGISTER_TRAINING=0），使用相同背压TCM作逐周期请求控制、有效/停顿中的总线载荷、WB、预测和11项CSR状态比较，程序覆盖九类异常/中断；`-Mode dual -BrokenDual`故意破坏第二路写回，预期返回1。新增数据采样会改变没有请求时的空闲地址，`-CompareIdleBus`保留旧诊断且预期在第2085周期报告空闲地址差异，不能将它称为事务不一致。

新默认寄存重定向有真实恢复延迟，使用`run_redirect.ps1 -Test ordered -Mode both -Seed 37`验证；另外复测1234567/271828种子。每个原核/候选执行均有独立镜像、随机接纳背压和0~3拍响应等待；同步异常模式比较完整按序WB载荷、store及异常轨迹，844次完成/91次store，不要求周期相同。`-Interrupt`单独运行IRQ/mret自检，异步IRQ入口不要求逐条轨迹相同；`-Broken`破坏真实load数据并要求拒绝。它们是定向差分仿真，均不是完整ISA或形式证明。

`run_redirect.ps1 -Test frontend`检查寄存边界、在途返回、请求/输出背压和连续重定向；`-LegacyFrontend`应因原组合绕过而失败。`-Test payload/muldata/csrdata`分别检查issue及乘法/CSR的数据采样与有效位隔离。`-Test mularith`用独立整数模型校验四种乘法、气泡和hold，`-Broken`注入真实结果错误并要求拒绝。这些测试不增加生产源清单；原模块仅在仿真清单中作对照。

`run_route.ps1`运行单发射完整compile/synthesize/dev_map/pnr/report_timing。独立`cpu_route.json/.fdc`声明10ns、同钟I/O max2/min0.5ns、setup/hold不确定度0.1/0.05ns，没有false path或multicycle例外；管脚由工具自动布局。这是CPU隔离诊断的边界假设，不是正式SoC或板卡契约。PNR上限10分钟、外层900秒；每次新目录，保存源、数据库和最终报告哈希。仅所有实际时序检查通过才返回PASS；工具成功但时序违例记录为TIMING_FAIL，入口返回2。

`review_route.ps1 -RunDirectory <既有运行目录>`只读核验冻结源/输出、实际原生退出码、阶段标志、参数及最终时序，另存新收据，不回写旧result。PDS可能将逻辑表达式参数打印为`1'b1`；解析器同时接受正确的1位/32位值，并检查前端寄存选择和外层MMU仍关闭。

后续以实际STA路径判断，完整ISA/异常、正式SoC/DDR/NPU集成与板测另行验收。CoreMark在配置或硬件行为改变后按相同边界复测。当前时序候选与逐轮结果见STATUS及`redirect_timing_plan.md`；不将局部改动或工具PASS称为100MHz通过。

`run_redirect.ps1 -Test training`验证完整训练事件寄存，包含call/return/jump和没有miss请求的BHT更新。旧训练时序的物理运行只读复核须显式使用`review_route.ps1 -LegacyTraining`，正常新运行仍强制REGISTER_TRAINING=1。第4轮不作为已通过时序的部署版，原始结果见`training_timing.json`。

`run_redirect.ps1 -Test requestdata`检查请求地址格式/store数据不依赖晚到valid、有效控制关闭、未接纳请求载荷保持及fault取消/badaddr；`-Test loadbypass`保留返回数据与精确异常的分离检查。第8轮实际100MHz仍TIMING_FAIL，详见STATUS和`request_payload_timing.json`。

`run_redirect.ps1 -Test lanedata`检查对齐fetch packet的原始lane选择独立于完整PC/valid，而错PC/空lane仍关闭发射和消费；该契约依赖当前FIFO的pc0/pc1固定word位置。第9轮CPU-only7175 LUT/6084 FF，实际100MHz setup仍为-3.064ns，证据`lane_payload_timing.json`。

单发射寄存器堆在`triha_regfile.v`使用两份原生异步读分布式RAM及同步复位可见标记，次写口必须为0；双发射保留原实现。`run_regfile.ps1 -Backend candidate`运行独立组件oracle，`-Stage map`核对真实分布式RAM/FF资源，`-Broken`要求拒绝输出损坏。原语模型路径与哈希见`config/cpu_primitives.json`，由仿真公共入口绑定。最新整核6833 LUT/5123 FF，100MHz Slow setup仍-4.659ns，证据`distributed_regfile_timing.json`。

`triha_divider.v`默认为原除法器增加一拍完整输入寄存，DIV/REM完成流延后一周期，原算法/缓存/重启不变；`run_redirect.ps1 -Test divarith`验证独立数值及对原模块的一拍输出流关系，`-LegacyDivider`应触发延迟契约RED，`-Broken`必须拒绝。旧逐周期整核miter显式关闭此寄存，新默认用按序回归。旧物理结果复核另加`-LegacyDivider`，需要时与`-LegacyTraining`组合；新PDS运行必须核对CPU/wrapper寄存参数均1。第11轮实际100MHz仍TIMING_FAIL，见`divider_input_timing.json`。

`triha_decode.v`维护FIFO空槽宽载荷采样，计数/指针/有效/fault控制不变，并保留无效槽的原始CSR历史分类，避免影响IRQ inhibit。`run_redirect.ps1 -Test fifodata`比较2023周期的控制、有效载荷和CSR历史，覆盖X数据；`-LegacyFifo`是原连接RED，`-Broken`注入真实损坏。第12轮实际100MHz仍失败，见`fifo_payload_timing.json`。

E2/WB数据旁路使用独立于当前stall的已注册目的tag，提交/RF写口/scoreboard仍用原tag，实际发射时断言两者相等。`run_redirect.ps1 -Test bypasstag`覆盖停顿、返回恢复及fault取消；第13轮CPU-only6685 LUT/5209 FF/32分布式RAM单元，实际100MHz setup Slow/Fast -3.486/+1.027ns，仍未通过，见`bypass_tag_timing.json`。

PC顺序增量提前计算，并保留有用组合边界，单发射不生成未用PC+8；`run_redirect.ps1 -Test pcupdate`检查原优先级和32位算术，`-Broken`必须拒绝。`check_pc_carry.py <ADS网表> --output <收据>`只检查本层PC数据锥的carry依赖，显式保留子模块边界，不是STA。第14轮CPU-only6713 LUT/5209 FF，实际100MHz setup Slow/Fast -3.247/+1.018ns，仍未通过，见`pc_increment_timing.json`。

LSU深度2请求队列按head/tail寄存存储，保持原全部有效及无效残留输出、接纳和pop规则；不增加load周期。`run_redirect.ps1 -Test lsuqueue`比较深度2/4各10001周期并使用独立有效流oracle，`-Broken`必须拒绝。`check_lsu_head.py`核对实际ADS网表36位输出直接来自FF，仅为本层结构检查。第15轮实际setup Slow/Fast -4.936/-0.103ns变差，CPU-only6806 LUT/5207 FF；保留为诊断检查点，非部署验收，见`lsu_head_timing.json`。
