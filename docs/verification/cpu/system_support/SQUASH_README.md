# 流水冲刷后的副作用隔离

测试连接正式 `triha_core` 的公开取指和数据端口，配置为六级单发射、RV32IM/CSR、512项直接映射BTB、512项BHT、4项RAS，关闭GShare。测试台提供128KiB行为存储器及一个MMIO写计数模型，不实例化Cache；不强制或写入DUT内部状态，生产RTL不变。

| 触发条件 | 错误路径/年轻指令 | 检查 |
|---|---|---|
| 分支误预测重定向 | SRAM store | 受保护字保持0x13579BDF，只有一次合法初始化写 |
| 分支误预测重定向 | MMIO write | 只有一次合法0x42写入 |
| 分支误预测重定向 | mscratch write | 保持0x12345678，只有一次合法架构写入 |
| 长延迟加载访问异常 | SRAM store | 禁止指令零退休，无额外存储 |
| 长延迟加载访问异常 | MMIO write | 禁止指令零退休，无额外外设写入 |
| 长延迟加载访问异常 | mscratch write | 禁止指令零退休，无额外CSR写入 |
| 长延迟加载访问异常 | 同目的寄存器load | 年轻请求不被接纳，MRET后复用x20加载得到0x11223344 |

两组正例：返回延迟32周期时750周期、2199项检查；64周期时1102周期、3031项检查。各退休162条指令、发生4次加载访问异常和4次MRET。七条禁止指令均被取回，其中四条异常后的年轻指令进入译码；禁止PC及故障加载PC均未出现在退休流中。四次异常均为mcause=5、mtval=0x8001F080、mepc等于各自故障加载PC。异常入口的软件还检查x20仍为异常前的0x22446688；四次恢复加载均为0x11223344。

独立核验解析原始WLF对应的VCD及完整退休日志，将写x0时无架构意义的结果字段归零后，两组退休序列完全相同。原始PASS行中的fetched=7f、decoded=78、recoveries=f为十六进制掩码；独立索引按十六进制解析。原始runner的statistics.decoded字段由通用十进制正则生成，值78不能作为十进制覆盖掩码使用，原始记录原样保留。

四个负例分别反转三处分支条件，以及将加载错误响应故意改报成功。前三个分别触发SRAM、MMIO、CSR副作用检查；第四个使异常后的非法SRAM写实际执行，也由SRAM监测器拒绝。它们是自检器的错误输入验证，不是RTL变异。各runner返回1，并具有对应CPU_SQUASH_FAIL及真实Fatal；ModelSim以-onfinish exit结束时工具本身仍可能返回0。

当前LSU阻塞等待一个已接纳请求，四个异常场景中年轻请求在错误响应返回前不能被接纳。本测试覆盖该互锁、精确异常和恢复执行，不声称验证了“已经接纳的旧load跨重定向后返回并被丢弃”。模块级前端迟到取指响应验证另见已有前端证据。

```powershell
# 在 D:/FPGA/TriHaRiscv-cpu-windows 执行
python scripts/cpu/run_squash.py
python scripts/cpu/run_squash.py --delay 64
python scripts/cpu/run_squash.py --negative store
python scripts/cpu/run_squash.py --negative mmio
python scripts/cpu/run_squash.py --negative csr
python scripts/cpu/run_squash.py --negative load
```

`squash_run_2026-10-30.json`绑定六个最终运行、冻结输入和输出哈希、独立VCD/退休流检查、截图及文档。`cpu-squash-support-2026-10-30.zip`包含六组冻结源码、ELF/MAP/HEX、原始日志、WLF/VCD、事件与退休流、查看脚本和截图；厂商仿真库和工具按原始记录的外部路径与哈希引用。

截图直接保存ModelSim Wave原始窗口字节，展示1900–3300ns，未裁剪或重绘，无鼠标指针。数据地址只在相应请求有效时有意义；在途事务使用saved_addr保存已接纳地址。2285ns错误响应对应0x8001F080，2306ns观察到mepc=0x800000C0、mcause=5，随后进入处理程序并恢复加载。该批次是RTL功能仿真，不包含综合、PNR、实际外设或板卡验收。

桌面工具恢复记录：旧会话在写入kernel assets时返回Windows os error 3，发生在UI接口初始化前；新运行时成功完成窗口枚举、原生截图和文件保存。未确认旧会话具体缺失路径，未修改Codex配置或安装新软件。截图完成后已关闭本轮查看器。
