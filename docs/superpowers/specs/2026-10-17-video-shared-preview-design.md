# HDMI共享预览与同帧双窗口设计

依据v0.6第8.1、8.3、8.4、9.3节及既有Video路线P2。用户已授权继续下一阶段，沿用 `video/windows-bringup` 和当前工作区。上一阶段基线 `2f309c4`；技术报告的独立修改不纳入。

## 范围与方案

本阶段从同一真实HDMI完整帧同时生成raw RGB888和400×300 preview RGB888；两份写响应和独立DDR读回CRC全部合格后，在安全输出帧边界显示两个400×300完整视图。按需单帧/KEY0重采，暂不连续采集。采用流式2×2缩放，避免第二次读取raw生成preview；保留原raw-only目标作为回退。检测5×5/量化属于P3，本阶段的完成仅称raw/preview诊断完成，不发布SoC CAPTURE_DONE/INPUT_READY。

备选为先从DDR的raw生成preview，或直接复制本地彩条形成双窗口；前者增加raw读取且不满足采集时分支目标，后者不能证明真实输入经DDR显示，因此选用双分支实时写入和共享行缓存。

## 数据与接口

- 原输入解析和48bit异步FIFO保持不变；core在合法PIX上原子分送raw packer及preview_downscale，任一路未ready均不消费原PIX。不可背压输入的FIFO满仍整帧报错。
- `preview_downscale` 参数FRAME_WIDTH/FRAME_HEIGHT，均为偶数且2..2048。端口为 `clk,reset_n,clear,s_valid,s_ready,s_rgb[23:0],s_row_last,m_valid,m_ready,m_rgb[23:0],m_row_last,fault`。clear只用于无在途任务的启动/协调清理；禁止中途清除已公开AXI。输出按每通道 `(sum+2)>>2`，行宽减半、行数减半；输出受阻保持。检测行末及多余像素，错误保持到clear/reset。行RAM不整体复位。
- 新 `video_preview_capture` 参数FRAME_WIDTH/FRAME_HEIGHT/TIMEOUT_CYCLES，消费原48bitFIFO，提供arm_toggle/cancel；双packer/双写DMA经本地burst级轮询汇合到单一AXI128写口。AW选中后直到对应B完成保持归属，AW/W受阻不撤回VALID；每分支最多一个事务。这是独立诊断内部合流，不替代CPU正式fabric。
- capture输出 `busy,done,error,error_code,captured_pixels,preview_pixels,source_crc,preview_crc,fifo_peak`；done需good EOF、两个DMA成功且计数/tag精确匹配。source_crc来自源EOF，preview_crc按实际送入preview packer的R/G/B计算。异常锁存、已公开事务排空，协调复位才重采。
- 独立 `video_frame_crc_reader` 在写退休后逐平面读CRC，按行有效字节计算，不将行尾padding计入。AXI128 INCR、16拍上限、4KiB拆分；RID/RESP/LAST严格检查，错误后排空已公开读burst，VALID受阻保持。
- 测试保留区raw基址 `0x87300000`、preview基址 `0x87460000`，各行2400/1200B；结束均小于 `0x87500000`。小几何测试将stride向上16B对齐，不修改正式三槽规划。

## 显示组件契约

`preview_display` 提供core域显示记录valid/ready接纳（base/stride/frame_id/slot），输出core域保持到ready的commit事件和旧记录release事件。pixel域接收独立时钟、同步释放reset及输出扫描x/y/hs/vs/de/frame_start，输出延迟一致的RGB/hs/vs/de。128bit AXI读口连接同一生产桥，读取与capture/CRC按任务阶段串行使用。

像素只读已完成且引用受保护的preview。双时钟乒乓行RAM，每行只从DDR读一次，带frame_id/行号；左 `[0,400)×[150,450)` 和右 `[400,800)×[150,450)` 各消费一次。右窗口结束前不得覆写该bank。上下输出确定性本地背景。首行就绪后才在frame_start原子提交记录；待提交记录稳定保持，忙时不接纳新记录。旧记录所有在途读和bank引用退休后才发release。首版允许提交等待多个扫描周期。

CDC使用每bank稳定请求/完成toggle握手，相关地址/行号/记录在确认前保持；每条bundle给出源/目的寄存器与保持区间，约束必须有max-delay及第一同步级单独例外。不能用整时钟组false-path掩盖bundle或本地域路径。独立源/目的复位由协调KEY0支配，不能只因RX失锁清bank。

欠载不暂停扫描，输出本地背景并锁存错误/计数；不能借另一行或另一帧内容补齐，不把受影响扫描计作完整显示。DDR/PLL/超时错误撤销旧成功。第一版可要求协调reset恢复，不能宣称无缝热插拔。

## 板级、诊断与验收

新增 `video_preview_board`，保持HMIC内部层次及原DDR FDC/RCF，沿用现有HDMI初始化、输入时序检查和看门狗。复用生产桥；捕获、CRC和显示读用显式阶段所有权，不能在读仍在途时切换。UART分别报告raw/preview计数和两对CRC、显示frame_id/commit/扫描/行读取/欠载计数及心跳。包资格与raw-only type5分开。

验证分层：

1. 缩放独立四像素oracle，穷尽sum=0..1020、全黑/全白/通道独立、随机受阻、行尾、clear和故障；完整800×600逐像素比较。
2. 双分支独立byte-memory oracle核对raw及preview全部有效字节、padding和红区；延迟B/错误响应/overflow/坏EOF/源停钟/复位，最后写响应前不得done。
3. 显示独立非同相core/pixel时钟及AXI BFM，逐输出像素核对位置/缩放/同帧，计数每扫描300次行读取；新记录帧边界提交和旧记录释放、首行延迟、在途reset、错RID/RESP/LAST及欠载背景。
4. 联合数字集成采用明确标记的DDR替身；最终完整回归、当前输入哈希、PDS所有内部多角时序和CDC约束审计通过后才可打包/下载。
5. 物理Program/Verify、UART两分支CRC和持续显示计数、现场两幅同一完整画面/四角及KEY0恢复分别记录。实体按键与现场画面需用户实际确认；未确认前保持待验。

外部HDMI AC及厂商保护训练仿真沿用未签核状态。本阶段不包含CPU MMIO冻结、共享多主QoS、NPU、框/头像、连续fps或三分支完成。
