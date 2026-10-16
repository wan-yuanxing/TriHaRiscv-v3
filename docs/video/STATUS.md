# Video 工作台账

更新：2026-10-16。分支：`video/windows-bringup`。用户已确认板卡、HDMI 源和显示器已就绪；当前开发在主工程内执行，未建立第二份源码副本。

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

已完成 P0 工程基础、P1 的输出彩条上板及部分输入监测准备。**P0/P1 尚未整体验收通过：输出已有本版画面与下载校验证据，物理输入、DDR 自检仍无本版板测结果。**

## 按依赖继续实施

| 编号 | 下一项 | 依赖与完成条件 |
|---|---|---|
| V012b | 外部 HDMI AC 时序核实 | 缺 MS7210 采样沿/setup/hold 与板级 skew，不能以内部时序通过替代 |
| V013c | 输出板测补全 | 补记显示器模式/LED、照片或录像及持续运行时长；用户口头观察不能代替时长测量 |
| V014b | 物理 RX 初始化与频率/模式确认 | 接收初始化、固定源/EDID、实际像素频率与同步脉宽/porch；便携几何监测不能替代物理确认 |
| V015 | DDR 自检与完整 wrapper | 完整 IP 依赖、校准、125 MHz 参考、真实 BIST、错误与复位；跨主端写后读语义先明确 |
| V020 | 原图/preview DMA＋双窗口 | 正式帧地址/请求/提交契约，逐像素参考、行缓存复用与板测 |
| V030 | 检测预处理＋人工框/头像 | NPU 量化清单、素材清单；真实张量与像素参考一致 |
| V040 | 三槽/CDC/压力与错误恢复 | 延迟/相位扫描、在途读写及释放 ACK、实际模拟 NPU DDR 流量 |
| V050 | CPU/Video/NPU 两两集成 | 对应路线接口与可运行产物 |
| V060 | 真实演示与优化 | 10 分钟功能、30 分钟优化稳定性；实际有效 fps/延迟分别报告 |

## 尚未关闭的共同契约

- CPU＋Video：MMIO 详细位定义、事件保持/W1C、提交记录锁存点、旧槽释放、fabric 仲裁和写后读可见性。
- NPU＋Video：固定 YuNet 输入量化、饱和/舍入、物理布局版本与参考张量。当前配置只记录格式，不编造量化尺度。
- CPU＋Video：头像锚点、目标矩形和边界规则；三帧槽最坏生命周期证据。

## 本轮硬件连接观察

2026-10-16 初次仅 COM1；用户连接并上电后，识别 USB Cable II、COM12 CP210x、COM9/COM11 FTDI，驱动状态 OK。最初 JTAG 出现 JtagServer-0306、原始 ID 全 `0xFFFFFFFF`。用户确认电源灯亮、J12 排线接好并断电重插。之后使用历史成功的原始只读 Tcl 恢复识别，当前默认扫描脚本同样通过。尚未确认初次失败的根因，不能归因为 CPU 下载损坏板卡或单独认定脚本/频率设置有误。

最终下载记录：`build/video/board_program/20261016T082259_109276Z`，Program/Verify 均成功，无 Flash 写入；用户确认最终彩条稳定，短按 KEY0 后恢复。显示器 OSD、LED、照片/录像与连续时长尚未记录。当前位流 SHA256 为 `925da96138681fdcc2e1f18739d3a8d931a81f65f34d3972ed8c98bad17f9290`。初次打包遗漏 Verify 必需的同名 `.smsk` 已修复，打包现在核对其哈希并带入发布目录，缺失/损坏回归通过。最新扫描在 `build/video/jtag_scan/20261016T082422_246743Z`，入口为 `build/video/latest_jtag_scan.json`。临时 server 只结束自身进程。DONE 为配置状态，本次未确认独立 DONE 灯的存在或位置。

首批 11 项 Python 测试的记录保留在 `windows_kickoff.json`；本批扩展为 19 项，18 项通过、符号链接权限相关 1 项跳过。当前各套件包括 timing、clocks、tx_init、board、rx；完整 WAIT 另外运行。原始结果在 `build/video/latest_all.json`，本批小型摘要见 `docs/verification/video/evidence/board_smoke.json`。

提交管理：基础提交为 `84b8d69 feat(video): establish native Windows bring-up baseline`。本批提交名为 `feat(video): add HDMI board smoke build and RX frame monitor`，仅包含 Video 文件；技术报告已有修改保留，未推送或合并到 main。验证摘要与源码哈希绑定，提交号以 `git log` 为准。
