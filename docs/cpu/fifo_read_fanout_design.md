# FIFO读指针物理复制

备份020ef40/cpu-board-pre-fifo-fanout-20261020保留顺序PC提前计算及其完整证据。板级父版Slow setup -0.212ns，3个违例同源：FIFO rd_ptr_q[0]→rs2/旁路→ALU结果。首段扇出141、布线0.990ns，整条逻辑2.266ns、布线7.504ns。

本项只使用既有PDS ADS官方syn_maxfan机制将该寄存器负载限为32，并保持seed8、区域、PLL、100MHz/IO/hold/uncertainty和所有RTL/固件不变。相比再次重构旁路或为每个FIFO槽复制操作数网络，此次有界诊断不改变接口、状态转移或周期，先验证实测首段负载的物理影响。失败时保留结果并退出默认recipe，不因复制本身声称时序改善。

实际原生综合产生6个副本，逐个核对GTP_DFF_C、D、CLK、C、GRS_EN和INIT均一致；原父版无副本被检查器拒绝。CPU综合层次5941LUT/5178FF/64分布式RAM/0DRM/4APM，较父版+7LUT/+6FF。该检查只证明所检查副本状态连接一致，不是完整网表语义证明。完整CPU/固件RTL和原数字证据按源哈希复用；不重复无关仿真。

最终仍需实际后布线Slow/Fast setup、hold、脉宽和独立证据复核全部通过，才可生成并打包位流。没有Program/Verify或板测，不改主工程Video。

终态board-route-20261019T1812181122360Z布通但未准入：Slow/Fast setup -0.438/+1.752ns、hold+0.017/+0.002ns、MPW+3.655/+4.202ns。Slow39个违例端点/TNS -7.490ns。实际最差指针首段扇出降至31、布线0.605ns，但指令选择到ALU控制的后续布线增加，整体不优于父版。该诊断已结束，不继续扫描复制阈值；从默认recipe撤销此项，仅保留冻结结果与约束文件作历史证据。
