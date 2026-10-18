# 同帧共享预览与双窗口验证

2026-10-18当前已验证版本为`0d3cf8f`的KEY0/HDMI复位分离，位流`33e1b8242053`；26套件数字回归、已分析内部物理路径，以及四角图/真实桌面的两次受控实体KEY0画面恢复均通过。其当前来源与状态见 [preview_link_reset.json](evidence/preview_link_reset.json) 和 [RX启动诊断](rx_image_geometry.md)。下文各代实现及`shared_preview.json`、`startup_guard.json`的“当前”字段属于各自生成时绑定的旧源码，不能用来批准新候选下载；旧KEY0图像失败结论继续保留。

2026-10-17实施，基线 `2f309c4`，设计/计划提交 `3b2844f`，分拍实现提交 `632a8d4`。当前109项输入的23套件回归和独立审查、125MHz八类内部时序及束路径审计通过。板上CRC一致性、扫描计数、60秒状态和实体KEY0复位前后统计均通过，但用户后续澄清窗口内容纯黑，原40054bd的画面验收结论已撤回，阶段重新打开。设计见 `docs/superpowers/specs/2026-10-17-video-shared-preview-design.md`。

## 黑帧与裁切问题历史（当前结论见文末）

用户确认窗口可为左右400×300，但内容纯黑。正常应显示该HDMI桌面的同一完整画面缩小后的两个副本。raw CRC `ebf5a8c4` 恰等于1440000个零字节的CRC，preview CRC `16fa9be1` 恰等于360000个零字节的CRC；与用户观察相符。双CRC一致只能说明传输数据一致，不能建立源内容正确的结论。初始诊断为 `build/video/preview_black_frame/result.json`，原汇总已按哈希另存。

后续使用完全相同的preview位流重新Program/Verify（`board_program/20261017T115658_117385Z`），raw/preview CRC变为 `48a69dc7/f6e6187d`，用户明确确认“已出现左右相同的源桌面画面”。纯净基线为 `board_serial/20261017T115938_584262Z`。这说明当前路径能够显示真实桌面，不应把黑帧直接归因于扩展屏设置或显示窗口布局。

随后连续记录 `board_serial/20261017T115954_960491Z` 再次复现KEY0后黑帧。此记录含三个epoch：原桌面、一次无源模式等待超时（error7，未采到像素）、另一次复位后完成但CRC恢复为全零帧值。用户确认“已按 KEY0，又变为纯黑”。不能将这段记录描述为一次干净的成功复位；目前实体KEY0后正确图像恢复验收失败。

切回RX诊断镜像后，用户再次按KEY0；`board_serial/20261017T121243_200974Z` 的7个type1快照均为正常模式、坏帧0、RGB签名非零，good_frames1035→1638。这段采集未覆盖复位瞬间。

后续持续、带主机接收时间戳的 `rx_startup_trace/20261017T121624_114412Z` 完整记录了一次KEY0。elapsed479115.638ms时RX尚未配置/锁定；480115.889ms时mode_good=true、good_frames5，但RGB签名0；482115.630ms时good_frames126、RGB签名34477。签名0本身有碰撞可能，主机时间戳也不是精确像素时间；结合先前全零CRC及黑屏，支持启动时序先就绪、源内容稍后恢复、单帧入口过早选择的原因。完整证据及哈希见 [preview_black_reset.json](evidence/preview_black_reset.json)。

当前候选修复增加128个连续完整好帧的稳定期（约2.12秒），之后才能选择下一帧；失锁/坏帧重新计数，RGB不参与准入，合法黑色输入仍可采集。此阈值针对本次源恢复观察，不保证所有HDMI源结束黑场的时刻。旧RTL在新增板级黑场测试上按预期失败，候选组件/板级测试与额外CRC观察、合法黑帧、六个突变检查通过。

新完整回归 `regression/20261017T122911_118029Z` 的24套件/111输入通过，44项Python测试中43通过/1跳过。独立复核发现板级TB可能只收type7而跳过CRC断言；已加强为四个成功epoch各自必须收到type6，`124835_465106Z` 定向复验通过。`startup_guard_digital_composite.json` 确认唯一被取代的输入是该TB，生产源码未变；独立复核 `independent_startup_guard_review/20261017T124950_134546Z` 关闭此项，无阻塞发现。新的PDS构建仍在运行，原125MHz/6ns/5秒超时约束不变，尚未下载新候选，现场图像恢复仍未通过。当前分层结果见 [startup_guard.json](evidence/startup_guard.json)，设计与任务见同日startup-guard文档。

此后第一轮 `pds/20261017T122911_128053Z` 的六组布局全部未通过，最佳setup为−0.104ns，未下载。实际报告含DMA描述符、FIFO及桥读缓存控制等不同路径。对桥作已知状态下的等价控制简化：普通读/写/空闲阶段只保留该阶段可能发生的fault真值，VADDR/VDATA仍使用完整masked验证；原fault_now优先级、sticky诊断、VALID及排空不变。隔离候选 `bridge_phase_guards_startup_1259` 经279552四态比较、191场景32197逐周期配对及三突变检查，独立复核 `independent_bridge_phase_guard_review/20261017T130136_580922Z` 通过，随后仅LF归一后应用。未知内部状态不在等价范围内，协调复位后的状态保持已知。

当前实际桥SHA `f898c46870e418f99d4086956d2ff1fa376d5295f075c8fed11a28a969a52408` 的实际DUT独立复核 `independent_applied_bridge_phase_guard_review/20261017T130902_274324Z` 再次通过四态和逐周期检查；第二轮完整回归 `130743_837727Z` 的24套件/111输入全部通过，116项当前汇总哈希匹配。当前附加CRC/合法黑帧/突变复核为 `startup_guard_review/20261017T130958_208241Z`。PDS `130743_823296Z` 尚未完成签核；数字资格已恢复，物理/画面资格仍待验。上述变更没有放宽125MHz、6ns或超时，尚无新镜像板测。

## 数据路径与范围

真实HDMI完整帧经48bit异步FIFO，在core域原子分送raw和2×2平均分支，各自packer/DMA写入预留测试区。raw `0x87300000`：800×600、2400B行步长、1440000有效字节；preview `0x87460000`：400×300、1200B行步长、360000有效字节。每通道缩放为 `(p00+p01+p10+p11+2)>>2`。good EOF及两路成功写结果齐备后，独立读取有效字节核验两平面CRC，再交给显示读口。

显示每行从DDR读取一次，双bank双时钟行RAM供左右各消费一次；右窗口最后像素退出流水线后才能回收。窗口 `(0,150)` 与 `(400,150)` 各400×300，上下背景RGB `101820`。输出扫描不能因DDR或事件消费者受阻而暂停。显示记录经稳定bundle跨域，首行就绪且帧边界才commit，旧引用全部退休后release。

本阶段按需单帧、KEY0重采，frame_id1/slot0为诊断编号；不包含连续采集fps、检测输入量化、三分支CAPTURE_DONE、CPU正式fabric/MMIO或三槽分配。原raw-only和RX目标保留。preview镜像已显示过正常桌面，但KEY0后可再次锁存黑帧，实际图像恢复尚未通过。定位期间板卡临时运行RX诊断彩条。

## 数字证据及独立审查

| 部件 | 证据与覆盖 |
|---|---|
| 缩放规格 | `build/video/preview_scaler_spec/20261017T014927_662683Z/result.json`；X/Z行末误接纳先RED后修复 |
| 缩放质量 | `build/video/preview_scaler_quality/20261017T015539_734996Z/result.json`；50次编译/仿真、22组byte oracle、全部sum0..1020、1024偶数尺寸、5突变、完整120000输出；PDS兼容位宽改写等价 |
| 双平面写规格 | `build/video/preview_capture_spec/evidence.json`；完整800×600、21项额外异常、1859次原子接纳、49次竞争仲裁、30项参数边界 |
| 双平面写质量 | `build/video/preview_capture_quality/evidence.json`；31场景×3小几何、完整1800000有效字节、padding/guard及正好写一次、18次严格编译、10突变被拒绝 |
| 显示规格 | `build/video/preview_display_spec/spec_recheck.json`；独立完整720000窗口像素/900次行读，长事件背压问题修复后复核通过 |
| 当前显示质量 | `build/video/preview_display_quality/quality_review.json`；45次行为仿真、31作者场景、完整光栅、独立长背压、最小/最大尺寸、4突变、2次runner失败隔离；覆盖最后counter-wrap及参数溢出修复 |
| CRC/联合规格 | `build/video/preview_integrated_spec/final_result.json`；独立CRC/协议排空/联合模式/UART旧PASS检查；未知expected/tag、受阻结果稳定和晚到源故障先RED后修复 |
| CRC/联合质量 | `build/video/preview_integrated_quality/final_result.json`；26次预期退出检查、15个packet测试、178次448bit原子快照、真实UART交替、fault排空及3突变；随后显示两项边界修复由当前显示质量单独覆盖 |
| READY实际源码复核 | `build/video/preview_ready_spec/result.json` 与 `build/video/preview_final_quality/result.json`；65536组四态、191例/32197配对，网表READY无宽比较路径、联合复位和晚到故障检查 |
| 后续两处等价简化规格 | `build/video/preview_post_ready_spec/result.json`；直接编译实际capture/CRC，4194304组四态miter、31例/52571配对、525264组函数比较及15例/12023配对，3突变被拒绝 |
| 后续两处等价简化质量 | `build/video/preview_post_ready_quality/result.json`；5次三域KEY0、77625个已知状态采样、109次行读/216拍、31877个done样本，晚到sourcefault撤销且保留display排空所有权；当前边界探针与新网表复核通过 |
| 分拍打包器实际源码规格 | `build/video/preview_serial_spec/result.json`；默认逐周期兼容、两种模式完整帧及全部0..18占用，三小几何各31异常场景、完整raw/preview独立字节及CRC、额外原子/互斥/退休监视通过 |
| 分拍打包器实际源码质量 | `build/video/preview_serial_quality/result.json`；默认算法和持久TB未弱化、实际联合板级observer/packet通过、当拍停止抑制与双packer互斥；新网表控制到storage依赖缩短，结构深度不代替STA |

首次上板预览版本主要源码SHA256（启动修复前的历史输入）：

| 文件 | SHA256 |
|---|---|
| preview_downscale.sv | `690f701b072123984e4352addb5058d1623e5937d5378967941e606d150fc957` |
| video_preview_capture.sv | `e8454fe85bde0f9fbe3f57330c9fcc9ff3870bfb7f59ae6ce94860b24594326a` |
| rgb888_packer.sv | `a44cf8dc0c36944001877ba65287ed4c754c03559012b831fc61be98b63a71db` |
| preview_display.sv | `40e345c23435757a84dbc3efba7abc8e28d463ebaf8ffba028ad6316373120a3` |
| video_frame_crc_reader.sv | `bdc9d4701d5ba586e6f9d257f4884f7c84c7857e6de2b5e272acce850462d89f` |
| video_preview_engine.sv | `0cbf7b3bec734be0ba29da389d3ed044f00d7f7f4546f35e6478ccc7b6a7dc86` |
| axi128_hmic256.sv | `6589602b4df02f4408728b9c602be259ee93726ddd19c3587c33fbbc8632383b` |

`build/video/regression/20261017T032723_616331Z` 当前分拍源码的23套件回归通过，109项输入哈希全部匹配；44项Python测试中43通过、1项Windows符号链接权限相关跳过。`024846_329135Z` 保留为79b7c5b的107项输入历史通过，`022843_972206Z` 保留为db4edba的历史通过；`021256_549473Z` 因审查修复期间输入变化而失败，保留其失败。

板级TB使用数字DDR替身、受控输入候选事件和缩短输出光栅；其结果不能验证保护DDR训练或HDMI外部AC。完整真实尺寸的缩放/写入及完整显示光栅分别由独立组件套件核对。CRC用于数据一致性检查，有碰撞边界；缩放数值正确性由独立像素oracle证明。

## PDS与约束

保留失败运行：`20261017T015011_446534Z` 的PDS尺寸转换语法不兼容；`015159_534705Z` 的commit payload综合合并别名；`015812_678377Z` 中单记录目标无消费者的release payload被优化；`021035_775878Z` 的声明前向引用不兼容。均按实际综合语义修正，没有放宽live bundle时限。

`build/video/pds/20261017T021230_486332Z` 的seed4在125MHz下slow setup WNS −1.227ns、488个失败端点。保存的三条最差路径均为桥payload→masked比较→fault_now→READY→显示watchdog，不能据此归因全部488端点。该运行输入被后续显示修复超越，已停止本运行进程并保留失败/中断记录，未下载。

仅将桥IDLE阶段READY按互斥状态等价简化，保持fault_now、故障锁存、native VALID与排空、timeout和时钟约束原样。`build/video/preview_timing_analysis/REPORT.md` 与 `proof.json` 记录65536次四态组合、191例桥回归及32197次逐周期输出/状态/缓存相等，两项抑制突变被拒绝。任意强制内部X状态不在等价保证内；协调复位后状态已知且保持已知。应用到实际源码的独立复核另见 `build/video/preview_ready_spec/`。

`build/video/pds/20261017T022843_973232Z` 已完成seed4/5：slow setup分别−0.291ns/52端点、−0.804ns/285端点，其余七角通过。新的最差族为preview DMA计数→raw packer，及descriptor算术→CRC寄存器CE，旧比较器→READY路径已由独立网表扇入审查确认消除。seed6未完成时停止此运行，保留所有已完成报告及interruption.json；未把两次结果称作整个六seed结果，也未下载。

随后保留原fault_now优先级，独立以四态procedural-if真值并行归约capture当拍停止条件；CRC描述符因上界16B对齐且有效运算不溢出，改用last_byte直接比较。候选证明在 `build/video/preview_timing_analysis/post_ready/`：4194304次四态归约、31例/52571样本capture配对；525264次descriptor函数四态配对、15例/12023样本CRC配对。早期capture测试夹具漏镜像内部force导致的不对称已明确隔离，不计生产失败。实际源码LF归一后另做独立规格/质量复核。

`build/video/pds/20261017T024846_346140Z` 的六个预定布局全部失败，slow setup WNS依次为−0.622/−0.457/−0.690/−0.825/−0.968/−0.717ns，未下载。随后启用preview两路packer输入/输出互斥的分拍模式，默认参数保持原算法。实际完整800×600分拍组件耗时570000core周期，两个平面有效字节1440000/360000、CRC为11767148/1aad8212；吞吐是数字仿真结果。后续实采FIFO峰值140、KEY0后141，容量2048，均无溢出。

分拍新输入物理构建 `20261017T032723_632587Z` 的六次slow setup WNS为−0.595/−0.425/+0.001/−1.011/−0.841/−0.475ns。最终选择seed6，slow/fast的setup、hold、recovery、removal全部通过，时钟及超时约束未放宽。最终资源15019 LUT、14983寄存器、8.5 DRM。位流SHA256为 `a8658296e6b8b44cf05926fd835a72160f0e180932e1ab3afc27ef1eb267d11e`，同名掩码为 `c4dbc6a509addc6bc056f55104d34662a2fb08fe326ba33734fec81e0e9f4893`。余量很小，不将单次时序通过解释为跨版本或更高频率保证。

重复的frame_id目标因综合后与commit_frame_id合并，已仅删除无实体别名选择器；32位实际active_frame→commit_frame_id仍逐位保留6ns。最终输入绑定的结构审计已通过139位引脚、56位Gray、实际显示CDC、68组本地同步级、reset及零组合环检查。448bit逻辑诊断快照在本目标保留424个live数据位；报告按实际保留位核验。14组布线后只读报告及最终束路径审计全部通过，原PNR和全局时序报告保持原哈希。最小slow setup/hold/recovery/removal为0.001/0.038/3.080/0.336ns，fast为2.789/0.029/4.739/0.224ns；全部端点匹配，6ns显示束约束保留。本版PDS未输出独立max-skew表，仅记录逐位到达时间跨度，不声称额外skew签核。最终审计为 `build/video/preview_constraints_audit/20261017T032723_632587Z/result.json`。外部HDMI AC与本次板测分别记录。

## 实际板测与现场验收

RX回退构建 `build/video/pds/20261017T022511_958401Z` 已通过当前脚本检查并打包为 `build/video/releases/video_rx_board_50c38c3e293f`，尚未因此重配板卡。最新RX串口记录 `build/video/board_serial/20261017T034454_058502Z` 的3个模式快照均确认800×600、1056×628、同步/porch及约40.0002MHz正常；历史坏帧累计10798，本次采样期间未增加。

最终14组报告由 `build/video/preview_physical_review/result.json` 独立只读复核，20项检查全部通过，结论为PHYSICAL_INTERNAL_APPROVED，范围不含外部AC或板测。

当前包 `build/video/releases/video_preview_board_a8658296e6b8`；`build/video/board_program/20261017T041304_789836Z` 已识别0x00602899并完成Program/Verify，无Flash写入。首轮串口 `board_serial/20261017T041330_728463Z` 及复查 `041451_607762Z` 均可正常收包，但flags0x59、phase0xe0、error_code7：DDR init及PLL/TX正常、rx_mode_good为0、两平面像素数/显示提交均为0，采集超时。串口transport的status=pass不表示采集或显示通过，两项资格均为false。

用户确认唤醒HDMI源且活动信号800×600、60.32Hz。`board_serial/20261017T045015_580184Z` 的8个包均输入锁定，旧超时保持；随后 `045037_986816Z`、`045152_225318Z` 两次60秒记录未观察到KEY0，未将它们算作复位通过证据。后续 `board_program/20261017T113803_624986Z` 对同一位流重新Program/Verify成功，未修改RTL或约束；这是JTAG重配置，不能替代实体KEY0验收。

`board_serial/20261017T113832_560587Z` 首轮12秒实测的6个type6与6个type7均合格：raw480000像素、preview120000像素，源/DDR raw CRC均 `ebf5a8c4`、preview CRC均 `16fa9be1`；frame_id1、commits1、无欠载/溢出，FIFO峰值140/2048，扫描813→1416、行读244023→425027，逐样本满足300行/扫描预算。

`board_serial/20261017T113906_640215Z` 连续60秒记录60个健康包（type6/7各30）：flags0x75、phase0xa5、error0，全部像素数和CRC不变；heartbeat95→213，无复位，扫描2864→6362、行读859202→1908799，逐包行预算合格，欠载0、FIFO峰值140。完整包检查汇总为 `build/video/preview_stability/result.json`。这验证同一静态帧持续扫描，不表示连续采集fps。

实体KEY0验收：用户确认“已按 KEY0，左右相同完整画面已恢复”。按键发生在两段串口记录之间，未连续记录瞬时校准过程；`board_serial/20261017T114039_807867Z` 的复位前心跳399、扫描12032，与 `114247_672280Z` 的新记录心跳99、扫描2792构成新epoch证据，两段之间没有JTAG重配置。复位后12个包（type6/7各6）全部健康，心跳99→121，显示扫描2792→3395、行读837602→1018502，commits1、欠载0，FIFO峰值141/2048；新采集两路像素数及CRC仍满足上述精确值。该前后对比与用户实体操作共同关闭KEY0重采验收，证据为 `build/video/preview_key0/result.json`。

40054bd之后用户明确澄清内容纯黑，因此上文旧现场确认不再作为图像正确证据；KEY0心跳重置及CRC/扫描统计仍保留。后续正常桌面→KEY0→黑帧的复现进一步撤销KEY0图像恢复通过结论，主JSON将reset/transport观察与正确图像恢复分开。优先解决并重新验收，再进入检测input、三分支/正式槽状态、CPU共享互连与连续采集。汇总见 `docs/verification/video/evidence/shared_preview.json`；外部HDMI AC和更长时长稳定性仍单列。

## 启动稳定期修复进展

连续RX记录 `rx_startup_trace/20261017T121624_114412Z` 捕获实体KEY0：mode_good已成立、good_frames为5时RGB签名仍为0，到126帧时签名为34477。签名可能碰撞且时间为主机接收时间，不能推断准确首个非黑像素；结合全零帧CRC及现场观察，支持时序先就绪、内容随后恢复。新增128个连续完整好帧门控，RGB不参与准入；该有限稳定期不保证任意源结束合法黑场。具体策略和数字RED见同日startup-guard设计及 `evidence/preview_black_reset.json`。

启动门控首轮PDS `122911_128053Z` 六布局全部失败，最佳slow setup −0.104ns。随后只对桥已知状态剔除无关fault依赖，保留全局故障优先级/锁存、验证及排空；实际源码独立检查279552组四态、191场景/32197配对通过。第二轮 `130743_823296Z` 六布局仍失败，最佳−0.150ns，最优三组路径均为FIFO RAM输出到raw DMA计数器CE。两个失败构建均未下载，原始报告保留。

第三版在preview板级core域FIFO读口与引擎间加入48bit单词流寄存器。无组合数据直通、背压保持、可同沿退休/替换，无新CDC、复位或超时规则。组件及板级定向回归通过，独立复核 `independent_stream_register_review/20261017T134024_549790Z` 覆盖1/2/48/49/128位、旁路突变及四个板级CRC epoch，无发现。附加 `startup_guard_review/20261017T134015_674991Z` 的CRC/合法黑帧/六突变检查通过。完整回归 `133740_219325Z` 已通过25套件/113输入，44项Python测试中43通过/1跳过；composite及全部118项当前汇总哈希、39项证据引用核对通过。125MHz、6ns束约束及5秒超时保持原样，实际KEY0图像恢复仍待新镜像验收。

第三轮PDS `133740_221065Z` 六布局slow setup为−0.173/−0.204/−0.392/−0.669/−0.294/−0.211ns，seed9另有slow hold−0.012ns，最终失败，未打包或下载。40项实际构建输入均匹配；独立网表观察确认FIFO读口已映射DOB_REG=1，原FIFO RAM输出起点违例消除。新最差族分布在CRC请求描述符、CRC行推进/结果、capture超时控制和桥AR描述符，不把它们归为同一路径。全部报告保留，下一次RTL调整先做架构复核，物理与现场资格保持待验。

架构复核 `independent_timing_architecture_review/20261017T140733_751605Z` 选择保留CRC状态机/周期、在现有处理窗口提前算数据：请求payload不再由descriptor_ok控制装载，正常R拍预存下一地址/行基址，BYTES用移位后的低字节计算。完整描述符检查、故障优先级、RESULT时刻、timer、AR保持及R排空不改；仅允许被拒payload在ARVALID=0时改变无所有权ARADDR。当前CRC源码SHA为 `f1cc6e8036df520f2d2aa38f72a84fbc2d550a2fe0507f14d5b958f7aecdb711`。

隔离候选139场景/85539半周期配对、525264描述符边界/X/Z检查及三个突变拒绝通过。独立复核 `independent_crc_datapath_review/20261017T142231_839491Z` 另增45场景/11361半周期/476次helper有效性检查，覆盖16拍物理排空、每个字节位置、最终字节故障、RECEIVE X/Z stopping及TIMEOUT1/2；无发现。正式TB新增56个独立字节CRC/短行/跨界/复位场景，原RTL和候选均通过。候选按字节应用后再次运行全部配对、独立45场景及正式CRC/板级测试通过。第四轮完整回归 `142615_902618Z` 已通过25套件/113输入，44项Python测试中43通过/1跳过；全部118项当前汇总哈希及44项证据引用核对通过。

`independent_crc_synthesis_review/20261017T143502_449401Z` 确认完整描述符乘加/检查已退出payload CE，32个CRC D锥只使用低8bit、128bit移位连接正确、64个地址helper为同core时钟无复位FF；无新增控制/CDC发现。这是综合结构检查，不能替代实际布线签核。当前执行进度见STATUS和机器证据，CRC设计/计划保留实施前的审阅版本。

最终PDS `142615_898505Z` 六布局slow setup为+0.138/+0.042/+0.061/+0.143/−0.129/−0.098ns；前四布局均满足八类检查，最终选seed7。置放后15006 LUT、15065寄存器、8.5 DRM；位流SHA256 `4dffe2d2e51b55e622f2c97224a410a399beb4772561cb7369376f7a4ae00de7`，同名掩码 `a2c40c7045ee985f8285c138a3c08ca496f4b6a7ae4e39267a3623cd3afe0e09`。全部六布局原始报告已在 `pds_seed_reports/20261017T142615_898505Z` 按哈希归档。

最终结构预检、14组布线后只读报告及finalize均通过；139位管脚、56位Gray、68组本地同步级和全部live数据束覆盖匹配，6ns束界限保持。slow setup/hold/recovery/removal最小余量为0.143/0.076/3.318/0.319ns，fast为3.022/0.061/4.883/0.211ns，原PNR/全局报告哈希保持。工具未输出独立max-skew表，只记录逐位到达跨度及其限制。当前独立物理复核进行中；新包已生成但HDMI源未锁定，尚未下载，实际桌面及实体KEY0恢复仍待验。

只读报告的来源核对以原工程及PNR ADF哈希、实际执行命令和报告中实际器件/时钟/时钟组/MaxDelay例外为依据。PDS退出时会把部分报告副本的`focused_timing.pds`改写为默认工程模板，不能用这些运行后的副本文件证明原工程文本被保留；原始构建工程和布线产物哈希仍保持一致。

最终独立内部物理复核 `independent_internal_signoff/20261017T150606_961164Z` 通过44项检查、448项输入哈希，无发现；覆盖14组报告、1415项live管脚请求、68组本地同步级。其范围仍不含外部AC、实际DDR训练及图像验收。新包于 `board_program/20261017T151122_358275Z` 实际识别PG2L100H / 0x00602899，Program/Verify均成功、未写Flash。已提前开启持续串口记录；重新初始化后仍rx_mode_good=false，随后error7、两平面像素均0，属于等待合格输入超时，没有新图像成功证据。用户已确认唤醒源，后续请求电脑端HDMI拔插以重新握手；尚未进行本修复版实体KEY0验收。

用户随后确认完成唤醒与HDMI重插。新持续记录 `preview_startup_trace/20261017T154047_684230Z` 首批状态已rx_mode_good=true，但保留旧超时；同包再次Program/Verify `board_program/20261017T154106_443047Z` 通过后，新帧480000/120000像素，raw源/DDR CRC均2712310869，preview源/DDR CRC均4170646268。elapsed37576.593～127577.038ms连续91包均健康，约90秒，无溢出/欠载，扫描持续增加；此为CRC一致性和运行状态证据，实际桌面及实体KEY0图像恢复仍待用户确认和复测。

2026-10-18用户明确确认“两边都显示完整源桌面”。前一段记录已到时结束，末尾曾出现输入失锁；新记录 `preview_startup_trace/20261018T021947_200959Z` 已在任何实体KEY0请求前开启，首包输入锁定、原帧CRC保持、显示扫描无欠载。未重新编程，后续须在同一新记录内补齐复位前健康基线、一次实体KEY0及真实桌面恢复，不能跨两段记录拼接为连续复位验收。

该连续记录在约85秒健康基线后请求实体KEY0；heartbeat76839→1，约4秒后新帧完成，raw/preview CRC为1376050373/1149537542，均与DDR读回一致。约48秒后又观察到heartbeat95→1，第二帧CRC为3891614158/1412348982；第二次复位的具体操作尚未确认，本代理期间未操作JTAG。两次均无溢出/欠载，但用户回复“已按 KEY0，未恢复或画面异常”，进一步明确“仍有左右窗口，但是内容只是压缩显示了一部分”。照片显示两份一致的桌面窄条、其下大面积黑色及单独鼠标指针；不能判为全画面恢复成功，也不能仅凭照片断定错误发生在源端、RX、缩放或扫描输出哪一级。

记录已通过stop文件正常结束，原始UART重新解码与带时间戳记录逐项一致。失败证据 `preview_geometry_diagnosis/20261018T022734_926351Z/result.json` 绑定原始流、三个epoch、用户确认与原照片；汇总中的图像验收保持false。用户另提供完整800×600源桌面PNG用于对照；已准备800×600四角/边框定位图与独立2×2平均参考图，等待源端全屏显示后再采帧。未修改生产RTL或扩大启动等待阈值。

2026-10-18当前复位分离候选为`33e1b8242053`（提交0d3cf8f），其源码、26套件回归、内部物理及最终独立审查证据集中在[preview_link_reset.json](evidence/preview_link_reset.json)。新模块保留KEY0的DDR/采集/显示协调复位，HDMI转换器与EDID/I2C仅在PLL启动或失锁时重新初始化。KEY0也不再清理HDMI初始化的sticky错误；该错误需重新配置、上电或实际PLL失锁恢复。新的reset/SRL内部物理计时限制和外部AC仍单列。新包已完成Program/Verify，首帧raw480000/preview120000像素、CRC33bac95a/679ff89c精确匹配参考及DDR，持续记录为`preview_startup_trace/20261018T050414_986976Z`。这只证明首次参考帧，实体KEY0后四角完整与真实桌面重采尚未验收，V020d保持open。

## 2026-10-18复位分离版本现场验收

最终PDS为`20261018T043859_105620Z`、seed14，125MHz/6ns束边界/5秒超时均保持。26套件/122输入回归及实际PASS日志、最终独立84检查/882输入哈希通过。易失Program/Verify为`board_program/20261018T050738_013474Z`，bit SHA256为`33e1b8242053694d7725b11522cf85a4f6d086534fcc47bc8acc0174d075d026`。最小slow setup/hold为0.179/0.066ns、fast为2.962/0.051ns，原14组束路径及新增42端点×四类=168路径通过。新reset recovery/removal没有可报告路径，打包SRL内部级间未独立计时；这些项目、外部AC和模拟余量均不包含在认可范围。

首段`preview_startup_trace/20261018T050414_986976Z`正常到时结束，1666条原始UART重新解码完全一致，其中完成状态稳定约1578秒。此后等待用户回复期间有未记录间隔，不声称全程连续监测。用户确认初始两幅四角与白边框完整后，开启新段`preview_startup_trace/20261018T072758_303450Z`，整个按键验收均在该段中进行，没有再次JTAG编程。

| 观察阶段 | 完成状态包/时长 | raw / preview CRC | 用户画面确认 |
|---|---|---|---|
| 新记录按键前基线 | 118包，约117秒；请求前约84秒 | 33bac95a / 679ff89c，精确匹配独立参考 | 两边四角和边框完整 |
| 一次KEY0，四角图不变 | 94包，约93秒 | 33bac95a / 679ff89c | 两边四角和边框仍完整 |
| 切普通桌面后一次KEY0 | 82包，约81秒 | a8809b95 / 9a755661 | 两边更新为同一完整桌面 |

两次新epoch分别heartbeat17043→1、191→1；首包busy、两平面像素数清零，随后heartbeat5报告新帧完成。UART采样时DDR初始化已完成，未捕获亚秒校准瞬态。所有完成样本均为raw480000/preview120000像素、源与DDR读回CRC相同；所有显示样本commits1、欠载0，逐包满足300行/扫描预算。四角与桌面FIFO峰值分别149/145，均无溢出、错误或额外复位。时间是主机收包时间，不能换算为准确按键响应或模拟校准延迟。

最终298条记录经stop文件干净停止，raw重新解码、JSON结果和时间戳记录逐项一致。原始证据、用户操作标记和全部SHA256见`build/video/preview_startup_trace/20261018T072758_303450Z/board_acceptance.json`；小型受版本管理摘要见[preview_link_reset.json](evidence/preview_link_reset.json)。当前V020d画面验收通过；板卡保留该易失预览镜像，未写Flash。此结论限于本次静态四角图/桌面及两次KEY0，仍是单帧截图显示，不代表连续采集fps、热插拔或任意源冷启动恢复。
