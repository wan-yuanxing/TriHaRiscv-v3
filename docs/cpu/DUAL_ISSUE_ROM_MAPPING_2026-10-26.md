# 启动 ROM 映射候选 v68b

v67两个主要违例均从ROM数据读口出发，经LSU/旁路到B路ALU或分支控制。块ROM输出tco为1.565ns。实际启动镜像大部分内容相同，仍强制使用DRM，故本轮先验证同步逻辑ROM映射，CPU/LSU不改动、不增加等待周期。

依据本机ADS Synthesis User Guide 5.18，`syn_romstyle="logic"`支持ROM输出信号。首次仅改数组属性仍映射到DRM；记录保留，未进入整核布线。按手册把属性放在两个输出reg并移除数组block_rom属性后，实际组件映射为4LUT/4FF/0DRM。去除属性改动后RTL与原版完全一致，1024×64地址空间、双端口、镜像、同步一拍读取及使能保持均保留。

实际综合网表通过5124次对照：两口各遍历1024地址，覆盖独立使能和保持；读数据破坏负例失败。首次使能前输出不作定义，首次读取后逐周期检查。该资源数仅适用于当前冻结启动镜像，不外推任意ROM内容。

完整SRAM CoreMark通过：1221907周期、1448448条WB、4.091964 CoreMark/MHz；ROM/SRAM镜像、完整WB/store/profile与v67一致。这是-O2 RTL短测，非板测或官方分数。

整核原生映射为CPU-only9703LUT/4908FF/752已含RAM-LUT/4APM/0DRM，ROM夹具另计4LUT/4FF/0DRM。CPU逻辑源码没有改变，但综合优化后的CPU面积比v67增加122LUT，不能把此次变化当作仅改变ROM位置。

原10ns/IO/hold/multicorner/seed1完整布线终态为 **TIMING_FAIL，不采用此候选**：

| 检查 | Slow | Fast |
| --- | ---: | ---: |
| Setup | −1.376ns | +2.639ns |
| Hold | +0.116ns | +0.102ns |
| MPW | +3.655ns | +4.202ns |

Slow setup共108个违例端点、TNS−32.588ns，弱于v67的3端点/−0.218ns，也弱于历史最佳v57的−0.009ns。native返回0、验收器记录runner2，476输出/冻结输入及五阶段标记已核验。工具完成不能替代时序通过。

最差已变为B路pc_e1[9]→pc_x[31]，11层、logic1.888ns、route9.138ns；其它包括data_error→SRAM CE。双口ROM都改为逻辑实现引起了全局重映射/布局变化，不能根据局部组件去掉DRM就推导整核收益。该实验停止，不再扫seed或重跑。

后续回到v67的ROM数据返回/LSU旁路链进行分析。若再评估ROM资源，必须先限定只影响数据读口、保留取指口物理实现，验证真实映射及语义后才讨论物理准入；本轮没有实现或启动这一方案。默认RTL、集成工作树和板卡不变，**100MHz仍未通过**。

证据：[dualissue_rom_logic.json](../verification/cpu/dualissue_rom_logic.json)。
