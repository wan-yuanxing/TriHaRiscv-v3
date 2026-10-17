# HDMI共享预览与同帧双窗口实施计划

> **For agentic workers:** 使用superpowers:subagent-driven-development逐任务实施及规格/质量审查；独立文件域可按dispatching-parallel-agents分工，禁止同时修改共享脚本或文件。用户已授权继续，沿用当前Video分支，不触碰技术报告、不push。

**Goal:** 真实HDMI单帧同时写raw/preview，经DDR读回核验后显示同帧双窗口。

**Architecture:** 既有入口FIFO→原子分流→raw DMA及2×2缩放/preview DMA→生产桥；写退休后独立CRC；再用独立pixel域双bank行缓存左右复用，安全提交及引用释放。

**Tech Stack:** Windows PowerShell/Python、SystemVerilog/Icarus、PDS PG2L100H、已有HDMI/HMIC IP。

设计：`docs/superpowers/specs/2026-10-17-video-shared-preview-design.md`。所有仿真/临时工具/PDS产物放 `build/video/`；实现与证据按小批提交。

## Task 1：2×2缩放

文件：`rtl/video/preview_downscale.sv`、`tb/video/tb_preview_downscale.sv`。

- [ ] 先写四像素独立oracle TB，记录模块未实现时RED（编译或自检非零）。
- [ ] 实现设计给定ready/valid接口、每通道10bit加法和+2取整、同步行RAM；不整体reset RAM。
- [ ] 独立核对sum0..1020、通道独立、每种stall相位、行末、clear、错误保持及完整800×600的120000输出。
- [ ] PowerShell运行：`iverilog -g2012 -Wall -s tb_preview_downscale -o build/video/preview_scaler/scaler.vvp rtl/video/preview_downscale.sv tb/video/tb_preview_downscale.sv`，`vvp build/video/preview_scaler/scaler.vvp`，需 `PREVIEW_DOWNSCALE_PASS` 与exit0。
- [ ] 独立规格审查，再质量审查，绑定当前文件哈希，单独提交。

## Task 2：同帧raw/preview写入

文件：`rtl/video/video_preview_capture.sv`、`tb/video/tb_video_preview_capture.sv`。

- [ ] 先建立AXI BFM及独立byte-memory oracle；缺实现时命令非零。
- [ ] 实现FIFO合法PIX/EOF、双packer/DMA和burst归属，写口标准AXI128（AW/W/B全部字段沿用video_write_dma），arm/cancel及诊断端口按设计。
- [ ] 验证2×2、26×6、32×6及800×600；raw/preview全部有效字节与padding/guard一致；随机AW/W/B受阻、最后B延迟、坏BID/RESP、overflow、坏EOF、源停钟/timeout及协调reset。
- [ ] done晚于good EOF、两路成功写结果及计数/tag核对；fault后事务排空且结果不复用。
- [ ] `iverilog -g2012 -Wall -s tb_video_preview_capture -o build/video/preview_capture/capture.vvp rtl/video/preview_downscale.sv rtl/video/rgb888_packer.sv rtl/video/video_write_dma.sv rtl/video/video_preview_capture.sv tb/video/tb_video_preview_capture.sv`，执行vvp需 `VIDEO_PREVIEW_CAPTURE_PASS`。
- [ ] 独立规格审查、质量审查和单独提交。

## Task 3：共享预览读取及显示记录

文件：`rtl/video/preview_display.sv`、`tb/video/tb_preview_display.sv`，必要的本任务子模块亦限 `preview_*.sv` 并明确列举。

- [ ] 先建立独立异步时钟和AXI读BFM，记录RED；完整扫描以公式oracle比较所有窗口及背景像素。
- [ ] 实现valid/ready显示记录、稳定CDC、双时钟双bank行缓存、每行一次读取及右窗口消费后释放。
- [ ] 首行就绪且frame_start才commit；新记录不得覆盖未接纳旧记录；release晚于旧帧在途读取和bank引用。事件保持到ready。
- [ ] 验证两个不同frame_id图样、不同相位/速比、3个完整扫描及每扫描300次行读取、帧中提交不立即生效、延迟首行/延迟返回、错误RID/RESP/LAST、欠载输出背景及协调reset。
- [ ] `iverilog -g2012 -Wall -s tb_preview_display -o build/video/preview_display/display.vvp rtl/video/preview_display.sv tb/video/tb_preview_display.sv`，执行vvp需 `PREVIEW_DISPLAY_PASS`。
- [ ] 给出全部CDC寄存器/保持区间/约束清单；独立规格审查、质量审查和单独提交。

## Task 4：读回CRC、联合板级工程及原生入口

文件：`rtl/video/video_frame_crc_reader.sv`、`rtl/video/video_preview_engine.sv`、`tb/video/tb_video_frame_crc_reader.sv`、`fpga/pg2l100h/rtl/video_preview_board_top.sv`、`project/video_preview_board.json`、`constraints/video_preview_board.fdc`、`tb/video/tb_video_preview_board.sv`；修改 `scripts/video/{run,build_pds,package_board,program_board,read_board}.py` 及对应Python测试。

- [ ] 先测试CRC读取（行尾/stride/4KiB/坏RID/RESP/LAST/abort排空）及UART新包资格，RED后实现。
- [ ] capture写退休→raw CRC→preview CRC→display提交，单一桥的读通道阶段所有权不得交错；桥故障和健康丢失撤销旧PASS。
- [ ] 联合顶层保留原DDR层次、PLL/训练/复位，新增CDC约束不放宽既有时钟或切掉本地同步路径。
- [ ] 新目标显式列出来源、测试及约束；脚本增添独立目标和回归套件，回退镜像继续可构建/打包。
- [ ] 联合数字集成验证真实UART、KEY0、停钟/init loss、无源和旧PASS撤销，数字替身不作为物理证据。
- [ ] `python scripts/video/run.py --suite all` 当前输入全部匹配；独立规格及质量审查通过后提交。

## Task 5：物理构建与验收

- [ ] `python scripts/video/build_pds.py --target video_preview_board --stage bitstream` 全内部约束通过；逐位/CDC/bundle及引脚审计，不下载失败产物。
- [ ] `python scripts/video/package_board.py --target video_preview_board` 按位流/掩码哈希打包，保留RX回退包。
- [ ] `python scripts/video/program_board.py --target video_preview_board --start-server` 后读取UART；两路计数/CRC通过、显示commit及扫描持续、无欠载。
- [ ] 现场同源双窗口和KEY0恢复分别确认；远程无法确认时明确待验并保持证据准确。
- [ ] 更新 `docs/video/{STATUS,README}.md`、`docs/interfaces/video.md`、`docs/verification/video/shared_preview.md` 及小型JSON摘要；只做本地Video提交。
