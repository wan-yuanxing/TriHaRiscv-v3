# 存储控制路径候选 v67

在v65 CPU分支预比较和v66 ROM指令使能隔离的基础上，仅改两个指令目标选择寄存器的内部更新条件。异步清零仍由原复位分支负责；内部更新去掉重复的外部accept复位门控，外部接口、RAM写入、响应和pending行为不变。reset为X/Z时回退旧表达式，保留仿真语义。

组件对照包含异步复位、复位下禁止写、释放首拍、碰撞挂起、ROM/SRAM并发、未知输入和reset X/Z。先建立已知SRAM selector再切未知reset+ROM，使错误更新可观察。破坏fallback负例按预期失败。结构测试旧版RED、新版GREEN。

完整SRAM CoreMark为1221907周期、1448448条WB，4.091964 CoreMark/MHz。ROM/SRAM镜像、完整WB/store与profile均和v65一致。该数值是-O2 RTL短测，非板测或官方分数。

原生CPU-only为9581LUT/4908FF/752已含RAM-LUT/4APM/0DRM。两selector实际为GTP_DFF_CE，异步C引脚仍接复位反相；CE组合锥126节点无reset或unknown。ROM锥无维护/碰撞控制；FIFO后端全层级检查通过、无别名歧义。实际CE LUT注入reset的负例被检查器拒绝。上述均为映射检查，不是STA。

独立评审复核输入、固件、约束和映射后，`build/cpu/dual-memory-control-io-physical-v67`完成一次完整物理实验。保持原10ns、IO/hold、多corner、seed1、PNR10分钟及外层900秒。**100MHz仍未通过**。默认RTL、主工程集成及板卡未修改。

实际后布线：setup Slow/Fast **−0.218/+2.835ns**，hold **+0.103/+0.064ns**，脉宽 **+3.655/+4.202ns**；Slow setup有3个违例端点，TNS−0.371ns。native返回0、验收器记录runner2；444个输出、冻结输入和五阶段成功标记已核验。CPU-only仍为9581LUT/4908FF。相比v64的−0.396ns改善，但新映射/布局仍弱于历史最佳v57的−0.009ns，保留最佳基线。

本轮route自己的综合网表再次通过selector/ROM/FIFO/分支结构检查。当前瓶颈为：

- ROM **数据口CLKA/rom_data** → memory读响应合并 → LSU格式化 → E2旁路 → B路ALU减法 → result[21]，12层，logic3.364ns、route6.364ns，setup−0.218ns。不是ROM取指口使能路径。
- 同一ROM数据返回 → load旁路 →零比较分支 → FIFO head1更新，12层，−0.142ns。
- FIFO head1 → B路执行结果，9层，−0.011ns。

后续优先核对同步小ROM的实际映射选择及数据返回/旁路深度，必须保持ROM映像、可读语义和读延迟；不得用删除ROM读取、伪造false path或放松时序消除路径。不启动第二次同候选布线或扫seed。

证据：[dualissue_memory_selector.json](../verification/cpu/dualissue_memory_selector.json)。
