# CPU 单元级仿真支撑材料

本目录对应技术文档 B.2 的五类单元验证。

| 单元 | 正例结果 | 负例结果 |
|---|---|---|
| 乘法器 | 2730 次有效结果检查，904 个 hold 周期 | MUL_PAYLOAD_FAIL |
| 除法器 | 308 次算术操作、312 次完成检查、16 次快速完成 | DIV_ARITH_FAIL |
| CSR | 21 次访问、91 项检查、两次异常和一次返回 | CSR_UNIT_FAIL |
| ALU | 17804 次结果检查、384 组移位扫描 | ALU_UNIT_FAIL |
| 寄存器堆 | 2476 次读值检查、1006 次有效写入、两次复位、六次全地址扫描 | REGFILE_FAIL |

`cpu-unit-support-2026-10-29.zip` 为乘法器、除法器和 CSR 的冻结支撑包；`run-index.json` 为其运行登记。
`cpu-datapath-support-2026-10-29.zip` 为 ALU、寄存器堆增量包；`datapath-run-index.json` 为其运行登记。
各包的 `source/` 保存测试台与依赖源码，`runs/` 保存实际结果、编译和仿真日志、WLF/VCD、显示脚本，`figures/` 保存未重绘的 ModelSim 窗口原图。各登记文件记录实际命令、SHA-256 和截图时间窗口。

CPU 工程根目录执行：

```powershell
pwsh -NoProfile -File scripts/cpu/capture_unit_waveforms.ps1 -Test mularith
pwsh -NoProfile -File scripts/cpu/capture_unit_waveforms.ps1 -Test divarith
pwsh -NoProfile -File scripts/cpu/capture_unit_waveforms.ps1 -Test csr
pwsh -NoProfile -File scripts/cpu/capture_unit_waveforms.ps1 -Test alu
pwsh -NoProfile -File scripts/cpu/capture_unit_waveforms.ps1 -Test regfile
```

追加 `-Broken` 执行负例。正例脚本返回 0；负例脚本返回 1，实际错误见 `simulation.stdout.log`。原生 ModelSim 的 `$fatal` 可返回 0，脚本同时核对失败文本与成功标志。

查看 WLF 使用独立日志，例如 `vsim -l viewer.log -view alu.wlf -do report-view-final.do`。第一批三个正例目录的默认 `transcript` 被 GUI 会话复用，因此该包以未变的 `simulation.stdout.log` 为仿真日志证据，未打包默认 `transcript`；其余登记输出与原始波形均已核验。第二批将批处理和查看日志分开，所有登记输入、原语模型及输出哈希均匹配。

寄存器堆仿真使用本机已安装 Pango 原语模型，模型绝对路径和哈希见增量登记，不分发厂商工具源文件。ALU 只验证组合单元接口；整核发射/旁路、Cache 交互和系统异常流程见后续模块级与系统级批次。
