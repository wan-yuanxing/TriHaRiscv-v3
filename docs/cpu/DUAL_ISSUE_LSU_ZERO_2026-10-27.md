# LSU符号扩展前零属性 v72

从v70派生，v71 HOLD不叠加。目标保留所有加载数据、异常、转发tag和周期，原100MHz约束及-O2 SRAM>4/MHz不变。

复用现有窄标志转发组织：LSU原始返回数据预计算4个byte-zero/2个half-zero/word-zero，按原byte优先、half次之、word默认选择。byte地址X/Z时默认零载荷→标志1；half地址bit1未知走低半字。符号位与signed未知不改变零判定等价性。E2镜像原过程式LOAD/STORE、MUL、ALU选择，valid_e2_q，不添加ack/error或stall门控；两路issue来源2/3使用标量，数据通路不动。

- [x] 缺失侧带红测、实际LSU/E2四态对照、真实侧带负例。
- [x] 完整CoreMark/WB/store/profile、已有加载与异常测试。
- [x] 原生映射核对格式化后宽归约是否移除、零属性输入扇出/资源成本。
- [ ] 与独立SRAM→B ALU路径分析合并评估；未经实际结构审查不启动PNR。

该优化只针对SRAM→FIFO判零许可，不能单独解释为全核时序修复。默认RTL和主工程不变。

## 本轮验证

四种LOAD/MUL bypass配置各102401检查PASS，合计409604。包括完整1024组LSU四态metadata与36种payload，以及独立256组E2选择控制×256组ALU0/ALU1/MUL/memory载荷；补测消除了初版控制相关性遗漏有效STORE的问题。真实LSU输出和E2输出破坏均检出。

实际指令测试377周期，48次LB/LBU/LH/LHU/LW和48条依赖ALU退休结果正确，LSU A/B发射44/5（含完成store），220拍保持。已有精确fault/badaddr/mtval和乘法程序PASS。测试先前在完成store发出时提前检查最后一条ALU退休，现等待退休完成；RTL未因此修改。

完整CoreMark仍1221907周期，WB1448448，观察IPC1.185400，-O2短测4.091964/MHz；镜像、完整WB/store/profile与v70一致。均非官方或板级跑分。

原生compile/synthesize/dev_map PASS；CPU-only u_core9514 LUT/4911 FF/752个已包含RAM-LUT/4 APM/0 DRM，相比v70 -42 LUT/+4 FF。未新增RTL状态，但综合复制及全局映射改变，不能当固定布局对比。

映射零锥166节点，无格式化后32位结果依赖、无ack/error/unaligned依赖和未知节点；零标量有2个组合消费者。原raw_source_zero[2/3]名被优化掉，明确不可用，不把名称不存在当作无路径。SRAM data[23]到LSU零输出最短4条连接仅为拓扑诊断，不是STA。

## 剩余工作

v72未PNR。保留为功能/局部结构通过候选，不直接消耗一次物理实验。v70剩余两条B路违例实际经过exec1输入选择、立即移位器N44/N50及最终muxf7，并非加减carry；下一步评估专用移位数据入口，但需保持SUPPORT_ALU_PREDECODE任意值和未知解码的兼容性。分支恢复→fetch CE仍需处理；最佳已完成v57 -0.009ns仍为FAIL。

首次重建因原pipe_ctrl无末尾换行导致生成patch缺少EOF标记而失败，预检拒绝，未启动ModelSim；失败目录保留，修正patch后新clean目录逐项hash重建成功。有效证据见[dualissue_lsu_zero.json](../verification/cpu/dualissue_lsu_zero.json)。

独立审查确认功能/局部结构证据一致，未授予PNR准入。资源口径u_core含1 LUT包装；严格u_cpu为9513 LUT/4911 FF，均排除ROM/SRAM/MMIO夹具。
