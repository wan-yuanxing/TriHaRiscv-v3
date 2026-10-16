# Video RX 与 DDR 板测实施计划

> **For agentic workers:** Use superpowers:subagent-driven-development；实现任务依次推进，来源/约束审计可并行。用户已批准 Video 总路线并要求继续下一阶段，本文件细化原计划 P1 的 V014b/V015，不新增整机功能承诺。

**Goal:** 在已验证的彩条基础上得到真实 HDMI 输入时序和 DDR 校准/自检证据。两项独立报告，不以串口日志、仿真或初始化完成替代另一项。

**Architecture:** TX 先初始化并保持本地彩条；共享 I²C 随后交给 RX，接收端使用官方配置顺序和固定模式 EDID。输入时序在像素域测量，频率以 27 MHz 时基测量，快照经握手 CDC 后由独立诊断 UART 输出。DDR 使用官方 HMIC/PHY 和真实 125 MHz 参考，先在独立板测顶层执行 native 自检；正式 AXI128/fabric 及多主端可见性留在其契约任务。

**Tech Stack:** Windows PowerShell/Python、Icarus、PDS、官方 MS7200/MS7210 与 HMIC_S 参考，串口使用 Windows 原生接口。

## 文件与分工

- `fpga/pg2l100h/rtl/hdmi_rx_init.sv`：接收配置、连接探测与可观测错误；厂商原文件不修改。
- `config/video_edid.hex`、`scripts/video/gen_edid.py`：固定 800×600 EDID 与独立解析/校验。
- `rtl/video/video_rx_measure.sv`：完整同步脉宽/porch 与像素计数，兼容已有 `video_rx` 候选帧契约。
- `fpga/pg2l100h/rtl/video_diag_uart.sv`：周期性、整包锁存的诊断快照和 UART 8N1。
- `fpga/pg2l100h/rtl/video_rx_board_top.sv`、对应 project/FDC：TX 基线与实际 RX；源不支持目标模式时保持彩条并报告。
- `scripts/video/read_board.py`：Windows 串口读取及可机器解析结果；明确 COM 选择，不猜测其他设备。
- `fpga/pg2l100h/ip/video_ddr_manifest.json`、`scripts/video/gen_ddr.py`：完整官方 IP 的文件哈希、约束重绑定与生成/提取证据。
- `rtl/video/ddr_native_bist.sv`、`fpga/pg2l100h/rtl/video_ddr_bist_top.sv`、对应 project/FDC/RCF：校准后 native 写读、掩码、地址与数据模式自检。
- 对应测试位于 `tb/video/`；新增套件/目标接入原入口，日志和 IP 副本全部进入 `build/video/`。

## Task 1：来源与实际参数

- [x] 审计 MS7200 的 boot、EDID、频率状态轮询与重连，列出不能从原文确认的寄存器语义。
- [x] 审计完整 DDR IP、125 MHz 输入、容量、native 接纳时序及 PHY 反馈/约束实例层次。
- [x] 对照原手册提取新增 RX/串口/DDR 管脚，逐属性核验。
- [x] 记录可重复命令和测试范围；既有彩条提交 `16556d1` 可恢复。

## Task 2：可测量的 RX 板级链路

- [x] 先写 EDID 解析测试：128 字节校验、首选 40 MHz/800/256/600/28、正同步、没有多余高分辨率广告，再实现生成器。
- [x] 先写串行 RX 模型与测试，覆盖正确配置/读回、无源等待、NACK、坏探测、启动/中途复位和源重连，再实现 RX wrapper。
- [x] 测试完整帧时序、错同步脉宽/porch、停钟与恢复；像素域不能自己证明时钟为 40 MHz。
- [x] UART 测试逐 bit 解码、包内一致性和复位；频率计量使用独立参考时基并标明容差。
- [x] TX 先完成后 RX 使用共享 I²C；无源、坏模式、RX 初始化失败时 TX 彩条继续。
- [x] 完成仿真、下降沿采样集成测试和 PDS 内部时序；外部 AC 未签核。
- [x] 最终下降沿位流 Program/Verify、实际串口输入参数与完整模式验收；恢复后 60 秒/60 包均合格、坏帧 0，用户确认稳定彩条。

## Task 3：独立 DDR 校准与 native 自检

- [x] 完整依赖和约束 staging 先验证所有哈希/层次，再综合，不整体复用旧 warning 白名单。
- [x] BIST 模型先验证背压、无 WVALID 的 native 数据节拍、不能背压的返回、超时与错误保持。
- [x] 自检覆盖受验证访问窗口的首尾、各地址位、字节掩码、交替和确定性伪随机模式；读命令在写接纳后的实际读回给出证据。
- [x] 初始化前禁止访问；失锁或重新校准中止并协调重启，不能仅清状态宣称旧事务消失。
- [x] 完成 ModelSim 保护库可用性核验和 PDS/约束审查：库编译/展开成功，运行被厂商 GPLL 除零中止；真实训练仿真未通过。PDS 内部约束全部满足，125 MHz core WNS +0.200 ns。
- [x] 实际校准/自检/KEY0 复位后重测通过：每轮 3,014,685 个 256-bit 比较，错误码 0；心跳 173→1 后 16 个新包全部 PASS。独立 native BIST 不宣称 AXI128 或跨主端排序已验证。

## Task 4：审查与交付

- [x] 实现后先做规格审查，再做代码质量审查，修复后复核。
- [x] 跑当前已实现套件，核对源码、IP、位流和校验掩码哈希；最终完整回归 `20261016T104805_104909Z` 通过，33 项 Python 测试中 32 通过、1 项权限相关跳过。
- [x] 更新 STATUS、接口、来源记录与小型证据摘要；提交范围仅 Video 文件及原始 RCF 换行保护规则，保留技术报告已有修改。
- [x] 分别报告 RX/DDR 的仿真、综合、内部时序与实际板测状态；JTAG 恢复后本版 RX 模式和物理 DDR/KEY0 自检均通过，外部 AC 与训练仿真仍保持未签核/未通过。
