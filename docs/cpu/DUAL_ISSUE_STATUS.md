# 双发射独立路线状态

更新：2026-10-23。工作树 `D:/FPGA/TriHaRiscv-cpu-dualissue-windows`，
分支 `cpu/dualissue-windows`，基线 `340bcc2`。主工程和 SoC 集成继续各自推进。

已完成现有六级顺序双发射路径的缓存封装接通及模拟功能基线。默认仍为单发射。
固定 RV32IM/CSR、BTB512/BHT512/RAS4、I/D 各 16KiB/两路/32B 行，D 写回/写分配。
共享 LSU/乘除法资源与现有接口不变。

同一加载程序、GCC15.2 `-O2`、五次 CoreMark、相同 AXI DDR 数字模型下，
单/双周期 2,014,969 / 1,781,952，短测 CoreMark/MHz 2.481428 / 2.805912，
吞吐提升 13.076503%。WB 观测 IPC 0.718844 / 0.812843，不是架构 `minstret`。
完整计时 WB/store 除已核实的绝对起始时间外相同；CRC 和破坏负例通过。
这是 RTL 仿真，非官方或板级分数。

当前门槛是原生 CPU-only 资源及真实后布线 100MHz；二者均 UNKNOWN，
尚未开始本路线 PDS 或板测。待集成任务的 PDS 工作释放工具后，先用现有
CPU-only 单/双映射比较 FF 四读两写寄存器堆成本，再决定 Pango RAM 适配。
不把旧单发射时序或整板面积作为新双发射的验收结果。

完整证据及重现命令：[模拟基线](../verification/cpu/dualissue_cached_baseline.md)。
后续准入需继续覆盖精确异常/中断、依赖与共享资源互锁、ISA、完整 Cache
维护语义，以及多 corner 物理时序；本功能基线不替代这些门槛。

## TCM 主目标与 Cache 对照（2026-10-23）

用户明确最高性能目标以 SRAM/TCM 为主，要求超过 4 CoreMark/MHz。
已完成 DDR Cache-off/on 四组短测；双发射分别为 0.459042 / 2.805912。
TCM 双发射基线 3.543019，隔离窄 MUL 转发候选 3.658271，尚未达标。
候选全计时 WB/store 对照及定向、有序执行、中断自检通过，生产 RTL 保持不变。
详见 [TCM 诊断](../verification/cpu/dualissue_tcm_profile.md) 与
[Cache 矩阵](../verification/cpu/dualissue_cache_matrix.md)。

## 配对优化短测达到门槛（2026-10-23）

隔离候选TCM **1,249,840周期 / 4.000512 CoreMark/MHz**，同固件-O2，
不带observer复现相同cycle；比双发射初始基线吞吐提高12.912533%。
DDR Cache开/关分别为3.078298 / 0.459491。完整WB/store、定向负例、
有序异常/IRQ回归和独立只读评审已完成。仅RTL短测达标，非官方/板级成绩；
CPU-only资源与实际100MHz仍UNKNOWN，生产RTL和集成工程未改。
见[配对优化证据](../verification/cpu/dualissue_pairing_performance.md)。
