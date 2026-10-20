# 板上 CoreMark 串口接收

2026-10-20已部署`build/soc/releases/cpu_coremark_3f69fa00663b`，实际PG2L100H扫描ID00602899，Program/Verify原生返回0。新固件重新完整100MHz后布线通过：Slow/Fast setup +0.023/+1.752ns、hold +0.155/+0.100ns、MPW +3.655/+4.202ns，恢复/移除检查也通过。下载未打开串口，未写Flash；完整实物跑分日志仍待用户接收，不能把预检短测填成板级成绩。配套索引为`board_coremark.json`。

串口助手使用COM12（CP210x）、115200波特率、8数据位、无校验、1停止位、无流控，文本接收。打开后短按KEY0并松开；收到CPU_COREMARK_START后等待测试完成。测试中不需要发送命令。再次按KEY0重新测试。串口被其他程序占用时先关闭那个程序的连接；下载工具本身不打开串口。

当前配置是六级单发射RV32IM/CSR、BTB32/BHT512/RAS8开启、无Cache、本地32KiB SRAM、标称100MHz。CoreMark v1.0采用2000字节performance数据集、5000次迭代，预计约17秒；以实际UART计时为准。

有效实物结果需要全部满足：

- 标准CRC：seed e9f5、list e714、matrix 1fd7、state 8e3a。
- Correct operation validated，以及CPU_COREMARK_STATUS errors=0 short=0。
- CPU_COREMARK_BOARD_PASS iterations=5000，测量时间至少10秒。

最终CoreMark和CoreMark/MHz行是用实际周期数计算、保留6位小数的结果。前面的Iterations/Sec (whole seconds)是原始无浮点报告的整数秒粗略结果，不用来记录成绩。计时使用同源timeh/cycle的high/low/high读取，串口输出和64位除法都位于计时区间之外。没有架构minstret，串口不报告未经验证的实物IPC。

保存完整文本后，可运行：

```powershell
python scripts/soc/coremark_board.py D:/path/to/coremark_uart.txt
```

解析器独立核对完整记录、CRC、时长、状态和周期到分数的换算。它不打开串口，也不把短仿真结果作为板测成绩。这里只完成performance配置的部署准备，不宣称EEMBC官方提交或认证；完整公开报告还需遵守原基准的全部运行/报告规则，包括validation配置。

部署流程：

```powershell
python scripts/soc/run_board.py --test clocks
python scripts/soc/run_board.py --test coremark
python scripts/soc/run_board.py --test coremark --fault crc
# CRC负例预期返回1，不能用于部署。
pwsh -NoProfile -File scripts/soc/run_board_route.ps1 -FirmwareTest coremark -FirmwareRunDirectory <coremark-positive-run> -ClockRunDirectory <clock-run> -PlacementSeed 8
python scripts/soc/review_board.py <route-run>
python scripts/soc/package_board.py <route-run>
python scripts/soc/program_board.py <package-directory>
```

板级数字PLL仿真实际执行5次迭代并逐bit解码UART，完整5000次部署镜像由同一冻结源另建；两者的ITERATIONS和PREFLIGHT策略宏不同。完整5000次运行不冒充已经过RTL仿真。部署固件重新执行PDS完整流程，必须实际100MHz全corner通过才生成下载包。原自检包cpu_board_df5475cbb154和备份标签cpu-board-physical-pass-20261020保留。只下载易失配置，不写Flash、不恢复Video。

本轮首次预检捕获编译参数报告溢出原256字节formatter缓冲区，报告后出现取指异常；未下载该失败固件。修正为UART只展示实际代码生成参数（限制整行小于256字节），完整参数仍保存在原生命令记录中；不扩大栈缓冲、不改原始算法/formatter源码。负例与修复后复测定位见配套证据索引。

预检另修正观察器：CSR模块的opcode_valid也包含普通指令，jalr -1024的高12位恰好为c00。观察器现在匹配真正的rdcycle操作码，避免把该跳转误计为CSR读取。修正后软件与观察器两次真实读取的差值均为1685886周期，CRC负例实际exit=1/reads=2；CPU RTL未改变。
