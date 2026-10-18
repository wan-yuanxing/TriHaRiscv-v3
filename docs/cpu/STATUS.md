# TriHa CPU 状态

更新：2026-10-18。分支 `cpu/windows-baseline`，工作树 `D:/FPGA/TriHaRiscv-cpu-windows`。

## 本批交付

- 固定来源28文件导入，逐项SHA256匹配；许可证和来源清单位于 `rtl/cpu/vendor/`。
- `rtl/cpu/triha_core.v` 按旧风格封装六级CPU，默认单发射；复位极性、命名与完整总线握手绑定，不增加额外流水。
- Windows ModelSim2020.4 已完成编译/展开/实际执行。PowerShell入口按真实程序退出码、软件输出和发射配置判定，保存每轮哈希与日志。
- 显式filelist没有编译Xilinx原语文件或追踪模块；这不等于Pango综合资源已经验证。
- 已按用户确认的RV32/ILP32要求安装Windows GCC15.2.0预编译包，SHA256匹配发布元数据。`check_toolchain.ps1`实际完成RV32I/ILP32和RV32IM_Zicsr/ILP32编译、链接及ELF32检查；探针软件未执行。
- CoreMark基准版本1.0的8个固定源码/许可文件已导入；源码补丁标签v1.01，Git blob与SHA256均已核对，运行时移植尚未实施。

## 本机实际仿真

| 测试 | 结果 | 观察 |
|---|---|---|
| 单发射 | PASS | 程序退出0；3315周期、2151次issued、0配对 |
| 双发射 | PASS | 程序退出0；3118周期、2151次issued、274配对周期 |
| 实际失败程序 | 正确拒绝 | CPU通过CSR返回1；单独宿主入口返回1 |
| 周期超时 | 正确拒绝 | MAX_CYCLES=8，实际第9周期终止；单独宿主入口返回1 |

两个正例均有十项软件检查输出，包含乘除法、移位、比较、字/字节访问。观察范围仅是固定程序和指定配对检查；issued不是instret，不计算退休IPC，不作为CoreMark。四项运行输入在本次运行前后未变。

证据索引：`docs/verification/cpu/windows_baseline.json`。首个RED记录保留于build：封装缺失时vlog实际返回2。首次加入封装后程序完成，但`-onfinish stop`触发onbreak返回3；改为`-onfinish exit`后正常结束由宿主核对程序状态。负例证明宿主不会因模拟器返回0就接受失败程序。

## 仍需完成

- 性能基准按用户截图固定CoreMark v1.0，尚未建立其本机运行时移植、完整编译或测量结果。
- 正式RV32I/ACT4、CSR/异常/IRQ、背压与访存错误、flush/取消及退休观测。
- CPU-only原生综合、真实RAM/APM映射和最终100MHz Slow/Fast setup/hold/脉宽。
- 新主工程地址/外设、DDR/AXI、NPU/Video集成和板级运行。

主工程Video及技术报告未提交修改保持原位；本批尚未合入该分支，未启动PDS或编程板卡。
