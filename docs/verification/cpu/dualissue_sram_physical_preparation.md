# 双发射真实 SRAM 边界与物理准备

2026-10-23，候选CPU仍与配对优化manifest相同，仅隔离SoC快照的DUAL_ISSUE从0设为1。
生产RTL、主工程和集成工程没有修改。复用真实8KiB ROM、32KiB同步SRAM和MMIO，
GCC15.2 -O2、五次CoreMark，实际双发射配对412320次，两个WB槽均计入。

结果：**1,253,888周期，3.987596978 CoreMark/MHz**，WB1448448，CRC通过。
这是新的软件地址/链接及真实SRAM边界，不是此前128KiB仿真TCM的同ELF比较；
比该短测多4048周期不能全归因于SRAM硬件。超过4仍需至少减少3889周期。
本边界性能尚未达标，实际时序也尚未验证。

物理输入已冻结至`build/cpu/dual-physical-sram-v1`，状态为PREPARED_NOT_EXECUTED。
使用原cpu_minimal_soc.fdc的10ns周期、setup/hold不确定度及输入输出延迟，
Tcl包含compile/synthesize/dev_map、Slow/Fast优化、hold修复及最终report_timing。
CPU面积仅按u_core统计；ROM/SRAM/MMIO单列，禁止用系统面积作为CPU面积。

集成侧有匹配自身目录的PDS综合/布局布线/报告进程，本轮未启动PDS、生成比特流或编程板卡。
待共享物理流程空闲后，仍须用受控执行器复核输入和退出码、阶段成功标记、实际双发射配置、
两corner setup/hold/脉宽及performance一致性。准备成功不等于综合、时序或上板通过。

入口：`scripts/cpu/run_dual_sram.py`、`scripts/cpu/prepare_dual_physical.py`。
79项Python检查通过；原始运行和冻结哈希见[机器记录](dualissue_sram_physical_preparation.json)。
