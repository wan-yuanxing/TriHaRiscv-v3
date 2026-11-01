# 六级双发射 SRAM CoreMark 上板

**最终100MHz六级双发射已通过真实板测及实体KEY0重跑。** 两次5000迭代输出完全一致：
CoreMark409.278990、CoreMark/MHz4.092789、CoreMark/LUTs0.042293，1221660558周期、
12.216605秒；errors=0、short=0、全部CRC正确。CPU-only9677 LUT，片上32KiB SRAM、
无Cache/DDR，GCC15.2/-O2。实际100MHz板级STA全通过，串口采集已关闭，当前保留
该100MHz CPU易失配置。此前95MHz/HIGH镜像实物未锁的失败记录与准入撤销仍保留。

用户已授权下载后自行使用串口助手接收。目标为已通过独立100MHz物理验收的v83，
六级顺序双发射，32KiB片上SRAM，无Cache/DDR；GCC15.2、CoreMark1.0、2000字节
performance数据集、`-O2`，部署5000次迭代。95/100MHz原标签和验收归档不变。

复用现有N3/N2的125MHz差分参考、HIGH带宽PLL100MHz、KEY0 C22和UART C24。
COM12、115200、8N1、无流控。下载为易失Program/Verify，不写Flash；流程不打开
串口。用户打开串口助手后短按KEY0即可完整重新输出，避免长按等待下载。

## 冻结构建边界

`scripts/cpu/prepare_dual_board.py`在`build/cpu/dual-board-v83-20261101/project`
创建一次性冻结构建包，明确文件清单和原始/生成哈希。22个CPU文件与v83候选
逐字节相同，SoC memory/ROM/实际DUAL_ISSUE=1来自原通过物理包。原生产源码、
主工程和既有下载包不修改。这是build内构建输入，不是另一套长期维护项目。

复用原板级时钟、软件、面积、物理复核、打包和Program/Verify工具。仅生成
双发射适配入口：实际参数必须为dual1，数字预检必须观察到真实双发射，WB日志
计入两个通道；路由器核对实际dual1。独立物理复核和程序包哈希/器件ID验证保持。
更新构建包内的派生哈希元数据时，另用v83完整候选清单约束全部22个源，不以
修改元数据代替源码身份校验。

保留原板级10ns、PLL、IO、hold、多corner预算、seed1，采用v83的自由布局方式，
不继承旧单发射PAP区域及试验参数。板级STA必须重新验收，不能直接使用此前
外部供给时钟的片上系统通过结论。只有全部实际时序通过才生成可下载位流。

## 早期实施记录

- 准备器5项检查通过：实际模式、双通道观察、缺失模板及哈希损坏拒绝。
- 实际PLL模型通过；JTAG只读识别PG2L100H/00602899，尚未下载。
- 复用CoreMark串口/CRC/短时/分数解析9项测试通过。
- 板级CPU-only原生面积测量通过：9503 LUT、4965 FF、752分布式RAM（已含于
  LUT）、4 APM、0 DRM；编译日志确认实际双发射参数。
- 5次板级短预检通过，使用数字PLL替身及真实115200 UART波形解码，观察到
  473739次实际双发射配对。计时1229829 cycles、1448453次WB、70840次store，
  CRC正确，errors=0、short=1。短RTL CoreMark/MHz为4.065605，不是实物分数。
- 已从相同冻结源以`-O2`编译5000次部署固件，并绑定9503 CPU LUT分母。
  串口打印CoreMark、CoreMark/MHz和CoreMark/LUTs。
- 首次板级PNR完成但时序失败：`project/build/soc/board-route-20261101T0923010007891Z`。
  Slow/Fast setup -0.501/+1.752ns、hold +0.161/+0.103ns、MPW +3.655/+4.202ns。
  最差为退出状态到LED的组合输出；另有SRAM读回-0.236ns和除法控制-0.205ns。
  未生成位流、未下载，不能沿用独立CPU边界的100MHz结论替代板级时序。

本轮证据均位于`build/cpu/dual-board-v83-20261101/`，准备清单为
`prepared-board.json`；项目内时钟验证为`build/soc/board-clocks-20261101T091028511162Z`，
CPU面积为`build/soc/cpu-area-20261101T091048932203Z`，短预检/最终部署固件为
`build/soc/board-coremark-20261101T091345535886Z`。短预检和部署镜像独立保存，
PNR使用运行根目录中已绑定的5000次固件。

## 板级状态输出修正

首次实际STA明确了退出状态译码到慢速LED引脚的跨区组合路径。新增可选准备参数
`--register-status-leds`，仅在新冻结构建包中寄存4个LED输出，异步复位保持熄灭，
释放及状态变化增加一个CPU周期显示延迟；CPU、UART及所有频率/IO约束保持。
`tb/cpu/tb_dual_board_led.v`以受控时钟/SoC桩验证成功、错误、空闲、中间周期保持
和异步复位；原包装实际仿真出现`BOARD_LED_FAIL combinational success path`，
寄存包装出现`BOARD_LED_PASS registered_status=1 asynchronous_reset=1`且无错误。
ModelSim在`-onfinish exit`下的Fatal也可能返回0，因此以实际日志错误/PASS标记
判断，不能只看工具进程退出码。红/绿日志位于`build/cpu/dual-board-led-unit-{red,green}`。

修正包为`build/cpu/dual-board-v83-ledreg-20261101/project`，CPU仍为原v83全部22文件，
旧冻结包与验收记录不修改。实际PLL模型重新通过，CPU-only原生面积为9677 LUT、
4968 FF、752分布式RAM（已含于LUT）、4 APM、0 DRM；这是本轮板级综合边界实际值，
不能当成对独立CPU边界资源的改善。最终固件LUT分母绑定9677。

修正后的完整短测通过，cycles1229829、实际配对473739、WB1448453、store70840；
计时窗口profile及WB/store轨迹哈希与初版逐字节相同。UART/CRC、errors=0/short=1
均通过；这是短RTL结果，实物跑分仍待用户串口验收。部署5000次固件ELF SHA256为
`7a00358e2f07dde157176c87c4e68c16031499e8008d91d01c3ef7e94475d1df`。

项目内时钟、面积和预检证据分别为`build/soc/board-clocks-20261101T093042776916Z`、
`build/soc/cpu-area-20261101T093105268098Z`、`build/soc/board-coremark-20261101T093310241377Z`。
第二轮原约束/seed1实际板级PNR在`build/soc/board-route-20261101T0937289142859Z`完成。
LED路径已不在违例中；Slow/Fast setup -0.535/+2.443ns、hold +0.167/+0.100ns、
MPW +3.655/+4.202ns，仍未生成位流。13个违例均为乘法器APM到result_e2_q相关路径，
最差数据逻辑5.585ns、布线4.291ns，CPU-only面积9677与UART分母匹配。

为处理实际乘法器跨资源布线，冻结一个独立的
`scripts/soc/run_dual_board_performance_route.ps1`适配入口：只在原PNR加
`-mode performance`并将新入口自身纳入输入哈希，保留原全部时序、面积、源哈希
及位流选择检查。原生模式有既有板级配方支持，不修改CPU或降低约束，不扫描seed。
来源/输出哈希及假设保存在修正包父目录`performance-route-adapter.json`。
复用同一已通过PLL、面积、完整短测和5000次固件，该运行位于
`project/build/soc/board-route-20261101T0943154182621Z`，终态仍为TIMING_FAIL：六项
时序和逐阶段布局checksum与前轮一致。显式性能模式没有改善，不能宣称收益。

接着仅对乘法器加入`PAP_REGION soc_board_mul(65,116,100,149)`，坐标顺序为
Xmin/Xmax/Ymin/Ymax，对应实际报告的完整X1/Y2时钟区（1400 CLMA、500 CLMS、
40 APM容量）。假设是将DSP、累加及结果寄存器集中在同一时钟区，减少数据布线
和跨区域clock skew；不能把PAP逻辑坐标直接当CLMA/APM物理site坐标。
约束和新独立入口冻结记录为`mul-region-route-adapter.json`，所有新输入均纳入
原时序/面积/哈希验收。运行`project/build/soc/board-route-20261101T0950466640275Z`
实际绑定96个乘法器叶节点，最终前20条路径不再出现乘法器；仍为TIMING_FAIL，Slow/Fast
setup -0.223/+3.594ns、hold +0.162/+0.103ns、MPW +3.655/+4.202ns。当前最差为
operand_rb_e1 -> branch0 compare -> issue/fetch accept -> head FIFO CE，逻辑2.190ns、
布线7.368ns。不能把针对乘法器的改善当作整板通过。

下一轮保留乘法器区域并仅将u_issue加入同一X1/Y2区域，合计原生层次2657 LUT
（u_issue2565、u_mul92）、4 APM，低于该区容量。记录为`issue-mul-region-route-adapter.json`，
运行目录`project/build/soc/board-route-20261101T0957278520915Z`。映射PCF生成2634个
叶节点区域绑定；最终仍为TIMING_FAIL，Slow setup -0.445ns，最差转移为head FIFO
到第二执行通道，另有fetch PC路径；hold/MPW通过。该方案不是改善结果，未下载。

## 95MHz实测边界

为先完成用户本轮上板测分，沿用此前允许小幅降频的授权，同一v83 CPU准备独立
95MHz板级版本；100MHz板级尚未收敛，不能用95MHz的通过替代。CPU全部22文件
保持原验收哈希，仍为六级顺序双发射、SRAM32KiB、无Cache/DDR、GCC15.2/-O2。
保留注册LED与乘法器X1/Y2局部约束，不保留退化的整块u_issue约束。

创建入口为`scripts/cpu/prepare_dual_board_95.py`，构建包
`build/cpu/dual-board-v83-95mhz-20261101/project`。PLL为125MHz/5*38/10=95MHz，
PFD25MHz、VCO950MHz、HIGH带宽；FDC生成19/25比例、原IO/hold预算不变。
RTL/C生成时钟定义、UART分频825、物理UART测试采样、64位真实计时及秒数/分数
同时更新；不保留100MHz的错误计时分母。独立板级复核保留所有源/工具/输出哈希、
器件/管脚/PLL、最终六项及复位时序、routed数据库和位流对应关系检查，仅将冻结
目标时钟改成95MHz；Program/Verify另要求程序包明确cpu_hz=95000000。

5项有失败前例的检查通过：实际PLL比值、95MHz正确计分、拒绝100MHz伪装、拒绝
错误分数及错误PLL。厂商GPLL模型在原1ps运行精度下的VCO量化使周期成为10.520ns，
与95MHz期望不符；改为模型支持的1fs精度后实际10.526320ns，保留原±1ps周期容差
和全部复位测试通过，没有扩大容差。纯数字CPU短测仍使用原1ps精度。

PLL证据为`build/soc/board-clocks-20261101T100838763601Z`；面积为
`build/soc/cpu-area-20261101T100908776417Z`：CPU-only9615 LUT/4966 FF/752已含RAM-LUT/
4APM/0DRM。短测/5000次固件运行目录为
`build/soc/board-coremark-20261101T101050905524Z`，完整短测通过：1229724 cycles、
473709次真实双发射配对、CRC正确、errors=0/short=1；短RTL为4.065953/MHz，非板测。

## 95MHz历史物理与烧录记录（已撤销运行准入）

首次95MHz布线原始报告为Slow setup -0.080ns、1个违例，未下载；时钟表分别保留
10.5263ns周期与5.2630ns半周期，原校验器按周期直接除二导致额外拒绝。后续独立
校验分别核对已知19/25周期和独立量化的半周期；实际旧报告仍正确判为timing FAIL，
损坏周期及半周期均被拒绝。未更改95MHz PLL/FDC或隐藏这条80ps真实违例。

最终使用原生布线后时序修复2轮，目标余量0.200ns、最多20条路径，原20分钟PNR/
1500秒外层预算不变。最终运行`build/soc/board-route-20261101T1025077899326Z`，
工具/runner返回0、全部冻结输入输出哈希复核通过。独立复核：

| 检查 | Slow余量/ns | Fast余量/ns |
| --- | ---: | ---: |
| Setup | +0.341 | +4.097 |
| Hold | +0.050 | +0.013 |
| 最小脉宽 | +3.918 | +4.465 |
| Recovery | +2.539 | +4.676 |
| Removal | +0.971 | +0.663 |

全部违例数为0、performance与最差setup一致。实际选择的顶层routed ADF SHA与
`place_route/route_constraint_ite_2/triha_cpu_board_top_pnr.adf`完全相同，位流由该库
生成；不是第一轮失败结果。CPU-only仍为9615 LUT/4966 FF/4APM/0DRM，UART分母一致。

程序包：`project/build/soc/releases/cpu_coremark_7edd33c0c21b`。
实际Program/Verify：`project/build/soc/board-coremark-program-20261101T104828807762Z`，
设备PG2L100H/00602899、原生返回0、cfg_program及cfg_verify实际成功。位流SHA256为
`7edd33c0c21b3516b841047c15116c343140f6e8814ba90ea729216d31bfb5a8`。
这是易失配置，不写Flash，流程未打开串口。主工程/NPU/Video工作树和任务不修改。

串口助手选择COM12、115200、8N1、无流控，打开后短按KEY0。等待5000次完成，
接收`CPU_COREMARK_BOARD_PASS iterations=5000`、errors=0/short=0及完整CRC/精确分数。
实际主频提示必须为95000000；CoreMark、CoreMark/MHz和CoreMark/LUTs由真实64位周期
计数计算。完整实物分数仍由用户本次UART日志验收，不把短测4.065953当作板测分数。

机器摘要：[dualissue_board_coremark_deployment_20261101.json](../verification/cpu/dualissue_board_coremark_deployment_20261101.json)。

## 实物启动故障定位与最终100MHz验收

用户报告按KEY0无响应、LED全灭后，实际90秒COM12/115200接收为0字节，重新下载
原95MHz包仍相同。复用已实测的27MHz独立观察器得到连续校验正确的诊断帧：同板
125MHz参考时钟正常、KEY0已松开；100MHz I1/M1/F8/O10/HIGH锁定且复位释放，
失败的95MHz I5/M1/F38/O10/HIGH未锁、复位保持。单因素把95MHz带宽改为OPTIMIZED
后锁定/复位均正常，分频计数符合95MHz。此结论限于实际测过的参数组合，不把
HIGH一概判错；100MHz仍使用已验证的HIGH配置。95MHz创建器已改为实测OPTIMIZED，
实际生成配置回归先复现HIGH失败，再验证OPTIMIZED和分频比；旧冻结包不改写。

故障摘要：[dualissue_board_startup_diagnosis_20261101.json](../verification/cpu/dualissue_board_startup_diagnosis_20261101.json)。
失败95MHz部署保留：[dualissue_board_95mhz_boot_failure_20261101.json](../verification/cpu/dualissue_board_95mhz_boot_failure_20261101.json)。

100MHz修复继续保持v83全部22个CPU文件、原PLL/管脚/IO/hold、多corner预算、seed1、
注册LED和乘法器X1/Y2区域，原生时序修复预算从2轮增到4轮，最多40条路径；原PNR/
外层截止不变。2轮仍-0.148ns/9违例；4轮实际运行
`build/cpu/dual-board-v83-ledreg-20261101/project/build/soc/board-route-20261101T1117136198580Z`
和独立复核全部通过。实际选中routed ADF与`route_constraint_ite_4`逐字节一致：

| 检查 | Slow余量/ns | Fast余量/ns |
| --- | ---: | ---: |
| Setup | +0.220 | +3.768 |
| Hold | +0.162 | +0.104 |
| 最小脉宽 | +3.655 | +4.202 |
| Recovery | +2.036 | +4.167 |
| Removal | +0.653 | +0.441 |

全部违例为0、performance与最差setup一致，源/工具/输出哈希通过。CPU-only9677 LUT/
4968 FF/752已含RAM-LUT/4APM/0DRM；UART分母9677与实际层次综合一致。
程序包为该项目`build/soc/releases/cpu_coremark_4a3932361535`。

先打开接收再调用未修改的100MHzProgram/Verify工具，实际设备00602899、返回0、
写入/回读均成功。实际接收目录为
`build/soc/dual100-physical-uart-20261101T114717089665Z`。自动下载后完整`boot-2.txt`
通过；随后用户短按KEY0并回复“已按”，完整`boot-3.txt`再通过。两次UART文本、周期、
CRC和精确三项分数完全相同。原自动采集器不推断物理按键，实体KEY0验收由用户
确认文件与随后第二个完整启动共同绑定，原采集记录不改写。

最终精确板测（非短RTL、非官方提交）：

| 指标 | 两次实测值 |
| --- | ---: |
| 迭代 | 5000 |
| 周期 | 1221660558 |
| 时间/s | 12.216605 |
| CoreMark | 409.278990 |
| CoreMark/MHz | 4.092789 |
| CoreMark/LUTs | 0.042293 |

seed/list/matrix/state/final CRC为e9f5/e714/1fd7/8e3a/bd59，errors=0/short=0；
接收器已正常关闭COM12，串口未发送任何字节，不写Flash、不恢复Video或改动主工程。
