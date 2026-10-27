# B立即移位数据通路 v73

从v72派生。v70实际SRAM→B ALU负余量路径经过LSU格式化/E2旁路、exec1输入选择、立即移位及最终结果选择。目标在不改变任何周期或接口行为的前提下，让rs1移位不经过PC/立即数输入选择。

保留原ALU作完整fallback；对rs1来源的三个移位操作并行计算移位结果，在结果端选择。predecode非rs1、未知来源、未知ALU操作及legacy其他操作继续走原通路。这样保留任意predecode行为，代价可能是冗余移位逻辑；须以实际映射筛选，不能仅凭RTL独立线断言更快。

- [ ] 冻结父版exec及ALU为全输出时钟oracle，覆盖预译码开关、全部512个控制值、X/Z、reset/hold及shift边界。
- [ ] 旧输入选择污染红测，候选正测和真实输出破坏负例。
- [ ] 完整CoreMark及WB/store/profile保持，原生资源/连接比较。
- [ ] 只有结构门槛通过才考虑和分支恢复CE方案统一进行一次实际100MHz验收；本轮不预承诺PNR。

主工程和默认RTL不变，现有最佳时序仍v57 -0.009ns FAIL。

## 本轮结果

v73 HOLD，未运行PNR、未提升默认RTL。完整SRAM短CoreMark为1221907周期、1448448次观测WB、IPC1.1853995435、4.0919644457 CoreMark/MHz；不是官方或板级分数。完整WB/store/profile和ROM/SRAM与v72一致。

组件两模式各32510次全输出检查通过，poison各32511次；旧版污染红测和实际输出破坏负例均检出。额外96项覆盖hold=0的三种移位×32移位量，30项覆盖移位量逐位X/Z；原512控制值扫描包含hold，不宣称每项均完成寄存。

Windows PDS compile/synthesize/dev_map通过，CPU核u_core为9726 LUT/4932 FF/752 RAM-LUT（包含于LUT）/4 APM/0 DRM；比v72增加212 LUT、21 FF。RTL未添加状态，FF差异来自实际映射。严格u_cpu为9725 LUT，不能混入系统夹具资源。

局部连接追踪只在exec1输入边界内进行。检查64个候选移位中间位，20个有完整驱动且未经过原alu_input_a选择，13个驱动未解析、31个名字不可用。该部分结果不能证明完整路径缩短，也不是STA。资源增长而整条路径收益UNKNOWN，因此不以本候选启动PNR。

下一步保留v72为基线，处理实际分支恢复→fetch PC CE高扇出路径；v73不自动叠加。历史最佳v57仍为-0.009ns FAIL，100MHz尚未通过。

证据：`docs/verification/cpu/dualissue_shift_data.json`；完整重建使用同名前缀patch和sources.json；组件复现入口`scripts/cpu/check_shift_data.py`。
