# 板级PLL启动核验

2026-10-20，用户确认CPU Program/Verify和UART/KEY0验收，随后明确“不用恢复”Video。原912cb8d/cpu-board-100mhz-sta-20261020、CPU位流5f5eb8c89efd及其实际STA、下载包保持原始字节。新备份标签cpu-board-pre-pll-bandwidth-20261020指向该版。

原CPU镜像在PG2L100H/00602899实际Program/Verify返回0，但按实体KEY0后没有CPU串口输出，用户观察LED全灭。串口采集只有下载前296字节Video报文；没有CPU_BOARD_PASS或ALIVE。因此原版仍只通过STA和位流/回读校验，实际软件启动未通过，不能把Program/Verify当执行验收。

独立诊断只写入忽略的build/soc目录，不改CPU RTL。使用板上D18独立27MHz时钟驱动UART，跨域同步观察KEY0、PLL LOCK、CPU复位释放以及参考/输出时钟的分频翻转。包有固定头、序号和XOR校验；组件仿真核对UART帧和包校验。临时诊断的异步观察路径不是CPU时序验收，不放宽正式CPU约束，也不替代正式下载包。

原PLL参数I1/M1/F8/O10、BANDWIDTH=OPTIMIZED在27个连续诊断包中始终LOCK=0、CPU复位未释放、KEY0已松开。125MHz参考每个名义27MHz秒测得3814/3815个32768分频翻转，符合其标称参考频率；这不是校准仪器测频。只增加参考域启动/KEY0对PLL复位仍未锁定，失败对照保留。

同板已验证的DDR GPLL使用相同125MHz参考和I1/M1/F8、HIGH带宽。保持原诊断其他输入不变，仅将PLL BANDWIDTH改为HIGH后，实物连续28包LOCK=1、CPU复位释放=1，CPU分频计数每秒3051/3052次，对应标称100MHz。此结论限本板和本次配置，不推断所有OPTIMIZED配置均无效。

正式修复只在config/cpu_board.json显式声明HIGH，生成器同时写入IDF的BANDWIDTH和BANDWIDTH_advancedPage，独立生成wrapper复核也检查该字符串。新增生成带宽漂移/非法带宽两项测试先RED后GREEN，配置工具11项通过。真正安装PLL模型按既有-t 1ps/-voptargs=+acc设置111项通过；一次临时遗漏+acc的诊断调用产生模型除零，原日志保留，未据该调用验收。厂商文件无修改。

正式时钟/整核两次启动仿真及真实单字节损坏拒绝重新运行。CPU CoreMark源/输出哈希未变，复用1685831周期/1467843WB观察、短估算2.965896/MHz证据，不把PLL-only测量当CPU性能分数。后续必须完整新compile/synthesize/dev_map/pnr/report_timing、原100MHz/IO/hold/multicorner全部通过并重新生成包，再Program/Verify和现场UART/KEY0验收。不恢复Video、不写Flash。
