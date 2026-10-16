# Video AXI128 DDR 与单平面采集 DMA 实施计划

> **For agentic workers:** Use superpowers:subagent-driven-development；先测试后实现，每个组件依次进行规格和质量审查。用户已批准 Video 路线并要求继续，沿用 `video/windows-bringup` 原工作目录，技术报告变更不纳入本批。

**Goal:** 建立可测的 AXI128→HMIC256 边界和 RGB888 行式写 DMA，并以独立板测证明同一路径的写后读；不发布尚未实现的三分支 CAPTURE_DONE。

**Architecture:** 一个串行桥独占 native 端口，完整缓存最多 16 个 AXI 拍，处理 16 B 对齐的上下半 lane；成功写响应前 masked readback 验证。DMA 先缓存一整个 burst，再发 AW/W/B，按行和 4 KiB 拆分。板测先用已知 RGB 图样驱动相同 DMA 和桥，回读验证，正式 HDMI 像素 CDC、预览/网络分支及共享 fabric 在后续集成。

**Tech Stack:** Windows PowerShell/Python、SystemVerilog、Icarus、PDS、已通过板测的 HMIC_S1.10 与 UART。

## 固定接口与故障边界

- AXI：32 bit 逻辑字节地址 `0x80000000..0x87ffffff`；128 bit、SIZE=4、INCR、1..16 拍，16 B 对齐、不跨 4 KiB，4 bit ID。桥一次只拥有一个读或写事务；W 可早于 AW 提出，收到 AW 后才接纳 W。
- native：28 bit 32-bit-word 地址，32 B 一拍、地址 +8；1..9 拍足以容纳一个上半 lane 起始的最大 AXI burst；没有 WVALID/RREADY/B。完整缓存接纳无背压返回，支持 AW+W、AR+R 最早同拍。
- B OKAY 表示本次全部有效写字节已通过同一 native 端口读回核对。该桥必须独占 native，所有后续逻辑主端由 CPU fabric 进入此桥；不允许验证期间另一路 native 写覆盖。此处不宣称物理 DRAM 持久化。
- 非法地址/参数读按 ARLEN 返回零和 DECERR；非法写排空 advertised W 数后 DECERR，不写缓存/DDR。WLAST 错误排空后 SLVERR 并保持故障。初始化曾成功后任何丢失均故障保持。
- 已接纳但未收齐 W 的故障写仍允许排空 W，之后 SLVERR；master 不再送数据时须协调复位。已提出的受阻 VALID/载荷不能因 abort/timeout 撤回；native 故障进入隔离，禁止新 AXI 请求，允许既有稳定响应排空。native 看门狗不把上游 W/B/R 背压当作设备超时。
- 故障完成有明确条件：已公开的 native 命令保持到接纳并排空其 advertised 长度，之后才完成相应 AXI 错误响应；native 永不接纳/返回时由系统协调复位恢复，不承诺虚假的有界错误响应。隔离期间缓存和命令所有权不复用。
- DMA descriptor：base/row_bytes/row_stride/rows/tag；base/stride 16 B 对齐，stride≥row_bytes>0，整体地址计算不能溢出/越界。stream 128 bit、keep16、row_last，有背压；低 byte lane 对应低地址，每行最后 keep 为连续低位 1。
- 像素打包：输入 `rgb[23:0]={R,G,B}`，内存 `base+y*stride+3*x+0/1/2=R/G/B`；不扩成32bit，不在16 B边界丢弃跨拍像素。raw=2400 B/行，preview=1200 B/行；组件小几何测试允许非整拍尾。
- DMA 单平面成功需全部 stream 字节和正确行边界、所有成功 B、无 abort/error。正式整帧几何及三分支汇合由上层负责；未做 pixel FIFO/CDC 时不接不可背压的物理 HDMI。
- DMA 完成记录保持 `result_valid/result_ready/tag/success/error_code/written_bytes`；written_bytes 只计成功 B 认领的有效字节。错误 burst 可部分改写内存，失败不表示回滚。wrong BID/无主 B 触发端口协议故障保持，协调复位前禁止新 descriptor。
- DMA abort 当拍禁止新 descriptor/stream/新 AW；已注册并公开的 AWVALID 即使尚未握手也保持并完成整 burst。未公开 buffer 可直接丢弃；result 消费后一拍才开放新请求。上游在 abort/失败后须清理旧流；packer 的同步 `flush` 是有意取消旧 stream 的控制例外，只在 DMA 已停止接收后使用。
- packer 使用至少18字节 reservoir 或等价 spill，输出末行 keep 为连续低位 1，收 pixel_last 后等待末拍被消费再接下一行；正常 stall 时数据/keep/last 保持。

## Task 1：桥接组件

文件：`rtl/video/axi128_hmic256.sv`、`tb/video/tb_axi128_hmic256.sv`，独立 native byte-memory 模型或现有模型的测试适配。旧来源 `D:/FPGA/TriHaRiscv-v3/targets/pango676/ddr/axi128_hmic256.sv` 仅借鉴，不改原件。

- [x] 审计旧桥、CDC 和 arbiter；拒绝迁入旧地址/256 拍上限/未验证完成语义。
- [x] 先建立失败测试：两种起始 lane、1..16 拍、所有 strobe、上下窗口/溢出/4KiB/17与256拍拒绝、W在AW前、同时AW/AR、B/R背压。
- [x] 实现完整缓存、地址转换、masked readback-before-B，原生错误/超时/初始化丢失、写故障排空、错误读的完整长度。
- [x] 测验证读回错误、晚到返回、VALID稳定、复位和未初始化禁止访问；记录 RED/GREEN 和输入哈希。
- [x] 独立规格审查通过后做代码质量审查，必要时修复并复核。

## Task 2：行式 DMA 与 RGB888 打包

文件：`rtl/video/video_write_dma.sv`、`rtl/video/rgb888_packer.sv`、`tb/video/tb_write_dma.sv`、`tb/video/tb_rgb888_packer.sv`。

- [x] 先建立独立字节 oracle：13像素/39B、stride48，检查尾 keep=0x007f、padding和红区；覆盖跨拍 RGB、1/15/16/17拍、0xff0附近地址和4KiB拆分。
- [x] DMA 在 AW 前缓存整 burst，WSTRB 保留尾部，保持 VALID 载荷，等待 B 后推进，完成记录保持至 result_ready。
- [x] descriptor 全域地址/步长检查；abort 只丢未公开数据，已经提出 AW/W 完整排空；BID/BRESP错误保持，不伪造成功。
- [x] 数字集成测试完整800×600 raw和400×300 preview，用坐标图样逐字节验证并注入延迟/错误。
- [x] 独立规格审查和质量审查；明确该组件不自行证明 HDMI 帧几何或三分支完成。

## Task 3：独立 DDR 端到端板测

文件：`rtl/video/video_axi_capture_bist.sv`、`fpga/pg2l100h/rtl/video_axi_capture_top.sv`、`fpga/pg2l100h/project/video_axi_capture.json`、对应 FDC/RCF 与数字 TB。脚本扩展原有显式目标/套件及诊断包类型；原 RX/native BIST 目标仍可恢复。

- [x] 数字测试先验证已知 RGB→packer→DMA→bridge→native memory→AXI readback，错误、复位和 UART 不得输出旧 PASS。
- [x] 独立顶层仅使用规格预留测试区，如 `0x87300000` 起2MiB；测试前后端点/红区检查；该区不是此前低/高1MiB BIST窗口。
- [x] PDS 新目录构建、严格 C/E 消息审查、内部多角时序和当前源哈希复核；保留完整官方 PHY/PLL/复位约束及实例层次。
- [ ] Program/Verify 后串口验证实际 AXI/DMA 字节数、读回匹配和故障状态，KEY0 重测；完成后恢复 RX 彩条诊断。

## Task 4：交付

- [x] 接入 `scripts/video/run.py`，跑当前完整回归，失败不得沿用旧 PASS。
- [x] 更新接口、来源、STATUS 和小型证据，分别报告仿真/内部时序/板测与仍未实现的 HDMI capture/三分支/AXI fabric/外部 AC。
- [x] 只提交本批 Video 文件，不提交技术报告，不 push。

当前检查点：软件实现、独立审查、完整回归、最终PDS和可下载包完成。实际Program/Verify因JTAG未识别而未执行成功，等待用户重插J12；物理自检/KEY0/恢复RX板测保持未勾选。
