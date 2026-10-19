# CPU片上系统实施计划

执行方式：当前会话内逐项实施与复核，不使用agent。

- [x] 归档固定IO诊断，保留TIMING_FAIL和首轮工具失败。
- [x] 添加config/soc_map.json与生成器，生成RTL/C和SRAM链接脚本；--check拒绝漂移。
- [x] 写tb/soc/tb_soc_memory.v，实际缺模块RED；实现rtl/soc/triha_soc_memory.v、triha_sram.v、triha_boot_rom.v和triha_uart_tx.v。ModelSim验证协议、独立内存oracle及负例。
- [x] 添加rtl/soc/triha_minimal_soc.v，连接稳定CPU，写正式地址固件/ROM镜像工具与集成TB，运行runtime及CoreMark，记录周期/CRC/WB观察。
- [x] 添加显式cpu_minimal_soc目标和相应100MHz FDC，重用现有报告解析器，完整PDS后布线，核验两corner六项和哈希。
- [x] 更新STATUS/证据与已知限制，小批提交，不自动合并或烧板。

主要命令：python scripts/soc/gen_config.py --check；python scripts/soc/run.py --test memory；python scripts/soc/run.py --test runtime；python scripts/soc/run.py --test coremark；pwsh -NoProfile -File scripts/soc/run_route.ps1。所有运行独立build/soc目录，失败非零。

首轮完整物理结果TIMING_FAIL（Slow setup −1.206ns）。计划项完成表示完成实现和真实验收，不表示100MHz通过；保持原约束继续按实际路径优化。


后续收敛检查点：

- [x] 单拍本地存储返回，366项协议检查与CoreMark 1685831周期。
- [x] 原生SRAM综合网表12296项与真实损坏拒绝；整核4类访问异常。
- [x] 并行BTB fallback优先计算，整核/组件/两模式CoreMark完整回归，系统周期保持。
- [x] 第三轮完整时序核验：Slow setup −0.183ns，仅4个端点，其余五项通过。
- [x] 同一RTL/固件下局部前端布局对照的最终后布线核验（失败保留）。
- [x] 实际100MHz六项setup/hold/MPW全部通过；失败记录不改写。
- [x] 交付当前通过配置、CPU核资源与后续板级入口说明。

最终PASS证据：docs/verification/cpu/minimal_soc_100mhz.md，compact/seed1，Slow setup+0.232ns。CPU工作树保留，不自动合并或烧板。
