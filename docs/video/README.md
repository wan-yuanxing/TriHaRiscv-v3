# Video 开发入口

本路线使用 Windows 原生 Python、Icarus、ModelSim、PDS。总范围见 [路线计划](../superpowers/plans/2026-10-16-video-route.md)，实际完成情况以 [STATUS](STATUS.md) 为准。

## 目前可以运行

从仓库根目录的 PowerShell 执行：

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

配置更改后先执行 `python scripts/video/gen_config.py`，再执行 `--check`。当前只接受 v0.6 固定模式，修改规格后才扩展模式校验。`--suite all` 运行当前已实现的配置/参考、彩条、实际 PLL/复位、发送初始化、板级输出集成和输入帧几何监测；不代表物理采集/DDR/推理已经通过。另用 `--suite tx_init_full` 保留真实约 320 ms 等待验证初始化。

彩条目标的管脚、LED、复位、下载与时序边界见 [板测说明](../verification/video/board_smoke.md)。

工具覆盖、版本与运行证据见 [Windows 工具链](../verification/video/toolchain.md)。`prepare_reference` 默认只提取清单中的已验证文件，并不生成完整可综合 DDR IP；完整依赖 staging 属于后续板级任务。

## 当前文件树

```text
config/video_cfg.json                    固定模式与图像布局权威配置
rtl/video/
  include/video_cfg.vh                    生成的 RTL 常量
  video_timing.sv                         800×600 扫描计数与同步
  video_test_pattern.sv                   RGB888 八色条
  video_pattern_core.sv                   便携综合边界，外部提供 40 MHz
  video_rx.sv                            候选 RGB888 坐标、完整帧几何和就绪丢失监测
sw/include/video_cfg.h                    同源生成的 C 常量
tb/video/
  tb_timing.sv                           完整光栅/像素/复位自检
  test_config.py                         固定模式、生成一致性、漂移拒绝
  test_references.py                     提取字节、哈希失败、目录越界检查
  test_pll.py / test_pds_messages.py     实际分频、生成器失败失效、PDS 消息拒绝
  test_package.py                       打包失败不能沿用旧成功状态
  tb_pll.sv / tb_clock_reset.sv           真实厂商时钟模型与启动/失锁恢复
  tb_hdmi_tx_init.sv                     真实串行配置、ACK/超时与复位
  tb_board_smoke.sv                      板级输出接线/完整光栅集成
  tb_video_rx.sv                         输入几何错误和整帧恢复
  models/                               仿真用 PLL 与 MS7210 串行设备模型
scripts/video/
  common.py                             原生命令/工具/哈希/结果辅助
  doctor.py                             本机工具发现与版本探测
  gen_config.py                         生成 RTL/C 定义
  gen_pll.py                            基于官方 IDF 生成真正 40/10 MHz PLL
  prepare_reference.py                  只提取哈希匹配的参考文件
  run.py                                已实现的回归入口
  build_pds.py                          组件/板级综合、布局布线及位流入口
  scan_board.py                         只读 JTAG 线缆/器件扫描
  package_board.py                      核验哈希后打包板测位流和报告
fpga/pg2l100h/
  project/video_timing.json              显式源文件与测试清单
  constraints/video_timing.fdc           组件 25 ns 时钟约束
  ip/video_reference_manifest.json       HDMI/DDR 来源和选中文件哈希
  ip/video_pll.json                      双输出 PLL 静态分频 recipe
  project/video_board_smoke.json         TX-only 板测目标与正式 filelist
  project/video_rx.json                  接收帧几何监测组件目标
  constraints/video_board_smoke.fdc      官方 HDMI 管脚和内部时钟约束
  constraints/video_rx.fdc               输入监测组件时钟约束，无板级管脚
  rtl/video_clock_reset.sv               PLL 和各时钟域复位/外设启动
  rtl/hdmi_tx_init.sv                    独立发送初始化及 ACK/超时错误
  rtl/video_board_smoke_top.sv           RGB888 彩条板级顶层
docs/interfaces/                        Video 与 DDR 契约状态
docs/verification/video/                 工具、参考差异、验证证据
docs/video/STATUS.md                     任务、依赖和完成状态
build/video/                            被忽略的运行结果、参考副本和 PDS 工程
```

后续 HDMI/DDR/CDC wrapper 放在 `fpga/pg2l100h/rtl/`；跨板可复用像素和 DMA 模块放在 `rtl/video/`。板级约束不与组件约束混用；最终 SoC 顶层由 CPU 牵头集成。已经存在的空目录不表示功能已实现。

## 结果定位

- `build/video/doctor.json`：工具版本发现。
- `build/video/latest_all.json`：最新完整已实现套件的状态及日志目录。
- `build/video/latest_pds.json`：最近一次 PDS 目标的状态、资源与输入哈希。
- `build/video/latest_pds_video_board_smoke.json`、`latest_pds_video_rx.json`：各目标独立结果，避免组件综合覆盖板级下载包依据。
- `build/video/latest_package.json`：通过哈希复核的板级位流包。
- `build/video/latest_jtag_scan.json`：只读扫描结果，不能替代 Program/Verify 或画面证据。
- `build/video/vendor/{hdmi,ddr}/provenance.json`：参考包与成员哈希。
- 回归和 PDS 使用独立时间戳目录；时间戳目录用 UTC，报告日期按北京时间记录。

当前入口可生成彩条板测镜像，扫描脚本仅检查连接。下载按板测说明在 PDS Configuration 执行易失配置和验证；本批无 Flash 固化流程。外部 MS7210 AC 参数和实际画面仍须单独验收。
