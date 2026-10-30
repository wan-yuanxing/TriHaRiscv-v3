# Cache开启时的整核中断验证

六级单发射RV32核，512项直接映射BTB、512项BHT、4项RAS，GShare关闭。I/D Cache各16KiB、两路、32B缓存行，数据Cache写回、写分配。复用现有本地ROM/SRAM/MMIO及AXI128行为内存平台，无生产RTL修改。

启动程序将代码由SRAM复制至私有可缓存区，执行FENCE.I后通过I-Cache运行测试和中断处理程序。依次在驻留数据加载返回、缺失填充等待、新缓存行加载返回时从公开IRQ端口注入中断；没有强制DUT内部状态。

| 场景 | 目标加载地址 | 加载结果 | 中断保存mepc | 检查 |
|---|---|---|---|---|
| 驻留命中返回 | 0x80002000 | 0x13579BDF | 0x80004060 | 只保留预热时的一次下层填充 |
| 缺失填充等待 | 0x80002400 | 0x2468ACE0 | 0x80004094 | 下层延迟64周期；IRQ有效且读未完成、无RVALID共66周期 |
| 缺失加载返回 | 0x80002800 | 0x31415926 | 0x800040C8 | 新缓存行只填充一次 |

正例：11758周期，1110次退休，12655项逐周期与事件检查；三次入口、三次MRET、三次恢复，最终exit_code=0。各加载及后继指令只退休一次，三个软件检查点依次为1、2、3。全部入口检查mcause=0x8000000B、mtval=0、mstatus=0x1880、mie=0x800；处理程序清除mie，MRET恢复mstatus=0x88，下一退休PC等于原mepc。

中断专用负例：通过软件宏让处理程序将mepc加4，自检在MRET返回地址检查处拒绝，runner=1。原生ModelSim以-onfinish exit结束时此负例的工具返回码为0，因此入口同时核对实际Fatal、自检错误和成功标志，不能仅凭工具返回码判定通过。

同批重新运行既有Cache系统固件，仍为1277项检查、26356周期、三次受控异常。运行索引为`cache_irq_run_2026-10-29.json`；提交包`cpu-cache-irq-support-2026-10-29.zip`保存冻结源码、固件、WLF/VCD、日志、事件和退休流、原生截图。

```powershell
# 在 D:/FPGA/TriHaRiscv-cpu-windows 中执行
python scripts/cpu/run_cache_soc.py --test irq
python scripts/cpu/run_cache_soc.py --test irq --fault irq-return
python -m pytest scripts/cpu/test_cache_irq.py -q
```

正例返回0，负例返回1。波形图窗口为114450–116050ns，源自ModelSim原生全屏查看器，保存原始截图字节，无鼠标光标、裁剪或重绘。查看器已退出。此项仅为RTL功能仿真，不包含物理DDR、CDC、后布线时序或板级中断验收。
