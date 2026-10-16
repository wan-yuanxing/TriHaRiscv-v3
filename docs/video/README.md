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
python scripts/video/gen_edid.py --check
python scripts/video/build_pds.py --target video_rx_board --stage bitstream
python scripts/video/package_board.py --target video_rx_board
python scripts/video/program_board.py --target video_rx_board --start-server
python scripts/video/read_board.py --port COM12 --seconds 12
python scripts/video/build_pds.py --target video_ddr_bist --stage bitstream
python scripts/video/package_board.py --target video_ddr_bist
python scripts/video/program_board.py --target video_ddr_bist --start-server
python scripts/video/read_board.py --port COM12 --seconds 12
python scripts/video/build_pds.py --target video_axi_capture --stage bitstream
python scripts/video/package_board.py --target video_axi_capture
python scripts/video/program_board.py --target video_axi_capture --start-server
python scripts/video/read_board.py --port COM12 --seconds 12
python scripts/video/run.py --suite capture_ingress
python scripts/video/run.py --suite capture_engine
python scripts/video/run.py --suite hdmi_capture_board
python scripts/video/build_pds.py --target video_hdmi_capture --stage bitstream
python scripts/video/package_board.py --target video_hdmi_capture
python scripts/video/program_board.py --target video_hdmi_capture --start-server
```

配置更改后先执行 `python scripts/video/gen_config.py`，再执行 `--check`。当前只接受 v0.6 固定模式，修改规格后才扩展模式校验。`--suite all` 运行配置/参考、彩条、实际 PLL/复位、收发串行初始化、输入几何/时序/探针、CDC/UART、RX 板级集成、native BIST，以及 AXI 桥、RGB888 打包、行式 DMA 和完整 800×600 合成帧写后读；三个 DDR 板级测试使用明确标记的数字 IP 替身。物理结果见 STATUS。另用 `--suite tx_init_full` 保留真实约 320 ms 等待验证发送初始化。

彩条目标的管脚、LED、复位、下载与时序边界见 [板测说明](../verification/video/board_smoke.md)。

工具覆盖、版本与运行证据见 [Windows 工具链](../verification/video/toolchain.md)。`prepare_reference` 只提取选中文件；DDR 构建随后用 `gen_ddr.py` 在独立目录生成并复核完整 74 个硬件源文件。生成器的通用 FDC 不用于板卡，正式目标单独加载已审查的 FDC/RCF。

新增两个独立上板目标：`video_rx_board` 保持本地彩条、配置固定 EDID 并报告真实输入；`video_ddr_bist` 暂停 HDMI，执行破坏性 native DDR 自检。目标、下载包、日志和物理验收各自记录，不能把独立 BIST 当作正式 AXI128 wrapper 已实现。

`video_axi_capture` 在已验证 DDR 物理壳中集成生产 AXI128 桥、packer 和 DMA，使用可背压的合成 RGB 源写入预留测试区，再独立逐字节检查 raw 帧及 guard；UART type 4 单独报告结果。它暂停 HDMI 输出，测试结束应恢复 `video_rx_board`。真实 HDMI 像素跨域、preview/input 分支、CAPTURE_DONE 和 CPU fabric 仍待集成，范围见 [本批验证](../verification/video/axi_capture_bringup.md)。

`video_hdmi_capture` 的单帧raw链路从真实HDMI候选像素，经48bit异步FIFO和既有DMA写入DDR，再比较源与DDR读回CRC。保留本地彩条输出，每次KEY0协调复位采一帧；type5资格与合成图样type4分开。2026-10-17实际raw帧CRC及同镜像JTAG重启复测已通过，已恢复RX；物理KEY0和现场画面确认仍待验。组件、联合构建与板测进度见 [HDMI raw记录](../verification/video/hdmi_raw_capture.md) 和STATUS，不能把命令入口存在当作已完成物理验收。

新增文件按职责放置：`config/video_edid.hex` 和生成头保存 EDID；`rtl/video/video_rx_measure.sv`、`video_rx_probe.sv`、`ddr_native_bist.sv` 为便携组件；板级初始化、CDC、UART 和两个 top 在 `fpga/pg2l100h/rtl/`；目标清单与 FDC/RCF 位于各自的 `project/`、`constraints/`；对应 TB、设备/内存数字模型在 `tb/video/`。`gen_edid.py`、`gen_ddr.py`、`program_board.py`、`read_board.py` 扩展原生脚本入口，生成物始终留在 `build/video/`。

## 当前文件树

```text
config/video_cfg.json                    固定模式与图像布局权威配置
config/video_edid.hex                    固定 800×600 EDID
rtl/video/
  include/video_cfg.vh                    生成的 RTL 常量
  include/video_edid.vh                   生成的 EDID 查表
  video_timing.sv                         800×600 扫描计数与同步
  video_test_pattern.sv                   RGB888 八色条
  video_pattern_core.sv                   便携综合边界，外部提供 40 MHz
  video_rx.sv                            候选 RGB888 坐标、完整帧几何和就绪丢失监测
  video_rx_measure.sv / video_rx_probe.sv 精确时序和独立原始边沿探针
  ddr_native_bist.sv                      native256 地址/数据/掩码自检
  axi128_hmic256.sv                      core 域串行桥与 masked readback-before-B
  rgb888_packer.sv                       R/G/B 内存字节序、跨拍 spill 和行尾 keep
  video_write_dma.sv                     单平面步长写入、burst 缓存和响应排空
  video_axi_capture_bist.sv               合成 raw 图样、lane/mask probes 和独立检查
  video_async_fifo.sv                    Gray指针双时钟RAM和受阻输出寄存器
  video_capture_ingress.sv               合法帧首接纳、PIX/EOF、源CRC及overflow
  video_capture_engine.sv                单次raw写DMA、EOF/写结果汇合和读回CRC
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
  tb_hdmi_rx_init.sv / tb_rx_board.sv     RX 串行初始化和板级数字集成
  tb_rx_measure.sv / tb_rx_probe.sv       精确时序和原始探针测试
  tb_rx_telemetry.sv / tb_diag_uart.sv    跨域与逐 bit 串口测试
  tb_ddr_native_bist.sv / tb_ddr_board.sv  native 和板级数字自检
  tb_axi128_hmic256.sv                   AXI/native 地址、掩码、响应和故障保持
  tb_rgb888_packer.sv / tb_write_dma.sv   字节顺序、尾拍、步长、abort 和错误
  tb_axi_capture_bist.sv                 完整帧 byte-memory oracle 与故障注入
  tb_axi_capture_board.sv                新目标 UART、复位和旧 PASS 撤销
  tb_video_async_fifo.sv                 异步速比/相位、满空/回卷与输出稳定
  tb_video_capture_ingress.sv            帧首/EOF、源CRC、故障和协调复位
  tb_video_capture_engine.sv             真正两域入口、byte-memory oracle及CRC故障
  tb_video_hdmi_capture_board.sv         联合目标UART、复位/停钟的数字替身
  models/                               PLL、MS72xx 串行、native 内存和板级 IP 数字模型
scripts/video/
  common.py                             原生命令/工具/哈希/结果辅助
  doctor.py                             本机工具发现与版本探测
  gen_config.py                         生成 RTL/C 定义
  gen_pll.py                            基于官方 IDF 生成真正 40/10 MHz PLL
  gen_edid.py / gen_ddr.py               固定 EDID 和锁定来源的完整 HMIC IP
  prepare_reference.py                  只提取哈希匹配的参考文件
  run.py                                已实现的回归入口
  build_pds.py                          组件/板级综合、布局布线及位流入口
  scan_board.py                         只读 JTAG 线缆/器件扫描
  package_board.py                      核验哈希后打包板测位流和报告
  program_board.py / read_board.py       易失下载/Verify 和接收只读串口诊断
fpga/pg2l100h/
  project/video_timing.json              显式源文件与测试清单
  constraints/video_timing.fdc           组件 25 ns 时钟约束
  ip/video_reference_manifest.json       HDMI/DDR 来源和选中文件哈希
  ip/video_pll.json                      双输出 PLL 静态分频 recipe
  project/video_board_smoke.json         TX-only 板测目标与正式 filelist
  project/video_rx.json                  接收帧几何监测组件目标
  project/video_rx_board.json            本地彩条和物理输入诊断目标
  project/video_ddr_bist.json             独立 native DDR 板测目标
  project/video_axi_capture.json          AXI/DMA 独立目标，共用 DDR FDC/RCF
  project/video_hdmi_capture.json         真实HDMI raw联合目标，显式HDMI和DDR输入
  constraints/video_board_smoke.fdc      官方 HDMI 管脚和内部时钟约束
  constraints/video_rx.fdc               输入监测组件时钟约束，无板级管脚
  constraints/video_rx_board.fdc         RX/TX 管脚、半周期采样与 CDC 约束
  constraints/video_ddr_bist.fdc / .rcf   完整 DDR 管脚/时钟/复位和官方位置约束
  constraints/video_hdmi_capture.fdc     额外HDMI管脚、生成时钟和帧入口CDC
  ip/video_ddr_manifest.json             保护源、wrapper、slice 和工具版本锁定
  rtl/video_clock_reset.sv               PLL 和各时钟域复位/外设启动
  rtl/hdmi_tx_init.sv                    独立发送初始化及 ACK/超时错误
  rtl/video_board_smoke_top.sv           RGB888 彩条板级顶层
  rtl/hdmi_rx_init.sv                    RX 配置、EDID 和状态监测
  rtl/video_rx_telemetry.sv              计频、快照握手和新鲜度
  rtl/video_diag_uart.sv                 整包锁存的诊断 UART
  rtl/video_rx_board_top.sv              下降沿接收采样与本地彩条
  rtl/video_ddr_bist_top.sv              HMIC、独立监测、复位和 BIST
  rtl/video_axi_capture_top.sv           HMIC、合成 raw 写入与 UART type 4
  rtl/video_ddr_snapshot_cdc.sv          三个 DDR 目标共用的冻结快照握手
  rtl/video_hdmi_capture_top.sv          HDMI初始化、彩条输出、帧入口和HMIC
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
- `build/video/latest_pds_video_rx_board.json`、`latest_pds_video_ddr_bist.json`：RX/DDR 板级目标的内部时序、位流和校验掩码哈希。
- `build/video/latest_pds_video_axi_capture.json`：AXI/DMA 目标的独立构建证据；对应 `latest_package_video_axi_capture.json` 保存下载包入口。
- `build/video/latest_pds_video_hdmi_capture.json`、`latest_package_video_hdmi_capture.json`：真实HDMI单帧raw目标的联合构建与包入口。
- `build/video/latest_package.json`：通过哈希复核的板级位流包。
- `build/video/latest_package_video_rx_board.json`、`latest_package_video_ddr_bist.json`：RX/DDR 各自最新发布包。
- `build/video/latest_board_program.json`、`latest_board_serial.json`：实际下载/校验和串口采集；串口收包成功与 RX/native DDR/AXI-DMA 合格分别记录。
- `build/video/latest_jtag_scan.json`：只读扫描结果，不能替代 Program/Verify 或画面证据。
- `build/video/vendor/{hdmi,ddr}/provenance.json`：参考包与成员哈希。
- 回归和 PDS 使用独立时间戳目录；时间戳目录用 UTC，报告日期按北京时间记录。

当前入口可生成彩条、RX 诊断和独立 DDR 自检镜像；扫描脚本仅检查连接。`program_board.py` 在同一会话核对 FPGA ID 后执行易失配置与 Verify；本批无 Flash 固化流程。外部 AC 参数、实际画面、RX 模式和 DDR 校准/自检分别验收，当前状态见 STATUS。
