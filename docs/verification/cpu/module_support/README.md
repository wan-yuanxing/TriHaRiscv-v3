# CPU 模块级仿真支撑材料

本目录对应技术文档 B.3 的前端重定向、发射/旁路、LSU及I/D Cache模块验证。

| 模块 | 正例结果 | 负例结果 |
|---|---|---|
| 前端重定向 | 4 次重定向、12 项交付、4 项迟到响应丢弃 | 未注册重定向版本触发 FRONTEND_FAIL |
| 发射/旁路 | 16 次发射、16 次退休、26 项操作数检查、38 周期 | 错误加载返回触发 ISSUE_FLOW_FAIL |
| LSU端口 | 18次访问，220/220项检查 | 错误返回数据触发 LSU_UNIT_FAIL |
| I/D Cache组合 | 1297/1297项检查，35个I/D同时在途周期 | 错误返回数据触发 CPU_CACHE_FAIL |
| 数据Cache写回 | 1355/1355项检查，35次下层读、184次下层写 | 错误返回数据触发 CPU_DCACHE_WB_FAIL |
| 数据Cache响应重叠 | 142/142项检查，12次连续读取的接纳间隔为2周期 | 错误返回数据触发 CPU_DCACHE_OVERLAP_FAIL |

`module-run-index.json` 记录两组正例、两组负例的工具命令、源码/原语模型/输出 SHA-256 和截图时间窗口。`cpu-module-support-2026-10-29.zip` 包含实际 WLF/VCD、日志、显示脚本、测试台和依赖源码。

`memory-run-index.json`及`cpu-memory-support-2026-10-29.zip`补充LSU和Cache的四组正例、四组负例。包含实际WLF/VCD、日志、测试台、依赖源码及四张2553×1440原生ModelSim截图，截图保留原始字节，无鼠标指针，未裁剪或重绘。`memory-run-index.json`登记命令、输入输出SHA-256、截图时间范围及检查统计；本批3014/3014项正例检查通过。

运行入口（CPU 工程根目录，Windows PowerShell）：

```powershell
pwsh -NoProfile -File scripts/cpu/capture_unit_waveforms.ps1 -Test frontend
pwsh -NoProfile -File scripts/cpu/capture_unit_waveforms.ps1 -Test issueflow
pwsh -NoProfile -File scripts/cpu/capture_unit_waveforms.ps1 -Test lsufunctional
pwsh -NoProfile -File scripts/cpu/capture_cache_waveforms.ps1 -Test components
pwsh -NoProfile -File scripts/cpu/capture_cache_waveforms.ps1 -Test writeback
pwsh -NoProfile -File scripts/cpu/capture_cache_waveforms.ps1 -Test overlap
```

追加 `-Broken` 执行错误注入负例。正例返回 0，负例返回 1；判定同时检查 PASS/FAIL 标志和仿真日志，不能只看 ModelSim 退出码。

前端波形窗口为 0--300 ns，发射波形窗口为 140--340 ns。截图来自原生 ModelSim WLF 窗口，未重绘。

LSU窗口为1000--1500 ns，指令Cache为2580--3260 ns，数据Cache写回为2920--4140 ns，响应重叠为3690--3970 ns。各测试独立连接所测模块；I/D组合测试的两个下层端口由内存模型分别服务，不验证共享总线仲裁、物理DDR控制器或整机缓存一致性。B.4整核系统级验证另行登记。
