# Video启动稳定期实施计划

**Goal:** 修复模式先锁定时单帧预览抢采启动黑场的问题，并复验实体KEY0图像恢复。

**Architecture:** pixel域完整好帧计数门控现有入口选择；128帧阈值，不检查RGB、不改变复位和超时。设计见同日startup-guard-design。

**Execution:** 当前会话依次实施，沿用Video分支和用户已有授权；保持技术报告独立修改。

- [x] 持续RX串口捕获KEY0与模式/RGB恢复，保存时间戳、原始流及失败历史。
- [x] 修改 `tb/video/tb_video_preview_board.sv`：每次复位先送两个黑色稳定帧，再送图样；在warmup期间断言入口无接纳。旧RTL在122733_829867Z以“startup frames must not enter capture FIFO”失败。
- [x] 新增 `tb/video/tb_video_capture_startup_guard.sv`，逐项检查完整帧准入、阈值1/2/128、健康恢复、黑帧和饱和；实际模块缺失时编译失败。组件GREEN为122816_574706Z，联合GREEN为122844_184909Z；额外review123132_872972Z检查四次板级CRC、合法黑帧及六个突变，8项通过。
- [x] 新增 `rtl/video/video_capture_startup_guard.sv`，接入 `fpga/pg2l100h/rtl/video_preview_board_top.sv` 的入口mode_good；顶层RX_WARMUP_FRAMES默认128，板级TB用2。显式更新目标来源和 `scripts/video/run.py` 套件。
- [x] 运行 `python scripts/video/run.py --suite all`：122911_118029Z的24套件/111输入通过，44项Python测试中43通过/1跳过。随后仅加强板级TB，124835_465106Z定向复跑通过；composite逐项确认唯一差异为TB、全部116项汇总当前输入匹配。独立复核124950_134546Z关闭CRC包覆盖问题，无阻塞RTL发现；新pixel域路径无新增CDC，保持旧接口/失败判定。
- [ ] 运行 `python scripts/video/build_pds.py --target video_preview_board --stage bitstream`，现有八类内部时序和实际CDC/bundle审计全部通过后才打包。失败位流不下载。
- [x] 第一轮 `pds/20261017T122911_128053Z` 六布局全部失败，setup余量依次−0.226/−2.473/−0.422/−1.030/−0.104/−0.486ns，保留原报告及拒绝结果。最优组含DMA描述符/FIFO路径，另一组桥payload→全局poisoned→读缓存WE；不把所有失败端点归因于同一路径。
- [x] 对桥的已知状态分别消除无关fault输入，保留完整fault_now优先级/锁存、VADDR/VDATA masked验证、VALID及排空；隔离候选279552四态比较、191场景32197配对及三突变检查通过，独立复核通过后应用。当前实际桥SHA为 `f898c46870e418f99d4086956d2ff1fa376d5295f075c8fed11a28a969a52408`。原时钟/超时不变，未知内部状态不在等价保证内。
- [x] 对已应用桥重新做实际DUT复核及完整回归：`independent_applied_bridge_phase_guard_review/20261017T130902_274324Z` 再次编译实际源码并通过279552四态/191配对；`regression/20261017T130743_837727Z` 的24套件/111输入通过，合并116当前哈希匹配。附加8项板级CRC/合法黑帧/突变复核为 `startup_guard_review/20261017T130958_208241Z`。
- [x] 第二轮PDS `130743_823296Z` 六布局仍全部失败，slow setup分别−0.255/−0.334/−0.150/−0.303/−0.570/−0.383ns；最优三组关键路径均从FIFO RAM读口到raw DMA计数器CE。原报告保留，未下载。
- [x] 在preview板级core域FIFO与引擎间加入48bit单词弹性寄存器，切断RAM数据到DMA控制的直接组合路径；无直通，可同时退休/替换，不新增CDC或取消复位。旁路替身先以行为断言失败，组件及板级定向回归 `133625_233638Z/133625_233672Z` 通过。独立复核 `independent_stream_register_review/20261017T134024_549790Z` 检查1/2/48/49/128位、背压与复位、旁路突变及四个板级CRC epoch，无发现。
- [x] 第三轮完整回归 `133740_219325Z` 通过25套件/113输入；44项Python测试中43通过/1跳过。当前composite、两项实际源码review及全部118项汇总哈希核对通过，38项证据引用完整。数字资格恢复，物理和图像资格不随之恢复。
- [x] 第三轮PDS `133740_221065Z` 已失败退出，六布局slow setup为−0.173/−0.204/−0.392/−0.669/−0.294/−0.211ns；seed9另有slow hold−0.012ns。40项构建输入匹配，失败产物未打包/下载。独立网表复核确认FIFO的DOB_REG由0变1、实际输出进入capture_stream_data，原RAM起点违例消除；剩余CRC请求/行推进、capture超时及桥AR描述符等路径需架构复核。
- [x] 完成独立架构复核及保持周期的CRC数据通路整理：同日crc-datapath-timing设计/计划；139场景配对和45场景独立检查通过，实际源码及新增56项CRC持久测试再验通过。保留原FSM、故障优先级、计时及排空，未增加CHECK故障窗口。
- [x] 第四轮完整回归 `142615_902618Z` 通过25套件/113输入，44项Python测试中43通过/1跳过；全部118项当前汇总哈希、44项证据引用核对通过。CRC实际综合数据路径复核无发现；数字资格恢复，物理资格独立待验。
- [ ] 第四轮PDS `142615_898505Z` 运行中，已有四布局八角通过；仍冻结输入，最终结果后重新执行实际路径审计。
- [ ] `package_board.py --target video_preview_board`、`program_board.py --target video_preview_board --start-server`；首帧及60秒状态检查；开启长记录后请求一次实体KEY0，验正确源桌面恢复。
- [ ] 更新STATUS/接口/验证摘要与原始结果引用，保留旧黑帧/超时/纠正证据；只提交本批Video文件，不push、不写Flash。
