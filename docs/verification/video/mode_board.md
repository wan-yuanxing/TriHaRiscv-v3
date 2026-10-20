# F3c 独立静态全屏三模式

状态：2026-10-20，独立静态全屏三模式的数字、内部布线/50项端点、Program/Verify及实体验收均通过。四角图三路数值、三次KEY1、返回RAW和普通桌面KEY0恢复已逐项完成。当前板卡保留完整桌面RAW。见[流水计划](../../superpowers/plans/2026-10-20-mode-capture-pipeline.md)。机器摘要见[mode_board.json](evidence/mode_board.json)。

## 行为与边界

独立目标 `video_mode_board` 从冻结 F2 顶层派生，F2 顶层、管脚、时钟、DDR IP 及四份原有约束保持原字节；公共CRC reader、writer及其测试的等价优化，capture第一故障码流水及其测试，以及bridge私有缓存写使能等价简化作为有记录例外，详见下文。默认原分辨率 800×600 RAW；KEY1/C23 低有效，经两级同步和 20ms 去抖，依次切 RAW → BOX → AVATAR → RAW。长按只产生一次请求。KEY0/C22 保留协调复位、DDR 重校准和单帧重采，MODE 与素材回到初始状态；沿用 F2 的 HDMI 初始化保持方式。

BOX 使用人工常量：主人脸红框 `[200,600)×[150,450)`，次框绿色 `[100,400)×[100,300)`；主人脸五点黄色。AVATAR 在主框区域显示本地算术生成的 256×256 RGBA 测试纹理，按非预乘 Alpha 混合。框、点及纹理均是诊断素材，不是 NPU 检测或真实人脸头像。缓存完整写入 65536 字后封存；无 DDR 素材 DMA、CPU 上传或运行中替换。

每次协调复位只锁存一份合法 raw 帧/槽/代际；身份变化为 sticky fault。raw_display 的 RGB/控制先注册两级，新坐标与 SOF 同样注册两级后接 F3b；叠加 13 级加 pad 1 级，因此扫描边沿 n 到 pad 边沿 n+15，共 16 级寄存。模式仅在 raw 对齐 SOF 生效，首像素使用新记录；实际首像素到 pad 后才允许 core 得到提交反馈。

纯 MODE 不向 raw_display 重发记录，不增加 raw commits，不改变 frame_id、采集 CRC 或 arm toggle，不重启 HDMI/DDR。这个独立单帧诊断没有通用多帧所有者、槽释放 ABI 或正式显示 MMIO；F4 仍须实现它们。

## 数字证据

- `--suite mode_output`：三场景，独立数学逐像素及 14 级 helper 对齐；长按、快速合并请求、复位后不同源图。
- `--suite mode_board`：6 个原有健康/故障/复位场景、三模式完整光栅及四种 UART 包；349 光栅、34900 个有效像素。明确断言 MODE 期间三路身份/CRC、arm、raw 提交和 HDMI/DDR 状态不变。板级测试使用标记的数字 DDR/PLL 模型及强制接收前端，不能替代实际采集。
- 实际800×600组合定向检查通过1920021个有效像素；BOX/AVATAR各完整480000像素，返回RAW后序号/反馈仍一致。复用独立数学oracle和14级监视器，仅缩短命令流程。此前完整通用场景在全尺寸下超过600秒计算时限，已另存未完成记录，不计为通过。
- Python：102 项，101 通过、1 项 Windows 符号链接权限跳过。新增 type10 解码、状态/完整轮次/目标切换及 KEY1 管脚校验。独立审查发现旧 MODE 成功可被后来的 raw-only 包沿用；RED 复现后，现要求最新两个完整有序 `6/9/8/10` 轮次，仅接受下一轮最多三包的有序前缀。
- 独立组合及板级审查各有单独来源/产物哈希。板级审查另外核对 42894 个像素，并用 raw 坐标/SOF 错一拍的替身确认测试失败。最终结论以对应 JSON 及父核验为准。

首轮 PDS compile 揭示顶层 net 在使用后声明；仅调整新顶层的声明位置。第一次完整综合拒绝了一条无实际路径的 free_clk→新逻辑 reset 例外。新逻辑复位来自本地 core_release/display_pixel_release，删除多余例外后保持本地 recovery/removal 计时；没有放宽 8ns core 或 6ns bundle 约束。

## 构建、约束及物理检查

当前综合为17252 LUT、18747 FF、73.5 DRM36K、16 APM，包含完整HDMI/DDR、三分支和素材缓存。实际网表检查140个管脚无缺失/碰撞、64素材双钟RAM、77同步链及13组存活束，未发现未覆盖跨域或内部组合环。ASYNC_REG属性被本版PDS忽略，以实际网表/物理路径为依据。

所有构建保留core8ns、pixel25ns和原跨域约束。完成的布线结果如下；表中多种子列出最佳结果，全部hold通过。

| 源码阶段 | 布局 | 最差setup/ns | 失败端点 |
|---|---|---:|---:|
| 原数字检查点 | normal4..9，最佳8 | -0.060 | 2 |
| 原数字检查点 | performance8 | -0.060 | 2 |
| CRC BYTES停止条件拆分 | normal8 | -0.247 | 14 |
| 同上 | normal4..7，最佳6 | -0.140 | 10 |
| CRC接收私有暂存优化 | normal6 | -0.205 | 4 |
| writer先饱和再低位取整 | normal6 | -0.225 | 18 |
| capture第一故障码流水 | normal6 | -0.202 | 92 |
| bridge私有缓存去除当拍WLAST依赖 | normal6 | +0.334 | 0 |

CRC两个改动均已逐拍比较公共输出并独立检查四态；停止首因、公开事务排空和结果保持不变。writer只改burst算术，函数之外原字节保持，2499200组数值/四态及19动态场景公开输出一致；另有228872组独立检查及3个错误替身通过。最新write_dma/raw_board/mode_board回归通过。历史全量37套件的198项输入中187项相同，11项差异由当前定向证据覆盖，不冒称完整all重跑。

流水前slow/fast hold为+0.124/+0.089ns，但setup仍失败，最差路径是preview DMA的结果字节数校验到缩放器使能。前6次完成的构建均未打包/下载。三轮局部等价优化之后转向[控制流水计划](../../superpowers/plans/2026-10-20-mode-capture-pipeline.md)，允许内部故障响应增加一个core周期，同时保护第一错误、AXI排空和成功发布边界。等价检查点与失败来源见[时序记录](../../superpowers/plans/2026-10-20-mode-board-timing.md)。

新增capture流水只将故障分类跨一个core寄存边界；pending立即阻止请求、驱动cancel及三个子DMA abort，第一错误不被后续offline替换。WAIT_EVENT单独检查新标量故障，防止发布成功的同拍竞态；非法/未知像素和EOF不更新摘要。正常成功的数据、事务和CRC周期保持，失败帧允许多计入一次检测边沿的合法接纳，仍须排空全部已公开AW/W/B且不能发布成功。已发布且背压的完成记录仍保持不变。

CASE28定向7项通过，原源RED及三个删除保护的替身均按预期失败。当前three_capture/raw_board/mode_board回归通过，包含800×600及307200字节NCHW黄金检查；原有故障场景保留。独立审查88条命令、12组48次采集、10×10零padding故障复跑、100×50多burst/4KiB三槽正常采集、三种尺寸逐周期原版对照及10个关键guard替身均通过。报告位于`build/video/capture_fault_pipeline_review/review.json`，来源和全部产物由父审计绑定；不代表实际DDR、时序或现场验收。流水版PDS完成后setup为-0.202ns/92端点，slow/fast hold为+0.038/+0.029ns，recovery/removal亦通过。最差路径转至preview DMA burst_beats→WLAST→仲裁器→bridge expected缓存CE，逻辑1.035ns/布线6.390ns，中间控制扇出1881。第7次失败镜像未打包或下载，结构审计仍通过；该轮板上保留已验收F2。

按[桥缓存计划](../../superpowers/plans/2026-10-20-mode-bridge-cache.md)准备最小候选：保留公共WLAST诊断和COLLECT失败排空，仅从未使用的私有缓存写使能去掉当拍WLAST。原桥自校验加1088个故障/复位后恢复用例共1343场景、111496次全部23公共输出对照通过；删去公共LAST诊断的替身被检出。独立native字节模型另完成13739场景、556402有效core周期，全部23公共输出逐半周期一致；其中6656失败写、6951成功写、32成功读。6528核心坏LAST组合及连续全掩码脏缓存、上下半字覆盖、各阶段协调reset均已覆盖，检查1782560字节数据和邻接guard；941次实际私有缓存差异未泄漏到公共接口。4个变异被检出，两种半字漏清零变异关闭原版对照后也被独立native oracle检出。独立报告`build/video/bridge_collect_cache_review/review.json`已由父任务逐项核对哈希。已精确采用候选c3d3f04b，原桥f898c468按字节保存；当前axi_bridge/raw_board/mode_board回归通过。第8次构建`20261019T191756_225568Z`在原约束下通过全部setup/hold/recovery/removal，slow/fast setup +0.334/+2.627ns、hold +0.135/+0.101ns。18份独立只读报告覆盖实际同步级和存活数据束，50项严格核验全部为true；原布局数据库、网表、工程和完整报告哈希未变。实际端点arrival范围及PDS未输出独立max-skew表的限制保留在审计JSON中，不扩大为外部AC签核。

构建器新增seed/mode参数，默认保持4..9/normal；非法值先于构建退出。现场验收器修复了未观察复位沿用、旧Program日志沿用及物理产物绑定三类问题，18项独立检查通过。正式三模式实体验收记录已生成并通过全部严格检查。外部HDMI AC、连续视频、共享fabric/三槽所有权及真实NPU不在本次签核内。

```powershell
python scripts/video/run.py --suite mode_output
python scripts/video/run.py --suite mode_board
python scripts/video/build_pds.py --target video_mode_board --stage bitstream --seed-start 6 --seed-count 1 --pnr-mode normal
python scripts/video/package_board.py --target video_mode_board
python scripts/video/program_board.py --target video_mode_board --start-server
python scripts/video/read_board.py --port COM12 --seconds 60
```

下载入口保留成功构建/当前来源哈希、同会话芯片 ID、匹配 `.sbit/.smsk` 与 Program/Verify 检查，仅做易失配置。现场RAW/BOX/AVATAR/返回RAW和KEY0后新桌面均由用户实际操作并明确确认；按下表独立绑定串口时段，不以组件测试代替观察。

## 上板与现场验收记录

合格包为`build/video/releases/video_mode_board_8274194d1c69`，sbit SHA256为`8274194d1c69d219b86a4d6230da8e4d5b4ced8922ab1ea1a3b9598627f71e43`，对应smsk SHA256为`cf8bf57d3366b28ccc56338bbeaba331d808d1d560d879b85f619bf89b88af2e`。`build/video/board_program/20261019T193232_105390Z`同一会话识别PG2L100H/0x00602899并成功Program/Verify，未写Flash，F2合格包保留可恢复。

历史自动记录`build/video/mode_board_trace/20261019T193331_403299Z`冻结了当前Program会话。自动前缀证据`build/video/mode_board_automatic_check/result.json`保存120.993秒、122包及原始字节/时间记录：RAW/preview源与DDR CRC相等，input写入/检查均307200字节、CRC稳定，scan从2615到9612、欠载0；frame_id/raw commits均1，mode_state=0x190，模式请求0/提交1。三CRC分别cf904ad2/748dffe5/fdf5d86f。

上述历史自动前缀的首帧当时尚未经用户确认，CRC不等于四角图黄金值，因而只计传输/扫描健康。随后用户准备四角图并单次KEY0重采，本次正式记录才用于关闭数值、视觉和按键验收，历史自动字段仍保留false。

正式记录为`build/video/mode_board_trace/20261020T020501_245661Z`，932个有效包中，五段观察共440包；验收器`build/video/accept_mode_board.py`与结果`build/video/mode_board_acceptance/result.json`均有哈希绑定。每段用户原话和观察内容、实际时间范围及完整UART前后文均保留。开始时的旧截图作为epoch0前置历史，不计四角图验收；四角图及三次MODE使用epoch1，桌面单次KEY0必须恰好进入最终epoch2。

| 现场阶段 | epoch | 合格包数 | 稳定秒数 | 请求/提交 |
|---|---:|---:|---:|---:|
| RAW四角图 | 1 | 136 | 135.001 | 0/1 |
| KEY1→BOX | 1 | 76 | 75.000 | 1/2 |
| KEY1→AVATAR | 1 | 37 | 36.000 | 2/3 |
| KEY1→RAW | 1 | 86 | 85.000 | 3/4 |
| KEY0桌面重采 | 2 | 105 | 104.000 | 0/1 |

前三次KEY1只改变模式请求/实际提交，frame_id/raw commits始终为1，三路CRC稳定为33bac95a/679ff89c/1f56fc1e。最终桌面KEY0后计数返回请求0/提交1，新三CRC为68777b0b/87a234ee/33018b9d；源/DDR相符、input完整读回300KiB，用户确认完整桌面且无叠加。所有合格段无硬件错误、溢出或欠载。素材就绪、模式和身份状态均满足四包健康条件，接收记录已正常关闭。任意桌面的input CRC未与独立像素参考逐字节比对，不扩展该项结论。

首次正式验收在读取原始PDS日志时发现CP936进度条字形导致严格UTF-8解码失败；原日志SHA仍为334b35090eef36c3aa4a331a868ff741713893b7c71ee96f55f17a88f89f2097。验收器仅将该读取改为与`program_board.py`相同的UTF-8/replace，仍先核对原始字节哈希并严格分类芯片ID及Program/Verify成功命令。原版RED、修复后真实GREEN、编码与缺命令/错ID/错误行负例，以及独立复核见`build/video/mode_verifier_encoding/`和`build/video/mode_verifier_encoding_review/`。生产源码、位流和所有硬件记录未变。

## 串口

仍是 37 字节 `TRV1` 包，type6/9/8/10 四包轮转，同一 896bit 冻结 core 快照。type10 的六个 uint32 为 mode_state、request_seq、committed_seq、request_count、commit_count、coalesced_count，末 uint32 是 heartbeat。

mode_state 位0..1 请求模式、2..3 实际模式、4 active_valid、5 pending、6 unavailable、7 core素材就绪、8 pixel素材就绪反馈、9控制协议错、10缓存错、11叠加错、12按键按下、13无有效上下文、14上下文错、15跨域协议错；高16位为0。健康静止 RAW/BOX/AVATAR 通常为 0x190/0x195/0x19a，按下期间另有 bit12。

`physical_mode_fullscreen_readback_verified` 同时要求四种包的最新完整健康 epoch、素材/模式/seq 一致、三路读回相符及扫描推进无欠载。这是 UART 数据资格；实际屏幕和按键仍单独记录。
