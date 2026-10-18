# 预览HDMI链路复位分离实施计划

**Goal:** KEY0重采不重新启动HDMI转换器，完成完整画面的实体按键恢复验证。

**Architecture:** 新增预览专用clock/reset模块，独立locked→link启动链；保持原KEY0→pixel/cfg及DDR/流水线复位。原RX诊断及厂商源不改。

**Execution:** 依据当前会话已授权的Video修复范围顺序实施，已有Video分支只提交明确文件；继续使用系统化调试、测试驱动与完成前验证流程。

## 任务1：保存受控证据

- [ ] 停止`rx_image_probe_serial/20261018T034758_212305Z`，重新解码raw并核对全部记录；只统计85404.051ms标记后的一个确认KEY0。
- [ ] 保存128=5243da6a、129=aebe097e、最后变化188→33bac95a及后续稳定期、用户确认和来源哈希；原失败证据保持历史状态。

## 任务2：先失败测试，再替换预览模块

文件：新增`fpga/pg2l100h/rtl/video_preview_clock_reset.sv`、`tb/video/tb_video_preview_clock_reset.sv`；修改preview顶层、显式JSON、`scripts/video/run.py`及预览板级TB。

- [ ] 独立TB用`OLD_CLOCK_RESET`宏实例化原`video_clock_reset`，其余使用相同端口/PLL模型。初始KEY0按住直到PLL锁定及链路启动，再断言HDMI reset为1；旧实现必须在此或后续KEY0保持检查失败。
- [ ] 新模块复制现有PLL和pixel/cfg释放逻辑，另加两级`link_release`，异步清零条件仅`!locked`；tx_release计数由locked/link_release控制。`tx_reset_n=locked&&tx_release`，pixel/cfg输出继续受KEY0控制。
- [ ] 测试KEY0短于时钟周期、长按、重复按；pixel/cfg立即置低且各自至少两沿后释放，HDMI reset不掉；PLL失锁同时清理两域与HDMI，重新锁定后等待完整启动计数。停止cfg/pixel时钟时不得提前释放。
- [ ] `video_preview_board_top`仅替换模块类型，保留实例名clocks；JSON替换源路径并登记新TB，run新增`preview_clocks`套件纳入all。
- [ ] 板级TB在PLL正常且link已启动后，跨多次KEY0检查rstn_out不掉；原PLL丢失/DDR错误/CRC/UART及再次重采测试继续运行。
- [ ] 运行`python scripts/video/run.py --suite preview_clocks`及`--suite preview_board`；RED/GREEN原始日志进入独立build目录。

## 任务3：物理和板测

- [ ] 运行现有完整回归，绑定新显式源及测试；各套件结果分别记录，不复用旧25套件通过声明。
- [ ] `python scripts/video/build_pds.py --target video_preview_board --stage bitstream`。冻结源码、保留125MHz/6ns/5秒，检查全部内部角的setup/hold/recovery/removal、无空约束、新复位结构和原bundle边界。
- [ ] 请求当前文件/时序独立复核；复核有问题则先修复并重新绑定，不能带旧审查打包。
- [ ] 打包并校验bit/smsk与审查来源。开启新串口后Program/Verify，不写Flash；静态四角图先验证raw/preview参考CRC及用户完整画面。
- [ ] 标记后一次实体KEY0，确认新一帧、DDR重新校准、源/DDR CRC、无overflow/underflow及用户四角完整；实际桌面再复验。失败保持V020d open并回到取证。
- [ ] 更新STATUS与小型证据，明确数字/物理/画面验收范围；只提交Video文件，无push/merge。
