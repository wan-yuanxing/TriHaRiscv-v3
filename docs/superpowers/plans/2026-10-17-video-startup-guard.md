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
- [ ] `package_board.py --target video_preview_board`、`program_board.py --target video_preview_board --start-server`；首帧及60秒状态检查；开启长记录后请求一次实体KEY0，验正确源桌面恢复。
- [ ] 更新STATUS/接口/验证摘要与原始结果引用，保留旧黑帧/超时/纠正证据；只提交本批Video文件，不push、不写Flash。
