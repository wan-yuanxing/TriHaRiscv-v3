# TriHa CPU 开发与维护

主工程：`D:/FPGA/TriHaRiscv-main`。CPU 工作树：`D:/FPGA/TriHaRiscv-cpu-windows`，分支 `cpu/windows-baseline`。更新：2026-10-18。

Windows ModelSim基线、GCC裸机启动、CoreMark1.0短RTL测量和CPU-only Pango综合/映射已经建立，并完成首轮隔离后布线；100MHz setup尚未收敛，详见 [STATUS.md](STATUS.md)。正式SoC、完整ISA及板测仍需后续验收，主目录中的Video分支尚未合入本批CPU RTL。

## 目录与旧工程风格

用户确认：保留新主工程顶层，CPU 内部沿用旧工程的 Verilog 风格和职责划分。

| 位置 | 内容 |
|---|---|
| `rtl/cpu/triha_core.v` | CPU 产品封装，默认单发射，固定六级；完整导出取指/数据/缓存维护协议 |
| `rtl/cpu/triha_cpu.v`、`ADAPTATIONS.json` | 直接维护的内部连接派生Verilog及差异哈希；单发射不生成第二执行单元，保留共享CSR/异常控制 |
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

单发射已条件裁剪第二执行单元；原始连接仅在差分测试中作父版。`run_equivalence.ps1`使用相同背压TCM对父版/候选作逐周期总线、WB、预测和CSR状态比较，程序覆盖九类异常/中断；`-Mode dual -BrokenDual`故意破坏第二路写回，预期返回1。它属于定向差分仿真，不是完整ISA或形式证明。

`run_route.ps1`运行单发射完整compile/synthesize/dev_map/pnr/report_timing。独立`cpu_route.json/.fdc`声明10ns、同钟I/O max2/min0.5ns、setup/hold不确定度0.1/0.05ns，没有false path或multicycle例外；管脚由工具自动布局。这是CPU隔离诊断的边界假设，不是正式SoC或板卡契约。PNR上限10分钟、外层900秒；每次新目录，保存源、数据库和最终报告哈希。仅所有实际时序检查通过才返回PASS；工具成功但时序违例记录为TIMING_FAIL，入口返回2。

下一步依据真实异常/取消到前端PC/预测路径，区分外围I/O布局和核内组合依赖，再验证具体优化；完整ISA/异常、正式SoC/DDR/NPU集成与板测另行验收。CoreMark在配置或硬件行为改变后按相同边界复测。
