# 现有IO FF打包诊断（第17轮，未采用为最佳配置）

同第16轮RTL、单时钟区域、原100MHz/IO/hold/multicorner、seed1及预算，仅添加ADS手册5.22支持的`define_global_attribute {syn_useioff} {1}`。没有手写额外流水寄存器，也没有编程板卡。功能证据同第15轮，全部哈希重新核验后复用。

实际map日志有96次成功的输出FF/IO打包，其中62次复制原FF。CLM FF计数5207→5173的净减少34，并不是仅打包34个，也不是CPU面积节省；包括IO FF共5173+96=5269，比原逻辑FF5207多62。输出寄存器复制不会增加时序级数，但会增加控制/数据驱动和物理布线负担。

原生PDS返回0，宿主return2/TIMING_FAIL，完整338.229秒。32项冻结输入/389项输出、23项同RTL输入及独立只读核验一致。实际setup Slow/Fast -4.776/-0.552ns，hold +0.056/+0.026ns，脉宽 +4.346/+4.345ns，performance一致。Slow较第16轮恶化2.499ns，违例端点2446→3042。该开关仅保留为已测诊断入口，不取代第16轮的最佳配置。

最差训练packet_q[38]→BTB匹配/优先写入选择→btb_target_q[5][13] CE：15级逻辑、逻辑2.264ns/布线12.105ns。上一轮也存在BTB读选择→RAS CE -1.929ns；后续应检验预测器读/写两条优先选择链，以等周期、保留最高表项优先级及重复tag语义的并行选择结构进行定向对照，再做实际STA，不能因为某次布局差就任意缩减预测规模。

证据`docs/verification/cpu/io_register_timing.json`包含实际打包/复制日志计数。最佳仍为`run_route.ps1 -SingleClockRegion`的setup -2.277ns，100MHz尚未通过。
