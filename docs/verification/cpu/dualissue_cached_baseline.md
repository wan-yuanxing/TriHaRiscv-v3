# 六级双发射：带 Cache 的功能基线

2026-10-23，分支 `cpu/dualissue-windows`，基于 `340bcc2`。
实现和全部新运行均位于 `D:/FPGA/TriHaRiscv-cpu-dualissue-windows`。
本批完成模拟功能基线；双发射资源、实际后布线 100MHz 和板测均未验收。
机器可读绑定见 [JSON](dualissue_cached_baseline.json)。

## 实现范围

`triha_cached_core` 新增默认值为零的 `DUAL_ISSUE` 参数，转交现有 CPU。
复用既有配对规则、两个整数执行通道及共享 LSU/乘除法资源，没有新增主流水级。
保持 RV32IM/CSR、BTB512/BHT512/RAS4、GShare 关闭，以及 I/D 各 16KiB、
两路、32B 行；私有 DDR 使用写回/写分配，共享 DDR 不缓存。

测试入口新增 `--issue-mode single|dual`，默认单发射，实际检查内部参数，
观察真实成对接受和第二路写回，并按 lane0、lane1 顺序记录两路完整 WB。
组件测试拒绝双发射参数。原件及许可未修改。默认生产路径仍为单发射。

## 同程序比较

Windows 原生 GCC15.2.0，`-O2`，无 LTO，CoreMark1.0 的五次短迭代。
两模式使用相同加载镜像和相同 AXI128 数字内存模型；确定 ready，写等待 30 周期，
32B refill。该模型不是实际 DDR 延迟测量。时钟标称值用于计算每 MHz 指标，
不代表双发射 CPU 已在 100MHz 工作。

| 指标 | 单发射 | 双发射 |
|---|---:|---:|
| 计时周期 | 2,014,969 | 1,781,952 |
| 计时 WB 观测事件 | 1,448,448 | 1,448,448 |
| WB 观测 IPC | 0.718844 | 0.812843 |
| 短测 CoreMark/MHz | 2.481428 | 2.805912 |
| 计时 CPU store | 70,839 | 70,839 |
| 全运行成对发射次数 | 0 | 311,626 |
| 全运行第二路 WB 次数 | 0 | 311,626 |

节省 233,017 周期，周期减少 **11.564297%**，相同频率下吞吐提升
**13.076503%**。WB 观测包含完整计时指令流，但不是硬件 `minstret` 或完整
架构退休证明。全运行配对计数还包含启动和打印，不能直接拿来除以计时周期。

两个 ELF 的完整文件不同，仅非加载 `.strtab` 的临时对象文件名字符串不同；两个
`PT_LOAD` 段和 `firmware.hex` 均相同。加载镜像 SHA256：
`f4709ec564c8c3a01555d1651f43f30020f0e471676214fc2b28b45999e6adb2`。

完整对照 1,448,448 条 WB 和 70,839 条 store：仅首条 cycle CSR 返回值，
及首条保存该绝对起始时间的 store 不同，其余逐行相同。比较脚本独立检查
首条确实是 cycle CSR，并通过 ELF 符号确认对应 `started` 地址，未忽略其他差异。
两模式标准 CRC 为 `e9f5/e714/1fd7/8e3a`，五次最终 CRC 均为 `f24c`，
软件 `errors=0 short=1`。保留原 CoreMark 的短于十秒警告；这是 RTL 仿真，
不能称为官方分数或板级跑分。

同一 ELF 的 TCM 对照也通过：单/双分别 1,646,469 / 1,411,226 周期，
WB 观测 IPC 为 0.879730 / 1.026376，短测 CoreMark/MHz 为
3.036802 / 3.543019，吞吐提升 16.669407%。不同内存边界的成绩分别报告。

## 写回覆盖失败的诊断及修正

旧测试台要求每个程序都出现下层写事务。两个首次 CoreMark5 运行虽然软件
`errors=0`，仍在该断言失败，原结果保持 FAIL。
补充诊断的一次迭代实际观察到 I 读 391、D 读 134、计时 store 14,175、
Cache 数据 RAM 更新 16,628、下层写 0、协议错误 0，再次触发原断言。
写回 Cache 的工作集驻留且无脏行逐出时，下层写为零是允许的行为。

修正后共同要求实际取指/数据读及 CPU store；Cache 开启时还要求实际数据 RAM
写使能出现，不能把 refill 计成 CPU store。仅带 Cache 的 CoreMark 允许零下层写。
定向维护/异常程序以及旁路模式继续要求完成下层写事务：本轮两种发射模式的
定向程序各完成 33 次，旁路各完成 9 次。组件写回测试也通过。
CoreMark5 两模式各有 73,294 次全运行 Cache store 更新，协议错误为零。

## 验证和证据

- 单/双发射冒烟、预期失败程序及超时负例组成的原生套件通过。
- 实际 runtime、14 指令 WB 探针，以及同 ELF TCM CoreMark 单/双模式通过。
- 新参数解析四项测试先 RED 后 GREEN；缓存封装未转交参数时真实 elaboration RED 已保留。
- 最新缓存定向单/双、旁路单/双、组件 writeback 和 CoreMark5 单/双均通过。
- 真实 CRC 破坏使软件 `errors=1`，宿主退出 1；数据破坏使程序不能完成，
  在周期 100001 被 transport watchdog 拒绝，不能描述为直接数据比较报错。
- 74 项 Python 回归、`python -O` 下四项参数测试、缓存原件/派生文件预检及
  `git diff --check` 通过。独立只读评审核对了源码、完整轨迹、加载段及冻结哈希。

主要原始结果：

| 用途 | `build/cpu/` 下目录 |
|---|---|
| 单发射 CoreMark5 | `cache-coremark-20261023T112219934835Z` |
| 双发射 CoreMark5 | `cache-coremark-20261023T112230076790Z` |
| CRC 负例 | `cache-coremark-20261023T112240295186Z` |
| 数据破坏负例 | `cache-cpu-20261023T112737111528Z` |
| 旧写覆盖诊断 RED | `cache-coremark-20261023T112111609276Z` |
| 未接通双发射参数 RED | `cache-cpu-20261023T111250672161Z` |
| 同 ELF TCM CoreMark | `firmware-coremark-20261023T1103533439788Z` |

每次原生运行的 `result.json` 绑定输入、工具和输出 SHA256。缓存运行有 `src/`
冻结输入副本，已逐项复核；旧 TCM/runtime/WB 探针入口没有输入副本，已复核
其当前工作树输入与记录相同以及全部输出摘要，JSON 单独注明此区别。
日志、完整轨迹和失败运行留在忽略的 `build/` 中。

重现入口：

```powershell
python scripts/cpu/run_cache.py --test cpu --issue-mode dual
python scripts/cpu/run_cache.py --test coremark --issue-mode single --iterations 5
python scripts/cpu/run_cache.py --test coremark --issue-mode dual --iterations 5
python scripts/cpu/run_cache.py --test coremark --issue-mode dual --iterations 1 --fault crc
python scripts/cpu/check_cache.py
python -m unittest discover -s scripts/cpu -p 'test_*.py'
```

## 下一门槛

待正在进行的 SoC PDS 工作释放工具后，复用 `run_pds.ps1 -Mode both -Stage map`
测量相同原生边界下的 CPU-only 资源，检查双发射四读两写 FF 寄存器堆的实际成本。
随后依据结果评估复用成熟的复制 RAM bank/最新写入选择结构，先做状态模型与
RAW/WAW/同址写/复位测试，再实施。I/D Cache、共享 LSU 和外部接口保持现有边界。
性能取舍同时看 CoreMark、CPU-only 面积及最终 100MHz 多 corner 时序。

本批未启动 PDS、未访问板卡或串口，也未改动/合并主工程及集成工作树。
双发射 CPU-only 资源和 CoreMark/LUT 当前为 UNKNOWN。100MHz 准入仍须实际
后布线 setup、hold、Slow/Fast 脉宽全部通过，不能继承单发射旧报告。
