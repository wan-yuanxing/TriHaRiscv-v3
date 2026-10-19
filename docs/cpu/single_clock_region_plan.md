# 同RTL单时钟区域布局诊断

现有最差路径布线占比87.662%，逻辑级数只有9级，需单独检验物理局部性。先保存第15轮完整终态，再冻结同一RTL，仅将两时钟区域(0,64,100,199)缩至单个(X0,Y3)完整区域(0,64,150,199)。原10ns、全部IO/hold/multicorner、seed1、PNR10分钟/外层900秒不变；不改变任何功能或重用旧map/place。

容量依据为实际器件clock_utilization.txt：X0,Y3有1900 CLMA、900 CLMS，每块4 LUT，共11200 LUT及20 APM；当前原生CPU映射6806 LUT、5207 FF、32分布式RAM和4 APM，逻辑LUT约60.768%容量，尚需实际pack/route确认。容量不是收敛证明，区域属性也不是独立坐标审计。

- [x] 同RTL/时序FDC与功能证据逐项哈希对照：23项RTL/头文件/清单一致，复用24正例/6预期拒绝，全部输入/外部模型/输出重新核验，没有新仿真。
- [x] 完整新compile/synthesize/dev_map/place/route/report_timing；9359个唯一CPU叶节点区域绑定，原生clock report的非IO时钟负载实际范围(4,63,150,198)位于目标内；没有独立逐单元坐标审计。
- [x] 31项冻结输入/260项输出、新阶段标记及六项最终时序和performance核验一致，独立只读复核完成。
- [x] 同RTL对照结果保存至`docs/verification/cpu/single_clock_region_timing.json`。

结果：CPU-only6806 LUT/5207 FF/32分布式RAM/0 DRM/4 APM与父版相同，224 IO另计；原生PDS返回0、宿主return2/TIMING_FAIL，完整191.430秒。setup Slow/Fast -2.277/+0.318ns，hold +0.107/+0.083ns，脉宽 +4.346/+4.345ns。Slow较同RTL两区域改善2.659ns，且超过旧第9轮-3.064ns，成为当前最优WNS，仍未通过100MHz。新映射/布局，不是固定网表/placement比较。

最差变为内部地址寄存器→外部data_addr_o[25]，逻辑2级、逻辑3.195ns/布线3.431ns，主要含输出buffer及寄存器到pad连接。前20条中仍可见PC→BTB选择→RAS CE核内setup -1.929ns，不能宣称CPU内部已经通过。下一步只启用官方syn_useioff现有IO寄存器pack进行物理对照；保持原时序预算、RTL和流水周期。是否实际pack及其收益须查新映射/最终报告。
