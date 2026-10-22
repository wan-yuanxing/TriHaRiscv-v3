# Video 工作台账

更新：2026-10-21。分支：`video/windows-bringup`。用户已确认板卡、HDMI 源和显示器已就绪；当前开发在主工程内执行，未建立第二份源码副本。

## 全屏显示设计变更

2026-10-19 用户确认正式输出采用 800×600 raw 原分辨率全屏，独立 MODE 功能键
循环 RAW/BOX/AVATAR，在安全输出帧边界生效；KEY0 保留协调复位/重采。新设计
及主规格已修订，既有双窗 RTL、公共 preview 配置和已验收双窗位流继续作为诊断基线。
已完成F1 raw扫描组件及F2独立全屏板级目标，最终内部布线时序和实体板级验收通过，
F3a控制/F3b叠加及F3c独立静态板级接入进度见下文，设计见
[全屏显示设计](../superpowers/specs/2026-10-19-fullscreen-display-design.md)。

F1已实现原分辨率行扫描、完整首像素、CDC/提交/释放及独立非致命描述符拒绝；
46项组件场景纳入完整回归，独立11检查/5变异/3来源篡改拒绝通过。组件综合
1332LUT/1614寄存器/4DRM36K/4APM，core8ns估计setup+3.094ns，无布线或新板测。
实际证据及边界见[raw_display](../verification/video/raw_display.md)。

最终完整回归35套件/184输入、285份仿真PASS日志，Python79通过/1项Windows
符号链接权限跳过。父核验192项源码/8项引用及614份日志哈希；本地交付限定12文件，
31项其他路线文件保持原样，机器证据见[raw_display.json](../verification/video/evidence/raw_display.json)。

F2目标`video_raw_board`已接raw原图并保留三分支读回，type9区别旧双窗显示。
27个引擎场景、6个板级数字场景及6项串口包测试通过；板级逐像素检查270光栅/
27000像素，含KEY0模拟复位后不同源图。独立审查关闭两项UART epoch误判，
无剩余实质问题。综合网表139管脚/68同步链及全部显示束路径结构审计通过，
ed8a779完整回归基线36套件/190输入/311份仿真PASS日志、Python85通过/1权限跳过。
两轮12个布局均未达内部时序，最接近路径为DMA burst→桥AW接纳；新增49bit AW
保持寄存后，当前受影响套件28份仿真日志及独立14场景通过。其余187项完整基线
输入哈希一致、run.py仅改用例数；不冒称修订后完整重跑。父核验53来源/725日志
哈希及35项保留文件。第三轮仅raw_engine一项构建RTL变化、保持8ns/6ns约束，
最终slow setup/hold为+0.112/+0.026ns，fast为+2.966/+0.020ns；15组专项CDC报告
及全部端点核验通过。镜像0cd4a546804b已易失Program/Verify，串口三路读回及
raw扫描合格、欠载0。首轮源图不符后重新Program/Verify，三路CRC均匹配四角黄金值，
用户确认单幅全屏四角/边框完整，单次实体KEY0后仍完整且三路CRC匹配黄金值。
普通桌面换源后再次单次KEY0，用户确认完整全屏桌面恢复。最终三段验收epoch
共495包，连续健康288.002/121.001/77.000秒，均无溢出或欠载；UART已正常停止，
板卡保持全屏桌面镜像。F2独立静态单帧板级验收完成，外部HDMI AC仍未签核。
见[板级记录](../verification/video/raw_board.md)。

F3a当前24场景已通过，20ms去抖与模式控制已分别综合为30LUT/26FF、317LUT/658FF，
8ns估计setup+5.131/+4.080ns，均0DRM/APM。独立审查发现并关闭32bit回绕完成性
误判，独立dirty/覆盖状态和case14/15/16验证通过；当前完整回归37套件/198输入/337份仿真PASS日志通过，
Python85通过/1权限跳过。修复后独立77检查及针对性突变通过，11项审查来源/529项
审查产物与40项保留文件核对一致。本批F3a控制组件验收完成；
F3a阶段板卡仍为F2静态全屏，当时尚不能通过MODE键切换。见[控制组件验证](../verification/video/mode_control.md)。

F3b已完成独立最多16框/可选五点与单张256×256 RGBA像素组件，9级精确最近邻
寻址和13级像素/身份/同步/标志对齐，素材错误逐像素退回原图并锁存fault。最终
12场景独立核验858756个退休像素、621263请求，含全480000有效像素与全65536
纹理地址；raw46场景、mode24场景及Python85通过/1权限跳过。独立审查发现无效
RGBA未知污染，foreground隔离后父RED/GREEN及5319像素/3679请求复核通过，
8项突变全部被检测，当前无未解决实质问题。最终综合10637LUT/1645FF/0DRM/6APM，
25ns及同钟边界约束下估计setup+15.961ns；hold估计-2.470ns，尚无布线闭合。
93项既有dirty/冻结来源保持，F3a完整37套件198输入中196项字节相同，两项runner
只新增组件入口；本批仅重跑三个受影响套件，不冒称完整all。F3b阶段板卡仍为F2镜像，
素材DDR缓存、像素CDC/原子提交及MODE实体接线尚未接入。见[像素验证](../verification/video/overlay.md)。

F3c前置已实现模式单事务CDC及单bank RGBA封存缓存：pixel接纳与实际提交分开，
core反馈保持至消费；素材65536字全部写入后才可见，封存后不改写直到协调reset。
16个组件场景及overlay12/mode24重跑通过，Python85通过/1权限跳过。CDC综合
9LUT/470FF/0DRM，缓存98LUT/186FF/64DRM，两者0APM；仍无物理布线。
官方手册与例程已交叉确认KEY1=C23、低有效，后续作为MODE。见[资源组件验证](../verification/video/mode_resources.md)。

F3c独立 `video_mode_board` 静态全屏三模式板级验收已完成：默认RAW，KEY1/C23循环RAW→BOX→AVATAR→RAW，KEY0回RAW并重装素材、重校准、重采。用户逐项确认四角/边框、人工框/五点、测试贴图及撤除叠加后的完整原图，最后普通桌面单次KEY0恢复完整全屏。框、点和纹理仍为人工诊断输入，不是真实NPU结果。

实际镜像`8274194d1c69`已Program/Verify；原core8ns、pixel25ns及跨域约束下，slow/fast setup为+0.334/+2.627ns，hold为+0.135/+0.101ns，recovery/removal亦通过。17252LUT/18747FF/73.5DRM/16APM，140管脚、64素材RAM、77同步链、13束结构审计及18份报告/50项端点检查全部通过；7次旧失败构建保留。

正式现场记录`build/video/mode_board_trace/20261020T020501_245661Z`共932包，5段合格观察共440包，稳定时长依次135.001/75.0/36.0/85.0/104.0秒，均无错误/溢出/欠载。四角图raw/preview/input CRC精确匹配33bac95a/679ff89c/1f56fc1e；三次KEY1保持帧ID、raw提交及三CRC不变，模式请求0/1/2/3、提交1/2/3/4准确推进。最终KEY0进入下一epoch，模式计数复位，桌面新CRC 68777b0b与DDR一致，用户确认无黑屏、窄条或裁切。串口已正常关闭，板卡保留完整桌面RAW。

公共CRC/writer、[capture错误流水](../superpowers/plans/2026-10-20-mode-capture-pipeline.md)及[桥缓存使能](../superpowers/plans/2026-10-20-mode-bridge-cache.md)分别有等价/边界测试与独立审查。合并证据时发现PDS进度条为本地编码，验收器读取按现有下载脚本容错，仅修改忽略目录中的读取方式，原始Program日志、位流、trace字节和哈希保持。正式验收器及父审计绑定当前Program、源码、50项物理检查和五条明确人工确认；详见[板级记录](../verification/video/mode_board.md)及[机器证据](../verification/video/evidence/mode_board.json)。

本阶段为固定800×600静态单帧诊断；正式显示MMIO/整记录、通用多帧所有者/槽释放、共享DDR、素材DDR DMA、连续视频和真实NPU集成仍未实现，外部HDMI AC不在本次签核内。

后续F4通用显示记录/多帧所有者、共享DDR及F5真实NPU集成仍待推进。当前 raw/preview/input 三分支及
320×320 BGR NCHW 保留；24fps采集、固定扫描率下基础读写约137.43MB/s，NPU/
头像/协议另计。早期检测原始输出64KiB/槽草案不足以容纳320输入的16bit完整输出，
须由NPU/CPU交接时重新冻结；本批未改模型或公共地址配置。

F4a新增独立`display_slot_owner`显示引用组件：完整记录接纳后保留槽，匹配实际commit才更新active；同帧MODE只改mode/seq，不释放槽。旧槽必须等待下游全部引用退休证明及上层release ACK才FREE，事件背压不覆盖身份。13个定向/7与513bit压力场景、五个关键错误变异和既有MODE24场景通过；Python101通过/1权限跳过。独立42组/304916断言、9个有效变异及最终13场景复跑通过，无未关闭发现；综合网表无环/多驱动/锁存器，四条常量探测警告保留说明。PDS组件综合478LUT/963FF/0DRM/APM，core8ns寄存器路径估计setup+2.369ns、hold+0.671ns，未布线或上板。详见[显示槽记录](../verification/video/display_slots.md)。显示侧FREE不代表全局采集/NPU引用清除，正式显示ABI/MMIO、全局三槽、共享DDR及退休证明生产者继续由F4后续批次实现。

F4b新增独立显示ABI/AXI-Lite和C驱动：0x20011000/4KiB子窗口，640B同源记录，保留采帧ABI1；整记录校验/冻结后交F4a，commit与release ACK分离。10场景含16框/五点、同帧三模式、素材pending、错误访问及真实C的163写事务回放通过；驱动原生执行、RV32I对象编译通过，未执行RISC-V CPU。旧F4a13场景、采帧MMIO两组及Python105通过/1权限跳过，五个关键变异均被断言检出。

完整context比较在首轮综合形成长进位链，8ns下估计setup -51.451ns；仅等价拆成32bit组并保留边界，44组/43个对外信号逐周期对照及独立190522组四态检查通过。最终10853LUT/16038FF/0DRM/APM/0锁存器，8ns寄存器路径综合估计setup +1.591ns、hold +0.671ns；未布线或新板测。56项其他冻结来源保持字节一致，owner为唯一有前后hash和等价证据的例外。详细证据见[显示控制记录](../verification/video/display_mmio.md)。CPU/fabric、实际像素提交/DDR退休、统一三槽分配及跨master可见性继续由F4c推进。交付前修正新显示JSON的CRLF/仓库LF检出差异，先失败断言、再仅规范新配置并重生成头；定义不变，受影响验证和综合重新运行，旧采帧ABI字节保持。独立1595组校验/7个MMIO场景、441次回调失败/256组ACK和7变异均通过，无未关闭发现；57条审查命令、114项审查产物及244项冻结文件由交付审计核对。owner组合图无环/多驱动的结论仅限该模块；综合警告和未完成集成边界保留。25文件小范围本地交付，31项其他路线文件保持原字节，见[机器证据](../verification/video/evidence/display_mmio.json)。

F4c1新增CPU单一所有者三槽C库，串起CAPTURING/READY/PROCESSING/READY_DISPLAY/
DISPLAY_PENDING/DISPLAYING/RETIRING；整图锁保留到结果发布和工作区退出，MODE不
释放、实际事件ACK成功才FREE，错误/未知完成不推进新帧，失败I/O保守保留引用。
同图软件ticket顺序和issued耗尽规则关闭旧tag重复完成风险；实际NPU tag映射未冻结。
11个原生场景、180次I/O失败、1000帧延迟退休及81读/1149写/6命令/2退休/1拒绝的
实际显示RTL回放通过，11个策略变异由指定断言检出。旧MMIO/owner/采帧回归及Python
105通过/1权限跳过。RV32I仅交叉编译，未执行CPU；旧RTL/ABI/PDS输入不改，没有新
综合、布线或板测。独立8组/65153检查、183个MODE失败点/3类不确定写及70读/985写的第二条实际RTL
回放均通过，标签重用修复独立复核，无未关闭发现。243项旧冻结来源及31项其他路线
文件保持字节；详见[机器证据](../verification/video/evidence/frame_pool.json)。
详细边界见[三槽记录](../verification/video/frame_pool.md)；F4c2
继续采集rearm、共享CPU/fabric/DDR和真实退休生产者，多主可见性及连续采集另验。

F4c2a增加默认关闭的`ENABLE_REARM`：成功记录消费、三路写响应退休且入口空闲后，
允许新CPU槽请求清理预处理并再arm；FIFO指针、DMA/DDR/显示不靠局部reset重启。
所有失败仍锁止。独立审查复现并关闭DONE/IDLE短暂健康脉冲消失后误复用，修复
仅作用于开启多帧的实例，保留已发布成功记录且不制造旧身份的第二完成。
20个新场景覆盖109个完整成功帧、6类失败排空及DONE/IDLE晚到脉冲；包括三帧
800×600逐字节raw/preview/BGR NCHW校验、三槽循环、异步时钟、记录/最终B背压。
7个关键变异被指定断言检出，旧默认three_capture/ingress/MMIO/frame_pool及Python
105通过/1权限跳过。开启实例核综合4273LUT/2876FF/1.5DRM/2APM/0锁存器，
8ns寄存器路径估计setup+1.578ns、hold+0.428ns；无布线或新板测。入口双时钟
本批仅数字仿真，组件综合不包含实际HDMI/DDR或新增物理CDC验收。399个其他已跟踪
文件及31项其他路线现状（含两项原有删除）保持；详见[重武装验证](../verification/video/capture_rearm.md)。
本批是F4c2a采集组件，不是连续视频交付；采集MMIO ABI1仍单次，CPU/fabric/共享DDR
可见性、真实显示退休生产者及NPU执行仍需后续集成。
F4c2b增加独立采集ABI2：`0x20012000/4KiB`、CPU generation回显、保持事件和显式
REARM；成功/排空、软件双事件ACK与核ready全部满足才可复用。旧ABI1、F4c2a入口/
采集核和板级默认字节保留，CPU全局槽和物理可见性责任不转移给新端点。
12份组件仿真通过：8个控制场景、三种几何共21帧/60039字节真实三路写入及139读/
30写/4次事件/13个fence标记的实际C驱动RTL回放。驱动224检查、50个回调失败点和
4个已执行后返回失败的写检查通过，RV32I对象无未定义符号；没有执行RISC-V CPU。
独立审查关闭故障IRQ被清除后驱动漏报sticky STATUS的问题；历史成功记录保留，
但资格检查正确返回失败。10项关键变异均被指定断言检出；旧MMIO/三槽回归及Python
109通过/1权限跳过。端点综合816LUT/982FF/0DRM/APM/0锁存器，8ns寄存器路径估计
setup+2.708ns、hold+0.701ns；无布线或板测。构建首轮遗漏新增include的失败已保留，
补齐隔离构建输入后重跑通过。409项其他已跟踪文件和31项其他路线现状保持，见
[ABI2验证](../verification/video/capture_v2.md)。正式fabric须优先译码新子窗口；
共享DDR仲裁/跨master可见性、CPU执行和真实像素退休仍待后续，未完成连续视频验收。

## F4c3a Video局部共享DDR

新增`video_memory_scheduler`和`video_shared_ddr`，让采集写与raw显示读共用唯一的
既有AXI/native桥。普通竞争交替服务，急迫显示读采用默认4次、可设1..16次的配额，
随后服务等待写。地址接纳后锁存，写占有到B握手，读按ARLEN+1拍退休；故障阻止
新请求，已公开事务继续保持并排空。旧桥、ABI1/2及采集/显示核字节保持。

19个协议场景及5组真实采集/显示数字联测通过，共33帧/96237有效字节/39900显示像素，欠载0。覆盖三槽轮换、三路数据/CRC、逐像素、
提交/释放背压和并行读写。故障测试重新提出请求，验证真正锁止；9项关键变异
被指定断言检出。共享端口、旧桥/raw显示/ABI2及Python回归结果以
[本批验证](../verification/video/shared_video.md)和[机器证据](../verification/video/evidence/shared_video.json)为准。

wrapper综合3806LUT/3561FF/0DRM/APM/0锁存器，8ns估计setup+1.993ns、hold+0.730ns。
没有本批布线或板测。联测控制器模拟CPU槽引用，实际raw_display的commit/release
控制复用；尚未接生产C三槽库与显示MMIO退休适配器。urgent在联测固定为1，
真实水位生产者未实现；服务界限以对端持续前进条件下的事务数计，不是无条件周期
或显示deadline。仅验证所列缩小几何/时钟/native模型，未验证800×600并行带宽。

下一批推进显示MMIO/所有者与raw扫描器的实际提交、释放适配及CPU三槽库事务回放；
可先独立仿真，不必等待CPU核。正式CPU/NPU共享fabric、跨master物理可见性、素材
DDR读取和连续视频仍待集成，CPU仍是全局帧与graph所有者。

## F4c3b 显示MMIO与真实RAW扫描闭环

新增`display_scanout_link`和`video_display_scanout`独立RAW-only目标，保持既有显示
ABI/owner/raw/CDC及C三槽库字节。接纳命令不制造commit；匹配真实raw commit后
反馈原slot/frame/generation/seq。raw真实释放经逐槽代际账本交owner，owner继续
保持release至软件ACK；link退休握手不代替CPU全局FREE。同帧RAW命令经CDC在
对齐帧边界完成，不再提交raw记录，不释放槽。BOX/AVATAR能力未接入且明确拒绝。

新suite含11项协议和6项真实wrapper联测/实际C事务回放。完整800×600检查实际
换帧/旧引用释放，缩小探针仍使用固定800×600/2400 ABI；覆盖长ACK、第三槽提交、
同RAW模式、代际重用、错误保留及像素/同步。C库本机执行，真实R/W/F以等待事件
标记驱动RTL，不注入commit/retire。模型采集/NPU结果仅为C所有权前提，不冒称
RISC-V执行或真实推理。计数、独立审查及证据见
[闭环验证](../verification/video/display_scanout.md)。

修复旧release延迟至下一命令OFFER/WAIT_RAW时的互等：匹配非active旧引用继续
排空，当前active引用仍等待替换反馈。9项关键变异被断言检出。综合12174LUT/
18123FF/4DRM/4APM/0锁存器，core8ns估计setup+0.373ns，pixel25ns估计+19.809ns，
最小hold估计+0.619ns；14项约束均适用，无error/critical。仅组件综合，无本批
布线/板测或端口I/O预算；独立fault输出仍须由平台接收，不改变MMIO故障ABI。

下一步把本RAW闭环与ABI2采集、共享DDR及CPU三槽控制联测组合，再接BOX/AVATAR
整记录和真实NPU结果。全局fabric、跨master物理可见性、不可背压HDMI连续流及
800×600采显并发带宽仍待验收，CPU继续统一全局帧和graph状态。

## F4c3c 采集/共享DDR/显示端到端联测

2026-10-21新增`video_pipeline`独立组件，显式连接原ABI2采集、可REARM三分支核、
唯一共享DDR端口及RAW-only显示MMIO；两个独立AXI-Lite口、core域可背压PIX/EOF，
CPU继续全局帧/graph所有权。原RTL/ABI/生产C库保持字节，独立fault/IRQ留给平台。

原生C通过真实RTL响应控制四帧槽0/1/2/0轮转：第二次显示事件未ACK期间采第三槽，
真实软件ACK完成后才复用slot0。同RAW模式不重发raw或释放槽；坏EOF/单bit存储
损坏均产生真实失败，C保留引用并拒绝REARM/新分配。正常三路8428800写字节、
2400000像素/5完整光栅、欠载0，实际并行争用42拍；native C共2216检查通过。
每地址唯一写与精确分支总量检查含全零padding，完整光栅同步/blanking独立核对。

受影响旧capture_v2/display_scanout/shared_video/frame_pool共54份仿真PASS，
Python109通过/1权限跳过。独立审查关闭重复地址覆盖盲点和第三帧BUSY测试预期，
三项身份/字节/ACK前状态变异被检出；没有为测试改变生产协议。组件综合20318LUT/
25158FF/5.5DRM/6APM/0latch，core8ns setup估计+0.311ns、pixel25ns+19.809ns，
minhold+0.619ns；14约束适用、94项组件I/O预算未指定警告，无本批布线/板测。

详见[端到端验证](../verification/video/video_pipeline.md)。本机C不是RISC-V执行，
空检测结果为测试前提；RPC可暂停时间，不作CPU延迟或物理吞吐承诺。下一步接
BOX/AVATAR整记录与素材退休；正式CPU/NPU fabric、物理可见性、不可背压连续HDMI
及实际NPU仍待联合验收。451保护文件/31其他路线现状保持，限定17文件本地交付。

## F4c4a 完整记录与叠加像素退休

2026-10-21新增独立`display_record_pixels`，完整640B记录经冻结CDC原子传递，
在实际RAW slot/frame/generation匹配的SOF应用16框/80点/primary及素材矩形。
素材身份随9级寻址流水传递；n输入像素在n+13退出后才证明commit，core消费
反馈后发布保持的旧像素退休贡献。同素材跨新帧持续持有，同帧转RAW只退休素材。
CPU仍是全局帧/graph所有者；此贡献不能代替扫描器排空、owner release和全局FREE。
现有`video_pipeline`保持RAW-only，正式BOX/AVATAR闭环尚未接入。

16场景覆盖完整800×600数值oracle、异钟比/无blanking、全部框点/稀疏mask、
素材/源代际等待、故障/复位及反馈/退休背压。旧四套件55份仿真日志通过，Python
109通过/1权限跳过。八项隔离变异检出；独立审查修复新RAW先于素材时误报错、
core fault后pending仍可提交，并补齐禁用点/primary测试盲区。

组件综合13267LUT/15475FF/0DRM/6APM/0latch；core8ns setup估计-1.249ns、
pixel25ns+12.426ns，边界hold-2.470ns、reset最小-0.037ns，未满足125MHz时序。
13约束适用，74项物理I/O未指定警告；5076组件接口位不能用作板级top。未布线
或上板，不能把综合完成视为时序闭合。详见[验证记录](../verification/video/record_pixels.md)。

下一步接素材DDR装载/版本持有与真实RAW身份，再联合像素退休、扫描器和owner。
462保护文件/42其他路线路径保留，旧RTL/ABI/C字节不变；交付16文件，其他路线
STATUS追加保持未暂存，本地提交，无COM/JTAG/Flash操作。

## F4c4b DDR素材装载与封存版本

2026-10-21新增`avatar_ddr_cache`，作为AXI128读客户端装载256×256 RGBA素材。
16B拍、最多16拍/单在途、4KiB拆分；逐字节CRC通过后才写最后texel并封存原cache。
身份保持到协调reset，结果ACK不能覆盖素材；没有第二份cache或动态替换分配器。
不改旧RTL/显示ABI/C，不接第二物理DDR端口，也未使现有RAW系统支持BOX/AVATAR。

24场景全部通过，完整262144B/16384拍/1025burst、65536词逐一读回；9项变异
检出，原mode_resources16份仿真PASS，Python109通过/1权限跳过。提前R、封存后
online边界及已有fault后stray排空可信性三项问题均有RED/GREEN并修复。历史完成
事件保持，后来端口故障不能伪造排空或撤销已完成素材。

组件综合509LUT/628FF/64DRM/0APM/latch，core8ns setup估计+2.614ns、pixel25ns
+21.793ns、minhold+0.619ns；4约束适用，48项I/O预算未指定警告。仅内部估计，
无布线/物理CDC/板测，前批record_pixels时序问题仍待系统集成解决。详见
[素材DDR验证](../verification/video/avatar_ddr.md)。457保护文件/57其他路线路径
保留，交付15文件，其他路线STATUS保持未暂存。下一步接共享读仲裁及完整记录
叠加链，再联合RAW扫描器/owner退休和平台可见性；本批无COM/JTAG/Flash操作。

## F4c4c 共享读仲裁与完整记录素材链

2026-10-21新增`video_read_arbiter`，RAW紧急最多连续4个burst后服务等待素材，
非紧急轮转。源AR锁存后独占owner，不按RID路由；错误仍按公布拍数排空，未知/
意外响应保守undrained。新`video_record_renderer`显式组合仲裁、DDR素材cache和
完整记录像素组件，真实固定拍provider连接，单个AXI128出口，不新增物理DDR通路。

验证分14个仲裁场景及6个集成场景，含实际旧共享DDR/原生桥、并发RAW字节核验、
800×600三模式像素oracle、异钟比/素材等待/CRC失败/协调reset和退休背压；8项
变异及独立协议/端口审查另绑定。测试退休ready曾未跨core上升沿，已由实际与
最小RED/GREEN定位并修正。集成TB补实际首输出seq证明，检出原先存活的提前commit
变异；PDS实例简写改显式171端口连接，旧生产模块不变。

综合13998LUT/16295FF/64DRM/6APM/0latch；core8ns setup估计-3.630ns，pixel
25ns+12.607ns，hold-2.470ns，未时序闭合。14约束适用，118警告含宽对象集合/
物理I/O未指定；5755接口位仅为组件top，无布线/物理CDC/板测结论。详见
[共享读叠加验证](../verification/video/record_renderer.md)。实际RAW像素身份仍由
调用者提供，尚未联接scanner/owner/MMIO，`video_pipeline`继续RAW-only。

18文件本地交付；465保护文件保持，另1项并行CPU修改及57其他路线路径保留，
STATUS中NPU追加不暂存。下一步接实际RAW身份与owner联合退休，并优先收敛真实
内部互连下的core时序；不把本地像素退休当作CPU全局FREE。本批无COM/JTAG/Flash。

## F4c4d 实际扫描器身份与联合退休

2026-10-21新增video_record_scanout/display_record_link，组合原owner、实际RAW
扫描器和DDR素材渲染器；扫描generation沿冻结mailbox及像素启动路径传递，与
RGB两级对齐。新帧同时等scanner/输出commit，旧槽同时等RAW/像素退休并在替换
反馈被owner接受后才退休；release ACK前不可复用，CPU保留全局FREE决定。

测试为6个事件场景及小尺寸/异钟比/完整800×600整链，逐像素独立oracle、同帧
三模式、generation复用、ACK/素材背压及故障门控；定向变异和独立审查另绑定。
审查发现故障后接受新submit、素材未期待/重复退休两项实现问题，已以即时门控和
精确单次旧渲染引用账本修正；最终结果见[验证记录](../verification/video/record_scanout.md)。

综合18624LUT/30058FF/68DRM/10APM/0latch，core8ns setup估计−1.797ns，pixel
+11.549ns，hold−2.470ns，125MHz尚未闭合。26约束均适用；constraint_check为
0error/critical和138warning，组件6944接口位仅作内部估计，无物理CDC/布线/板测。
正式MMIO和video_pipeline继续RAW-only；下一步接正式控制/采显链并收敛实际内部
互连时序。本批Windows原生、本地提交，不操作COM/JTAG/Flash；保留其他路线改动。

## F4c4e 正式MMIO与三模式采显

新增video_display_record：原正式MMIO内唯一owner连接实际扫描与DDR素材三模式，
MODES=7、地址/640B记录/事件/ACK/C驱动保持。默认关闭的健康扩展仅由新组合启用，
当拍offline/fault阻止新SUBMIT、owner预留和素材load；历史事件仍可ACK，F0下游
fault粘滞，owner协议错误优先，未完成事务不自动回滚。新增video_record_pipeline
复用原采集MMIO、三分支核与唯一shared_ddr，旧video_pipeline目标继续RAW-only。

直接MMIO六个健康及三个实际像素场景通过；完整采显原生C/实际RTL双向回归
完成两帧800×600、三次同帧MODE、五次显示commit、一次联合退休，逐像素核对
2880000个有效输出，欠载0；坏EOF/损坏场景不发布。父4项/审查3项变异均检出，
旧MMIO10/显示扫描17/RAW采显3场景及Python109通过/1权限跳过。独立审查无未关闭
发现；[验证记录](../verification/video/record_mmio.md)及机器证据绑定最终来源/产物。
两目标综合26254/34480LUT、35278/42299FF、68/69.5DRM、10/12APM，0锁存器；
core8ns setup估计−2.090/−3.337ns，pixel25ns +11.549/+11.128ns，hold最差−2.470ns。
125MHz尚未闭合，没有新布线、板测、CPU/NPU执行或物理可见性证明。素材仍为
平台旁带、封存至协调reset，源仍为core域可背压PIX/EOF。下一步推进正式内部
互连/板级wrapper和时序收敛，CPU仍负责全局帧/graph所有权。

## F4c5a CPU控制路由与真实采显固件

新增同钟video_axil_decode，lane0接ABI2采集20012000，lane1接显示20011000；
旧ABI1/孔/不对齐本地DECERR，AW/W独立缓存、读写独立、目标保持到响应。
118项定向/3父变异及独立64项/2变异通过。冻结8a2a07c真实CPU执行未改三个
C驱动，经新路由和原三模式采显共享DDR链完成2帧/3MODE/5反馈/1退休，逐像素
核对5025920有效输出，欠载0；坏EOF不显示，断控制与实际内存损坏被拒绝。
原采集核仅提前同一3行net声明以兼容ModelSim，表达式不变；rearm20/cpu_axil2120用例
通过。已修复审查发现的Python -O移除assert假通过，普通/优化模式各10项验证。

新译码综合89LUT/120FF/0DRM/APM/锁存器，8ns+2ns I/O预算setup估计−3.676ns、
hold−1.970ns，无布线/板测或125MHz闭合结论。CPU仍导出到build作固定数字诊断，
未合入生产CPU；当前轮询、同钟、仿真ROM/SRAM、平台素材和core域可背压源。
正式CPU CDC/fabric、物理可见性和NPU执行仍待各自集成。
[验证记录](../verification/video/cpu_record.md)及机器证据绑定当前结果与范围。

## 本批已交付

| 编号 | 工作 | 状态/证据 |
|---|---|---|
| V000 | Windows 原生工具与许可运行检查 | Icarus、PDS、ModelSim 已实际运行；见工具链记录；DDR 保护库另验 |
| V001 | 工程规则、文件目录和路线台账 | 根 AGENTS、Video README、本文件及接口/参考记录 |
| V002 | 固定模式同源定义 | JSON → RTL/C，支持生成漂移检查和非法模式拒绝 |
| V003 | 参考来源锁定与可重复提取 | HDMI 18 文件、DDR 5 文件按包及成员 SHA256 核验；未整体迁入旧应用 |
| V004 | 便携时序与 RGB888 彩条 | 两连续帧＋中途复位后一完整帧，逐像素自检 |
| V005 | PDS 组件综合 | 原彩条组件 53 LUT、21 寄存器、0 DRM；本批另有板级目标与输入监测组件 |
| V010 | 40/10 MHz PLL 和复位 | 真实厂商 GPLL 模型验证 25/100 ns 周期；外部复位、PLL 失锁及启动等待通过 |
| V011 | TX-only 初始化 | 无 RX 依赖；49 项配置、实际 ACK/超时、五种时刻复位、完整 320 ms 等待通过 |
| V012 | 板级目标/管脚与内部时序 | 37 个 bit-port 的 255 条属性与官方 FDC 一致，24 RGB 引脚与手册一致；外部 AC 参数仍待核实 |
| V013a | 彩条位流与下载包 | 307 LUT、252 寄存器、0.5 DRM；布局布线内部约束通过，.sbit 已生成并按哈希打包 |
| V013b | 实际下载/输出画面 | PG2L100H / 0x00602899；JTAG Program 和 Verify 成功，用户确认最终彩条稳定、按 KEY0 后恢复 |
| V014a | 便携输入帧几何监测 | 12 个好帧、19 个闭合间隔、7,164,199 RGB888 候选像素；尺寸/总计数/DE/控制丢失测试通过，PDS 组件综合通过 |
| V014b-prep | RX 初始化、固定 EDID、精确计时与诊断 | 串行配置、冷启动/重连/故障与复位通过；早期上升沿采样的一周期 HS 歧义已由下降沿板测关闭 |
| V014b | 统一下降沿输入采样与板测 | Program/Verify 成功；800×600、1056×628、全部同步/porch 正确，约 40.0001 MHz；恢复后连续 60 秒采集的 60 包均模式合格、坏帧为 0，用户确认彩条稳定；内部 WNS +6.240 ns，1970 LUT、2918 寄存器、1 DRM |
| V015-prep | 完整 HMIC 与独立 native 自检 | 74 个硬件源锁定、FDC/RCF 审查、8 组缩小窗口 BIST/板级数字替身与错误恢复通过；PDS 内部约束全部满足，125 MHz core WNS +0.200 ns，6747 LUT、6816 寄存器、0 DRM |
| V015a | 物理 DDR 校准、自检与 KEY0 重测 | Program/Verify 成功；低/高各 1 MiB 加哨兵的 3,014,685 个 256-bit 比较无错；KEY0 后心跳 173→1，随后 16 个新包均重新完成自检、错误码 0、全部 PLL 锁定；已恢复 RX 位流 |
| V015b-core | AXI128→HMIC256 桥核心 | core 域串行读写、上下 lane、非法 burst 排空、masked readback-before-B 和故障隔离；canonical191例、独立354例及质量复核通过；共享 fabric/CDC/跨主端排序仍待集成 |
| V020a | RGB888 打包与行式写 DMA | R/G/B 字节序、跨拍 spill、行尾 keep、stride padding、4 KiB拆分、abort/错误排空；完整 raw/preview 数字测试及独立规格/质量审查通过 |
| V020b | 合成 raw AXI/DMA物理自检与KEY0 | 完整800×600、1,440,000字节/90,000拍数字及物理读回通过；60秒完成状态无错，KEY0后heartbeat329→1、17个新PASS包；PDS125 MHz内部多角时序通过，core WNS +0.087 ns，10919 LUT、10488寄存器、0 DRM；已恢复RX、验证输入合格，用户确认稳定彩条 |
| V020c-raw | 真实HDMI单帧raw采集及KEY0 | 实采、60秒状态及同镜像JTAG重启复测通过；现场KEY0后heartbeat167→1，计数清零后45个新完成状态包合格：480000像素/1440000字节、源/DDR CRC均ebf5a8c4，无错误/overflow，FIFO峰值121/2048。已恢复RX并Verify，4个输入快照合格、坏帧0；用户确认KEY0后彩条恢复、恢复RX后彩条稳定，阶段验收完成 |
| V020d | 同帧raw/preview与共享双窗口画面恢复 | 已通过当前候选的受控验收。33e1b8242053已Program/Verify，四角图与普通桌面分别单次实体KEY0后均恢复完整；连续298包包含两个新epoch，复位后稳定约93/81秒，源/DDR CRC一致，溢出/欠载0。旧版黑帧/裁切失败保留历史；仍为按键单帧预览，不代表连续视频或任意源恢复。 |
| V020d-probe | 独立RX像素分布与启动历史诊断 | 独立目标defaa36及当时138帧组件/5解码/完整RX联合仿真、PDS和41检查/117哈希已验证。一次KEY0无时钟75秒；下一次KEY0时序合格但128/129帧CRC仍非四角图，至188才恢复，随后95秒20个取样精确匹配。已保存680条UART和单次按键绑定；支持分离HDMI与采集复位，尚非preview图像验收。后续run.py已修改，旧诊断审查保留为历史来源，不冒称当前全树审查 |
| V020d-reset | KEY0重采保留HDMI链路 | 实现0d3cf8f；26套件/122输入、最终独立84检查/882哈希无发现。第三轮选seed14，slow setup/hold +0.179/+0.066ns、fast +2.962/+0.051ns；原14组束路径和新增42端点/168路径通过。KEY0仍复位DDR/采集/显示，HDMI保持初始化。实体图像验收通过，见[当前证据](../verification/video/evidence/preview_link_reset.json)；新reset/SRL内部计时、外部AC及模拟余量仍不在签核范围。 |
| V020e-scale | 独立检测5×5缩小 | 800×600→160×120 RGB888已完成。27套件/128输入完整回归、6376总和及4突变拒绝通过；独立15帧/12非法尺寸/1350异常注入/4流水取消无发现。组件综合191 LUT、88普通FF、1 DRM、3 APM，8ns估计setup+2.370ns；无布线/板测或量化/补边/DDR。见[验证记录](../verification/video/detect_scale.md)。 |
| V020e-format | 独立BGR/补行及量化后C8 | 两组件定向与4突变拒绝通过；完整源图经明确测试量化模型写DMA的163840B逐字节一致，含末B暂停/stride/4KiB及错误响应。组件综合分别42LUT/46FF、138LUT/129FF，8ns估计setup+4.697/+3.457ns，无DRM/APM。28套件/138输入完整回归及独立审查无发现；真实模型量化与三分支正式事件未实现。见[验证记录](../verification/video/input_format.md)。 |
| V020e-handoff | 外部NPU交接审查 | 用户提供keep-s/npu_zgtc，固定4fc0fc8；167文件/五项资产哈希、241参数数组及三组合成输入哈希已核对，433项定向检查通过。已找到模型/数值/参考，但其320×320双线性居中补边、UINT8 NCHW与本工程160×128块平均/C8不同；300KiB也超出当前每输入槽256KiB。尚无NPU RTL/硬件ABI及跨master可见性验收；见[交接审查](../verification/video/npu_handoff_audit.md)。 |
| V020f-320-ref | 适配既有NPU320数值参考 | 用户已选优先迎合320×320基线，设计ef591a6。800×600→320×240双线性、上下40行零、UINT8 BGR NCHW307200B参考已实现；精确OpenCV4.11的4169764相位/水平和例（优化开关均核对）、六幅全尺寸哈希、4突变拒绝通过。独立19图/11673600字节及另一组完整相位穷尽一致，无发现；Python63项中62通过/1跳过。尚非RTL/DMA或板测，见[验证记录](../verification/video/yunet320_reference.md)。 |
| V020f-320-rtl | 固定5:2双线性RTL | 默认800×600→320×240有效RGB、同步行RAM/分步取整已实现；十组定向及六幅全尺寸OpenCV哈希、4突变拒绝通过。综合246LUT/134FF、1个DRM18K/0APM，8ns估计setup+4.025ns。29套件/145输入完整回归和独立审查通过，尚非NCHW/DMA或板测。见[验证记录](../verification/video/detect_bilinear.md)。 |
| V020g-nchw | 320 BGR NCHW行式DMA | 已实现单行缓存、上下40行零、B/G/R平面和响应排空；公共配置及RTL/C迁移至307200B张量、320KiB槽。完整回归30套件/151输入、162份仿真PASS日志，独立79项检查及184项哈希复核通过；综合1223LUT/791FF/1DRM18K/0APM，8ns估计setup+2.109ns；组件结果及范围见[验证记录](../verification/video/nchw_dma.md)。无三分支/CPU fabric/板测。 |
| V020h-three | 同帧三分支采集核心 | 已实现slot/frame_id/version锁存、原子三路分送、good EOF/raw CRC及三路B退休、保持事件和显式排空；完整回归31套件/159输入、209份仿真PASS日志；独立88条命令/5突变、仲裁7突变及224项哈希复核通过。综合3959LUT/2825FF/3DRM18K/2APM，8ns估计setup+0.596ns。见[验证记录](../verification/video/three_capture.md)。CPU MMIO/fabric/三槽调度及板测未完成。 |
| V020i-three-board | 三分支板级接入及实体KEY0 | 独立目标/串行三路读回/双窗及type8诊断已通过。完整回归32套件/167输入/235份仿真PASS日志，Python67通过/1权限跳过，规格/质量审查通过。第二轮种子14在原8ns/6ns约束下通过内部时序及路径审计，125MHz slow setup/hold为0.000/+0.066ns，16713LUT/17029寄存器/9.5DRM。Program/Verify成功；正式279包中按键前后约116/159秒持续健康，三路CRC均匹配四角图，欠载0，用户确认单次KEY0前后双窗完整。见[集成记录](../verification/video/three_board.md)及[证据](../verification/video/evidence/three_board.json)。 |

已获得P1的稳定彩条、合法HDMI输入时序、DDR校准及复位后自检证据。同帧raw/preview目标保留工作镜像33e1b8242053；三分支独立镜像89c2e860fde4已通过四角图三路CRC及单次实体KEY0验收，保留为双窗诊断基线。F2验收镜像为0cd4a546804b，详见顶部F2记录；当前板卡状态见顶部F3c。旧版黑帧、裁切及错误源图记录均保留。V021a采帧MMIO及V021b-control原生CPU控制桥/数字联测已完成；生产SoC接入/共享fabric、三槽所有权、跨master可见性、NPU推理、外部AC签核及连续采集仍未完成。

本轮 RX/DDR 的独立说明见 [rx_ddr_bringup.md](../verification/video/rx_ddr_bringup.md)。当前用户确认电脑活动信号为 800×600、60.32 Hz，实测 VS 原始高电平为 4224 个像素时钟、场周期 663168；没有将 HS 边沿歧义读出的 VS=3 放宽为可接受模式。最终 RX 位流 SHA256 为 `406edfee9a218bb63b61f3e8a972c671f78e6466692fa67f7666da9154dae50c`，DDR 位流为 `9617217b476b659a51923b06f3338e80b89c41d0cf981ad9436e4ed5ac6666f4`；两者已连同各自同名校验掩码打包。

上一轮JTAG恢复：17:46 后曾持续读全 1，历史脚本/低速/延迟读取均保留失败证据；18:59 重插后两次扫描仍失败。用户随后怀疑 J12 排线接触不良并要求重试，19:04 默认扫描识别到 `0x00602899`，随后 RX、DDR、恢复 RX 的三次 Program/Verify 均成功。恢复支持接触不良判断，但没有电压/导通测量定位具体接点，也没有更改驱动、系统设置或 Flash。当时恢复了下降沿 RX 镜像且用户确认稳定彩条；恢复记录为 `build/video/jtag_scan/20261016T110442_787297Z`。

本批20:10下载AXI/DMA镜像再次在器件识别前失败，默认和500 kHz扫描均找不到FPGA；当时未成功执行Program/Verify，COM12仍收到原RX包但输入模式不合格。用户再次断电重插J12两端并上电后，20:20下载和Verify成功；物理AXI/DMA初测、60秒状态监测、KEY0重测均通过。20:24恢复RX并Verify，随后5个输入快照均合格，坏帧0。本批实现、独立审查、构建和物理证据见 [axi_capture_bringup.md](../verification/video/axi_capture_bringup.md)。

## 按依赖继续实施

| 编号 | 下一项 | 依赖与完成条件 |
|---|---|---|
| V012b | 外部 HDMI AC 时序核实 | 缺 MS7210 采样沿/setup/hold 与板级 skew，不能以内部时序通过替代 |
| V013c | 输出板测补全 | 已有恢复后 60 秒串口记录及用户稳定彩条观察；补显示器模式/LED、照片或录像及更长持续运行记录 |
| V014c | RX 热插拔与长时输入 | 本版固定输入已实测合格；后续扩展拔插/停源、整链路恢复和更长稳定性证据 |
| V015b-integration | AXI桥共享接入 | 核心及独立AXI/DMA物理自检、KEY0已通过；接入CPU fabric/CDC，验证跨主端写后读、在途复位及带宽 |
| V020 | 检测input与正式三分支采集 | 同帧三分支独立板测和实体KEY0已通过，采帧MMIO组件已冻结；下一步接CPU总线/fabric，验收正式就绪事件/槽状态/提交契约及跨master写后读可见性，再扩展连续采集。 |
| V020e-input | 320输入RTL与正式输入集成 | 320数值参考、双线性及NCHW/DMA已实现，公共配置和RTL/C统一300KiB张量、320KiB槽；独立板级三分支的已知图CRC与KEY0已通过。下一步完成CPU地址/版本/MMIO/可见性和槽生命周期，再对接实际NPU推理。 |
| V021b-fabric | 共享DDR与正式CPU SoC | 原生控制桥及固定CPU数字联测见V021b-control；继续实现生产ROM/SRAM、共享DDR不可缓存属性/跨master写后读、PLIC/CDC、协调复位及统一槽状态。采帧MMIO不提供槽allocator或多帧rearm。 |
| V022-fullscreen | 原分辨率全屏与功能键 | F1组件和F2独立全屏板级验收完成；四角图及普通桌面单次KEY0恢复、三段至少60秒健康扫描通过。F3a控制/F3b叠加及F3c独立三模式数字接入已完成，内部时序、Program/Verify和实体KEY1/KEY0验收通过；再接共享DDR与真实NPU。旧双窗位流保留为诊断基线。 |
| V030 | 检测预处理＋人工框/头像 | NPU 量化清单、素材清单；真实张量与像素参考一致 |
| V040 | 三槽/CDC/压力与错误恢复 | 延迟/相位扫描、在途读写及释放 ACK、实际模拟 NPU DDR 流量 |
| V050 | CPU/Video/NPU 两两集成 | 对应路线接口与可运行产物 |
| V060 | 真实演示与优化 | 10 分钟功能、30 分钟优化稳定性；实际有效 fps/延迟分别报告 |

## 采帧控制接口进度

V021a新增`video_capture_mmio`：同core域AXI4-Lite控制、46寄存器同源RTL/C、
锁存采帧请求、独立accepted/completion邮箱、W1C及IRQ。端点351项检查、实际core
三几何21场景、独立规格22486项及质量8708项总线检查均通过；质量审查另验四几何
28场景。RV32I/ILP32头文件已实际编译；8ns组件综合666LUT/852寄存器/0DRM，
估计slow setup+3.298ns。最终完整回归及输入/产物绑定见
[验证记录](../verification/video/capture_mmio.md)和[证据](../verification/video/evidence/capture_mmio.json)。

最终回归33套件/176项输入、238份仿真PASS日志；Python79通过/1项Windows权限跳过。
规格/ABI/质量审查无剩余实质问题，当前185项源文件及全部审查产物哈希经父任务
复核一致。交付18个Video文件，31项其他路线文件保持起始哈希；仅在本地提交。

本端点仍是每个协调复位epoch采一帧，ACK不释放槽、不清故障。原三分支板级RTL
及目标保持`f3c456f`基线；本批不迁移CPU、不下载新位流。修正了晚到accepted、JSON
重复键、独立config证据遗漏，以及构建复制快照哈希竞态与Windows路径键，失败记录保留。

V021b-control已实现CPU原生11bit tag至Video AXI4-Lite适配，组件2120项及独立规格/
质量检查通过；64LUT/132寄存器、8ns未布线setup估计+5.870ns。固定CPU提交8a2a07c
的单/双发射×轮询/中断/采帧失败六个真实固件用例、精确load/store错误及两类负例
均通过，原文件/副本/Gitblobs/工具/产物均绑定。详情见
[控制路径](../verification/video/cpu_video_control.md)。固定CPU的CSR读使能导致旧MIP
缓冲问题，诊断清位序列与原波形已记录；正式SoC前仍需CPU侧修正，不作完整CSR签核。
随后接共享DDR fabric、跨master写后读和统一三槽状态/显示释放ACK。CPU工作树
尚无正式SoC互连，不能把本端点的completion当作已验证的SoC INPUT_READY。
连续采集还需受控重用及排空，NPU实际RTL/推理继续按独立依赖验收。

本批最终完整回归34套件/180输入、239份仿真PASS日志；Python79通过/1项Windows
符号链接权限跳过。父任务复核当前源、工具和全部引用证据，并绑定520份回归日志。
规格/质量独立审查无本批剩余实质问题。交付19文件，31项其他路线文件保持起始
哈希；小范围本地提交，不修改CPU工作树或新增板卡下载。机器摘要见
[cpu_video_control.json](../verification/video/evidence/cpu_video_control.json)。

## 尚未关闭的共同契约

- CPU＋Video：采帧MMIO及原生CPU控制适配的数字联测已通过；生产SoC接入、显示提交/旧槽释放、fabric仲裁及跨master写后读可见性待集成。
- NPU＋Video：用户已选适配外部4fc0fc8的320×320 UINT8 NCHW；精确OpenCV4.11参考、缩小与NCHW/DMA及独立三分支板测已通过，物理已知图证据为三路CRC对照。320KiB槽已纳入公共JSON及生成RTL/C；CPU译码/fence/跨master可见性、NPU RTL和真实推理基线仍待验收。
- CPU＋Video：头像锚点、目标矩形和边界规则；三帧槽最坏生命周期证据。

## 本轮硬件连接观察

2026-10-16 初次仅 COM1；用户连接并上电后，识别 USB Cable II、COM12 CP210x、COM9/COM11 FTDI，驱动状态 OK。最初 JTAG 出现 JtagServer-0306、原始 ID 全 `0xFFFFFFFF`。用户确认电源灯亮、J12 排线接好并断电重插。之后使用历史成功的原始只读 Tcl 恢复识别，当时默认扫描脚本也通过。尚未确认初次失败的根因；后续再次失败的当前状态见上文，不能归因为 CPU 下载损坏板卡或单独认定脚本/频率设置有误。

TX-only 彩条验收记录：`build/video/board_program/20261016T082259_109276Z`，Program/Verify 均成功，无 Flash 写入；用户确认彩条稳定，短按 KEY0 后恢复。显示器 OSD、LED、照片/录像与连续时长尚未记录。该历史位流 SHA256 为 `925da96138681fdcc2e1f18739d3a8d931a81f65f34d3972ed8c98bad17f9290`。初次打包遗漏 Verify 必需的同名 `.smsk` 已修复，打包现在核对其哈希并带入发布目录，缺失/损坏回归通过。扫描入口为 `build/video/latest_jtag_scan.json`；临时 server 只结束自身进程。DONE 为配置状态，本次未确认独立 DONE 灯的存在或位置。

首批 11 项 Python 测试的记录保留在 `windows_kickoff.json`；TX-only 批次的 19 项记录保留在 `board_smoke.json`。RX/DDR 批次完整回归 `build/video/regression/20261016T104805_104909Z` 已通过：33 项 Python 测试中 32 通过、1 项 Windows 符号链接权限相关跳过；串行 RX 初始化、精确测量/探针、CDC/UART、RX 板级集成、8 组 native BIST 和 DDR 板级数字替身均通过。当前完整回归原始结果入口为 `build/video/latest_all.json`，本批摘要见 `docs/verification/video/evidence/rx_ddr_bringup.json`。

提交管理：基础提交为 `84b8d69`，彩条基线为 `16556d1`，RX/DDR 实现为 `cd5ee08 feat(video): add HDMI RX diagnostics and standalone DDR BIST`。本批补记恢复后的物理板测结果，仅提交 Video 文档与证据；技术报告已有修改保留，未推送或合并到 main。验证摘要与源码哈希绑定，提交号以 `git log` 为准。

## AXI/DMA 本批交付记录

最终完整回归 `build/video/regression/20261016T120334_259053Z` 通过，35项Python测试中34项通过、1项Windows符号链接权限跳过；新增桥、packer/DMA、四种几何端到端测试及AXI板级数字替身均纳入，原RX/native DDR等套件同时通过。完整800×600检查1,440,000字节、90,000拍；独立物理结果另由实际Program/Verify和UART证明，未混同数字IP替身。

首轮布线core WNS −0.195 ns，因读回比较进入写选通组合路径；仅按互斥读写阶段等价拆分写掩码故障条件，保留所有响应/故障语义。两组四态等价测试、当前哈希桥质量复核通过；最终125 MHz WNS +0.087 ns，约束原样保留。包为 `build/video/releases/video_axi_capture_f1535f12e7d3`，位流SHA256 `f1535f12e7d3ce07fa3c144122e1d31b6fa460ae13f6a97eec44304f90315328`。

独立RX恢复包为 `build/video/releases/video_rx_board_46d80ec8eed2`，按当前构建脚本重新生成，已在本轮完成Program/Verify和模式复验。机器可读摘要为 `docs/verification/video/evidence/axi_capture_bringup.json`；历史 `rx_ddr_bringup.json` 保持历史证据，不重标为当前源验证。软件实现提交 `c928706`；只提交本批Video变更，保持当前分支，不push。

## HDMI raw 单帧本批收尾状态

实现提交为 `27960cb`（引擎）、`61d3a07`（写缓存等价故障条件）、`22bfb22`（联合板级工程及脚本）、`86aed0d`（读回专用故障与写控制分离）。最终18套件回归、PDS和独立审计均绑定当前源码；125MHz slow setup余量+0.233ns，12043 LUT、12174寄存器、4 DRM，原约束未放宽。保留本地分支，未push。

2026-10-17用户恢复800×600源后，采帧包 `video_hdmi_capture_2e01feb8e69d` 已实际Program/Verify；首帧和60秒状态通过，CRC5c1e6651。当时用户远程无法按KEY0，先以同镜像JTAG重新配置作自动重启测试：heartbeat757→1，新帧CRC8aa54beb，45个新的完成包全部合格；该记录与后续实体KEY0补验分开。

用户随后到场，重新安装同一采帧位流后短按KEY0。`build/video/board_serial/20261017T012418_613147Z` 记录heartbeat167→1，复位后首包busy、未完成、计数清零，随后45个完成状态包报告同一新帧：480000像素、1440000字节、源/DDR CRC均ebf5a8c4，FIFO峰值121/2048，无错误/overflow。用户确认KEY0后彩条恢复。观察区间无JTAG编程，实体按键重采验收已完成。

该轮 `build/video/board_program/20261017T012531_400691Z` 已恢复 `video_rx_board_26d25f7dd060` 并Verify，`build/video/board_serial/20261017T012551_557951Z` 的4个快照模式合格、坏帧0；用户确认重新出现稳定彩条。raw单帧阶段的现场待验项已全部关闭。该轮验收范围为raw单平面；后续共享preview/捕获内容显示的验收见V020d，检测input、三分支CAPTURE_DONE和共享CPU fabric仍未实现。

物理汇总见 [hdmi_raw_capture.json](../verification/video/evidence/hdmi_raw_capture.json)，现场补验见 [hdmi_raw_capture_key0.json](../verification/video/evidence/hdmi_raw_capture_key0.json)，详细结果见 [hdmi_raw_capture.md](../verification/video/hdmi_raw_capture.md)。[hdmi_raw_capture_preboard.json](../verification/video/evidence/hdmi_raw_capture_preboard.json) 保留为前一天上板前的历史状态，不重写或混作当前物理结论。


## 2026-10-22 Video F4c5b 组件时序基线

- 沿用已批准的125MHz收敛方向，新增三个内部组件的显式PDS pads/component诊断；默认综合命令保持兼容，未修改产品RTL、ABI、驱动或FDC。component仅禁用物理I/O缓冲，不切reset/I/O/CDC路径，core8ns、pixel25ns和稳定束6ns保持。
- 最终同版工具四项综合及诊断完整性通过：译码器pads setup−3.676ns、component+1.255ns；显示组合component core+0.311/pixel+11.549ns；采显组合component core+0.311/pixel+11.128ns。component映射分别91/120/0、26491/35278/68、34718/42300/69.5（LUT/FF/DRM），不把I/O模式差当作RTL优化幅度。
- 两大组件最紧内部setup为RAW描述符范围检查的APM链至显示link状态CE。采显组合hold−3.097ns、最差removal−1.393ns仍开放；均单slow corner，fast表空，无PNR、物理闭合或板测。setup正裕量不能替代全系统125MHz验收。
- 25项相关测试普通/-O通过；独立审查的两组P2已修复，8项缺损/矛盾报告反例均拒绝。严格解析时钟、5类汇总和关键路径；datapath_only仅核验捕获组保守下界，明确区别于精确时钟对。探索的无效Tcl句柄筛选及114/120不完整名单保留，不当成功；完整120FF有限寄存器诊断另记。
- [验证记录](../verification/video/component_timing.md)、[机器证据](../verification/video/evidence/component_timing.json)。CPU交付不阻塞本批；下一步建立可布线的内部接口边界，再验证原频率下setup/hold/removal，必要流水化单独回归。未操作JTAG/串口/Flash，保留NPU当前板卡状态；CPU/fabric/DDR/CDC与真实模型合拢仍独立验收。


## 2026-10-22 Video F4c5c 注册边界与shadow字节写使能

- 新增完整默认采显video_record_probe，161原端口/2227位经双域扫描形成12个物理端口；core708/1148、pixel26/341位输入/输出。显式生成与逐位映射检查、真实DUT idle及三个有效编译RTL反例通过；仅准synth/route，禁止bitstream。
- core8ns/pixel25ns、4标量同步例外和12稳定束6ns保持，扫描I/O max2/min0.5ns及setup0.1/hold0.05ns不确定度共30约束。新注册边界不同于旧组件I/O模型；不作数值直接优化对比。两版CCR均0error/0critical，无不适用/有问题约束；12条缺物理pin属性告警保留。
- 根据旧布局15级MMIO shadow合并写路径，改为逐字节写使能；ABI、B/R响应拍数、健康/owner不变，无新增周期。旧/新2723写2883读、既有MMIO10场景和C驱动、6健康/3真实三模式显示组合均通过；相关Python普通/-O各46项，独立审查发现均修复。
- 同扫描边界新版综合35254LUT/44517FF/69.5DRM，比旧版少67LUT/1FF。相同seed4/performance及估计连线模型布局core−2.953/pixel−1.184ns，旧版−2.841/−1.393ns；最差路径由15降13级但core未改善，地址计算和高扇出写控制仍需处理。普通report_timing读placement DB的零连线正值单列，不能签核。
- 初次route中断诚实留存；旧冻结版和字节使能版分别独立布线，最终报告均未取得。旧helper额外绑定的当前验证器变化有旧副本/哈希审计，不能将其expected hash拒绝改为helper成功。新wrapper/FDC/manifest与冻结版完全相同。125MHz系统时序仍未闭合。
- [验证记录](../verification/video/record_probe.md)、[机器证据](../verification/video/evidence/record_probe.json)；CPU交付不阻塞本批。95项既有状态中94项非STATUS条目未变，台账只追加并按index projection仅提交本段，保留CPU/NPU/技术报告修改。无CPU/NPU迁入、JTAG/COM/Flash或板测；后续先取得真实route，再按实际关键路径继续收敛。
