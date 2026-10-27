# 条件目标纯加法边界 v75

基线v74；其实际布线-0.297ns最差为issue有效→新目标carry。实际综合网表N46_1_4 carry输入I0=N16，连接到div_opcode_valid_w（通用发射有效命名），与PC/立即数共同驱动COUT。原因是capture否则清零逻辑吸收进加法，不是除法结果依赖。

最小实验仅将相同issue_pc+Bimm表达式提为syn_keep的32位wire，再由原always采样。所有状态、hold/flush/reset优先级和周期不变。先组件状态不变量与负例，再整核CoreMark；native必须核验实际COUT支持锥，不能以保留网名代替控制独立。历史保留属性也曾布线退步，因此该实验不自动PNR。

默认RTL和集成主线不改，100MHz仍未通过。v74失败证据完整保留。

## 准入结果

组件24577项、负例、LSU异常与MUL/branch程序通过。纯sum提取逆变换逐字符还原v74；triha_issue.v字节相同，复用其41151项完整分支oracle证据。完整SRAM CoreMark保持1221907周期/1448448观测WB，4.0919644457/MHz短估算；measurement/profile、镜像及WB/store与v74一致，非官方分数或板测。

原生三阶段通过，68输出哈希核验。u_core9527LUT/4975FF/752已包含RAM-LUT/4APM/0DRM，比v74+11LUT/FF不变；严格u_cpu9526LUT。映射不能只检查保留的孤立sum：两路各32个实际目标FF的D均消费对应sum bit，并检查D锥及sum锥全部30个COUT/路，仅依赖PC/opcode/常量。未知、别名多驱动和组合环均拒绝，真实控制边图注入得到HOLD。该结果只是局部结构，不是完整时序。

独立审查重放正常/负报告并核对native68和CoreMark122输出，允许一次原100MHz物理诊断。目录build/cpu/dual-target-sum-io-physical-v75；原IO/hold/多corner不变。须确认实际布线中控制保持在结果选择/寄存器控制端，同时检查剩余SRAM与CSR违例。

## 实际物理终态

工具完成布线、退出0，验收runner退出2，TIMING_FAIL。356输出与冻结输入、五阶段成功标记核验。Slow/Fast setup -0.409/+2.663ns；hold +0.111/+0.102ns；MPW +3.655/+4.202ns。Slow 22端点，TNS -3.053ns。相同10ns/IO/hold约束下比v74的-0.297ns更差，是新网表新布局，不能宣称频率收益。

完整报告22条setup违例中，11条BTB target RAM WE，11条B分支恢复→fetch PC CE；没有新目标寄存器端点。实际route包synthesis重放仍确认64实际D消费sum、60条carry不含控制。局部目标确实达成，但整体未收敛。

最差BTB路径：训练包寄存器→写口tag读RAM→tag选择/比较→write_target→target_we，6级，logic1.229ns/route9.163ns（88.174%）。训练索引网络扇出601；最后两段write_target/target_we布线分别2.145/2.435ns。原target-write条件为write_i && (taken_i || !write_hit)，不能为缩路径直接删除tag匹配，因为未跳转且命中时应保留旧目标。

后续应在保持预测策略/状态和周期的前提下审查BTB写口块内比较及索引/写使能局部化，并同时处理B分支恢复CE；需要独立验证四态索引、同址读写和更新优先级。停止对纯sum添加属性或重复seed。不提升默认版；最佳历史v57仍-0.009ns FAIL。
