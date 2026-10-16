# Video 接口状态

依据：v0.6 第 3、8、9、11.3 节。当前已实现固定时序、彩条、PLL/复位及独立发送初始化；采集/显示 MMIO、DDR DMA、帧所有权接口仍是后续实施契约。TX-only 板级端口与状态见 `docs/verification/video/board_smoke.md`。

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

## 已实现：video_rx 候选像素与帧几何确认

输入 `pixel_clk/reset_n/enable/rx_ready/hs_in/vs_in/de_in/rgb_in` 已在接收像素域同步，RGB 为完整 24 bit。输出 `pixel_valid/rgb_out/x/y` 为注册的候选像素；`frame_start` 与首个候选 `(0,0)` 同拍。启动中途、disable、rx_ready 丢失后等待新的正 VS 边界，避免拼接前后两帧。

下一正 VS 边界输出 `frame_end`，仅当刚结束间隔中每行连续 800 像素、600 活动行、1056 周期/行、628 行/场以及同步/DE 不重叠等检查通过时，`frame_good` 同拍为 1 并获得 `mode_locked`。首个完整合格间隔之前不宣称锁定；错误时撤销锁定，`mode_error` 复位前保持。

`active_width/active_height/h_total/v_total` 分别记录最近非空行、间隔和 HS 周期的测量；失去 enable/readiness 后清除。该模块不测量自身像素时钟频率，也未完整检查同步脉宽与每个 porch 长度。物理 RX 初始化、外部时间基准及上板输入模式确认仍由后续板级链路完成。

候选像素可以先写入预留存储，但消费者必须等 `frame_good` 后才能把它视为几何合格帧；还需等待各 DMA 写响应，才能发布正式 `CAPTURE_DONE/INPUT_READY`。本模块的事件不能替代这些完成语义。

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
