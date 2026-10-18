# CPU Single Execution Specialization Plan

> Execute inline in the current CPU worktree with systematic-debugging, test-driven-development and verification-before-completion. No subagents.

**Goal:** 安全移除单发射第二执行单元，验证行为和实际资源。

**Architecture:** 固定父版作并行对照，派生Verilog连接仅加入条件生成；保留共享CSR/异常控制，不引入新工具。

**Tech Stack:** Windows、ModelSim、PowerShell7、RISC-V GCC、PDS。

- [x] 建立`tb/cpu/tb_cpu_equivalence.v`及`scripts/cpu/run_equivalence.ps1`，候选缺失时编译非零失败。
- [x] 增加`sw/tests/control_stress.S`，覆盖branch/jump、算术/访存依赖、异常返回与IRQ；TB增加确定性背压和错误注入。
- [x] 增加`rtl/cpu/triha_cpu.v`和适配记录，更新生产封装及显式仿真/PDS清单；原件字节不变。
- [x] 单/双模式对照通过，单发射不活动路径断言通过，双发射错误写回负例应失败。
- [x] `run_firmware.ps1 -Program coremark -Mode both -Iterations 5`通过且与父版等周期/完成数/CRC；startup/retire/原冒烟回归通过。
- [x] PDS单/双CPU-only综合/映射通过，核对真实模块存在性、参数、原语与面积。
- [x] 记录`docs/verification/cpu/single_exec_trim.json`和STATUS，检查哈希/许可/差异，独立提交。
