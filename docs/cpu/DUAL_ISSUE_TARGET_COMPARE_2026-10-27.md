# 分支目标预比较 v71

目标仍为六级双发射、无Cache/DDR、-O2 SRAM/TCM >4 CoreMark/MHz和原100MHz实际时序。v70有11条setup违例，8条经过条件分支目标→类型选择→预测PC比较→恢复→fetch CE。路径布线占82%，因此RTL层数变化不能直接代表时序改善。

复用现有并行比较组织：conditional、JAL、JALR目标分别比较预测PC，再按原procedural if优先级选标量。方向未知时原向量合并fallback不变；所有next_pc、request/fault/CSR接口、状态和周期不改。替代方案为最终CE局部分组或寄存恢复；前者可能被综合合并，后者引入新的周期语义，本轮不采用。

实施门槛：先冻结父版完整分支模块作为oracle，随机及X/Z对照全部输出；用目标向量污染验证比较移至目标mux之前，用真实比较信号破坏验证oracle可失败；完整CoreMark和WB/store/profile保持一致后原生映射；核对比较锥、复制资源及扇出，不直接启动PNR。

当前组件41151检查及结构污染测试PASS，旧结构红测和真实比较负例检出。可重放脚本scripts/cpu/check_branch_target_compare.py。完整CPU回归PASS，仍1221907周期、WB1448448、短测4.091964/MHz；镜像、全部WB/store轨迹及profile与v70一致。

SRAM三条违例仍未解决：数据经过memory merge、LSU byte/half选择与符号扩展、E2旁路后到判零/FIFO或B ALU。下一步独立评估符号扩展与选择的顺序及E2零属性边界，不增加stall，不以只改善8条CE违例宣称全核收敛。v71未PNR，100MHz未通过。

## 映射筛选结论

原生compile/synthesize/dev_map PASS，CPU-only9583 LUT/4905 FF/752个已包含RAM-LUT/4 APM/0 DRM，比v70 +27 LUT/-2 FF。三个比较信号保留，每个比较输出到对应recover有2级最短连接；conditional_pc[10]到recover的最短连接为13，父v70同样13。该数值只是图连接，不是STA。部分原名被优化掉，不能用找不到信号当作无依赖。当前无法证明实际关键路径缩短，因此HOLD，不启动v71 PNR，不更换最佳或默认版本。

映射检查器修正了GTP_LUT6D常量选择处理：I5固定1时Z仅使用高半真值表，旧全表支持引入假环。只对字面0/1计算固定输入下的依赖，未知/未连接/别名保持保守。新增4个正负测试，先复现失败后修复，全部13项通过；recover0锥中的该假环消失；不推广为全网无环证明。该修复用于检查器准确性，不是CPU时序收益。

下一步LSU零属性需保留byte地址未知时默认0载荷→零标志1，half地址未知走低半字，以及byte/half控制未知时的过程式跳过语义。E2零选择必须镜像LOAD/STORE优先、MUL其次、默认ALU，使用valid_e2_q，且不引入ack/error门控。SRAM到B路ALU仍需独立处理。

资源口径沿用u_core（含1 LUT的CPU包装，排除ROM/SRAM/MMIO夹具）；严格u_cpu行9582 LUT/4905 FF。独立只读审查确认HOLD结论及检查器常量处理安全性。
