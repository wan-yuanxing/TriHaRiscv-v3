# 分支恢复比较阶段记录

v65在v64环形后端上仅修改两路E1分支的预测PC不匹配判断：目标PC与顺序PC分别比较后，再由方向选取结果。未知方向仍使用原向量合并语义。恢复PC、异常优先级、取消年轻结果和周期均未改变。默认CPU与SoC源码未提升。

完整SRAM短测通过，1221907周期、1448448条WB、70839条store，4.091964 CoreMark/MHz。镜像、完整WB/store及profile与v57一致；这是RTL短仿真，非板测或官方分数，WB观察IPC不是minstret。组件24378次检查、有序/IRQ两模式通过，错误标量选择和真实输出破坏负例均按预期失败。

正确原生包`build/cpu/dual-recovery-compare-native-gate-v65`只执行compile/synthesize/dev_map，返回0，68个输出及冻结输入哈希核验。CPU-only9584LUT/4908FF/752已含RAM-LUT/4APM/0DRM，比v64增加49LUT，FF不变。

两路预比较在映射中保留；方向到recover的保守连接深度为2/3，到recovery为3/4。这些是连接诊断，不能当作时延或频率收益。FIFO后端1356个D/CE引脚全层级核查通过，1209个访问节点、无pop支持、无未知节点。

检查器最初把GTP_LUT6D两个输出均连到全部输入，产生假的pop支持。按已安装厂商模型，Z5只使用INIT低32位；实际N13_sum2_7的Z5不依赖I3。已按逐输出真值表支持精化，未知/缺失INIT仍保守，独立评审复核3266个支持集合。测试包含真实pop和INIT破坏，未通过忽略未知节点换取PASS。

执行事故保留：`build/cpu/dual-recovery-compare-io-native-v65`曾误用旧v64仿真绑定调用完整route入口，发现后停止已核实的自有进程。native/runner均为1，未进入PNR；该FAIL记录保留，排除于v65验收。正确包重新绑定本轮成功仿真，且执行Tcl明确不含PNR。

**100MHz尚未通过，本候选没有后布线结果。**最佳完成物理基线仍是v57的setup −0.009ns，也不算通过。后续先处理以下两类真实违例，再决定物理准入：

- ROM取指使能：有效ROM命中与SRAM碰撞互斥，应验证解除对LSU flush/写冲突的依赖。需覆盖挂起SRAM请求时实时地址切ROM、并发SRAM写、非法维护操作及未知输入，不能直接删门控。
- 选择寄存器CE：现有异步复位分支之外，i_service又含复位组合门控。需验证内部更新条件和外部接受/写使能能否分离，保留复位期间无副作用、释放首拍、挂起请求和无效输出历史。尚未实现或证明。

本轮证据：[dualissue_recovery_compare.json](../verification/cpu/dualissue_recovery_compare.json)。
