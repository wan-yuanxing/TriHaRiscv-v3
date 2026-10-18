# Video 接口状态

依据：v0.6 第 3、8、9、11.3 节。固定800×600输入、彩条、DDR及真实HDMI raw单帧已有分别记录的物理证据。同帧raw/preview在d017092绑定的复位分离版本通过四角图和真实桌面的两次受控实体KEY0图像验收，历史黑帧/裁切失败仍保留，证据见 `docs/verification/video/shared_preview.md`。本批新增独立检测缩小组件；CPU fabric/MMIO、量化input分支及SoC三槽生命周期尚未冻结，下述局部接口不替代共同契约。

## 独立检测缩小组件

`detect_downscale`的`clk/reset_n/clear`、`s_valid/s_ready/s_rgb/s_row_last`和`m_valid/m_ready/m_rgb/m_row_last/fault`与preview scaler同类。宽高为5的倍数、5..2045，默认800×600；每个完整5×5块按各RGB通道`floor((sum+12)/25)`输出一个RGB888像素，默认160×120。帧只运行一次，下一帧需协调clear/reset。clear取消当前帧，RAM不清除，但第0行覆盖后才读累计，禁止调用方在取消时继续发送旧帧。

输入未知RGB或错误/未知row_last置sticky fault并停止消费；完整帧后继续s_valid也置fault。已有输出在故障时保持至ready，不能把fault当作撤销公开VALID的许可。运算流水预留唯一输出槽，pending期间停止输入，输出消费可与下一源像素同拍。调用方必须处理ready背压，不能将此组件直接连到不可停顿的物理HDMI引脚。

该组件不转换BGR、不量化、不补8行或C8无效通道，不发布三分支就绪。模型尺度和量化零值未冻结，不把RGB888输出称作可供NPU执行的正式输入。组件验证见[detect_scale.md](../verification/video/detect_scale.md)。

## 检测输入格式组件

后续集成目标已由用户选择适配外部NPU 4fc0fc8：固定800×600源按OpenCV4.11 UINT8双线性缩至320×240，上下各补40行，输出UINT8 BGR NCHW三平面307200B、scale=1/zero-point=0。数值参考见[yunet320_reference.md](../verification/video/yunet320_reference.md)。下面160×128/C8模块为已验收独立组件；新的板级RTL/DMA入口和公共配置/输入槽迁移尚待分批实现，不能将两套布局混用。

`detect_bilinear`已提供有效RGB缩小组件，默认800×600→320×240；FRAME_WIDTH/HEIGHT为5..2045内5的倍数。端口与scaler同类：clk/reset_n/clear、s_valid/s_ready/s_rgb/s_row_last、m_valid/m_ready/m_rgb/m_row_last/fault。源行/列2号相位也检查未知RGB与行末；accepted错误及末输入后额外s_valid置sticky fault，blocked payload不解释。fault取消尚未公开流水，保持已公开VALID及数据至ready；clear/reset可协调取消并重新采一帧。RAM不清，top行覆盖后再读。输出仍为RGB有效图像，未包含BGR/40行补边/NCHW/DMA；验证见[detect_bilinear.md](../verification/video/detect_bilinear.md)。

`detect_input_pad`处理量化前图像，输入s_rgb高/中/低字节为R/G/B，输出m_bgr高/中/低字节为B/G/R。默认160×120→160×128，底部生成raw零；输出伴随row_last/frame_last/padding。宽1..2048、有效高1..2048、存储高有效高..2048，支持零补行。单帧clear/reset，row_last不匹配或未知RGB在接纳时置fault，补行/完成后额外s_valid置fault。

`detect_c8_pack`的req_valid/req_ready/req_zero锁存本帧外部模型所有者提供的量化零编码。s_q_bgr的高/中/低字节为已经量化的B/G/R；s_row_last/s_frame_last/s_padding必须匹配本帧坐标，padding三个有效通道必须等于req_zero。它不执行量化，不从raw补0推测量化零。输入字节以二补码编码原样搬运，未定义尺度、舍入或饱和。

输出m_data[7:0]为先像素B，[15:8]为G，[23:16]为R，[63:24]为5个量化零；后像素位于[127:64]。m_keep在整拍为ffff、奇数宽行尾为00ff，尾拍无效高64bit清0，不跨行拼装。m_row_last/m_frame_last同拍保持。默认行1280有效字节、共163840字节；本地done仅在末输出消费后成立，必须继续等待所有DMA写响应才能形成未来的正式三分支完成事件。

两个模块均遵守背压保持，fault不撤销已公开VALID，clear/reset是协调取消。pack的半拍、未消费输出及done均在取消时清除；请求前不接纳数据，fault/完整帧后不再接纳新帧。验证见[input_format.md](../verification/video/input_format.md)。

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

## 同帧共享预览组件

`preview_downscale` 使用core域ready/valid；RGB888按每通道四像素求和后 `(sum+2)>>2` 输出，输入为800×600、输出400×300。同步行RAM保留上一行，背压时输入和输出分别按握手推进。未知像素/行末或错误计数使fault保持至clear/reset。

`video_preview_capture` 接收既有48bit PIX/EOF流，只有raw packer和scaler同时可接纳才消费同一个PIX；两条DMA以AW到B为所有权单位共享AXI。raw测试区 `0x87300000`，800×600、2400B行步长、1440000有效字节；preview测试区 `0x87460000`，400×300、1200B行步长、360000有效字节。两区均为预留诊断区，不是正式三槽配置。good EOF、tag1、480000/120000像素、两个成功写结果齐备后才完成双平面写阶段。

`video_frame_crc_reader` 请求锁存base、row_bytes、stride、rows、tag和expected_crc，以16B对齐、最多16拍及4KiB边界分割，跳过stride padding，只对有效RGB字节计算CRC32/ISO-HDLC。结果保持到ready；故障和未知CRC不能成功。公开AR不会因abort/offline/timeout撤销，已公开长度必须排空；消费结果不代表故障端口可立即复用。

CRC数据通路使用正常R接纳拍预存后续地址候选，既有BYTES周期内移位取低字节，不增加协议周期或故障窗口。无复位scratch仅在正常R接纳后使用。请求接纳沿即执行原完整描述符/未知值检查，拒绝仍即时code01且不发布AR；被拒payload可改变ARVALID=0时的ARADDR，调用方只在VALID成立时解释AR payload。原故障优先级和RESULT保持条件不变。

`preview_display` 的core接口为 `record_valid/ready` 和base/stride/frame_id/slot。接纳后稳定总线经toggle握手跨到pixel域；首行就绪且 `pixel_frame_start` 才切换。`commit_valid/ready` 与 `release_valid/ready` 分别保持对应frame_id/slot；release晚于旧帧在途DMA及像素流水线引用退休。事件背压期间继续重复扫描活动帧。新记录不能使用仍受保护的base或slot；调用方仍须保证不同base代表互不重叠的分配区。

显示的双bank双时钟RAM每行只读DDR一次，左右窗口各消费一次，右侧最后像素退出流水线后回收。默认窗口 `(0,150)` 和 `(400,150)`，各400×300，背景RGB `101820`，输出RGB/HS/VS/DE同拍延迟。欠载输出背景并锁存故障；扫描不可暂停。scalar控制仅切异步首级D路径，稳定bundle实设6ns，本地同步级保持常规setup/hold。core/pixel复位必须协调；此单记录目标优化掉未消费release payload，多记录目标必须补其6ns数据束约束。

`video_preview_engine` 顺序完成capture→raw CRC→preview CRC→display；显示接管读口后保持所有权至协调reset，包括故障排空。source fault/overflow或DDR丢失会撤销诊断done；本目标仅一次frame_id1/slot0，KEY0使三域协调复位后重采。

preview板级入口增加 `video_capture_startup_guard`，默认128个连续完整好帧之后才准入下一frame_start。只统计从frame_start起持续mode_good/rx_ready且good frame_end结束的完整区间；任意健康丢失或坏EOF清计数，饱和不回卷。RGB不参与判断，合法黑色帧仍可被选中。该有限稳定期不是通用的源内容就绪证明，也不改变入口FIFO/显示bank协调复位或既有5秒超时。后续预览专用clock/reset模块将KEY0采集复位与HDMI初始化分离，d017092所绑定镜像已通过受控物理复验。

preview板级FIFO读口与引擎之间另有 `video_stream_register`，在同一core域持有一个48bit词。无组合数据直通，空时增加一周期延迟，满时可在同一沿退休并替换；背压保持数据和valid。run/valid由既有core协调复位清零，数据存储不复位，取消不会独立丢弃所有权。FIFO RAM水位及EOF峰值字段仍排除core持有词；此级增加一个额外持有词，不改变原Gray指针或CDC束约束。

联合目标UART仍为37B TRV1包；payload0为type，1为flags，2为phase，3为error_code，4..31为七个小端uint32：

| type | payload 4..27的六个uint32 | payload28..31 |
|---|---|---|
| 6 | raw_pixels、preview_pixels、raw_source_crc、raw_ddr_crc、preview_source_crc、preview_ddr_crc | heartbeat |
| 7 | frame_id、commits、completed_scans、underflows、read_lines、fifo_peak | heartbeat |

flags bit0..7为init_done、busy、done、error、all_pll_lock、rx_mode_good、tx_done、overflow；tx_done同时要求发送初始化完成和HDMI PLL锁定。两种状态来自同一个448bit冻结快照，UART每次发送完成后交替包型。`read_board.py` 分别输出capture与display资格；较新任一包的故障或重启会使前一轮PASS失效，显示还要求两次推进扫描、无欠载和相符行读预算。CRC相等证明有效字节的一致性，不能单独证明缩放数值或实际画面质量。

## 后续 CPU–Video 协议准入

单平面组件 `rgb888_packer` 与 `video_write_dma` 以core域ready/valid流连接，物理HDMI的不可背压像素由既有FIFO/CDC和帧接纳器接入。内存递增地址按R、G、B保存，`WDATA[8*k+:8]` 对应字节地址 `AWADDR+k`，不能直接把 `24'hRRGGBB` 低字节优先解释为同一格式。

packer默认 `ALLOW_SIMULTANEOUS_TRANSFER=1` 保留同拍出入；共享预览的两个实例选择0，使输入和输出传输互斥，输入字节只按注册count定位，避免下游READY经占用更新参与输入字节位置选择。容量仍为18字节，17/18字节行尾分为完整拍及1/2字节尾拍。固定800/400像素行在无下游停顿时需950/475个core周期，125MHz下理论峰值约105.263Mpixel/s；这是组件上限，实际FIFO水位和端到端表现由板测另验。

DMA 请求锁存 `req_base/req_row_bytes/req_stride/req_rows/req_tag`，base 和 stride 为16 B对齐，stride≥row_bytes>0；整个有效区和最后总线拍必须在逻辑 DDR 窗口内。stream 为 `s_data[127:0]/s_keep[15:0]/s_row_last`，keep 为全有效或行末连续低位1，row_last 与行字节数严格匹配。每次 AW 前完整缓存 burst，按行、16拍和4 KiB拆分；stride padding 不写。

`result_valid/result_ready/result_success/result_code/result_tag/written_bytes` 是**单平面写结果**，保持至消费；written_bytes 只计正确 BID/OKAY B 覆盖的有效字节，错误 burst 仍可能部分改写内存。它不表示完整 HDMI 帧几何合格，也不等于 `CAPTURE_DONE/INPUT_READY`。abort 丢弃未公开数据，已公开的 AW/W/B 必须排空；上游须 flush 旧 packer/stream 后再发新请求。wrong BID/无主 B/初始化丢失等端口故障须协调复位。

新增真实源入口 `video_capture_ingress` 和独立诊断引擎 `video_capture_engine`：core先接纳单次descriptor再翻转arm；像素域等待合法帧首，PIX/EOF经48bit Gray指针FIFO跨域。EOF同时携带good、源CRC和保守RAM水位；源坏帧、overflow和cancel保持至协调reset，不能从下一帧补旧帧。默认FIFO RAM2048字，另有一个读输出寄存器；无条件持续供数或任意native停顿下无溢出不在保证内。

引擎分别保持good EOF和成功DMA结果，两者齐备才读DDR，按递增有效字节地址逐字节计算CRC32/ISO-HDLC。480000像素、1440000字节、tag1、计数/行末和CRC完整一致才置本地raw诊断done；读AR/R和写AW/W/B故障后按advertised长度排空。`busy=0`在故障后只表示诊断任务停止推进，不能作为端口已经排空或可复用的凭证；本阶段必须协调reset才重采。

联合目标 `video_hdmi_capture` 的type5 UART报告原始源单帧数据一致性，本地输出仍是独立彩条。物理结果和CRC碰撞边界见 `docs/verification/video/hdmi_raw_capture.md`；该本地done不具有SoC三分支CAPTURE_DONE或CPU槽所有权语义。

保留规格的控制基址 `0x2001_0000` 与寄存器区间；当前不生成可误用的完整 `video_regs.h`，待详细位定义、复位值、W1C 和忙时规则形成一致版本后一起生成 RTL/C。

- CAPTURE_REQUEST：保存请求；在下一合法完整输入帧边界发布带 slot/frame_id 的 CAPTURE_ACCEPTED。
- CAPTURE_DONE/INPUT_READY：同一逻辑事件，raw、preview、input 三分支及对应写响应完成，尺寸检查通过后发布。
- DISPLAY_SUBMIT：接纳完整影子记录；接纳与实际提交是不同事件，不直接修改活动寄存器。
- DISPLAY_COMMIT：安全输出帧边界原子切换 preview、框、头像、状态和 frame_id。
- DISPLAY_RELEASE_ACK：旧槽所有 DMA、预取与像素缓存引用结束后确认，不能等同于 DISPLAY_COMMIT。
- 地址、slot、frame_id、预处理版本必须校验；状态/事件保留到软件消费，旧事件不能推进新任务。
- CPU 统一维护槽状态与 graph_active/frame_owner；Video 只管理自己持有的引用和握手。共享 DMA 数据不可缓存。

详细记录打包、序号回绕/复位代际、超时、屏障与中断规则在 V020 前完成 CPU–Video 联调，不以本文件存在代替接口已冻结。
