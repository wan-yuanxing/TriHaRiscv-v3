# TriHa Startup and CoreMark Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans in this session, with test-driven-development and verification-before-completion. Continue in the existing isolated worktree.

**Goal:** 跑通Windows GCC生成的软件，并取得可复现的CoreMark1.0单/双发射短RTL测量。

**Architecture:** 测试TCM运行时、标准基准平台适配、同一DUT测试平台的仿真计数。产品RTL与固定算法源保持不变。

**Tech Stack:** Windows、PowerShell7、GCC15.2、ModelSim2020.4、Verilog2001、RV32IM_Zicsr/ILP32。

## Task 1: 测试与边界

- [x] 创建runtime data/BSS/算术自检和14指令汇编探针。
- [x] 在启动文件缺失时运行编译，确认非零失败。
- [x] 添加 `sw/runtime/crt0.S`、`triha_tcm.ld`、`triha_runtime.h/.c`，实现gp/sp、BSS、mtvec、字符和退出。
- [x] 添加计数/CSR窗口观察，运行runtime、retire两模式；错误期望和非法指令必须失败。

14指令的计数依据：初始化1 + 循环3×3 + store1 + load1 + 减法1 + 检查分支1 = 14。计数不依赖寄存器写使能，必须覆盖store/branch。

## Task 2: 基准构建与标准CRC

- [x] 创建 `sw/benchmarks/coremark/port/core_portme.h/.c`，使用真实cycle CSR、原始短测时长检查和标准volatile种子。
- [x] 将固定格式化源码的UART占位替换为运行时回调、加入错误消息钩子；HAS_FLOAT按值判断。算法源不改写。
- [x] 创建 `scripts/cpu/firmware_common.ps1` 和 `run_firmware.ps1`，原生进程有上限、独立运行目录、完整输入输出哈希。
- [x] 在移植文件缺失时运行CoreMark编译确认失败，再添加移植实现。
- [x] 使用同一ELF运行performance两模式；核对0xe9f5、0xe714/0x1fd7/0x8e3a；周期数与CSR窗口必须相同。
- [x] validation单模式核对0x18f2、0xe3c1/0x0747/0x8d84。
- [x] build副本中翻转一个预期CRC，确认错误输出及非零退出被拒绝。

执行入口：

```powershell
pwsh -NoProfile -File scripts/cpu/run_firmware.ps1 -Program runtime -Mode both
pwsh -NoProfile -File scripts/cpu/run_firmware.ps1 -Program retire -Mode both
pwsh -NoProfile -File scripts/cpu/run_firmware.ps1 -Program coremark -Mode both -Iterations 5
pwsh -NoProfile -File scripts/cpu/run_firmware.ps1 -Program coremark -Mode single -RunKind validation -Iterations 1
```

## Task 3: 回归与提交

- [x] 修改后的共同TB运行原 `run.ps1 -Case all`，防止破坏首批冒烟/失败处理。
- [x] 核对原始来源与benchmark文件仍匹配清单、Git保留原字节。
- [x] 保存 `docs/verification/cpu/coremark.json`、更新CPU STATUS/README，记录CoreMark/MHz、观察IPC、相同ELF、TCM与短测限制。
- [x] `git diff --check`与实际日志一致后只提交本批CPU文件，不合入Video或运行PDS。
