# CPU片上系统实施计划

执行方式：当前会话内逐项实施与复核，不使用agent。

- [x] 归档固定IO诊断，保留TIMING_FAIL和首轮工具失败。
- [ ] 添加config/soc_map.json与生成器，生成RTL/C和SRAM链接脚本；--check拒绝漂移。
- [ ] 写tb/soc/tb_soc_memory.v，实际缺模块RED；实现rtl/soc/triha_soc_memory.v、triha_sram.v、triha_boot_rom.v和triha_uart_tx.v。ModelSim验证协议、独立内存oracle及负例。
- [ ] 添加rtl/soc/triha_minimal_soc.v，连接稳定CPU，写正式地址固件/ROM镜像工具与集成TB，运行runtime及CoreMark，记录周期/CRC/WB观察。
- [ ] 添加显式cpu_minimal_soc目标和相应100MHz FDC，重用现有报告解析器，完整PDS后布线，核验两corner六项和哈希。
- [ ] 更新STATUS/证据与已知限制，小批提交，不自动合并或烧板。

主要命令：python scripts/soc/gen_config.py --check；python scripts/soc/run.py --test memory；python scripts/soc/run.py --test runtime；python scripts/soc/run.py --test coremark；pwsh -NoProfile -File scripts/soc/run_route.ps1。所有运行独立build/soc目录，失败非零。
