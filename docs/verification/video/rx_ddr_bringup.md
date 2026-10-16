# RX 与独立 DDR 板测

日期：2026-10-16。基线为 `16556d1`，当前批次细化 V014b/V015。所有步骤使用 Windows 原生工具；无 Flash 写入。最终验收摘要见 `evidence/rx_ddr_bringup.json`，原始目录均在忽略版本管理的 `build/video/`。

## 工程与来源

RX 目标保留本地 RGB888 彩条，以串行模型验证 TX 完成后 RX 才取得共享 I²C。固定 EDID 只广告 DMT 800×600，实际扫描率约 60.3165 Hz。RX boot 与频率事件配置分别可观测；未把 sticky 配置状态当作实时锁定。厂商 MS7200/MS7210 和 I²C 源文件保持原始字节，适配均在本工程 wrapper。

DDR 目标独立于 HDMI。`gen_ddr.py` 在新目录生成 HMIC_S1.10，并复核 71 个已安装保护源、两个原 wrapper 和一个生成 slice 的哈希，以及精确 74 文件集合。构建只添加一次 IDF；DDR FDC/RCF 独立加载，拒绝生成器产生的通用管脚 FDC。71 个 DDR bit-port 属性与官方板级参考完全一致；独立参考中的 freeclk/UART 冲突已筛除。125 MHz N3/N2 与 27 MHz D18 不混用。

## 数字验证边界

- RX 串行初始化：300 项 boot 写入、264 次 EDID RAM 写入（前 8 字节重复写）、冷启动已有频率事件、正常事件、重连、NACK/读回/看门狗与中途复位。256 字节 RAM 最终内容独立核验。
- 接收时序：800×600、1056×628、全部同步/porch、错误时撤销、整帧恢复；VS 可在有效区原点或 HS 边界变化。探针独立报告 VS 高电平/周期的像素时钟数与原始边沿次数。
- 跨域/串口：注册 Gray 计频、冻结总线 req/ack、两级同步及额外等待沿；停止/恢复；UART 实际 bit 解码、32 字节快照一致性、XOR、异步复位。
- Native BIST：8 个缩小参数组合，含 137 beat / 7 beat 的跨 4 KiB 边界测试；独立内存模型和 oracle 验证模式、32 个 one-hot 字节掩码、无 WVALID 的最早/间断 WREADY、返回 ID/LAST、地址别名、超时、全部 256-bit 错误与协调复位。
- DDR 板级数字替身：初始化前无访问、core 不启动/停止、保持失败、失锁后的旧 PASS 撤销、KEY0 恢复、CDC 和可解码 UART。替身明确不是 PHY/DRAM 仿真。

ModelSim 能编译/展开保护库，但厂商 GTP_GPLL 模型在 76 ns 出现除零并中止。未报告训练仿真通过。BIST 缩小参数回归也不等同于默认 1 MiB 窗口的完整仿真。

默认物理 BIST 比较数为 `29 + 46 × 2 × 32768 = 3,014,685` 个 256-bit beat。覆盖低/高各 1 MiB、物理地址位与 128 MiB 规划窗口边界哨兵，不是全部 1 GiB 扫描。正式 AXI128、跨主端写后读可见性、仲裁和带宽仍待实现/验证。

## RX 上板调查

最初直接把 pad 输入扇出至边沿检测器，实测水平时间戳滚动且没有完整 VS 区间。独立仿真下载位流对应的综合后监测逻辑，干净输入下正确，保持 HS 时计数冻结，排除了所怀疑的逻辑截断原因。

加入统一输入寄存器后，实际有效区恢复为 800×600，总行场为 1056×628，像素频率约 40,000,100 Hz。但上升沿采样仍出现 HS 127/128、front 40/41、偶发周期 1055，VS 行数读为 3、back 24。原始探针确认 VS 宽度实际 4224、周期 663168；独立模型用一像素 HS 相位变化重现同一组读数。因此未放宽时序检查，而是把 pad 统一采样移至下降沿，内部按半周期定时。

用户确认 Windows 活动信号模式 800×600、60.32 Hz，与规范计算一致。下降沿版已通过板级集成仿真和 PDS 内部时序；实际 Program/Verify 和最终模式通过与否由证据摘要单独记录。

JTAG 本批多次 Program/Verify 成功，随后出现下载器可见、链为空；同一时刻 COM12 旧程序仍正常运行。默认及 100 kHz 扫描、下载器 USB 重连未恢复时，停止写入并保留失败日志，请用户协调板卡电源重启。不能单凭链为空归因于 CPU 程序、供电、脚本或硬件损坏。

板卡电源重启后已直接运行原 CPU 的 `jtag_scan_only.tcl`，仍读全 1。另按已安装 Configuration 手册采用 `cfg_set_options -server_delay_time 1 -report_detail true`，在连接后设置，再以 100 kHz 扫描，同样未识别。没有改系统驱动、安全配置或 Flash。手册确认 FPGA 专用 JTAG pad 为 H12/H11/H10/J10，均未被 RX/TX/DDR FDC 占用；未发现下载进程冲突。下一硬件分界是下载器到 J12 的排线/参考电压通路，避免重复把 USB 枚举当作目标连接正常的证明。

若排线重插后仍不能恢复，按板卡原理图定位 J12：1=TCK、3=TDO、5=TMS、9=TDI、4=A3V3、2/10=GND，6/7/8 未连接。具备设备时可核对目标参考电压及扫描中的 TCK/TDO，或通过核心板直连 JTAG 隔离底板/板间连接。此处为后续诊断位置，不表示已经做过电压或波形测量。

18:59 用户确认排线两端已断电重插、重新上电。新目录默认和 100 kHz 扫描均未识别 FPGA，server 日志仍为 `0xffffffff`；COM12 仍在枚举。两次只读结果为 `jtag_scan/20261016T105905_265475Z` 与 `20261016T105929_019078Z`。用户有万用表，已安排断电拆下板端排线后测 J12.4 A3V3 对 J12.2 GND 的直流电压；尚无电压读数，不能推断供电正常、排线导通或 FPGA 损坏。

## 时序与物理验收

RX Gray CDC 有 20 ns 延迟/skew 上界，冻结总线有 150 ns 上界；DDR 冻结总线上界 80 ns，小于 27 MHz 目的域至少约 111 ns 的稳定等待。没有用 blanket async 分组掩盖这些路径；第一同步级、异步复位和厂商 PHY 原始例外分别约束。

DDR 原始异步复位的跨域路径按 C/P 管脚逐项约束，实际本地域释放仍接受 recovery/removal 检查。厂商 phase-adjust 的 32 个原始复位端点单独审查：26 个功能寄存器在恢复初期保持复位值，6 个输入流水寄存器吸收 START/DONE；精确综合网表仿真还显示 core PLL 复位在 resetctrl 本地域释放后的 202 个 rst_clk 沿才撤销。该例外依赖固定厂商 PLL/启动协议和至少 1 ms 的外部保持，明确是复位启动协议例外，不宣称原始输入已同步释放或模拟复位安全已经签核。

最终 RX 构建为 `build/video/pds/20261016T104815_249764Z`，内部约束全部满足，40 MHz RX 域 setup WNS +6.240 ns；资源为 1970 LUT、2918 寄存器、1 DRM。最终 DDR 构建为 `build/video/pds/20261016T103600_829655Z`，内部约束全部满足，125 MHz core setup WNS +0.200 ns；资源为 6747 LUT、6816 寄存器、0 DRM。BIST 每次命令前用 17 拍填满 16 项 LUT RAM 并预取首拍，模式生成及 native 输出均有寄存级；为同 core setup 另留 0.2 ns uncertainty 实现余量，没有改变实际 125 MHz 频率。

DDR 的 `free_release* startup_done` 源寄存器例外经完整综合网表审计，只到达 core 域 405 个 C/P 复位端点，未到达 D/CE/RAM 数据端；本地域释放、握手和冻结数据仍接受定时。避免使用 PDS FSM 重编码后不能绑定的端点名称，也未放宽未知消息拒绝规则。

两套最终位流及同名 `.smsk` 已通过源码新鲜度和哈希核对后打包。外部 MS7200/MS7210 setup/hold、板级 skew 和 DDR 终端/模拟 AC 未得到完整参数签核，标志保持 false。实际串口收包、接收模式合格、DDR 校准、BIST PASS、画面观察也分别记录；JTAG 尚未恢复，因此最终下降沿 RX 和 DDR 均没有本版板测通过证据。当前未完成采集 DMA、缩放、分屏或 NPU/CPU 集成。

## 复现

```powershell
python scripts/video/run.py --suite all
python scripts/video/build_pds.py --target video_rx_board --stage bitstream
python scripts/video/package_board.py --target video_rx_board
python scripts/video/program_board.py --target video_rx_board --start-server
python scripts/video/read_board.py --port COM12 --seconds 12
python scripts/video/build_pds.py --target video_ddr_bist --stage bitstream
python scripts/video/package_board.py --target video_ddr_bist
python scripts/video/program_board.py --target video_ddr_bist --start-server
python scripts/video/read_board.py --port COM12 --seconds 12
```

独立 DDR 目标会覆盖所测内存并暂停 HDMI 输出。确认测试结果后重新下载 RX 目标恢复本地彩条/输入诊断。发布包校验源码、位流和同名 `.smsk`；失败使相应最新成功入口失效，旧包只作为历史记录保留。
