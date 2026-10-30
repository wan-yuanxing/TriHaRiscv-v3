# CPU整核系统仿真支撑材料

本目录对应技术文档B.4第一批。使用Windows GCC 15.2.0和ModelSim SE-64 2020.4，固件以`-O2`构建。

| 测试 | 检查结果 | 事务及退出 |
|---|---|---|
| Cache开启整核固件 | 1277/1277 | 26356周期，14读/35写，3次受控异常，exit=0 |
| Cache关闭同固件 | 809/809 | 25250周期，15读/22写，3次受控异常，exit=0 |
| 内存路由 | 476/476 | 12读/9写，故障锁存和复位恢复 |
| 整核波形重放 | 与Cache开启固件的周期和统计一致 | 原始WLF/VCD |
| 下层数据错误负例及波形重放 | 两次均检出 | 固件退出检查触发CPU_CACHE_FAIL，runner=1 |

周期统计包含UART等待，用于本次功能覆盖。下层为行为级AXI128内存模型，未包含物理DDR或跨时钟域；未执行PDS或板卡操作。外部中断进入与返回见`IRQ_README.md`，Cache开启时的中断交互见`CACHE_IRQ_README.md`。

`cpu-system-support-2026-10-29.zip`包含冻结源码、固件ELF/HEX/MAP、原始日志、WLF/VCD和原生截图。`system-run-index.json`登记实际命令、输入输出SHA-256和截图绑定。

截图窗口为172700--173650 ns，展示平台故障后读取失败、mcause=5、mtval=0x80000000、mepc从0x101FC加4到0x10200、MRET重定向及done=1/exit_code=0。截图为原生ModelSim窗口原始字节，无光标、裁剪或重绘。

运行入口位于`D:/FPGA/TriHaRiscv-cpu-windows/`：

```powershell
python scripts/cpu/run_cache_soc.py --test runtime
python scripts/cpu/run_cache_soc.py --test runtime --bypass-caches
python scripts/cpu/run_cache_soc.py --test router
python scripts/cpu/run_cache_soc.py --test runtime --fault data
python scripts/cpu/capture_system_waveforms.py --baseline <runtime运行目录>/result.json
```

最后一项追加`--broken`执行下层数据错误负例。ModelSim原始退出码和自检入口退出码分别登记，负例要求实际错误标志且入口返回1。

路由测试台的旧1000周期全量刷新上限不足以扫描256组、两路的写回Cache；旧测试还把缓存存储完成等同于下层内存已更新。本批将上限改为20000周期，按公开成功存储更新独立架构值模型，并在显式clean后检查下层字节可见性。原始失败日志保存在CPU工作树`build/cpu/cache-soc-router-20261029T105327382656Z/`和`cache-soc-router-20261029T105556963794Z/`，修正后记录为`cache-soc-router-20261029T105709019809Z/`。生产RTL未修改。
