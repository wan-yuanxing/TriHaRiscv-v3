# TriHa 启动与CoreMark测量设计

本阶段执行用户已授权的后续实施：在现有CPU工作树接通Windows GCC、裸机启动和ModelSim CoreMark1.0。产品RTL保持当前六级配置，使用同一ELF比较单/双发射；不更改正式SoC地址、Video/DDR、缓存或流水。

## 实施选择

采用小型裸机运行时和基准自带的轻量格式化输出，复用现有ELF加载和TCM测试模型。相比引入完整newlib系统调用或重新实现printf，此方式适配范围较小，计时区间不包含字符输出。格式化源码保留原件，构建时只生成串口回调/消息检查与HAS_FLOAT值判断的窄适配，生成文件和哈希放入build。

## 软件边界

- `sw/runtime/`维护启动、测试TCM链接布局、CSR字符/退出通道及异常报告。
- 启动设置gp、16字节对齐sp、mtvec，关闭中断并清BSS；PT_LOAD已经把data加载到VMA，当前不宣称ROM搬运启动。
- 128KiB TCM与0x80000000入口只属此测试环境。ELF导出先填0xa5，再复制实际文件段，因此BSS必须由启动代码清零。
- `sw/tests/runtime_smoke.c`核对data/BSS和算术；陷阱负例执行非法指令，经实际mtvec报告并返回1。
- `sw/tests/retire_probe.S`固定执行14条被指定PC范围覆盖的指令，包含3次循环、分支、store、load，核对单/双发射的WB事件计数。错误期望值负例必须被拒绝。
- CoreMark算法、已知CRC和计时检查保持原样。默认5次迭代，2000字节，RV32IM_Zicsr/ILP32、-O3，编译参数完整记录；支持performance/validation标准种子。

## 测量与判定

周期读取真实0xc00计数器。C端time_in_secs按100MHz测试时钟换算，短测不足10秒的原始警告保持可见；报告仅给RTL短测估算，不能称官方分数或已通过100MHz物理时序。

现核没有minstret实现，仿真侧按两路valid_wb、停顿和异常状态统计完成事件。两次cycle CSR实际读入的同一半开时钟区间记录周期/完成数；此范围用定向14指令测试验证，但不等于完整ISA/异常退休证明。报告标明计数来源与观察限制，不使用issue次数替代。

宿主必须检查：工具返回0、真实程序退出0、完整完成标记、无异常/错误、软件ticks与仿真CSR窗口相同、迭代数、种子/三项已知CRC、计数定向测试通过。唯一允许的CoreMark错误文本为原始短测时长警告及其汇总；其他ERROR、未知种子、CRC不符均失败。CRC负例在build中的core_main副本翻转一个预期CRC常量，原始源码保持不变。

每次新建build目录，保存源/工具/生成文件/ELF/BIN/日志哈希、原生命令、各模式结果和墙钟时间。编译上限60秒，单次仿真上限180秒。超时只清理本次拥有的进程树。

## 阶段完成条件

启动测试、14指令计数测试在单/双模式通过；错误计数期望、实际非法指令和CRC负例返回非零；performance两模式及validation单模式通过CRC。更新CoreMark/MHz、观察IPC、差异和明确限制后提交。完整ISA、正式SoC、CPU-only资源和实际100MHz后布线继续独立验收。
