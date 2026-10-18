# TriHaRiscv 总工程工作约定

## 权威来源与范围

- 当前主工程是本目录 `TriHaRiscv-main`。规格依据为 `docs/TriHaRiscv_SoC_Design_Spec_v0.6.md`。
- `D:/FPGA/TriHaRiscv-v3` 及独立 CPU 工程仅为来源/验证记录，不能把它们的旧应用、地址、格式或路径规则带入总工程。
- 用户当前已授权开始 Video 路线实施，优先 Windows 原生开发、参考例程复用和尽快上板。旧 README 的“暂不迁移”历史状态已结束；复用仍须逐项验证。
- 现有 `docs/technical-report/` 修改属于独立工作，遵守其局部 AGENTS，不覆盖、不连带提交。

## CPU 路线最新约束（2026-10-18）

- 用户已将本目录确认为当前主工程；CPU 选型与维护位置见 `docs/cpu/README.md`。旧 `TriHaRiscv-v3-cpu-dualissue` 不属于本仓库工作树，只作源码来源、备份和历史证据，不能继续作为正式 CPU 维护主线。
- CPU 当前硬件要求为 Pango、RV32I，另要求直接维护 Verilog 实现，开发环境集中在 Windows + Codex + ModelSim + PDS + RISC-V GCC；不引入 Scala/Spinal/Chisel/Bluespec 或 HDL 降低工具链，不把 WSL 设为新 CPU 流程前提。复用已安装 Windows 工具和本工程已有脚本能力，不另建环境。
- CPU 仍需评估 CoreMark、退休 IPC、CPU-only 资源及实际 100MHz 后布线时序。M/C/PMP/Cache/发射宽度按实际需求选择；v0.6/旧 README 中 CPU 固定功能清单与这些最新指示冲突时，以用户指示为准。系统地址、MMIO、DDR、帧所有权等独立契约不能随 CPU 选型擅自改变。
- CPU 源码及适配放 `rtl/cpu/`，SoC 互连放 `rtl/soc/`，板级适配遵守本仓库 `fpga/pg2l100h/` 结构；不复制旧 SoC、旧地址表或旧 `targets/pango676` 工程覆盖新主工程。工程、目标、分支和运行提示统一使用 TriHa/CPU 命名；来源与许可保留在独立清单和许可证中。
- 用户确认保留新主工程顶层，CPU 内部沿用旧工程风格：四空格缩进、ANSI Verilog端口、`clk_i/rst_ni`、`*_i/*_o`、`u_*` 实例和职责清楚的模块/文件头。第三方原始文件保持字节和许可不变，不为统一风格批量改写。
- 性能基准固定为CoreMark v1.0；软件工具目标为RV32裸机GCC。Windows GCC15.2.0已安装在`D:/AI_Tools/xpack-riscv-none-elf-gcc-15.2.0-1/`，用户接受实际前缀`riscv-none-elf-`，以RV32/ILP32能力为准；配置与检查入口为`config/cpu_toolchain.json`、`scripts/cpu/check_toolchain.ps1`。记录真实工具名和校验值，不改名伪装目标三元组。
- 共享目录当前承载 Video 工作。需要独立 CPU 分支时，从本仓库建立独立 Git 工作树，使用相同相对目录，避免在共享目录切换分支或复制成另一套长期独立工程。选型/目录评估不等于已建立 CPU 工作树或已执行实现。

## 目录与责任

- CPU：`rtl/cpu/`、`rtl/soc/`、`sw/drivers/`、`sw/runtime/`，负责正式互连、地址属性、固件和统一帧状态。
- NPU：`rtl/npu/`、`model/yunet/`，负责模型清单、真实量化参数、整数参考及算子。
- Video：`rtl/video/`、`tb/video/`、`scripts/video/`、`fpga/pg2l100h/` 中 Video 文件及后续 `assets/avatars/`。
- `config/` 保存公共权威配置；生成 RTL/C 定义不分别手改，修改后运行生成器和 `--check`。
- `fpga/.../project/` 保存显式目标/filelist，禁止递归收集所有 RTL 作为正式构建输入。
- 原始厂商包不修改；选中文件按版本/哈希提取到 `build/video/vendor/`。IP 实例配置/来源清单纳入版本，生成库/网表/临时工程不纳入版本。
- 所有波形、日志、PDS 输出、临时转储统一进入已忽略的 `build/`；文档保留小型证据摘要和原始结果定位。
- 不提前创建大量空目录；实现与对应测试同时落到职责目录。

## Windows 工具与命令

默认入口是 PowerShell + Python 3.11 及以上，不要求 WSL、bash、make 或 Linux 路径转换。

```powershell
python scripts/video/doctor.py
python scripts/video/gen_config.py --check
python scripts/video/prepare_reference.py --reference hdmi
python scripts/video/prepare_reference.py --reference ddr
python scripts/video/run.py --suite all
python scripts/video/build_pds.py --target video_timing --stage synth
python scripts/video/build_pds.py --target video_board_smoke --stage bitstream
python scripts/video/package_board.py
python scripts/video/scan_board.py --start-server
```

工具通过 PATH、`TRIHA_IVERILOG`、`TRIHA_VVP`、`TRIHA_PDS_SHELL`、`TRIHA_VSIM`、`TRIHA_TAR` 及已安装默认位置发现；工具覆盖变量填写可执行文件路径。板卡包可通过 `TRIHA_BOARD_ROOT` 或命令参数指定。Python 文本文件显式用 UTF-8，不依赖 Windows 默认代码页。

## 验证与交付

- 新硬件行为先建立可失败的自校验测试，再实现；数值 oracle 依据规格独立定义。
- 失败返回非零。新运行先使旧成功标志失效，构建使用独立目录；保存输入哈希、工具版本和结果。
- 分别报告组件仿真、综合、布局布线、物理时序、板测；不得以其中一项替代另一项。
- `video_timing` 是便携时序/彩条组件，尚无 HDMI/PLL/DDR/板级管脚。它的综合成功不能用于下载或宣称板卡已点亮。
- `video_board_smoke` 为 TX-only 板级彩条，包含 40/10 MHz PLL、独立发送初始化和官方 HDMI 管脚；只读扫描与实际下载分别记录。内部时序通过不等于 MS7210 外部 I/O 时序已验证。DDR/RX 不包含在此目标中。
- Video 不自行假定 NPU 量化尺度或 CPU 的总线写可见性；未冻结契约在接口文档和任务表中明确记录。
- 每批更新 `docs/video/STATUS.md`，列出本批证据、未完成项、依赖及下一步。
- Git 保留小范围可审查变更，禁止 `git add .` 连带其他路线修改；不在并行任务使用的共享目录反复切换分支。当前 Video 分支为 `video/windows-bringup`。
