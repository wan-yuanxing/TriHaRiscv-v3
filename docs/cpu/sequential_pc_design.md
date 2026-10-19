# 顺序PC提前计算

父版2eb3c34及标签cpu-board-pre-sequential-pc-20261020保留BHT提前读取实现。其实际板级后布线Slow setup为-0.586ns，CPU层次5915LUT/5172FF/64分布式RAM/4APM，未通过100MHz。

父版最差路径从fetch PC[15]经过tag比较、upper优先级、payload中的返回元数据，再进入共享加法进位链，最终到fetch PC[23]。晚到控制N28[0]扇出34、布线1.202ns，之后仍有连续COUT与末端1.360ns布线。此次只检验一个假设：把顺序PC+8作为保留的早期组合结果，可使预测控制在加法后选择，避免其进入进位链。

维护实现新增一个syn_keep组合wire，表达式仍为`{pc_f_i[31:3],3'b0}+32'd8`；BTB未命中和最终顺序fallback两处引用同一结果。非预测分支、预测优先级、BTB32/BHT512/RAS8、训练、复位和全部状态不变，不增加流水级或周期。原vendor28文件不变。

完整预测器输出/状态及直接BHT信号比较、23560项优先级检查、16512项并行RF检查、训练、三seed单/双模式有序执行和IRQ/mret均通过。预测器和优先级坏输出被拒绝。真实PLL模型111项、两次整核板级启动、单字节损坏后固件code1拒绝均通过；正负例ELF的PT_LOAD内容一致，SRAM初始化只在0x10640异或1。14项运行的当前输入、可用快照、外部模型和输出哈希已核验，见board_sequential_pc_validation.json。

CoreMark短RTL仿真保持1685831cycles/1467843WB完成观察，观察IPC0.870694、短测2.965896/MHz，CRC正确；这不是官方分数、完整minstret证明或板测。板级100MHz仍以本轮实际Slow/Fast setup、hold及脉宽报告为准，不以保留wire或综合结构代替STA。

实际终态：board-route-20261019T1806550427178Z完整布通，独立证据复核通过，但timing_closed=false。Slow/Fast setup -0.212/+1.752ns、hold +0.154/+0.101ns、脉宽+3.655/+4.202ns，Slow仅3个违例端点、TNS -0.442ns。CPU层次5934LUT/5172FF/64分布式RAM/4APM，较父版+19LUT、FF不变。新映射和新布局下最差值改善0.374ns，不能归因成固定布局中的单条逻辑收益。

最差三条均从FIFO rd_ptr_q[0]出发，经指令rs2选择/旁路到执行结果。该指针实际扇出141、首段布线0.990ns，最差全路径12级、逻辑2.266ns/布线7.504ns。预测控制经加法进位链已不在前三个违例路径中。下一项仅对这一实测高扇出寄存器使用已验证过的ADS syn_maxfan复制机制，复核复制FF的D/CLK/CE/reset/init和实际后布线；不重新扫描工具选项或降低约束。
