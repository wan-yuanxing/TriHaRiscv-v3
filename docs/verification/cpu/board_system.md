# CPU板级最小系统验收

更新时间：2026-10-20。原100MHz系统基线`5c4229a`和标签`cpu-soc-100mhz-sta-20261019`保留，本批CPU RTL未改。板级顶层为`triha_cpu_board_top`，六级单发射、RV32IM/CSR、BTB32/BHT512/RAS8开启、无I/D Cache，8KiB ROM、32KiB SRAM和UART TX地址不变。

## 板级边界

| 信号 | 管脚 | 含义 |
|---|---|---|
| ref_clk_pi/ref_clk_ni | N3/N2 | 125MHz差分参考，SSTL15D_I/1.5V |
| rst_ni | C22 | KEY0低有效，异步断言、100MHz三拍同步释放 |
| uart_tx_o | C24 | 115200/8N1，LVCMOS33 |
| led_o[0..3] | A20/C18/C19/E18 | 硬件心跳、复位释放、软件成功、软件失败，按信号电平描述 |

当前PLL I1/M1/F8/O10，PFD125MHz、VCO1GHz、CPU100MHz。来源IDF、实际生成wrapper、安装原语、工具和固件均按哈希绑定。板级不含DDR/Video/NPU；UART为固件MMIO输出，未添加独立硬件自报PASS通路。

## 已完成的数字验证

- 配置/工具8项通过：精确100MHz、PFD范围、管脚唯一性、未知端口、生成约束漂移和真实Windows nm符号解析/歧义拒绝。另原系统生成工具6项保持通过。
- `board-clocks-20261019T134603015872Z`：安装Pango真实GPLL/INBUFDS/CLKBUFG模型、实际生成PLL，111项检查，100个连续周期均为10ns；按键保持/三拍释放/重复按键/强制lock丢失后重新释放通过。这是模型验证，不是物理PLL测量。
- `board-system-20261019T134606298225Z`：同一GCC ELF/ROM/SRAM镜像完成两次真实CPU启动；每次独立检查BSS和8KiB可写缓冲的地址相关数据/字节lane，串口线级接收完整PASS和ALIVE，KEY0后重新初始化成功。系统仿真使用明确标识的数字PLL替身，不能代替PLL模拟模型。
- `board-system-20261019T134559208677Z`：只破坏ELF中实际initialized符号对应SRAM字节，固件真实UART输出`CPU_BOARD_FAIL code=00000001`，宿主拒绝。最初故障注入工具的CRLF解析错误已单独保留为FAIL，不当作CPU负例通过。
- 只读JTAG：`build/video/jtag_scan/20261019T134756_805037Z`，识别PG2L100H/00602899、DONE=1，未编程。Windows可见COM12 CP210x；本轮未打开串口或替换当前配置。

8KiB自检仅覆盖软件拥有的缓冲，不能称32KiB全部地址的现场测试。原生SRAM全地址组件证据仍见原最小系统验收。新增固件不是CoreMark；CPU性能数值继续引用原SRAM短RTL基线，不将它改称板级分数。

## 物理流程

10ns及原IO max2/min0.5ns、setup/hold uncertainty配置0.1/0.05ns保持，无false path或multicycle。实际PLL报告的setup总不确定度为0.250ns，原外供时钟系统为0.150ns；保留工具对真实时钟的建模，不调低预算。

| 完整运行目录后缀 | 物理配置 | 最差setup/ns | 失败端点 | 结论 |
|---|---|---:|---:|---|
| 1346585243566Z | 基础CPU区域/seed1 | −0.661 | 29 | 布通但时序失败，另有报告提前读取的脚本错误；原始FAIL保留 |
| 1352504748462Z | ROM与CPU共区域/seed1 | −0.303 | 13 | 完整工具返回0，其余五项及两角复位recovery/removal通过，100MHz仍未通过 |
| 1358076128200Z | 同一ROM区域/seed2 | −0.781 | 161 | 未选用，布局seed变化未带来改善 |
| 1403393645182Z | 前端32×32区域/seed1 | 无报告 | 不适用 | PDS区域容量检查失败，未进入布局布线，不算时序结果 |
| 1407209697773Z | 前端40×40区域/seed1 | −0.897 | 以原报告为准 | 布通但未通过，未选用 |
| 1412486341257Z | ROM区域/seed1/关键路径优先 | −0.303 | 13 | 未改善，未生成位流 |
| 1421275069880Z | seed4..9/并行2，最佳8 | −0.096 | 3 | 原网表最佳，仍未通过 |
| 1431073056262Z | seed10..15/并行2，最佳13 | −0.217 | 以原报告为准 | 未选用 |
| 1440308216288Z | seed8/定向布线最多3轮 | −0.267 | 12 | 未选用 |

目录统一前缀为`build/soc/board-route-20261019T`。首轮摘要见`board_first_route.json`，第二轮独立复核见`board_rom_local_route.json`，其中status=PASS仅表示证据核验成功，timing_closed=false表示时序未通过。原始目录不回写。

最佳轮路径PC→完整BTB tag比较/最高优先选择→预测PC，10级逻辑，1.482ns逻辑/8.358ns布线。前端32×32区域未通过PDS真实容量检查，错误`ConstraintEditor-0070`、工具1/宿主1，已完整保留。扩大40×40区域后布通但时序更差，因此正式清单不启用前端子区域。

上述均已终态，原CPU RTL和固件未改，正式清单不启用前端子区域。原网表最佳为seed8的−0.096ns，仅3个端点；有界布局和定向布线已评估，当前没有可交付板级位流。后续预测器等价实现调整单独验证，不回写这些失败记录。

只读串口入口`python scripts/soc/board_serial.py --port COM12 --seconds 12`，应在实际Program/Verify前开始捕获以接收完整启动banner；`--expect-reboot`要求两次完整banner和各自的周期推进。解析器6项先RED后GREEN，覆盖固件FAIL、周期停滞、丢序、缺banner及非预期重启。不写串口数据，不替代Program/Verify和实体KEY0操作证明。本轮未执行物理捕获。

恢复候选：主工程`build/video/releases/video_raw_board_0cd4a546804b/video_raw_board_top.sbit`与同名smsk，已对照`build/video/latest_board_program.json`的历史Program/Verify成功记录核对两者哈希。本轮未再次下载该文件，不以JTAG DONE=1推断板上当前位流身份。

现场Program/Verify、UART实际接收、持续运行、实体KEY0及物理时钟仍未验收；当前Video配置保持在板上。


## 2026-10-20 板级物理对照及下一步

已恢复a9034b5的原CPU源/11项派生清单，28个vendor文件不变。PC复制未改善（-0.536ns），高PFD PLL I1/M1/F8/O10仍精确100MHz，实际PDS uncertainty仍0.250ns，最差-0.096ns。相邻区域(0,64,100,149)容量失败（native1）；恢复原CPU/ROM区域(0,64,150,199)。合法详细布局迭代40次、Performance模式均仍-0.096ns；LUT6D策略0/2分别-0.673/-0.500ns；布局扩散系数0为-0.205ns，均未收敛。无频率、IO或hold约束放宽，没有位流/上板。首次迭代参数8被工具拒绝，已保留并增加合法10..50前置检查。

当前数字验证：实际PLL模型111项；整核两次启动/8KiB自检；真正损坏0x10640的一字节后固件code1拒绝，正负例ELF加载内容一致。配置9项、串口6项、选定路由DB绑定4项通过；见board_selected_digital_validation.json。

工具选项对照不再扩大。下一步仅在维护派生中将AUIPC/JAL/JALR的PC加法从通用ALU输入选择链移出，保持六级单发射、预测器规模、状态/复位/hold和周期不变。先执行原执行单元全输出对照和负例，再做整核退休/store/异常、CoreMark及板级正负例，最后以实际100MHz STA判断。原版及所有失败证据保留；本检查点仍不是可交付板级版。


## 2026-10-20 发射选择路径核对

PC加法等价实验通过完整执行单元/整核/CoreMark，但实际-0.442ns，已存7e9df4d/cpu-exec-pc-diagnostic-20261020后恢复原CPU，并从默认树删除该实验RTL/入口/TB，快照和标签保留。真实关键路径是issue PC[2]选择指令字→RF地址/读取→ALU，不是PC算术。

只复制该选择位的物理对照实际增加7FF；8个状态的D/CLK/CE/reset/init逐项一致，但全局setup恶化至-0.800ns，不选用。最后补齐种子3/16为-0.329/-0.233ns，原版最佳仍seed8的-0.096ns。所有约束保持、无bitstream/上板。

下一步复用两个既有原生2读口单写寄存器堆，分别固定读取两个取指槽，旁路优先级分别计算后再选择实际操作数。每拍仍只发射一条指令，不增加CPU状态级/周期或改变预测器。预计额外32个分布式RAM单元，实际CPU-only资源与后布线另测；不能提前声称频率收益。
