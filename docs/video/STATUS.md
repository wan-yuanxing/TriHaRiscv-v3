# Video 工作台账

## 当前进度：2026-11-04 04:53，三项控制路径优化已采用，整机与物理流程重建

源码检查点 `76d3d53` 保留指定照片、无损像素和50/125/40MHz：区域内MMIO偏移限为12位，
完整地址合法性仍先检查；100位像素提交身份比较拆成6组16位和1组4位，保留比较节点，
不加协议周期；缓存延迟数据/地址寄存器每周期采样，只有原有delayed_write允许实际RAM写入，
素材发布时刻不变。三项分别针对完整旧报告中的身份比较、地址译码及缓存数据使能路径。

先做隔离逐周期对比、独立协议/字节/逐像素验证，再采用。生产代码19个控制场景、
模式按键检查、指定头像8个DDR场景和3个连续流/复位场景通过，完整65536像素一致。
新增可复现控制测试入口 `python scripts/video/test_display_control_paths.py`。
新正脸/无脸七段整机仿真和综合同时运行，本批尚无新的整机或时序通过结论。
完整流程为 `build/video/face_photo_control2_50_pipeline_20261104/receipt.json`。

首个构建误选上一轮正脸ELF；已核对ROM/SRAM全部字相同，仅ELF非装载.strtab不同。
为保留发布流程对正脸ELF的精确绑定，主动停止所属构建进程，改用本轮正脸ELF重新综合，
两场整机仿真继续运行。中止记录保留，不记作原生综合失败。没有改动验收器或放宽检查。

上一轮8网优先路由独立验收仍失败：setup最差−0.653ns、hold最差−0.553ns；
DDR内部339个负setup端点、compute域25个、DDR至PHY1有2个，另有3条跨SRB路径低于200ps
修复目标。552个指定PHY位置保留，通过位置核验不代表时序通过。本轮未生成位流。
完整负setup补充报告覆盖更早一轮260个端点/6个起点，仅作诊断，不代替正式双角验收。
硬件连接仍以04:12/04:13只读扫描未识别FPGA为最新证据；照片版尚无烧录或七段上传。


## 2026-11-04 04:21，记录校验版独立时序失败，继续实测关键网布线

指定头像及完整功能仿真保持上一批通过状态。记录校验/行计数优化版的最终独立双角报告
仍未闭合：最差setup −0.533ns（DDR内部258端点），DDR至PHY1另有2端点、最差−0.168ns；
所有hold表非负，但最小仅0.000ns，并有3条跨SRB路径不足200ps修复目标（1项STA-3017）。
552个指定PHY寄存器的最终位置逐项核对通过。故本轮未生成位流。

记录校验及行计数旧关键路径不再出现在报告的负setup样本中；当前最差路径为像素提交
身份比较至帧退休控制，其次为MMIO读地址译码。现复用冻结布局，对4个不同起点的8条
原始关键网络设置布线优先级，均已被原生工具接受；时钟、逻辑和验收门槛不变。
流程：`build/video/face_photo_guard_priority_50_pipeline_20261104/receipt.json`。
失败证据：`build/video/face_photo_guard_50_review_20261104/result.json`。

另在隔离副本验证MMIO区域内偏移限宽、像素提交100位身份比较分段两项备选改动，
19个场景及全部输出逐周期对比通过，含完整4096地址页/高位别名、2723次字节写/2883次读、
100个身份位分别翻转拒绝；生产源码和活动映射未采用这些实验改动。独立原生综合均成功：MMIO估算setup由+1.388ns
提高至+2.727ns、LUT 2796→2790、FF 6156不变；身份比较模块为+1.183→+1.217ns、
LUT 526→531、FF 1070不变。仅为组件综合估算，不能代替整机布线时序。
首次诊断脚本因沿用要求复位时钟覆盖的宽范围解析器而拒绝报告，原生综合成功；
第二次采用仅提取组件setup表的诊断解析，生产时序验收器未修改。
紧凑视频回归脚本的预期记录校验数量也已从246同步至当前248，检查已有通过日志及语法，
未声称重跑完整紧凑视频套件。
用户告知重接电源/JTAG后，04:12的1MHz及04:13的100KHz只读扫描仍仅识别下载器，
未识别FPGA；日志已保留，照片版尚无烧录或七段实板上传。


## 当前进度：2026-11-04 03:49，记录校验/行计数优化整机通过，继续布线

指定照片、无损行区间缓存及50/125/40MHz保持。源码检查点为 `d759664`：
在接受记录时寄存16路框检查结果，借用原有header周期分隔几何判断和lane选择，协议及结果周期不变；
RAW每行剩余AXI拍数改用 `$clog2(ROW_WORDS+1)` 位，800像素模式为8位，最大值150，
只减去已完成且不超过剩余数的burst。两项分别针对实测最差−0.780ns和次差−0.375ns路径。

248项独立记录校验及46个RAW场景通过；RAW整幅800×600检查3帧、144万像素，
覆盖窄行/填充、4KiB边界、错误/背压/复位和时钟比例。采用前的隔离校验流水实验还逐周期
比较了原实现，含等待素材和中途复位。新正脸/无脸整机七段仿真均PASS，零错误/零警告，
两帧全像素、三模式、释放和复用均通过；136项共享源码及固件已与本次映射逐项核对。
综合PASS：48,833 LUT、47,759 FF、112.5 DRM；映射及PHY位置约束布局完成，
布局最终估算+0.635ns、TNS=0，目前performance模式正式布线中，尚无新布线后时序结论。
当前流程：`build/video/face_photo_guard_50_pipeline_20261104/receipt.json`；会在新映射上继续
使用已有552个PHY同名寄存器位置证据，重复最终位置、双角STA、Gray时钟及原生诊断验收。

本次仿真正脸相邻结果间隔18,079,060计算周期=361.5812ms（2.76563次/秒），
无脸为361.20636ms（2.76850次/秒）。每个场景仅一个间隔，使用DDR仿真代理；不是实板FPS或端到端延迟。
参考画面位于 `build/video/face_photo_guard_reference_20261104.png`，是独立oracle渲染，不能当作板卡截图。

上一轮24网优先布线最终为setup−0.780ns（DDR内部56个端点），所有hold表非负、最小+0.018ns，
552个PHY位置保留；仍有4条跨SRB路径不足200ps修复目标，故未生成位流。保留失败报告，
不改成通过。最近02:52的只读JTAG仍只能见下载器；照片版尚未Program/Verify或七段实板上传。

## 2026-11-04 02:58，指定照片头像保留 PHY 布局优化关键布线

已验收 BOX 发布保留在 `face-box-20261103`。当前用户照片的无损行区间缓存与写流水版本
为 `2c9e0e9`；正脸/无脸整机七段加载、RAW/BOX/AVATAR 逐像素检查及综合/映射均通过。
performance seed-5 已完成布线，但独立报告最差 setup −1.716ns、hold −0.758ns，
DDR 域仍有违例，未生成位流。旧缓存 RAM 写使能长路径已不在报告的负 setup 路径中；
23组/116位 Gray 数据路径界检查通过，但未进行完整 Gray 时钟验收。
normal seed-4 新布局在520轮详细布线后仍剩973条网络，主动中止并保存拥塞记录；
这是代理切换方案，不能当作原生工具失败或最终时序结果。复用 performance 冻结布局的29条关键
网络优先路由已完成，DDR内部setup改善到−0.473ns，但PHY仍使最差setup/hold为−1.707/−0.770ns，
未生成位流。随后把先前hold全表通过的原生布局中552个同名PHY寄存器位置用于新布局；
新旧DDR IP文件和生成来源完全一致，最终原生位置逐项比较552/552通过。
本轮最终独立STA最差setup为−0.464ns（DDR内部60个端点，DDR至PHY另有3个端点），
hold全表非负、最小+0.018ns；仍有1项跨SRB路径未达到200ps修复目标的STA-3017，验收失败。
当前复用此冻结布局，对12条不同起点的负setup路径中24条实测关键网络优先布线；
全部优先级名称已被原生工具接受。映射逻辑、50/125/40MHz约束及验收门槛保持。
详细证据见 `docs/verification/npu/2026-11-03-face-avatar-bringup.json`。

用户重接后的历史 JTAG 扫描曾识别 PG2L100H，但 00:25 的 1MHz/500KHz 两次新服务器扫描
均只能看到下载器，02:52再扫1MHz仍未识别FPGA；已请求用户确认当前电源/JTAG。当前仅只读扫描，
未对照片版执行 Program/Verify 或七段上传。继续完成离线时序验收和可复现交付，再进行上板验证。
下方按批次保留历史记录，旧板卡状态及旧时钟规格不代表本条当前进度。

最新失败证据：`build/video/face_photo_phy_sites_50_review_20261104/result.json`；位置核验：
`build/video/face_photo_phy_sites_50_retention_20261104.json`；当前流程：
`build/video/face_photo_phy_sites_priority_50_pipeline_20261104/receipt.json`。此前首次优先级约束含5条
布线后临时ntR网络，被原生约束检查拒绝；修订后的29条原始网络均已被工具接受。

验收脚本新增复用布局时的阶段区分：合并PNR日志必须有唯一且有序的“Finished placement.”/
“Routing started.”边界，布局部分继续检查全部错误，后续未复用的旧路由诊断单独保留。
当前新路由始终检查完整日志；同文件不能裁切。7项单元测试先红后绿，11项原生审计反例及
真实旧/新日志诊断检查通过；两组既有完整整机仿真重新核对与映射源码一致。RTL和位流门槛不变。

PHY位置试验仅约束同名且未进行后布局打包的寄存器，保留官方管脚及两个门控时钟位置；
后续会逐项比较原生最终位置。首轮临时监控器误把53项已在官方参考中核实的share-pin提示
当成约束错误，已保留中止日志和诊断；第二轮改用既有严格参考匹配审核。映射网表导出探测
也记录为失败：该版本原生gen_netlist要求PNR数据库，没有生成或声称验证映射网表。

交付导出器 `scripts/video/export_face_release.py` 已通过7项独立传输检查：完整恢复、递归保留
原始布局依赖、拒绝源码/原生证据篡改、拒绝未通过资格的输入、发布目录不可覆盖，以及压缩期间
文件变动。最后一项先得到预期失败，再增加打包前/逐文件读取/完成后的身份核对后通过。
记录为 `build/video/face_release_export_red2_20261104.log` 和 `face_release_export_green_20261104.log`。
这些小型合成夹具只验证交付机制，不代表照片版时序、位流回放或板测通过；实际包仍待时序收敛。

## 2026-11-03 本机恢复与人脸检测优先（11:58，在运行）

用户当前明确：板卡暂未连接；先完成功能仿真、构建及布线后时序收敛，得到位流后再连接设备。第一里程碑为真实人脸检测与同帧主框显示，帧率记录但不设硬门槛，头像/五点不阻塞。当前工程是用户指定的 `D:/FPGA/TriHaRiscv-v3`、分支 `soc/face-box-integration`；下方旧条目的工程位置、板卡状态和125MHz计算域描述不代表当前状态。

本机工具恢复为现有 GCC 15.2.0、ModelSim 10.5、PDS 2022.2-SP6.4。仅用进程环境变量覆盖旧绝对路径。Python数值依赖放入忽略目录 `build/python-deps`。固定上游提交 `558280b30219acdcf9f962acd6e907e0f680ab52`；241项参数数组独立比较后恢复format1 program/parameters，两者SHA与冻结清单完全一致。新增可复现入口 `scripts/npu/recover_format1_assets.py`；复跑结果在 `build/npu/recovered_format1_repro/result.json`。

B03恢复：38/68历史文件匹配，`core_ready=true`，zero/full255/pattern三例237个算子输出比较通过；其余历史场景/记录未恢复，整体audit保持PARTIAL。自然人脸新参考在 `build/npu/face_fixture_20261103`，ROI为(349,215,166,257)，不作为准确率指标。

发现并修复无模式键时固件停留RAW的问题。新增整机断言已先得到预期失败：`build/soc/face_system-20261103T034810_639716Z`，报BOX未在捕获前选择。修复后完整六段加载/真实CPU+NPU/两帧逐像素回归正在 `build/soc/face_system-20261103T034939_772163Z` 运行；需完成后才可记PASS。固件组件4007检查、13项时钟/上传器测试、真实PLL连接及复位变异测试已PASS。

新增显式 `--face-profile box`，保留avatar默认配置。BOX使用现有精简主框renderer、关闭头像cache和KEY1，CPU/NPU=100MHz、Video/DDR=125MHz、pixel=40MHz，DEMO_BOX_ONLY=0。第一次PDS构建因三个已裁除节点的约束而失败；将这三条原命令原样移入头像profile专用FDC，独立Counter比较证明原约束全体一条不漏、无重复。第二次构建 `build/video/pds/20261103T035439_337985Z` 正在运行；尚未获得布线后时序或位流结论。KEY1参考FDC已通过原厂RAR提取与SHA核验恢复（`prepare_reference.py --reference key`）。

构建/上传指引见 [FINAL_APPLICATION.md](FINAL_APPLICATION.md)。BOX上传必须带 `--model-only`，六段；avatar为七段。没有扫描、下载或Flash操作。当前待完成：整机回归、综合资源、完整布线、慢快角全部检查、Gray max-skew、PHY sites、位流/校验掩码与证据打包；HDMI外部AC及实板验收另列。


## 2026-10-30 CPU流水冲刷副作用隔离验证

完成既有CPU工作树的七个分支重定向/加载访问异常场景。32/64周期加载返回延迟正例分别为750周期/2199项检查、1102周期/3031项检查，各162条退休序列独立比较一致；四个软件或端口错误输入负例均被副作用检查拒绝。原始VCD复核四次精确异常、四次MRET及同目的寄存器恢复加载，禁止指令零退休。当前LSU为阻塞式，未将尚未接纳的年轻加载描述为跨重定向迟到返回。

桌面工具旧会话在写kernel assets时返回os error 3；当前新运行时窗口枚举与实际截图均已恢复，旧会话具体缺失路径未确认。已保存3060×1920无鼠标指针的ModelSim原始截图，并关闭本轮只读查看器。技术报告B.4新增方法、七项结果表与波形，现有build.ps1编译成功；最终日志无错误、未定义引用或Overfull，未渲染或预览PDF。

摘要：`docs/verification/cpu/system_squash_side_effects_2026-10-30.json`；支撑说明与323项逐SHA核验的增量包位于`docs/verification/cpu/system_support/SQUASH_README.md`和`cpu-squash-support-2026-10-30.zip`。本批未修改生产RTL，未运行PDS、PNR或板卡操作，未开展DMA可见性第二类场景，NPU/Video设计不变。

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

## 2026-10-20 NPU最新交付验证与合拢评估

外部NPU已拉取至`D:/FPGA/npu_zgtc`，固定`178c3ad1ba515d43725dd80ab19e20b50d471413`。
本轮7项资产哈希、241参数数组、3×79张量INT64及程序回放、27头历史golden哈希、
6图1843200字节预处理交接比对通过；14个ModelSim平台仿真任务及4个独立PDS
顶层布线通过，BIST位流已生成，无本轮下载。完整NPU计算/控制/DMA仍缺席，
不能将平台探针视为真实推理。报告见[合拢评估](../verification/npu/2026-10-20-integration-readiness.md)。

旧160/C8/256KiB差异已由当前320 UINT8 BGR NCHW/320KiB槽消除。当前新增核实的
阻塞是主规格逐算子调度与外部整图程序、五点与bbox九头的契约冲突，以及NPU
候选100DRM与当前三模式板级73.5DRM直接相加超过155DRM容量。还需生产CPU/fabric、
100↔125MHz CDC、唯一DDR通路及跨master可见性；CPU100MHz收敛状态仍按CPU证据。
可以先推进契约和RAW系统仿真，完整合成/真实推理/板测准入尚未满足。

完整WIDER AP、天然图golden及上游完整程序ABI入口未复现；干净克隆缺失reports依赖
的失败与仅用已提交资产重建的补充验证均保留。此次没有修改Video RTL、公共配置或
已有技术报告，也未执行新的Video回归、系统PDS或板测。

## 2026-10-20 NPU平台自检首次SRAM下载

用户随后授权开始NPU片上自检上板。本地硬件手册哈希、两套厂商LED例程各10引脚、
电平/方向/驱动和省略SCBV策略已复核；复制同名sbit/smsk并逐项核对原仿真/PDS证据。
19:58完成PG2L100H ID识别、Program/Verify及下载后DONE=1，全部成功，无Flash写入。
板卡当前运行独立PLL/RAM/APM自检，HDMI画面暂停；原三模式恢复包保留。
20:25登记用户确认初始灯态/心跳符合预期、实体KEY0五次复测均正常，片上自检与
重复复位现场功能通过。10分钟稳定性仍待单独确认，未以消息间隔推断通过。
见[上板记录](../verification/npu/2026-10-20-board-selftest.md)及[机器证据](../verification/npu/evidence/board_selftest.json)。


## 2026-10-21 NPU合拢准备：CPU表、候选地址和资源方案

- 用户授权继续推进，并确认最终保留五点关键点，bbox仅为中间验证。沿用主规格CPU逐算子控制，新增主机候选配置与标准库准备入口；现有Video公共配置和RTL未改。
- 从冻结包生成三槽地址、80张量/150参数/79算子的21728B离线CPU表；输入直接绑定0x82800000/0x82850000/0x828A0000，参数转入model区。C头默认DDR指针，未交付MMIO寄存器编码、板级装载器或可运行NPU驱动。
- 最终33测试通过，独立核验240张量地址、150参数地址及全部算子字节；两种C头模式实际RV32I/ILP32编译通过。硬件准入选项实际退出2，hardware_ready=false。
- 按Video73.5DRM（含64头像cache）和NPU保留100.5重核：原样174超155；RAW候选计入CPU10/fabric8后128，换16DRM按需DDR素材cache候选144。均为规划，尚无合并实现/新素材路径或全系统时序签核。
- 独立CPU侧已存在dc00f80的100MHz通过记录（setup+0.113ns），纠正旧评估阶段性结论；主工程未合CPU，当前CPU工作区另有实验，本批不迁入。五点FP32候选保留九头的三输入比对通过，额外MAC约1.81%；关键点INT8与硬件仍开放。
- 原始结果`build/npu/integration_preparation_20261021/`；[本轮记录](../verification/npu/2026-10-21-integration-preparation.md)、[机器证据](../verification/npu/evidence/integration_preparation.json)。49项其他既有文件保持哈希，Video旧流水线计划在期间变化另记；本台账仅追加。
- 本批无RTL仿真/PDS/JTAG/串口操作，未提交或推送。BIST10分钟观察仍待明确反馈；下一批实现单算子MMIO/DMA回读仿真闭环，再逐层扩展及五点量化。


## 2026-10-21 NPU 真实单算子 CPU 闭环

- 已按白名单迁入单通路 Dense/DW、JSON 单源寄存器、AXI128 DMA、RV32I 驱动和固件；native AXI-Lite 仅参数化地址前缀，默认 Video 行为保留。固定 CPU dc00f80 从 Git blob 导出联测，未导入 CPU 工作树实验源码。
- 主工程完整 26 组 poll/IRQ、52 任务、6308 字节实际回读通过，断开控制/破坏输出两反例拒绝；18 组数值场景、DMA72、MMIO785+生成器20，以及原 Video cpu_axil 回归通过。上批准备33项、报告4项、源/副本注改6项共43项测试通过。
- 100MHz 组件最终布线 setup slow/fast +0.424/+2.480ns、hold +0.118/+0.101ns；3339LUT/2807FF/16APM/0DRM，含542扫描边界FF，约束未放宽。保留两轮真实时序失败；质量审查发现并修复完成快照竞态、runner源绑定及优化模式验收问题，最终无阻塞项。
- 34个交付文件迁移保护检查通过；复制瞬间46个既有文件保持哈希，本台账只追加。早期快照以来Video头像计划、迁移后Video renderer测试的并行变化单列保留，未恢复或归入本批。
- [验证记录](../verification/npu/2026-10-21-operator-loop.md)、[机器摘要](../verification/npu/evidence/operator_loop.json)、[接口](../interfaces/npu.md)。真实Conv_0仅7×5裁剪输入；CPU回读为同一数字DDR模型的本地端口。完整网络、最终五点INT8、正式fabric跨master可见性、物理DDR/CDC、全系统时序/资源/帧率与整机板测仍开放。
- 本轮无JTAG/串口/Flash、提交或推送，未确认当前板卡镜像；历史BIST初始灯态/KEY0五次通过、10分钟稳定性待明确反馈的状态保留。下一步逐层整数/五点量化及共享fabric/DDR/CDC集成。


## 2026-10-21 NPU 真实卷积逐层验证

- 复用178c3ad冻结程序、参数、整数参考及golden，47个真实卷积（Dense30/DW17）×zero/full255/pattern共141次全尺寸RTL仿真通过；全部11736000字节一致，无裁剪/抽样。名义MAC253569000、有效MAC252434112逐层核对通过。
- 未修改npu_scalar_conv（仍ea9cf1af…）；Windows原生编译仿真跑全量，ModelSim四态独立复核4个代表层，7400字节完全一致。第三方工具只在build解压并锁SHA，实际自报rev vUNKNOWN-built20260516-4e853d8，未替代物理验证。
- 规格/质量审查通过，修复manifest/segment封存窗口并严格区分PARTIAL与完整资格。主工程12个文件迁移、26项测试及两后端入口复测通过，上一批34文件交付保持哈希；复制瞬间88个既有文件不变，Video renderer计划/测试/STATUS并行变化单列保留。本台账只追加。
- [验证记录](../verification/npu/2026-10-21-layer-validation.md)、[机器摘要](../verification/npu/evidence/layer_validation.json)。各层输入为主机参考中间张量，尚未硬件串联；Add2/Pool4/Resize2/Transpose9/Reshape9/Sigmoid6共32算子仍缺，不能称整网完成。
- 最终五点INT8/精度、正式fabric/DDR/CDC、整机资源/时序/帧率和板测仍开放。本轮无DUT/约束修改，未重跑PDS、未JTAG/串口/Flash、未提交推送。历史BIST10分钟反馈仍待明确确认。下一步补辅助算子/调度并做整图串联。


## 2026-10-22 NPU上游DDR更新审查与处理顺序

- 上游已fetch到89acc7b（相对178c3ad新增4提交/59文件）；外部工作树仍保留178c3ad与本地台账，本轮按283文件冻结快照审查。46个既有数值/参考文件及关键控制/地址契约未变，47卷积×3的141次结果继续有效，不重做量化或卷积回归。
- 更新集中于HMIC原生DDR自检、监督器、正确器件IP及B00/B01下载包，没有新增辅助算子、整图引擎或五点INT8。主工程与新HMIC的371参数/71个DDR端口最终属性一致；复用唯一DDR，现桥已有按WSTRB读回匹配后才返回B的实现。
- 本机代理26正常/28故障（含7非法）/2忙时复位、监督器2正常/5故障/8复位通过。真实HMIC+双DDR模型九轮27写/27读、5184字节比较通过；首轮旧acc选项兼容失败留存，仅自有重放脚本改为npr。初始化加速及297告警保留，不作严格DDR时序或物理签核。
- P0功能主线继续补32辅助算子并串联79算子；P0接口验证并行处理保护库76ns失败归因、真实NPU DMA经正式候选fabric/CDC/唯一桥的末B→DONE→另一master读回及协调复位。P1保留最终五点INT8/精度要求，bbox仅为中间出口；P2待数字准入后做全系统PDS与同路径静态图板测。
- 新B01板测仍0次、两个Git包均缺同构建smsk，当前作为诊断后备，不切换板卡镜像。上游B00与本线程历史位流不同，不合并身份，KEY0五次通过及10分钟稳定性待明确反馈的状态保留。
- [完整审查](../verification/npu/2026-10-22-upstream-update-priority.md)、[机器摘要](../verification/npu/evidence/upstream_update_20261022.json)。原34/12交付文件保持哈希；92既有文件保护中观察到Video译码测试并行变化，保留并单列，本台账只追加。本轮无产品RTL/模型/公共配置修改、PDS、JTAG/串口/Flash、提交或推送；辅助算子新阶段尚未开始实现。


## 2026-10-22 B01独立DDR实际SRAM下载与现场功能通过

- 用户要求先验证远端DDR自检。远端89acc7b包缺smsk，本机以未修改的冻结RTL/FDC与同版HMIC重新构建同构建sbit/smsk；实际下载本地9ababdacf26e…，远端原953172e6…分列，未混用身份。
- 本轮PDS：6572LUT/6422FF/8DRM/2GPLL，125MHz UI slow setup+0.379ns，现有约束满足；83实际I/O全部属性与既有DDR/LED参考一致。保留3195行工具警告，不代表严格外部DDR时序或CDC签核。
- 10:19完成ID00602899核对、SRAM Program/Verify及下载后DONE=1，无Flash/串口。板卡当前为独立B01，原三模式恢复包sbit/smsk哈希重新核验并保留。
- 用户明确“与上述通过灯态一致”“5次均正常”：LED0/2/4/5/6亮、LED1闪、LED3/7灭及KEY0五次恢复通过。本镜像的16MiB九轮DDR功能和重复复位验收通过；九轮每次150994944比较字节为设计计数，结果来源为用户灯态，没有硬件计数转储。
- 十分钟稳定性用户反馈“正在观察，尚未满10分钟”，保持观察中，不推断完成；后续NPU实现等待稳定性反馈。完整图/五点/fabric/CDC/P18/整机门槛继续开放，原B00历史十分钟项不由B01替代。
- [上板记录](../verification/npu/2026-10-22-ddr-board-selftest.md)、[机器摘要](../verification/npu/evidence/ddr_board_selftest_20261022.json)。原34/12交付、283冻结源及上轮审查结果保持哈希；仅新增记录和追加台账，无产品RTL/模型/公共配置修改、提交或推送。


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


## 2026-10-22 Video F4c5d shadow AW 并行译码

- 在 F4c5c 字节使能基础上，AW 握手时锁存160位绝对字地址选择，每字固定四字节写入；AW/W仍独立缓存，原地址/四态/locked/WSTRB检查、B/R保持、健康和owner、ABI及响应拍数不变，无公共配置/FDC变化。
- 固定 `2c9c67f` leaf 的53端口、23输出逐周期四态 miter 已覆盖 reset；普通/-O 各11个正常场景和3个有效编译故障变体通过。故障变体包含错误地址、取消BVALID、reset-only输出差异；inout遗漏也会拒绝。完整默认DUT idle、6组health、3组三模式显示及2723写/2883读通过。
- 完整采显综合：32881 LUT、44678 FF、69.5 DRM；相对F4c5c减少2373 LUT、增加161 FF。core综合setup−1.306 ns仍为负。相同seed/约束布局估计 core setup−2.135 ns、pixel+0.216 ns，较F4c5c core改善0.818 ns；core hold−0.027 ns、recovery−0.954 ns、fast setup−1.306 ns仍未闭合。
- F4c5c原 merged shadow 版本的真实续跑因Route-4022拥塞、Route-0008无法布线退出，未生成最终STA；不外推到其他版本。本轮AW译码版route在第10次迭代后进程消失，最后43247个未布通net，没有routed DB/STA，记为interrupted且不推断原因。F4c5c字节使能版和本轮AW译码版分别保留冻结DB/route身份，布局估计不能替代签核。
- [验证记录](../verification/video/shadow_address.md)、[机器证据](../verification/video/evidence/shadow_address.json)。CPU/NPU交付不阻塞本批；无JTAG/COM/Flash/下载/板测。下一步等待新route最终报告，若仍失败则按扫描输出、reset network和内部guard路径分别处理。


## 2026-10-22 Video F4c5e overlay共享像素边界

- 保留RAW/BOX/AVATAR、16框×5点及13级像素流水，把每lane加减改为共享signed13像素阈值；记录坐标仍signed16，裁切/退化框/点和主框优先级不变，avatar/alpha、ABI及FDC未改。
- 固定2463d01旧RTL，15输出逐拍四态比较；普通/-O各19场景、181704事件、6个编译故障变体通过。覆盖signed16全部65536坐标值、全部lane、边界、模式/消隐/复位和指定X组合。修复测试覆盖缺口及mutation覆写正向dump问题，38份正向dump独立重放并核验全部哈希。
- 同目标PDS综合：独立overlay10637→4641LUT（−56.4%），1645FF不变；完整采显32881→26842LUT（−6039/18.4%），44677FF/69.5DRM，占PG2L100H LUT40.3%。完整快照仅overlay源改变，不是含CPU/NPU的最终SoC资源。
- 像素16场景、renderer14仲裁/6显示、scanout6交接/3扫描和真实C↔RTL采显联动3场景通过；全尺寸像素2440179、scanout3360000逐像素检查。两份早启FULL像素仿真900秒超时原样保留，FULL预算改1800秒后完整通过，小场景仍900秒；时钟/仿真周期/DUT/检查不变。部分外层汇总因无关测试脚本在运行中变化而拒绝，未改写为PASS；最终逐项核验内层真实依赖、工具和输出哈希。
- 同seed4/performance估计连线布局：slow core setup−2.102ns、pixel+0.295ns、core hold−0.027ns，fast core setup−1.565ns。core仅改善0.033ns，fast恶化0.259ns，不能称时序收敛；扫描输出和reset/enable路径仍需处理。新冻结布局已用seed11独立布线，旧AW版保留自身DB和结果，未取得最终routed DB/STA，125MHz仍未闭合。
- [验证记录](../verification/video/overlay_geometry.md)、[机器证据](../verification/video/evidence/overlay_geometry.json)。94项无关非STATUS条目保持；共享台账只追加，提交投影另去除上批重复F4c5d段，保留NPU未提交内容。无CPU/NPU迁入、JTAG/COM/Flash或板测，不改变当前板卡镜像。


## 2026-10-23 Video F4c5f组件复位释放与I/O输出寄存器

- 仅改默认完整采显组件外壳：core/pixel独立两级异步断言/同步释放链，第二沿后释放本域reset，第三沿接受scan/capture；扫描位序、稳态拍数、产品RTL、ABI及CPU/NPU不变。不把stub单域复位测试写成产品CDC复位恢复证明。
- core_scan_o的syn_useioff由native网表转PAP_IO_REGISTER=TRUE，器件映射确认core_output_q[0]实际打包到IOL的OFF；四个同步FF和CLK/D/Q连接保留。原8/25ns、I/O2/0.5ns、uncertainty和16条CDC例外保持，没有新增reset切断或板级pin。
- 普通/-O各12项unit、每轮11个实际RTL场景通过：2250次映射检查、真实默认DUT idle、2723写/2883读shadow、停钟/错相/短脉冲/域间隔离reset，7个有效编译故障变体均拒绝。保留旧实现预期RED和开发时两项失败；独立审查发现的证据绑定缺口已修复，最终重新封存unit/Python/工具/快照/产物与报告哈希。
- 同目标综合26881LUT/44681FF/69.5DRM，比F4c5e多39LUT/4FF。综合快照仅probeRTL/FDC/manifest和生成器变化，产品RTL保持。相同seed4/performance估计连线布局slow core setup−1.720ns（改善0.382）、pixel+1.896ns、fast core setup−0.869ns；slow core setup失败端点11454→1167、TNS−4265.597→−409.002ns。
- slow core hold仍−0.027ns，失败端点2→6、THS−0.035→−0.143ns，不能称时序闭合。最差setup已转到guard的lane[3]→lane[1]/CE，9级、扇出1030、估计连线7.567ns；下一批先拆分该内部选择/错误判定，再做完整route，不把placement或旧未完成route作为最终STA。
- 两份旧seed11 locator仍写running，但日志已停更且无routed DB/STA，保留原文件身份、不推断退出原因。本批无新完整route、CPU/NPU迁入、JTAG/COM/Flash或板测。94项无关条目保持，工作台账只追加，index投影仅提交本段。详见[验证记录](../verification/video/probe_reset_io.md)及[机器证据](../verification/video/evidence/probe_reset_io.json)。

## 连续 RAW 上板主线（2026-10-23，已上板验收）

用户已批准优先交付无需 KEY0 的连续 RAW，随后再接连续 BOX/AVATAR；暂停不阻塞实际板级目标的 LUT/探针优化。
新增独立 `video_live_board`，A/B 双槽在显示 release 后才复用，保留 raw/preview/320×320 BGR NCHW 三分支。
新帧在帧边界替换，允许跳过输入帧；不提前承诺 60 个新帧每秒。板级控制器独占 Video DDR，最终 CPU/NPU 所有权和可见性契约不变。

旧引擎对照在提交第 1 帧后停止更新，新的变化源端到端及板级数字仿真已验证自动换帧、完整像素和复位。
故障测试要求明确首错码，停止新发布并等待已承诺读写排空。专用 UART11 记录捕获/提交/释放/扫描数，UART12 是进行中捕获观察，UART9 是显示观察；不宣称每帧 DDR CRC 读回。
125 MHz/40 MHz 的实际板级目标已通过综合（16121 LUT / 16481 FF / 9.5 DRM），完整尺寸仿真3次提交/96万输出像素通过；最终内部布线时序slow setup/hold +0.049/+0.137ns，fast +2.926/+0.099ns，位流644852dd6321已打包。新增release束34端点两角均通过6ns约束。
连续 RAW 实体板测已通过；初次JTAG线缆列表为空；用户重新连接后，PG2L100H识别及易失Program/Verify通过，首段60秒及一次KEY0后连续114秒健康，欠载/溢出/错误均为0；实测新图30.16fps、输出扫描约60.32Hz。用户确认全屏内容自动更新，单次KEY0后恢复并继续更新。串口已关闭，板卡保持镜像运行；后续连续BOX/AVATAR及真实NPU另行交付。详见 [连续 RAW 记录](../verification/video/live_raw.md)。

## 连续 RAW / BOX / AVATAR 实体交付（2026-10-23）

新增独立 `video_live_mode_board`：沿用800×600、40MHz扫描、125MHz核心和raw/preview/320×320 BGR NCHW三分支；A/B旧槽仍待真实release后才复用。扫描器输出同拍像素身份，KEY1在有效图像SOF按RAW→BOX→AVATAR→RAW循环，pad首像素退休后反馈；叠加不持有旧DDR槽、不新增整帧写回。框/五点和256×256 RGBA贴图均为人工诊断数据，未接真实NPU或CPU统一帧池。

变化帧独立像素/Alpha oracle、完整板壳、命令到达SOF相位、pad退休反馈变异、两次复位及四类UART历史失效检查通过。桥接器215例、共享DDR、原连续RAW、原静态模式和完整NCHW回归通过；故障期间只允许私有scratch填充，错误B/WPRE/native发布检查和QUARANTINE保持。规格书移除“双窗仍为当前实现”的旧进度断言，实际状态以台账和验收记录为准。

前两轮物理失败记录保留；定宽NCHW掩码、去掉故障控制对宽scratch CE的扇出，并为新存活的generation字段补齐原握手6ns约束。最终 `build/video/pds/20261023T042858_495450Z` 内部布线时序通过，slow setup/hold +0.063/+0.129ns、fast +2.911/+0.097ns，recovery/removal均通过。16770LUT /18150FF /73.5DRM，其中64DRM为测试纹理；release34、generation1、MODE3、素材2个存活CDC端点两角均通过6ns，原数据库及报告哈希保持。

位流 `50ea2b124300` 已Program/Verify，未写Flash。用户确认完整RAW连续更新，三次单独KEY1后BOX、AVATAR和返回RAW均正常且底图保持动态；一次KEY0后恢复完整动态RAW。持续串口共514包，复位后连续健康87.000秒，新图30.1548fps，欠载/溢出/错误为0。串口已关闭，开发板保持新镜像运行。详见[连续三模式记录](../verification/video/live_modes.md)和[机器证据](../verification/video/evidence/live_modes.json)。本阶段实体交付关闭；下一步接真实NPU结果与正式CPU/共享DDR契约，不能以本诊断测试替代整机推理验收。


## 2026-10-25 B02远端原始程序实际上板通过

- 用户指定B02。最新b7ce46a已fetch并导出605文件冻结快照；原始发布sbit SHA33c8ca921095…、包7项和四验证摘要哈希一致，84源管脚含UART C24复核。未修改产品或本机重建。
- COM12先启动记录，再执行SRAM Program与下载后DONE=1；远端包无smsk，配置读回Verify未执行，未借用掩码、未Flash。功能由实际UART CRC/身份/分项日志验收，保留原始字节及切片边界。
- 首次及一次实体KEY0重启两轮均VERIFIED_PASS：16项全PASS，executed/passed=FFFF，failed/blocked=0000，协议及解析错误0，epoch 1→3→4符合。每轮DDR实际读写各151034112B、输入echo307200B、小卷积及32组回归通过；两轮完整记录最终结果后至少10秒。
- 用户确认首次4F/5F灯态、按住KEY0全灭、松开后恢复4F/5F。两次启动各自日志独立，KEY0轮无再次下载。B02是平台和小算子实板验收，完整YuNet/五点/生产共享fabric/严格CDC时序/30fps仍开放。
- 记录：D:/FPGA/TriHaRiscv-main/docs/verification/npu/2026-10-25-b02-board-selftest.md；摘要evidence/b02_board_selftest_20261025.json。原始证据D:/FPGA/TriHaRiscv-npu-operator/build/npu/b02_20261025/。B01历史10分钟项不推断关闭，未提交推送。


## 2026-10-28 技术文档采用SRAM CPU实物结果

按用户要求更新主工程LaTeX报告，仅涉及CPU说明、CPU性能/流水分析、附录CPU复现及README。采用已通过100MHz后布线的独立SRAM调试镜像：3.055365628 CoreMark/MHz、CPU核6139 LUT、0.049769761 CoreMark/CPU LUT，setup最差+0.366ns、hold最差+0.034ns；固件历史5933-LUT元数据与原发布版效率单独说明。

正文三幅图改为hash核对后的38位真实硬件list/matrix/state窗口，各1024拍，图中展示前48拍；Cache/DDR板测2.497435168/MHz和数字模型0.717562 WB IPC分开保留。新增六个PDF/SVG矢量文件及 docs/verification/cpu/sram_report_2026-10-28.json 绑定，未混用Cache事件或整段板测IPC。独立检查确认234个其他报告输入及CPU小节之外正文不变。

现有 latex/scripts/build.ps1 成功编译48页技术文档.pdf，无LaTeX错误、未定义引用或overfull hbox；按约定未渲染、预览PDF。本批没有新仿真、综合、PNR或板卡操作，NPU/Video内容未改。

## 2026-10-29 技术文档改用最大化软件原生截图

按用户要求，离线打开已冻结的list/matrix/state硬件WDF副本，在最大化的Fabric Debugger 2022.2-SP6.4中放大入口附近波形，保存三张2560×1392完整截图。正文改用原像素裁剪PNG，保留原生信号名、游标PC和采样刻度，不重绘；原生游标0对应CSV索引1。原始DPRJ/WDF/CSV及上一版矢量图证据均未改。

更新主工程技术报告03-results、06-appendix及README；性能、时序和资源数据不变，241项其他报告输入及目标段落之外正文核对不变。现有build.ps1成功编译48页PDF，无LaTeX错误、未定义引用或overfull hbox，未渲染或预览PDF。截图、裁剪逐像素一致性和输出哈希见主工程docs/verification/cpu/sram_report_screenshots_2026-10-29.json；完整截图与加载记录位于CPU工作树build/cpu/native-report-screenshots-20261029-v1/。

本批无新硬件采样、下载、仿真或实现，NPU/Video内容不变。本次原生截图替换完成，无待处理项。

## 2026-10-29 CPU性能叙述调整为TCM与L1 Cache实测

按用户PDF批注及随后澄清，CPU性能只并列TCM本地存储与L1 Cache＋板载DDR两种实际板测配置，不纳入DDR直访历史版本。明确TCM由32KiB本地SRAM实现、L1 I/D各16KiB；保留-O2/5000次、3.055365628与2.497435168 CoreMark/MHz及对应资源/时序结果。以最高分TCM配置讲解DebugCore加载、入口触发与原生波形采集，三张最大化原生截图及全部原始采样未变。

正文02-system、03-results、06-appendix与README已调整，48页PDF重新编译通过，无LaTeX错误、未定义引用或overfull hbox，未渲染预览。核对两个实测结果及缓存版原始UART绑定，47个其他报告输入、NPU/Video及非CPU结果不变。当前文档输出绑定见主工程docs/verification/cpu/memory_evaluation_report_2026-10-29.json；此前截图索引继续提供图像和采样来源绑定，其旧PDF哈希属于历史输出。

本批仅修改文档，无新增仿真、综合、布线、采样或板卡下载。本次批注处理完成，无待处理项。

## 2026-10-29 插入用户提供的两张CoreMark原始串口截图

两张原始PNG按字节复制到主工程docs/technical-report/figure/cpu-tcm-coremark-uart-original.png及cpu-l1-cache-ddr-coremark-uart-original.png，尺寸1087×765和1076×840，均未裁剪、重绘或修改文字。CPU性能小节插入两图并引用，说明TCM图中5933-LUT固件历史打印值与调试构建6139-LUT分母的区别，以及整数秒字段不用于精确评分；原有性能数据及其他章节不变。

原文件与docs副本字节一致，原有正文移除新增段落后逐字一致；现有build.ps1成功编译49页PDF，无LaTeX错误、未定义引用、overfull hbox或浮动体过高警告，未渲染预览。原图、正文和输出哈希见主工程docs/verification/cpu/coremark_uart_screenshots_2026-10-29.json。无新采样、下载、仿真或实现；本次插图请求完成。

## 2026-10-29 三张原生波形图移除鼠标指针

按用户要求，用现有Fabric Debugger离线打开冻结WDF的新副本，在最大化窗口中重截list/matrix/state。截图前把鼠标移至控制台，确认鼠标与蓝色光晕均在文档裁剪区域外；仅按原像素裁剪，未涂抹、修补或重绘。三幅docs/technical-report/figure/cpu-sram-*-native.png已替换，旧完整截图保留，新完整截图及加载记录在CPU工作树build/cpu/native-report-screenshots-20261029-v2/。

原始DPRJ/WDF/CSV、CPU性能正文及用户提供的两张串口原图哈希不变。README和附录仅更新截图来源记录；实际49页PDF重新编译通过，无LaTeX错误、未定义引用或overfull hbox，未渲染预览。当前图形、逐像素裁剪和PDF绑定见主工程docs/verification/cpu/sram_report_screenshots_2026-10-29_v2.json。没有新采样、下载或实现；本次请求完成。

## 2026-10-29 附录B去除重复性能说明并补齐B.3

按用户要求参考D:/RV-CPU/TriHaRiscv/复赛文档/CICC1002692+分区决赛+技术文档附录B的组织方式，移除当前附录的CoreMark观测/复现、跑分元数据和重复板上采样说明，相关内容保留正文。B.2改为Windows ModelSim SE-64 2020.4/GCC15.2测试平台与判定规则，B.3补入RV32IM/CSR覆盖分类、V01至V10实际定向记录、官方测试集统计边界及Windows复现命令，B.3编号已核对。

逐项核对七项正常记录及三项预期失败的result和原始stdout日志哈希，保留负例FAIL；乘法2730次有效结果/904次保持、前递1032项、除法308组操作等使用原始日志值。旧五级文档134/134和165/165官方通过数未移用于当前六级核；当前核官方riscv-tests/ACT4全量绑定记录仍需补充，本轮未声称全量ISA或退休证明。

当前51页PDF编译通过，无LaTeX错误、未定义引用或overfull hbox，未渲染预览。正文性能、五张原生截图及附录B.4以后内容保持；检测到并保留其他任务的02-system/FIFO图源/page10图更新，未覆盖。当前文档、V01至V10及日志来源绑定见主工程docs/verification/cpu/appendix_b3_isa_2026-10-29.json。未新跑仿真、综合、布线或板卡操作。

## 2026-10-29 CPU模块级LSU与Cache功能仿真

在既有CPU工作树完成LSU端口测试，18次访问、220项检查通过，错误数据负例被检出。复核三组Cache正例及负例的当前输入与原始输出哈希，复用已完成的Windows ModelSim结果，未重复运行。四组正例合计3014/3014项检查，四组错误数据负例均按实际自检失败拒绝；不修改生产RTL，不进行PDS或板卡操作。

主工程技术文档B.3新增LSU、I/D Cache、写回维护和响应重叠统计及四张2553×1440原生ModelSim截图，无鼠标光标、裁剪或重绘。60页PDF编译通过，无LaTeX错误、未定义引用或Overfull警告，未渲染预览。新增提交包docs/verification/cpu/module_support/cpu-memory-support-2026-10-29.zip约2.45MB，154项条目逐项哈希核验；汇总见docs/verification/cpu/module_memory_waveforms_2026-10-29.json。各模块下层由独立内存模型服务，不作为共享总线、物理DDR或整核系统验收；后续B.4继续整核固件、异常/中断及Cache子系统联调。

## 2026-10-29 CPU B.4整核系统仿真第一批

Cache开启的最小整核固件完成1277项检查、26356周期、14次读、35次写和3次受控异常；关闭Cache对照完成809项检查。独立路由完成476项检查，覆盖片上地址隔离、Cache命中和共享区旁路、刷新、错误锁存与复位恢复。下层数据错误负例在固件退出检查处失败，退出码1；正例均返回0。路由测试台原有全量刷新1000周期上限和写穿可见性预期与当前写回Cache不符，本批仅修正测试台预期并复测，生产RTL未修改。

整核WLF/VCD和日志保存在CPU工作树build/cpu/wave-system-runtime-20261029T110017121207Z/，原生ModelSim截图插入技术文档B.4，窗口172700--173650 ns，显示平台故障、三次异常计数、mcause/mtval、mepc加4和MRET返回。Cache开启下的三次中断交互另有原生WLF/VCD、事件日志和截图，摘要见docs/verification/cpu/system_support/cache_irq_run_2026-10-29.json。63页PDF重新编译通过，无LaTeX错误、未定义引用或Overfull警告，未渲染预览。物理/板级验证仍未在本批声称完成。

## F4c3d 高价值系统级波形

四个短场景已在 Windows 原生 ModelSim 中生成原生 Wave 波形，并保留完整 WLF/VCD：采集重武装、显示槽所有权、共享 DDR 背压和采显联合。四个入口均通过，关键统计分别为 7 次采集/重武装、槽状态 155 项检查、12 读/12 写且最大等待为 0，以及 7 个任务/7800 像素/13 次光栅/欠载 0。联合场景在 2 ms 窗口核对四帧提交/释放和共享读写重叠；完整 13 次光栅及全部哈希仍以机器证据为准。

四张无鼠标指针截图、WLF/VCD、ModelSim 工具哈希和冻结输入绑定见 [高价值波形证据](../verification/video/evidence/video_high_value_waveforms_20261030.json)，结果摘要见 [验证记录](../verification/video/high_value_waveforms_20261030.md)。技术文档附录已增加四类场景表和四张波形图。本批不运行 PDS、不下载板卡，不把数字背压模型或空检测前提写成物理 HDMI、整机时序或真实 NPU 验收。


## 2026-10-30 系统互联与存储仿真

完成主工程现有 CPU→Video、CPU→NPU 和 Video 共享 DDR 联测。CPU→Video 单/双发射 6 个正例及 2 个负例通过；CPU→NPU Dense U8、DW S8 的轮询/中断 4 个正例通过；Video 共享 DDR 回归通过。两份原生 ModelSim WLF 和结果哈希登记在 docs/verification/soc/system_interconnect_storage_20261030.json。

本批验证了控制面路由、AXI 独立通道、背压保持、DMA 几何和完成顺序。主工程当前仍没有正式 CPU/NPU/Video 共享 fabric 或缓存一致性模块，因此跨主端可见性、CPU fence/cache maintenance 和物理 DDR CDC 仍开放，不能把本批结果写成整机互联验收。


## 2026-10-30：B03 主工程集成调研与规划

用户要求获取 keep-s/npu_zgtc 最新状态并在本主工程开展集成，当前先完成规划。通过系统代理和现有 Git 身份 fetch/ls-remote 确认上游 main 为558280b（源码检查点580174a）；已核对 B03 整网/FPGA后处理、最新面积审计与尚未完成的物理/板测出口。用户确认采用 NPU 整网及解码/NMS、CPU 管理帧/头像/显示的职责。

[设计提案](../superpowers/specs/2026-10-30-b03-main-integration-design.md)与[阶段计划](../superpowers/plans/2026-10-30-b03-main-integration.md)明确复用现有320×320 BGR NCHW、唯一HMIC/AXI128桥及同帧显示，补共享fabric、100/125MHz CDC、帧级ABI、生产发布和全局恢复。首阶段完成来源/资产准入及统一资源预算；bbox先作中间验收，五点与最终性能要求保留。

本轮仅远端/源码/证据审查与文档落盘，没有导入产品RTL、修改ABI、执行RTL/PDS或板测。新发现：runtime清单68项在提交的包目录缺失，需重建/核SHA；最新163候选缺同Graph六图统一证明；B03候选55663 LUT/90.5 DRM尚无CPU/Video统一预算，私有scope0不等于生产发布。上游具体数值是引用证据，未在本机重跑。来源和哈希见[审查JSON](../verification/npu/2026-10-30-upstream-integration-audit.json)。原Video交付与技术报告修改保持原位。

## 2026-10-31：CPU 后处理与资源收敛

最终应用路径已改为“B03 整网写 heads，CPU 解码/NMS，CPU 提交 BOX 记录”。板级默认保留完整 CPU 配置，`ENABLE_HARDWARE_POST=0` 时综合裁掉 FPGA decode、sort、ROI 和结果记录写回模块；NPU 仍执行真实图和真实 heads，CPU 使用 B03 lookup table、0.6 阈值和 IoU 0.3 生成真实人脸框。无五点关键点时点字段继续保持零。

主机/RV32 `FACE_AVATAR_PASS checks=3896`、显示 MMIO 回归 `RECORD_MMIO_PASS` 通过，独立 CPU heads smoke 通过。完整 CPU 综合基线为 58886/66600 LUT；板级默认切到可选的 `MINIMAL_CONTROL_CPU=1` 后，再用 primary-box overlay 裁剪显示比较器，综合降至 53468/66600（80.3%）、寄存器 49955/133200（37.5%）、DRM 76/155（49.0%），完整 CPU 仍可用参数恢复。该显示裁剪不减少 NPU 算力和输入吞吐，只保留当前最小展示所需的 primary 框。约束审查无 rejected 时钟项。已补齐 DDR PHY 站点和 `mem_*`/`ref_clk_*` 约束；80% 资源单 seed route 已进入详细布线，尚未声称布局布线或板上时序通过。

## 2026-10-31：NPU 诊断网络裁剪与单 seed route 监控

在保持 B03 算术、输入/输出格式和 CPU heads 解码不变的前提下，给 dense APM 阵列和 depthwise 阵列增加 `ENABLE_DIAGNOSTICS` 综合参数。板级 CPU-post 配置关闭每拍返回一致性、溢出归约和最低 lane 诊断树；完整诊断配置仍可恢复。B03 frame runner、asset 回归和导入回归通过，显示 MMIO 回归通过。

板级综合结果从 53468 LUT/49955 FF 降至 52544 LUT/48866 FF/76 DRM（78.9% LUT、36.7% FF、49.0% DRM），综合输入快照和产物分别保存在 `build/video/pds/20261031T090816_033912Z` 与 `build/video/pds/20261031T091657_906206Z`。随后对 52544-LUT 候选启动单 seed route，工作目录为 `build/video/pds/20261031T092657_451272Z`；运行约 20 分钟仍停留在 `place_route` 前段，没有 routed STA、`unrouted=0`、`All Constraints Met` 或 bitstream，已主动停止。该候选仍不能宣称物理时序通过，下一步需继续压 NPU 并行数据路径后再布线。
## Final application integration (2026-10-30)

- Added the board-level `triha_face_board_top` entry. It connects HDMI RX/TX,
  the single DDR3 owner, capture/preprocess, `triha_face_system`, and HDMI
  scanout in one explicit production source list.
- Added `fpga/pg2l100h/project/triha_face_board.json` and the top-level pin
  constraint set `fpga/pg2l100h/constraints/triha_face_board.fdc`.
- The board target is BOX-only. The checked-in B03 model has no landmark
  branch; point/landmark fields are zero and AVATAR remains disabled until a
  real model and asset package are supplied.
- The digital final-application regression remains the acceptance check for
  CPU frame management and same-frame display. It uses a native DDR byte
  proxy and does not establish PDS or board timing.
- The formal `build_pds.py --target triha_face_board --stage synth` entry was
  exercised. PDS reached RTL analysis and set `triha_face_board_top` as the
  top, then stopped on the current CPU source set (`biriscv_alu.v` and related
  files) because the installed PDS Verilog front end rejects the SystemVerilog
  syntax used by the admitted CPU. No synthesis, mapping, timing or bitstream
  result is claimed from this run.

## Minimal face-box board demonstration (2026-10-31)

The first board deliverable now defaults `triha_face_board_top` to
`DEMO_BOX_ONLY=1`. It uses the real HDMI TX PLL/I2C/timing path and renders a
visible 800x600 BOX record shape; DDR and HDMI RX pins are held inactive in
this resource-bounded demonstration. The preserved CPU+B03 full application
is still selected with `DEMO_BOX_ONLY=0`.

Formal PDS synth and bitstream both pass. The verified bitstream package is
`build/video/releases/triha_face_board_5eea0d2922fb/` with sbit SHA256
`5eea0d292fbeaff00fd65b376b6386feb3674a94fa81667294b5bbd7a3e6520` and
matching verify mask. Synthesis uses 281 LUT, 225 registers and 0.5 DRM;
internal routed timing is marked met. This is a display-function and BOX
shape demonstration, not a claim of live B03 inference or physical board
program/verify. The full CPU+B03 path remains over the PG2L100H LUT budget
(79,167/66,600 from the previous formal run) and remains the next closure
item.

## NPU CPU-post resource/timing convergence (2026-10-31)

The production profile now uses B03 for the full network and head writes, while
the CPU decodes heads, applies threshold/IoU filtering, and submits the BOX
display record. Hardware decode/sort/NMS/ROI/result-writer logic remains disabled
for this minimum face-box application. The dense APM array is reduced to
`M_LANES=8`; the board top passes that profile through the SoC and NPU service.

The two-frame native B03 proxy run passed with 79/79 operations, independent
HEAD/result checks, and shared task/op/epoch stability. A dedicated `M_LANES=8`
two-frame run also passed; its model cycle count increased as expected from the
reduced spatial parallelism. Synthesis result
`build/video/pds/20261031T112725_557724Z` used 49,632 LUTs (74.52%), 48,702
registers (36.56%), and 74 DRM (47.74%).

Three NPU reset nets with fanout above 10,000 were given bounded replication
attributes. The follow-up synthesis
`build/video/pds/20261031T133843_830059Z` has no warnings for those reset nets
and uses 49,921 LUTs (74.96%), 48,702 registers, and 74 DRM. One-seed routed
placement improved from about `-1.811 ns` to `-1.686 ns`, but routing still
reported about `-4.691 ns` before detailed route completion and was stopped;
there is still no `unrouted=0`, routed WNS/TNS pass, `All Constraints Met`, or
bitstream evidence for the live B03 path. The next optimization target is the
remaining high-fanout control/data nets, especially the video-side `dma_base`
path and residual NPU control/reset nets, before another P&R attempt.

## DMA descriptor fanout reduction (2026-10-31)

The NCHW input DMA now registers its descriptor base when a frame, plane, or row
changes. This removes the flattened combinational `row_base + plane` mux from
the DMA request path while preserving the row/plane address sequence. The full
NCHW DMA regression passed. Synthesis
`build/video/pds/20261031T144128_284603Z` reports 49,610 LUTs (74.49%), 48,728
registers (36.58%), and 74 DRM (47.74%); the previous `dma_base` fanout warnings
are gone.

A single-seed P&R reached global `unrouted nets = 0` at iteration 33 in
`build/video/pds/20261031T145228_761769Z`. Detailed routing remained at 48,541
unrouted subnets after iteration 13. Placement WNS was `-2.330 ns` and the
pre-global-route report was `-4.191 ns`; the run was stopped before routed STA,
so no routed WNS/TNS, `All Constraints Met`, or bitstream claim is made.

The CPU admission manifest now records the parameterized `triha_core.v` as a
reviewed working-tree delta with its original Git baseline hash; this keeps the
default CPU configuration unchanged while admitting the board's
`MINIMAL_CONTROL_CPU` parameter. The face-system testbench hierarchy was updated
to the compact display MMIO instance. Compile-only integration passes. A full
face-system run starts real capture and B03 execution (capture slots complete and
operator 0 reaches 2,035,035 cycles), but the 300-second bounded run does not
finish the 79-op frame and is recorded as a simulation timeout rather than a
functional pass.

## Current resource-bounded baseline (2026-11-01)

The board profile now uses `M_LANES=4`. This keeps the fixed 16-row accumulator ABI
and all 79 model operations while serializing the dense output tiles further. The
result is `build/video/pds/20261031T155456_149654Z`: 48,878 LUTs (73.39%), 48,684
registers (36.55%), 73 DRM (47.10%), and 79 APMs (32.92%). Compared with the
8-lane baseline, this saves 732 LUTs, 32 APMs, and one DRM; it has not yet been
through placement or routing.

An additional trusted-graph experiment was rejected after synthesis increased the
mapped design to 48,935 LUTs. The graph source and admission manifest were restored
to the 4-lane baseline. Given the remaining 73% LUT occupancy and the previous
detailed-route runtime, the next work item is a structural reduction in the NPU
vector/input path; another full route is deferred until that reduction produces a
clear front-end gain.


## 2026-11-01: Quantizer serialization and two-lane dense profile

The minimum board profile now uses an exact one-physical-lane Q8 quantizer
(`b03_quant8_tdm1`) behind a parameterized selector; the default two-lane
quantizer remains available for non-board users. The external mask, tag, error,
and output ordering ABI is unchanged. Compile-only face-system integration and
source admission pass.

The first one-lane synthesis measured 48,687 LUTs (73.10%), 48,437 registers
(36.36%), 73 DRM (47.10%), and 75 APM (31.25%). The LUT reduction was only 191
against the 4-lane baseline and introduced high-fanout quantizer control nets,
so the main resource gain comes from dense serialization rather than the
quantizer itself.

The board dense profile was then reduced from `M_LANES=4` to `M_LANES=2` while
keeping the fixed 16-row accumulator ABI and all 79 operations. Synthesis
`build/video/pds/20261101T014928_479909Z` reports 48,205 LUTs (72.38%), 48,414
registers (36.35%), 72.5 DRM (46.77%), and 59 APM (24.58%). This saves 482 LUTs
and 16 APMs versus the one-lane-quantizer/4-lane-dense result. No placement,
routed timing, or bitstream result has been claimed for this candidate yet.


The single-seed route monitor for this 2-lane candidate was
`build/video/pds/20261101T020153_597477Z`. Placement reached about -1.94 ns
worst slack before routing, but detailed routing still had 66,653 unrouted
subnets at iteration 4 (115,701 total subnets); the run was stopped to avoid
another long low-yield route. There is no routed STA, `unrouted=0`, constraint
pass, or bitstream evidence for this candidate.


## 2026-11-01: Trusted input repair and application-profile audit

The earlier trusted-input candidate was not functionally admissible: bypassing
PARAM_BOUND also bypassed publication of shadow_valid. A new trusted-mode test
failed on the empty mask before the fix. The mask is now published atomically
at successful parameter KEY_SAVE; transport errors, cancellation, epoch and bank
checks remain. The default 34-case input regression retains its cycle comparison
against the frozen upstream reference. Trusted-mode scoreboards cover the same
parameter/A/B/DW data, with only the approved content-invalid cases admitted.

The old route at build/video/pds/20261101T031831_616772Z was cancelled because
its source had that functional defect. Its partial route is not timing evidence.
Also, ddrphy_sysclk is the actual 125 MHz CPU/NPU core clock, not an external-only
PHY exception. Its negative setup slack must be resolved. Earlier Python runner
unit tests and default-profile face-system compilation did not establish trusted
board-profile frame correctness.

The repaired trusted profile passed two complete zero/pattern frames in
build/npu/board_heads2_20261101: 79 preflights and 79 real operations per frame,
all 26,368 head bytes equal to the immutable golden data, no hardware POST,
and no outstanding transaction debt. Source hashes are frozen in result.json.
This is NPU/native-memory-proxy proof, not CPU/video, routed timing or board proof.
Synthesis 20261101T033530_744971Z measured 45,615 LUTs (68.49%), 47,485 FF,
72.5 DRM and 59 APM, with core setup estimate -2.580 ns.

The vector transfer descriptor is now registered before boundary/tag validation.
The 66,051-case boundary/CE/cancel test rejects the old same-cycle implementation
and passes the registered implementation. Two-frame regression
build/npu/board_heads_pipeline_20261101 preserves every head byte and transaction
count; frame cycles increase from 16,826,075 / 16,809,495 to
16,831,475 / 16,815,020 (about 0.033%, including proxy stall variation).
The modelcycles diagnostic is zero in this trimmed profile and is not used for
performance claims. Vector-path synthesis saved 78 LUTs but exposed a worse reset
feedback path (-2.951 ns); it was not sent to routing.

Internal input receipt accounting now uses the capacity predicate under the
sequential reset branch, while public ready remains qualified by interface reset.
The first stage passed both 34-case input suites and reduced synthesis to
45,359 LUTs (68.11%), core estimate -1.888 ns. A further equivalent ready-path
simplification is being checked; no routed timing closure has been established.

The application audit found incorrect CPU head halfword strides and the wrong
lookup-table column for width/height. The corrected CPU decoder reads packed
16-bit heads, uses the already-stride-scaled exponential extent, retains subpixel
coordinates until ROI clipping, and keeps the strongest 64 candidates before
16-box NMS. It emits FP32 score bits using integer arithmetic. Independent host
cases include three frozen empty heads, three scales, odd/even candidates,
fractional boxes, a late strong candidate, overlap suppression and score cutoffs.
The old driver produced false boxes on the zero fixture. The CPU decoder remains
a bounded Q16/pixel-ROI implementation; this does not assert equivalence to the
full upstream Q40/model-coordinate NMS for every possible scene.

The face-system runner now has --board-profile, matching trusted input, CPU POST,
two dense lanes, one quantizer lane, disabled preview/row cache, minimal BOX and
the existing board CPU profile. Compile elaboration exposed a missing
explicit display_box_only source, now included. Runtime exposed another integration
mismatch: preview DMA is disabled but capture MMIO/software still require full
preview counts (protocol error 0x0c). This must be fixed before board admission.
The top-level CPU configuration has not been reduced in this batch.

## 2026-11-01: CPU application, real boot assets and natural-face validation

The preview capability and CPU-post MMIO completion format mismatches are fixed.
`build/soc/face_system-20261101T042618_814181Z` passes the actual CPU application
with zero input: 43,427,258 cycles, four capture requests, two NPU/CPU results,
two display records/commits, one release/reuse and two complete pixel frames.
This run preloaded model assets and did not demonstrate a positive face.

The board target now enables the fixed-range model loader, receives UART on
vendor-verified B24 and transmits ACKs on C24 at 115200 8N1. CPU application
admission requires the model seal; TX remains available for final-packet retries.
`build/soc/boot_uart-20261101T043614_136337Z` passes 265 UART checks and 1,966
loader checks each with direct-byte and actual UART-wire transport. Full frozen
assets pass six segments/6,916 packets through the real loader and shared DDR
bridge in `build/soc/face_system-20261101T050522_122159Z`; all DDR bytes match
before seal and the CPU then enters its first capture request. Memory remains
a simulation storage proxy, not a physical DDR test.

The host uploader `scripts/soc/upload_face_model.py` audits asset hashes without
opening hardware unless `--port` is supplied. Its six host tests pass. Audit
`build/soc/model_upload-20261101T050037_099881Z` covers 1,770,496 payload bytes;
the 115200-baud minimum wire duration is 170.50 seconds. No serial upload or
board download has occurred.

A new independent natural-face fixture in `build/npu/face_fixture_20261101`
uses the hash-recorded OpenCV 4.10 Lena sample and frozen integer reference.
It predicts one face: candidate 902, ROI (349,215,166,257), FP32 score bits
1063575960. The CPU host decoder matches that record. This is a new fixture,
not a recovered historical WIDER case. The actual two-frame CPU/capture/NPU/
display regression with full model boot is running in
`build/soc/face_system-20261101T051349_433163Z`; first-frame HEAD/result/record
checks have passed, but full completion is still pending at this update.

Enabled-loader synthesis `build/video/pds/20261101T050627_702707Z` uses the
actual application ELF: 46,945 LUT (70.49%), 50,130 FF and 73 DRM. Core setup
estimate is -2.126 ns. The preceding `20261101T050242_884004Z` run failed on an
unresolved internal UART pin constraint; the current constraint covers only
the asynchronous RX pad, whose sole sink is the first synchronizer register.
The worst current core path is NPU reset feedback through quantizer readiness
to layer state, so CPU configuration is unchanged. No new route or timing
closure is claimed.

The standalone boot packet RAM helper passes 1,213 checks in
`build/soc/boot_uart-20261101T051747_103925Z`. Independent synthesis
`build/soc/boot_buffer_synth_20261101` maps it to 9 LUT, 132 FF and one DRM18K
(0.5 DRM36K). Integration into the loader is pending the active frozen run.
The narrowed AXI address predicate passes 2,359,296 known-bit comparisons,
but the new X-address test correctly rejects the current implementation in
`build/soc/arbiter_legal_x_red_20261101`; conservative unknown-bit rejection
must be restored before final admission.

## 2026-11-01: Positive-face full-system PASS and additional RAM conversion

The complete natural-face run `build/soc/face_system-20261101T051349_433163Z`
passed with unchanged frozen inputs and clean simulator diagnostics. It loaded
all model assets through the real loader, checked captured RGB and preprocessed
input bytes, checked both 26,368-byte NPU HEADs, checked the CPU face record,
and checked two full 800x600 source-plus-box pixel frames. Final counters:
47,572,058 cycles, captures=4, requests=4, results=2, records=2, commits=2,
releases=1, reuses=1, cpu_reads=4,296, nativeAW=91,016, nativeAR=358,483.
The expected positive box is (349,215,166,257). This is actual CPU/RTL/native
storage-proxy evidence, not a physical HDMI/DDR/board demonstration.

The boot packet block RAM is now integrated. Expanded UART/loader regression
`build/soc/boot_uart-20261101T053425_647934Z` passes UART=265, buffer=1,213,
and loader=2,066 checks in both direct and UART-wire modes, including parser
timeout/framing recovery and irrevocable AW/W retirement after an RX error.
`build/soc/face_system-20261101T053455_541912Z` passes full six-segment model
admission in 7,755,382 cycles. Extra packing cycles occur only during boot;
they are negligible beside the roughly 170.50-second UART wire-time minimum.

The AXI narrowed-address predicate now rejects unknown middle address bits.
`build/soc/arbiter_legal_x_green_20261101` passes 2,359,301 legality cases,
two/three-master scoreboards and actual shared bridge/fabric checks. The failed
X-bit regression remains preserved as the red case.

Reset-independent private quantizer capacity now drives layer sequential
accounting under its reset branch. Public quantizer handshakes remain qualified
by reset. `build/npu/quant_capacity_main_green_20261101` compares the previous
hash-checked implementation cycle by cycle: 40,000 checks for each one/two-lane
profile, with CE, clear, reset, random data and long stalls. No arithmetic or
transaction latency changed. The production import manifest retains upstream
hashes and explicitly identifies these local derivatives.

Combined boot-buffer/quantizer synthesis `build/video/pds/20261101T053455_594394Z`
measures 46,305 LUT (69.53%), 48,210 FF, 73.5 DRM, and core setup estimate
-1.827 ns. The remaining worst path passes from command acceptance into the
NPU read-response qualification; this is not acceptable routed timing evidence.

Two further optimizations are now applied and under combined revalidation:

- The shared DDR bridge expected-write cache uses two synchronous half-word
  block-RAM banks. The standalone same-fixture mapping drops from 3,739 LUT /
  3,369 FF / 0 DRM to 874 LUT / 489 FF / 4 DRM. Both old and new versions pass
  215 byte/fault scenarios in exactly 133,784,000 ps. Main-source evidence is
  `build/video/bridge_storage_main_20261101`; mapped candidate evidence is
  `build/video/bridge_storage_candidate_synth_20261101`. No transaction cycle
  is added. Final board-level resource savings must come from the new synthesis.
- The NPU block service keeps default same-command-cycle response support for
  general users, but the actual SoC connection disables that bypass because
  its AXI adapter registers read/completion responses. `registered_block_main_20261101`
  passes 33 adapter checks and 86 block checks with unchanged transaction and
  cycle counts; the adapter test also asserts no command-ready/response overlap.
  `arbiter_bram_fabric_20261101` passes the shared-memory regression with the
  new DDR bridge storage.

The intermediate full-system run `face_system-20261101T053522_639068Z` was
deliberately terminated at roughly 23 million cycles to combine these changes;
its nonzero exit and `superseded.json` are retained, and it is not a PASS.
The combined natural-image regression is `face_system-20261101T054415_775926Z`;
the corresponding synthesis is `build/video/pds/20261101T054415_781459Z`.
Both are pending at this update. CPU configuration and operating clock remain
unchanged. No new route, bitstream or physical-board PASS is claimed.

Read-only scan `build/video/jtag_scan/20261101T053649_452352Z` found no JTAG
cable/PG2L100H; serial inventory showed no board USB serial port. The user
confirmed that engineering and timing should finish first, with hardware
connection later. Do not repeat hardware scans until that changes.

The combined synthesis `build/video/pds/20261101T054415_781459Z` has now
completed: 43,038 LUT (64.62%), 45,321 FF and 77.5 DRM (50%). This saves
3,267 LUT and 2,889 FF relative to `20261101T053455_594394Z`, using four
additional DRM. Core synthesis setup estimate is still -2.148 ns; the worst
path is now CPU fetch-FIFO read pointer through instruction decode/issue into
CSR exception state. These are synthesis estimates, not timing closure.

An isolated evaluation enables the CPU's existing extra decode stage without
changing cache, predictor, ISA, issue width or clocks. The main wrapper remains
unchanged while the complete natural-image run is active. Candidate evidence:
`build/cpu/decode_stage_eval_20261101/project/build/cpu/isa-20261101T055147745696Z`
passes all 103 ISA programs; `squash-20261101T055147806360Z` and
`cache-soc-irq-20261101T055334701600Z` pass wrong-path and cache/IRQ checks.
Candidate synthesis `build/video/pds/cpu_decode_probe_20261101` is pending.
These isolated results are not production CPU admission or a performance benchmark.

The installed PDS can resume mapping and single-seed placement from synthesis
ADF (`build/video/place_resume_smoke2_20261101`) and report timing from placed
ADF (`build/video/place_timing_smoke_20261101`). This allows placement/path
screening before committing to full routing. Placement timing is still an
estimate; final acceptance requires actual routed setup/hold and other checks,
zero unrouted nets, and separate physical-board acceptance.

The combined natural-image run `face_system-20261101T054415_775926Z` now
passes with unchanged inputs and zero simulator errors/warnings: 51,716,858
cycles, captures=4, requests=4, results=2, records=2, commits=2, releases=1,
reuses=1, full_pixel_frames=2, cpu_reads=4,296, nativeAW=91,476 and
nativeAR=366,236. It covers the boot/bridge BRAM, quantizer capacity and
registered-response optimizations together. It still uses the native DDR
storage proxy, and the production CPU still has EXTRA_DECODE_STAGE=0.

The isolated CPU extra-decode synthesis passes and verifies its input hashes:
43,259 LUT (64.95%), 45,434 FF, 77.5 DRM and 59 APM. Core setup estimate is
-2.088 ns; the leading path moved to video capture job-clear/control followed
by the source-coordinate carry chain. The extra stage alone does not close
timing. Single-seed performance placement `cpu_decode_place3_20261101`
completes in 434.6 seconds including mapping, but its final optimizer worst
slack is -4.502 ns. No routing was launched.

Important PDS qualification: the independent `report_timing` command accepts
a placed ADF, but reports zero delay for unrouted interconnect. The resulting
positive core number is not a usable placement-delay estimate or timing PASS.
Also, adding FDC beside that command did not replace constraints embedded in
the ADF. The baseline and CDC report experiments under `cpu_decode_place3_20261101`
must not be used as closure evidence. Fresh synthesis from compiled ADF does
apply updated FDC, independently checked with `resynth_constraint_smoke_20261101`.

Two isolated follow-ups are pending: `capture_sum_probe_20261101` preserves
independent coordinate increment carry chains without adding state or cycles;
`face_cdc_probe_20261101` audits the existing display mailbox, ingress Gray
pointer and RX telemetry protocols with explicit per-endpoint constraints.
No clock-group cut or same-domain CPU/NPU timing exception has been added.
The live source remains frozen during each run; adoption awaits measured
benefit and corresponding functional evidence.


### 2026-11-01 production adoption and board constraint review

The earlier pending statuses above are superseded as follows. Production
`triha_core.v` now enables the CPU's existing `EXTRA_DECODE_STAGE=1`, with
no change to its other feature parameters or clock. Admission validates all
89 files. Production ISA `isa-20261101T061512235475Z` passes all 103 programs;
`cache-soc-irq-20261101T061512240765Z` and
`squash-20261101T061512253326Z` also pass. These are functional tests, not
CoreMark results.

Production capture now preserves separate 32-bit x/y increment carry wires.
`build/video/capture_sum_miter_20261101` passes 20 scenarios, comparing all
38 public outputs cycle by cycle, including three consecutive 800x600 frames.
The +2 mutation is detected. No state or latency was added; source hashes
remain unchanged during the test. Its isolated synthesis is 43,304 LUT
(65.02%), 45,436 FF and 77.5 DRM, with core estimate -1.884 ns.

The new combined production natural-image run is
`build/soc/face_system-20261101T062158_690425Z`; it is still running at this
update. Do not substitute the older extra-decode=0 system PASS for this run.

Board CDC constraints now explicitly bound display mailboxes, ingress Gray
pointers and RX telemetry. Gray source regular expressions exclude the
synchronizer destination registers. Candidate `face_cdc_probe2_20261101`
has zero constraint errors. The DDR clock definitions are restored from the
hash-locked generated IP, preserving its divide-edge phase, cross-clock
uncertainty and multicycle requirements; the core remains 125 MHz with
0.2 ns setup margin. No generic vendor board pin file is imported.
`face_timing_contract2_20261101` synthesizes at 43,524 LUT (65.35%), 45,484 FF,
77.5 DRM; core setup estimate is -1.796 ns, not closure.

PDS `report_place_timing` exists, but its report is an internal binary table,
not the text timing signoff used by the build runner. `generate_constraint`
requires both placed and device-map databases. The correctly exported PCF
confirms the old placement did NOT honor the two vendor gate FF sites.
The main project now includes explicit CDC FDC plus gate-site PCF and route
priority RCF. Mapped-instance site validation is still pending. Source-bound
production synthesis with real ELF is `build/video/pds/20261101T063504_655125Z`.

`build/video/face_reset_audit_20261101` independently flattens the candidate
netlist (331 modules, 90,762 primitives): the startup/free-release sources
reach exactly 47 clear and one preset core-domain pins and zero core data/CE
pins, with zero alias-width or unknown-output errors. Exact synthesized
vendor phase logic passes the 26-functional-register reset hold check;
the exact reset controller retains the guarded PLL release at edge 202.
These support a narrow startup-protocol exception, not analog reset signoff.
The final source-bound netlist must be rechecked before adopting that exception.

No complete route or board PASS is claimed. The user requested engineering
and timing first and will connect the board later; hardware scanning remains
paused.


The production combined regression `face_system-20261101T062158_690425Z`
now PASSES: two natural-image HEAD comparisons, two actual CPU records,
two full display frames, commit/release/reuse, 51,716,858 cycles, zero
simulator errors/warnings and unchanged input hashes. Total cycles equal
the preceding extra-decode=0 version in this frame-paced test; this is not
a general CPU performance benchmark. Source-bound synthesis `063504`
passes with 43,524 LUT (65.35%), 45,484 FF, 77.5 DRM and 59 APM. The current
production netlist independently confirms exactly 48 startup-source C/P
sinks and no core data/CE sinks. The narrow source-qualified exception has
therefore been adopted. One seed-4 performance placement is running in
`build/video/pds/face_contract_place_20261101`; no full route is started.
Evidence index: `docs/verification/npu/2026-11-01-face-timing-progress.json`.


A further PDS report-location clarification: `report_place_timing` writes
both the explicitly requested binary `.rpt` and a text `.rtr` beside the
input placed ADF. The latter was found at
`cpu_decode_place3_20261101/place_route/triha_face_board_top.rtr`, timestamp
14:25:46 matching the `report_place_timing` invocation. It contains nonzero
estimated data-net delays and reports core-to-core setup -1.990 ns; the old
worst cross-domain paths are separately covered by the new CDC/reset review.
This is a usable placement estimate, still not routed signoff. The earlier
standalone `report_timing` zero-wire reports remain invalid for this purpose.
The fresh production phase/reset-controller netlists also pass both protocol
checks in `face_reset_audit_20261101/production`.


The first `face_contract_place_20261101` placement was stopped when its live
log showed PDS dev_map had OVERWRITTEN the input PCF, deleting the two gate
sites. Its receipt remains FAIL/inputs_unchanged=false. The overwritten file
was preserved, and the exact original main PCF restored from its verified
snapshot. Synthesis and mapping were retained; no full route was started.

`face_contract_place2_20261101` resumes that immutable mapped database with
a combined post-map PCF. Its placer explicitly accepts both gate sites.
Final placement export must still verify them. The formal builder now uses
`post_map_constraints`: dev_map emits the generated pin map, Python merges
it with immutable custom sites, then PNR starts from the mapped database.
Three tests pass (pin/source preservation, missing pin-map rejection and
duplicate-site rejection); real-PCF replay matches the live placement's
140 ports and three primitive-site commands. Firmware tests also pass.
The full route/bitstream builder with this new orchestration remains unrun.


The corrected seed-4 placement completes in 559.5 seconds with unchanged
inputs. Both DDR gate sites are verified by exporting the placed primitive
locations. Final optimizer WNS is -0.988 ns. The text placement timing report
has core slow setup -1.119 ns (535 failing endpoints), fast setup +0.051 ns,
core slow hold +0.023 ns, recovery +1.072 ns and removal +0.443 ns. PHY/core
hold still has small negative paths (worst fast hold -0.270 ns). No routed
signoff or route launch is claimed. The leading slow path is now NPU vector
`op[172]` to `io_address[31]`, not CPU or reset startup.

An isolated candidate associates vector transpose addressing as parallel
chunk-base and channel-offset calculations followed by one final add. It
adds no state or cycles. `vector_address_green_20261101` passes 66,051 transfer
cases and 8,192 address/CE/wrap cases with zero warnings; the +1 mutation is
detected in `vector_address_red_20261101`. Main RTL is not yet changed.
Resource/timing evaluation runs in `build/video/pds/vector_address_probe_20261101`.
The first two baseline address runs failed due to test-runner sequencing and
missing explicit unused output connections; `vector_address_baseline3_20261101`
is the clean baseline PASS. Failed receipts are retained.


Vector-address candidate synthesis finishes with unchanged inputs and no tool
errors: 43,503 LUT (65.32%), 45,485 FF, 77.5 DRM and 59 APM. The core synthesis
estimate is -2.033 ns, worse than baseline on a different input-gather path;
this is not a proven timing improvement. Main vector RTL remains unchanged.
One seed-4 performance placement runs in `vector_address_place_20261101`,
reusing the synthesized ADF and the verified post-map PCF merge. No route starts.
`place_frozen_face_20261101.py` records immutable input hashes at map/place
boundaries. Three physical-merge and four firmware tests pass using their
standalone script entry points (package-style unittest invocation does not
resolve their local imports and is not a passing test).

`FINAL_APPLICATION.md` now documents the board-profile boot/natural-image
regression and the later UART model upload. It explicitly records the existing
MINIMAL_CONTROL_CPU=1 board profile rather than claiming a full CPU performance
configuration. No further CPU feature reduction is made in this batch.


The vector-address placement completes with immutable inputs and both gate sites
verified. Its full placement estimate is core slow setup -0.924 ns / 380 failing
endpoints (baseline -1.119 ns / 535), fast setup +0.263 ns, core slow hold +0.120 ns,
slow recovery +1.496 ns and removal +0.443 ns. Worst PHY/core fast hold is -0.360 ns.
The optimizer's -0.678 ns value is not the full report WNS. No route starts.
The no-extra-cycle vector change is adopted byte-for-byte; the admission manifest
retains the actual upstream blob/source hash and new local blob identity.
Production 66,051 transfer + 8,192 address tests pass. New whole-system natural
image revalidation is running in `face_system-20261101T073150_408427Z`; the previous
062158 PASS does not cover the new source bytes.

The next measured paths are graph TASK_PAIR region-selection/end-comparison and
gather row-presence/address-bound checking. An isolated graph candidate adds one
admission cycle per region pair (15 per frame) and passes 1,024 independent
64-bit region/overlap cases plus 80 cancellation placements; removing overlap
checking is detected by the negative control. Synthesis is running in
`graph_pair_probe_20261101`. A separate gather candidate removes the late dummy
lookup from the address-check carry, preserving public addresses and all cycles;
50,000 random internal-state/public-output comparisons pass and a disabled range
check mutation is detected. Neither candidate is adopted yet.


Standalone gather mapping compares the exact old/new candidates with no I/O
insertion: 1,991 -> 2,015 LUT, unchanged 777 FF, setup estimate -0.265 -> +0.622 ns.
The board path report confirms the late row-present mux formerly fed first_word,
then three carry stages, then completion CE. The candidate separates that lookup
from address checking. Combined graph+gather board synthesis is running in
`control_paths_probe_20261101`; no additional placement or route has started.


Adopted-vector full natural-face boot regression `073150_408427Z` PASSES with
unchanged inputs, 51,716,858 cycles, two real HEAD comparisons/CPU results/full
pixel frames and slot release/reuse; zero ModelSim errors/warnings. All metrics
match the preceding production baseline. This remains a native DDR proxy test.
The gather candidate's full 34-case input scoreboard also passes with every
metric matching `reset_receipt_trusted_20261101`, including 694,490 cycles.
The first gather-scoreboard attempt failed before simulation because the default
Python lacked onnx; the rerun used the existing upstream Windows venv.

Combined graph+gather synthesis passes at 43,460 LUT (65.26%), 45,569 FF, 77.5 DRM,
59 APM and -1.847 ns core setup estimate. Reset fanout and the exact vendor phase
protocol are rechecked successfully. One seed-4 placement completed in
`control_paths_place_20261101`: slow setup -1.067 ns / 402 failing endpoints,
worse than the vector-only baseline. This combination is rejected. A route
resume helper is prepared, but has not been invoked and does not certify STA.
Board defaults were checked explicitly: MINIMAL_CONTROL_CPU=1, CACHE_ENABLE=0,
M_LANES=2 and QUANTIZER_LANES=1. Documentation now states these accurately;
no additional CPU configuration reduction is made by this batch.

## 2026-11-01 控制路径组合放置结果更新

此前“PLACEMENT_RUNNING”已结束：组合候选实际 slow setup 为 -1.067 ns、402 个失败端点，比已采用向量版 -0.924 ns 更差，因此淘汰，未启动 route。固定布局入口证明已通过：三槽共 1056 次非法字段变异均被拒绝，任务快照保持不变。下一轮仅在此入口之后复用检查，并提前计算向量控制信息。按用户安排，先完成工程与时序，暂不扫描或连接板卡。

固定布局/向量元数据候选 `layout_metadata_candidate_20261101` 的整机自然图回归通过：两帧真实 HEAD、CPU 框、逐像素显示和槽位复用均通过，51,716,858 周期与生产基线一致，零仿真错误/警告。综合为 43,501 LUT / 45,518 FF / 77.5 DRM / 59 APM，输入及固件内容已核对。但实际放置为 -1.245 ns、1,231 个失败端点，差于生产基线，因此不合入、不布线。

新瓶颈已定位到层操作码→高扇出输入使能，以及状态/有效位→宽量化数据选择→偏置加法。`control_decode_candidate_20261101` 在原 START 边沿预译码操作类型，并移除宽数据上的无效周期清零门控；有效位、标签和错误检查不变。8,416 个独立场景通过，错误使能和错误数据选择负对照均检出。当前综合及完整 boot 回归已启动，生产仍保持已验收的向量地址版；未新增 route 或板卡访问。

## 2026-11-01 控制重构已采用，继续拆分真实关键路径

主工程已采用 control_decode（七个 RTL 的采用前备份及新旧哈希见
`build/npu/control_decode_adoption_20261101/result.json`）。完整模型加载、真实
CPU/NPU 两帧 HEAD/人脸框及逐像素显示通过，51,716,858 周期与基线相同，
ModelSim 零错误/零警告；采用后组件回归通过。整机证据为
`build/soc/face_system-20261101T084921_612281Z`，采用脚本核对编译字节一致。

综合 43,457 LUT（65.25%）、45,519 FF、77.5 DRM、59 APM。seed 4 放置
慢角 setup -0.603 ns / 69 失败端点 / TNS -12.379 ns，相比前生产
-0.924 ns / 380 / -128.017 ns 显著改善，仅少 46 LUT。快角 setup +0.758 ns；
PHY/core 最差 hold slow -0.211 ns、fast -0.255 ns，尚待布线修复。
gate sites、冻结输入与复位协议/网表扇出均验证通过。

未启动完整 route，时序未闭合，无新位流或板测。下一步拆分 graph 的
64 位累加→溢出/尺寸比较→状态控制路径，并评估 input transfer 末尾的
重复加法/比较前移；保持 CPU、125 MHz、额外 0.2 ns setup margin 不变。

## 2026-11-01 关键路径拆分候选：整机通过，启动单次布线

隔离 stage_split 候选将 graph 最终乘加结果先写入原累加寄存器，再做溢出及
尺寸检查，保留数学检查和错误码；在原 input PLAN 提前保存下一偏移及结束标志，
保留 32 位比较语义和传输周期。CPU 配置、时钟约束不变。

512 组乘积/错误检查、5 类新状态退出、4,096 组 burst 规划边界及负对照通过。
输入默认模式 34 场景/46 公开输出逐周期对照通过，信任模式 34 场景也通过。
完整自然图/模型加载/CPU 人脸框/逐像素显示两帧通过：
`build/soc/face_system-20261101T092149_415619Z`，零错误/警告，所有事务计数及
总周期 51,716,858 与基线一致。尺寸检查理论上每帧多 632 个使能周期，但该
受视频帧节奏控制的完整测试总周期未增加，不据此推导通用 FPS。

综合 43,503 LUT / 45,555 FF / 77.5 DRM / 59 APM，相对生产多 46 LUT / 36 FF。
seed 4 放置慢角 setup -0.440 ns（原 -0.603），TNS -8.557 ns（原 -12.379），
89 失败端点（原 69）；快角 setup +0.576 ns。core hold slow +0.023 ns，
全 clock-pair hold slow -0.226 ns / fast -0.270 ns；复位检查通过。
原 graph 乘加检查和 input transfer 完成链退出最差路径，当前首要路径是
gather pad_left 到 k_ci CE，其次量化器 collected 到 dense CE。

`stage_split_place_20261101` gate sites/输入核对通过；现复用该放置结果在
`stage_split_route_20261101` 做单次完整布线和 hold 修复。生产仍为 control_decode，
候选尚未采用。时序尚未闭合，无新位流/板测。

长布线跟进：当前线程已创建每 5 分钟 heartbeat `automation-5`（人脸框工程时序收敛跟进），
检查现有 stage_split_route，正常运行且无可行动变化时保持静默；结束后继续核对
全部物理时序并按实际路径推进。不得重复启动当前运行。生产与候选、仿真与物理
结论仍按上述记录区分；用户暂不接板。工具会话 37156 仍在运行。

## 2026-11-01 SoC 分支源码检查点

用户要求将当前工程推送 GitHub，并新建 SoC 分支。本检查点分支为
`soc/face-box-integration`，远端为 `wan-yuanxing/TriHaRiscv-v3`。
生产源码保持 control_decode；正在布线的两份 stage_split 覆盖源码以完全相同
字节存入 `experiments/npu/stage_split_20261101/`，附哈希、验证摘要和显式测试入口，
未加入生产 filelist，未宣称时序闭合或上板成功。构建产物仍保存在忽略的 build/。

推送前 CPU 89 文件及 B03 41 文件源码准入通过，SoC/Video/采集配置生成检查通过；
6 项帧配置、19 项 B03 导入器、3 项物理约束测试通过，归档候选的乘加与输入规划
组件仿真均通过。Git 暂存字节额外核对 CPU/NPU/上游测试及候选清单；补充上游
测试与模型清单的换行保护，防止重新克隆后破坏已冻结 SHA。保留已准入源码的
原始空白格式。独立技术报告备份不随本提交发布。现有布线和自动跟进继续运行。

## 2026-11-02 phase_decode_local 候选：功能通过，放置淘汰

针对集成后控制线可能重复的问题，先做了局部阶段译码复制：在
`b03_layer_exec_payload.v` 内把量化器 dense/depthwise/vector 的阶段选择拆成
局部保持线，未增加状态、周期、CPU 配置、125 MHz 时钟或约束。负对照将 dense
局部译码故意改成错误状态，组件回归按预期报 `quantizer valid mismatch`；正向
组件回归通过。候选文件哈希为
`88c19ddc5a12ea5ee1356ce86b7152d03942feccec4f0ab3ba25f13d86bebf0f`，负对照哈希为
`cd420ec4fb7898659e73aba7d9c906c698c4c3687d1d2384cfc93bf5136a67e4`。

使用自然图 fixture、`BOARD_PROFILE=1`、真实 `BOOT_LOAD=1` 的整机仿真通过：
`build/soc/face_system-20261101T213238_895014Z`，两帧 CPU/NPU/人脸框/逐像素显示
完整闭环，`FACE_SYSTEM_PASS` 为 51,716,858 周期、`cpu_reads=4296`，0 错误/警告，
输入未变。候选综合为 43,593 LUT / 45,554 FF / 77.5 DRM / 59 APM，输入未变。

seed 4 放置及完整分析已完成，两个 DDR gate sites 和输入哈希均核对通过；但慢角
setup 为 -0.674 ns、313 个失败端点、TNS -85.601 ns，快角 setup +0.534 ns；
慢/快 hold 最差 -0.220/-0.264 ns，recovery +1.730 ns，removal +0.443 ns，
minimum pulse width 两角均 +0.035 ns。首要路径已落到视频显示 raw→link CE，且
整体明显差于生产 `control_decode` 的 -0.603 ns / 69 / -12.379 ns，因此候选淘汰，
未启动 route、未生成位流、未宣称时序闭合或板测通过。

此前 `interface_split_register` route 也已记录为 14,400 秒超时，最后仍有 47,215
个未布线网络，未取得完整 route DB/STA 签核，候选不采用。生产 RTL 继续保持
`control_decode`；外部 HDMI AC、板测、扫描和下载仍由用户后续处理。

## 2026-11-02 graph_pair 放置结果与 stage_split route 结论

针对集成后控制线可能重复的问题，`graph_pair_compat_candidate` 的兼容接口回归、
自然图两帧 CPU/NPU/完整模型加载/逐像素显示仿真和综合均通过；其固定布局入口
保留 `PREVALIDATED_TASK_LAYOUT` 兼容参数，功能结果仍为 51,716,858 周期，输入
未变。综合为 43,686 LUT / 45,570 FF，较生产 `control_decode` 增加控制状态和
寄存器。

seed 4 placement 的完整分析已完成，两个 DDR gate sites、输入哈希和所有时钟对的
setup/hold/recovery/removal/minimum-pulse-width 摘要均已核对：慢角 setup
-1.420 ns / 1,337 个失败端点 / TNS -468.681 ns，快角 setup -0.594 ns；
慢/快 hold -0.227/-0.294 ns，慢/快 recovery -0.317/+0.158 ns，慢/快 removal
+0.433/+0.358 ns，最小脉宽两角均 +0.035 ns。placement-only 报告没有可接受的
max-skew 或 routed STA 签核；最差路径从 `saved_write` 到 `input_path/state[2]`。
相对生产 `control_decode`（-0.603 ns / 69 / -12.379 ns）明显退化，因此候选
淘汰，不启动 route、不采用、不生成位流。

冻结的 `stage_split_route_20261101` 已由 receipt 明确报告失败：PDS route 命令
运行 14,400 秒后超时，最终日志仍显示 41,362 个未布线网络；没有完整 route DB、
全角 routed STA 或位流验收依据。当前没有对应 PDS/Python 活动进程。生产继续为
`control_decode`；保持 CPU 配置、125 MHz 和额外 0.2 ns setup margin，未放宽约束，
也未进行板卡扫描、下载或 HDMI AC 验收。


## 2026-11-02 architecture audit before further timing work

A source and configuration audit stopped the next gather-candidate physical run before synthesis. The graph scheduler, layer dispatch and task/model validation are still implemented in the FPGA B03 service (`b03_frame_exec_payload`, `b03_graph_engine_cap`, `b03_model_input_payload`); the CPU submits work and consumes heads. `ENABLE_HARDWARE_POST=0` removes the FPGA decode/sort/NMS/record writer, but it does not move graph scheduling or model validation to the CPU.

The CPU post path is real, but its current contract is not yet safe for timing admission. `sw/drivers/npu_frame.c` keeps only the strongest 64 candidates before NMS, while the hardware post reference scans up to 2100 eligible heads. Its insertion order compares the raw class*object product, whereas the hardware sort key compares rounded FP32 score and then candidate id. This can drop a late face and can reorder rounded-score ties. The single-face natural-image regression does not exercise either case.

The pre-fix board implementation wired core and compute to 125 MHz and uses `M_LANES=2`, `QUANTIZER_LANES=1`; the arithmetic ABI remains a fixed 16-row by 16-channel layout with unused rows tied low. The user has clarified that CPU/NPU must share 100 MHz and DDR UI/video must use 125 MHz; the prior all-125 MHz connection is an integration mismatch. Lane count is a separate resource decision. The production face board explicitly passes `ENABLE_AVATAR(0)` and its project scope is RAW+BOX; avatar source files and the older diagnostic mode do not constitute a connected face-board avatar replacement.

The gather candidate's natural-face run is recorded as PASS at 51,716,858 cycles with zero simulator errors/warnings, but synthesis and placement are held until the CPU-post full-head/tie contract is fixed or explicitly frozen and adversarial regressions pass. Production remains `control_decode`; no admission hashes or bitstream inputs changed.


## 2026-11-02 CPU/NPU 100 MHz 与 DDR/video 125 MHz 时钟契约修正

用户明确两个核共用 100 MHz，DDR 用户接口/视频处理使用 125 MHz，像素仍为 40 MHz。
旧板顶把 compute/video 同接 DDR core_clk；BOARD_PROFILE 仿真也把 compute 半周期改为
4 ns。因此既有 -0.603 ns 放置和 51,716,858 周期自然脸通过均属于旧 125 MHz compute
实现，不能外推为 100/125 MHz 的验收，也不能简单给旧 slack 加 2 ns 就宣布通过。

本批工作区修复板顶：厂商生成的独立 GPLL 由 125 MHz reference 产生 100 MHz compute
（125/1*4*2=1000 MHz VCO，再 /10）；CPU/NPU 仅接 compute。DDR UI、采集入口、
capture register、UART/model loader 保持 125 MHz。现有 AXI128/AXI-Lite CDC 复用；
PLL 失锁协调复位应用各域，DDR PHY 保持自身独立启动复位。无整域 asynchronous cut；
十个跨域 FIFO 的每向 Gray bus 均增加 6 ns datapath/max-skew 上界，状态同步器只排除
异域输入路径，各域保留 0.2 ns setup margin。约束实际端点和映射仍待 PDS 复核。

已验证：`build/soc/face_clock_boundary_20261102/result.json` 使用真实厂商 GPLL 数字模型
和真实板顶，测得 10/8 ns；覆盖失锁应用复位、PHY 不被复位，以及三个负对照
（compute 错接 125 MHz、UART 错接 compute、仅一侧复位）均检出。此边界测试将
无关 HDMI/face 数据通路黑盒化，不能替代整机或物理 PLL 验收。
`build/soc/axil_clock_split_20261102/result.json` 三个相位、两复位 epoch、背压和乱序
AW/W 回归通过。契约/物理约束辅助/固件安装单测为 12 passed、7 subtests passed。

已启动全模型 boot + 自然脸两帧整机回归：`build/soc/face_system-20261102T053407_618939Z`；
带真实固件的单次综合：`build/video/pds/20261102T053407_671522Z`。尚无新放置或布线。
旧源码备份及新旧字节哈希在 `build/soc/face_clock_split_20261102/result.json`。
首次诊断 `20261102T051230_933197Z` 因 core_release 约束端点不存在被拒绝，其连接及
整域切断也已修正，不能用于验收；冻结产物保留。NPU control_decode 字节未改，
未采用 trusted fastpath，未改 admission hash。CPU top64/同分排序、FPGA 调度/校验迁移、
avatar 接入仍待处理；不将本批时钟修复当作这些功能已完成。heartbeat 现有状态为 PAUSED，
间隔仍为 30 分钟，已修正其过时提示而保持暂停；当前运行由本聊天直接启动。


## 2026-11-02 时钟拆分整机/综合完成与关键路径复核

此前两项 RUNNING 记录现已完成：`build/soc/face_system-20261102T053407_618939Z/result.json`
为 PASS，真实 CPU/NPU、完整模型启动加载、两帧逐像素显示和释放复用通过，零错误/警告，
48,005,166 个 100 MHz compute 周期。不能与旧 125 MHz 周期数直接比较性能。
`build/video/pds/20261102T053407_671522Z/result.json` 综合 PASS，43,331 LUT / 45,519 FF /
77.5 DRM，冻结输入前后检查通过。仿真/综合共有 127 个冻结文件字节一致；两个 ELF 容器
哈希不同，但提取后的 ROM/SRAM 完全相同，也与实际综合镜像和仿真 hex 的字值一致。

综合慢角报告确认 compute 10 ns、DDR UI/video 8 ns。compute 同域 setup +0.095 ns；
DDR/video 同域 setup -1.352 ns / 1,423 endpoints / TNS -748.539 ns，最差路径从
`face/u_compute_cdc/ddr_release_q[1]` 到 `face/u_video/u_capture/fault_stage_code_reg[0:2]/CE`。
另有 sys→compute reset removal -0.404 ns、DDR PHY hold 最差 -1.564 ns。
这些是综合估算，尚无新放置/布线、全角物理时序、位流或板测验收。

本次检查无活动 PDS/Python/ModelSim 进程；heartbeat 保持 PAUSED，不能把空闲称为持续执行。
下一步先修 CPU 后处理全候选/舍入同分语义，并检查采集复位释放扇出和重复控制；随后依据
证据决定单次放置。图调度/模型校验迁移和 avatar 接入仍未完成。保留 0.2 ns setup margin，
未放宽约束，未进行扫描或下载。详细证据已更新至 face-timing-progress.json 与
`build/soc/face_clock_split_20261102/result.json`。


## 2026-11-02 CPU 全候选后处理修复与采集控制去重

已用旧实现负对照复现三个错误：top64 之前的大量重叠候选使第 65 个以后独立框丢失；
原始乘积不同但 FP32 分数相同的框排序错误；同分 NMS 留下错误候选。
证据为 `build/soc/cpu_post_red2_{suppressed_prefix_65,rounded_tie_order,rounded_tie_nms}_20261102/result.json`。
CPU 实现现按 FP32 分数降序、candidate id 升序，每批保留 64 个键，持续扫描后续批次并
保留 NMS 幸存框，直到全部 2100 heads 耗尽或得到 16 个显示框。64 仅是内存缓冲大小，
不再截断候选语义；无需堆或全候选框数组，最多 33 遍扫描，普通单脸仍一遍。

`build/soc/cpu_post_full_heads_final_20261102/result.json` 的 56 项测试 PASS，含 64/65/128/129
密集候选和 2100 heads；`build/soc/face_avatar/20261102T080140_459674Z/result.json` 应用测试
3903 checks PASS，RV32 编译/链接通过，text 16224、bss 2784 bytes。GCC 静态栈记录显示
已检查的后处理调用链合计 3232 bytes，低于预留 4096 bytes（不是所有运行路径的动态测量）。

综合报告的 -1.352 ns 路径实为 reset -> AXI B -> 多级 READY -> job_clear（271 扇出）
-> 像素 READY/packet_take -> fault_stage_code。现将 packer/downscale/bilinear 的清理提前
到已排空的 IDLE，身份/计数仍在请求被接受时更新，消除新请求握手对本地像素 READY 的
组合依赖；未新增寄存级、时序例外或更改时钟。新增 CASE=30 检查旧实现第 2 帧准备阶段
按预期失败：`build/video/capture_idle_prepare_red_20261102/result.json`；新实现 7 帧通过。
三路采集组件回归 `build/video/regression/20261102T080040_364035Z` PASS，307200 字节
独立 oracle 比对通过。连续采集全尺寸回归 `build/video/regression/20261102T080040_375190Z`
现已整套 PASS，含重用/背压/故障/晚脉冲场景及连续三帧全尺寸采集，累计核对 6,321,600 字节。

新整机回归已启动：`build/soc/face_system-20261102T080716_077928Z`，含真实 CPU/NPU、完整
模型 boot、自然脸两帧逐像素显示，100/125 MHz 不变。组件回归通过后，单次综合也已启动：
`build/video/pds/20261102T080926_876364Z`，使用该整机目录实际 firmware.elf；已核对两处 ELF
字节及实际 ROM/SRAM 字值相同。两项运行完成后检查原长路径、reset removal/DDR PHY hold、
CDC 与物理门限，决定 seed 4 单次放置；本批尚未布线。旧源码与新旧哈希集中在
`build/soc/cpu_post_full_heads_20261102/result.json`。NPU upstream/admission 字节未变。

根据用户继续推进并避免结束后闲置的要求，automation-5 已恢复 ACTIVE、间隔 30 分钟，
提示已要求以最新 active_runs 检查真实进程/结果、完成即核验并继续。图调度/模型校验仍在
FPGA，生产仍 BOX-only，avatar/物理时序/位流交付尚未完成；未进行板卡扫描、下载或 HDMI AC 验收。


## 2026-11-02 16:35 接续：整机/综合通过，进入单次放置

`face_system-20261102T080716_077928Z` 已 PASS：完整模型 boot、真实 CPU/NPU、两帧显示
逐像素及释放复用通过，48,005,166 周期，零错误/警告，与此前同为 100 MHz 的周期数相同。
综合 `20261102T080926_876364Z` PASS，43,258 LUT / 45,519 FF / 77.5 DRM；相较前次减少
73 LUT、FF 不变。127 个共有冻结文件以及仿真/综合 ELF 字节一致，实际 ROM/SRAM 字值
已核对，输入检查通过。

综合慢角 DDR/video setup 从 -1.352 ns / 1,423 endpoints / TNS -748.539 ns 改善为
-0.782 ns / 299 / -131.005 ns；最差路径已转到显示记录校验 `u_raw/N6_m1` 至
`record_reject_valid`。compute setup +0.045 ns。sys→compute removal -0.404 ns 与 DDR
PHY hold 最差 -1.564 ns 仍待物理审查，不能当成时序闭合；快角综合摘要为空。
编译约束 1,011 条、零错误，53 条 critical warnings 全为既有共享管脚 ConstraintEditor-2002，
不替代映射端点/板级 AC 验收。全时钟对综合摘要和哈希保存在
`build/soc/cpu_post_full_heads_20261102/synthesis_analysis.json`。

已启动唯一新运行 `build/video/pds/idle_prepare_100m_place_20261102`，从上述冻结综合 DB
映射并执行 seed 4 / place_only / gplace_times 1；无重新综合、无换 seed、无 route。
使用独立目录及哈希回执，冻结输入未编辑；映射后合并固定 DDR gate site 约束。
启动脚本首次把 result 的 report hash 当作 ADF hash，在启动 PDS 前被断言拦住；已修正为
分别验证报告与固定 DB 哈希，并仅启动这一次映射/放置。
下次接续读取该 receipt/log，完成后核对所有时钟对慢快角时序、max-skew/CDC、实际 gate sites
和输入哈希，再决定后续实现；setup 为负或复位/PHY/CDC 未闭环时不布线。
已将旧整机/综合 RUNNING 改为 PASS，新 active_runs 仅指向本次放置。板卡未扫描/下载。


## 2026-11-02 17:05 接续：放置 setup 全通过，复位/PHY/CDC 审查进行中

`idle_prepare_100m_place_20261102` 已完成唯一 seed 4 放置。全角分析在其
`placement_analysis/result.json`：输入哈希不变，两个 DDR gate sites 确认为
CLMA_357_354/660 FF3。慢角 setup 最差 +0.465 ns（DDR/video），compute +0.606 ns；
快角 setup 最差 +1.341 ns，所有时钟对 setup 均零失败。最小脉宽两角最差 +0.035 ns。

仍有 DDR PHY hold：慢/快最差 -0.322/-0.358 ns；复位 recovery 慢/快
-0.471/-0.219 ns，removal -1.226/-1.219 ns。复位违例从 sys 域 startup/free_release
到 compute CDC 释放链、IRQ 同步器 RS；PDS 映射名含 opit_0_srl，需检查实际器件结构，
不能仅凭 RTL 的 ASYNC_REG/syn_preserve 属性假定同步链保留正确。数据域 setup 为正
不等于整体通过。已请求 max-skew，但通用报告无独立 skew 汇总，尚未作签核。

已启动只读聚焦审查 `build/video/idle_prepare_placed_cdc_20261102`：复制 placed DB 到
独立审查目录，导出真实映射网表，针对十个 compute/video FIFO 双向 60 个 Gray bit
做完整端点查询和 6 ns 有界路径检查，保留原始 DB/报告和约束。检查实际复位连接、
同步器级数与映射后再修正实现；不新增宽泛 false path，不把 PHY hold 掩盖掉。
该审查使用 `build/video/audit_placed_face_cdc_20261102.py`，receipt/result 持续记录真实状态。
旧 placement RUNNING 已改为 COMPLETE，active_runs 仅为此审查；尚未启动布线。


本轮审查入口修正：PDS `gen_netlist` 要求 PNR 阶段，拒绝 placed DB，首次审查
`idle_prepare_placed_cdc_20261102` 标记 FAIL（仅工具导出能力不适用，原 DB 哈希未变）。
已改为 `idle_prepare_placed_cdc_v2_20261102`，用受支持的 `generate_constraint -prim`
导出两个 CDC 模块实际 primitive sites，并运行全部 Gray bit 聚焦放置时序。当前没有导出
功能仿真网表，不能声称已证明同步器实现；后续仍需结合实际原语/级间路径审查。
active_runs 已切换到 v2，未重复综合、放置或启动布线。


## 2026-11-02 17:35 接续：Gray 全位审查完成，修复状态同步器复位归属

聚焦审查 v2 已完成，原始 DB/报告哈希不变。`idle_prepare_placed_cdc_v2_20261102/review.json`
核对十个 FIFO 双向 60 个 Gray bit（20 组），慢快角共 120 条路径全部受到 6 ns
`-datapath_only` 上界约束；最大数据到达 0.925 ns、最小余量 4.976 ns，组内最大派生
到达时间差 0.435 ns。这是全位放置估算，不是独立 PDS MaxSkew 表或 routed 签核。
释放链映射为 FFAPP/opit_0_srl；名称/位置本身不证明级数丢失或结构不安全，未据此改 RTL。

确认并修复一处复位归属问题：`triha_face_system.v` 的 video_irq_sync/compute_fault_sync
原先直接用 rst_ni，绕过本域释放链。分别改用已有 compute_reset_n/video_reset_n，复位期间
不提前采样异域状态，复用已有接口，不增加释放状态机或修改时钟/约束。
`face_status_reset_red_20261102/result.json` 在旧连接分别检出 IRQ/FAULT 逃逸本域复位；
`face_status_reset_green_20261102/result.json` 三个时钟相位、三次复位周期通过，两个恢复旧
连接的负对照均检出。测试编译真实 SoC 状态寄存器 always 块，黑盒化无关数据通路并驱动
本域复位输出/状态源，不能代替完整 SoC 或亚稳态验证。

新整机回归 `build/soc/face_system-20261102T094505_126681Z` 和单次综合
`build/video/pds/20261102T094524_634464Z` 已启动，实际 ELF/ROM/SRAM 字值相同。备份及新旧
哈希在 `build/soc/face_status_reset_fix_20261102/result.json`；NPU 字节未改，无 admission 更新。
台账旧审查已改为 REVIEWED，active_runs 仅为这两项。仍须检查释放链异步输入的
recovery/removal 和 PHY hold；当前不启动布线、不加宽泛 false path、不宣称时序闭合。


## 2026-11-02 18:15 接续：状态复位整机通过，补齐释放链异步输入约束

本域状态复位修复的 `face_system-20261102T094505_126681Z` 已 PASS：完整模型加载、真实
CPU/NPU、两帧逐像素显示，48,005,166 周期，零错误/警告。综合 `20261102T094524_634464Z`
PASS，43,070 LUT / 45,519 FF / 77.5 DRM。127 个共有冻结源码、ELF 及实际 ROM/SRAM 字值
一致；证据 `build/soc/face_status_reset_fix_20261102/completion_verification.json`。两项旧
RUNNING 已改 PASS，当前没有仍在运行的整机仿真。

综合慢角 DDR setup -0.678 ns、compute setup -0.302 ns，仍为综合估算，不宣称改善或闭合。
compute 本域 recovery/removal 为 +3.133/+0.868 ns；sys→compute removal 的四个失败端点
全部是 `u_compute_cdc/cpu_release_q[0:1]/C` 和 `u_control_cdc/s_release[0:1]/C`，IRQ 已离开
原始异域复位。实际综合网表确认这两条链均为两个 GTP_DFF_C，第一级 D=1、Q 仅接第二级
D，第二级才向本域释放复位。该证据不替代后续 FFAPP 映射结构/物理级间时序审查。

新增 `scripts/soc/check_face_reset_constraints.py`，旧 FDC 负对照复现遗漏；仅对上述四个
异步清零 C 输入添加带首尾锚点的精确匹配。未改时钟周期、0.2 ns margin、Gray 6 ns 上界，
未改变其他例外；本域释放扇出、功能复位、级间 D 和 DDR PHY hold 仍受检查。green 回归及
五项负对照（缺失、误切 D、扩大引脚范围、两条链分别退化一级）通过；100/125 MHz AXI-Lite
三个相位/两次复位周期回归、实际厂商 PLL 板顶时钟/复位及其负对照也通过。旧 FDC 备份及
新旧哈希见 `build/soc/face_reset_constraint_fix_20261102/result.json`。NPU upstream 未改。

只改约束，复用已通过的整机仿真，不再重复长仿真。唯一新运行为
`build/video/pds/20261102T101304_076125Z`（单次综合，seed 4/seed_count 1），Python 33668、
PDS 26876 已确认存在。台账 active_runs 仅保留此项。完成后检查 PDS 实际匹配恰为四个 C、
本域 recovery/removal 与数据路径仍受约束、冻结输入一致，再进入单次放置及映射/CDC 审查。
尚未布线，PHY hold、独立 max-skew、位流、avatar、图调度/模型校验迁移继续开放；没有板卡
扫描/下载，也没有外部 HDMI AC 或板测验收。


18:17 工具阶段修正：`20261102T101304_076125Z` 在 FDC 导入阶段 FAIL，未产出新综合网表。
PDS 此时保留 `[1:0]` 总线名，位级 `[0]`/`[1]` 正则匹配为空；这不是时序或 RTL 功能失败。
已保留失败日志并立即从 active_runs 移除。匹配改为精确允许 `(0|1|1:0)`，仍限定两条链的
C 输入；检查器增加 PDS 总线形态并拒绝 `[2]`/`[3:0]`，新的红/绿及五项负对照通过。
当前唯一运行改为 `build/video/pds/20261102T101558_115107Z`（Python 46368、PDS 16040），
实际端点匹配应先得到两个 `[1:0]/C`，综合后对应四个位清零输入。下一步必须核实这些匹配、
本域释放时序覆盖及新综合网表，不能把约束源检查通过直接当作 PDS/物理通过。


## 2026-11-02 18:48 接续：PDS 精确端点导入已验证，串联受检查条件控制的综合/放置

`20261102T101558_115107Z` 已 FAIL，未生成新综合网表；旧 RUNNING 已移至失败记录。
编译数据库副本查询确认实际端点是 `u_compute_cdc/cpu_release_q[1:0]/C` 和
`u_control_cdc/s_release[1:0]/C`。单独正则及字面名称均可匹配，之前含分组选择的正则在
PDS 不匹配。现改为这两个精确字面总线名称，不再依赖分组正则；硬件仍对应四个清零输入。
`face_reset_literal_red/green_20261102` 检查及五项负对照通过。完整生产 FDC/CDC 的 PDS
导入验证也通过，仅保留诊断文件 stop.fdc 的预期停止错误。证据在
`build/video/face_reset_pin_query_20261102/review.json`，原编译数据库与副本哈希一致。
该目录的 max_delay 查询仅用于诊断副本，并在综合前刻意停止，未加入生产约束。

为减少半小时接续间隙，启动唯一受检查条件控制的运行：
`build/video/face_reset_literal_impl_20261102/receipt.json`，主 Python 45820。
当前综合目录 `build/video/pds/20261102T104632_695568Z`、子 Python 43984、PDS 32268。
脚本 `build/video/continue_face_reset_20261102.py` 在综合完成后验证冻结输入只有目标 FDC
变化、资源/固件/实际 ROM SRAM 一致、真实两级释放链、本域 recovery/removal 覆盖不减、
setup 不劣于先前综合；任一检查失败即 STOPPED_REVIEW_REQUIRED，不进入放置。
通过后自动执行唯一 seed 4 放置 `face_reset_literal_place_20261102`，再生成全角放置报告，
无需等待下一次心跳才接续。该脚本不启动布线，物理释放链/Gray/max-skew 与 PHY hold 仍需
审查后决定。台账 active_runs 只列这一串联运行，检查时先读其 receipt，禁止重复启动阶段。
未改 RTL/CPU/NPU/时钟周期/0.2 ns margin；BOX-only、图调度/模型校验迁移、avatar、位流及
外部 HDMI AC/板测仍未闭环。没有板卡扫描或下载。


## 2026-11-02 19:05 工期优化与放置结果

串联运行已完成综合、准入核验、seed 4 单次放置和全角分析，不再运行；active_runs 已清空。
`face_reset_literal_place_20261102/placement_analysis/result.json` 输入不变、DDR gate sites
正确。recovery 慢/快最差 +1.159/+1.353 ns，removal +0.443/+0.367 ns，均零失败；最小脉宽
两角 +0.035 ns。setup 慢角 -0.106 ns/10 端点、快角 +1.259 ns/零失败；hold 慢/快
-0.259/-0.303 ns，均为 DDR PHY 时钟对，仍未闭合。

9 个 DDR/video setup 端点共用显示 descriptor extent 乘加/边界判断至 mailbox CE 链；
另 1 个 compute 端点为 graph check_j 至 state，-0.016 ns。下一轮应围绕这两条控制链做
组件级负对照和简化，不能盲目换 seed。固定头像仍未接入：板顶 ENABLE_AVATAR=0，CPU
present 使用 BOX mode 1；已有通用 renderer 并不代表生产完成。将必要功能与路径修复汇总
后统一整机/综合/放置，避免先对 BOX-only 做长布线再因 avatar 重跑。此顺序调整不取消
avatar 或图/模型职责审查；全面迁移图调度不应在缺乏收益证据时成为交付前置大重构。
已通过且输入未变的组件/整机证据复用，修改部分先跑小回归；PDS 语法先用数据库副本
查询验证。维持 CPU/NPU100、DDR/video125、pixel40 MHz 和额外0.2 ns margin。


## 2026-11-02 19:15 RAW 描述符范围运算简化

依据放置报告的 `u_raw/N6_m1 -> descriptor_invalid -> mailbox CE`，修改
`rtl/video/raw_display.sv` 的描述符范围运算：利用已有 16-byte 对齐和 128 MiB DDR 窗口，
先拒绝必然越界的 stride，再以 AXI beat 为单位使用 24-bit 行乘积、25-bit 地址和。
单行图像仍允许所有原先合法的大 stride；地址窗口、行尾填充、未知值、非法几何、slot、
最小 pitch 检查保留。不增加流水状态或握手延迟。旧源码和新旧哈希保存在
`build/video/raw_descriptor_range_fix_20261102/result.json`，NPU/CPU/约束未修改。

新增独立 Python 无限精度字节地址 oracle 和真实 RAW admission 测试台，旧 RTL 先通过
基线，错误 32-bit 截断负对照能检出。新实现 `raw_descriptor_oracle_green2_20261102`
通过 12 组几何、124,692 组数值输入及四种未知字段；缺少 pitch、误用排他上边界、去除
大 stride 上界三项新实现负对照均检出。范围等价通过不等于物理时序已改善。

首次完整 RAW 回归 `20261102T111124_635311Z` 的全部仿真用例已通过，包括 1,440,000 像素，
但末尾整体输入哈希失败：运行期间补充了范围测试脚本，而 runner 冻结全部视频脚本。
该运行明确记 FAIL，不作为通过证据。现已固定全部输入并启动唯一串联验证
`build/video/raw_descriptor_validation_20261102/receipt.json`（主 Python 24668），当前
完整回归目录 `build/video/regression/20261102T111408_635407Z`、Python11968/VVP45252。
完整回归通过后自动接续一次 standalone raw_display 综合；不会启动整机综合或布线。
活动期间不修改冻结 RTL/脚本。后续先整合固定头像和剩余控制链修复，再统一长验收。


## 2026-11-02 20:00 固定头像接入：组件闭环，整机未验收

RAW 范围修复的完整回归 `20261102T111408_635407Z` 和组件综合
`20261102T111538_426628Z` 已 PASS，输入已核验，1308 LUT / 1954 FF / 4 DRM。
其 RUNNING 已清除；旧脚本哈希失败仍保留 FAIL。

CPU 原 primary_index=0 已用红测试复现，改为在最多16个可显示 NMS 框中选择面积最大者，
同面积按 FP32 分数、候选编号决胜，原 BOX 排序不变。新增启动期不可变素材配置、
256x256 素材锚点/覆盖系数生成未裁剪目标方形（仅显示覆盖裁剪）、无脸清空素材字段，
以及 RAW/BOX/AVATAR 请求和复用现有池协议的同帧 mode-only 原子提交。默认现在为 RAW。
`build/soc/face_avatar/20261102T115452_649918Z` 4007 检查及 RV32 链接 PASS；五项
真实源码变异（主脸0、错误裁剪、素材代次错误、强制BOX、漏同帧切换）均被测试检出，
见 `face_avatar_integration_20261102/mutations2/result.json`。首次变异脚本因缩进警告失败，
修正后的独立 mutations2 才是负对照证据。旧整机/固件证据不适用于当前软件字节。

`triha_model_loader.v` 增加可选第七段固定素材区，AVATAR_BYTES=0 保留六段加载行为。
开启时必须整段 CRC 和最终 DDR B 都完成才封存；不能从 UART 指定地址。红测试证明旧
实现过早封存。`boot_uart-20261102T115133_989142Z` 含六/七段直连与实际串行检查、
完整262144字节七段检查（318536项）、CRC失败/越界偏移/幂等重传/背压/故障排空均 PASS。
主机传输七项测试 PASS。板顶目前仍未开启第七段，因此不能称生产头像已接通。

已生成可重现的原创几何卡通头像 `assets/avatars/triha`，提供SVG/PNG预览、RGBA原始字节
及锚点/覆盖参数/CRC/SHA清单。生成器 `scripts/video/gen_fixed_avatar.py --check` PASS。
实际素材 SHA256 c4897906fe809c679acea3b92ba8b4ac3ce25b62b48a67fcd863fc12536c485b。
接着用现有完整缓存读取全部实际 texel、第二像素时钟比及错误CRC做验证。完整缓存复用
已有64 DRM方案；板级总资源及真实路径仍须统一综合确认。未改CPU配置、NPU upstream、
100/125/40MHz、0.2ns margin和约束，不进行板卡扫描/下载。

后续：把该素材CRC/身份绑定到启动加载和固件，接通 boot seal→cache load 与独立模式键，
核对 CPU 记录/RTL guard/全像素参考，再合并板级实现。图调度/校验职责、PHY hold、
路由CDC/max-skew及最终位流尚未闭环，不启动旧BOX-only长布线。


### 20:14 头像真实字节缓存通过，启动系统集成运行

`build/video/avatar_ddr/20261102T120436_276365Z` 已 PASS 并移出活动运行：实际素材
65536 texel 在两个像素时钟比下各比较65538次，错误CRC拒绝 code5。其 Python/VVP 已退出。
生成器同时输出 `sw/include/avatar_preset.h` 与 `rtl/soc/include/avatar_preset.vh`；
两者与实际262144字节素材绑定 CRC32=6112fc3c、身份1/1、基址0x82600000。

SoC 新增默认关闭的 BOOT_AVATAR：开启时第七段完整CRC和最终B完成后，仅握手一次，
自动提交固定描述符到原头像DDR读取/CRC缓存。没有另建DDR通路。主固件读取显示模式
能力，只有平台支持AVATAR才配置同一生成清单；不把配置当成实际cache-ready。
新固件组件 `face_avatar/20261102T120939_836557Z` 4007检查及链接PASS，
`face_avatar_status_reset_20261102` 原始状态复位及两个变异PASS。

第一次系统启动探针 `face_system-20261102T121244_958310Z` 在0时刻因测试台遗留的
六段数量断言FAIL，已明确记录；仅将AVATAR_BOOT下预期段数改为7后重启一次。
当前唯一运行 `build/soc/face_system-20261102T121350_305980Z`，Python3320、ModelSim20872。
命令 `python scripts/soc/run_face_system.py --board-profile --boot-only --avatar-boot`。
它核对实际CPU、全部模型加素材UART包/DDR写后读回、自动cache-load、完整CRC、像素域封存；
不代表完成推理/显示，更不代表物理时序。实际板顶仍未开启BOOT_AVATAR，模式键尚待接入。
以台账active_runs为准，运行期间不改冻结RTL/固件/脚本/素材。完成后立即核验接续。


20:17 接续修正：`face_system-20261102T121350_305980Z` 已FAIL并结束。六个真实模型段
均完成，在第七段首字节遇到旧测试台将素材区当作采集 guard gap 的断言。只为
AVATAR_BOOT 且 boot_owner、未封存时开放精确0x82600000..0x8263ffff窗口，同时增加
逐字节重复检测、262144字节总数和封存后禁写检查；其他采集guard不变。
当前唯一活动运行替换为 `build/soc/face_system-20261102T121616_403404Z`，Python31548、
ModelSim24236，已确认实际进程存在。旧3320/20872不再运行。继续冻结当前输入直到结果。


### 2026-11-02 头像、模式键板级接入及下一轮验收

旧启动运行 `build/soc/face_system-20261102T121616_403404Z` 已结束，结果
PASS_BOOT_ONLY：7段、7940包、7394379周期，真实CPU准入、全部模型和262144字节
素材经DDR写后读回、完整缓存CRC/身份及像素域ready通过；不是三模式完整显示证据。
旧 RUNNING 文字是历史记录，当前进程以台账 active_runs / receipt.json 为准。

板顶现已接入固定头像全缓存及官方KEY1/C23，CPU读取新增只读MODE_REQUEST(0x84)
并保持唯一显示所有者，默认RAW，按键依次切换BOX/AVATAR；新增能力位16，记录ABI不变。
预览采集与显示器选择解耦，板顶明确关闭未用preview，未削减CPU/NPU配置。
模式键真实去抖/MMIO、长按/抖动/reset/stall及三个负对照PASS
(`face_mode_key-20261102T122623_604578Z`)；应用4007检查、原始状态复位回归及厂商PLL
100/125/40 MHz连线检查通过。上传器默认7段，--model-only明确用于旧6段位流；
8项主机测试与只读资产审计PASS，未访问串口/板卡。

PDS编译数据库确认模式键必须使用 `g_mode_key.u_key`，旧斜线层级不匹配。
补齐头像ready第一级输入豁免，保持第二级正常计时，两个身份捕获目标保留6ns
max_delay。所有生产约束端点重放通过，查询脚本以专门不存在的STOP端点停止综合；
诊断退出非零是预期停止，未计作综合或物理通过。原始证据
`build/video/face_avatar_cdc_query_20261102/review.json`，不增加宽泛false path。

紧凑显示回归19项MMIO/CDC/像素检查通过后，完整显示组合测试因测试台旧层级
`dut.u_mmio`无法绑定而停止；只修正脚本映射到 `dut.g_full_mmio.u_mmio`，
重新执行受影响的3个显示场景，旧19项须核对所有未变化输入后才复用。
输入备份、新旧SHA见 `build/soc/face_mode_integration_20261102/after_hashes.json`。

下一步用带守卫的串联运行完成实际自然脸、7段完整加载、真实CPU/NPU、RAW/BOX/AVATAR
逐像素核对，通过后自动使用同一次仿真的firmware.elf做单次综合，并比较共享RTL及
ROM/SRAM实际字；资源/时序人工审阅前不布局布线。三个显示模式使用独立Python数学
oracle，测试台加速去抖不改变生产125MHz/20ms。内部物理闭合、图调度/模型校验职责、
外部HDMI AC及板测仍未闭环。NPU仍为control_decode，准入哈希未变。


接续：紧凑显示兼容性已 PASS，共22场景（19项未变化输入复用，3个完整显示场景重跑）。
证据 `build/soc/face_compact_compat_20261102/result.json`。已启动唯一串联协调器
`build/video/face_avatar_validation_20261102/receipt.json`（Python42028）；当前SYSTEM阶段
`build/soc/face_system-20261102T125839_514465Z`，Python17952 / ModelSim20468，实际进程已确认。
整机通过后自动接续一次使用同一ELF的综合；失败立即停止并写真实状态，不轮换seed，
不自动放置/布线。冻结输入至协调器结束；此处仍未宣称整机三模式或物理时序通过。


### 2026-11-02 21:31 三模式整机及综合通过，单次放置准入

`face_system-20261102T125839_514465Z` 已 PASS，7段完整模型/素材、真实CPU/NPU、
自然脸两帧、RAW/BOX/AVATAR逐像素、模式独立提交与槽释放复用均通过：
49663086周期，modes=111，Errors/Warnings=0。旧协调器与ModelSim已退出，
active_runs没有残留RUNNING。综合 `build/video/pds/20261102T131939_550869Z` 已PASS，
51262 LUT (76.97%)、55283 FF (41.50%)、141.5 DRM (91.29%)、64 APM，零latch。

仿真/综合130个共享输入、同一firmware.elf、ROM/SRAM逐字一致，源码快照及原始文件
均未变化；实际100/125/40MHz时钟、计算/视频额外0.2ns setup、窄复位C引脚、模式键
官方来源及约束端点检查通过。证据 `build/video/face_avatar_synthesis_review_20261102/result.json`。
像素/RX/config/free域的物理验收仍须至少保留0.2ns setup余量，不能仅看非负slack。

综合估计setup slow -0.461ns/135端点、hold -1.748ns/371端点；recovery/removal/pulse
零违例。setup首路径为显示link.base到link.state CE；计算域首路径为释放复位到NPU
done_detail。综合无fast表，不替代真实放置/布线。DRM余量13.5块，路由可行性仍未证实。
当前准入一次已有综合DB的seed4放置，并自动接续全角时序/gate sites分析；无重新综合、
无seed轮换、不自动布线。图调度/部分模型校验仍在FPGA；外部HDMI AC和板测未完成。


### 2026-11-02 22:06 放置setup全通过，准入一次DDR hold修复布线

`build/video/pds/face_avatar_place_20261102` 已完成并自动分析，原Python/PDS退出，
active_runs已清空。慢/快setup最差+0.379/+1.223ns，零失败；计算域慢setup+0.699ns，
视频域+0.379ns，像素域+1.094ns。recovery +1.021/+1.215、removal +0.433/+0.358、
pulse +0.035/+0.035均零失败。输入、两个实际DDR gate sites均已核实。
实际映射51244 LUT/55181 FF/141.5 DRM，不把综合资源当实际映射。

hold慢角-0.349ns/115端点，快角-0.416ns/200端点，仅三个DDR PHY时钟对；报告列出的
97条违例路径起止均在厂商DDR PHY内。对应时钟对慢setup下界5.368/2.918/2.303ns，
扣除快角hold缺口仍为4.952/2.553/2.137ns。因此选择工具物理延时修复，避免无依据
修改CPU/NPU或降低频率。23个Gray bus的max_skew与同值max_delay约束均保留于实际映射，
有界数据路径setup通过；放置报告未提供数值max-skew表，最终布线仍需明确核验。
证据 `build/video/face_avatar_route_review_20261102/result.json`。

启动一次固定seed4放置DB的route，开启文档支持的multi-corner/fix_hold_violation及
fix_hold_violation_in_route。冻结源码、固件、约束及数据库；不重新放置/换seed，
不放宽时钟不增加false path。90分钟硬上限，超时记录并终止此PDS进程树，不自动重试。
完成后自动生成全角时序和routed gate sites，仍保留STA_REVIEW_REQUIRED，只有
零未布线、所有时序/偏斜及边界证据齐全才可进入工程/位流交付。此处不是时序闭合。


### 2026-11-03 布线超时，转向删除显示上下文重复副本

face_avatar_route_20261102 在90分钟上限停止，iteration15仍有63168条未布线网络；
输入哈希未变，相关PDS/Python进程全部退出，active_runs为空。没有最终route数据库或STA，
不能把此前放置setup通过当作闭合；不重启同一候选、不换seed。

综合u_pixels/u_context占7880 FF；compact renderer实际仍使用普通复制式CDC。
候选仅改用已有held-record消费者，MMIO原记录由link保持至扫描/像素联合反馈，
像素active副本继续保留；删除中间两份宽记录，保持ABI、三模式、输出延迟及释放语义。
先实际组合源破坏负对照、shadow并发写/忙提交拒绝、异步比率及逐像素组件回归，
再测量资源收益，收益成立才进入真实整机/单次综合。新增原记录到像素域6ns有界路径，
不加false path；端点和最终全角物理时序另行验收。源码备份及旧哈希在
build/video/face_held_context_20261103/before/及before_hashes.json。


接续：真实组合负对照已红/绿核实，握手接受后的源记录破坏在新组合准确触发
HELD_RECORD_SOURCE_CHANGED；旧组合未检测。首次注入早于接受边沿，已作废并修正，
以build/video/face_held_context_20261103/negative_review.json为准。
已接入候选并同步显式整机/板级source列表，BOX_ONLY参数兼容原分支；尚未物理采用。
新增的原记录到pixel_clk路径保持6ns上限，所有频率及0.2ns margin不变。

2026-11-03 00:22:56启动唯一协调器Python6980，组件Python48924及vvp49044实际在运行，
组件目录build/soc/resource_probe_video_compact_20261102T162256_315033Z。
receipt: build/video/face_held_validation_20261103/receipt.json。
流程为23项组件回归→同端口像素组件新旧资源比较→仅当至少减少4000FF、LUT增长不超过100
且DRM/APM不增加才接续真实三模式完整加载整机→同一ELF单次板综合。
失败立即写真实状态并清空active_runs；完成停在CDC/复位/资源审核，不自动放置或布线。
源码、脚本、约束已冻结；后续以该receipt及active_runs核对实际运行。


### 2026-11-03 00:42 23项组件通过，准入变化核实后接续资源比较

build/soc/resource_probe_video_compact_20261102T162256_315033Z/result.json 已PASS：
23项含两种时钟比逐像素、RAW/BOX/AVATAR组合、模式独立提交、槽/素材释放、
shadow并发写及忙提交拒绝、复位、源记录破坏负对照。所有组件实际输入哈希未变。

原协调器在组件结束后检测config/cpu_admission.json变化并正确停止，active_runs已清空，
没有残留Python/PDS/ModelSim。变化来自当前共享CPU CSR/LSU审查的准入清单更新；
本轮冻结期间仅该清单变化，CPU RTL字节及显示组件输入均未变化。
当前CPU admission_common.validate()重新PASS；核对本地CSR regfile已同步进入CPU、
SoC和板级显式source列表，保留对方修改。旧板级物理证据不覆盖当前CPU修正。
证据build/video/face_held_context_20261103/resume_admission.json，保存新清单实际字节。

未重跑已通过组件；新独立协调器build/video/resume_face_held_20261103.py以当前哈希冻结，
00:42:36启动Python49576，资源比较Python23708/PDS14196（子47336）实际运行。
新receipt为build/video/face_held_validation_resume_20261103/receipt.json；依次比较原/候选
像素组件资源，达到既定削减门槛后自动接续完整真实整机及同一ELF单次板综合。
完成停在CDC/复位/资源审核，不自动布线；原失败记录保留，不改写为PASS。


### 2026-11-03 01:09 资源报告解析修正，复用已完成基线

上一协调器在基线组件综合完成后停止：resource_report给出的根层级名称为u_pixels，
统计脚本错误要求以/u_pixels结尾。真实综合成功，非RTL失败，候选综合当时未启动；
该失败及无活动进程状态已保留。基线u_pixels实际8763 LUT/15475 FF/6 APM/0 DRM，
扫描夹具资源单列，不用于板级时序结论。

已用真实保存的.snr验证解析修正。新资源脚本复用原基线，核对每个冻结源码，且候选
扫描夹具必须除被测模块名外逐字相同；不重跑23项组件或基线综合。证据
build/video/face_held_context_20261103/resource_parse_review.json。
新协调器build/video/continue_face_held_resource_20261103.py于01:09:55启动，
Python41980/资源Python51492/PDS51144（综合子47408）实际在运行。
receipt: build/video/face_held_validation_resource_20261103/receipt.json。
达原资源削减门槛后自动接真实整机、同ELF单次板综合，仍不自动放置/布线。


01:10 接续：资源比较PASS。相同扫描边界下像素组件从8763 LUT/15475 FF降至
8853 LUT/7777 FF，即FF减少7698（49.7%）、LUT增加90（1.03%），6 APM/0 DRM不变。
所有实际源码与冻结副本一致，原基线未重跑。满足原门槛，已自动进入
build/soc/face_system-20261102T171030_980602Z，整机Python39712；完成通过后接同ELF板综合。
此资源结果仅证明组件收益，不宣称整板资源、CDC路径或物理时序已经通过。


### 2026-11-03 01:36 held-record三模式整机通过，综合正在运行

build/soc/face_system-20261102T171030_980602Z 已PASS：7段完整模型/头像加载、真实CPU/NPU、
RAW/BOX/AVATAR逐像素、模式提交、槽释放复用均通过。49663086周期，与此前三模式基线
相同，Errors/Warnings均为0；组件23项PASS仍保留。实际源码与仿真冻结副本、工具及
外部输入哈希均重新核对；同一ELF已进入板级综合。
证据build/video/face_held_context_20261103/system_review.json。

唯一活动流程已自动进入build/video/pds/20261102T173040_811236Z，协调器Python41980、
综合Python8548/PDS25580（子30532）实际运行。CPU CSR/LSU新字节包含在本次整机中；
旧物理证据不挪用。保持冻结输入，综合完成后核对实际资源、CDC新增6ns路径、复位和
约束命中，再决定单seed4放置；尚无该候选的板级综合/物理闭合结论。


### 2026-11-03 held-record综合完成，但CDC/复位失败，先修正再放置

build/video/pds/20261102T173040_811236Z 综合完成：51449 LUT/47583 FF/141.5 DRM，
相对三模式旧基线FF减少7700、LUT增加187（同时含已准入CPU CSR修正）。132个共享源码、
同ELF及ROM/SRAM逐字一致。所有旧进程退出，active_runs为空。

该候选不准入放置：原记录到SOF overlay组合路径在6ns约束下-5.110ns/89端点；
组合双域复位引出recovery -6.879ns/74端点、removal -2.065ns/105端点。
证据build/video/face_held_retime_20261103/previous_synthesis_review.json。不是工具完成即闭合。

修正：复位各域两级同步释放，仅四个异域release链async C引脚精确例外；本地复位
扇出、D/Q/CE及同步级间仍计时。将原末级像素输出寄存器移到RAW入口，记录在SOF
先捕获到pixel active_data，overlay仅使用本地域数据，删除宽跨域旁路和选择器。
显示总延迟不变；素材请求9->10拍，提交证明相应等到首像素/故障已寄存，不能提前ACK。
不放宽6ns有界路径、频率或0.2ns margin，不修改CPU/NPU配置。

复位释放red已复现；定向green含首次采样故障、无空隙帧逐像素及pending reset均通过。
将新提交标记故意提前一拍的负对照准确触发RECORD_PIXELS_FALSE_FAULT_COMMIT。
证据build/video/face_held_retime_20261103/focused_review.json，before/及新旧哈希保留。
接续25项组件回归、完整真实整机三模式和同ELF单次板综合；当前尚未验证新物理时序。


### 2026-11-03 03:12 held-record重排通过整机与综合审查，接续单次放置

25项组件回归PASS；build/soc/face_system-20261102T182652_956679Z整机PASS：
7段完整模型/头像加载、真实CPU/NPU、RAW/BOX/AVATAR逐像素、模式提交与槽释放复用均通过，
49663086周期，Errors/Warnings=0。旧协调器/PDS/ModelSim均已退出，active_runs已清空。
综合build/video/pds/20261102T184655_932606Z：49056 LUT、47680 FF、141.5 DRM；
相比完整头像基线减少2206 LUT/7603 FF，相比首次held候选减少2393 LUT、增加97 FF。
132个共享源码、同一ELF及ROM/SRAM实际字一致，454个冻结输入重新核实未变。

新增双域复位链的综合网表确认各两级，stage0仅连接stage1；四个异域async C引脚
被PDS准确解析，D/Q/CLK/CE与本地扇出没有新增例外。5项审查负对照均被拒绝。
原记录的6ns限制保持，active_data先在像素域捕获，overlay没有跨域原记录旁路。
视频到像素域综合setup最差+2.297ns、零失败；recovery/removal/pulse均零失败。
综合最差setup仍为视频link.base到state CE的-0.431ns/102端点，hold -1.536ns/71端点；
综合fast表为空，不能充作物理通过。计算域setup +0.138ns已计入0.2ns uncertainty。
证据build/video/face_held_retime_synthesis_review_20261103/result.json。

准入一次复用该综合DB的seed4映射/放置，完成自动分析慢快角及实际DDR gate sites，
停在物理结果审查，不自动route；每个PDS阶段40分钟上限，超时终止对应进程树。
流程receipt为build/video/face_held_retime_place_flow_20261103/receipt.json，
放置目录build/video/pds/face_held_retime_place_20261103。所有输入继续冻结。
NPU仍为control_decode；图调度/部分模型校验迁移、最终max-skew数值核验、
工程/位流交付、外部HDMI AC及板测仍待完成。本次没有物理时序闭合结论。


### 2026-11-03 03:48 放置未通过，依据两类关键路径删除晚到控制链

held_retime seed4放置及全角分析已完成，所有进程已退出，active_runs已清空。
慢角setup -0.491ns/27失败端点、TNS -6.498ns；快角setup +0.462ns/零失败。
计算域慢setup +0.502ns；像素本域+1.175ns；6ns视频到像素有界路径最差+0.115ns。
hold慢/快-0.368/-0.412ns，60/94失败端点；recovery、removal、pulse均零失败。
实际两个DDR gate sites通过。max-skew数值最终仍待核实。本候选未启动route。
证据build/video/face_pointer_guard_20261103/previous_placement_review.json。

真实首路径从DDR ready状态经采集READY进入ingress FIFO的prefetch，再进入二进制加法及
Gray编码；另一类从record guard的lane[2]（扇出1033）经256位记录选择、坐标比较进入
错误结果CE。选择提前计算而非增加流水拍：FIFO恒定计算read+1/Gray及两个empty候选，
prefetch只选更新/保持；框校验在每个固定slice先判断，lane仅选择1位错误结果。
保持FIFO容量、出数顺序、背压、Gray协议、校验顺序及17拍成功延迟，不改变时钟或约束。
未修改板级ready安全门、CPU/NPU配置或NPU准入哈希。旧源码及新旧哈希均已保存。

先运行独立队列/逐项框边界oracle，破坏stall保护及矩形检查的基线负对照均准确失败。
候选FIFO五种深度/时钟组合及四种采集场景PASS；框校验246项PASS，覆盖所有16框/5点、
有符号坐标、零宽/反向高、缺失/保留字段、错误优先级、背压和逐项完成拍数。
同样的两种候选负对照均准确失败。证据build/video/face_pointer_guard_20261103/focused_review.json。
框定向测试已纳入run_video_compact.py，完整组件变为26项。

接续唯一协调器build/video/continue_face_pointer_guard_20261103.py：26项组件→完整真实
CPU/NPU七段加载/三模式整机→同ELF单次综合；使用已通过的9项FIFO/采集证据。
receipt: build/video/face_pointer_guard_validation_20261103/receipt.json。
综合后停在结构、资源及时序审查，不自动放置/布线。输入冻结至协调器结束。
此处只证明定向功能回归，未宣称新实现整机或物理时序通过。


### 2026-11-03 07:39 指针/框校验重排通过整机与综合审查，已接续单次放置

26项组件PASS（框校验246子项）；完整七段模型/头像加载、真实CPU/NPU及RAW/BOX/AVATAR
整机PASS，49663086周期，Errors/Warnings=0。结果build/soc/face_system-20261102T195356_684319Z。
综合build/video/pds/20261102T201358_344221Z完成：49087 LUT/47678 FF/141.5 DRM。
相对上一held_retime候选+31 LUT/-2 FF；相对完整头像旧基线-2175 LUT/-7605 FF。
132个共享源码、同一ELF、ROM/SRAM逐字一致，457个冻结输入重新校验通过。
验证协调器已结束，旧RUNNING已清除；本批没有重复启动综合或整机仿真。

综合网表独立连接审查确认11个FIFO变体的读binary/Gray寄存器D锥仅来自rd_binary，
prefetch仅进入CE；旧候选作为负对照被拒绝。框校验lane[2]实际primitive负载1031->10，
lane不再进入任何比较carry锥，旧候选仍会进入比较carry。原4个时序/物理约束文件字节未变。
计算/视频/像素周期10/8/25ns及0.2ns margin策略保持；双域释放链、四个精确异域C引脚、
6ns记录跨域界限和像素本地域捕获再次通过审查，5个复位/约束负对照均被拒绝。
综合视频->像素setup +2.267ns、compute setup +0.112ns；最差setup -0.461ns/107端点，
hold -1.536ns/71端点，recovery/removal/pulse零失败；fast综合表为空，不能宣称物理通过。
证据build/video/face_pointer_guard_synthesis_review_20261103/result.json。

已启动唯一seed4映射/放置协调器（Python PID 28072），复用上述综合DB，
每个PDS阶段40分钟上限，完成后自动分析全角时序及实际DDR gate sites，停在人工结果审查。
receipt: build/video/face_pointer_guard_place_flow_20261103/receipt.json；
placement: build/video/pds/face_pointer_guard_place_20261103。新运行输入继续冻结。
未启动route；最终零未布线、慢快角全时钟对、max-skew数值与全部margin仍须实测报告验收。
图调度/部分模型校验迁移、工程/位流交付、HDMI外部AC及板测仍未闭环；不扫描或下载。


### 2026-11-03 07:51 放置setup通过，立即接续固定放置的单次hold修复布线

本轮映射/放置合计516秒，分析已完成；旧协调器/PDS进程退出，旧RUNNING已清除。
慢/快角setup最差+0.827/+1.302ns，均零失败；视频域慢setup +0.832ns，计算域+0.827ns，
像素本域+6.282ns，6ns视频->像素有界路径+0.969ns。recovery/removal/pulse全角零失败。
hold慢/快-0.354/-0.413ns，140/225失败端点，三个失败时钟对都属于DDR PHY；
95条报告中的失败hold路径首尾均在厂商DDR范围内，实际两个DDR gate sites通过。
23组Gray max_skew与配套max_delay在映射记录中匹配，最终数值偏斜仍待布线报告核验。
证据build/video/pds/face_pointer_guard_place_20261103/placement_analysis/result.json。

准入一次已有seed4放置的物理hold修复route。每个失败时钟对的慢setup减去两倍快hold
缺口后，剩余4.752/2.052/0.242ns。最后一对余量有限；此为布线尝试筛选，不能视为
跨角修复保证或签核，原时钟、0.2ns margin及全部约束未变。相比旧路线的固定1ns
尝试筛选，现明确用双倍缺口与0.2ns剩余量评估；没有降低最终任何验收门槛。
准入证据build/video/face_pointer_guard_route_review_20261103/result.json。

已启动build/video/route_face_pointer_guard_20261103.py（Python PID 472，
启动PDS PID 33192），receipt为build/video/pds/face_pointer_guard_route_20261103/receipt.json。
固定放置不重综合、不换seed、不重做已通过的整机；route有90分钟硬上限，超时终止自身树。
布线成功后自动在独立PDS调用里生成全角时序及实际gate sites，修正旧脚本在route前
预解析尚不存在routed DB的问题，报告阶段10分钟上限。没有等待下一次半小时heartbeat才接续。
路由完成后仍须零未布线、慢快角全时钟对与0.2ns margin、max-skew数值、约束匹配及
实际gate sites全部验收。当前没有闭合位流，不扫描/下载。图调度/模型职责迁移与外部AC/板测仍开放。


### 2026-11-03 09:49 固定放置route超时，转入限时拥塞取证

route在09:20:29达到90分钟上限，按既定策略终止自身PDS树，未生成routed DB/全角报告。
第51次详细布线迭代仍有34720条未布线（总nets 99896）；最后几轮为35695、35417、
35041、34720，仍有进展但逐轮下降变慢。旧Python/PDS均退出，active_runs已清空；
480个冻结输入重新校验无变化。原receipt保留STOPPED_REVIEW_REQUIRED，工程台账明确
记录FAILED_ROUTE_TIMEOUT。没有位流/物理闭合结论，也不能把本次超时当作永远不可布通。
失败审查build/video/face_pointer_guard_route_failure_20261103/result.json。

映射使用49068 LUT/47575 FF/141.5 DRM（74%/36%/92%），存在多条数千扇出的控制网络。
日志无PDS错误，CPU持续工作；不能仅凭占用和慢进展断言某个RTL模块是拥塞根因。
本轮未开启厂商拥塞导出，缺少具体冲突网络及SRB位置。PDS User Guide第113页说明
Dump Router Congestion Plot会导出CongestionPlot和CongestionNetInfo；本机help确认
参数-dump_router_congestion_plot TRUE。当前也没有证据支持换seed或延长完整布线。

已启动单个短时诊断采样：build/video/diagnose_face_route_congestion_20261103.py，
Python PID 40636、PDS PID 4256。同一map/placement DB、同一频率/约束和路由选项，
仅打开拥塞明细导出；规范化脚本文本对比确认只有该开关变化。详细迭代>=5且两类文件
都产生即停止，否则10分钟硬上限；此运行是取证，不作为第二次交付布线或时序验收。
receipt: build/video/pds/face_pointer_guard_congestion_20261103/receipt.json。
下一步按冲突net层级和热点位置判断布局密度/硬块邻近/控制扇出/工具设置，再决定改动。
不改活动运行冻结输入，不扫描/下载，不触及technical-report。


### 2026-11-03 10:12 GitHub当前源码快照

按用户要求推送当前应用版本，功能及物理边界见docs/verification/npu/2026-11-03-face-version-snapshot.json。
提交前重新核对162个整机源码、37个输出及外部输入哈希；头像/显示ABI生成检查、13项时钟与上传器
测试、CPU admission均PASS。包含当前整机依赖的CSR/LSU修正与来源记录；不包含技术报告及独立审查脏文件。
本次是功能回归通过的源码快照，route仍为90分钟超时、末次34720未布线，不代表可下载或物理闭合。

拥塞诊断已结束，active_runs为空，485个冻结输入未变，但未得到预期冲突导出，状态为
DIAGNOSTIC_INCOMPLETE_REVIEW_REQUIRED。receipt记录实际1174.6秒，超过设定600秒，计时及停止路径
需要单独核查，不能声称10分钟硬上限已经验证。该问题与具体拥塞根因均继续待查。

### 2026-11-03 12:10 BOX真实人脸两帧整机PASS，详细布线继续

`build/soc/face_system-20261103T034939_772163Z` 已PASS：48005166计算周期、2次真实结果、2个完整800×600 BOX输出、4次捕获/请求、2次提交、1次释放/复用，模式010，0 errors/0 warnings。首帧与第二帧26368字节HEAD均独立比较；固件在首次捕获前进入BOX，正样本每完整帧的1676个边框像素通过检查。197个当前源码/输出哈希、与PDS共用132个源码文件均核验一致；ELF逐字一致，ROM/SRAM解码内容一致（文本仅CRLF/LF差异）。无脸六段整机回归仍在运行，不能提前计PASS。

26项显示组件/246 guard子项PASS。计算域两条复位链综合审计和5项负对照PASS，原有跨域约束保持。BOX综合43018 LUT、43377 FF、77.5 DRM、58 APM；相对历史头像版减少6069 LUT、4301 FF、64 DRM。最终资源以映射/路由报告为准。PDS已进入详细布线；全局布线零未连不等于详细布线完成或时序闭合。当前没有验收位流。

摘要：[face-box-bringup](../verification/npu/2026-11-03-face-box-bringup.json)。实板仍按用户要求延后，未扫描或下载。

### 2026-11-03 12:19 无脸整机及UART加载组件PASS

无脸场景 `build/soc/face_system-20261103T035952_325404Z` 已PASS：2帧HEAD独立比较、完整BOX模式像素无误框、槽位释放/复用，48005166周期、0 errors/0 warnings；与有脸/PDS的ROM/SRAM初始化内容完全一致（ELF非加载元数据不要求字节一致）。当前源码和输出哈希再次核验通过。UART RX 265检查、并行/串行model-loader各2072检查、boot buffer 1213检查PASS，路径 `build/soc/boot_uart-20261103T041416_677529Z`。这些是数字仿真，未打开实体串口。

主线功能仿真已完成，继续等待本次详细布线及全角时序报告；尚未产生验收位流。不因全局布线完成或综合/布局setup估算为正而提前标记时序闭合。

### 2026-11-03 13:09 BOX布局对比与布线拥塞取证

基线 BOX 的 seed4 继续详细布线；复用同一 mapped DB、固件、管脚和时序约束，增加一组
`-plc_decongestion 3` 放置对比。候选放置完成，随后从该放置 DB 开始固定布局布线，开启
厂商拥塞明细导出，90 分钟超时会终止自身进程树。未重复综合或已通过的整机仿真。
候选运行 `build/video/pds/face_box_spread3_route_20261103`；基线运行路径不变。
截至本条，基线第354轮3975条未布线，候选第72轮4608条未布线；两者均未完成物理验收。

用 `report_place_timing` 对两组放置分别检查：基线慢/快 setup 最差 +0.771/+1.346ns，
候选 +0.903/+1.542ns；hold 基线 -0.336/-0.372ns，候选 -0.379/-0.418ns，失败时钟对
均在 DDR PHY。其余 recovery/removal/pulse 全角零失败。该报告是放置估算；普通
`report_timing` 读取 placement DB 会缺失预计布线/时钟延迟，其先前诊断结果已明确作废。
正确原始文本报告已独立保存于 `build/video/face_box_placement_review_20261103`，
两个 DDR gate 的实际放置位置也已核验，证据 `build/video/face_box_place_sites_20261103`。

最终仍需 routed DB、详细布线零未连、全角五类时序、Gray 偏斜数值、实际 PHY sites 和
输入哈希一致性验收。`-report_max_skew` 尚未在放置文本报告中输出独立偏斜表，正在核查；
不能把约束成功匹配视为偏斜数值验收。BOX 不连接的 KEY1 会产生一条精确的 dangling
提示，须按真实 BOX 参数单独审查，其他错误/关键警告不放宽。未连接、扫描或下载实板。

### 2026-11-03 13:35 BOX首次布通，CPU setup 定向优化继续

spread3 候选已完成 367 轮详细布线，末轮未布通为 0；物理 hold 修复完成并保存
`triha_face_board_top_pnr.adf`。基线在约4000条未布通附近反复，已在确认具体 PID 后
终止其自身 PDS 树，失败/停止记录保留；未修改该构建的输入。spread3 完整运行约20分钟。

独立 routed STA 显示：只有 compute_clk 慢角 setup 未通过，WNS -0.306ns、67个端点、
TNS -8.598ns；快角 setup +2.709ns。hold慢/快 +0.103/+0.072ns，recovery
+1.875/+3.945ns，removal +0.352/+0.249ns，pulse +0.035/+0.035ns，均零失败。
源文件中计算/视频0.2ns margin保留，报告总setup uncertainty为0.35ns（含工具自身项）。
140个实际I/O及电气属性与冻结PCF一致，唯一移除端口是BOX禁用的KEY1；两个DDR gate实际
位置正确。证据 `build/video/face_box_routed_review_20261103`，状态 `TIMING_FAILED`，
没有生成或交付此版位流。

本机PDS独立小例子中，0.001ns的max-skew约束未反映到全局PASS和文本表，而两位延迟
已相差0.068ns。因此新增独立验收：核对23组116位Gray全部慢/快角数据路径，并通过定向
STA收集源/目的时钟的早/晚延迟，共928条观测。以源时钟范围+非负数据延迟上界+目的时钟
范围保守界定跨位相对到达时间差；最差上界4.145ns，各组均满足各自6/20ns约束。
证据 `build/video/face_box_gray_clocks_review_20261103`。脚本严格要求全位/全角覆盖；
8项时序/Gray负对照及6项时钟/管脚负对照PASS。完整资格入口也准确拒绝本次setup失败。

保持逻辑、固件、布局、时钟和全部时序约束不变，从实际67条违例路径选出17条延迟≥0.65ns
的CPU网络，加入优先布线RCF，PDS全部接受。新运行
`build/video/pds/face_box_cpu_priority_route_20261103` 正在进行，仍有90分钟硬上限。
完成后重新生成全部物理证据，旧版Gray/时序结果不能代替新routed DB的验收。实板继续延后。

### 2026-11-03 13:54 计算域改为实际80MHz，重新构建与整机回归

100MHz CPU网络优先布线仍未满足setup：慢角 -0.859ns/126端点，原始结果保留在
`build/video/face_box_cpu_priority_review_20261103`。按用户功能优先、帧率放宽的指示，
当前计算域改为实际80MHz；Video/DDR125MHz及像素40MHz不变。GPLL采用125MHz输入、
I=5/M=16/F=2/O=10、VCO800MHz，STA比值16/25，保持0.2ns应用域margin及所有CDC界限。
这不是仅放宽SDC来接受100MHz位流；原100MHz两次route均未生成交付位流。

先修改时钟测试，旧PLL在12.5ns周期断言处准确失败；修改PLL后，厂商实际GPLL模型正例及
3项连接/复位负对照PASS，6项时钟契约检查PASS。15项构建/管脚/打包检查通过后启动新构建，
使用显式 `--plc-decongestion 3`；源码、固件和模型再次冻结。
新有脸整机 `build/soc/face_system-20261103T055313_986442Z`、无脸整机
`build/soc/face_system-20261103T055314_011073Z` 正在执行，不能沿用100MHz的PASS作为80MHz结果。
新构建绑定前者生成的ELF；首次时钟/功能/时序全通过之后再生成位流。未扫描或下载实板。

### 2026-11-03 14:14 80MHz有脸/无脸完整整机均PASS

两组均完成45035813个计算周期、4次捕获/请求、2次结果/记录/提交、1次释放/复用、
2个完整800×600 BOX画面，模式010，0 errors/0 warnings。有脸场景HEAD逐字节符合独立
参考，框像素校验通过；无脸场景无误框。两组当前输入/输出哈希再次核验通过，与新PDS
快照共用134个文件一致；ROM/SRAM解码逐字一致，有脸ELF与构建ELF完全一致。
路径沿用13:54记录，当前摘要已将100MHz历史记录与80MHz结果分开。

新物理构建 `build/video/pds/20261103T055401_228008Z` 已完成映射/布局，布局末次setup
估算+1.010ns，正在详细布线。布局估算不作为最终时序验收，目前仍无交付位流。

### 2026-11-03 14:33 80MHz首次route完成，setup尚未收敛

`build/video/pds/20261103T055401_228008Z` 完成307轮布线，未布通为0，hold修复完成。
独立全量routed STA及实际位置导出保存在 `build/video/face_box_80_review_20261103`，
状态 `TIMING_FAILED`：慢角compute setup -0.785ns/54端点、DDR/video -0.230ns/9端点；
hold慢/快最差 +0.024/+0.017ns，其他类别均无违例。数据Gray 23组116位双角覆盖完整。
NPU地址计算路径中布线占76%，视频MMIO读响应路径布线占82%，不能沿用布局正slack宣称收敛。

新增 `scripts/video/reroute_face.py`，直接读取冻结mapped DB，不重复综合或改变已验证RTL/时钟。
当前performance模式、seed5、decongestion3新实现位于
`build/video/pds/face_box_80_performance5_20261103`；输入前后校验、独立目录、超时失败返回，
后续仍须独立全量STA及CDC/管脚验收，不能将ROUTE_REVIEW_READY等同timing通过。
有脸/无脸80MHz整机PASS继续有效；本批无可交付位流，实板未连接/扫描/下载。

### 2026-11-03 15:06 实际50MHz与视频MMIO读请求寄存级

80MHz performance seed5已完成335轮详细布线及hold修复，最终独立STA仍失败：
`build/video/face_box_80_performance5_review_20261103` 慢角setup -1.899ns/309端点，
hold慢/快 +0.137/+0.099ns，recovery/removal/pulse均通过。多条NPU输入/量化控制长路径
仍失败。seed6在确认自身PDS PID7824及命令行后停止，以转入逻辑和实际时钟调整；
其未完成结果保留为FAIL，停止理由见该目录stop_review.json，没有冒充时序结果。

按功能优先、推理FPS不设门槛，将实际compute PLL改为50MHz：I5/M16/F2/O16，VCO800MHz，
STA比值2/5；DDR/video125MHz、pixel40MHz及原有uncertainty/CDC界限保持。旧80MHz PLL
在20ns新周期断言处准确失败，证据 `build/video/face_board_clocks_50_red_20261103`；
修改后的实际厂商PLL模型正例、3项连接/复位负对照PASS，6项静态时钟契约PASS，
证据 `build/video/face_board_clocks_50_20261103`。

视频DDR域关键路径从共享AR地址总线到MMIO响应控制，增加一项AR请求寄存器隔离。
接受后固定地址，若记录拷贝占用RAM则等待，背压时保持响应，复位丢弃未完成请求。
新CASE10先在旧RTL准确失败（拷贝占RAM时不能接收请求），证据
`build/soc/resource_probe_video_compact_20261103T070053_149196Z`；修改后1653检查PASS。
初次测试编号与既有driver trace CASE9冲突的失败也保留，修正编号后才建立有效红灯。
完整组件回归 `build/soc/resource_probe_video_compact_20261103T070209_315891Z` 正在执行，
正常显示组合已PASS；15项时钟/物理管脚/构建选项/打包检查PASS。

新有脸整机 `build/soc/face_system-20261103T070341_048946Z`、无脸整机
`build/soc/face_system-20261103T070341_033768Z` 均已进入真实NPU；新PDS构建
`build/video/pds/20261103T070558_933114Z` 绑定有脸ELF，normal/seed4/decongestion3。
源码冻结，不用80MHz旧功能PASS替代本轮。当前仍无可交付位流，实板未扫描/下载。

另核对配套MS7210/MS7200 V1.0手册，电气章节只有极限/DC参数，没有视频接口setup/hold
或clock-to-data AC表；本地来源哈希见 `build/video/hdmi_ac_20261103/result.json`。
当前HDMI模式固定800x600/约60Hz，与推理FPS无关，已补入应用和打包说明。

15:09 补记：上述完整视频组件回归已PASS，共27项组合用例及246项record guard边界；新排队读CASE10含1653检查。50MHz整机与PDS继续运行，未更改冻结输入。

### 2026-11-03 15:24 50MHz两组整机回归及源码对齐PASS

有脸 `build/soc/face_system-20261103T070341_048946Z`、无脸
`build/soc/face_system-20261103T070341_033768Z` 均完成40581783计算周期、4次捕获/请求、
2次真实推理/记录/提交、1次释放/复用、2个完整800x600画面，modes=010，0 errors/0 warnings。
有脸HEAD逐字节符合独立参考且框像素正确，无脸无误框。输入/输出哈希均重新核验；
与当前PDS快照共用134个源文件完全一致，ROM/SRAM逐字一致，有脸ELF字节完全一致。
审计 `build/video/face_box_50_sim_alignment_20261103.json`。

新PDS已完成综合/映射/布局：42531 LUT、43408寄存器、77.5 DRM、58 APM；布局估算
setup +1.092ns，正在详细布线。仍须最终routed STA、全位Gray时钟/数据界限及位流生成，
当前不能宣称时序收敛或已交付。实板保持未连接/未扫描/未下载。

### 2026-11-03 15:47 50MHz首次route仅余捕获控制路径，定向重布线

`build/video/pds/20261103T070558_933114Z` 完成463轮详细布线、0未布通及hold修复。
独立审计 `build/video/face_box_50_review_20261103` 仍为TIMING_FAILED：计算域setup
+1.145ns，DDR/video慢角仅3端点失败，WNS -0.059ns、TNS -0.176ns；其余所有双角类别通过，
hold最差慢/快 +0.068/+0.053ns。三条路径共用video_reset_n经B响应、DMA ready、rearm_empty
到capture状态机CE；延迟约88%来自布线。不能将59ps违例视为通过。

新增reroute入口可复用已审查布局，并仅接受def_route -prior_net形式的RCF；同一mapped/
placed DB及约束保持哈希绑定。正在运行 `build/video/pds/face_box_50_capture_priority_20261103`，
normal模式，仅优先原报告实际7条网络。其来源报告/RCF哈希见
`build/video/face_box_50_capture_priority_20261103.json`。不降低125MHz视频时钟，不放宽margin、
不扩大false path。此轮没有RTL/固件变更，50MHz有脸/无脸整机证据仍匹配同一网表源输入。
新route完成后重新执行全部STA、Gray时钟/数据、物理位置及输入一致性检查，成功后才生成位流。
当前没有交付位流；板卡保持未连接、未扫描、未下载。

补记：本轮50MHz失败报告的10项审计负对照均PASS，证据 `build/video/face_box_50_failed_route_controls_20261103.json`；baseline_timing_met仍为false，负对照通过不等于物理时序通过。

### 2026-11-03 16:13 定向布线消除setup违例，继续修复DDR内部单条hold

`build/video/pds/face_box_50_capture_priority_20261103` 完成398轮详细布线、0未布通。
独立审计 `build/video/face_box_50_capture_priority_review_20261103` 确认所有setup通过，
最差慢角+0.002ns；但DDR内部dcd_wr_addr[26]到fifo_rdata_b[31]/DIH短连线仍有一个hold
端点失败，慢角-0.026ns、快角-0.014ns。其余类别通过。原生hold-fix阶段初步数字
与独立STA略有区别，以后者为准。该route继续记为TIMING_FAILED，未生成位流。

根据已安装PDS用户手册第108–109页及help pnr，新增显式hold修复选项：迭代上限30、
正余量目标100ps、布线时hold修复开启、clock-tree修复阈值100ps。这些参数让工具修复
slack低于目标值的物理路径，不改变SDC/uncertainty，不改厂商RTL。4项非法数值边界拒绝检查PASS。
新run `build/video/pds/face_box_50_capture_hold100_20261103` 复用同一mapped/placed DB及7条
关键网络优先级；源码和固件仍为已通过50MHz整机仿真的版本。完成后重新审查所有时序类别。
板卡仍未连接/扫描/下载，暂无合格位流。

### 2026-11-03 16:36 hold余量优化未改变违例，缩小布线优先范围

`build/video/pds/face_box_50_capture_hold100_20261103` 已完成398轮布线和hold修复。
原生日志仍报告DDR地址短路径-26ps/-14ps，后续明确写有`Hold violation fix failed`；
工具先写“fixed successfully”却仍列负slack，不能据该措辞验收。后布线修复实际执行一次，
30次是上限，未解决该路径；独立review继续保留最终证据。

新run `build/video/pds/face_box_50_bvalid_priority_20261103` 保持同一网表、布局、时钟和
时序约束，将优先网络从7条缩到原始失败报告中延迟最大的低扇出段video_c_bvalid
（1.536ns），目标是改善捕获setup路径并减小其他布线扰动。仍开启30次/100ps hold优化。
实测来源与RCF哈希见 `build/video/face_box_50_bvalid_priority_20261103.json`；必须重新
全量审查，不能借用前轮正slack。当前无合格位流，未操作板卡。

### 2026-11-03 18:07 修复PDS单RCF覆盖问题并重新保留DDR时钟优先级

单BVALID优先级试验最终STA为setup最差+0.051ns，仍有DDR地址短线hold -0.028/-0.015ns。
使用computer-use技能只读打开原始50MHz主构建的PDS Design Editor，查询dcd_wr_addr[26]：
其hold通过的原始路线经14个引脚绕行至CLMS_327_163/AD。保存完整窗口/命令/输出至
`build/video/face_box_50_ddr26_route_observation_20261103.txt`，源DB与报告哈希均绑定。
未保存或修改原始DB，也未执行硬件操作。

固定该分支的 `face_box_50_ddr26_fixed_20261103` 最终仍失败：setup -0.059ns/3端点、
hold -0.028/-0.015ns/1端点。检查原生日志发现两个构建问题：PDS只允许一个RCF，后添加
文件会以RouteConstraintEditor-4001覆盖前者；固定路由还因两个端点在已导入的plc DB中
未标成显式约束而被2004/2006拒绝。因此旧多RCF试验没有保留原来的两条DDR时钟优先级。
原始50MHz主构建仅一个RCF，未受覆盖问题影响；所有这些试验均未生成合格位流。

修复reroute入口：将原始DDR两条及应用优先级合成单一routing.rcf；读取日志发现任一
RouteConstraintEditor警告/错误立即终止自身PDS进程并返回FAIL。新增4项回归PASS，涵盖
合并保留全部约束、覆盖警告拒绝、端点拒绝、成功消息。补上源报告中的端点PCF后，
`face_box_50_ddr26_merged_20261103` 仍被导入布局的端点检查拒绝，现已提前FAIL，没有再空跑。
固定分支方案尚未获工具接纳，不作为已完成修复。

当前 `build/video/pds/face_box_50_preserved_phy_20261103` 复用同一50MHz网表和布局，单RCF
确实包含原始2条DDR时钟优先级和1条BVALID优先级，未使用被拒绝的固定分支。三条命令均被
PDS接受，已进入全局布线。保留30次/100ps hold优化；源码、固件、FDC时钟/uncertainty不变。
之后仍须全量STA及Gray/物理/仿真输入核验才能生成位流；板卡保持未连接、未扫描、未下载。

### 2026-11-03 18:30 保留DDR约束后hold通过，继续处理7个setup端点

`face_box_50_preserved_phy_20261103` 完成297轮详细布线、0未布通，独立STA确认双角hold
全部通过，最差慢/快 +0.068/+0.052ns；recovery、removal、pulse width也均通过。
100ps是额外hold优化目标，原生日志“fix failed”对应未达到该目标，不能替代最终STA判断。
慢角setup仍有7个端点失败，最差-0.203ns、TNS -0.387ns；计算域+1.850ns。失败分为
模型加载器地址CE、内存桥span CE、显示mailbox CE及MMIO request_seq CE四类。

独立审查 `build/video/face_box_50_preserved_phy_review_20261103` 最终状态为FAIL：除上述
setup外，Gray审查还拒绝 ingress/fifo/wr_gray[8] 路径中新增的 CLKROUTE_107/CR 单元。
该路径最大延迟0.741ns、约束20ns，但尚未证明该物理单元的功能，不能仅凭正slack验收。
审查器继续严格拒绝，未生成位流；原始失败证据保留。

新run `build/video/pds/face_box_50_balanced_priority_20261103` 复用同一网表和布局，在单RCF
中保留原厂2条DDR优先级、原BVALID优先级，并按实际报告加入上述四类的最长连线，共7条。
来源报告与RCF哈希见 `build/video/face_box_50_balanced_priority_20261103.json`。不改逻辑、
固件或时序例外；同时核实新增路由单元的实际功能。仍需全量审查才能生成合格位流。

18:39 补记：已只读导出上述FAIL route的实际后布线功能网表，源DB前后哈希不变，
证据 `build/video/face_gray_route_netlist_20261103`。CLKROUTE_107/CR对应
CLMS_75_1081/ntM3 的V_BUF，从wr_gray[8]/Q到同位sync1/D；原厂V_BUF模型为恒等赋值，
模型哈希固定校验。新增审查只允许这种可追踪的同位恒等缓冲链，要求物理位置/级数匹配STA，
仍计入整个路径延迟，不放宽20/6ns约束。原生全116位数据界限检查PASS；10项单元回归PASS，
覆盖反相、错误位、额外逻辑、重复端点、环、位置/级数不符及网表/模型/route证据不符。
旧审查脚本与哈希备份至该导出目录的prior_auditor，旧FAIL结果保持不变。
当前以新审查重新导出独立STA/位置/网表至 `face_box_50_preserved_phy_identity_review_20261103`，
用于验证完整流程；该历史route仍有已知setup违例，不能生成位流。balanced_priority主run继续布线。

18:43 补记：上述完整identity review已结束，116位Gray数据审查PASS；仍因7个setup端点返回TIMING_FAILED。新流程的10项原生报告/位置负对照全部PASS，证据 `build/video/face_box_50_identity_review_controls_20261103.json`，baseline_timing_met=false。

### 2026-11-03 18:55 setup缩减到单端点，定向优化内存桥及hold余量

`face_box_50_balanced_priority_20261103` 完成490轮布线、0未布通。独立review为TIMING_FAILED：
慢角setup仅1个端点，WNS -0.135ns，位于u_memory/u_arbiter/length_q[4]到u_bridge/span_q[2]/CE；
所有其他双角类别通过，hold最差慢/快+0.137/+0.100ns，116位Gray数据界限PASS。
原生另有STA-3017/Timing-4105：一条rgb_pipe像素路径fast hold为149ps，低于额外200ps优化目标。
已核对PDS User Guide第110–111页：此提示针对用户设定的修复余量，并非自动等同于负slack；
本轮仍保留未验收，未放宽检查或生成位流。

新run `build/video/pds/face_box_50_bridge_priority_20261103` 保留前5条应用优先级及原厂2条DDR
优先级，补入剩余路径的m_arlen[4]、共享末级_N447056_1及N1805三条实际网络，共10条单RCF。
将post-route和clock-tree hold修复目标提高至200ps（原100ps），让上述149ps路径也进入后布线
修复范围；cross-SRB默认200ps保持不变。STA时钟/uncertainty/例外、网表和布局均不变。
证据 `build/video/face_box_50_bridge_priority_20261103.json`；自动审查链重新等待新DB，全部通过
才生成位流。实板保持未连接、未扫描、未下载。

19:05 备选分析（未改RTL）：针对内存桥剩余路径，证明在128MiB页对齐窗口和现有4KiB边界检查成立时，起始地址上下界检查可替代33位exclusive_end上界/溢出比较。8个代表性边界页×4096偏移×256长度编码，共8388608组合一致，证据 `build/video/face_bridge_window_proof_20261103.json`。仅为后续可能的逻辑优化依据，不是新硬件仿真或时序通过。当前仍等待冻结的bridge_priority route。

### 2026-11-03 19:19 首次50MHz完整内部STA通过

`face_box_50_bridge_priority_20261103` 完成464轮详细布线、0未布通。独立review
`build/video/face_box_50_bridge_priority_review_20261103` 返回REPORTS_READY：setup慢/快
+0.183/+2.961ns，hold +0.143/+0.108ns，recovery +2.373/+4.241ns，removal +0.335/+0.230ns，
pulse width +0.035/+0.035ns，全部0违例。原生后布线修复消除了本轮DDR hold负值；原来的
STA-3017/Timing-4105跨SRB余量提示未再出现。部分非SRB路径未达额外200ps优化目标的日志
不等于STA负值，以独立双角表为准。116位Gray数据界限也PASS。

当前正在运行 `face_box_50_bridge_priority_clocks_20261103`，仍需928个早/晚时钟观察、
最终管脚/DDR站点/来源一致性及消息核验后才能生成位流。尚未宣称外部HDMI AC或板测通过。

### 2026-11-03 19:23 离线BOX交付包完成，等待设备连接

全位Gray时钟审查PASS：23组、116位、928个双角早/晚观察，最大保守界限4.233ns；
14项最终审查负对照PASS。qualify返回FACE_QUALIFY_PASS，核验140个实际管脚、两个DDR
门控固定位置、134个仿真/实现共有源文件、ROM/SRAM/ELF及模型来源，消息审查0拒绝。
位流生成前后输入/证据哈希均一致，没有放宽时钟、uncertainty或CDC例外。

交付目录：`build/video/releases/triha_face_board_3939c52f4d94`。
包含triha_face_board_top.sbit、同名.smsk、manifest.json、timing.rtr、message_review.json、README.txt。
位流和掩码均3791112字节；位流SHA256
`3939c52f4d94cd50476905a206f50ae82347f864604f4b8bb8c98a6fefd51e65`，掩码SHA256
`d3ca5bbce1a9e90e4ee1ca568df24fd1d10d78505e96ecaff1da8bad5a8997fd`。
独立包字节/哈希复核PASS：`build/video/face_box_50_release_audit_20261103.json`。
最终资格记录 `build/video/face_box_50_bridge_priority_qualified_20261103/result.json`。

内部后布线时序与CDC通过；外部HDMI I/O AC和实板功能仍未验收，manifest明确保留false。
未扫描JTAG、未编程、未访问串口。已告知用户可连接设备，等待连接状态回复，再继续易失JTAG
Program/Verify、六段--model-only上传及800x600输入的人脸/无人脸实测。模型加载后自动BOX，
主脸检测框；帧率只记录。备选内存桥布尔化简未实施，交付RTL仍是通过两组整机仿真的原冻结版本。

### 2026-11-03 19:36 用户接板后JTAG下载/校验通过，模型上传中

用户明确回复“已连接，可以开始上板验收”。只读扫描识别USB Cable II、PG2L100H、
ID 00602899，证据 `build/video/jtag_scan/20261103T112627_147954Z`。
program_board入口补入triha_face_board目标，继续执行原有包/来源/器件ID检查；本文件不在
位流冻结输入中。已成功执行易失Program及Verify，证据
`build/video/board_program/20261103T112808_536586Z`，对应位流SHA3939c52f4d94…，未写Flash。

CP2102实际已接入，但最初Windows报告代码28、未装驱动；未向其他COM端口发送模型。
用户随后自行安装驱动，重新枚举确认CP210x状态OK、COM12、VID10C4/PIDEA60、序列0001。
正在运行 `upload_face_model.py --model-only --port COM12`，前两段已获硬件ACK，累计118528字节。
六段共1770496字节；后处理表为最大段，当前正在传输。下载/ACK不等于整机功能板测通过，
接下来仍需模型seal及HDMI有脸/无脸与同帧框观察。

19:38 补记：六段模型已全部上传并封存，`build/soc/model_upload-20261103T113330_193913Z`
为PASS_UART_LOADER_ACK：1770496字节、6916包、0重试、最终ACK游标(6,0)，model_seal_acknowledged=true。
已请求用户在800x600@60Hz输入上显示清晰正脸并观察实际输出；尚未收到画面结果，不能据ACK
宣称人脸检测实板闭环已通过。当前保持设备运行，不重置或改写已封存模型。

### 2026-11-03 19:41 第一优先级真实人脸检测实板功能验收通过

模型封存后，用户首次观察确认“画面正常，且人脸上出现检测框”；随后按要求移动/更换人脸位置
并切换无人脸场景，确认“都正常：框更新、无脸消失、画面继续更新”。这些为用户人工画面确认，
不冒称自动视频采集或板上性能计数。结合已下载的DEMO_BOX_ONLY=0真实B03位流、精确模型CRC/
ACK和两场景整机仿真，首优先级的HDMI输入→真实推理→同帧主脸框输出闭环完成。

完整交付关联记录 `build/video/face_box_board_acceptance_20261103.json` 将最终资格、包、JTAG
扫描/Program/Verify、模型加载及两组仿真结果按SHA256绑定，保留两次人工确认原文。
内部双角时序及CDC均通过；外部I/O AC未正式签核、FPS未测，不混同于本轮功能验收。
头像/五点仍不在本轮范围。当前保持开发板运行；易失配置断电后需重新JTAG下载及六段模型上传。
未写Flash，未实施前述备选内存桥布尔化简。用户的第一优先级功能目标已完成。

### 2026-11-03 19:56 按用户要求重新烧录并加载模型

再次使用已验收的 `triha_face_board_3939c52f4d94` 交付包，来源与位流/掩码哈希检查通过。
PG2L100H / 00602899 的易失 JTAG Program/Verify 均成功，记录为
`build/video/board_program/20261103T115107_784037Z/result.json`。
随后在确认身份的 CP210x COM12 上重新上传六段模型：1770496 字节、6916 包、0 重试，
最终 ACK 为 (6,0)，模型封存通过，记录为
`build/soc/model_upload-20261103T115137_079011Z/result.json`。
关联哈希收据位于上述 board_program 目录的 `reprogram_and_model_load.json`。
当前保持开发板运行，未写 Flash；本次未重复要求人工画面验收，也不把此前的人工确认记作本次新观测。

### 2026-11-03 当前性能数据提取（仿真参考，非实板测速）

用户询问当前帧率。已从最终资格绑定的两组50MHz整机仿真中提取连续CPU后处理结果完成标记，
逐一验证结果文件与simulation.log的SHA256。正脸的完成周期为21491404与39578629，
间隔18087225周期，即361.7445ms／2.764382结果帧每秒；无脸为21466225与39528043，
间隔18061818周期，即361.23636ms／2.768271结果帧每秒。每个场景仅有一个间隔样本，
不能称作长期平均或实板测量；该口径排除了启动/加载时间，包含CPU后处理及帧间调度。
采集源与native DDR端点为仿真模型，不能用结果间隔代替纯NPU耗时或采集至显示的端到端延迟。

绑定配置的HDMI输出为800x600，40MHz/(1056x628)=60.316541Hz，扫描周期16.5792ms；
重复扫描同一已提交帧不代表产生新的检测结果。当前UART仅连接boot ACK，未提供运行时性能
读出，因此本次未访问/重置开发板，实板FPS仍未测。后续实测应导出统一时基、推理/结果/显示
提交计数与同帧起止时间戳，排除预热后记录足够时长，并保留现有已验收交付包。
派生数据、来源哈希与限制见 `build/video/face_box_performance_20261103.json`。

### 2026-11-03 已验收版本的GitHub交付与干净目录复现

按用户要求，将当前BOX版本及位流纳入 `releases/face-box-20261103/`，使用Git保存原始
`.sbit`/`.smsk`和四个小于50MiB的压缩包，不依赖Git LFS或外部临时下载地址。
包内有当前模型、自然人脸fixture、原固件、生成IP、冻结物理数据库与原始验收证据；
厂商工具/许可证仍由安装环境提供。历史失败路由保持原状态，不改写为通过。

新增restore_face_release入口，校验209项源码及996项归档成员，恢复998个文件至build；
冲突内容拒绝覆盖，默认只校验，不访问开发板。Git属性固定11项此前可能被换行转换的
已冻结输入。已从Git索引导出到独立新目录，完成恢复和模型审计、固件/RTL编译。
编译出的ROM/SRAM逐字节相同；ELF仅GCC随机临时对象名有6字节差异。
从冻结路由数据库运行PDS重新生成位流及掩码，除文件头日期/时间外其余每字节完全一致，
通过PASS_CONFIGURATION_IDENTICAL。原发布位流不修改；比较器拒绝器件/数据/格式变化。
8项恢复负向检查、6项位流比较测试、10项Gray证明测试、4项路由约束测试通过。
没有重新进行实板操作或完整整机仿真，原正负场景回归继续由源码哈希绑定。

发布README给出安装、下载、模型上传、冻结数据库回放及从源码重建完整命令。
从源码重建仍需固定工具环境和官方板卡手册，并对新物理实现重新验收；不承诺跨工具版本
的布局布线字节确定性。发布目录的 `verification.json` 保存本次复现结果。

### 2026-11-03 20:57 头像叠加目标启动：功能仿真通过，进入物理实现

用户在已发布BOX基础上要求实现头像，并明确设立目标持续推进。保留tag
`face-box-20261103`及其原始位流，当前基线为ab8ebb3。复用仓库原创256x256透明头像，
按真实主脸框中心及1.25倍覆盖系数定位/缩放；五点/姿态旋转不在本二维功能范围。
KEY1经CPU提交RAW→BOX→AVATAR，七段模型/素材完整校验后启用。

当前50/125/40MHz正脸与无脸整机回归均PASS：
`build/soc/face_system-20261103T123428_227974Z`、`...T123428_271099Z`，
均41410743周期、两次真实推理、modes=111、完整帧像素/同帧身份/模式提交/槽释放复用通过，
零错误和警告。134项共享源码及ROM/SRAM与综合字节/字值一致，正脸ELF完全相同；
`build/video/face_avatar_50_sim_alignment_20261103.json` 保存绑定。

实际65536 texel缓存在两个时钟比通过，坏CRC被拒绝，证据
`build/video/avatar_ddr/20261103T123631_710851Z`。素材原始RGBA、SVG、清单可逐字节重生；
旧gen_fixed_avatar --check仅因PNG压缩编码不同报错，解码像素相同。现对PNG预览核对像素，
运行RGBA/清单/C/RTL常量继续逐字节检查；两项测试确保像素/alpha与运行字节变化仍拒绝。
实际素材及预览文件未改写。

综合 `build/video/pds/20261103T123539_673117Z` PASS，48663 LUT、47709 FF、141.5/155 DRM。
新增map_face_synthesis把冻结综合复制到新目录继续映射，未重新综合或改写旧记录；
`build/video/pds/face_avatar_50_map_20261103` PASS。单次seed4/normal/decongestion3路由在
`build/video/pds/face_avatar_50_route_20261103`运行，hold修复30轮、目标200ps，约束不放宽。
验收脚本现区分精确BOX/AVATAR参数、六/七段模型加载、三模式像素覆盖、头像oracle及KEY1物理端口；
四项profile测试和四项路由约束测试通过。应用4007项、上传器8项及真实模式键回归也通过，
证据 `build/soc/face_avatar/20261103T125815_617326Z`、`build/soc/face_mode_key-20261103T125815_653946Z`。
尚未声称布线/时序/位流/头像板测通过，开发板未操作。
活动状态入口为 `docs/verification/npu/2026-11-03-face-avatar-bringup.json`。

### 2026-11-03 21:10 用户指定照片替换卡通素材，继续同一头像目标

用户提供透明头像PNG并要求使用该图。原图原样保存为assets/avatars/triha/source.png，
SHA256 c2904a1831374d73c1b1b83d58de6f7cfd54f14b9dbc029a585179f71094b3b1。
gen_fixed_avatar现从已绑定原图确定性转换256x256 RGBA，保留alpha，无裁剪/修饰/生成新人物。
素材generation改为2，定位锚点(128,160)、覆盖系数1.5，为头发留出上方空间；这是固定二维
近似对齐，仍不宣称五点/旋转。转换、像素与运行字节负向检查及七段素材审计通过。

原卡通物理运行在用户改图后主动终止（不是时序失败）；日志、数据库、两组已通过仿真保留
为历史记录，不用于新照片验收。只停止了本任务的旧PDS与等待协调器，未操作开发板。
新正/负场景回归为build/soc/face_system-20261103T131024_940165Z和...T131024_940464Z，
已启动配套50MHz固件综合，完成后重新映射、布线、双角STA和CDC验收。

用户允许收敛困难时改用SD卡。当前素材通过UART装入DDR，显示缓存额外占约64 DRM；
换加载来源本身不减少缓存或改变像素关键路径。先按实际后布线瓶颈决定是否缩小/重构缓存，
SD作为后备素材加载来源；本批未引入未验证的SD控制器。

21:19 新照片配置综合通过：48670 LUT、47708 FF、141.5/155 DRM，目录
build/video/pds/20261103T131112_702512Z；固件SHA为13d97fb46c514b0ebfa593c2730086fff36ad5728dbafeee456b42c54d5fdfa5。
自动流程build/video/face_photo_50_pipeline_20261103/receipt.json已进入映射，随后将运行
新的布线/双角时序/Gray时钟审计；任一步失败都不会生成下载包。
新素材的4007项应用检查通过，记录build/soc/face_avatar/20261103T131337_429232Z。

21:28 新照片配置布局估算最差slack +0.452ns、TNS=0，进入详细布线；不是最终STA结论。
只读JTAG最初两次只能找到USB下载器，用户重新接好电源和JTAG后，
build/video/jtag_scan/20261103T132743_664738Z成功识别PG2L100H / 00602899。
本批没有Program/Verify、复位或UART上传；新配置待完整资格通过后下载。

21:32 指定照片的正脸、无脸整机回归全部PASS，各41410743周期、两帧真实推理、三模式完整
像素检查（modes=111）、同帧身份/显示提交/释放复用通过，零错误和警告。134项共享源码与
综合一致，ROM/SRAM字值一致，正脸ELF与综合输入SHA一致；绑定记录为
build/video/face_photo_50_sim_alignment_20261103.json。

从两次CPU结果完成标记计算仿真间隔：正脸361.5812ms（2.76563结果/秒）、无脸361.20636ms
（2.76850结果/秒）。每场景仅一个间隔，含CPU后处理及调度，使用native DDR仿真代理，
不能称为实板FPS或端到端延迟。记录为build/video/face_photo_performance_20261103.json。
当前仍在详细布线，没有新位流、Program/Verify或照片板测结论。

### 2026-11-03 21:58 新照片第一轮布通，正式时序未通过，继续定向重布线

第一轮face_photo_50_route_20261103共402轮、0未布通网络，保持修复6轮；
完整STA为TIMING_FAILED，不生成位流。最差setup -1.331ns为DDR PHY写DQS，
125MHz内部控制域最差-0.832ns、249个setup端点；最差hold -0.001ns为采集DMA到SRB。
CPU50MHz最差setup +0.150ns，像素40MHz +1.224ns。主要慢路径布线占比高，
例如帧所有权检查的最差路径85.3%为连线延迟；不能把此次失败归因于照片存放位置。

从每个违例起点的最坏路径选两条最大数据连线，共18条优先级，保留原2条DDR约束并合成
唯一RCF。证据build/video/face_photo_50_priority_20261103.json绑定原报告及RCF哈希。
复用已冻结布局，在build/video/pds/face_photo_50_priority_20261103重新路由；
源RTL、固件、50/125/40MHz时钟、时序例外及约束均未改变，继续使用同一套已通过照片仿真。
自动流程为build/video/face_photo_50_priority_pipeline_20261103/receipt.json。
旧失败日志和报告保留；没有Program/Verify、模型上传或照片画面验收声明。
代码与素材已本地提交ab4e999，未推送新版本；原BOX tag不变。

### 2026-11-03 22:53 — supplied-photo lossless cache to relieve RAM pressure

- Second full-cache route is **TIMING_FAILED**, not downloadable: `build/video/face_photo_50_priority_review_20261103/result.json`. Setup: DDR system −0.405 ns, compute −0.491 ns, DDR-to-PHY −0.934 ns; hold minimum 0.000 ns. Four native cross-SRB paths remain below the extra 200 ps requirement. Clocks and acceptance thresholds have not been relaxed.
- Keep the user's photo and all 65,536 RGBA texels exactly unchanged. Per-row all-zero margins need no storage; retain 34,331 texels / 137,324 bytes and return zero outside the admitted spans. Split main/tail RAM avoids rounding one 34,331-word array to 65,536 words. Display still responds at one pixel per clock with the same latency.
- New compact-preset rejection test first failed against the generic implementation (`build/video/avatar_ddr/20261103T144745_953286Z`). After implementation, all eight compact cases pass (`build/video/avatar_ddr/20261103T145037_751939Z`): 65,538 reads in each positive/ratio/reset case; wrong ID, generation or CRC rejected before DDR; changed payload fails CRC; nonzero omitted data fails closed. Generic 24-case DDR suite and mode-resources suite also pass.
- Generated span table is included in frozen synthesis/simulation inputs. Source PNG SHA and runtime RGBA SHA remain unchanged. Asset storage is an implementation detail; upload remains the same seven-segment full RGBA protocol.
- New full-system positive/negative simulations: `build/soc/face_system-20261103T145108_340149Z` / `...385397Z`; synthesis: `build/video/pds/20261103T145127_860103Z`. **Running**, no claimed resource or timing result yet. Then map, route, full STA/CDC and bitstream qualification. No photo-version board programming has occurred; accepted BOX release remains available.

### 2026-11-03 23:00 — compact-cache PDS diagnosis

- Production synthesis attempts `20261103T145127_860103Z` and `20261103T145530_412154Z` failed with native PDS signal 11 / Flow-0189 (compile database creation, then synthesis architecture building). The failures are preserved; neither supplies resource or timing acceptance.
- Isolated DDR/cache synthesis succeeds in `build/video/avatar_span_synth_probe_ddr_20261103`, physically inferring 32 main + 2 tail DRM for RGBA (34 vs prior 64), plus two half-DRM lookup tables: 35 equivalent DRM total. This is a synthesis-only diagnostic without production timing constraints.
- A separate full-design diagnostic copy `build/video/avatar_span_tail_probe2_20261103` uses power-of-two tail allocation and explicitly narrow tail RAM addressing. It cannot produce a qualified package. Current production source and the two ongoing frozen full-system simulations remain unchanged.

### 2026-11-03 23:13 — lossless-cache simulations pass; unused-function workaround

- Both original compact-cache full-system runs are **PASS**, zero errors/warnings: `build/soc/face_system-20261103T145108_340149Z` (face) and `...385397Z` (no face). Each has 41,410,743 compute cycles, 4 captures/requests, 2 results/records/commits, 1 release/reuse, full-frame RAW/BOX/AVATAR checks (`modes=111`). They remain evidence for their exact frozen source version.
- Tail address-width experiment did not cure PDS signal 11. The successful isolated full-design experiment removes the **unused** 256-row function from `avatar_ddr_cache`, retaining its generated constant identity line. Of 377 copied inputs, only that file differs. `build/video/avatar_span_identity_only_probe_20261103` synthesizes with 48,883 LUT, 47,745 FF and 112.5 DRM (72.58%), vs 141.5 DRM previously. The cache still contains the actual row lookup. This diagnostic is not physical timing or downloadable acceptance.
- Production now generates a separate constant-only `avatar_span_identity.vh`; both headers are explicitly frozen in build/simulation inputs. Eight compact component cases pass again in `build/video/avatar_ddr/20261103T151205_807340Z`.
- Formal revised-source positive/negative runs: `build/soc/face_system-20261103T151233_715409Z` / `...715084Z`; synthesis: `build/video/pds/20261103T151254_336880Z`; coordinator: `build/video/face_photo_spans_50_pipeline_admitted_20261103/receipt.json`. All running. Original full-cache control experiment stopped intentionally after the useful diagnostic succeeded; marked cancelled, not a tool failure. No timing constraints, clock targets or photo bytes have been relaxed/changed.

### 2026-11-03 23:21 — production compact-cache synthesis PASS

- Formal synthesis `build/video/pds/20261103T151254_336880Z/result.json` is **pass** with unchanged frozen inputs. Actual utilization: **48,883 LUT, 47,745 FF, 112.5/155 DRM (72.58%)**. Against the supplied-photo full-cache version: +213 LUT, +37 FF, −29 equivalent DRM. The user's RGBA, CRC, geometry, serial protocol and clock targets remain identical.
- Native PDS failure is avoided by the generated constant-only loader include; the successful diagnostic is now independently reproduced by the formal build. Generic 24-case DDR regression also passes after this exact include change: `build/video/avatar_ddr/20261103T151928_905907Z`.
- Local source checkpoint: `1a36b55` (row-span cache); previous `ab4e999` (user photo). No new GitHub release or photo programming yet. Mapping/route coordinator remains active; exact-source positive/negative full-system simulations are still running. Synthesis success does not establish physical timing.

### 2026-11-03 23:34 — exact-source positive/negative full-system PASS

- Revised-source positive `build/soc/face_system-20261103T151233_715409Z` and negative `...715084Z` both **PASS**, zero errors/warnings. Each validates 4 captures/requests, 2 results/records/commits, 1 release/reuse and full-pixel RAW/BOX/AVATAR (`modes=111`) at 50/125/40 MHz.
- `build/video/face_photo_spans_50_sim_alignment_20261103.json` independently invokes the bitstream qualifier's functional admission against the mapped source, verifying all shared source hashes and ROM/SRAM words, including the generated span headers; positive ELF exactly matches synthesis.
- Result intervals remain 18,079,060 cycles / 361.5812 ms (face, 2.76563 results/s) and 18,060,318 / 361.20636 ms (no face, 2.76850). `build/video/face_photo_spans_performance_20261103.json` binds these to logs. One interval per scenario in simulation; **not measured board FPS**.
- Physical implementation continues in `build/video/pds/face_photo_spans_50_route_20261103`. Placement estimate −0.884 ns, so no closure claim; final routed STA/CDC and native critical-warning checks remain mandatory. No photo bitstream or board acceptance yet.

### 2026-11-03 23:57 — routed cache bottleneck; registered RAM-write stage

- Compact-cache first route/review is **TIMING_FAILED**: `build/video/face_photo_spans_50_review_20261103/result.json`. Slow setup DDR system −1.886 ns (330 endpoints), DDR→PHY0 −0.141 ns, DDR→PHY1 −0.476 ns. CPU +1.180 ns, pixel +8.727 ns. Both hold corners are nonnegative, minimum +0.121 ns; the native timing log has no STA-3017 critical warning. Router messages about its extra 200 ps repair target are not themselves negative STA slack.
- Exact worst path is span-control ROM → subtraction/range test → packed-last addition/validation → RAM WEA: **10 logic levels, 3.627 ns logic + 5.743 ns routing**. Original reports are retained (`build/video/face_photo_spans_50_failed_paths_20261103.txt`); this failing 125 MHz physical timing check drives the next change.
- Generated bounds now store exclusive right edges, so keep decisions use two parallel comparisons. Packed-last validation compares against constants without adding `keep_word`. A registered write enable/address/data stage isolates RAM from validation. Read sampling latency is unchanged. Core readiness is delayed until the physical final write commits; stream ready is closed while sealing, and reset cancels pending writes.
- Added an independent raw-RGBA stream bench before changing RTL. Continuous one-word-per-clock loading, reverse-order full pixel reads, second pixel-clock ratio, and reset after acceptance/before next write edge all pass before/after. Latest component run `build/video/avatar_ddr/20261103T155459_320871Z`: eight DDR cases plus three 65,536-word/65,536-pixel direct-stream cases. Generic 24-case suite: `...155600_896370Z` PASS. No texture-table lookup is used by the test oracle.
- New positive/negative full-system runs: `build/soc/face_system-20261103T155600_633574Z` / `...655389Z`; synthesis: `build/video/pds/20261103T155625_876936Z`; coordinator: `build/video/face_photo_pipe_50_pipeline_admitted_20261103/receipt.json`. Next route uses performance mode, seed 5, same clocks and timing constraints. **Running; not downloadable yet.**

### 2026-11-04 00:04 — registered-write production synthesis PASS

- `build/video/pds/20261103T155625_876936Z/result.json` is **pass**: 48,902 LUT, 47,797 FF, 112.5/155 DRM. Relative to the prior compact cache: +19 LUT, +52 FF, no extra DRM. Physical write enable/address/data are registered; the final seal follows the committed write, while pixel latency remains unchanged.
- The exact-source full-system simulations are still running. Coordinator now proceeds through mapping and performance-mode seed-5 implementation. No claim of routed timing closure or physical image acceptance yet; all earlier failed routes remain intact.

### 2026-11-04 00:11 — registered-write placement estimate improves

- Local source checkpoint `2c9e0e9` freezes the write-pipeline/bounds change and continuous-stream regression.
- Performance-mode seed-5 placement in `build/video/pds/face_photo_pipe_50_route_20261103/route.log` reports estimated **+0.415 ns**, TNS 0 before global route (previous compact version −0.884 ns). Routing has started. This is not final routed timing or qualification; both full-system simulations continue.

### 2026-11-04 00:17 — registered-write exact-source full-system PASS

- Positive `build/soc/face_system-20261103T155600_633574Z` and negative `...655389Z` are **PASS**, zero errors/warnings. Each has 41,410,743 compute cycles, 4 captures/requests, 2 results/records/commits, 1 release/reuse, and full RAW/BOX/AVATAR pixel checks (`modes=111`). The write pipeline preserves the visible frame contract.
- `build/video/face_photo_pipe_50_sim_alignment_20261103.json` verifies **136 shared source files**, all functional evidence hashes, ROM/SRAM contents and the positive ELF against `face_photo_pipe_50_map_20261103`. No old simulation is substituted for this revised source.
- `build/video/face_photo_pipe_performance_20261103.json` records unchanged simulated intervals: 18,079,060 / 18,060,318 cycles (2.76563 / 2.76850 results/s). These are simulation-only, not board FPS.
- Performance-mode seed-5 routing continues; no final STA or downloadable photo bitstream yet.
