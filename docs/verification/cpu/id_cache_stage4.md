# I/D Cache：独立DDR板级实现与时序诊断

2026-10-22，父提交`6c40346`。本节点完成实际板级边界和两轮完整物理实现，**100MHz尚未通过**。小型机器索引见`id_cache_stage4.json`。原部署`build/soc/releases/cpu_coremark_6ff82025b53d`保留，未生成新位流、打开串口、编程、合并或推送。

## 板级边界

`triha_cpu_ddr_board_top`连接原本地缓存CPU、五通道CDC、固定native256桥及实际DDR控制器/PHY。独立27MHz时钟负责启动、初始化超时、时钟停止和锁定状态观测；N3/N2的125MHz差分参考只经过一个输入缓冲，同时供CPU PLL与DDR IP使用。CPU PLL沿用已验证的HIGH带宽125→100MHz参数。DDR实例名`I_ips_ddr_top`、71个mem管脚属性、PHY时钟/site和两条priority net保持固定来源字节/层次契约。

显式工程`fpga/pg2l100h/project/cpu_ddr_board.json`选入实际CPU/Cache/CDC/桥、两个板级模块、生成PLL和全部74个DDR硬件源。生成IP的通用管脚FDC不加载，数字PLL/DDR模型不进入硬件filelist。所有运行独立保存输入/工具/固件/生成IP和输出哈希、命令/退出码、进程命令及心跳。PNR20分钟，单次外层上限1500秒，仅允许超时时清理本次拥有的进程树。

这是native端口独占的CPU诊断目标。软件会覆盖私有`0x80010000`和共享`0x87300000`各8KiB，不能同时挂另一native写端或当作生产多主fabric。

## 数字验证与复位修复

GCC15.2、RV32IM/ILP32、`-O2`、无LTO的真实固件完成ROM→SRAM、UART、私有/共享区模式/字节/半字测试；在`0x80001000`写入代码，FENCE.I后先返回7、修改后返回9。KEY0前后两次完整自检均成功。这里使用数字PLL/DDR替身，没有证明模拟训练、信号完整性、真实DDR延迟或板上运行。

四类监测测试分别核对初始化超时E0、初始化丢失E1、DDR停钟E4、CPU PLL丢失E5，错误码保持且能由本地软件报告。DDR故障不撤销已拥有事务或复位控制器；CPU PLL丢失协调CPU/Cache/CDC/桥/控制器的复位epoch。数据损坏负例实际触发CPU store异常，cause7、地址`0x80010000`，自校验失败且宿主返回1。

首轮实际STA暴露了板级状态的跨域复位释放。新增时钟边沿自校验先在旧版失败（`unsynchronized free reset release`），再修复：free域状态使用本域两级释放，DDR心跳和板级fault同步器使用DDR本域两级释放。原KEY0 IO max2/min0.5ns预算保留，例外仅指向异步释放同步器的C引脚；其余同域recovery/removal、第二级D、CE及数据路径继续检查。完整启动、四故障及损坏负例重新执行通过。此前stage3在途事务/协调复位验证仍单独保留；这些板级监测用例不扩大为任意故障中断下的物理持久性证明。

## 实际后布线

两轮均为新compile/synthesize/dev_map/place/route，无旧布局/路由导入，原100MHz和IO/hold/multicorner要求不降低。PDS实际返回0、阶段标记完整；runner返回2要求独立审核，不能当作时序通过。

| 检查 | 首轮Slow / Fast | 同步释放修复后Slow / Fast |
|---|---:|---:|
| CPU setup | -0.863 / +3.423ns | **-0.155 / +3.521ns** |
| CPU hold | +0.160 / +0.101ns | +0.158 / +0.100ns |
| CPU最小脉宽 | +3.655 / +4.202ns | +3.655 / +4.202ns |
| CPU recovery | +3.303 / +4.950ns | +4.723 / +6.463ns |
| CPU removal | +0.357 / +0.225ns | +0.219 / +0.129ns |

最新CPU Slow setup两个违例端点，TNS -0.161ns。最差路径是前端FIFO `rd_ptr_q[0]`经指令/寄存器选择到`u_exec0/result_q[5]`，源扇出225、首段布线0.801ns；另一条FIFO数据到`result_q[7]`为-0.006ns。新布局整体改善不单独归因于某一RTL修改，更不能当作已达到频率。

原CPU→free/DDR的外部复位恢复违例和普通free→DDR板级状态违例已消除；仍有**free→DDR PHY相位调整FSM五个recovery端点**，Slow -8.198ns、Fast -4.539ns。实际端点为重编码后的`cpd_state_reg[0..4]`，需要核对厂商启动协议与原scoped reset例外在FSM转换后的传播，不以扩大整域豁免消除报告。其余时钟域仍按最终实际报告逐行保留。

Gray约束兼容PDS前期宽单元`wr_gray[2:0]/Q[bit]`与后期`wr_gray[bit]/Q`；正则只匹配指针和第一同步级，禁止前缀把第二同步级也选入。实际CCR中20个指针选择各3位、六组状态第一同步级分别1/1/9/1/2/1位。最终64路径报告覆盖两corner全部60条实际datapath-only MaxDelay检查，均通过8ns要求。虽然已设置10条2ns max-skew且启用report_max_skew，最终报告没有独立skew检查段，**skew保持UNKNOWN**，不以已匹配、无工具错误或max-delay余量替代。

DDR mem端口沿用厂商PHY约束，报告中的外部DDR AC/校准仍未独立签核。板级UART/LED预算不放宽。全局工具成功、CPU单项余量或原生映射估计均不能代替完整准入。

## 资源：最新同一综合上下文

无面积扫描夹具；RAM LUT已含在LUT中。DRM按36K等效计数。

| 范围 | LUT | FF | RAM LUT子集 | DRM | APM |
|---|---:|---:|---:|---:|---:|
| CPU核 | **6478** | **3562** | 688 | 0 | 4 |
| I/D Cache及传输 | 523 | 763 | 0 | 11 | 0 |
| 五通道CDC | 67 | 153 | 0 | 6 | 0 |
| 固定DDR桥 | 3634 | 3354 | 128 | 0 | 0 |
| 本地ROM/SRAM/MMIO | 145 | 89 | 0 | 16.5 | 0 |
| DDR控制器/PHY | 4696 | 5144 | 43 | 0 | 0 |
| 独立监测 | 110 | 105 | 0 | 0 | 0 |
| 其余互连/板级逻辑 | 93 | 51 | 0 | 0 | 0 |
| 整板目标合计 | **15746** | **13221** | **859** | **33.5** | **4** |

层次统计用于分离CPU核和周边，不把整板数字算成CPU资源，也不与另一综合上下文直接宣称CPU优化。本轮软件是诊断程序，没有新增CoreMark跑分；原stage1固定数字内存模型的性能对照及已部署SRAM版本分别保留。

## 复现与剩余门槛

```powershell
python scripts/cpu/gen_ddr_board.py --check
python scripts/cpu/test_ddr_board_config.py
python scripts/cpu/test_ddr_board_review.py
python scripts/cpu/run_ddr_board.py
python scripts/cpu/run_ddr_board.py --test no-init
python scripts/cpu/run_ddr_board.py --test init-loss
python scripts/cpu/run_ddr_board.py --test clock-stop
python scripts/cpu/run_ddr_board.py --test cpu-pll-loss
python scripts/cpu/run_ddr_board.py --fault data
python scripts/cpu/run_ddr_board_route.py --firmware-dir <本轮boot目录>
python scripts/cpu/review_ddr_board.py --physical <本轮route目录> --output <审核JSON>
```

损坏负例应返回1。审核JSON的status PASS表示绑定/报告核对完成，timing_status仍FAIL。原始运行、失败选择器诊断和复位RED目录均由机器索引定位。

下一步按实际读指针/执行路径、厂商FSM复位和完整Gray skew处理物理准入；不改CPU周期/预测器或降低100MHz要求。随后才是共享fabric及其他主端可见性，再独立处理真实DDR训练和板卡验收。
