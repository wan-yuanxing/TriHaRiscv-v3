# 连续 RAW 板级交付记录

2026-10-23，基于 `2fc380a`。目标 `video_live_board`；连续 RAW 实体上板验收通过；连续 BOX/AVATAR 和真实 NPU 集成是后续任务。

## 行为与边界

800×600、40 MHz（约 60.32 Hz）输入和输出，125 MHz 核心。A/B 两槽交替采集，保留 raw、preview、320×320 UINT8 BGR NCHW 三分支；采集好 EOF、所有写响应退休后发布 RAW。新图在输出帧边界提交，收到旧图 release 后才允许覆盖旧槽。输入帧可跳过，新图更新率待实体实测。该演示独占 Video 本地 DDR 端口，不代替最终 CPU 帧池、NPU 消费和系统可见性栅栏。

`KEY0` 协调复位后重新开始连续运行。HDMI 初始化保持既有策略及 128 帧启动保护。每帧不再全量回读三个缓冲区；兼容端口的 DDR CRC 值为零，不作为读回成功。UART11 表示生命周期、UART9 表示扫描、UART12 是进行中的捕获观察，后者的像素/字节计数和 CRC 可因新任务开始而归零。只有生命周期持续前进且无欠载/错误才判定自动运行正常。

## 验证入口

```powershell
python scripts/video/run.py --suite live_board
python scripts/video/test_live_video.py --full
python scripts/video/build_pds.py --target video_live_board --stage bitstream --seed-start 5 --seed-count 1 --pnr-mode performance
python scripts/video/package_board.py --target video_live_board
python scripts/video/program_board.py --target video_live_board --start-server
python scripts/video/read_board.py --port COM12 --seconds 60
```

- RED：旧 `video_raw_engine` 在变化源测试中仅提交第 1 帧；`build/video/live_video/20261023T023336_420164Z/baseline_simulation.log`。
- GREEN：常规入口 `build/video/regression/20261023T024758_672232Z/result.json`。小图变化源、随机 DDR 等待、快速 DDR、源端故障、读停顿恢复与排空、800 像素行宽、完整板壳及两次协调复位均通过。保护槽直到真实 release，逐像素 oracle 基于独立源函数和实际写入的 DDR 字节。
- 完整 800×600：`build/video/live_video/20261023T024046_881218Z/full_simulation.log`，3 次自动提交、2 幅完整输出、960000 像素。该轮测试脚本在运行时增加了后续元数据检查，因此脚本本身哈希与当前不同；编译的 RTL、模型和 TB 输入哈希另行核对，不能宣称该轮运行了后来新增的检查。
- 首轮审查修正了两项故障注入测试：源故障必须在 CAPTURE 内注入并要求首错 `03`；DDR 读停顿首先触发显示欠载 `66`，恢复响应后检查排空，不再误称其测试了桥原生超时。桥超时仍归既有桥测试负责。复审未发现新的 RTL 阻塞。
- 串口协议 39 项回归通过，包含新增的持续进度、静止计数拒绝和复位/故障后历史失效检查。

## 物理实现

- 综合：16121 LUT / 16481 FF / 9.5 DRM。139 个板级管脚，保留官方 DDR IP 及管脚层级，新增旧帧 release 元数据的 6 ns CDC 约束。
- 首轮 seed4/performance：`build/video/pds/20261023T024146_139994Z`。布线完成，但 slow core setup −0.217 ns、11 个端点不通过；slow/fast core hold +0.033/+0.026 ns，fast core setup +2.811 ns。最差为捕获 error → preview 写 DMA 的 row_index CE，5 级逻辑、6.635 ns 布线。不打包、不下载该失败轮位流。
- 第二轮 seed5/performance `build/video/pds/20261023T025057_182121Z` 使用相同 RTL 和时钟，最终 All Constraints Met。slow setup/hold +0.049/+0.137 ns，fast +2.926/+0.099 ns；两角 recovery/removal 均通过。位流 `644852dd6321` 及匹配 Verify 掩码已打包。新增 release 束 34 个端点两角均覆盖，6 ns 约束最小余量 slow +4.504 ns / fast +5.159 ns；专项报告没有修改原始数据库、网表、项目或报告。外部 HDMI AC 未签核。
- 初次 JTAG 只读扫描线缆列表为空，COM12 正常可见。用户重新连接并上电后，USB Cable II、PG2L100H/00602899 已识别，易失 Program/Verify 通过；`build/video/board_program/20261023T030012_747600Z`。首段60秒串口通过，自动提交1550→3269，约30.16幅新帧/秒，欠载/溢出/错误均为0；未写 Flash。

39 项包检查日志为 `build/video/live_delivery/packet_tests.log`；capture_rearm 的 20 份仿真和 shared_video 的 24 份仿真回归均通过。

动态验证图位于 `tb/video/assets/live_source.html`。本轮启动 HTTP 服务被自动审批策略拒绝，未改用其他方式绕过；可直接移动源电脑窗口验证动态更新。源电脑全屏打开后，应在输出看到完整四角、持续变化的计时器和移动白条。用户已现场确认完整全屏画面随源电脑内容自动更新，并确认只短按一次 KEY0 后完整画面恢复、继续自动更新。持久串口记录 `build/video/live_board_trace/20261023T030420_685519Z` 共155包，明确记录1次复位；复位后连续健康114.000秒，提交25→3463、释放24→3462，欠载/溢出/错误均为0，新帧率30.1579fps。输出扫描为约60.32Hz，允许每幅新图重复扫描。串口已正常关闭，开发板保留运行镜像。

机器证据：[live_raw.json](evidence/live_raw.json)。本阶段连续 RAW 实体交付关闭；后续连续 BOX/AVATAR、CPU 帧池接管和真实 NPU 结果另行验收。
