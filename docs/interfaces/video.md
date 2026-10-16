# Video 接口状态

依据：v0.6 第 3、8、9、11.3 节。当前已实现并验证的接口仅为固定时序和彩条组件；采集/显示 MMIO、DDR DMA、帧所有权接口仍是后续实施契约。

## 已实现：video_pattern_core

| 信号 | 含义 |
|---|---|
| `pixel_clk` | 外部提供 40 MHz；当前组件不含 PLL |
| `reset_n` | 低有效，异步置位；调用方必须在像素域同步释放 |
| `hsync/vsync` | 正极性，脉宽 128 像素/4 行 |
| `de` | 仅 800×600 有效区；复位时为 0 |
| `frame_start` | 有效区起点 `(0,0)`，复位时为 0 |
| `rgb[23:0]` | `{R[7:0],G[7:0],B[7:0]}`，消隐为黑；当前八色条 |

内部光栅坐标从有效区 `(0,0)` 起，水平 active/front/sync/back 为 800/40/128/88，垂直为 600/1/4/23。总计 1056×628，扫描率约 60.3165 Hz。像素有效区后的消隐属于同一光栅周期。

## 后续 CPU–Video 协议准入

保留规格的控制基址 `0x2001_0000` 与寄存器区间；当前不生成可误用的完整 `video_regs.h`，待详细位定义、复位值、W1C 和忙时规则形成一致版本后一起生成 RTL/C。

- CAPTURE_REQUEST：保存请求；在下一合法完整输入帧边界发布带 slot/frame_id 的 CAPTURE_ACCEPTED。
- CAPTURE_DONE/INPUT_READY：同一逻辑事件，raw、preview、input 三分支及对应写响应完成，尺寸检查通过后发布。
- DISPLAY_SUBMIT：接纳完整影子记录；接纳与实际提交是不同事件，不直接修改活动寄存器。
- DISPLAY_COMMIT：安全输出帧边界原子切换 preview、框、头像、状态和 frame_id。
- DISPLAY_RELEASE_ACK：旧槽所有 DMA、预取与像素缓存引用结束后确认，不能等同于 DISPLAY_COMMIT。
- 地址、slot、frame_id、预处理版本必须校验；状态/事件保留到软件消费，旧事件不能推进新任务。
- CPU 统一维护槽状态与 graph_active/frame_owner；Video 只管理自己持有的引用和握手。共享 DMA 数据不可缓存。

详细记录打包、序号回绕/复位代际、超时、屏障与中断规则在 V020 前完成 CPU–Video 联调，不以本文件存在代替接口已冻结。
