# TriHa CPU 状态

更新：2026-10-18。分支 `cpu/windows-baseline`，工作树 `D:/FPGA/TriHaRiscv-cpu-windows`。

## 本批交付

- 固定来源28文件导入，逐项SHA256匹配；许可证和来源清单位于 `rtl/cpu/vendor/`。
- `rtl/cpu/triha_core.v` 按旧风格封装六级CPU，默认单发射；复位极性、命名与完整总线握手绑定，不增加额外流水。
- Windows ModelSim2020.4 已完成编译/展开/实际执行。PowerShell入口按真实程序退出码、软件输出和发射配置判定，保存每轮哈希与日志。
- 显式filelist没有编译Xilinx原语文件或追踪模块；这不等于Pango综合资源已经验证。
- 已按用户确认的RV32/ILP32要求安装Windows GCC15.2.0预编译包，SHA256匹配发布元数据。`check_toolchain.ps1`实际完成RV32I/ILP32和RV32IM_Zicsr/ILP32编译、链接及ELF32检查；探针软件未执行。
- CoreMark基准版本1.0的9个固定源码/许可文件已导入；源码补丁标签v1.01，Git blob与SHA256逐项核对。原始算法不变，平台移植与构建生成的formatter适配独立维护。
- 本机GCC实际生成并运行裸机软件，启动建立gp/sp、mtvec、关闭中断、清零BSS；ELF加载器先将TCM填0xa5再复制文件段，data/BSS自检在两模式通过。当前data由测试加载器直接装入VMA，不是ROM搬运启动。
- 已跑通CoreMark performance单/双模式和validation单模式；计时用真实cycle CSR，周期与仿真观察窗口一致，标准CRC全部匹配。

## 本机实际仿真

| 测试 | 结果 | 观察 |
|---|---|---|
| 单发射 | PASS | 程序退出0；3315周期、2151次issued、0配对 |
| 双发射 | PASS | 程序退出0；3118周期、2151次issued、274配对周期 |
| 实际失败程序 | 正确拒绝 | CPU通过CSR返回1；单独宿主入口返回1 |
| 周期超时 | 正确拒绝 | MAX_CYCLES=8，实际第9周期终止；单独宿主入口返回1 |

两个正例均有十项软件检查输出，包含乘除法、移位、比较、字/字节访问。观察范围仅是固定程序和指定配对检查；issued不是instret，不计算退休IPC，不作为CoreMark。四项运行输入在本次运行前后未变。

证据索引：`docs/verification/cpu/windows_baseline.json`。首个RED记录保留于build：封装缺失时vlog实际返回2。首次加入封装后程序完成，但`-onfinish stop`触发onbreak返回3；改为`-onfinish exit`后正常结束由宿主核对程序状态。负例证明宿主不会因模拟器返回0就接受失败程序。

## GCC固件与CoreMark短测

同一ELF、RV32IM_Zicsr/ILP32、GCC15.2.0、-O3、无LTO、2000字节总数据、5次迭代；使用128KiB测试TCM。完整编译参数、源/生成文件/ELF/日志哈希见`docs/verification/cpu/coremark.json`索引中的实际result.json。

| 模式 | 测量周期 | WB完成事件 | 观察IPC | CoreMark/MHz短测估算 |
|---|---:|---:|---:|---:|
| 六级单发射 | 1,659,900 | 1,467,843 | 0.884296 | 3.012230 |
| 六级双发射 | 1,380,497 | 1,467,843 | 1.063271 | 3.621884 |

双发射相对单发射周期减少16.832520%，相同模拟频率下吞吐提高20.239305%。两模式标准CRC均为seed e9f5、list e714、matrix 1fd7、state 8e3a。validation单模式1次迭代为333,416周期，CRC为18f2/e3c1/0747/8d84。

上述是RTL仿真，不是板级结果。5次短测保留“至少10秒”的原始警告，因此不能作为官方CoreMark分数。TCM时钟设置100MHz不等于Pango后布线100MHz已通过，也不能与旧工程不同编译器/存储/ISA配置的结果直接作性能结论。

IPC按两次cycle CSR读入边沿之间的WB完成事件/周期计算，不用issued替代。14条指令探针在两模式精确通过，包含循环、branch、store、load，双发射轨迹包含第二条完成通道；它只验证该计数器的定向范围。现核没有架构minstret实现，完整ISA、异常、取消和退休语义仍待证明。

新增负例均被宿主返回1正确拒绝：期望15而实际14的计数错误、非法指令（真实mtvec输出cause=2/value=ffffffff）、build副本中预期list CRC e714→e715（基准errors=1且程序退出1）。原始CoreMark文件保持不变。共同TB修改后的原始四项冒烟也已回归通过，产品CPU RTL未在本批改变。

## 仍需完成

- 正式RV32I/ACT4、CSR/异常/IRQ、背压与访存错误、flush/取消及退休观测。
- CPU-only原生综合、真实RAM/APM映射和最终100MHz Slow/Fast setup/hold/脉宽。
- 新主工程地址/外设、DDR/AXI、NPU/Video集成和板级运行。

主工程Video及技术报告未提交修改保持原位；本批尚未合入该分支，未启动PDS或编程板卡。
