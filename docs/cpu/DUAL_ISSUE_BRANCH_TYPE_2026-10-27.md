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

## 最终物理结果

本轮完整执行341.55秒。主详细布线95次迭代到0，PDS退出0；验收器记录退出2，TIMING_FAIL（外层命令转发的退出1不代替验收记录）。冻结输入、282输出、五阶段成功标记和performance一致性均已审计。

| 检查 | Slow/ns | Fast/ns |
|---|---:|---:|
| Setup | -0.185 | +2.639 |
| Hold | +0.053 | +0.019 |
| 最小脉宽 | +3.655 | +4.202 |

Slow21违例，TNS-0.971ns。相比v75同10ns最差-0.409改善0.224ns，但本轮新映射/布局，不能归因到单一逻辑。历史最佳v57 -0.009仍FAIL，v77不是新最佳，也不是100MHz通过。

最差data_error→LSU delay→issue_lsu→SRAM CEB，5级、logic0.811ns/route9.155ns，占比91.862%为布线。两个SRAM CE端点失败。另19端点：15个pc_x CE、2个FIFO头CE、2个fetch branch_pc CE；主要由A路opcode[31]经JALR目标加法、比较、recover0/recovery到更新控制，最差-0.082ns。不能把物理单元名当新乘法或CSR数据路径；需读逻辑网络。

实际route包合成重查：两lane三组比较器及recovery消费、BTB256 WE/624地址/80延迟边界均PASS；这些局部结构目标保留，尚不足以关闭整体时序。

下一步只针对上述真实路径：先评估SRAM本地使能避免复用全局issue_lsu控制，保持错误响应、维护请求、写副作用和周期不变；并分析JALR目标加法/恢复扇出。不能直接删除LSU mem_error阻塞，不能把依赖rs1的JALR当作已提前计算的条件分支。先组件和映射门槛，不重复同候选/seed试跑。
