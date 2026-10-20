# CPU板级现场验收

2026-10-20：HIGH带宽PLL修正版已在PG2L100H/FBG676/-6实物通过Program/Verify、8KiB软件自检、持续UART和实体KEY0重启。用户明确“不用恢复”，板卡当前保留CPU易失配置，未恢复Video、未写Flash。源码提交3e73c28，验收备份标签cpu-board-physical-pass-20261020；独立CPU工作树保留，未合入或push。

## 镜像与物理时序

[当前下载包](../../../build/soc/releases/cpu_board_df5475cbb154/README.md)；[冻结哈希](board_pll_high_package.json)；[独立STA](board_pll_high_route.json)。包的README/manifest保留打包时尚未下载的快照，本文件和现场证据记录随后实际操作，不修改包内字节。

位流SHA256为`df5475cbb1543dbcaa264d1e26a2eca05b20019e87c29b65a3b8ab5d41c70704`，对应掩码`df20d8f7be3d5058915405f084e2650a9a04303297d566fb4d2572f8bfe991c6`。完整新compile/synthesize/dev_map/pnr/report_timing/gen_bit_stream及宿主均返回0，46项输入、328项输出和10项包文件哈希核验。

N3/N2标称125MHz参考、PLL I1/M1/F8/O10、BANDWIDTH=HIGH得到标称100MHz。原100MHz、IO max2/min0.5ns、setup/hold uncertainty及实际PLL总setup uncertainty0.250ns保持，无新增false path/MCP。

| 检查 | Slow/ns | Fast/ns |
|---|---:|---:|
| Setup | +0.023 | +1.752 |
| Hold | +0.155 | +0.100 |
| Minimum pulse width | +3.655 | +4.202 |
| Recovery | +2.056 | +4.164 |
| Removal | +0.739 | +0.499 |

全部零违例，performance slack与最差setup一致。CPU-only5977LUT/5172FF/64分布式RAM/0DRM/4APM，排除SRAM/ROM、PLL和板级外围。六级单发射、RV32IM/CSR、BTB32/BHT512/RAS8、GShare关闭、无I/D Cache；CPU RTL及固件未因PLL修正改变。

## 实际下载、软件与按键

原始记录目录`build/soc/board-pll-high-program-20261020T030627030226Z`。UART在下载前以Windows SerialPort开启COM12/115200/8N1，不发送字节或控制DTR/RTS。JTAG识别00602899，cfg_program和cfg_verify均实际成功，原生退出0；回读掩码与下载位流按包哈希绑定。

软件由真实ROM跳转进入SRAM运行，输出`CPU_BOARD_PASS checked_bytes=8192`，随后持续`CPU_ALIVE seq=... cycle=...`。下载窗口存在两个初始启动epoch（2条及108条ALIVE）；后一个连续107.34个标称秒，序号从0递增到107。之后在Program/Verify已结束的独立观察窗口，用户确认短按一次实体KEY0。该窗口恰好出现一个新的完整PASS banner，ALIVE从0重新开始，随后54条连续记录、53.17个标称秒。总164条ALIVE均通过序号和32bit cycle回绕/间隔检查，无CPU_BOARD_FAIL或CPU_TRAP。按键窗口没有其他JTAG操作。

[现场机器证据](board_system_physical_acceptance.json)核验所有原生工具、Program日志、原始uart.bin、按键前字节偏移、用户确认和包文件哈希。上述时长根据真实cycle计数按标称100MHz换算，不是校准仪器测频。软件自检只覆盖其拥有的8KiB缓冲，不能称32KiB全地址现场验收。没有据此推断LED极性或校准物理PLL频率。

## 已保留的失败与准入边界

旧5f5eb8c89efd虽然STA/Program/Verify通过，实物没有CPU输出。独立27MHz诊断观测到参考存在、KEY0松开、PLL不锁定、CPU复位未释放。单独增加PLL复位未解决；仅改HIGH带宽后锁定和CPU启动均通过。失败记录、UART及对照完整保留：[首次尝试](board_startup_attempt_20261020.json)、[原PLL观察](board_pll_diagnostic_20261020.json)、[带宽对照](board_pll_bandwidth_diagnostic_20261020.json)、[修正说明](../../cpu/board_pll_bandwidth_fix.md)。

CoreMark仍引用未变CPU/系统的短RTL结果1685831周期、1467843WB观察、IPC0.870694、短估算2.965896/MHz；非官方或板级CoreMark。完整ISA/异常准入、DDR/Video/NPU系统集成和更长压力测试另行完成。当前是可重新下载的CPU片上最小系统，未写入Flash，不宣称断电后自动加载此CPU镜像。
