# 整核外部中断增量支撑材料

单发射RV32核使用512项直接映射BTB、512项BHT、4项RAS，GShare关闭；测试台连接128 KiB行为级存储器，不包含I/D Cache或DDR。实际正例完成3582周期、864次退休、92次存储，8类同步异常及一次机器外部中断的覆盖掩码为0x1FF。

`irq-run-index.json`登记当前配置的正例、错误数据负例、CSR原始采样及退休流检查。`cpu-irq-support-2026-10-29.zip`包含冻结源码、固件ELF/二进制、日志、WLF/VCD、显示脚本和原生截图；外部厂商模型仅记录本机路径与哈希。

波形窗口34000--35600 ns：irq在34905 ns置位，中断状态在34975 ns保存，mcause=0x8000000B、mepc=0x80000150、mtval=0；mstatus从0x88变为0x1880。处理程序清除mie并将s1加一，MRET在35465 ns恢复mstatus=0x88，退休流从mepc继续执行。截图来自ModelSim原生窗口，无光标、裁剪或重绘。

负例将下层加载返回数据异或一位，在810 ns触发CPU_ORDER_FAIL program_exit，入口返回1；该负例检查固件数据错误检出能力，在中断阶段之前失败，不作为中断专用错误注入。

CPU工作树的复现入口：

```powershell
python scripts/cpu/capture_irq_waveforms.py --baseline build/cpu/redirect-ordered-20261029T1119135071015Z/result.json
python scripts/cpu/capture_irq_waveforms.py --baseline build/cpu/redirect-ordered-20261029T1119135071015Z/result.json --broken
```

入口先核对固件基线及全部源码/模型哈希，再编译冻结输入，单独保存每次结果。基线只提供相同固件，基线的较小预测表配置及其周期统计不用于当前结论。此批未修改生产RTL，未运行PDS或板卡操作；中断管脚、跨域及Cache并发中断不在本次范围内。
