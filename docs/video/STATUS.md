# Video 工作台账

更新：2026-10-18。分支：`video/windows-bringup`。用户已确认板卡、HDMI 源和显示器已就绪；当前开发在主工程内执行，未建立第二份源码副本。

## 本批已交付

| 编号 | 工作 | 状态/证据 |
|---|---|---|
| V000 | Windows 原生工具与许可运行检查 | Icarus、PDS、ModelSim 已实际运行；见工具链记录；DDR 保护库另验 |
| V001 | 工程规则、文件目录和路线台账 | 根 AGENTS、Video README、本文件及接口/参考记录 |
| V002 | 固定模式同源定义 | JSON → RTL/C，支持生成漂移检查和非法模式拒绝 |
| V003 | 参考来源锁定与可重复提取 | HDMI 18 文件、DDR 5 文件按包及成员 SHA256 核验；未整体迁入旧应用 |
| V004 | 便携时序与 RGB888 彩条 | 两连续帧＋中途复位后一完整帧，逐像素自检 |
| V005 | PDS 组件综合 | 原彩条组件 53 LUT、21 寄存器、0 DRM；本批另有板级目标与输入监测组件 |
| V010 | 40/10 MHz PLL 和复位 | 真实厂商 GPLL 模型验证 25/100 ns 周期；外部复位、PLL 失锁及启动等待通过 |
| V011 | TX-only 初始化 | 无 RX 依赖；49 项配置、实际 ACK/超时、五种时刻复位、完整 320 ms 等待通过 |
| V012 | 板级目标/管脚与内部时序 | 37 个 bit-port 的 255 条属性与官方 FDC 一致，24 RGB 引脚与手册一致；外部 AC 参数仍待核实 |
| V013a | 彩条位流与下载包 | 307 LUT、252 寄存器、0.5 DRM；布局布线内部约束通过，.sbit 已生成并按哈希打包 |
| V013b | 实际下载/输出画面 | PG2L100H / 0x00602899；JTAG Program 和 Verify 成功，用户确认最终彩条稳定、按 KEY0 后恢复 |
| V014a | 便携输入帧几何监测 | 12 个好帧、19 个闭合间隔、7,164,199 RGB888 候选像素；尺寸/总计数/DE/控制丢失测试通过，PDS 组件综合通过 |
| V014b-prep | RX 初始化、固定 EDID、精确计时与诊断 | 串行配置、冷启动/重连/故障与复位通过；早期上升沿采样的一周期 HS 歧义已由下降沿板测关闭 |
| V014b | 统一下降沿输入采样与板测 | Program/Verify 成功；800×600、1056×628、全部同步/porch 正确，约 40.0001 MHz；恢复后连续 60 秒采集的 60 包均模式合格、坏帧为 0，用户确认彩条稳定；内部 WNS +6.240 ns，1970 LUT、2918 寄存器、1 DRM |
| V015-prep | 完整 HMIC 与独立 native 自检 | 74 个硬件源锁定、FDC/RCF 审查、8 组缩小窗口 BIST/板级数字替身与错误恢复通过；PDS 内部约束全部满足，125 MHz core WNS +0.200 ns，6747 LUT、6816 寄存器、0 DRM |
| V015a | 物理 DDR 校准、自检与 KEY0 重测 | Program/Verify 成功；低/高各 1 MiB 加哨兵的 3,014,685 个 256-bit 比较无错；KEY0 后心跳 173→1，随后 16 个新包均重新完成自检、错误码 0、全部 PLL 锁定；已恢复 RX 位流 |
| V015b-core | AXI128→HMIC256 桥核心 | core 域串行读写、上下 lane、非法 burst 排空、masked readback-before-B 和故障隔离；canonical191例、独立354例及质量复核通过；共享 fabric/CDC/跨主端排序仍待集成 |
| V020a | RGB888 打包与行式写 DMA | R/G/B 字节序、跨拍 spill、行尾 keep、stride padding、4 KiB拆分、abort/错误排空；完整 raw/preview 数字测试及独立规格/质量审查通过 |
| V020b | 合成 raw AXI/DMA物理自检与KEY0 | 完整800×600、1,440,000字节/90,000拍数字及物理读回通过；60秒完成状态无错，KEY0后heartbeat329→1、17个新PASS包；PDS125 MHz内部多角时序通过，core WNS +0.087 ns，10919 LUT、10488寄存器、0 DRM；已恢复RX、验证输入合格，用户确认稳定彩条 |
| V020c-raw | 真实HDMI单帧raw采集及KEY0 | 实采、60秒状态及同镜像JTAG重启复测通过；现场KEY0后heartbeat167→1，计数清零后45个新完成状态包合格：480000像素/1440000字节、源/DDR CRC均ebf5a8c4，无错误/overflow，FIFO峰值121/2048。已恢复RX并Verify，4个输入快照合格、坏帧0；用户确认KEY0后彩条恢复、恢复RX后彩条稳定，阶段验收完成 |
| V020d | 同帧raw/preview与共享双窗口画面恢复 | 已通过当前候选的受控验收。33e1b8242053已Program/Verify，四角图与普通桌面分别单次实体KEY0后均恢复完整；连续298包包含两个新epoch，复位后稳定约93/81秒，源/DDR CRC一致，溢出/欠载0。旧版黑帧/裁切失败保留历史；仍为按键单帧预览，不代表连续视频或任意源恢复。 |
| V020d-probe | 独立RX像素分布与启动历史诊断 | 独立目标defaa36及当时138帧组件/5解码/完整RX联合仿真、PDS和41检查/117哈希已验证。一次KEY0无时钟75秒；下一次KEY0时序合格但128/129帧CRC仍非四角图，至188才恢复，随后95秒20个取样精确匹配。已保存680条UART和单次按键绑定；支持分离HDMI与采集复位，尚非preview图像验收。后续run.py已修改，旧诊断审查保留为历史来源，不冒称当前全树审查 |
| V020d-reset | KEY0重采保留HDMI链路 | 实现0d3cf8f；26套件/122输入、最终独立84检查/882哈希无发现。第三轮选seed14，slow setup/hold +0.179/+0.066ns、fast +2.962/+0.051ns；原14组束路径和新增42端点/168路径通过。KEY0仍复位DDR/采集/显示，HDMI保持初始化。实体图像验收通过，见[当前证据](../verification/video/evidence/preview_link_reset.json)；新reset/SRL内部计时、外部AC及模拟余量仍不在签核范围。 |
| V020e-scale | 独立检测5×5缩小 | 800×600→160×120 RGB888已完成。27套件/128输入完整回归、6376总和及4突变拒绝通过；独立15帧/12非法尺寸/1350异常注入/4流水取消无发现。组件综合191 LUT、88普通FF、1 DRM、3 APM，8ns估计setup+2.370ns；无布线/板测或量化/补边/DDR。见[验证记录](../verification/video/detect_scale.md)。 |
| V020e-format | 独立BGR/补行及量化后C8 | 两组件定向与4突变拒绝通过；完整源图经明确测试量化模型写DMA的163840B逐字节一致，含末B暂停/stride/4KiB及错误响应。组件综合分别42LUT/46FF、138LUT/129FF，8ns估计setup+4.697/+3.457ns，无DRM/APM。28套件/138输入完整回归及独立审查无发现；真实模型量化与三分支正式事件未实现。见[验证记录](../verification/video/input_format.md)。 |
| V020e-handoff | 外部NPU交接审查 | 用户提供keep-s/npu_zgtc，固定4fc0fc8；167文件/五项资产哈希、241参数数组及三组合成输入哈希已核对，433项定向检查通过。已找到模型/数值/参考，但其320×320双线性居中补边、UINT8 NCHW与本工程160×128块平均/C8不同；300KiB也超出当前每输入槽256KiB。尚无NPU RTL/硬件ABI及跨master可见性验收；见[交接审查](../verification/video/npu_handoff_audit.md)。 |
| V020f-320-ref | 适配既有NPU320数值参考 | 用户已选优先迎合320×320基线，设计ef591a6。800×600→320×240双线性、上下40行零、UINT8 BGR NCHW307200B参考已实现；精确OpenCV4.11的4169764相位/水平和例（优化开关均核对）、六幅全尺寸哈希、4突变拒绝通过。独立19图/11673600字节及另一组完整相位穷尽一致，无发现；Python63项中62通过/1跳过。尚非RTL/DMA或板测，见[验证记录](../verification/video/yunet320_reference.md)。 |
| V020f-320-rtl | 固定5:2双线性RTL | 默认800×600→320×240有效RGB、同步行RAM/分步取整已实现；十组定向及六幅全尺寸OpenCV哈希、4突变拒绝通过。综合246LUT/134FF、1个DRM18K/0APM，8ns估计setup+4.025ns。29套件/145输入完整回归和独立审查通过，尚非NCHW/DMA或板测。见[验证记录](../verification/video/detect_bilinear.md)。 |

已获得P1的稳定彩条、合法HDMI输入时序、DDR校准及复位后自检证据。当前同帧raw/preview目标已通过四角图和真实桌面的两次受控实体KEY0验收；保留工作镜像33e1b8242053，串口已正常停止。旧版黑帧与裁切失败不重写为成功。检测input、正式三分支/三槽、CPU fabric、共享接口冻结、外部AC签核及连续采集仍未完成。

本轮 RX/DDR 的独立说明见 [rx_ddr_bringup.md](../verification/video/rx_ddr_bringup.md)。当前用户确认电脑活动信号为 800×600、60.32 Hz，实测 VS 原始高电平为 4224 个像素时钟、场周期 663168；没有将 HS 边沿歧义读出的 VS=3 放宽为可接受模式。最终 RX 位流 SHA256 为 `406edfee9a218bb63b61f3e8a972c671f78e6466692fa67f7666da9154dae50c`，DDR 位流为 `9617217b476b659a51923b06f3338e80b89c41d0cf981ad9436e4ed5ac6666f4`；两者已连同各自同名校验掩码打包。

上一轮JTAG恢复：17:46 后曾持续读全 1，历史脚本/低速/延迟读取均保留失败证据；18:59 重插后两次扫描仍失败。用户随后怀疑 J12 排线接触不良并要求重试，19:04 默认扫描识别到 `0x00602899`，随后 RX、DDR、恢复 RX 的三次 Program/Verify 均成功。恢复支持接触不良判断，但没有电压/导通测量定位具体接点，也没有更改驱动、系统设置或 Flash。当时恢复了下降沿 RX 镜像且用户确认稳定彩条；恢复记录为 `build/video/jtag_scan/20261016T110442_787297Z`。

本批20:10下载AXI/DMA镜像再次在器件识别前失败，默认和500 kHz扫描均找不到FPGA；当时未成功执行Program/Verify，COM12仍收到原RX包但输入模式不合格。用户再次断电重插J12两端并上电后，20:20下载和Verify成功；物理AXI/DMA初测、60秒状态监测、KEY0重测均通过。20:24恢复RX并Verify，随后5个输入快照均合格，坏帧0。本批实现、独立审查、构建和物理证据见 [axi_capture_bringup.md](../verification/video/axi_capture_bringup.md)。

## 按依赖继续实施

| 编号 | 下一项 | 依赖与完成条件 |
|---|---|---|
| V012b | 外部 HDMI AC 时序核实 | 缺 MS7210 采样沿/setup/hold 与板级 skew，不能以内部时序通过替代 |
| V013c | 输出板测补全 | 已有恢复后 60 秒串口记录及用户稳定彩条观察；补显示器模式/LED、照片或录像及更长持续运行记录 |
| V014c | RX 热插拔与长时输入 | 本版固定输入已实测合格；后续扩展拔插/停源、整链路恢复和更长稳定性证据 |
| V015b-integration | AXI桥共享接入 | 核心及独立AXI/DMA物理自检、KEY0已通过；接入CPU fabric/CDC，验证跨主端写后读、在途复位及带宽 |
| V020 | 检测input与正式三分支采集 | V020d的受控KEY0画面恢复已通过；下一步冻结检测input的量化/布局参考，继续检测input、三分支CAPTURE_DONE、正式帧地址/槽状态/提交契约，再扩展连续采集。 |
| V020e-input | 320输入RTL与正式输入集成 | 用户已选320路线，精确整数参考及有效RGB双线性RTL已验收；下一步实现BGR/上下40行和NCHW/DMA，并统一迁移公共配置及300KiB输入槽。需最终源图/golden和CPU共同地址/版本/完成契约；三分支与板测仍单列。 |
| V030 | 检测预处理＋人工框/头像 | NPU 量化清单、素材清单；真实张量与像素参考一致 |
| V040 | 三槽/CDC/压力与错误恢复 | 延迟/相位扫描、在途读写及释放 ACK、实际模拟 NPU DDR 流量 |
| V050 | CPU/Video/NPU 两两集成 | 对应路线接口与可运行产物 |
| V060 | 真实演示与优化 | 10 分钟功能、30 分钟优化稳定性；实际有效 fps/延迟分别报告 |

## 尚未关闭的共同契约

- CPU＋Video：MMIO 详细位定义、事件保持/W1C、提交记录锁存点、旧槽释放、fabric 仲裁和写后读可见性。
- NPU＋Video：用户已选适配外部4fc0fc8的320×320 UINT8 NCHW；精确OpenCV4.11数值参考已落地，后续匹配最终源图/golden并接RTL/DMA。输入槽候选320KiB/槽须经CPU公共地址配置统一实施，当前板级入口尚未迁移。
- CPU＋Video：头像锚点、目标矩形和边界规则；三帧槽最坏生命周期证据。

## 本轮硬件连接观察

2026-10-16 初次仅 COM1；用户连接并上电后，识别 USB Cable II、COM12 CP210x、COM9/COM11 FTDI，驱动状态 OK。最初 JTAG 出现 JtagServer-0306、原始 ID 全 `0xFFFFFFFF`。用户确认电源灯亮、J12 排线接好并断电重插。之后使用历史成功的原始只读 Tcl 恢复识别，当时默认扫描脚本也通过。尚未确认初次失败的根因；后续再次失败的当前状态见上文，不能归因为 CPU 下载损坏板卡或单独认定脚本/频率设置有误。

TX-only 彩条验收记录：`build/video/board_program/20261016T082259_109276Z`，Program/Verify 均成功，无 Flash 写入；用户确认彩条稳定，短按 KEY0 后恢复。显示器 OSD、LED、照片/录像与连续时长尚未记录。该历史位流 SHA256 为 `925da96138681fdcc2e1f18739d3a8d931a81f65f34d3972ed8c98bad17f9290`。初次打包遗漏 Verify 必需的同名 `.smsk` 已修复，打包现在核对其哈希并带入发布目录，缺失/损坏回归通过。扫描入口为 `build/video/latest_jtag_scan.json`；临时 server 只结束自身进程。DONE 为配置状态，本次未确认独立 DONE 灯的存在或位置。

首批 11 项 Python 测试的记录保留在 `windows_kickoff.json`；TX-only 批次的 19 项记录保留在 `board_smoke.json`。RX/DDR 批次完整回归 `build/video/regression/20261016T104805_104909Z` 已通过：33 项 Python 测试中 32 通过、1 项 Windows 符号链接权限相关跳过；串行 RX 初始化、精确测量/探针、CDC/UART、RX 板级集成、8 组 native BIST 和 DDR 板级数字替身均通过。当前完整回归原始结果入口为 `build/video/latest_all.json`，本批摘要见 `docs/verification/video/evidence/rx_ddr_bringup.json`。

提交管理：基础提交为 `84b8d69`，彩条基线为 `16556d1`，RX/DDR 实现为 `cd5ee08 feat(video): add HDMI RX diagnostics and standalone DDR BIST`。本批补记恢复后的物理板测结果，仅提交 Video 文档与证据；技术报告已有修改保留，未推送或合并到 main。验证摘要与源码哈希绑定，提交号以 `git log` 为准。

## AXI/DMA 本批交付记录

最终完整回归 `build/video/regression/20261016T120334_259053Z` 通过，35项Python测试中34项通过、1项Windows符号链接权限跳过；新增桥、packer/DMA、四种几何端到端测试及AXI板级数字替身均纳入，原RX/native DDR等套件同时通过。完整800×600检查1,440,000字节、90,000拍；独立物理结果另由实际Program/Verify和UART证明，未混同数字IP替身。

首轮布线core WNS −0.195 ns，因读回比较进入写选通组合路径；仅按互斥读写阶段等价拆分写掩码故障条件，保留所有响应/故障语义。两组四态等价测试、当前哈希桥质量复核通过；最终125 MHz WNS +0.087 ns，约束原样保留。包为 `build/video/releases/video_axi_capture_f1535f12e7d3`，位流SHA256 `f1535f12e7d3ce07fa3c144122e1d31b6fa460ae13f6a97eec44304f90315328`。

独立RX恢复包为 `build/video/releases/video_rx_board_46d80ec8eed2`，按当前构建脚本重新生成，已在本轮完成Program/Verify和模式复验。机器可读摘要为 `docs/verification/video/evidence/axi_capture_bringup.json`；历史 `rx_ddr_bringup.json` 保持历史证据，不重标为当前源验证。软件实现提交 `c928706`；只提交本批Video变更，保持当前分支，不push。

## HDMI raw 单帧本批收尾状态

实现提交为 `27960cb`（引擎）、`61d3a07`（写缓存等价故障条件）、`22bfb22`（联合板级工程及脚本）、`86aed0d`（读回专用故障与写控制分离）。最终18套件回归、PDS和独立审计均绑定当前源码；125MHz slow setup余量+0.233ns，12043 LUT、12174寄存器、4 DRM，原约束未放宽。保留本地分支，未push。

2026-10-17用户恢复800×600源后，采帧包 `video_hdmi_capture_2e01feb8e69d` 已实际Program/Verify；首帧和60秒状态通过，CRC5c1e6651。当时用户远程无法按KEY0，先以同镜像JTAG重新配置作自动重启测试：heartbeat757→1，新帧CRC8aa54beb，45个新的完成包全部合格；该记录与后续实体KEY0补验分开。

用户随后到场，重新安装同一采帧位流后短按KEY0。`build/video/board_serial/20261017T012418_613147Z` 记录heartbeat167→1，复位后首包busy、未完成、计数清零，随后45个完成状态包报告同一新帧：480000像素、1440000字节、源/DDR CRC均ebf5a8c4，FIFO峰值121/2048，无错误/overflow。用户确认KEY0后彩条恢复。观察区间无JTAG编程，实体按键重采验收已完成。

该轮 `build/video/board_program/20261017T012531_400691Z` 已恢复 `video_rx_board_26d25f7dd060` 并Verify，`build/video/board_serial/20261017T012551_557951Z` 的4个快照模式合格、坏帧0；用户确认重新出现稳定彩条。raw单帧阶段的现场待验项已全部关闭。该轮验收范围为raw单平面；后续共享preview/捕获内容显示的验收见V020d，检测input、三分支CAPTURE_DONE和共享CPU fabric仍未实现。

物理汇总见 [hdmi_raw_capture.json](../verification/video/evidence/hdmi_raw_capture.json)，现场补验见 [hdmi_raw_capture_key0.json](../verification/video/evidence/hdmi_raw_capture_key0.json)，详细结果见 [hdmi_raw_capture.md](../verification/video/hdmi_raw_capture.md)。[hdmi_raw_capture_preboard.json](../verification/video/evidence/hdmi_raw_capture_preboard.json) 保留为前一天上板前的历史状态，不重写或混作当前物理结论。
