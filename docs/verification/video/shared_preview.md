# 同帧共享预览与双窗口验证

2026-10-17实施，基线 `2f309c4`，设计/计划提交 `3b2844f`，分拍实现提交 `632a8d4`。当前109项输入的23套件回归和独立审查、125MHz八类内部时序及束路径审计通过。真实HDMI双平面CRC、共享显示扫描、60秒稳定性及实体KEY0重采板测通过；用户确认左右同源完整画面在KEY0后恢复。本单帧阶段验收完成，初轮输入未锁定/超时记录保留。设计见 `docs/superpowers/specs/2026-10-17-video-shared-preview-design.md`。

## 数据路径与范围

真实HDMI完整帧经48bit异步FIFO，在core域原子分送raw和2×2平均分支，各自packer/DMA写入预留测试区。raw `0x87300000`：800×600、2400B行步长、1440000有效字节；preview `0x87460000`：400×300、1200B行步长、360000有效字节。每通道缩放为 `(p00+p01+p10+p11+2)>>2`。good EOF及两路成功写结果齐备后，独立读取有效字节核验两平面CRC，再交给显示读口。

显示每行从DDR读取一次，双bank双时钟行RAM供左右各消费一次；右窗口最后像素退出流水线后才能回收。窗口 `(0,150)` 与 `(400,150)` 各400×300，上下背景RGB `101820`。输出扫描不能因DDR或事件消费者受阻而暂停。显示记录经稳定bundle跨域，首行就绪且帧边界才commit，旧引用全部退休后release。

本阶段按需单帧、KEY0重采，frame_id1/slot0为诊断编号；不包含连续采集fps、检测输入量化、三分支CAPTURE_DONE、CPU正式fabric/MMIO或三槽分配。原raw-only和RX目标保留。当前硬件保留本阶段preview镜像运行，双CRC及显示扫描正常，用户已现场确认左右窗口的同源完整画面及KEY0后恢复。

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

当前主要源码SHA256：

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

本阶段保留preview镜像运行，不恢复RX，不写Flash。汇总见 `docs/verification/video/evidence/shared_preview.json`；初轮超时、当前物理通过及现场确认分别记录。后续工作为检测input、三分支/正式槽状态、CPU共享互连与连续采集；外部HDMI AC和更长时长稳定性仍单列，不能由本次内部时序及60秒测试代替。
