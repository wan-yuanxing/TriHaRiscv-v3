# HDMI 单帧 raw 采集实施计划

> **For agentic workers:** 使用superpowers:subagent-driven-development逐任务实施，组件先RED/GREEN，再独立规格审查和质量审查；用户已授权继续实施，不在任务间重复询问。沿用现有Video分支/目录，不修改技术报告。

**Goal:** 实际HDMI完整帧经FIFO/DMA写DDR，源端与读回CRC一致，KEY0后可重新采集。

**Architecture:** 像素域在合法帧边界接纳一次帧，将PIX/EOF打包经Gray指针异步FIFO送到core；core复用生产packer/DMA/桥，成功写响应及good EOF齐备后独立读CRC。板级保持本地彩条、固定EDID及独立DDR watchdog。

**Tech Stack:** PowerShell/Python、SystemVerilog/Icarus、PDS PG2L100H、已有HDMI/HMIC IP。

设计依据：`docs/superpowers/specs/2026-10-16-video-hdmi-raw-capture-design.md`。接口以该文完整位定义和RTL端口为准；每个实施者只能编辑获分配的文件，结果附源码哈希和日志。

## Task 1：异步FIFO及帧入口

文件：创建 `rtl/video/video_async_fifo.sv`、`video_capture_ingress.sv` 和 `tb/video/tb_video_async_fifo.sv`、`tb_video_capture_ingress.sv`。

- [x] 先写独立队列oracle TB：两个自由运行、互不整倍频时钟，随机write/read、回卷、满/空、输出stall稳定、协调reset，未实现时命令返回非零。
- [x] 实现注册Gray指针、两级同步和同步读RAM，输出寄存器预取；记录真实RAM/输出容量及full/highwater。
- [x] 先写入口TB，arm在中途、下一合法frame_start接纳首像素，PIX/EOF逐字核对、源CRC独立oracle，overflow/错坐标/ready丢失/cancel只失败不伪造good EOF。
- [x] 按设计固定48bit封包、arm/cancel握手和source fault保持；小几何及异步相位扫描通过。
- [x] 执行命令并保存RED/GREEN：`iverilog -g2012 -Wall -s tb_video_async_fifo -o build/video/hdmi_ingress/fifo.vvp rtl/video/video_async_fifo.sv tb/video/tb_video_async_fifo.sv`；对应ingress加入两个RTL及TB。`vvp`必须出现独立PASS标记且exit0。
- [x] 独立规格审查通过，再质量审查；本任务只产生数字证据。

## Task 2：生产DMA集成与读回CRC

文件：创建 `rtl/video/video_capture_engine.sv`、`tb/video/tb_video_capture_engine.sv`；复用已冻结packer/DMA/桥，优先不修改原组件。

- [x] RED TB以两个时钟经真实ingress驱动逐帧像素及事件，独立native byte memory验证R/G/B、padding/红区；CRC oracle不调用生产函数。
- [x] descriptor握手后arm；源EOF和DMA结果分别保持，两者齐备后读回；每周期一字节CRC，按行/16拍/4KiB读。
- [x] 同时验证13×3、16×3、1367×3和完整800×600，成功计数与ISO-HDLC CRC标准值；覆写非零高lane字节必须产生CRC错误。
- [x] 覆盖坏EOF/行末、overflow/source fault、AR/R协议错误、init丢失、源停钟和任务超时；fault不撤回AR/AW/W，错误后排空现有事务。
- [x] 按设计模块接口实现 `video_capture_engine` 并记录RED/GREEN、输入哈希和所有case数。
- [x] 独立规格审查通过，再质量审查；完整几何是独立byte oracle通过，物理结果另记。

## Task 3：HDMI＋DDR板级目标、脚本和数字集成

文件：创建 `fpga/pg2l100h/rtl/video_hdmi_capture_top.sv`、`project/video_hdmi_capture.json`、`constraints/video_hdmi_capture.fdc`、`tb/video/tb_video_hdmi_capture_board.sv`；修改 `scripts/video/{run,build_pds,package_board,program_board,read_board}.py`、`tb/video/test_board_packets.py`。

- [ ] 合并现有两个物理壳，保留DDR PHY/PLL/复位结构和必要层次，帧入口复位不能随RX enable/PLL临时丢失单独清FIFO。
- [ ] 组合显式HDMI/vendor与DDR IDF输入；build脚本同时生成两种IP、分别哈希核验，沿用严格消息审查和所有原约束margin。
- [ ] 新FDC只添加HDMI官方引脚和新CDC：wGray/rGray source-period max-delay＋skew、单bit第一同步级例外、EOF metadata通过FIFO，源总线无未定义跨域。
- [ ] 先补type5独立host包测试，缺字段/错误CRC/overflow/旧heartbeat均不得合格，再实现解码和qualification。
- [ ] 板级数字替身检查实际UART、冷启动、无源/无core、KEY0、PLL/init loss和stalePASS；不把数字IP当物理校准证据。
- [ ] `run.py` 接入 `capture_ingress/capture_engine/hdmi_capture_board` 和all；最终冻结输入后跑 `python scripts/video/run.py --suite all`。
- [ ] 规格及质量审查，核对原RX/native/AXI目标仍可构建/仿真。

## Task 4：PDS、物理验收和交付

- [ ] `python scripts/video/build_pds.py --target video_hdmi_capture --stage bitstream`：新目录，当前哈希，全部内部约束满足；失败产物不下载。
- [ ] 重新构建/打包恢复用RX镜像；新目标按 `.sbit/.smsk` 哈希打包。
- [ ] Program/Verify后串口 `physical_hdmi_raw_capture_verified` 为真，480000像素/1440000字节/CRC相等/无overflow；记录CRC碰撞和有限FIFO边界。
- [ ] KEY0后heartbeat复位、新帧计数/CRC再次完成；恢复RX、串口模式及用户彩条观察。
- [ ] 更新接口、README文件树、STATUS、单独小型证据；旧阶段JSON保持历史。只做Video本地提交，不push。
