# 条件目标纯加法边界 v75

基线v74；其实际布线-0.297ns最差为issue有效→新目标carry。实际综合网表N46_1_4 carry输入I0=N16，连接到div_opcode_valid_w（通用发射有效命名），与PC/立即数共同驱动COUT。原因是capture否则清零逻辑吸收进加法，不是除法结果依赖。

最小实验仅将相同issue_pc+Bimm表达式提为syn_keep的32位wire，再由原always采样。所有状态、hold/flush/reset优先级和周期不变。先组件状态不变量与负例，再整核CoreMark；native必须核验实际COUT支持锥，不能以保留网名代替控制独立。历史保留属性也曾布线退步，因此该实验不自动PNR。

默认RTL和集成主线不改，100MHz仍未通过。v74失败证据完整保留。

## 准入结果

组件24577项、负例、LSU异常与MUL/branch程序通过。纯sum提取逆变换逐字符还原v74；triha_issue.v字节相同，复用其41151项完整分支oracle证据。完整SRAM CoreMark保持1221907周期/1448448观测WB，4.0919644457/MHz短估算；measurement/profile、镜像及WB/store与v74一致，非官方分数或板测。

原生三阶段通过，68输出哈希核验。u_core9527LUT/4975FF/752已包含RAM-LUT/4APM/0DRM，比v74+11LUT/FF不变；严格u_cpu9526LUT。映射不能只检查保留的孤立sum：两路各32个实际目标FF的D均消费对应sum bit，并检查D锥及sum锥全部30个COUT/路，仅依赖PC/opcode/常量。未知、别名多驱动和组合环均拒绝，真实控制边图注入得到HOLD。该结果只是局部结构，不是完整时序。

独立审查重放正常/负报告并核对native68和CoreMark122输出，允许一次原100MHz物理诊断。目录build/cpu/dual-target-sum-io-physical-v75；原IO/hold/多corner不变。须确认实际布线中控制保持在结果选择/寄存器控制端，同时检查剩余SRAM与CSR违例。
