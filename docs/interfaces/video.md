# Video 接口状态

2026-10-19 显示设计修订：正式目标为 800×600 raw 全屏，功能键切换 RAW/BOX/AVATAR，
同帧只改模式不释放当前槽。F1/F2全屏已验收，F3a提供独立MODE控制/去抖组件，
F3b提供独立框/五点/单头像像素组件；F3c独立静态三模式诊断的布线、易失Program/Verify及实体KEY1/KEY0验收已通过。
独立显示MMIO、CPU三槽库及可选采集rearm组件已实现；正式CPU/fabric、叠加退休
与素材DDR接入尚待集成；下文
`preview_display` 与双窗板级条目描述现有诊断接口，不能作为新全屏能力。规格与迁移
边界见[全屏设计](../superpowers/specs/2026-10-19-fullscreen-display-design.md)。

## F3c 独立三模式板级诊断

`video_mode_board` 默认800×600 RAW；KEY1/C23低有效、两级同步与20ms去抖，循环
RAW/BOX/AVATAR；KEY0协调reset后回RAW并重装素材、重采一帧，保留HDMI初始化。
人工两框/主人脸五点和256×256 RGBA测试纹理用于观察，不接真实NPU结果。
每次reset只锁存一个不可变raw上下文；无raw重新提交/释放端口，纯MODE不改变
采集CRC/frame_id/raw commits。`video_demo_mode_output`在raw对齐SOF使用待提交
完整命令，叠加13级+pad1级退休后才反馈；加上raw输出前两级共16级寄存。

新增UART type10与6/9/8轮转，来自896bit冻结快照。六个uint32为mode_state、
request_seq、committed_seq、request_count、commit_count、coalesced_count，末字heartbeat。
mode_state位0..1请求/2..3实际模式，4有效，5待提交，6不可用，7/8 core/pixel素材就绪，
9控制错，10缓存错，11叠加错，12按下，13无上下文，14上下文错，15跨域错；高16位0。
`read_board.py`要求最近两个完整有序6/9/8/10轮次，最多再跟一轮6/9/8有序前缀；
各包可否定旧健康，不把raw-only或旧preview目标记录借作当前MODE成功。

缓存仍是一次装好后封存，未增加DDR素材DMA或运行中替换。正式多帧/raw/素材引用
与显示MMIO属于F4；诊断不替代其ABI。证据及当前物理状态见
[三模式板级记录](../verification/video/mode_board.md)。

## F4c3c 采集与显示的端到端组件

`video_pipeline`把原ABI2采集端点、允许显式REARM的三分支核、RAW-only显示端点和
唯一Video共享DDR桥连接。`c_s_axi_*`/`d_s_axi_*`是两个独立AXI4-Lite口，分别仍为
0x20012000/4KiB和0x20011000/4KiB；由未来全局fabric精确译码，不在本组件内别名。
默认core125MHz、pixel40MHz；源`src_valid/data/ready`是已同步到core、允许背压的
48bit PIX/EOF流，`arm_toggle/cancel`供未来物理ingress连接。正式成功几何固定
800×600 RGB888/stride2400，预览400×300、输入320×320 BGR NCHW（上下各40行0）。

CPU继续唯一管理全局槽与graph；组件没有自动分配或FREE接口。采集成功要求好EOF、
三分支DMA结果及全部B退休，C读取完成记录并验证身份/几何后才改变池状态；两个
采集事件ACK并确认rearm-ready后，软件显式REARM。显示实际commit/retire和软件
ACK仍是不同边界；旧release未ACK时可使用第三槽，但旧槽不能进入全局FREE。
同RAW模式不重复提交raw记录、不释放槽。BOX/AVATAR仍拒绝。

`faults[0/1/2]`依次为采集核/显示链/共享内存，错误码各自输出；两个`irq_*`仍来自
原MMIO事件端点，不向旧ABI合成fault位，也没有隐式局部reset。平台须采样独立fault
并执行协调恢复。`capture_port_drained`仅表示采集写口已排空，不能替代显示退休或
全局引用释放。`display_urgent`由外部提供，当前仿真固定1，尚无生产水位源。

本机C直接驱动实际RTL端点的联测验证功能和引用生命周期；RPC边界可暂停模拟时间，
不代表RISC-V执行或CPU延迟。详见[端到端验证](../verification/video/video_pipeline.md)。
物理HDMI不可背压连续流、CPU/NPU全局fabric、跨master可见性、素材/叠加退休与
真实NPU推理尚待集成；本批没有路由或板测。

## F4c4a 完整记录像素消费者

独立`display_record_pixels`的`cmd_valid/ready`接纳mode/slot/frame/generation/
seq及5120bit `cmd_data`。调用者须先通过冻结`display_record_guard`，本组件只
补查已知值、头部身份/几何一致性。完整payload跨域；只在`raw_sof`且实际
`raw_context_valid/slot/frame/generation`匹配时应用，同拍首输入像素使用新记录。
AVATAR还要求`asset_ready`及id/generation匹配。素材未就绪而新RAW已到时先透传，
保留旧引用至下一匹配SOF；就绪但素材key错误粘滞fault。

`avatar_req_valid/addr/asset_id/generation`保持9级请求对齐，provider按固定拍
返回`sample_valid/error/rgba`，不可背压或随意替换仍在用的版本。像素颜色、同步、
坐标、RAW身份、mode/seq与效果标记在n+13对齐退出。`commit_valid/ready`来自实际
首输出像素证明；core消费反馈后才发布保持的`retire_valid/ready`及旧身份。
`retire_raw`表示源身份变化的像素排空贡献；`retire_asset`另给旧素材id/generation。
相同素材跨新帧不退休素材；同帧AVATAR转RAW不退休RAW。退休未消费时拒绝新命令。

像素退休不表示扫描器DMA/预取/行缓存已经排空，不替代owner release或CPU全局
FREE。调用者保留全部引用版本至各自退休完成。两个域及上下游必须协调reset；
各域按已寄存/同步观察的fault禁止未证明提交，故障前证明保持。后续输入同拍故障
不撤销已经正确退出的历史首像素证明；当前输出像素错误禁止其commit。

本批只验证独立组件，未接实际raw scanner/owner、素材DDR或CPU/NPU。已有
`video_pipeline`、`video_display_scanout`仍RAW-only，原ABI/C及生产RTL不改。
组件综合core8ns setup估计-1.249ns，尚无布线时序闭合或板测，详见
[记录像素验证](../verification/video/record_pixels.md)。

## F4c4b DDR素材装载客户端

`avatar_ddr_cache`的core端`load_valid/ready`锁存32bit base/bytes/asset_id/
generation/expected_crc。默认262144B、16B对齐且完全位于0x82600000..0x827fffff；
CRC为本地描述符扩展，不改640B显示ABI。源DDR由调用者保持不可变并保证可见性。
AXI128固定ID9、size4/INCR、最多16拍和单在途，按4KiB/末尾拆分，需上游共享读
仲裁后接唯一DDR通路。缓存及固定拍pixel接口沿用`avatar_texture_cache`。

CRC32/ISO-HDLC按地址递增R/G/B/A计算，再重排cache RGBA；最后texel验证CRC后
才写，失败不公布素材就绪。`result_valid/ready`保持success/code/asset_id/
generation/checked_bytes/crc；checked_bytes计参与CRC的字节，不是写入或排空总量。
封存与版本持有直到协调reset，ACK不允许重载。最后texel写入为完成证明，随后
online丢失不撤销成功；后续意外R可另报fault/undrained而历史成功保持。

失败粘滞fault，保持已公开AR并按ARLEN排空，不以早LAST提前结束。错误RID/LAST、
未知数据或任何意外R（即使已有fault）使`port_drained=0`保持到协调reset；超时
不得假造响应或当作排空。故障码、24场景、综合及固定版本限制详见
[素材DDR验证](../verification/video/avatar_ddr.md)。本批未联接record_pixels/
RAW owner，未实现动态版本替换或全局FREE；无CPU/NPU、物理可见性或板测结论。

## F4c3b 显示MMIO至真实RAW提交/退休

独立`video_display_scanout`连接原`video_display_mmio`、owner和raw_display，能力
寄存器MODES=001，仅RAW；BOX/AVATAR由原validator拒绝。640B记录及地址/ABI不变。
link锁存一条命令和每槽frame/generation，只有匹配raw实际commit才反馈owner的
slot/frame/generation/mode/seq。raw记录握手或SUBMIT写响应不是提交事件。

同帧RAW命令不再次提交raw记录；复用display_mode_cdc，在与raw两周期输出对齐的
pixel帧边界确认，保持身份再反馈。不改变当前槽或发布release，不提供首次像素
精确时间戳。当前active引用在替换commit反馈消费后才能退休；更早非active引用
的延迟release在下一命令等待期间也可排空，避免和raw的旧事件ACK条件互等。

raw release匹配账本后携代际交owner，owner保持事件至软件release ACK；扫描器
释放、link退休、软件ACK及CPU全局FREE是不同边界。未知/错身份/无主raw事件、
raw拒绝/错误或CDC错误锁存fault并停新任务；保留已发布记录及已证明事件，协调
reset恢复，不能靠清账本丢弃引用。输出`fault/fault_code`由未来平台接收，不向旧
MMIO合成虚假故障位；irq_o仍是原MMIO事件IRQ。

默认真实几何800×600、stride2400。缩小参数仅为扫描固定ABI左上子区的测试探针。
本批native C库事务回放等真实事件，不执行CPU，不证明采集/NPU或物理DDR排序。
尚未接共享DDR/ABI2生产闭环及叠加素材退休；证据见
[显示闭环验证](../verification/video/display_scanout.md)。

## F4c3a Video局部采集写/显示读共享端口

`video_shared_ddr`同一core域接采集AW/W/B与raw显示AR/R，内部一个
`video_memory_scheduler`和一个未改动的`axi128_hmic256`。两路总计只接纳一个事务，
完整AW/AR描述符先锁存再下发；W必须等下游AW握手。写占有到上游B握手，读占有
到ARLEN+1次R握手，不以RLAST提前释放。协议范围仍由桥约束为128bit、1..16拍、
16B对齐INCR/4KiB拆分；调度器9bit计数另外验证非法256拍的DECERR排空。

普通竞争按前次方向交替。`display_urgent=1`优先读，但等待写前最多连续
`MAX_READ_BURSTS`次读grant（默认4，合法1..16）。不会抢占已接纳事务；背压、
native或master停止前进时无无条件等待上界。联测urgent固定1，未接实际行水位。

失锁、桥fault、提前/无主/未知响应、错ID/LAST、未知有效W控制/数据等锁存fault，
保留首因并阻止新grant，地址及已接纳W/B/R继续保持/按长度排空。正常SLVERR/
DECERR原样传回。调度器错误码1..11见DDR契约，wrapper桥错误置bit7。
必须与全部master及native桥协调reset；本地`port_drained`只证明调度器无事务，
不能代替显示像素退休、其他master引用或CPU全局FREE资格。

数字联测接真实ABI2与多帧核、raw_display和桥；仿真控制器模拟CPU分配，记录接纳
持有槽，实际release握手后才允许复用。未接生产C三槽库/显示MMIO退休适配，
未宣称物理跨master排序或完整连续视频。详细边界见
[共享端口验证](../verification/video/shared_video.md)。

## F4c2b 独立采集 ABI2

新端点`video_capture_mmio_v2`位于`0x20012000/4KiB`，版本`0x00020000`。
权威配置`config/video_capture_v2.json`由`gen_capture_v2.py`生成独立RTL/C定义，
旧采帧ABI1定义/行为保持。正式fabric必须先译码本窗口和显示窗口，再进入旧
Video大窗口；本批不替CPU安装fabric或决定DDR屏障语义。

沿用ABI1寄存器偏移，新增REARM=`0x30`、REQUEST_GENERATION=`0x134`、
ACCEPTED_GENERATION=`0x158`、COMPLETED_GENERATION=`0x1c0`、COMPLETED_DRAINED=
`0x1c4`；STATUS位8为REARM_READY、位9为核req_ready。generation为CPU锁存回显，
不是未协调reset后的核端旧事件甄别证明，endpoint/core/source仍必须协调reset。

SUBMIT冻结slot/非零frame/version/generation，accepted/completion复制进保持
邮箱后由软件读全记录再ACK。成功要求accepted、身份/权威地址、精确三路数量
和字节、合法峰值及真实port_drained；失败记录同样须排空。两个事件均消费且成功、
核ready、无在途事件/故障后才能显式REARM。ACK不隐式重武装，REARM不复位FIFO、
不arm视频、不分配全局槽或改变显示引用。错误仅可信协调恢复可清除。

`video_capture.h/.c`回调按窗口偏移读写，返回成功须真实总线响应已完成。失败写
可能已经执行，驱动不重试命令、不隐式释放allocation。读完整事件后再检查
sticky STATUS，清除IRQ通知不隐藏终态故障；已发布成功记录可保留但资格返回失败。
驱动validate只验证控制记录和排空资格；CPU调用frame_pool_capture_done前仍须
真实跨master DDR可见性证明。MMIO fence回调和本机C仿真不构成物理排序签核。
详见[capture_v2](../verification/video/capture_v2.md)。

## F4c2a 采集核受控重武装

`video_capture_ingress`与`video_three_branch_capture`新增`ENABLE_REARM=0`，
现有实例保持单次。新集成须在两端同时开启；源必须每次只发送一个完整PIX/EOF
序列。上一帧good EOF和数量/CRC合格、三writer结果全部退休、仲裁器空闲、
accepted和成功completion均消费后才重新开放请求；新的请求还检查无残留m_valid、
无未消费事件、所有writer就绪和无健康错误。CPU仍负责FREE槽及显示/计算引用资格。

completion_ready是核端整记录消费，调用方必须先复制统计和身份；不是旧MMIO
ABI1的ACK。`busy=0`不能代替req_ready或port_drained，核无新release/allocator。
新请求同步清理packer/scaler和每帧统计，再发描述符；上padding写完才arm。
源端健康STOPPED收到新arm后清理本地坐标/CRC并等下一帧首，重arm同拍的源帧
主动跳过；FIFO指针不复位。失败、DONE/IDLE采样到的abort/overflow/source_fault
及离线均粘滞锁止，不能因脉冲结束而复用，也不能靠新请求清错。晚到错不撤销
已发布成功记录；无新job的IDLE健康错不制造旧身份第二完成。

本批独立数字仿真和核综合不表示已接CPU/MMIO/fabric、实际显示/DDR引用退休或
跨master可见性。旧采帧ABI1和既有板级KEY0行为保持，详见
[capture_rearm](../verification/video/capture_rearm.md)。

## F4c1 CPU统一三槽

`sw/include/video_frame_pool.h`由CPU单一控制所有者使用，管理采集预留、三分支完成、
唯一graph/frame_owner、结果发布、显示在途/active/retiring及ACK后的全局复用。
算子间IDLE不释放整图锁，最后算子之后仍等后处理与工作区消费者退出；32bit软件
ticket在同图内首值任意、随后加一且禁止完整循环，实际NPU tag位宽/映射另行冻结。
完整事件快照校验后才ACK，ACK成功后才修改FREE；MODE不释放，失败发布/ACK保留引用。
recover要求四类真实协调清空证明和新generation；这些证明及跨master排序是平台
边界。没有采集rearm或新全局MMIO；旧采帧/显示ABI和板级RTL保持，详见
[frame_pool](../verification/video/frame_pool.md)。

## F4b 独立显示 ABI/MMIO

独立显示端点位于`0x20011000/4KiB`，保留采帧ABI1。公共
`config/video_display.json`同源生成RTL/C，640B记录含原图身份、结果、16框/五点及
单头像素材参数。校验期间保护shadow，合格后交F4a；实际commit/release仍来自
外部消费者。C驱动提供完整写序、平台fence回调、保持事件读取与显式ACK。
最末像素/DDR退休生产者、全局allocator、CPU/fabric译码和物理排序仍需集成；
独立数字/驱动测试不等于实际CPU或新板测。详细接口见
[display_mmio](../verification/video/display_mmio.md)。

## F4a 显示引用所有者

`display_slot_owner`新增同core域显示引用管理，不修改公共采帧ABI1或分配显示寄存器。
完整submit冻结到下游cmd，匹配实际feedback后发布active/保持commit事件；新帧只可
使用显示侧FREE槽，同帧MODE必须保持raw和完整context，mode/seq可改且不释放槽。
旧槽经完整retire证明进入WAIT_ACK，再等release事件握手才FREE；所有事件独立背压。
错误反馈首错锁存、阻止新submit，但不撤销已公开命令，已有合法反馈继续排空。

调用方负责同帧结果/素材资格和身份新鲜度，retire生产者负责DMA/bank/像素完整退休。
`slot_free`只表示显示引用清除，全局采集/NPU allocator必须另行汇总；协调reset不能
用局部复位替代。参数化context不是正式显示ABI。详细端口、错误码与测试范围见
[display_slots](../verification/video/display_slots.md)。组件仿真/综合未扩大为实际板测。

## F3c 前置资源组件

`display_mode_cdc`接F3a命令，core/pixel复位必须协调。`cmd_valid/ready`冻结mode、
slot、seq、frame_id、generation及`CONTEXT_WIDTH`数据；pixel以同名`pixel_cmd_*`
ready/valid接纳后进入`pixel_waiting_commit`。消费者须在安全帧边界应用完整记录，
再等实际显示/流水退休后单独发`pixel_commit`脉冲；该脉冲不能与首次接纳同拍。
没有等待事务时的脉冲锁存`pixel_protocol_error`，两级同步为core `protocol_error`。
只有实际commit后才产生core `commit_valid`，完整反馈保持到`commit_ready`；包括
`commit_data`在内的payload来自持续受保护的core mailbox。无槽释放接口；raw/素材
引用与帧边界责任不由这个桥替代。单域reset或取消已公开命令不在保证内。

`avatar_texture_cache`默认`TEXELS=65536`，测试可选1..65536。core端
`load_valid/ready`先保存32bit `load_asset_id/load_generation`，再通过
`s_valid/ready/rgba/last`顺序写入字0..TEXELS-1，RGBA高至低字节为R/G/B/A。全部
合法写入后`asset_ready`置1，`asset_id/asset_generation/words_written`稳定，装载
和写口封存直到协调reset；错last、未知身份/字置`load_fault`，不能继续发布。
blocked输入不解释。未装好前不允许像素访问部分RAM，RAM不靠reset清零。

pixel端ready两级同步并捕获稳定身份后发布`pixel_asset_ready`。每个
`pixel_req_valid/addr/asset_id/generation`在该边沿采样，立即在边沿后注册
`sample_valid/error/rgba`，供F3b下个边沿消费；边沿之间保持。addr为18bit字节
偏移且4B对齐，身份必须与封存素材一致。失败仍返回一个固定error槽，RGBA可未知；
非请求槽sample_valid=0。一次装载后内容不可变，因此该检查点无运行中替换或
失效端口；DDR取数、CPU上传和一般素材引用寿命留给后续所有者实现。

组件验证/来源与物理边界见[mode_resources](../verification/video/mode_resources.md)。
前置检查点仅覆盖组件；新板级组合与物理验收单列上节，不能反向扩大前置证据。

## F3b 原图坐标像素叠加组件

`display_overlay`固定800×600光栅、最多16框/每框5点、单张256×256 RGBA素材；
配合`avatar_sample_map`精确最近邻寻址，不直接读取DDR。调用方提供同一像素时钟
域已提交且稳定的记录，F3c再实现跨域/原子帧边界及raw引用寿命。此端口不是正式
显示ABI，也不把人工结果当作真实NPU结果。

- `pixel_frame_id[31:0]`、`pixel_x/y[10:0]`、`pixel_rgb[23:0]=RRGGBB`及
  `pixel_de/hs/vs/sof`每拍接纳，无ready。输出同名`out_*`在输入边沿n后的n+12边沿
  同步出现（13级寄存）。空白RGB也原样透传，DE低或坐标超出有效域不叠加。
- `mode=0/1/2`分别RAW/BOX/AVATAR，3安全透传原图；只有`result_valid`、
  `result_frame_id==pixel_frame_id`且`result_has_face`才叠加。有效无脸、错帧/失效
  结果不使用残留框/素材。上层接纳/等待/拒绝语义仍由F3a与后续记录接收器负责。
- 框为有符号16bit半开端点，`box_valid[15:0]`选lane，端点bus的`[i*16+:16]`
  对应第i框。先裁到`[0,800)×[0,600)`，再绘制内侧边框；无面积框及其点删除。
  `LINE_WIDTH`默认2、允许1..800。普通框绿、主人脸框红；主人脸由
  `primary_valid/primary_index[3:0]`选定，重叠时优先。颜色为24bit参数。
- `points_enable`独立开关；`point_valid[79:0]`和有符号16bit点坐标的lane
  `i*5+j`对应第i框第j点。点为半径`POINT_RADIUS`（默认2、允许0..31）的实心方形，
  直接裁到有效域；默认黄色且优先于框。BOX不画头像，AVATAR不画框/点。
- `avatar_enable`和有符号16bit`avatar_x0/y0/x1/y1`给出未裁剪目标矩形，允许
  最大65535跨度及跨四边覆盖。取`sx=floor((x-x0)*256/(x1-x0))`、y同理；
  地址只在目标有效覆盖处产生，不把裁剪后的左上角当作源纹理原点。
- `avatar_req_valid`及18bit`avatar_req_addr`在n+8边沿后输出，地址是4字节对齐
  的素材字节偏移，范围0..262140。供数器在n+9采样请求并注册响应；组件在n+10
  消费`sample_valid/error/rgba`。每个请求固定一个响应槽，无反压、不能滑动、重排或
  用上次响应补缺。后续DDR行预取/缓存必须满足这个截止条件，当前只用测试同步供数器验证。
- `sample_rgba[31:24/23:16/15:8/7:0]`为R/G/B/A；素材递增字节也是R、G、B、A，
  从小端DDR字读出时须明确字节拼装，不能直接把低字节当作Alpha。使用非预乘Alpha，
  `out=(a*fg+(255-a)*bg+127)//255`，0/255精确返回背景/素材。
- 缺数或error仅让对应像素返回原图；无效素材槽可有未知数据，内部明确隔离。
  `out_box/point/avatar`为最终选中路径标志（点覆盖框时box=0；alpha0的有效头像
  路径仍avatar=1）。`out_fault`与故障像素同步，`overlay_fault`在该像素退休时
  锁存至同步高有效`rst`；非请求响应忽略，后续健康素材仍可继续显示。控制有效且
  成功的素材响应须提供已定义的RGBA。该故障扫描不能当作健康叠加样本。

独立像素/故障/复位及组件综合证据见[overlay](../verification/video/overlay.md)。
F3b组件阶段未修改当时的F2镜像或公共显示寄存器；后续F3c已单独完成MODE三模式实体验收。

## F1 raw全屏组件

`raw_display`默认800×600原分辨率、raw stride2400B，双bank行缓存各2400B；起扫拍
同时发首像素，整行最后像素退休后才能归还bank。`record_valid/ready`消费新帧命令；
合法记录经CDC在安全帧边界提交，commit/release事件保持至消费。非法描述符走独立
`record_reject_valid/ready/code`，code1及`rejected_records`可观测，当前画面继续扫描。
AXI错误/超时/DDR失效/欠载为sticky扫描故障，公开事务排空；core/pixel/从端复位须
协调，不提供单独master复位后保留在途事务的保证。此组件还不接受同帧MODE更新，
不包含显示MMIO/叠加或板级接口。验证及综合范围见[raw_display](../verification/video/raw_display.md)。

依据：v0.6 第 3、8、9、11.3 节。固定800×600输入、彩条、DDR及真实HDMI raw单帧已有分别记录的物理证据。同帧raw/preview在d017092绑定的复位分离版本通过四角图和真实桌面的两次受控实体KEY0图像验收，历史黑帧/裁切失败仍保留，证据见 `docs/verification/video/shared_preview.md`。后续已实现320预处理、同帧三分支核心及独立板级诊断入口；采帧MMIO/原生CPU控制已完成数字联测，正式fabric与SoC三槽生命周期仍待集成，下述局部接口不替代共同契约。

## F3a 去抖与模式请求组件

`video_button_debounce`接收`clk/reset_n/button_async`，输出去抖状态`pressed`和
单拍`press_pulse`。参数默认125MHz、20ms、低有效，门槛为时钟和毫秒乘积除1000
向上取整；按下/释放均须两级同步后连续满足门槛。长按只触发一次；reset视为释放，
复位时按住的键重新资格满后可触发一次。未知样本清累计、不更改稳定状态。
模块没有假定板级KEY1或MODE管脚；板测接入前仍须核对原理图和实际时钟。

`display_mode_control`只在core域工作。`request_valid/ready/mode`接纳模式0/1/2，
每次合法请求增加32bit模数序号；3经`reject_valid/ready/rejected_mode`拒绝并计数，
事件背压期间不接纳新请求。独立本地控制器可将合格按键事件映射成
`requested_mode==2 ? 0 : requested_mode+1`；正式CPU所有者由F4接入。

调用方提供已验证的`context_valid/frame_id/slot/generation/data`，frame_id非零、
slot为0..2。`CONTEXT_WIDTH`默认128，只定义不透明完整上下文的数据宽度，不是
正式显示ABI；同一frame/slot/generation的数据和结果资格必须不可变，数据变化须
更换generation。调用方须持有所有原图/结果/素材引用，直到对应命令实际退休。
命令暴露后即使输入上下文、能力或就绪资格改变，原命令仍须完成；这些输入变化
只影响下一命令，不能作为取消公开valid的手段。

`capabilities[2:0]`分别表示AVATAR/BOX/RAW。缺少目标模式能力置`unavailable`；
BOX/AVATAR要求`result_valid && result_frame_id==context_frame_id`，非空AVATAR另
要求`avatar_ready`。`result_empty`表示已知有效无脸，此时AVATAR不要求素材就绪。
未就绪时置pending并保留活动记录，不借用其他帧结果。所有资格信号必须与上下文
数据对应；此组件不解析或验证raw地址、框和素材字节。

`cmd_valid/ready`公开mode/seq/frame_id/slot/generation/data，背压期间保持全部字段；
接纳后只有一个在途命令。后续请求更新最后期望值并合并尚未发出的中间请求，
已冻结命令不计合并。`commit_valid/ready`反馈同一mode/seq/frame/slot/generation，
只有匹配反馈才更新active/committed_seq，接纳命令不会提前更新活动状态。
不匹配反馈被消费，增加`protocol_errors`并置sticky `protocol_error`，仍等待正确反馈。
空闲时反馈ready为0；反馈生产者必须遵守握手，不能发送无所属命令的事件。

请求、命令接纳、实际提交、合并和拒绝各有独立32bit计数。
完成性由独立dirty和命令覆盖标记追踪，不依赖请求/提交序号相等；完整回绕后的
新请求仍须自身实际提交，新请求与旧反馈同拍时保留新请求。
请求/活动/命令/拒绝/反馈状态均由reset清除，跨域消费者须参与系统协调reset，
不能独立清除一端保留旧事务。
本组件没有DDR或槽释放端口。下游必须将raw、同帧叠加及模式在安全帧边界一起
提交，再返实际反馈；不能把cmd接纳当作帧边界或直接驱动像素mux。本批不证明
像素CDC、同槽原子更新、叠加或实体MODE切换，见[组件验证](../verification/video/mode_control.md)。

## 独立检测缩小组件

`detect_downscale`的`clk/reset_n/clear`、`s_valid/s_ready/s_rgb/s_row_last`和`m_valid/m_ready/m_rgb/m_row_last/fault`与preview scaler同类。宽高为5的倍数、5..2045，默认800×600；每个完整5×5块按各RGB通道`floor((sum+12)/25)`输出一个RGB888像素，默认160×120。帧只运行一次，下一帧需协调clear/reset。clear取消当前帧，RAM不清除，但第0行覆盖后才读累计，禁止调用方在取消时继续发送旧帧。

输入未知RGB或错误/未知row_last置sticky fault并停止消费；完整帧后继续s_valid也置fault。已有输出在故障时保持至ready，不能把fault当作撤销公开VALID的许可。运算流水预留唯一输出槽，pending期间停止输入，输出消费可与下一源像素同拍。调用方必须处理ready背压，不能将此组件直接连到不可停顿的物理HDMI引脚。

该组件不转换BGR、不量化、不补8行或C8无效通道，不发布三分支就绪。模型尺度和量化零值未冻结，不把RGB888输出称作可供NPU执行的正式输入。组件验证见[detect_scale.md](../verification/video/detect_scale.md)。

## 检测输入格式组件

后续集成目标已由用户选择适配外部NPU 4fc0fc8：固定800×600源按OpenCV4.11 UINT8双线性缩至320×240，上下各补40行，输出UINT8 BGR NCHW三平面307200B、scale=1/zero-point=0。数值参考见[yunet320_reference.md](../verification/video/yunet320_reference.md)。下面160×128/C8模块为已验收独立组件；新NCHW/DMA组件及公共配置已按下文迁移，板级input入口与CPU共享契约仍待接入，不能将两套布局混用。

`detect_bilinear`已提供有效RGB缩小组件，默认800×600→320×240；FRAME_WIDTH/HEIGHT为5..2045内5的倍数。端口与scaler同类：clk/reset_n/clear、s_valid/s_ready/s_rgb/s_row_last、m_valid/m_ready/m_rgb/m_row_last/fault。源行/列2号相位也检查未知RGB与行末；accepted错误及末输入后额外s_valid置sticky fault，blocked payload不解释。fault取消尚未公开流水，保持已公开VALID及数据至ready；clear/reset可协调取消并重新采一帧。RAM不清，top行覆盖后再读。输出仍为RGB有效图像，未包含BGR/40行补边/NCHW/DMA；验证见[detect_bilinear.md](../verification/video/detect_bilinear.md)。

`detect_nchw_dma`接收有效RGB并经既有`video_write_dma`写UINT8 BGR三平面，默认WIDTH=320、ACTIVE_HEIGHT=240、PAD_TOP/PAD_BOTTOM=40、ROW_STRIDE=320、PLANE_STRIDE=102400。req_valid/ready锁存已对齐的req_base和req_tag，完整张量的最终总线拍先验检查在逻辑DDR内；未知base/tag拒绝。输入s_rgb高/中/低字节为R/G/B，只有s_valid/s_ready时校验RGB和row_last，blocked数据不解释。一次请求只接纳固定有效高，调用方必须在后续请求前flush旧源；单行同步RAM先完整覆盖再分B/G/R读取，padding零直接生成。

每行每平面是一个DMA请求，row_last按WIDTH有效字节生成，keep为低位连续1，stride/plane间隙不写。result_valid/ready保持result_success/code/tag/written_bytes；written_bytes只累加正确ID/OKAY B确认的字节，失败burst仍可能改写内存。code0成功、1描述符、2输入流、3取消、4离线、5响应ID、6总线错误、7无主B；先记录的故障不被排空期后续错误覆盖。abort不撤销已公开AW/W，排空后返回失败；失败后sticky fault要求协调复位，不能用局部clear丢掉总线事务。成功结果消费后可重用，RAM不依赖reset清零。已发布结果保持期间发生abort/online丢失不改写结果payload，fault可禁止后续请求。

公共`video_cfg.json`及同源RTL/C已更新为320×320/307200B，输入槽A/B/C为0x82800000/0x82850000/0x828A0000，每槽320KiB。它们是统一分配定义，尚不是CPU译码/帧槽所有权验收。该组件的local result尚不检查HDMI good EOF、不汇合raw/preview，也不发布正式CAPTURE_DONE/INPUT_READY；接物理RX须经过可背压入口与三分支仲裁。验证见[nchw_dma.md](../verification/video/nchw_dma.md)。

`detect_input_pad`处理量化前图像，输入s_rgb高/中/低字节为R/G/B，输出m_bgr高/中/低字节为B/G/R。默认160×120→160×128，底部生成raw零；输出伴随row_last/frame_last/padding。宽1..2048、有效高1..2048、存储高有效高..2048，支持零补行。单帧clear/reset，row_last不匹配或未知RGB在接纳时置fault，补行/完成后额外s_valid置fault。

`detect_c8_pack`的req_valid/req_ready/req_zero锁存本帧外部模型所有者提供的量化零编码。s_q_bgr的高/中/低字节为已经量化的B/G/R；s_row_last/s_frame_last/s_padding必须匹配本帧坐标，padding三个有效通道必须等于req_zero。它不执行量化，不从raw补0推测量化零。输入字节以二补码编码原样搬运，未定义尺度、舍入或饱和。

输出m_data[7:0]为先像素B，[15:8]为G，[23:16]为R，[63:24]为5个量化零；后像素位于[127:64]。m_keep在整拍为ffff、奇数宽行尾为00ff，尾拍无效高64bit清0，不跨行拼装。m_row_last/m_frame_last同拍保持。默认行1280有效字节、共163840字节；本地done仅在末输出消费后成立，必须继续等待所有DMA写响应才能形成未来的正式三分支完成事件。

两个模块均遵守背压保持，fault不撤销已公开VALID，clear/reset是协调取消。pack的半拍、未消费输出及done均在取消时清除；请求前不接纳数据，fault/完整帧后不再接纳新帧。验证见[input_format.md](../verification/video/input_format.md)。

## 同帧三分支采集核心

`video_three_branch_capture`为新的core域单次请求组件，保留旧`video_preview_capture`板级入口。req_valid/req_ready锁存req_slot[1:0]、req_frame_id和req_preprocess_version；三路descriptor接纳后arm，首个合法PIX原子分送后accepted_valid/accepted_ready保持对应记录。slot、frame_id、preprocess_version、raw_base/preview_base/input_base锁存至协调reset，不跟随后续请求线。slot0/1/2使用同源公共定义：帧槽0x82000000/0x82200000/0x82400000各2MiB，preview偏移0x160000，input为已迁移320KiB三槽；未知字段、slot3、错误版本或非法分配先验拒绝，无arm或写入。

输入仍是48bit PIX/EOF，复用原RGB/preview/bilinear/NCHW流水。无故障PIX必须三路同时可接纳；good EOF还需与独立core raw CRC相符。completion_valid/ready保持success/code及锁存元数据，成功等待accepted消费、三路尺寸/行末和tag/bytes准确、全部成功B与good EOF。失败先锁存error/code并cancel，completion须等全部已请求writer及仲裁口排空。`port_drained`表示live端口，不能从error/busy或历史成功记录推断当前总线可复用；published事件不因后续错误撤销。5秒采集超时不覆盖已完成写入后等待accepted消费的时间，也不允许撤销已公开AXI。一次任务后必须协调reset源FIFO和所有流水/端口，不是三槽allocator或完整CPU MMIO实现。

`axi_write_arbiter3`将三路AXI写主按AW至B为所有权单元round-robin仲裁；owner注册后才公开AW，早B不释放owner，B仅在合法phase路由。无主B消费并报错，响应ID/RESP严格四态检查。sticky fault不能阻止待选已公开AW继续获得仲裁并排空。DMA使用注册error取消以消除READY/错误校验组合反馈；故障检测沿既有合法缓冲字仍可进入DMA，故障帧必须丢弃。

core错误码：01离线、09仲裁/响应、06 writer结果/端口、0c取消、02 overflow、03源、04 PIX、05 EOF/CRC、0a缩小输出/尺寸、07采集超时、08非法请求，保留首因。accepted在入口选中帧的首像素经流水到core时发布，不新增物理SOF时间戳。独立数值/控制、完整三路AXI字节内存、综合和未实现范围见[three_capture.md](../verification/video/three_capture.md)。

板级集成补充：三路descriptor均接纳后还须等NCHW顶部补零完成、可接收有效像素才arm，避免最早到达帧在补零期间填满入口FIFO。`video_three_engine`固定slot A/frame_id1/version1，消费accepted/completion后依次读回raw、preview、input，最后提交双窗显示。raw/preview匹配采集CRC，input报告实际有效字节CRC；后者不等于任意桌面的独立数值证明。reader新增默认开启的`CHECK_EXPECTED_CRC`参数；关闭时仍保留所有描述符/四态/响应/超时/排空检查。engine输出`port_drained`仅是capture写口状态，读回和显示可仍占用native口。

独立`video_three_board`目标保持既有时钟/复位及CDC约束；UART type8追加frame_id/version/input_pixels/input_written_bytes/input_checked_bytes/input_ddr_crc/heartbeat七个小端uint32。三类包共用健康后缀，晚到type8错误也撤销旧preview资格。实时板级PASS与历史capture完成分开；CPU MMIO、共享fabric及三槽生命周期仍未实现。详细范围见[three_board.md](../verification/video/three_board.md)。

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

### 采帧控制端点 ABI1

`video_capture_mmio`提供同core域的32bit AXI4-Lite端点，基址`0x20010000`、
版本`0x00010000`。寄存器唯一来源为`config/video_regs.json`，经
`scripts/video/gen_regs.py`生成`video_regs.vh`及`sw/include/video_regs.h`。
版本、能力和全部偏移受兼容性指纹保护；同版本不能悄悄移动字段。完整位表见
[端点设计](../superpowers/specs/2026-10-19-video-capture-mmio-design.md)。

该端点已定义独立AW/W缓存、B/R背压保持、AR握手时快照、WSTRB合并及W1C。
未映射/未对齐/越界地址返回DECERR；RO写、非法字段或忙时修改返回SLVERR。
读写同拍观察旧寄存器值。不支持的DISPLAY_SUBMIT和计数器不伪造成功响应。
SoC须负责32bit CPU总线适配、访问属性及AXI-Lite CDC；本端点不隐含跨域同步。

软件写CONTROL.enable、REQUEST_SLOT/FRAME_ID/VERSION后，全字写CAPTURE_REQUEST=1。
请求锁存后保持VALID/身份至capture_req_ready；此后shadow、CONTROL和第二次提交
锁定至协调复位，不提供局部reset或重采命令。每个slot的raw/preview/input地址由
既有video_cfg同源定义计算，软件不能在请求中另写任意DDR指针。软件自行保证槽可写。

accepted与completion分别进入单项事件邮箱。IRQ_PENDING位0/1/2为accepted、
completion、fault；IRQ_MASK只屏蔽中断线，不丢事件。W1C位0/1消费邮箱valid，
记录内容仍保留，新事件优先于同拍ACK。帧号摘要在0x28/2c，完整记录的frame_id
别名在0x144/184；全部数据跨多次读保持一致。合法失败可以发生在首像素之前；
成功必须已有同身份accepted（或与其同拍）。未知/过期/重复/错身份事件置E1，
错误首因保持，置capture_abort_o，已公开事务仍由采集核排空。

历史完成记录和实时健康分开：晚到live fault不会篡改完成数据，但STATUS.sticky_fault
保持并撤销实时健康。ACK不清错误、不解除abort、不释放槽。当前CAPABILITIES=7
仅声明采集端点、保持事件和IRQ；不声明显示、allocator、连续采集或共享可见性。
此批的完成邮箱来自既有三分支good EOF/全B结果，正式SoC INPUT_READY仍须接入
统一fabric/所有权协议后联合验收。accepted时间仍为首个合法core PIX，非新SOF时间戳。

端点、采集核、入口及在途DMA必须协调复位。CPU统一三槽状态、跨master写后读可见性、
Cache/fence、显示提交及释放ACK均不由这个邮箱替代。组件/联测/综合证据见
[capture_mmio.md](../verification/video/capture_mmio.md)。

### 原生CPU控制适配边界

`rtl/soc/cpu_native_axil.v`将CPU的32bit原生数据请求、4bit字节掩码和11bit tag接到
Video窗口AXI4-Lite，保持一个未完成事务。同钟接入；全11位tag锁存并在单次注册ACK
原样返回，AXI响应错误转换成同拍注册的CPU error。AW/W分别保持到接纳，全部写
地址/数据接纳后才接收B；AR接纳后才接收R。AXI背压不会撤销已公开VALID或重发写。

CPU LSU已将byte/half访问对齐并放置数据/掩码，适配器直接保留，不再次移位。
窗口外、非字对齐、可缓存、混合读写和维护请求在本地错误完成，不触发Video寄存器。
此适配器只处理选中Video端点的请求；正式fabric还须路由ROM/SRAM/DDR及全局维护。
不将拒绝Video缓存维护解释为完整CPU系统不支持FENCE或维护操作。

实际CPU固件数字联测使用冻结提交、测试ROM/SRAM和单源直连IRQ；不是正式PLIC、
共享DDR或板级SoC。源对象前提、实际执行和接口边界见
[CPU控制联测](../verification/video/cpu_video_control.md)。本端点的协调复位和单帧
限制不变，ACK不释放槽，不构成跨master写后读或正式INPUT_READY保证。

固定CPU的普通取数立即数0x144会进入其旧CSR挂起缓冲；诊断ISR采用W1C读回、
分隔的两次MIP清位并检查最终0的明确序列。CPU侧CSR读使能资格仍须在正式SoC
接入前处理；不能把本次单源中断联测当作完整CPU CSR/PLIC正确性签核。

单平面组件 `rgb888_packer` 与 `video_write_dma` 以core域ready/valid流连接，物理HDMI的不可背压像素由既有FIFO/CDC和帧接纳器接入。内存递增地址按R、G、B保存，`WDATA[8*k+:8]` 对应字节地址 `AWADDR+k`，不能直接把 `24'hRRGGBB` 低字节优先解释为同一格式。

packer默认 `ALLOW_SIMULTANEOUS_TRANSFER=1` 保留同拍出入；共享预览的两个实例选择0，使输入和输出传输互斥，输入字节只按注册count定位，避免下游READY经占用更新参与输入字节位置选择。容量仍为18字节，17/18字节行尾分为完整拍及1/2字节尾拍。固定800/400像素行在无下游停顿时需950/475个core周期，125MHz下理论峰值约105.263Mpixel/s；这是组件上限，实际FIFO水位和端到端表现由板测另验。

DMA 请求锁存 `req_base/req_row_bytes/req_stride/req_rows/req_tag`，base 和 stride 为16 B对齐，stride≥row_bytes>0；整个有效区和最后总线拍必须在逻辑 DDR 窗口内。stream 为 `s_data[127:0]/s_keep[15:0]/s_row_last`，keep 为全有效或行末连续低位1，row_last 与行字节数严格匹配。每次 AW 前完整缓存 burst，按行、16拍和4 KiB拆分；stride padding 不写。

`result_valid/result_ready/result_success/result_code/result_tag/written_bytes` 是**单平面写结果**，保持至消费；written_bytes 只计正确 BID/OKAY B 覆盖的有效字节，错误 burst 仍可能部分改写内存。它不表示完整 HDMI 帧几何合格，也不等于 `CAPTURE_DONE/INPUT_READY`。abort 丢弃未公开数据，已公开的 AW/W/B 必须排空；上游须 flush 旧 packer/stream 后再发新请求。wrong BID/无主 B/初始化丢失等端口故障须协调复位。

新增真实源入口 `video_capture_ingress` 和独立诊断引擎 `video_capture_engine`：core先接纳单次descriptor再翻转arm；像素域等待合法帧首，PIX/EOF经48bit Gray指针FIFO跨域。EOF同时携带good、源CRC和保守RAM水位；源坏帧、overflow和cancel保持至协调reset，不能从下一帧补旧帧。默认FIFO RAM2048字，另有一个读输出寄存器；无条件持续供数或任意native停顿下无溢出不在保证内。

引擎分别保持good EOF和成功DMA结果，两者齐备才读DDR，按递增有效字节地址逐字节计算CRC32/ISO-HDLC。480000像素、1440000字节、tag1、计数/行末和CRC完整一致才置本地raw诊断done；读AR/R和写AW/W/B故障后按advertised长度排空。`busy=0`在故障后只表示诊断任务停止推进，不能作为端口已经排空或可复用的凭证；本阶段必须协调reset才重采。

联合目标 `video_hdmi_capture` 的type5 UART报告原始源单帧数据一致性，本地输出仍是独立彩条。物理结果和CRC碰撞边界见 `docs/verification/video/hdmi_raw_capture.md`；该本地done不具有SoC三分支CAPTURE_DONE或CPU槽所有权语义。

保留规格的控制基址 `0x2001_0000` 与寄存器区间；本批ABI1生成采帧端点子集的
`video_regs.h`，包含详细位定义、复位值、W1C和忙时规则。显示/性能部分尚未发布，
不能把这个子集头文件当作完整SoC Video寄存器已实现。

- CAPTURE_REQUEST：保存请求；在下一合法完整输入帧边界发布带 slot/frame_id 的 CAPTURE_ACCEPTED。
- CAPTURE_DONE/INPUT_READY：同一逻辑事件，raw、preview、input 三分支及对应写响应完成，尺寸检查通过后发布。
- DISPLAY_SUBMIT：接纳完整影子记录；接纳与实际提交是不同事件，不直接修改活动寄存器。
- DISPLAY_COMMIT：正式全屏设计在安全输出帧边界原子切换 raw、模式、同帧框/头像/状态及 frame_id；F1/F2诊断已提交raw，F3c在单帧上另提交MODE；正式整记录仍待F4。
- MODE_REQUEST/MODE_COMMIT：独立记录请求/实际模式及序号；同帧模式更新不触发重新采帧/推理，不增加有效输出帧数，不产生当前槽释放。
- DISPLAY_RELEASE_ACK：旧槽所有 DMA、预取与像素缓存引用结束后确认，不能等同于 DISPLAY_COMMIT。
- 地址、slot、frame_id、预处理版本必须校验；状态/事件保留到软件消费，旧事件不能推进新任务。
- CPU 统一维护槽状态与 graph_active/frame_owner；Video 只管理自己持有的引用和握手。共享 DMA 数据不可缓存。

详细记录打包、序号回绕/复位代际、超时、屏障与中断规则在 V020 前完成 CPU–Video 联调，不以本文件存在代替接口已冻结。
