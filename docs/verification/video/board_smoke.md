# Windows HDMI 彩条板测工程

目标：PG2L100H-6IFBG676，MES2L676-100HP；HDMI OUT 单路 800×600 RGB888 彩条。该目标用于先验收输出，不使用输入视频和 DDR。

## 构建与验证

```powershell
python scripts/video/prepare_reference.py --reference hdmi
python scripts/video/gen_pll.py
python scripts/video/run.py --suite clocks
python scripts/video/run.py --suite tx_init
python scripts/video/run.py --suite tx_init_full
python scripts/video/run.py --suite board
python scripts/video/build_pds.py --target video_board_smoke --stage bitstream
python scripts/video/package_board.py
python scripts/video/scan_board.py --start-server
```

最后一条只扫描连接，不复位、下载或写 Flash；若它启动了临时 JTAG server，会在扫描后退出自己启动的进程。生成物、原始参考和日志均放在 build/video，源码保留显式目标与 IP recipe。

`latest_package.json` 指向可交付目录，内含 `.sbit` 及 PDS Verify 必需的同名 `.smsk`、输入/资源清单、时序和消息核对报告及板测说明。打包前重新核对位流、校验掩码哈希及构建输入；源码变化后先重新构建，避免混用旧镜像。

## 时钟与复位

- D18 输入 27 MHz；PLL 采用 I=1、M=5、反馈分频=8，VCO=1080 MHz，输出分频 27/108 对应 40/10 MHz。
- 不能只改 IDF 的请求频率。`gen_pll.py` 校验静态分频与生成 wrapper；tb_pll 直接使用厂商 GTP_GPLL/GTP_CLKBUFG 模型测量 25 ns/100 ns 周期和锁定。
- KEY0 C22 低有效；PLL 失锁或按键复位立即置本地复位，分别在像素和配置域同步释放。配置域再等待 10000 周期（1 ms）释放 G25，遵循例程启动延时。
- G25 为共享外设复位，手册中 HDMI 和 Ethernet PHY 都使用此网；本目标使用它初始化 HDMI。

## 发送初始化

复用原始 ms7210_ctl/iic_dri，原字节保持不变。使用独立 TX-only 封装，不等待 RX 完成。配置时钟 10 MHz、I²C 约 400 kHz、7 bit 地址 0x59，保持 49 项参考配置顺序和约 320 ms 的原始等待。

0x0003 的 0x5A 是写入/读回连通性挑战，不能称为芯片固定 ID。封装新增实际串行 ACK 检查及 1 秒超时；错误、完成为锁存状态，在复位时清除。SDA 开漏；SCL 与原例程一致为推挽，当前不支持时钟拉伸。

原例程的适配点及证据：

1. I²C 驱动没有完整复位 busy/trans_en 等内部状态。封装在暴露引脚前完成隔离的内部事务排空及重置，确保中途复位后能重新初始化；隔离期间 SCL=1、SDA 释放。
2. 控制器进入 WAIT 时有多余触发脉冲，会重复第一条后半段配置。封装依据公开 byte_over 和 trigger 仅滤掉该边界脉冲，保留 320 ms 结束时的正常触发。
3. 真实串行模型核对 scratch 读写、全 49 项配置、地址/中间/末项 NACK、坏读回、SDA 卡低、五种时刻复位。常规错误套件只加速 WAIT 计数；另有完整等待测试，实际为 3,251,424 个配置周期（约 325.1424 ms）。

## 管脚与状态

FDC 从哈希固定的 HDMI 参考中提取，全部 24 个 RGB 引脚已与原板卡手册一致核对。sys_clk=D18，KEY0=C22，PCLK=T24，HS=R20，VS=R21，DE=N19，SCL=K22，SDA=K23，RSTN=G25；完整 RGB 与电气设置见板级 FDC。

| 状态 LED | 位置 | 本目标含义 |
|---|---|---|
| LED0 | A20 | 配置时钟心跳，约 0.596 Hz |
| LED1 | C18 | PLL 锁定 |
| LED2 | C19 | TX 初始化错误/超时 |
| LED3 | E18 | TX 初始化完成 |

顶层保留例程端口名以对应原管脚，因此端口 `ddr_init_done` 连接的是 LED1 的 PLL 状态，`init_over_rx` 连接的是 LED2 的 TX 错误；本目标没有 DDR/RX。以后整机顶层采用实际功能名，不从这些独立板测端口推断整机状态。

## 实际上板步骤

1. 核对板卡、底板版本和跳线，断电时把 PDS 下载器的 10 针排线接到 J12（2×5），检查 1 脚对应且没有错位，再供电；下载器 USB 接电脑，HDMI OUT 接显示器。
2. 先运行只读扫描，应识别 PG2L100H，器件 ID 0x00602899。扫描无器件先检查供电、JTAG 数据线和驱动。
3. 在 PDS Configuration 扫描器件，将包内 `.sbit` 指定给识别出的 PG2L100H，执行 Program 和 Verify；这是易失配置，不烧写 Flash。
4. 记录 LED0/1/2/3、显示器检测模式、画面 RGB 顺序、按 KEY0 后恢复；保留实际 bitstream 哈希、照片/录像与错误状态。
5. 首次正常连续显示后再连接输入源，分开验收接收链路及 DDR，避免把彩条成功当作采集或 DDR 已通过。

## 时序与板测边界

板级顶层按例程正沿寄存 RGB/HS/VS/DE 并直接转发像素时钟。PDS 对 40/10 MHz 内部路径完成多角布局布线及 hold 优化。共享管脚提示只在引脚与哈希核验的参考 FDC 完全对应时逐项记录接受；其他错误/critical 提示使构建失败。

随板 MS7210 14 页资料没有采样沿、建立/保持时间表，PCB skew 也未提供。FDC 没有臆造 output delay 或屏蔽这些路径；`internal_timing_met=true` 与 `external_io_timing_verified=false` 分别报告。实际画面可作为板测功能证据，仍不替代外部 AC 参数核实。

2026-10-16 初次扫描线缆列表为空；用户连接并上电后，已枚举 USB Cable II 和 COM12，驱动状态正常。用户确认电源灯亮、10 针排线接在 J12。初期默认、1 MHz、100 kHz 扫描未读到 FPGA ID，报 JtagServer-0306，原始 ID 全为 `0xFFFFFFFF`，当时没有执行下载。该症状只表示当时没有有效 JTAG 回传，不能单凭此判断板卡损坏、具体断点或 RTL 是否正确。

用户随后按断电重插排线两端、重新上电操作，100 kHz 复扫仍报错；随后原始历史只读 Tcl 恢复读到 PG2L100H / 0x00602899，默认扫描脚本也通过。根因尚未确定，不能把恢复单独归因为脚本或频率改变。历史记录本身也出现过扫描失败后恢复成功，当前没有证据表明 CPU 下载损坏了 JTAG。

最终位流包：`build/video/releases/video_board_smoke_925da9613868`。`build/video/board_program/20261016T082259_109276Z` 的 Program/Verify 均成功，位流 SHA256 `925da96138681fdcc2e1f18739d3a8d931a81f65f34d3972ed8c98bad17f9290`，未写 Flash。用户确认最终彩条稳定、短按 KEY0 后恢复。尚未记录显示器 OSD 模式、各 LED、照片/录像和连续时长，不能由“稳定”推定已通过 10/30 分钟整链路验收。首次 Verify 因打包漏带 `.smsk` 失败，已修复打包并新增缺失/损坏掩码回归，不能将该打包缺陷误记为板卡异常。

官方硬件手册 PDF 第 44 页（页码 40，2.1.3.2.6）明确 J12 为 JTAG 连接座，并要求避免通电插拔。第 24 页（页码 20）说明信号通过板对板连接器进入核心板。`DONE` 是配置完成信号；本次没有确认独立 DONE 指示灯的存在或位置。即使未加载位流，也应能够扫描到 FPGA ID。

可用 `--frequency 1MHz` 或 `100KHz` 进行低速扫描；原始结果在 `build/video/latest_jtag_scan.json`，当前小型验证摘要在 [board_smoke.json](evidence/board_smoke.json)。
