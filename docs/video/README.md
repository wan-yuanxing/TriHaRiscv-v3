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
python scripts/video/run.py --suite preview_display
python scripts/video/build_pds.py --target video_preview_board --stage bitstream
python scripts/video/package_board.py --target video_preview_board
python scripts/video/program_board.py --target video_preview_board --start-server
```

配置更改后先执行 `python scripts/video/gen_config.py`，再执行 `--check`。当前只接受 v0.6 固定模式，修改规格后才扩展模式校验。`--suite all` 运行配置/参考、彩条、实际 PLL/复位、收发串行初始化、输入几何/时序/探针、CDC/UART、RX 板级集成、native BIST，以及 AXI 桥、RGB888 打包、行式 DMA 和完整 800×600 合成帧写后读；DDR 板级集成测试使用明确标记的数字 IP 替身。物理结果见 STATUS。另用 `--suite tx_init_full` 保留真实约 320 ms 等待验证发送初始化。

彩条目标的管脚、LED、复位、下载与时序边界见 [板测说明](../verification/video/board_smoke.md)。

工具覆盖、版本与运行证据见 [Windows 工具链](../verification/video/toolchain.md)。`prepare_reference` 只提取选中文件；DDR 构建随后用 `gen_ddr.py` 在独立目录生成并复核完整 74 个硬件源文件。生成器的通用 FDC 不用于板卡，正式目标单独加载已审查的 FDC/RCF。

新增两个独立上板目标：`video_rx_board` 保持本地彩条、配置固定 EDID 并报告真实输入；`video_ddr_bist` 暂停 HDMI，执行破坏性 native DDR 自检。目标、下载包、日志和物理验收各自记录，不能把独立 BIST 当作正式 AXI128 wrapper 已实现。

`video_axi_capture` 在已验证 DDR 物理壳中集成生产 AXI128 桥、packer 和 DMA，使用可背压的合成 RGB 源写入预留测试区，再独立逐字节检查 raw 帧及 guard；UART type 4 单独报告结果。它暂停 HDMI 输出，测试结束应恢复 `video_rx_board`。该目标的合成自检范围见 [AXI/DMA验证](../verification/video/axi_capture_bringup.md)，真实HDMI单帧采集由下述联合目标验证。

`video_hdmi_capture` 的单帧raw链路从真实HDMI候选像素，经48bit异步FIFO和既有DMA写入DDR，再比较源与DDR读回CRC。保留本地彩条输出，每次KEY0协调复位采一帧；type5资格与合成图样type4分开。2026-10-17实际raw帧CRC、同镜像JTAG重启及实体KEY0重采均通过；KEY0后计数清零，新帧480000像素/1440000字节、源/DDR CRC均ebf5a8c4，无错误/overflow。已恢复RX并Verify、串口模式复查通过，用户确认稳定彩条，本阶段验收完成。采集内容显示、preview/input和三分支完成事件仍属后续工作，详情见 [HDMI raw记录](../verification/video/hdmi_raw_capture.md) 和STATUS。

新增文件按职责放置：`config/video_edid.hex` 和生成头保存 EDID；`rtl/video/video_rx_measure.sv`、`video_rx_probe.sv`、`ddr_native_bist.sv` 为便携组件；板级初始化、CDC、UART 和两个 top 在 `fpga/pg2l100h/rtl/`；目标清单与 FDC/RCF 位于各自的 `project/`、`constraints/`；对应 TB、设备/内存数字模型在 `tb/video/`。`gen_edid.py`、`gen_ddr.py`、`program_board.py`、`read_board.py` 扩展原生脚本入口，生成物始终留在 `build/video/`。

`video_preview_board` 在同一入口帧原子生成raw和400×300 preview，写退休后分别读取DDR核验CRC，再显示左右两个同帧窗口。它按需采一帧，KEY0协调复位后重采；上下背景为深色。当前物理验收进度见 [共享预览记录](../verification/video/shared_preview.md)，不能以数字仿真替代实际画面确认。type6报告两路像素数及四个CRC，type7报告帧号、提交、扫描、欠载、行读和FIFO水位；两个包来自同一448bit原子快照，资格检查会丢弃重启/故障前的旧PASS。

2026-10-18版本将KEY0采集/显示/DDR复位与HDMI初始化分离：按键重采保持已初始化的HDMI链路。当前位流33e1b8242053已通过四角测试图及普通桌面的两次实体KEY0完整画面验收，源/DDR CRC一致、无溢出/欠载；旧版黑帧与裁切失败保留历史。仍为静态单帧预览，连续采集、检测input及正式三槽/CPU fabric是后续任务。KEY0保留HDMI初始化sticky错误，重新初始化需重配/上电或实际PLL失锁；外部AC、新reset/SRL内部时序和模拟余量未签核。

新增独立套件为 `preview_scale`、`preview_capture`、`preview_display`、`preview_crc`、`preview_board`、`preview_clocks`，均纳入 `--suite all`。显示套件另有独立入口 `python tb/video/run_preview_display_test.py`，为每次运行保留输入副本、哈希与逐像素结果。测试区地址和组件接口见 [Video接口](../interfaces/video.md)。

检测分支先落地独立`detect_downscale`：800×600 RGB888按5×5完整块平均成为160×120 RGB888，含全范围舍入、背压/复位及完整几何验证。`python scripts/video/run.py --suite detect_scale`运行组件测试和Python整数参考，`python scripts/video/build_pds.py --target video_detect_scale --stage synth`只作组件综合；不生成板测位流。后续格式组件见下文，模型量化与正式三分支继续按依赖推进，详见[检测缩小记录](../verification/video/detect_scale.md)。

格式阶段新增量化前`detect_input_pad`和量化后`detect_c8_pack`：前者转换BGR并补足128行，后者接收外部量化BGR及显式零编码，产生C8/128bit流。`python scripts/video/run.py --suite input_format`运行两个组件、整数参考及现有DMA字节内存联测；测试量化映射不作为模型参数。`video_input_pad`、`video_c8_pack`仅支持组件synth。真实量化、正式三分支完成和板测仍单列，见[格式验证](../verification/video/input_format.md)。

用户随后选择优先迎合已校准的NPU 320×320方案：后续采用800×600→320×240双线性、上下40行黑边、UINT8 BGR NCHW，保留0..255且不再额外有损量化。当前已实现无OpenCV运行依赖的整数参考，`python tb/video/test_yunet_input_reference.py`可验证；固定比例RTL、NCHW/DMA和公共配置/输入槽迁移另行验收，既有160/C8记录保留为原组件范围。见[320参考验证](../verification/video/yunet320_reference.md)。

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
                                        默认同拍传输，preview目标选择输入/输出分拍
  video_write_dma.sv                     单平面步长写入、burst 缓存和响应排空
  video_axi_capture_bist.sv               合成 raw 图样、lane/mask probes 和独立检查
  video_async_fifo.sv                    Gray指针双时钟RAM和受阻输出寄存器
  video_capture_ingress.sv               合法帧首接纳、PIX/EOF、源CRC及overflow
  video_capture_startup_guard.sv         连续完整好帧门控，RGB/CRC不参与准入
  video_stream_register.sv               core域FIFO读口与引擎间的单词流寄存器
  video_capture_engine.sv                单次raw写DMA、EOF/写结果汇合和读回CRC
  preview_downscale.sv                   RGB888四像素平均及同步行RAM
  detect_downscale.sv                    RGB888完整5×5块平均及累计RAM/算术流水
  detect_input_pad.sv                    量化前RGB→BGR、底部raw零及元数据
  detect_c8_pack.sv                      外部量化BGR和显式零值→C8/128bit
  video_preview_capture.sv               同帧raw/preview原子分送和双DMA仲裁
  video_frame_crc_reader.sv              行式有效字节CRC及读事务排空
  preview_display.sv                     双时钟双bank行RAM、共享读取及提交/释放
  video_preview_engine.sv                双平面CRC检查到显示读口的阶段所有权
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
  tb_rgb888_packer_serial.sv             两模式oracle、尾拍/受阻、默认波形及吞吐
  tb_axi_capture_bist.sv                 完整帧 byte-memory oracle 与故障注入
  tb_axi_capture_board.sv                新目标 UART、复位和旧 PASS 撤销
  tb_video_async_fifo.sv                 异步速比/相位、满空/回卷与输出稳定
  tb_video_capture_ingress.sv            帧首/EOF、源CRC、故障和协调复位
  tb_video_capture_engine.sv             真正两域入口、byte-memory oracle及CRC故障
  tb_video_hdmi_capture_board.sv         联合目标UART、复位/停钟的数字替身
  tb_preview_downscale.sv                独立四像素数值oracle、受阻与X/Z拒绝
  tb_detect_downscale.sv                 25坐标oracle、6376总和、全尺寸和异常/复位
  test_detect_reference.py               独立Python整数参考和坐标/舍入检查
  tb_detect_input_pad.sv / tb_detect_c8_pack.sv 通道/补行/元数据/打包及取消测试
  tb_detect_input_dma.sv                 scaler到C8/DMA字节内存联测，测试量化独立标记
  test_input_format_reference.py         BGR/raw补行和外部量化C8布局参考测试
  test_yunet_input_reference.py          精确OpenCV4.11固定比例/NCHW哈希与边界
  tb_video_preview_capture.sv            双平面byte-memory oracle及异常排空
  tb_preview_display.sv                  异步时钟、逐像素/行读/所有权与事件受阻
  run_preview_display_test.py            独立显示仿真和不可变输入证据
  tb_video_frame_crc_reader.sv           CRC、行尾/4KiB、错误与背压结果稳定
  tb_video_preview_board.sv              联合type6/7和复位/健康撤销数字替身
  tb_video_preview_clock_reset.sv        预览KEY0链路保持、独立域释放及PLL失锁
  test_preview_packets.py                两路CRC/显示资格和旧PASS失效
  models/                               PLL、MS72xx 串行、native 内存和板级 IP 数字模型
    rgb888_packer_legacy_model.sv        冻结默认算法，仅作兼容性仿真参考
scripts/video/
  common.py                             原生命令/工具/哈希/结果辅助
  doctor.py                             本机工具发现与版本探测
  gen_config.py                         生成 RTL/C 定义
  gen_pll.py                            基于官方 IDF 生成真正 40/10 MHz PLL
  gen_edid.py / gen_ddr.py               固定 EDID 和锁定来源的完整 HMIC IP
  prepare_reference.py                  只提取哈希匹配的参考文件
  run.py                                已实现的回归入口
  detect_reference.py                   规格定义的几何整数参考，不含模型量化
  input_format_reference.py             独立通道/补行/C8布局参考，不执行量化
  yunet_input_reference.py              800×600 RGB→320×320 UINT8 BGR NCHW整数参考
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
  project/video_preview_board.json        同帧raw/preview、共享双窗口联合目标
  project/video_detect_scale.json         独立5×5缩小组件显式源及测试
  project/video_input_pad.json / video_c8_pack.json 独立格式组件显式清单
  constraints/video_board_smoke.fdc      官方 HDMI 管脚和内部时钟约束
  constraints/video_rx.fdc               输入监测组件时钟约束，无板级管脚
  constraints/video_rx_board.fdc         RX/TX 管脚、半周期采样与 CDC 约束
  constraints/video_ddr_bist.fdc / .rcf   完整 DDR 管脚/时钟/复位和官方位置约束
  constraints/video_hdmi_capture.fdc     额外HDMI管脚、生成时钟和帧入口CDC
  constraints/video_preview_board.fdc    显示标量CDC首级、6ns稳定bundle及reset
  constraints/video_detect_scale.fdc     组件8ns core时钟，无管脚/布线验收
  constraints/video_input_format.fdc     BGR/补行及C8组件8ns时钟
  ip/video_ddr_manifest.json             保护源、wrapper、slice 和工具版本锁定
  rtl/video_clock_reset.sv               原有目标的PLL/各域复位/外设启动
  rtl/video_preview_clock_reset.sv       预览专用KEY0重采与HDMI链路启动分离
  rtl/hdmi_tx_init.sv                    独立发送初始化及 ACK/超时错误
  rtl/video_board_smoke_top.sv           RGB888 彩条板级顶层
  rtl/hdmi_rx_init.sv                    RX 配置、EDID 和状态监测
  rtl/video_rx_telemetry.sv              计频、快照握手和新鲜度
  rtl/video_diag_uart.sv                 整包锁存的诊断 UART
  rtl/video_rx_board_top.sv              下降沿接收采样与本地彩条
  rtl/video_ddr_bist_top.sv              HMIC、独立监测、复位和 BIST
  rtl/video_axi_capture_top.sv           HMIC、合成 raw 写入与 UART type 4
  rtl/video_ddr_snapshot_cdc.sv          DDR 目标共用的冻结快照握手
  rtl/video_hdmi_capture_top.sv          HDMI初始化、彩条输出、帧入口和HMIC
  rtl/video_preview_board_top.sv         真实源双平面、双窗口和448bit诊断快照
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
- `build/video/latest_pds_video_preview_board.json`、`latest_package_video_preview_board.json`：同帧共享预览目标的构建与包入口；验收必须另查Program/Verify、type6/7和现场记录。
- `build/video/latest_package.json`：通过哈希复核的板级位流包。
- `build/video/latest_package_video_rx_board.json`、`latest_package_video_ddr_bist.json`：RX/DDR 各自最新发布包。
- `build/video/latest_board_program.json`、`latest_board_serial.json`：实际下载/校验和串口采集；串口收包成功与 RX/native DDR/AXI-DMA 合格分别记录。
- `build/video/latest_jtag_scan.json`：只读扫描结果，不能替代 Program/Verify 或画面证据。
- `build/video/vendor/{hdmi,ddr}/provenance.json`：参考包与成员哈希。
- 回归和 PDS 使用独立时间戳目录；时间戳目录用 UTC，报告日期按北京时间记录。

当前入口可生成彩条、RX 诊断和独立 DDR 自检镜像；扫描脚本仅检查连接。`program_board.py` 在同一会话核对 FPGA ID 后执行易失配置与 Verify；本批无 Flash 固化流程。外部 AC 参数、实际画面、RX 模式和 DDR 校准/自检分别验收，当前状态见 STATUS。
