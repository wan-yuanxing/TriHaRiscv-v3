# CPU板级100MHz验收

2026-10-20：PG2L100H/FBG676/-6的板级PLL/管脚边界已通过真实后布线100MHz，并生成下载包。六级单发射、RV32IM/CSR、BTB32/BHT512/RAS8、GShare关闭、无I/D Cache；8KiB ROM、32KiB SRAM、UART TX和原地址保持。尚未Program/Verify或现场板测。

## 实际物理结果

冻结运行`build/soc/board-route-20261019T1825066711298Z`；100MHz、IO max2/min0.5ns、setup/hold uncertainty配置0.1/0.05ns，实际PLL总setup uncertainty0.250ns，无false path/MCP。125MHz差分参考，PLL I1/M1/F8/O10得到精确100MHz，实际PRR管脚及电气标准已逐项核对。

| 检查 | Slow/ns | Fast/ns |
|---|---:|---:|
| Setup | +0.023 | +1.752 |
| Hold | +0.155 | +0.100 |
| Minimum pulse width | +3.655 | +4.202 |
| Recovery | +2.056 | +4.164 |
| Removal | +0.739 | +0.499 |

全部零违例，Design All Constraints Met，performance slack +0.023ns与最差setup一致；最差路径SRAM块RAM→CPU执行结果。只验收100MHz，不由此宣称更高主频。compile/synthesize/dev_map/pnr/report_timing/gen_bit_stream均有新成功标记，宿主与三个原生调用全部返回0、source_unchanged。独立复核46项输入、328项输出、模型/工具、固件和实际报告绑定，见[物理复核](board_parallel_forward_route.json)及[交付索引](board_system_acceptance.json)。

CPU-only综合层次：5977LUT、5172FF、64分布式RAM、0DRM、4APM；不包含ROM/SRAM、PLL、复位、UART、LED及板级逻辑。不以不同运行的层次归属变化推断状态减少。

## 数字与性能证据

旁路优先级改为并行标签比较、独占选择及case传递数据，状态和周期不变。独立顺序oracle24448项覆盖所有六路命中组合、两个取指槽、x0及X/Z；原版通过，坏输出拒绝。三seed单/双模式WB/store/异常对照、IRQ/mret、完整预测器状态/输出/训练、真实PLL模型111项、整核两次启动及真实单字节损坏拒绝通过。[15项运行索引](board_parallel_forward_validation.json)核验vendor28文件、11项派生和5个安装模型。

GCC15.2/RV32IM_Zicsr/ILP32/O3、无LTO，CoreMark v1.0、2000字节、5次迭代：1685831周期、1467843次WB完成观察、观察IPC0.870694、短估算2.965896 CoreMark/MHz，CRC e9f5/e714/1fd7/8e3a、final f24c。RTL短测，非官方分数或板测；WB观察不能替代完整minstret证明。

FIFO复制未改善全局STA，已退出默认recipe；诊断标签和原始结果保留。首次旁路版STA通过但位流命令被PowerShell数组拆行，原FAIL未改写：[冻结失败核验](board_parallel_forward_bitstream_failure.json)。生产表达式回归真实先RED后GREEN，5项发布检查通过后重新完成整个PDS流程。原外供100MHz系统5c4229a/cpu-soc-100mhz-sta-20261019的385项输出哈希仍相同。

## 下载包与现场边界

[下载包说明](../../../build/soc/releases/cpu_board_5f5eb8c89efd/README.md)，10项文件哈希已核对，含位流/校验掩码、ELF/map、ROM/SRAM镜像、实际报告和review/manifest。位流SHA256：`5f5eb8c89efd95e57f97bfb5b07fda514ad7948bf8d7160335ec24c2cd17df9d`；掩码SHA256：`7b5a71319c9d4e2b8cf1e46bcf76137d98f6b4ac33ddbdc5d517b44616891a65`。源码备份标签`cpu-board-100mhz-sta-20261020`，CPU工作树保留，不自动合入或push。

N3/N2差分参考、C22低有效KEY0、C24 UART115200/8N1；LED按信号电平说明，不假定亮灯极性。固件拥有的8KiB自检通过后输出PASS和持续ALIVE，KEY0重新执行；这只是已验证的预期行为，尚无实际串口捕获，不称32KiB全地址板测。

下载将临时替换当前独立Video配置。待用户确认后，先核对最新Video恢复包和板卡身份，再volatile Program/Verify及UART/KEY0现场验收，结束后恢复确认过的Video包；不写Flash。当前Video和主工程技术报告未改动。
