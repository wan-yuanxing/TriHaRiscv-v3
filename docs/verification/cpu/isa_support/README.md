# CPU 指令集回归支撑材料

2026-10-29 完成当前六级单发射 RV32IM/CSR 核实际 RTL 仿真。BTB/BHT 各512项、RAS4项、GShare关闭。

| 测试集 | 分项 | 实际结果 |
| --- | --- | --- |
| riscv-tests | RV32I40、M8、机器CSR2 | **50/50 PASS** |
| ACT4 | I39、M8、Zicsr6 | **53/53 PASS** |

两套分别统计，103项的原生仿真均返回0、官方成功标志有效、无超时；运行期间源码及输入哈希未变。不沿用旧五级CPU的134/134或165/165。

文件组织：
- riscv-tests/、act4/：逐项原始ModelSim日志，以用例名命名。
- riscv-tests-cases.csv、act4-cases.csv：指令集验证逐项结果。
- cases.json：结果、实际周期及日志/ELF哈希。
- regression-2026-10-29.json：配置、版本、来源和提交包哈希。
- cpu-isa-support-2026-10-29.zip：冻结源码/脚本、官方ELF、实际镜像、反汇编、Sail签名及生成配置、原始日志、失败历史和哈希清单。

ACT4固定提交375292312d3d02b7468272eb550d81cb74be53d8。经用户授权，一次性复用已安装WSL GCC15.2/Sail0.12生成53个无C自检查ELF；YAML和Sail配置均关闭C/Zca。DUT执行始终为Windows ModelSim2020.4。256KiB RAM仅用于仿真，不定义SoC地址图或DDR性能。

回归先发现EPC低位未屏蔽，维护层现将读回、写回及xRET的低两位清零，第三方原件未变。原始红测与中间参考配置错误的记录均保留。原CPU文件备份为D:/FPGA/TriHaRiscv-cpu-windows/build/cpu/csr-alignment-backup-20261029/；最终结果仅引用isa-20261029T055835157465Z。

这是功能仿真结果。CSR修正版未重跑CoreMark、PDS时序或板测；正文的既有性能、时序及截图仍绑定其原冻结版本。完整机器特权、RV64/C/B扩展不包含在本次范围。
