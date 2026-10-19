# 旁路优先级并行选择

保持020ef40的CPU基线，撤销未改善STA的FIFO复制约束。实测读指针→rs2比较→旁路选择→ALU路径有12级，逻辑2.266ns/布线7.504ns；单独分散指针负载不能改善全局STA，故不继续扫描复制阈值。

仅将既有forward_raw_operand中的六次数据覆盖，改成六路标签同时比较、每路排除更高优先级命中，再用唯一选择码的case选择原始payload。仍为WB0、WB1、E2-0、E2-1、E1-0、E1-1的覆盖优先顺序，最后x0强制零。比较使用原过程if语义，未知比较视为不命中；case直接传递选中值的X/Z，不用会把Z变成X的多路按位OR。原生RF、地址、状态、旁路值、接口和CPU周期不变。

先扩展既有独立顺序oracle，穷举31个非零寄存器×64种六路命中组合×两个槽，同时注入被屏蔽与被选中的X/Z数据；原版须通过，真实坏输出须拒绝。然后修改单一函数，核对扩展检查、整核有序执行/异常/IRQ、CoreMark精确周期、板级正负例和真实STA。六级单发射、预测规模及原100MHz/IO/hold/uncertainty均不改变。

终态：24448项组件检查、15项当前运行/哈希索引通过，CoreMark仍1685831cycles/1467843WB、短估算2.965896/MHz。CPU5977LUT/5172FF/64分布式RAM/0DRM/4APM，较顺序PC父版+43LUT、FF不变。首次完整布局布线实际setup +0.023ns，但位流命令拆行导致流程FAIL；原记录和全部冻结哈希保留。修复PowerShell数组内拼接括号，并用生产表达式回归先RED(4行而非2行)后GREEN，不改RTL/约束。

完整复跑board-route-20261019T1825066711298Z全部工具和宿主返回0，source_unchanged；Slow/Fast setup+0.023/+1.752ns、hold+0.155/+0.100ns、MPW+3.655/+4.202ns，recovery/removal亦无违例，performance slack一致。最差为SRAM块RAM→ALU结果。独立review通过并生成cpu_board_5f5eb8c89efd下载包，未Program/Verify或板测。标签cpu-board-100mhz-sta-20261020保存此版。
