# HDMI 单帧 raw 采集设计

基线 `598a064`，Windows 原生，沿用 `video/windows-bringup` 工作目录。用户已授权 Video 实施，并在 AXI/DMA 板测及 RX 彩条恢复后要求继续。此文冻结该方向的下一项可独立验收工作；不要求再次批准已有路线。

## 范围与方案选择

实现真实 PC HDMI 的一帧800×600 RGB888采集：下降沿统一采样 → 已有几何/精确时序监测 → 整帧接纳 → 异步FIFO → 既有packer/DMA/AXI桥 → 真实DDR → 独立读回CRC。保留本地彩条输出和固定EDID；每次KEY0协调复位只采一帧，结果保持。使用测试预留区，不抢占正式CPU帧槽。

直接跨域逐像素采样不能保证数据一致；完整帧片上缓存占用过大。选用有明确满检测的双时钟FIFO，吸收写DMA的突发等待；有限FIFO不承诺任意DDR停顿下不溢出，溢出必须使整帧失败。共享fabric、preview/input生成、读显示DMA及正式三分支CAPTURE_DONE仍分别实施。

## 可复用模块及新增职责

- 保持 `axi128_hmic256.sv`、`video_write_dma.sv`、`rgb888_packer.sv` 的已验证接口与行为。
- `rtl/video/video_async_fifo.sv`：参数化双时钟FIFO，二进制本地指针、注册Gray跨域、两级同步、同步读存储器和受阻稳定的输出寄存器；协调复位之外没有局部flush。
- `rtl/video/video_capture_ingress.sv`：源像素域单帧接纳、源端CRC、行末标记及EOF元数据；包含FIFO及core侧arm/cancel和源fault/overflow的单bit同步器。
- `rtl/video/video_capture_engine.sv`：core域单次descriptor、packer/DMA/桥、FIFO包检查、独立DDR读CRC及所有权排空；不管理I²C/PHY。
- `fpga/pg2l100h/rtl/video_hdmi_capture_top.sv`：组合现有HDMI和DDR物理壳，保持 `clocks`、`telemetry`、`I_ips_ddr_top` 等必要约束层次。核心引擎实例沿用 `bist`，使既有DDR异步复位端点例外仍有对应对象；pixel FIFO实例位于独立 `ingress`。
- `project/video_hdmi_capture.json` 为显式filelist；新HDMI补充FDC只增加原始HDMI引脚、生成时钟及新CDC约束，DDR FDC/RCF原件不改。

## FIFO和帧接纳契约

默认FIFO深度2048、字宽48；地址宽11，满时绝不推进写指针或覆盖旧数据。输出寄存器可额外持有一个已预取字，文档/水位把它与RAM容量区分。Gray跨域只允许单步本地指针更新，源总线时延与skew有独立约束，不用全时钟组false-path掩盖总线。

每字编码：`[47:46]` kind，PIX=0、EOF=1，其余非法；PIX的bit45=row_last、[23:0]=RRGGBB，其余0。EOF的bit44=good、[43:32]=RAM保守最大占用（包含同步延迟影响，不计输出寄存器）、[31:0]=源帧CRC。RAM写端占用由本地write binary减同步read Gray解码获得，满标志与该保守观测一致。

ingress接口固定为 `pixel_clk/pixel_reset_n/core_clk/core_reset_n`，源输入 `pixel_valid/pixel_rgb[23:0]/pixel_x[10:0]/pixel_y[10:0]/frame_start/frame_end/frame_good/mode_good/rx_ready`；core输入 `arm_toggle/cancel`，输出 `m_valid/m_ready/m_data[47:0]/source_fault/overflow`。几何参数 `FRAME_WIDTH/FRAME_HEIGHT`、FIFO参数 `FIFO_ADDR_WIDTH`。source_fault和overflow是core域两级同步后的保持状态。

core先成功接纳DMA descriptor，再翻转arm。像素域同步后等待下一次 `frame_start && pixel_valid && mode_good && rx_ready`，第一候选像素同拍入队；不把启动中的半帧拼入。接纳后检查逐像素x/y、总数和行末，CRC覆盖所有选中候选的R、G、B字节。坐标、readiness或几何错误保持source_fault并停止发布像素；满时丢弃整帧、保持overflow，绝不静默丢像素后成功。

下一frame_end只在frame_good、mode_good、总数和全部坐标都合格时发布good EOF；EOF在源域寄存保持，可在FIFO满时等待空间，不把可停顿的EOF本身当像素溢出。core cancel经两级同步后停止源写入。一次arm只能产生一帧；下一请求必须协调复位。

像素端与core端复位都只由KEY0/全局启动产生，并分别本域同步释放；RX失锁、DDR初始化丢失、超时和普通abort不单独清FIFO/桥缓存。

## 内存及完成条件

固定逻辑base=`0x87300000`，测试allocation=`[0x87300000,0x87500000)`。默认2400 B/行、600行、1,440,000有效字节。缩小测试几何stride为 `ceil(width*3/16)*16`；只读写有效字节，padding和allocation外红区由独立数字模型检查。

engine接口使用 `clk/reset_n/init_done`、上述core FIFO/arm/cancel/fault信号、既有BIST同名native AXI端口及 `busy/done/error/phase/error_code/captured_pixels/checked_bytes/source_crc/ddr_crc/frame_tag/fifo_peak` 诊断。`FRAME_WIDTH/FRAME_HEIGHT/TIMEOUT_CYCLES` 为参数；默认frame_tag=1。原始位地址转换仍只由生产桥处理。

收到EOF前后，DMA成功响应可先到或后到，两个事实分别保持，不能漏掉先到事件。开始读回前必须同时满足：源good EOF、恰好width×height像素、正确所有行末、DMA成功结果及完整written_bytes、正确tag、无源/FIFO/桥错误。读回的AR按行、16拍和4KiB拆分，检查RID/RRESP/RLAST；每拍缓存后每core周期处理一有效字节，避免16字节组合CRC进入125MHz关键路径。

CRC使用CRC-32/ISO-HDLC：反射多项式 `0xedb88320`、初值 `0xffffffff`、最终取反、字节顺序R/G/B，标准字符串123456789结果 `0xcbf43926`。DDR读回按递增有效字节地址处理，忽略stride padding。成功需checked_bytes完整且两个CRC相等。物理CRC一致是传输一致性证据，存在CRC碰撞的固有限制；数字模型必须逐字节核对，不能只比较同一实现生成的CRC。

本地完成名义为raw单平面诊断结果，不发布CAPTURE_DONE/INPUT_READY。DMA/桥独占native；本阶段不引入多主仲裁，也不测持续帧率。

## 故障与在途事务

总任务看门狗默认5秒，等待模式/源停钟/EOF缺失也受监测；错误首次保持，禁止新请求，cancel源并abort DMA。已公开AW/W/B和AR/R继续遵守生产桥/主端排空契约；永久native停顿时错误可被报告，但必须协调复位才能完成排空。不能撤回VALID或用局部reset伪造取消。

无core时钟、PHY失败、PLL/init丢失及core快照停滞仍由独立27MHz域监测，撤销旧PASS。已完成帧后当前HDMI模式丢失单独呈现，不把历史帧当新采集；host合格条件同时检查当前模式、DDR/发送初始化、两个递增heartbeat包和完整CRC/计数。

## UART和验收

继续TRV1/37字节/115200/8N1/XOR、小端，新增type5 payload=`<4B7I>`：type、flags、phase、errorcode、captured_pixels、checked_bytes、source_crc、ddr_crc、frame_tag、fifo_peak、heartbeat。flags bit0..7=DDRinit/busy/done/error/allDDRPLL/RXmodegood/TXdone/overflow。默认成功为480000像素、1440000字节、tag1、CRC相等、overflow0；两包heartbeat不同且所有健康条件满足才置 `physical_hdmi_raw_capture_verified`。收包成功与物理合格分开。

数字验收含：FIFO异步比率/相位、满空/回卷/长stall/输出稳定/两域复位；ingress中途arm/先坏后好/首末像素/overflow/cancel/clockstop；端到端13×3、16×3、1367×3、800×600，独立byte memory和CRC oracle、反向通道背压、EOF与DMA结果两种先后、错行/错包/CRC与R通道错误、初始化丢失、各阶段协调reset以及故障时VALID稳定。板级数字替身需检查UART真实串行、无初始化/无core、停钟和旧PASS撤销。

PDS使用当前125MHz及0.2ns内部margin、40MHz RX/TX时钟；严格消息审查和慢/快角setup/hold/recovery/removal全部满足后才允许打包。脚本更改使恢复RX包失效时，必须重新构建/打包恢复包。实际Program/Verify → UART计数/CRC → KEY0后新采集 → 恢复RX并复验/观察彩条，分别记录证据。不把外部HDMI/DDR AC或保护库训练仿真自动标为通过。
