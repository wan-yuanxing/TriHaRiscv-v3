# CPU板级最小系统设计（2026-10-19）

本阶段沿用用户已批准的部署顺序：实际片上系统100MHz通过后，接板级时钟、复位、管脚和UART，随后再接DDR/Video/NPU。执行在现有CPU工作树，保留`cpu-soc-100mhz-sta-20261019`和原验收目录，不改已通过CPU RTL或原报告。

使用板卡已验证的N3/N2差分125MHz参考输入，`GTP_INBUFDS`后连接PDS生成的PLL。I=5、M=4、F=8、O=8，PFD=25MHz、VCO=800MHz、输出精确100MHz，均在安装工具的GPLL范围内。不用27MHz近似输出冒充100MHz。原始IDF从板卡参考包按已有清单哈希提取，只在build中生成新实例。

KEY0 C22低有效，PLL失锁或KEY0断言异步清复位释放链，三拍100MHz同步释放，CPU/总线/UART协调复位，SRAM不清空，启动软件清BSS。PLL不由按键重配。UART C24为115200/8N1，LED0 A20为硬件心跳、LED1 C18为释放状态、LED2 C19为软件成功、LED3 E18为软件失败；状态按电平描述，不假设灯亮极性。CPU外部中断绑0，未增加Cache、DDR或CPU流水级。

板级固件由同一GCC/ELF生成ROM与SRAM镜像，实际走ROM跳转和SRAM执行。检查初始化数据/BSS、8KiB独立可写缓冲的地址相关数据和字节lane、系统ID，UART打印CPU_BOARD_PASS后写EXIT=0并周期输出CPU_ALIVE。错误打印具体码并写非零EXIT。KEY0后再次清BSS、重新自检；不破坏正在执行的代码或栈。板级仿真使用同一镜像，不用TB灌入，不加仿真专用固件快路径。

先验证真实PLL模型的8ns输入/10ns输出和复位释放/失锁行为，再用数字PLL替身执行整核启动、串口线级接收与KEY0重启，明确区分模拟PLL和系统数字验证。完整PDS从新目录compile/synthesize/dev_map/pnr/report_timing，保持10ns、原IO max2/min0.5ns和uncertainty0.1/0.05ns，无false path/MCP。通过后才生成bitstream，并核验Slow/Fast setup/hold/MPW六项、performance一致、真实管脚/PLL映射和全部冻结输入输出。

只准备可审查下载包，包含位流、verify mask、镜像、日志索引、恢复说明和哈希；本阶段不自行替换板上Video镜像、不写Flash。现场Program/Verify、UART实读、实体KEY0和板级频率验收单独记录，不能把仿真、工具PASS或内部STA称为板测。

## 首轮物理反馈

首轮真实布通但Slow setup−0.661ns，主要是ROM数据返回经LSU/旁路/分支到PC。ROM到返回MUX及MUX到LSU两段分别1.001/1.420ns，下一轮增加ROM与CPU共用完整时钟区的明确物理约束，原逻辑、固件、seed1和时序预算不变，SRAM仍由工具自由布局；最终结果重新判定。

PDS会在执行阶段前解析Tcl，所以不能在含compile/route的同一脚本里立即打开尚未存在的最终报告。首轮错误完整保留。修正为宿主在完整PDS返回后读取报告、核验六项STA，通过后第二次调用PDS只执行位流生成；不忽略工具错误，也不让时序失败目录生成可交付位流。

ROM区域版seed1最差−0.303ns/13端点，seed2为−0.781ns/161端点，保留前者作物理比较基线。其PC预测反馈10级、1.482ns逻辑/8.358ns布线。前端(8,39,156,187)未通过PDS实际区域容量检查，已扩大为父CPU区域中的(8,47,154,193)，保持seed1和其他输入。这是布局试验，不能预先称为时序收益。

## 预测payload等价并行选择

有界物理对照后，原CPU网表最佳为seed8的−0.096ns/3端点，定向布线未改善。板级准备版本已提交a9034b5并打标签cpu-board-pre-npc-late-select-20261019；原100MHz通过标签仍保留。

只调整预测器组合读口，复用已有独热AND/OR选择器，分别提前选出完整精确PC/upper-word payload，再以原过程if决定最终payload。原32bit选择向量mux删除，最高表项优先、完整tag、upper-word fallback、BTB32/BHT512/RAS8、训练状态和预测周期不变，未新增流水或状态。保持payload边界以避免综合重新串回晚到选择信号。

四态等价按相同过程分支分类：不论条件为0/1/X/Z，原实现和新实现都按同一if规则选择同一个掩码；对选中掩码执行AND/OR，再选结果，与先选掩码再AND/OR完全相同，包括未选payload中的X/Z。完整预测器状态/输出对照和真实坏输出拒绝通过；三seed×单/双发射有序WB/store/同步异常以及IRQ/mret对照通过。新SRAM CoreMark1685831cycles/1467843WB及CRC与父版完全一致，观察IPC0.870694、短测2.965896/MHz；仍为RTL短测，非官方或板级分数。

新板级整核两次启动及8KiB自检通过，新的单字节故障仍被固件code1拒绝。继续相同10ns/IO/hold/PLL预算的全新PDS验证；仅实际报告全部通过才交付。

第一版并行payload实际−0.678ns，未选用。报告中独热选择器的平面OR归约被映射成长链，因此下一版按LUT6的六个输入显式分组：每叶三个AND项，组间每六项归约，再归约结果；OR结合律和零填充保持四态语义。删除仅用于求valid的32bit选择向量，直接按相同过程if选择标量valid。无寄存状态或周期变化，重新执行全部功能/性能验证后再物理实现，不能用逻辑层数估算代替STA。

平衡版亦通过完整功能/性能验证，实际CPU6404LUT/5172FF、后布线−0.408ns。两版未超越原网表最佳−0.096ns，均不准入部署；保留源代码诊断检查点、运行快照和完整记录后恢复原CPU源/清单，后续只用PDS官方syn_maxfan对实际高扇出PC寄存器做综合复制，并复核复制FF的D/CLK/CE/reset/init及真实时序。
