# B分支类型预比较 v77

基线v76（v75纯目标sum+BTB块内写许可）。实际v75 B恢复CE路径从opcode类型译码经branch_target_r宽选择、比较carry到recovery，最差-0.249ns。本轮复用v71的conditional/JAL/JALR分别比较后选择标量方案；v71当时受conditional加法路径限制而HOLD，现在条件目标已在E1寄存，前提已变。不得把历史HOLD直接当本轮通过。

保持目标数据、方向判断、异常、四态fallback及所有周期不变。先父版全分支输出oracle、旧目标向量污染红测和新正测、实际标量比较损坏负例，再完整CoreMark和native。实际门槛为类型控制退出比较carry，并同时保留v76的实际RAM WE局部性，不能只看比较器名字。未经组合候选验证不进行PNR，原100MHz约束不变。

## 本轮验证

- 分支组件 normal / 旧宽目标污染各41151检查通过；实际标量比较损坏负例检出。单/双发射 ordered 与 IRQ/mret 通过。
- 完整CPU短测1221907周期、1448448 observed WB，observed IPC 1.185400、CoreMark/MHz 4.091964。measurement/profile/WB/store与v76相同；非官方或板测分数。
- native compile/synthesize/dev_map通过。CPU核u_core9840 LUT/4975 FF，含752 RAM-LUT、4 APM、0 DRM；较v76 +85 LUT/−2 FF，不含SRAM/MMIO夹具。
- 两路三类比较器实际carry均仅依赖对应target与predicted边界；JAL bit0在映射中复用PC bit0。原mismatch_o名称被优化，改查实际recovery连接，六个比较结果均被消费。3条最短连接不是最大路径延迟或STA结论。
- 注入opcode类型控制及断开比较输出的两个图负例均HOLD；BTB256实际WE局部性、624地址连接及80两级边界保留。独立复核同时确认64目标FF D/60 COUT纯sum门槛。
- 组件、完整CPU122项、native68项输出哈希核验。详细证据：`docs/verification/cpu/dualissue_branch_type.json`。

## 物理验证

独立评审支持单次原约束PNR，已启动`build/cpu/dual-branch-type-io-physical-v77`。原10ns、IO/hold、多corner、seed1不变；PNR600秒、外层900秒。全新compile/map/place/route。未完成最终STA前不称100MHz通过，不提升默认RTL，不接触主工程集成或板卡。
