# Video 路线 Implementation Plan

> **For agentic workers:** Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 本文是路线与交付计划；本次仅规划，未开始迁移或实现 RTL。

2026-10-16 后续实施已启动；以上为制定计划时的状态。实时完成情况与证据统一维护在 [Video 工作台账](../../video/STATUS.md)，本文件保留原路线与验收条件。

**Goal:** 在 PG2L100H-6IFBG676 上实现 v0.6 的固定 HDMI 输入、三分支采集、同帧分屏及头像叠加，并交付可与 CPU/NPU 集成的 Video 子系统。

**Architecture:** 筛选复用厂商 HDMI/DDR IP 和旧工程通用传输模块，按 v0.6 实现 RGB888、两种固定缩放、共享预览、显示叠加及帧握手。采用独立板测顶层尽早点亮硬件；CPU/NPU 尚未接入时使用遵守正式协议的控制与结果测试模型。

**Tech Stack:** SystemVerilog/Verilog、Python 整数参考与回归、Icarus Verilog、PDS、厂商 HDMI/DDR/PLL IP；Verilator 与厂商加密 IP 仿真工具在工具盘点后决定实际入口。

---

## 1. 依据与当前状态

- 日期：2026-10-16。
- 用户已确认：开发板、HDMI 源和显示器已就绪，优先尽快上板。
- 权威规格：`docs/TriHaRiscv_SoC_Design_Spec_v0.6.md`，重点为第 3、4、6.3、8–15、18 节。
- 规格 SHA-256：`02b6b33d6ee0b5c72ff73220a167058b3e29f0a654b3b91415a9488228dcd0c5`。
- 总工程参考提交：`1be9301`。当前实现目录只有骨架，无统一硬件构建/回归入口。
- `docs/technical-report/` 已有未提交修改；本计划新增独立文件，不改变这些内容。
- 本机 PATH 已发现 `D:/iverilog/bin/iverilog.exe` 和 `D:/miniconda3/python.exe`；尚未验证版本、PDS 路径、下载器及仿真许可。
- 旧工程文档记录了组件级验证，但本轮没有重跑这些测试，也没有执行综合、下载或板测。

本计划中的新文件名和命令是拟建立的交付接口，不代表已经存在。v0.6 已固定的功能直接沿用；寄存器详细打包、模型量化参数、板卡实际版本等由对应任务形成有证据的冻结记录。

## 2. 选择的实施方式

| 方式 | 收益与代价 | 选择 |
|---|---|---|
| 筛选复用底层模块，重建 v0.6 数据路径与帧协议 | 利用已有 DDR/CDC 经验，又能消除 RGB565、旧地址及旧应用假设；每项复用重新验收 | 推荐 |
| 整体搬入旧视频应用再修改 | 看似接线少，但旧 1080p/RGB565、双缓冲/快照和 YOLO 配置会混入新工程 | 不采用 |
| 所有模块从头编写 | 边界可控，但重写厂商封装、DDR 桥与基础 CDC 会延后板测 | 仅对不兼容的像素、控制模块采用 |

优先顺序是“板上固定模式可见 → 板上同源双窗口 → 人工框和头像 → 完整采集/所有权 → 两两集成 → 真实整机与优化”。接口和帧所有权从第一批就设计；所有权压力验收放在后续独立节点，不等同于后补协议。

## 3. 固定边界

| 项目 | 实现目标 |
|---|---|
| 视频 | 一入一出、RGB888、800×600；40 MHz，1056×628，总扫描率约 60.3165 Hz |
| 左右窗口 | `(0,150)`、`(400,150)` 起各 400×300；均显示完整场景的同一份缩小图 |
| 采集 | 每个接纳帧同时产生 raw、preview、input；三分支成功完成后发布就绪 |
| 显示缩放 | 2×2 块平均，`floor((sum+2)/4)` |
| 检测缩放 | 5×5 块平均，`floor((sum+12)/25)`；160×120，底部补 8 行 |
| 检测输入 | BGR，有效 C3、物理 C8、INT8；量化尺度、舍入、饱和及量化零值由 NPU 的模型清单定义 |
| 帧存储 | 三槽，各 2 MiB；raw 偏移 0，preview 偏移 `0x160000`；输入张量独立分槽 |
| 叠加 | 左侧最多 16 框、可关闭的五点调试；右侧一个 256×256 RGBA8888 预设头像 |
| 贴图数值 | 最近邻、非预乘 Alpha；`floor((a*fg+(255-a)*bg+127)/255)` |
| 总线 | 32 bit AXI4-Lite 控制；逻辑 128 bit AXI4 DMA，INCR、最多 16 beat，4 KiB 拆分；首版每主端读/写各最多一个未完成事务 |
| 所有权 | CPU 维护统一帧状态和整图调度；Video 提供采集、提交、释放、错误事件与实际访问保护 |
| 性能 | 固定扫描必须连续；真实有效输出 ≥24 fps 为优化目标，30 fps 不作硬门槛或限速 |

Video 不实现 YuNet 推理、框解码/NMS、主人脸选择或表情分类。CPU 生成坐标和头像目标矩形，Video 执行像素工作。首轮人工结果仅作为开发测试，不能记作真实推理演示。

## 4. 复用清单与准入

| 来源 | 可复用内容 | 迁入前必须完成 |
|---|---|---|
| `D:/FPGA/TriHaRiscv-v3/targets/pango676/ddr/` | `axi128_hmic256.sv`、CDC/复位模块、契约及测试思路 | 来源提交/逐文件哈希；标准 AXI 子集、错误、RAW 可见性、复位语义回归；评估 mailbox 吞吐 |
| `D:/FPGA/TriHaRiscv-v3/targets/pango676/video/` | 像素 CDC、帧引用保护、固定扫描、背压/错误测试方法 | 逐项删除旧格式、旧布局、快照用途假设；不直接沿用双缓冲分配器 |
| `D:/FPGA/TriHaRiscv-v3/targets/pango676/video/hdmi/` | 厂商来源清单、MS7200/MS7210 配置线索 | 现有 `profile.json` 为 1920×1080/148.5 MHz/RGB565；重做本版模式配置；输入保留完整 RGB888 |
| 板卡资料 `2_Demo/2_10_hdmi_loop.rar`、`4_12_HDMI_IN_DDR3_HDMI_OUT.rar` | 接收/发送配置、接口与管脚参考 | 核对实物版本、芯片、有效电平、40 MHz 模式与外部 I/O 时序 |
| 板卡资料 `2_Demo/2_9_ddr3_test.rar` | 目标 FBG676 的 DDR IP、校准、自检、物理约束 | 核对 IP/器件版本，保留 PHY/PLL 反馈与 RCF；纠正来源中相互矛盾的约束 |

旧 DDR 文档记载：所选 HMIC_S 为 256 bit 用户数据、字地址，且无 WVALID、RREADY、标准 B 通道。合成的 AXI OKAY 只能表达契约规定的完成点，不能据此宣称物理 DDR 错误检测或写后跨主端可见性已经成立。

厂商包保留来源、通知和哈希，按其分发条件组织本地生成；不整体迁入旧 build 或生成网表。旧 FMC 示例存在器件封装元数据不一致记录，不能仅凭名称选择 IP。

## 5. 数据流、模块与文件归属

```text
HDMI RX / 输入像素域
  → 合法模式检查、完整帧接纳、frame_id
  ├─ raw RGB888 ───────────────┐
  ├─ 2×2 平均 → preview ──────┼→ FIFO/CDC → capture DMA → 对应 DDR 槽
  └─ 5×5 平均 → BGR/C8/量化 ─┘                         ↓
                                                 CAPTURE_DONE

CPU 提交同帧显示记录 → 影子记录/跨域握手 → 输出帧边界原子锁存
  DDR preview → 乒乓行缓存 → 左：框/关键点 ──┐
                          → 右：头像/Alpha ──┼→ 背景/状态合成 → HDMI TX
  DDR avatar  → 素材行预取缓存 ──────────────┘
  旧显示引用全部结束 → DISPLAY_RELEASE_ACK
```

下列均为候选新增文件；共享文件由主责发布，Video 不另建与 CPU 互连并存的正式仲裁器。

| 文件 | 责任 |
|---|---|
| `config/video_cfg.json`、`config/video_regs.json` | 固定时序、格式、视频 ABI 权威定义；引用 CPU 的地址表和 NPU 清单 |
| `scripts/video/gen_config.py` | 校验配置，生成 `rtl/video/include/` 与 `sw/include/` 的一致定义 |
| `docs/interfaces/video.md`、`ddr_wrapper.md` | 记录、事件、地址/字节序、错误/恢复、DDR 可见性契约 |
| `fpga/pg2l100h/rtl/hdmi_wrapper.sv`、`ddr_wrapper.sv`、`video_clock_reset.sv` | 板级 IP、时钟复位、标准边界封装 |
| `fpga/pg2l100h/rtl/video_board_smoke_top.sv`、`video_demo_top.sv` | 独立板测顶层；共用正式功能模块，测试控制源可替换 |
| `fpga/pg2l100h/constraints/video_io.fdc`、`video_cdc.fdc` | 像素 I/O、跨域及对应实例约束；DDR 约束单列并校核层级 |
| `rtl/video/video_timing.sv`、`video_rx.sv` | 输出扫描；输入宽高/同步验证及帧边界接纳 |
| `rtl/video/preview_downscale.sv`、`detect_downscale.sv`、`input_pack_quant.sv` | 两种平均、补边、量化及 C8 布局 |
| `rtl/video/capture_dma.sv`、`capture_control.sv` | 三流打包/写入、写响应汇合、失败帧排空 |
| `rtl/video/preview_reader.sv`、`preview_linebuf.sv` | 每行 DDR 读取一次，左右复用，乒乓预取 |
| `rtl/video/box_overlay.sv`、`avatar_reader.sv`、`avatar_blend.sv`、`video_compositor.sv` | 框/点、素材预取、最近邻/Alpha、背景及同步对齐 |
| `rtl/video/video_regs.sv`、`display_commit.sv`、`video_events.sv` | MMIO、记录快照、提交/释放/错误、时间戳与计数 |
| `tb/video/reference.py`、`test_reference.py` | 独立整数像素参考与数学边界测试 |
| `tb/video/models/axi_memory.sv`、`video_control_bfm.sv`、`npu_traffic_bfm.sv` | 可背压/报错内存、正式控制协议驱动、实际模拟 DDR 流量 |
| `tb/video/tb_timing.sv`、`tb_preprocess.sv`、`tb_compositor.sv`、`tb_frame_protocol.sv`、`tb_video_stress.sv` | 各层自校验回归 |
| `assets/avatars/avatar_manifest.json`、`scripts/video/convert_avatar.py` | 至少一张合法来源头像、转换、锚点、校验及版本 |
| `scripts/video/run.py`、`build_pds.py`、`summarize_events.py` | 仿真、构建、帧事件/延迟汇总入口 |
| `docs/verification/video/` | 迁入准入、工具记录、板测步骤及可追溯证据索引 |

通用 AXI/CDC 模块复用位置在 P0 与 CPU 主责对齐；依赖 filelist 列出唯一实现。Video 可提供驱动示例与测试固件，正式 `sw/drivers/`、`sw/runtime/` 由 CPU 路线维护。

## 6. 分阶段任务与验收

### P0：最小板测基线与接口骨架

**目的：** 形成第一份可复现的板级构建，同时让后续像素开发有稳定边界。P0 的板级部分完成即可进入 P1，不等待完整模型包。

**文件：** `docs/verification/video/source_inventory.md`、`toolchain.md`；两份接口文档；`config/video_cfg.json`、`video_regs.json`；配置/构建/回归脚本与独立顶层 filelist。

- [ ] 核对实际板卡、底板版本、收发芯片、DDR/引脚/电平/时钟、下载器、PDS 与串口；记录实物与资料的对应关系。
- [ ] 建立来源清单，标明“直接复用、适配、重写”，为候选模块先重跑相关旧测试。
- [ ] 固定 800×600 时序、RGB888 字节顺序与步长，引用规格地址；JSON 生成 RTL/C 定义并检测生成文件漂移。
- [ ] 与 CPU 对齐采集请求、显示提交接纳、实际提交、旧槽释放四个不同确认点；冻结错误和复位值、W1C、忙时写入及版本检查。
- [ ] 与 NPU 明确量化参数清单和测试向量交付要求；缺少真实量化参数时仅验证缩放/布局及显式测试配置。
- [ ] 建立 `video_board_smoke_top` 的编译/综合入口，生成物进入 `build/`；选定正式下载方式并记录准确命令。

**通过条件：** 一个命令可构建最小板测设计；板卡/IP 来源可追溯；采集/提交/释放协议可被测试驱动明确执行。模型清单未交付不阻塞 P1/P2 和显示功能。

### P1：尽快获得第一份板上证据

**目的：** 先验证最可能阻塞整个路线的物理链路。

**文件：** HDMI/DDR/clock-reset wrappers、`video_timing.sv`、`video_rx.sv`、板测顶层、FDC/IP 清单、`tb_timing.sv`。

- [ ] 仿真检查 1056×628 总计数、800×600 有效区、正 HS/VS 极性及复位后恢复。
- [ ] 输出固定彩条/网格，生成 40 MHz 输出像素时钟，完成 HDMI 初始化并上板观察。
- [ ] 接入视频源，测有效宽高、总行/场长、实际像素时钟、DE/同步极性与锁定状态；发现非目标模式则报告，拒绝采集。
- [ ] 独立运行 DDR 校准与读写自检，包括可访问窗口首尾、字节掩码、地址线、交替/伪随机数据和复位后重测。
- [ ] 输出端在 DDR 未就绪时继续本地背景；记录失败状态，不触发未知地址访问。
- [ ] 保存 bitstream/源码/IP 配置标识、PDS 时序/资源结果、UART/调试计数与画面照片。

**通过条件：** 板上稳定显示目标彩条；接收计数证明输入为目标模式；DDR 自检无错误。三项单独记结果，任一失败定位在此层，避免混入 NPU 问题。

### P2：RGB888 采集、共享预览与同源双窗口

**目的：** 第二个可见交付是板上两幅同一完整场景。显示可先用无框测试结果；协议始终采用正式影子提交/释放。

**文件：** `preview_downscale.sv`、`capture_dma.sv`、`capture_control.sv`、`preview_reader.sv`、`preview_linebuf.sv`、`display_commit.sv`、像素参考/测试模型及 `video_demo_top.sv`。

- [ ] 建立已知彩块、灰阶、坐标编码及带 frame_id 图样的 RGB888 参考图。
- [ ] 用水平成组累加加行间累加实现 2×2 平均；全图逐字节核对，包含首末行列及取整边界。
- [ ] 从合法 SOF 接纳完整帧，写 raw 与 preview；实现 RGB 字节流到 128 bit 的打包、WSTRB、burst 和 4 KiB 边界处理。
- [ ] 显示每行读 400 像素至乒乓缓存，左/右各消费一次；右侧结束之前不覆盖该行缓存。
- [ ] 预览地址和 frame_id 仅在输出帧边界切换；在三槽框架下先用按需串行请求验证，再启用重叠。
- [ ] 上板显示两个 400×300 完整视图，四角标记、像素转储与 frame_id 检查共同验证比例、同源、同帧。

**通过条件：** 双窗口位置/比例正确、颜色无 RGB565 截断、输出连续、preview 每行仅一次 DDR 读取、无帧中切换。

**阶段边界：** 检测分支尚未接入时，测试顶层只报告 raw/preview 测试完成，不发布正式 `CAPTURE_DONE/INPUT_READY`，不宣称完整三分支接口已通过。

### P3：检测预处理与人工框/头像

**目的：** 在不依赖真实推理的条件下，完成 Video 的像素功能。

**文件：** `detect_downscale.sv`、`input_pack_quant.sv`、box/avatar/compositor 模块、头像转换与清单、`tb_preprocess.sv`、`tb_compositor.sv`。

- [ ] 建立 5×5 精确平均；累加至少覆盖 0..6375，校验所有可能的 sum 对常数除法/舍入的结果。
- [ ] 实现 BGR、底部 8 行、C8 布局、量化零值；获得真实模型清单后对实际输入张量逐字节比较。测试量化配置须与产品配置区分。
- [ ] 三分支汇合：像素/尺寸合法且全部写成功后，统一发出 `CAPTURE_DONE/INPUT_READY`。
- [ ] 框采用左闭右开范围、左上 floor/右下 ceil 后裁剪；CPU 负责坐标生成，Video 校验范围并绘制最多 16 框和可关闭关键点。
- [ ] 转换至少一张 256×256 RGBA8888 非预乘素材；清单记录来源、许可、锚点、行步长、长度与哈希。
- [ ] 实现素材行预取、最近邻和 Alpha 流水；源坐标依据未裁剪目标矩形计算，四边裁剪不改变缩放比例。
- [ ] 延迟对齐 RGB、HS/VS/DE、窗口标志和帧标识；上板验证边缘头像、透明/不透明区域、多人框与无脸帧。

**通过条件：** 软件参考与 RTL 像素一致；alpha=0/255 精确通过；无脸关闭头像；人工框与头像跟随各自采集帧。该节点可交付“Video 独立演示版”，标签明确人工结果。

### P4：三槽、所有权、CDC 与错误恢复

**目的：** 证明并发运行不会读写覆盖或贴错帧。

**文件：** 完整 `video_regs.sv`、`display_commit.sv`、`video_events.sv`；捕获/显示 DMA 错误路径；`tb_frame_protocol.sv`、`tb_video_stress.sv`。

- [ ] 使用与 CPU 相同的 FREE/CAPTURING/READY/PROCESSING/READY_DISPLAY/DISPLAYING/RETIRING/INVALID 流程，Video 只管理自己实际持有的引用与握手。
- [ ] 请求接纳时锁存整条记录；配置、地址、frame_id 及参数在 ACK 前不可被另一请求覆盖。首版限制一个待处理提交，忙时返回明确状态。
- [ ] 原子提交 preview、框、头像、状态与 frame_id；提交确认不提前等价为释放确认。
- [ ] 按旧槽追踪在途读、预取、FIFO/行缓存引用，全部清除后发布带旧 frame_id/槽号的 `DISPLAY_RELEASE_ACK`。
- [ ] 扫描输入/输出频率差、相位、异步复位释放与停钟；多位记录经稳定握手/异步 FIFO 传递。
- [ ] 用 5/10/15/20/25/35/40/45/60 ms 及抖动处理模型压测，同时生成模拟 NPU 的实际 AXI DDR 流量。
- [ ] 覆盖下一帧 READY、当前图算子间暂停；验证测试控制模型不把单算子空闲当作整图可换帧。
- [ ] 注入最后写响应延迟、SLVERR/DECERR、FIFO 溢出/欠载、输入丢锁、坏尺寸、过期事件、重复提交、未完成事务时复位。
- [ ] 异常帧作废并排空，未确认安全不复用槽；恢复可采用协调的整机重初始化。

**通过条件：** 任意已接纳/正在显示的记录不被改写；释放严格晚于最后引用；慢处理只造成有记录的整帧跳过/旧帧重显；正常压力配置下无欠载、无错帧、无非法访问。

## 7. P0 必须落实的协议细节

以下不是可拖到最终联调才讨论的细节：

1. **采集与丢帧：** HDMI 不支持被 NPU 停顿。只在帧边界决定接纳；途中溢出或模式变化则整帧 INVALID，停止该帧后续生成、排空已发事务，不发布成功就绪。
2. **请求记录生命周期：** 请求接纳、像素帧接纳和写完成分别报告；显示记录接纳、实际提交和旧槽释放分别报告。状态/事件须保留到消费，不能只提供可能丢失的单周期脉冲。
3. **发布与顺序：** CPU 先完成共享记录写入，再按内存屏障约定敲提交寄存器；DMA 共享区不可缓存。声明的写成功必须支持对应后继读取，不能仅依赖一个本地 OKAY。
4. **DDR 包装：** 原生地址单位、128/256 bit lane 映射、完整写数据预存、不可背压读返回的容量预留、跨主端读写顺序都有定向测试。
5. **显示欠载：** 扫描保持连续，故障时确定性输出本地背景并标记错误，不能拿其他帧的行补齐。受影响显示不能冒充完整有效输出；发生中途错误时在统计中剔除对应帧。
6. **预取生命周期：** 先保证新记录和首行可用再安全提交；否则延后到后续边界。每个行缓存携带帧/行身份，禁止消费过期内容。
7. **时戳：** 使用统一时间基准，事件跨域可靠传递，记录同步误差；不把不同域自由运行计数值直接相减。
8. **复位：** 清除旧记录、FIFO 和事件，同时协调在途总线事务；局部寄存器清零不代表 DDR 请求被取消。

## 8. 两两集成、整机与优化

### P5：CPU＋Video、Video＋NPU 两两验收

**文件：** Video ABI/头文件、CPU 主责驱动与集成测试、模型向量及 `docs/verification/video/integration.md`。

- [ ] CPU＋Video：真实 CPU 通过 MMIO 驱动采集、人工结果提交、释放和错误恢复；验证寄存器版本、中断/轮询及不可缓存共享区。
- [ ] Video＋NPU：同一输入图生成实际 DDR 张量，与 NPU 整数参考逐字节一致；一致后连接真实首层/完整图消费。
- [ ] DDR＋互连：与 CPU 共同验证显示危险水位优先、有界仲裁、所有主端进展及跨主端写后读。
- [ ] 真实 NPU 结果替换人工记录：CPU 解码、NMS、主人脸选择后，提交本帧框和头像；不借 PC 运行时推理。

**通过条件：** 每个输出 frame_id 可追溯到对应输入和真实结果；无脸、单脸、多脸、四边、移动场景正确。Video 路线可独立完成 P4；真实模型整机验收需要另外两线交付。

### P6：完整演示和性能闭合

**文件：** `summarize_events.py`、系统压力配置、PDS 报告索引、板测记录与演示说明。

- [ ] 真实整机连续运行至少 10 分钟，记录源码/固件/模型/素材同一组版本；功能结论与性能结论分开。
- [ ] 记录 `FRAME_SOF`、三分支写完成、`INPUT_READY`、`DET_START/DONE`、`RESULT_READY`、`DISPLAY_COMMIT`、左右首次可见、`DISPLAY_RELEASE_ACK`。
- [ ] 统计首次实际完整显示的不同真实处理 frame_id；两个窗口合计一帧，重复扫描/人工结果/UI 更新不计真实有效输出。
- [ ] 验证延迟分解包含 READY 等待、三分支写排空、提交等待和窗口扫描偏移；报告 P50/P95/P99/最大值及更新间隔抖动。
- [ ] 按瓶颈优化 DMA burst、CDC、FIFO、显示/素材预取和采集/处理/显示重叠；保持位精确与同帧回归通过。
- [ ] 扩大到至少 30 分钟连续运行；另做冷启动、热插拔/失锁、坏输入、超时和协调重初始化。
- [ ] 报告实际有效输出 fps、≥24 fps 达成情况、50 ms P95 延迟参考达成情况、错误/丢帧与资源余量。

**通过条件：** 所有功能、异常和版本证据完整；目标像素时钟及所用主逻辑/DDR 配置完成对应时序核验。未达到性能优化目标时保留功能版和实测瓶颈，不能以扫描率代替有效输出率。

## 9. 带宽、缓存与资源的设计约束

```text
每接纳帧写入 = 1,440,000 + 360,000 + 163,840 = 1,963,840 B
基础带宽 = 1,963,840 × f_cap + 360,000 × f_scan
```

- 实际 DMT 扫描率约 60.3165 Hz；f_cap=24 时基础约 68.846 MB/s；每扫描帧都接纳时约 140.166 MB/s。以上均不含头像、NPU、CPU、协议开销。
- 输出活动窗口每行只有 26.4 μs；预览 1200 B/行约需 45.45 MB/s 的局部服务率。若每行再预取完整 1024 B 头像源行，两者约 84.24 MB/s，仍未包含争用及总线开销。
- 这些数字是预算，不是实测承诺。FIFO/预取深度须结合最大服务间隔、突发流量和初始水位确定；内存模型必须注入最坏连续背压。
- 预览双行像素容量为 2400 B，双头像源行约 2048 B；还需计入缩放累加存储、CDC/DMA 缓冲、元数据和 IP。不得把整个 256×256 RGBA 素材默认放入片上 RAM。
- 每个可综合里程碑都检查 LUT/FF/DRM/APM 映射和时序，尽早发现异步读 RAM 无法映射、CDC mailbox 吞吐不足或资源被整帧缓存占满。
- 全芯片还要容纳 CPU、NPU 与 DDR/互连；Video 预算由实际 PDS 结果汇总后与其他路线协调，不在无报告时填写确定占用率。

## 10. 计划建立的命令与证据规则

以下命令在 P0/P1 建立入口后执行；本轮未创建这些脚本、未运行这些测试。

```powershell
python scripts/video/gen_config.py --check
python scripts/video/run.py --suite timing
python scripts/video/run.py --suite preprocess
python scripts/video/run.py --suite compositor
python scripts/video/run.py --suite frame_protocol
python scripts/video/run.py --suite stress --seed 20261016
python scripts/video/run.py --suite all
python scripts/video/build_pds.py --target video_board_smoke --stage route
python scripts/video/build_pds.py --target video_demo --stage route
python scripts/video/summarize_events.py --input build/video/events.csv
```

脚本须在失败时返回非零，并输出包含工具版本、配置哈希、测试种子与结果的 JSON；重新运行前使旧成功标记失效。板测证据与仿真结果分开，不能因 behavioral DDR model 通过而自动标记真实 PHY/板测通过。下载命令在实际下载器确认后写入板测手册。

| 场景 | 必须能定位的失败 |
|---|---|
| 数学像素 | 缩放舍入、通道顺序、补边、量化零值、Alpha 极值、裁剪源坐标 |
| 存储 | 行尾/字节 mask、4 KiB、最后一拍、写响应延迟、RAW、非法地址 |
| 帧身份 | 错 frame_id、旧释放事件、提交中改写、左右不同帧、释放过早 |
| 实时供数 | FIFO 水位、最长仲裁等待、首行未就绪、右窗口消费前覆盖 |
| 异常恢复 | 失锁、坏尺寸、DMA 错误、途中复位、未排空复用、重复旧事件 |
| 统计 | 重复扫描计新帧、左右计两次、漏 READY 等待、提交时刻代替可见时刻 |

## 11. 外部依赖及关闭条件

| 依赖 | 主责 | 关闭条件 | 不阻塞的工作 |
|---|---|---|---|
| 实物板与 I/O/DDR 约束 | Video | P1 板测、实际信号和时序报告 | 纯像素参考/RTL 仿真 |
| fabric 地址、AXI 完成与排序 | CPU＋Video | 契约版本及跨主端读写/错误测试 | 独立板测 BIST、局部 DMA 测试 |
| YuNet 真实输入形状/量化清单 | NPU＋Video | 实际模型版本、量化参数、参考张量通过 | 两路缩放、共享预览和人工结果显示 |
| 头像锚点/覆盖参数 | CPU＋Video | 尺寸/位置/四边样例确认，清单版本固定 | 测试图案 Alpha 和缩放验证 |
| 三槽是否足够 | CPU＋Video | 不同延迟/相位下生命周期、丢帧和释放证据 | 串行按需采帧功能版 |
| 真实 CPU/NPU | 对应路线 | P5 两两接口与真实图计算通过 | P0–P4 Video 独立交付 |

## 12. 启动批次与后续拆解

建议正式开工第一批只覆盖 P0 的板级/最小契约部分和 P1：

1. 固定来源、工具、板卡与 800×600 配置。
2. 建立独立板测顶层与最小仿真/构建入口。
3. 彩条输出、输入时序测量、DDR 自检分别上板。
4. 交付可复现构建和三项板测记录，再依据实际结果细化 P2/P3 的实现任务。

P0–P4 每批都保持可构建的独立 Video 工程；P5 接正式 CPU/NPU；P6 完成真实演示与优化。代码级任务在对应接口冻结后进一步拆成小步，并写明具体测试、实现、运行命令与提交范围。这里不预填依赖实际 IP/模型参数的 RTL，避免把规划假设当成已冻结接口。
