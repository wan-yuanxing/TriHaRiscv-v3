# Windows 原生工具链验证

日期：2026-10-16。当前流程不依赖 WSL、bash 或 make。脚本只使用 Python 标准库，最低 Python 3.11；路径支持空格，源码文本显式 UTF-8，进程以参数列表启动。

| 工具 | 本机位置/版本 | 已验证范围 |
|---|---|---|
| Python | `D:/miniconda3/python.exe`，3.13.13 | 配置生成、测试、参考提取、回归/PDS 驱动 |
| Icarus/vvp | `D:/iverilog/bin/`，12.0 devel | 完整三帧时序/像素与复位测试 |
| PDS | `D:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe`，2022.2-SP6.4 build 146967 | 最小设计及 Video 时序/彩条组件编译综合 |
| ModelSim | `D:/modeltech64_2020.4/win64/vsim.exe`，SE-64 2020.4 | 原生 vlib/vlog/vsim -c 小型 smoke，0 errors/0 warnings |
| IP generator | 同 PDS 的 `bin/ip_generate.exe` | 原始 cfg_pll（27→10 MHz）的 IDF 生成 wrapper |
| tar | Windows 自带 bsdtar 3.8.8 | RAR 包选中成员无损读取、包和成员哈希核对 |

PDS 的综合和 ModelSim 的小型仿真已实际运行，超过仅查询版本的范围。但 DDR 加密控制器/PHY 的编译、许可、完整仿真仍需实际运行确认；普通 ModelSim smoke 成功不代表受保护 DDR IP 一定可用。

## 使用与覆盖

```powershell
python scripts/video/doctor.py
python scripts/video/gen_config.py --check
python scripts/video/run.py --suite all
python scripts/video/build_pds.py --target video_timing --stage synth
```

脚本按显式 `TRIHA_工具名`、PATH、本机已知安装位置发现工具。环境变量只填写可执行文件路径，不填 shell 命令。`TRIHA_BOARD_ROOT` 指定板卡包根目录；也可直接传 `prepare_reference.py --board-root`。

`doctor.py` 的成功表示必需工具能查询版本，不自动等价为后续构建或许可通过。ModelSim 为可选发现项；Icarus 不支持厂商 IEEE1735 保护模型，不能拿行为内存模型替代 PHY 板测证据。

## 运行记录

- 工具发现：`build/video/doctor.json`。
- 原生工具运行审计：`build/video/audit/native_smoke_20261016_145614/results.json`；ModelSim marker 为 `NATIVE_SMOKE_PASS`。
- 正式回归与综合：`build/video/latest_all.json`、`latest_pds.json` 指向各自独立运行目录。
- 小型可版本化摘要：`docs/verification/video/evidence/windows_kickoff.json`。

PDS 执行前创建 work_dir，进程 cwd 与 work_dir 一致，防止工具把产物落到源码目录。当前 `build_pds.py` 仅开放组件 synth；尚未实现 board route/bitstream/download，不能用自动分配管脚的组件产物上板。

固定时序组件综合结果为 53 LUT、21 寄存器、0 DRM；输出端口尚无板级 I/O 时序约束，不能据此宣称 40 MHz 板级时序闭合。下一步围绕 40 MHz PLL、TX 初始化和实际板卡约束建立独立目标。
