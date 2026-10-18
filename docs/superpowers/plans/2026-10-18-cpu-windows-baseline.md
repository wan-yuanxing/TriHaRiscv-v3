# Windows Verilog CPU Baseline Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task in this session. Preserve other routes' files. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 在已授权工作树内建立可复现的固定 TriHa CPU + ModelSim Windows 冒烟与负例基线。

**Architecture:** 固定上游源码保持原样，旧风格 Verilog wrapper 只绑定参数/复位/接口。ModelSim 跑上游真实 ELF 和独立失败程序，PowerShell 验证退出与软件输出，并保存哈希证据。

**Tech Stack:** Windows、PowerShell/.NET、ModelSim2020.4、Verilog-2001。复用已有 ELF；根据用户后续确认补充Windows GCC15.2和CoreMark1.0源码准备，不增加其他工具环境，不启动PDS。

---

### Task 1: 固定来源与维护方式

**Files:** `AGENTS.md`、`docs/cpu/README.md`、设计文件、`rtl/cpu/vendor/UPSTREAM.json` 及其显式文件。

- [x] 建立 `cpu/windows-baseline` 工作树；只带入本轮 CPU 约定，不带入 Video/技术报告未提交修改。
- [x] 运行 ModelSim启动和 `python scripts/video/gen_config.py --check`，记录返回0。
- [x] 按旧来源清单逐文件复制并在前后重算SHA256；不复制旧 SoC、脚本环境或生成结果。
- [x] 维护入口记录新代码风格、已创建工作树和本批范围；保存设计/计划提交。

来源核对命令：

```powershell
$upstream = Get-Content rtl/cpu/vendor/UPSTREAM.json -Raw | ConvertFrom-Json
foreach ($entry in $upstream.files.PSObject.Properties) {
    $actual = (Get-FileHash (Join-Path 'rtl/cpu/vendor' $entry.Name) -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $entry.Value) { throw "Upstream hash mismatch: $($entry.Name)" }
}
```

### Task 2: 先建立测试，再加入封装

**Files:** `tb/cpu/tb_triha_core.v`、`config/cpu_sources.f`、`scripts/cpu/run_modelsim.do`、`scripts/cpu/run.ps1`、`rtl/cpu/triha_core.v`。

- [x] 写自校验Verilog测试平台和显式filelist；测试平台通过产品名`triha_core`连接，复用来源TCM模块。
- [x] PowerShell入口验证来源、读取ELF PT_LOAD、每次新建运行目录，以60秒编译/仿真上限启动已装工具；解析完成标记/真实退出码，finally写本次result.json。
- [x] 在封装不存在时执行下述命令，确认因缺少`triha_core`编译失败且result.json为FAIL；该检查只证明集成缺项，后续负例才证明行为判定。
- [x] 添加设计中定义的窄封装，锁定EXTRA_DECODE_STAGE=0、SUPER/MMU/Xilinx=0、M/旁路/基础预测=1，默认单发射，不新增时序级。
- [x] 重跑单发射与双发射，要求程序退出0、十项上游软件检查输出齐全、模式/配对计数检查通过。

```powershell
pwsh -NoProfile -File scripts/cpu/run.ps1 -Case single
pwsh -NoProfile -File scripts/cpu/run.ps1 -Case dual
```

预期：封装前第一次返回非零；封装后两项返回0并各有`CPU_SMOKE_PASS`、真实`CPU_PROGRAM_EXIT code=0`。`.do`只负责工具执行：

```tcl
onerror {quit -f -code 2}
onbreak {quit -f -code 3}
run -all
quit -f -code 0
```

### Task 3: 验证失败判定，保存本批证据

**Files:** 同一测试平台/入口、`docs/verification/cpu/windows_baseline.json`、`docs/cpu/STATUS.md`。

- [x] `-Case fail`让CPU实际执行以下RV32I/Zicsr序列；要求观察真实code1、无PASS标记、入口返回非零。

```verilog
// addi a0,zero,1; csrw 0x8b2,a0; jal zero,0
write_word(32'd0, 32'h00100513);
write_word(32'd4, 32'h8b251073);
write_word(32'd8, 32'h0000006f);
```

- [x] `-Case timeout`设MAX_CYCLES=8；要求TB输出timeout、宿主返回非零、本次result为FAIL。
- [x] 汇总只把两个正例通过、两个预期失败被实际拒绝记作本批PASS；记录负例非零退出，不将其伪装为普通通过。
- [x] 核对来源仍字节相同、输出哈希/日志存在、`git diff --check`通过；STATUS明确完整ISA、退休等价、CoreMark、SoC、资源、PDS/100MHz及板测仍未完成；GCC按Task4单独记录。
- [x] 只提交本批源码/测试/脚本/文档，不合并Video分支，不提交build产物。

```powershell
pwsh -NoProfile -File scripts/cpu/run.ps1 -Case all
git diff --check
```

预期：all返回0；汇总中single/dual为PASS，fail/timeout为FAIL且已被判定器拒绝；无新的CoreMark或物理频率结论。

### Task 4: 按用户后续确认准备RV32软件环境

**Files:** `config/cpu_toolchain.json`、`scripts/cpu/check_toolchain.ps1`、`sw/benchmarks/coremark/`。

- [x] 用户确认GCC未安装并接受发行包实际前缀，以RV32/ILP32编译能力为准。
- [x] Windows预编译归档下载、SHA256核验并解压到独立工具目录；不改系统PATH、不安装环境管理器。
- [x] 执行 `pwsh -NoProfile -File scripts/cpu/check_toolchain.ps1`，真实编译/链接RV32I和RV32IM_Zicsr两配置；核对ELF32、RISC-V、入口和属性，保存日志/哈希。
- [x] 固定CoreMark v1.0实际版本标记，记录源码补丁标签v1.01和commit、8文件Git blob/SHA256及许可证；不宣称运行时移植或CoreMark测量通过。
