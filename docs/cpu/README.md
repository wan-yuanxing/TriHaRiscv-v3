# CPU 开发与维护入口

更新：2026-10-18。主工程为 `D:/FPGA/TriHaRiscv-main`。本文件确定 CPU 的源码归属、开发位置和集成边界；目前未导入 CPU、创建开发工作树或执行新的仿真/PDS。

## 当前检查结果

- 主仓库 HEAD：`f21f01186ae0f1c03e38890bfefd4b3f53af732d`；检查时分支为 `video/windows-bringup`。
- `rtl/cpu/`、`rtl/soc/`、`tb/cpu/`、`tb/soc/` 均只有 `.gitkeep`，尚无正式 CPU 实现。
- `fpga/pg2l100h/` 已有 Video 的显式工程清单、约束、IP 来源与板级封装。CPU 应沿用这一套目标目录，而非迁入旧 `targets/pango676/`。
- 当前工作区有 Video 和技术报告修改，必须保留。`git worktree list` 当前只列出主工程；旧 CPU 目录不是本仓库的附属工作树。
- 已有 DDR 接口契约位于 `docs/interfaces/ddr_wrapper.md`。其 AXI128/HMIC256、时钟域、完成/错误和写后可见性规则是新 CPU/互连需要适配的接口，不能拿旧工程同名接口替代。

## 选型与工具要求

以 biRISC-V 为首选准入候选，直接维护 Verilog-2001 源码及窄适配。固定来源：`https://github.com/ultraembedded/biriscv`，commit `6af9c4be5a0807d368eaad5e49af52322e31d073`，Apache-2.0。旧 CPU 工程 `third_party/biriscv/UPSTREAM.json` 保存来源和文件哈希，可作为导入核对依据。导入时只取显式需要的文件，不把上游测试顶层、Xilinx 专用寄存器堆或旧 SoC 自动加入 PDS。

用户指定 Windows + Codex + ModelSim + PDS + RISC-V GCC。CPU 仿真主入口采用 ModelSim Tcl/.do；PDS 原生 Tcl；固件由 Windows RISC-V GCC/binutils 构建；PowerShell 负责串联。可复用主工程已存在的 Windows 脚本能力，但不能为了 CPU 引入另一套环境、包管理器、生成语言或 WSL 依赖。当前 ModelSim 在 `D:/modeltech64_2020.4/win64/`，PDS 在 `D:/pango/PDS_2022.2-SP6.4/`；Windows GCC 路径尚待定位，未在 PATH 找到不代表未安装。

Pango、RV32I 为硬件硬要求；M/C/PMP/Cache/双发射结合性能与成本选择。v0.6 的固定 RV32IMC/Cache/BPU 清单为此前规格，涉及 CPU 的冲突项以最新用户指示为准，正式产品配置需要后续冻结。系统总线、地址、帧管理与 Video/NPU 契约继续按主工程维护。

先建立六级单发射功能基线，然后用同一软件/存储边界评估双发射收益。CoreMark、退休 IPC、CPU-only 资源和实际 100MHz 后布线结果共同决定交付配置；上游 4.1 CoreMark/MHz 不是本机成绩或单发射承诺。

## 正式源码布局

以下均相对主仓库根目录。只在产生实际源码或测试时建立对应文件，不预建大量空目录。

| 位置 | 维护内容 |
|---|---|
| `rtl/cpu/biriscv/` | 固定上游 Verilog 核；保存 LICENSE、UPSTREAM.json、文件哈希及本地差异记录 |
| `rtl/cpu/` | 产品 CPU wrapper、参数绑定、通用内存/总线适配；保持与上游核的来源边界 |
| `rtl/soc/` | 正式互连、AXI/MMIO、外设、IRQ、系统复位和 SoC 顶层；以新主工程契约为准 |
| `tb/cpu/`、`tb/soc/` | ModelSim 自校验测试平台、ISA/冒险/异常/访存/退休检查及集成模型 |
| `scripts/cpu/` | Windows 固件构建、ModelSim `.do`、PDS Tcl/PowerShell 入口；运行目录一律独立 |
| `sw/runtime/`、`sw/drivers/` | 启动、链接布局、平台运行时与驱动 |
| `sw/tests/`、`sw/benchmarks/coremark/` | CPU 测试程序和固定版本 CoreMark 移植；保留软件来源许可 |
| `config/` | CPU 产品配置及公共地址/寄存器的权威定义；RTL/C 定义同源生成 |
| `fpga/pg2l100h/rtl/` | Pango RAM/DSP/时钟/复位适配和 CPU 独立物理顶层，按文件区分 CPU/Video 责任 |
| `fpga/pg2l100h/project/`、`constraints/`、`ip/` | CPU 专用显式 filelist、PDS 目标、约束及 IP 配置；引用同一份源码，避免整树递归收集 |
| `docs/cpu/`、`docs/verification/cpu/` | 配置、来源/差异、维护状态、测试方法与小型证据索引 |
| `build/cpu/` | ELF/HEX、ModelSim work 库/波形、日志、PDS 工程/网表/报告；已由根 `.gitignore` 排除 |

本地修改尽量放在 wrapper/adapter；确需改上游核时，记录基准 SHA、改动原因和验证，不在多个目录保存可编辑的同名 CPU 副本。Pango 原语只进入目标适配层。便携模型与真实 IP 的验证结果分别报告。

## 开发工作区与长期维护

**长期维护归属：本主仓库。**建议实际 CPU 编码使用由本仓库创建的独立工作树，候选路径 `D:/FPGA/TriHaRiscv-cpu-windows`、候选分支 `cpu/biriscv-windows`，以避免与当前 Video 未提交工作相互影响。这是建议位置，尚未创建。

工作树沿用以上相对路径，使用同一 Git 历史。通过审查后以小范围提交集成回主仓库；不靠长期手工拷贝同步。CPU 开发独立运行自身目标；需要最新未提交 Video/DDR 改动时，先核对其来源/接口和提交状态，不能假定新建工作树自动包含主目录未提交文件。共享 DDR/Video 代码保持一份权威实现，不在 CPU 目录复制改名维护。

`D:/FPGA/TriHaRiscv-v3` 和 `D:/FPGA/TriHaRiscv-v3-cpu-dualissue` 保留为原始来源、备份与历史验证记录。后续不在其中开发新的正式 CPU；新构建不跨目录依赖旧核源码或旧库。必要源码导入新仓库后按来源/哈希维护，历史仿真、综合、时序 PASS 不能代替新配置验收。

本次仅新增维护入口及根目录 CPU 约定，未调整当前分支、复制 RTL、迁移旧 SoC、改动 Video/技术报告或启动板卡操作。
