# 双发射 v82：源寄存器使用角色预译码

v82 从保留的 v78 独立派生，未叠加失败的 v81。目标保持原 100MHz，六级顺序
双发射、SRAM/TCM、GCC15.2 `-O2`；不接 Cache/DDR、不修改集成主工程或板卡。
95MHz Git 标签和 534 文件完整归档不变。

## 针对实际路径的改动

v81 最差路径为 FIFO opcode bit3→源寄存器角色译码→依赖许可→fetch0_accept→
FIFO 头部写入。v82 将原 `register_roles` 的 3 位结果随 opcode 保存，发射端
只做原有 invalid/fault 资格判断。角色位仍是 rs1/rs2/rd 是否参与依赖检查，
不改变真实操作数、配对许可或控制状态机。

复用已有 FIFO 的可变数据宽度，每条 opcode 从 32 位扩为 35 位，上面保存取反
的角色位；每包输入从 64 位扩为 70 位。角色与 opcode 一起执行 bulk 更新，
包括 flush 后的无效载荷历史；旧 info/CSR 的 flush 保持规则不变。编码取反使
reset 全零载荷对应旧 opcode0 的保守角色111。名义新增 24 个状态位，未加流水级
或停顿。EXTRA_DECODE_STAGE 兼容路径沿用组合角色译码。

候选只改 `triha_decode.v`、`triha_frontend.v`、`triha_cpu.v`、`triha_issue.v`。
22 源文件的字节补丁/manifest 已独立重建验证，默认 RTL 未替换。

## 功能与性能

- 抽取真实旧角色函数和新资格函数，对照 1024 个 opcode/funct 组合，覆盖
  invalid/fault/选择的 X/Z 状态及随机未知指令位，共 272144 组双路检查。
- 旧实现对晚 opcode 污染按预期失败，新实现通过；损坏真实角色输入位仍失败。
- 实际 decode 队列四种 EXTRA/MULDIV 配置各 12005 拍，完整151位旧输出、ALU
  控制及至少12000拍角色/可见指令对照通过。真实角色 capture 损坏在第6拍检出。
- 单/双 ordered、IRQ/mret 及真实 E1 恢复通过。
- 完整 SRAM CoreMark 为 **1221907 cycles / 1448448 observed WB**，observed IPC
  **1.1853995435**，短测 **4.0919644457 CoreMark/MHz**。
  ROM/SRAM、完整 WB/store 和 profile 与 v78 相同，122 个输出哈希核验。
  这是 RTL 短测，未新增板测或官方分数。

队列测试初版的两次失败记录保留：既有测试嵌入的是旧 shift FIFO，并从可见
opcode 重算 ALU 控制，无法表示当前 FIFO 在 flush 时 bulk 更新而 info 保持的
历史。修订后复用原刺激，将所有旧输出和 ALU 控制直接接到冻结 v78 实际模块
作为 oracle；角色另外对照原角色函数。未通过删除 flush/X/Z 刺激掩盖差异。

8 组成功运行的 364 个输出、输入和外部工具哈希已逐一审计。

## 原生映射门槛

compile/synthesize/dev_map 通过，CPU-only 为
**9877 LUT / 5003 FF / 752 RAM-LUT（已计入 LUT）/ 4 APM / 0 DRM**。
对 v78 原100MHz映射为 +21 LUT/+28 FF；排除 ROM/SRAM/MMIO 夹具。

ADS 跨层暴露的是取反后的角色束。完整别名图确认 6 个角色位分别由两个队头的
`head{0,1}_q[52:54]` FF 驱动，A/B 资格输出各3位均消费相应角色，未检测到原始
opcode 支持或未知节点。实际 v78 已固定 `payload0_selected_w=1`，A 来自头0，
B 来自头1；检查器显式绑定冻结源码中的这个配置，不要求已被常量化删除的
A 路动态双头选择。独立逻辑测试另覆盖了选择 X/Z 的原过程式语义。

重新注入 opcode 依赖和切断角色输入的两个负例均 HOLD。早期按源码端口名或
错误地要求 A 消费两个头的 HOLD 记录保留。检查范围为实际连线，不是 STA 或
完整 FIFO 语义证明。原分支预比较、地址结果、BTB 块内写许可及16个 SRAM CE
门槛均通过。

## 100MHz 实现

运行目录 `build/cpu/dual-role-predecode-io-physical-v82`，完整新编译/综合/映射/
布局/布线。保持原 10ns、IO、hold、多corner、seed1、600秒PNR/900秒外层预算。
使用独立 TEMP，允许与独立集成 PDS 并行，不停止别人的进程。

## 终态：100MHz 未通过

五阶段全部成功，原生退出0、验收退出2；主详细布线158次到0。
30个冻结输入、408个输出及工具快照核验，source unchanged。实际周期10.0000ns，
performance slack 与最差setup一致。

| 检查 | Slow/ns | Fast/ns |
|---|---:|---:|
| Setup | **−0.994** | +2.520 |
| Hold | +0.112 | +0.099 |
| 最小脉宽 | +3.655 | +4.202 |

41个Slow setup端点违例，TNS−20.274ns。38条来自外部复位经BTB写地址缓冲，
最差rst_ni→960扇出复位网→metadata_we→两级写地址延迟→RAM WADDR[4]，
5级、logic1.381ns/route10.649ns（88.520%）。另外3条为B路E1分支恢复到fetch
branch_pc_q的CE，均−0.100ns。该统计不能替代完整41端点验收。

v82角色译码确已前移，但整体仍未超过v78同10ns的−0.175ns；新网表/布局不可
仅按局部拓扑判定收益。不重复本候选PNR、不扫描seed、不提升默认RTL。
95MHz归档仍完整。下一只验证BTB写地址在WE有效时的等价性，评估在不改变WE和
两级hold结构的前提下移除地址锥中多余的reset/train依赖；不降低约束。

证据：[dualissue_role_predecode.json](../verification/cpu/dualissue_role_predecode.json)。
报告：[triha_minimal_soc.rtr](../../build/cpu/dual-role-predecode-io-physical-v82/report_timing/triha_minimal_soc.rtr)。
