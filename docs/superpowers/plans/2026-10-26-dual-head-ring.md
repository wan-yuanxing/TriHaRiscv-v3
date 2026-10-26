# 双发射头部与环形存储实施计划

目标：保持v57六字容量、两字预留、跨包发射和原性能条件，解除pop对后部载荷写口的组合控制。使用现有Windows/ModelSim/PDS/GCC及独立CPU工作树。

设计细化：环形存储记录所有已接受输入，写指针仅随输入推进；两个头寄存器为读取副本。读指针随总消耗推进。B-only时头0保留，环形读指针推进1，此位置的旧内容被头0覆盖解释，后续字仍按环形顺序读出。总可接受容量仍为6，不因两个副本增加。头部用旧队列优先、新输入补齐，不新增组合输出旁路。flush清零计数/指针；头部bulk按旧更新规则变化，metadata保持。环形无效槽不外露，已写后才能作为有效补充值。

- [x] 新增独立序列oracle及后部不搬移测试；在v57先确认结构RED，普通行为检查PASS。
- [x] 从v57创建隔离候选，只替换FIFO实现，保存完整基线patch/manifest。
- [x] 检查全部可见输出、四种消费、输入0/1/2、回绕、flush、B-only、断续PC；加入实际输出破坏负例。
- [x] 运行现有decode对齐、异常/IRQ顺序和相同-O2 SRAM完整CoreMark/轨迹比较。
- [x] 若功能与>4/MHz满足，再做原生综合；后部D/CE不可含pop支持，核对全局面积与新头部选择器成本。
- [x] 结构评审决定是否准入一次原10ns后布线；未满足门槛不启动PNR。

新增状态是头部副本与环形指针；默认RTL不替换。测试/证据进入tb/cpu和docs/verification/cpu，生成物留build/cpu。只保留独立实验，不影响集成与板卡。

实施检查：恢复父版读索引syn_maxfan16，避免无关的扇出变化。106个合法交叉bin、20821步及全116位backend保持检查通过；对齐EXTRA_DECODE0/1、ordered97、IRQ/pair173、SRAM runtime通过。原型CoreMark300秒截断，保留FAIL；修订候选在显式600秒上限内319秒完成，1221907周期、4.0919644457/MHz，镜像/WB/store/profile与v57逐字节一致。

原生综合CPU9535LUT/4908FF/752已计入RAM-LUT/4APM/0DRM。局部检查不足以排除综合器跨层搬移，因此追加完整层级别名/位连接追踪：1356个backend D/CE引脚、1701个上游节点，零pop支持、零未知；状态边界包含FF与经过模型审查的同步RAM，保留RAM复位及级联组合边。跨层隐藏pop负例拒绝。独立审查无剩余准入阻塞。

同结构第一次原10ns、原IO/hold、多corner、seed1完整物理运行已结束，位置`build/cpu/dual-head-ring-io-physical-v64`。实际setup−0.396/+2.660ns、hold+.112/+.100ns、MPW+3.655/+4.202ns，native0/runner2。442输出及冻结输入已核验。未达100MHz，不启动第二轮；先审查复位、分支恢复→CSR、LSU flush→ROM使能三类剩余违例。全部证据见`docs/verification/cpu/dualissue_head_ring.json`。
