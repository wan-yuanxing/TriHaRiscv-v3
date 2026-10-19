# CPU板级最小系统实施计划

执行：使用executing-plans和test-driven-development，在本会话逐项完成；复用现有独立工作树，不使用agent。

**目标：** 将已通过的CPU片上系统接入真实板级100MHz PLL/复位/管脚，生成经核验的可下载包。

**架构：** `triha_cpu_board_top`封装现有`triha_minimal_soc`；配置权威为`config/cpu_board.json`，PLL生成物和所有运行输出保存在`build/soc/`。Windows PowerShell/Python、ModelSim、PDS、GCC保持不变。

- [x] 核对工作树、备份标签、干净基线及6项配置工具测试；确定125MHz参考的精确100MHz PLL方案。
- [x] `scripts/soc/test_board_tools.py`先实际RED；实现`gen_board.py`和板级配置，验证真实PLL分频、管脚唯一性、配置漂移和IDF/工具哈希。当前9项通过，包含实际PLL参数、Windows符号行尾与重复符号拒绝。
- [x] `tb/soc/tb_cpu_board_clock.v`先实际RED；实现板级时钟复位封装，以真实Pango模型核对100MHz周期、三拍释放、按键保持及失锁。111项通过。
- [x] 新增`sw/tests/cpu_board.c`、`tb/soc/tb_cpu_board.v`和独立入口，整核验证8KiB自检、串口、KEY0重启及真实损坏拒绝。两次启动通过；真实SRAM初始化字节损坏报告code1并被拒绝。
- [ ] 添加显式板级PDS目标、独立完整运行及报告复核入口；检查六项实际STA、CPU配置、PLL及管脚，时序通过后生成位流/掩码。
- [ ] 打包位流、掩码、固件/报告/哈希/恢复说明；更新CPU STATUS与证据，精确标明未Program/未板测。

验证命令：`python scripts/soc/test_board_tools.py`；`python scripts/soc/gen_board.py --check`；`python scripts/soc/run_board.py --test clocks`；`python scripts/soc/run_board.py --test system`；`python scripts/soc/run_board.py --test system --fault memory`；`pwsh -NoProfile -File scripts/soc/run_board_route.ps1 -FirmwareRunDirectory <system运行目录> -ClockRunDirectory <clocks运行目录>`。失败记录保留、返回非零，不重写原100MHz通过记录。

2026-10-20推进：原CPU已从诊断标签恢复；真实高PFD PLL的111项模型检查、两次整核启动及单字节真实损坏拒绝通过。板级STA仍未通过，当前核验Performance模式，禁止提前生成/交付包。已补4项选定路由数据库绑定测试；串口解析6项，配置工具9项。
