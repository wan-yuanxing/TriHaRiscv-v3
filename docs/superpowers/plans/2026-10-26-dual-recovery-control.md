# 恢复及存储控制路径分阶段检查

依据v64实际后布线8个违例，不再修改队列或扫布局种子。第一阶段只消除分支方向选择之后的预测PC比较：在triha_e1_branch内并行计算目标PC与顺序PC的预测不匹配位，再由方向选择窄结果；未知方向保留原合并语义。fault、stall、squash、CSR优先级、恢复PC及训练输出不变，无新增周期。

- [x] 实际branch组件：旧比较链结构RED、新结构隔离GREEN、普通二态/四态对照、真实输出破坏负例。
- [x] 从v64完整冻结patch重建新候选；只改issue内两路branch比较接口和recover条件。
- [x] ordered/IRQ回归及完整-O2 SRAM轨迹/计数比较，要求>4/MHz。
- [x] 原生映射保留两路预比较，方向到recover连接深度2/3，记录CPU-only9584LUT/4908FF，不提前PNR。深度不是STA；FIFO1356引脚全图通过。
- [x] v66 ROM使能隔离及v67 selector内部更新隔离：保留外部门控/异步清零/X-Z回退；组件、破坏负例、完整CPU轨迹、原生映射通过。默认SoC未修改。
- [x] 三类路径结构检查及独立启动评审通过；只对新包dual-memory-control-io-physical-v67运行一次原约束物理实验。
- [x] 核对最终实际多corner报告、冻结输入与444输出哈希；v67 setup−0.218ns，仍FAIL，剩ROM数据返回/旁路相关3端点。保留v57最佳−0.009ns；无第二次同候选布线。

工作仍在独立CPU工作树，默认源与集成不变。候选及日志留build/cpu，测量和源码清单保留在docs/verification/cpu。短仿真不当板级分数，native mapping不当时序通过。
