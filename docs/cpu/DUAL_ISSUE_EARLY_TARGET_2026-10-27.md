# 条件分支目标提前计算 v74

基线v72，不叠加HOLD的v71/v73。实际v70最差路径从E1 opcode[8]经目标加法、比较、recovery到fetch PC CE。目标加法移至原E1采样边界之前，条件目标与PC/opcode相同reset/stall/accept/flush分支保存，两路各32bit；不新增流水级，不改变罚拍。跳转和寄存器间接跳转保持原路径。

对比方案：仅复制CE可能被工具合并且不移除加法；恢复再打一拍会改变取消和周期。选择同边界预计算，但必须检查发射→新寄存器的新路径，不把移走旧路径视为自动改善。

验证步骤：
1. 实际整核实例内对照两路新寄存器与原E1 PC/opcode组合oracle，16384七控制独立四态组合和完整B立即数；真实输出损坏负例。
2. 冻结原分支模块作全输出oracle，验证提前目标输入后的行为与X/Z。
3. 完整SRAM CoreMark，比较周期、WB/store/profile与镜像。
4. 原生综合核对新增状态、旧加法移除及新输入路径，独立评审后决定是否PNR。
5. 唯有原100MHz所有corner实际后布线通过方可验收；不修改默认CPU/SoC或板卡。

## 功能与映射准入

组件24577检查通过：16384独立控制组合（含两种squash和reset），8192次立即数输入覆盖4096个不同B编码组合各两次，另一个首拍定向用例；lane1使用不同PC/opcode。真实目标输出损坏负例检出。完整分支oracle41151项通过；单/双有序压力与IRQ/mret两组通过，IRQ不作逐条跨模式退休相同声明。

完整SRAM CoreMark保持1221907周期、1448448观测WB、IPC1.1853995435、短测4.0919644457/MHz。measurement/profile、全部WB/store和镜像与v72一致。不是板测或官方CoreMark分数。

native compile/synthesize/dev_map PASS；CPU核u_core9516LUT/4975FF/752已含RAM-LUT/4APM/0DRM，较v72+2LUT/+64FF。严格u_cpu为9515LUT。64个条件目标输入均在寄存器边界终止，64个GTP_DFF_CE存在。局部新D锥在pipe_ctrl实际输入处截断，最大32图边、未知0；这不是完整issue路径STA。两路新寄存器共用原N161 CE，每路多32负载；模块内CE连接469/374个FF引脚，不等于实际布局扇出。

独立审查允许一次物理诊断，保持10ns/IO/hold/multicorner及原seed。运行目录build/cpu/dual-early-target-io-physical-v74；需要检查新D/CE与原recovery、SRAM返回路径。启动不代表通过，不提升默认RTL或集成主线。
