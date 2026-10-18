# RX画面范围诊断

2026-10-18，候选preview四角图测试失败。原始记录 `build/video/preview_startup_trace/20261018T023218_713265Z` 在marker414064.426ms之后记录一次KEY0；heartbeat325→1，约4秒后新帧完成。raw/preview像素为480000/120000，源/DDR CRC一致，分别e65ff076/16df1c7a，无溢出或欠载。用户确认“已变成四角测试图，但被压缩或裁切”。前面的其他复位不计为这次请求。

定位图严格RGB参考raw CRC为33bac95a，2×2平均preview为679ff89c。CRC不一致不能单独定位故障：源端浏览器缩放、GPU颜色转换和截图时刻都可能改变像素。原照片及完整800×600源截图保存在 `build/video/preview_geometry_diagnosis/20261018T022734_926351Z`，`pattern_result.json` 绑定本次测试原始UART和用户确认。

本批新增独立RX观测目标 `video_rx_image_probe`，保留原下降沿采样、几何测量、EDID、初始化、时钟、管脚和稳定总线snapshot；输出为本地彩条。统计只观察完整好帧，不进入任何采集准入路径：序号、480000像素数、非黑像素计数及边界、四象限中心颜色、RGB字节CRC。纯黑帧正常发布，空边界为ffff/ffff；坏帧和中途复位不发布半帧。

UART 115200、TRV1、32字节payload、XOR，初版按type1/3/8/9循环。type8/9来自同一冻结快照，以相同sequence配对；不接受跨帧拼接。四角图的四象限中心恰好落在灰色网格线上，实际参考RGB均为d1d5db；不能误用四块背景色作为这四个坐标的期望值。整图参考CRC33bac95a、非黑像素462440和完整边界是更强的核对。若RX已是窄条，继续查源/转换器；若RX完整，再查缩放和扫描输出，不能把内部统计通过直接视为图像验收。

组件8场景、串口4测试以及完整800×600板级数字仿真已通过。板级覆盖真实geometry、728位snapshot、type8/9字段和冻结帧序号；下游TX彩条持续输出。测试参考的独立梯度CRC为f24ade70。

构建输入在复制前冻结，复制后及结束逐一校验；只写独立`latest_rx_image_probe_*`，旧preview构建/发布指针保留。当前测试为 `rx_image_probe_test/20261018T025802_295623Z`，构建为 `rx_image_probe_pds/20261018T025812_462262Z`，八类内部时序通过，slow setup/hold/recovery/removal最小余量6.079/0.166/7.354/0.440ns，fast为8.633/0.104/9.257/0.288ns；728条跨域setup端点、零TNS/失败。bit SHA13fccaf34eb7bc170bdf63cbbbd31680da07b4be5da772701407ec69e8b5c3fb。

独立代码/来源审查和实际下载、RX颜色观测分别记录。旧25套件回归仅证明原preview冻结输入，新增诊断由本文件列出的专门测试覆盖。外部AC时序未签核；当前preview图像恢复仍失败，尚不进入后续检测分支。

初版RX观测已Program/Verify：`rx_image_probe_program/20261018T030344_327566Z`。持续记录 `rx_image_probe_serial/20261018T030028_665539Z` 包含一次实体KEY0，之后26个采样帧序号220..6252均精确匹配CRC33bac95a、462440非黑像素和全图边界；坏帧0。观察摘要为 `build/video/rx_image_probe_board_observation.json`。它漏过了前128帧，不能据此排除早期内容变化。

随后恢复相同preview包并Verify（`board_program/20261018T030849_190317Z`），raw/preview精确匹配33bac95a/679ff89c，用户确认“两边四角和边框都完整”。同一连续记录 `preview_startup_trace/20261018T030838_989349Z` 在marker451061.698ms后记录KEY0，raw/preview变为e20ea0d2/b0982209，用户确认又变窄条或缺角。用户也确认后续额外按过几次，对应另外4次复位及其他CRC；不判为板卡自行复位。本轮不能只归因为显示读口，也尚未证明具体采集入口或启动内容原因。

为覆盖遗漏的启动帧，历史版记录crc128/crc129/最后一次CRC变化帧及变化前CRC，新增type10，snapshot856位，原RX约束不变。组件138帧、解码5测试和完整RX板级测试通过；独立137帧测试及实际top的8/9/10共8组40包冻结检查通过。当前构建 `rx_image_probe_pds/20261018T032124_418528Z`、测试 `rx_image_probe_test/20261018T032114_338937Z`；独立复核 `independent_rx_startup_history_review/20261018T032255_874054Z` 的41检查/117哈希通过。slow八类最小余量5.916/0.158/7.671/0.620ns，fast8.483/0.100/9.365/0.436ns，856条跨域setup端点无失败。

历史版已Program/Verify（`rx_image_probe_program/20261018T032631_270657Z`），冷启动首个好帧及128/129帧均为33bac95a，最后变化帧为1。串口 `rx_image_probe_serial/20261018T032333_261385Z` 在用户确认临时断电后已干净停止；该段标记为断电中断、未确认实体KEY0，不计作按键验收。易失配置随后通过 `rx_image_probe_program/20261018T033106_371805Z` 恢复并Verify。

恢复后的记录为 `rx_image_probe_serial/20261018T033056_212008Z`。源端重新全屏前有内容变化，不能把这一阶段的128/129帧CRC797ee46c作为静态四角图故障证据。用户确认“四角图已全屏并保持不动”后，连续10组历史包和对应像素分布精确匹配33bac95a、462440及全边界，坏帧0。在218125.187ms处另设一次实体KEY0标记；记录继续，尚待按键后的历史结果。仍未改变任何采集门限或超时。

本地提交前复跑 `python scripts/video/build_rx_image_probe.py --test`，新记录 `rx_image_probe_test/20261018T033545_534221Z` 通过：组件138帧、完整RX板级模型、5项解码测试。复核原独立审查的41项检查及117个输入哈希均保持一致；本次没有修改其绑定文件，也没有重新下载打断按键观察窗口。新增独立目标未纳入旧preview的25套件验收声明。

实体KEY0随后确认已按一次。连续记录只出现一次序号回退；复位后16个模式包跨约75秒均为pixel_hz=0、good_frames=0、rx_boot_done=true、rx_configured=false，无TX/RX初始化错误。用户确认源端四角图仍全屏且Windows中HDMI屏幕仍在。没有完整新帧，因此crc128/129的0表示历史不可用，不能解释成黑帧，也不能用来判定窄条原因。该段983条记录已停止，原始UART重新解码与保存字段完全一致；证据入口为 [rx_image_probe_startup_key0.json](evidence/rx_image_probe_startup_key0.json)。

保持源端与接线不变，随后相同诊断镜像再次Program/Verify（`rx_image_probe_program/20261018T034813_684485Z`）恢复40MHz、完整四角图，128/129与当前CRC均33bac95a、最后变化帧1。新连续记录 `rx_image_probe_serial/20261018T034758_212305Z` 在85404.051ms处标记下一次单次KEY0；这是JTAG对照后的独立实体按键请求，结果仍待记录，不能以这次Program恢复替代按键验收。

参考路径进一步核对：固定厂商 `source/rtl/HDMI_IN_DDR3_HDMI_OUT_top.v` 的rstn_out只由PLL locked及1ms计数产生；KEY0的rst_in只写入未被使用的rst_reg，并未连接HDMI或DDR复位。当前工程 `video_clock_reset` 则让rst_in重新复位HDMI和重跑EDID/初始化。这是待验证的复位架构差异，尚未认定芯片内部具体失败原因，也未修改复位策略。

下一次单次KEY0已确认，`rx_image_probe_serial/20261018T034758_212305Z` 在标记后只有一次序号回退32967→8。序号8是480000个合法黑像素，时序合格；序号128/129的CRC5243da6a/aebe097e，均非参考图；最后一次内容变化在188，随后20个取样帧（序号310..6040，95秒）持续精确匹配33bac95a、462440及全边界。680条原始UART记录解码完全一致，已干净停止。证据为 [rx_image_probe_startup_transition.json](evidence/rx_image_probe_startup_transition.json)。这证明好时序早于静态源图恢复；独立目标不能逐帧代替preview同目标观测。

依据该证据开始实施[预览链路复位分离](../../superpowers/specs/2026-10-18-video-preview-link-reset-design.md)：保留KEY0对pixel/cfg、DDR与协调流水线的复位，独立locked→link_release启动链让HDMI转换器和EDID/I2C控制器不随KEY0重新初始化。原RX诊断模块与video_clock_reset保持原样。128帧、125MHz、6ns、5秒和黑帧准入不改；PLL实际失锁仍重启HDMI。旧模块的明确KEY0失败测试已复现，新12场景时钟测试及5场景预览板级数字测试通过；完整回归、新PDS、独立复核与实体画面验收仍在进行。

复位分离的诊断恢复范围：KEY0不再清理HDMI控制器已锁存的NACK/初始化超时；此类错误需重新配置、断电上电或实际PLL失锁后重启链路，不能宣称KEY0能够恢复一切HDMI错误。KEY0仍清理原DDR、采集和显示任务错误。初次连接和源端热插拔的内容稳定时间仍不由CRC/颜色判定。

当前完整数字回归 `regression/20261018T040244_825780Z` 已通过26套件，122项输入哈希全部匹配。初始独立复核 `independent_preview_link_reset_review/20261018T040453_701914Z` 的46检查/130哈希通过，无阻塞发现；包含额外22场景与实际生成GPLL冷启动模型。该复核不提前批准随后完成的全回归或活动PDS。综合17个链路状态在PNR中可能打包为16个物理资源，link_release两级合入gopSRL2，不能冒称两个独立FF路径；来自LOCK的未报告reset恢复时间也不能当作非空时序通过。新PDS仍在运行，实体画面未验。
