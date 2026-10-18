# CPU 物理区域诊断

目标仍为实际后布线100MHz。第5轮逻辑降至7256 LUT而布线占最差路径88.163%，因此本轮只改变物理区域，不继续叠加RTL改动。

固定第5轮RTL、原10ns/完整I/O/hold/multicorner时序FDC、seed1和10分钟PNR/900秒外层上限。附加`cpu_compact.fdc`：`define_attribute {i:u_cpu} {PAP_REGION} {cpu_compact(0,64,100,199)}`。依据本机PDS UCE手册2.3.4.7，模块层次属性会传播至映射叶节点。器件clock_utilization报告中这两个相邻区域合计18400 LUT、40 APM容量，足以容纳CPU；这是容量判断，不是频率证据。

- [x] 通过独立recipe保存区域属性，原时序FDC字节不变。
- [ ] 完整运行compile/synthesize/dev_map/place/route/report_timing。
- [ ] 核对约束转换及叶节点绑定；没有实际证据则标记UNKNOWN，不把输入属性当生效证明。
- [ ] 核对六项Slow/Fast最终时序、performance一致性、冻结源与输出哈希及原生退出码。
- [ ] 保存与第5轮的同RTL比较和实际资源/关键路径，不将工具成功、布局估算或拥塞数当100MHz通过。

运行入口：`pwsh -NoProfile -File scripts/cpu/run_route.ps1 -Compact`。未生成bitstream或编程板卡。
