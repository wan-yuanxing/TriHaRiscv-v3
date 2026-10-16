# Video 接口状态

依据：v0.6 第 3、8、9、11.3 节。当前已实现固定时序、彩条、PLL/复位、独立发送初始化、固定 EDID 接收配置及精确输入时序监测；下降沿 RX 采样已通过真实 800×600 输入板测。采集/显示 MMIO、DDR DMA、帧所有权接口仍是后续实施契约。TX-only 端口见 `docs/verification/video/board_smoke.md`，RX/DDR 证据见 `docs/verification/video/rx_ddr_bringup.md`。

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

## 已实现：物理 RX 与串口诊断

`video_rx_board_top` 按 TX → RX 顺序配置共享 I²C；SDA 开漏，SCL 仅一个所有者。G25 同时复位两颗收发芯片，RX 重连不得单独拉低它。RX boot 完成和频率事件后的配置完成分别报告；后者是保持状态，不是实时 HDMI 锁定信号。未经文档确认的状态寄存器只保留原始字节，不推测频率单位。

固定 EDID 使用 40 MHz 的 800/256/600/28 详细时序，无扩展块。输入 HS/VS/DE/RGB888 在 PCLK 下降沿统一捕获，供上升沿几何监测和精确时序检查使用。选择依据为上板观察到原上升沿采样有一周期的 HS 边沿歧义；内部半周期时序与真实输入测量分别验证，仍不替代收发芯片外部 AC 参数的签核。

频率计数以 10 MHz 配置时钟为时基，注册 Gray 计数经两级同步，在 10 ms 门宽测量；39.8–40.2 MHz 视为频率合格。完整状态经冻结源总线、req/ack 两级同步及额外等待沿传递。停钟后频率/新鲜度撤销最迟约两个门宽，不能当作零延迟断线中断。

UART C24、115200、8N1。每包 37 字节：ASCII `TRV1`，32 字节 payload，前 36 字节逐字节 XOR 校验；payload 整包锁存，多字节小端。约每秒一包，RX 目标按 heartbeat 状态输出 type 1 和 type 3，不保证严格交替：

| Payload 字节 | type 1：模式测量 | type 3：原始边沿探针 |
|---|---|---|
| 0 / 1 | 类型 / flags | 类型 / 同一 flags |
| 2–3 | RGB888 帧签名 | 保留为 0 |
| 4–23 | 10 个 uint16：ha、va、ht、vt、hs、vs、hfront、hback、vfront、vback | 5 个 uint32：VS 高电平周期、VS 周期、HS 上升/下降次数、VS 上升次数 |
| 24–27 | 像素 Hz，uint32 | VS 下降次数，uint32 |
| 28–31 | 好/坏帧计数低 16 位 | DE 上升次数，uint32 |

flags bit 0..7 为 TXdone、TXerror、RXbootdone、RXerror、RXconfigured、snapshotfresh、frequencygood、modegood。只有完整帧几何、全部同步/porch、频率及初始化条件同时通过才置 modegood。串口收包成功不表示模式验收成功；type 3 的 VS 周期以像素时钟为单位，不能与 type 1 的行数混淆。两种包分别为完整 CDC 快照，跨包不保证同一帧。

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
