# Windows Verilog CPU 首批实施设计

用户已确认：保留新主工程顶层，CPU 内部沿用旧工程风格。主仓库为 `D:/FPGA/TriHaRiscv-main`；本次实施工作树为 `D:/FPGA/TriHaRiscv-cpu-windows`，分支 `cpu/windows-baseline`。旧双发射工程保留作来源与历史证据。

## 本批目标和边界

建立能够独立复现的 Windows ModelSim CPU 基线：固定内核来源、旧风格 `triha_core` 封装、上游测试程序、单/双发射冒烟和真实失败程序/超时负例。ModelSim 初始启动与许可检查已返回 0；当前 CPU 目录为空，因此没有既有 CPU 回归可先跑。已有 Video 配置 `python scripts/video/gen_config.py --check` 通过。

本批不接入正式 SoC，不改变 Video/DDR、地址表或帧管理接口。首个程序的 128KiB TCM 和 `0x80000000` 启动位置属于上游测试平台，不是最终 Boot ROM/SRAM/DDR 产品地址配置。PDS/CPU-only 资源、100MHz 后布线、完整 RV32I/ACT4 和 CoreMark 为后续验收，不能由此冒烟替代。

## 目录与源码风格

- `rtl/cpu/triha_core.v`：手写产品边界，四空格缩进、ANSI 端口、`clk_i/rst_ni`、`*_i/*_o`、`u_*` 实例，文件头说明用途/接口和来源。时序逻辑用非阻塞赋值，组合逻辑完整默认值；明确常量宽度。
- `rtl/cpu/vendor/`：上游原始 Verilog、LICENSE、文档、测试映像及 UPSTREAM.json；文件字节与 commit `6af9c4be5a0807d368eaad5e49af52322e31d073` 清单一致。上游命名、格式和许可不改写为本地风格，不加参赛团队原创声明。
- `tb/cpu/`：旧式 `tb_*` 自校验 Verilog；只在测试平台引用上游内部 CSR/issue 信号。发射计数单列，不称退休 IPC。
- `scripts/cpu/`：原生 PowerShell 运行入口及 ModelSim `.do`。使用已装 ModelSim、.NET 和 PowerShell，无新环境或包管理器。PDS 后续沿用 `fpga/pg2l100h/` 的显式目标清单。
- `config/cpu_sources.f`：明确模块清单，不递归编译整个 RTL 树；不引入上游 Xilinx 原语文件或追踪模块。
- `build/cpu/`：每次独立运行目录，包含 work 库、ELF 导出 BIN、日志、输入/输出哈希和 result.json；失败不得复用上一轮 PASS。
- `docs/cpu/`、`docs/verification/cpu/`：维护入口和小型证据。

CPU 内部模块复用上游划分，不把上游六级强行重命名成旧五级 stage1..stage5。以后新增本地控制/缓存模块时再采用旧工程 ctrl/pipeline/mmu 的职责划分，不创建空目录或复制一套未使用模块。

## CPU 封装和数据流

`triha_core` 直接实例化 `riscv_core`，仅适配复位极性、端口命名和固定参数，不加入额外流水/队列。64位取指、32位数据及11位事务标签按上游协议完整导出；flush/invalidate/writeback 信号保持可见，未接正式缓存前由测试模型正确应答。

固定六级：EXTRA_DECODE_STAGE=0；关闭 SUPER/MMU/Xilinx 寄存器堆；保留 RV32M、基本 CSR、旁路和上游预测，以免把最低 RV32I 要求误当成必须牺牲性能。仅暴露 DUAL_ISSUE 作为当前单/双发射评估参数，默认 0；两种模式均执行同一程序。产品 ISA、Cache 和预测尺寸后续以测量冻结，暂不宣称完整架构合规。

## 自校验与错误处理

1. 上游 ELF 首先验证 SHA256；使用 PowerShell/.NET 按 ELF32 little-endian PT_LOAD 段生成 TCM BIN。检查 RISC-V machine、入口、段大小/偏移与地址范围，禁止越界。Windows GCC 不在 PATH 的情况明确保留，不为此安装工具；已有 ELF 冒烟不表示新的 GCC 构建链通过。
2. 测试平台在复位期间初始化 RAM，在负边沿后释放复位。替换上游非标准 `$fopenr` 用法，复用其 TCM 模型，不改生产核。
3. 上游 SIM_CTRL 的退出码经实际 CSR 写入检测；非零必须失败。测试平台输出字符和退出状态，不在生产 RTL 定义仿真控制宏。
4. 单发射模式不允许出现双发射；双发射模式必须实际发生配对，且检查同对 RAW/WAW 和年轻指令独自接受。该范围不等于完整退休正确性。
5. 失败程序由 `addi a0,zero,1; csrw 0x8b2,a0` 实际执行并返回 1，验证宿主入口不能只凭 ModelSim 退出 0 接受结果。另以缩短最大周期验证超时被拒绝。
6. 每个 native 进程设置墙钟上限；只清理本次启动的进程树。result.json 保存本次状态、命令返回码、输入哈希、工具版本和实际输出哈希；只有退出码/完成标记及所需软件检查项一致时 PASS。

## 后续顺序

本批结束后建立正式 ISA/异常/访存测试与 CoreMark 移植，测单/双发射性能，再做 Pango CPU-only 综合、RAM/APM 映射和原100MHz约束的双corner后布线。依据真实数据决定交付模式；不得把公开分数、本批issue计数或工具启动成功当作性能/时序验收。

## 用户后续指示

用户确认Windows GCC原先未安装，接受实际发行前缀，以RV32/ILP32能力为准；性能基准固定CoreMark v1.0。因此本批补充Windows预编译GCC安装/归档校验、两个RV32配置的实际编译与ELF检查，并固定CoreMark源码/许可。此项替代前文“本批不安装GCC”的初始范围假设；不新增其他工具环境。
