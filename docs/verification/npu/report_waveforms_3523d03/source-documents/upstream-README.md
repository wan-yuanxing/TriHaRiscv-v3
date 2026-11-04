# TriHaRiscv CPU NPU 异构 SoC 的 NPU 技术设计与集成说明

[按模块阅读 NPU 架构与仿真](#4-npu-微架构) · [完整 SoC 规格](SoC_Design_Spec_NPU.md) · [可编辑架构图](TriHaRiscv_NPU_Reference_Style.drawio) · [图片与依据清单](sources_manifest.json)

| 文档属性 | 内容 |
|---|---|
| 修订标识 | NPU 技术修订 20261103，基于 SoC 设计规格 v0.6 |
| 日期 | 2026 年 11 月 3 日 |
| 适用对象 | NPU RTL、CPU 固件、共享 DDR 与板级集成人员 |
| 融合代码根 | `TriHaRiscv-v3-soc-face-box-integration`，下文记为 SOC |
| 调试资料根 | `npu_zgtc`，下文记为 DBG |
| 架构基线 | CPU 图调度与后处理，单算子 NPU，计算规模通过 RTL 参数配置 |
| 验证状态 | 实际 CPU 与 NPU 的两帧 RTL 闭环已通过；完整后布线时序、新融合版板测和最终性能待验收 |

当前融合系统由 CPU 解析和校验模型程序、逐层启动 NPU，并对九个检测头执行框解码和 NMS。NPU 负责普通卷积、深度卷积及必要张量运算，通过共享 DDR 直接消费 Video 写入的模型输入。CPU 与 NPU 共用一根 100 MHz 时钟，DDR 用户接口运行于 125 MHz。

本文按现有融合代码修订原规格中的 NPU 设计，覆盖模型、数值、运算通路、缓存、DMA、寄存器、软件调度和验证。NPU 采用统一的参数化架构，2×16、16×16 等表示同一架构的计算规模配置。旧独立 B03 的自主 Graph、硬件 POST 及其测试记录作为控制架构演进资料保留。当前功能程序为 RAW 与 BOX 闭环；固定头像属于后续系统功能，当前部署模型不输出五点关键点。[R1][R2][R3]

## 1 修订范围与基线

### 1.1 修订依据

实现判断按以下顺序取证：正式板级参数和显式源清单、同源测试结果、机器可读模型及地址配置、最新调试记录。早期方案中的资源预算和未冻结字段，不能覆盖当前接口。

| 事项 | 原 v0.6 的 NPU 描述 | 当前修订 |
|---|---|---|
| 计算规模 | 默认最多 128 通路，64 通路调试 | 空间并行度由 `M_LANES` 配置，当前 N 方向为 16 通道；密集计算峰值为 `16×M_LANES` MAC/有效向量拍 |
| 图调度 | CPU 逐算子，接口尚为起点 | 已迁移至 `npu_graph.c`，执行 79 条算子记录 |
| 模型级校验 | 交付形式待冻结 | CPU 校验 NPM3 头、程序及参数 CRC、逐记录 CRC 和引用范围 |
| 输出 | 四类头及五点，布局待定 | 裁剪为 cls、obj、bbox 九头，无关键点；逻辑 25,200 B，物理 26,368 B |
| 量化 | 激活优先有符号 INT8，检测头格式待定 | 输入及 ReLU 为 U8，线性激活 S8，bbox 末层 S16，概率 U16 Q0.16 |
| 完成机制 | DONE 晚于输出写响应 | 层核完成且 DMA 和服务适配器退休后，保持结果等待身份匹配 ACK |
| 调试装载 | 模型装载方案待冻结 | 保留 UART 上电初始化，运行中不逐帧依赖 PC |
| 性能结论 | ≥24 fps 为优化方向 | 性能随计算与量化并行参数变化；已有仿真结果标明所用配置，不作为全部配置的性能 |

### 1.2 目标和当前能力

原 SoC 规格采用“有效输出帧率 ≥24 fps 为优化方向、30 fps 不作功能硬门槛”的口径；DBG 后续调试文档保留持续 30 fps 的目标。此次只修订 NPU 技术内容，不替用户重新冻结性能需求。验收记录应同时给出实际有效输出 fps、帧间隔与延迟，并明确采用哪个目标。

当前模型不含身份识别、表情或关键点分支。当前板级 `ENABLE_AVATAR=0`、`CACHE_ENABLE=0`，不可把原规格中头像显示和完整缓存配置的目标描述当作本程序已经实现的能力。[R2][R3]

## 2 CPU NPU 协同架构

### 2.1 控制与数据路径

```text
                          CPU 与 NPU 同根 100 MHz
CPU 固件
  ├─ NPM3 校验与算子图遍历
  ├─ 32 word 算子记录 + 7 word 地址及身份绑定
  │                      │ 32 bit AXI4-Lite
  │               npu_layer_mmio
  │                      │ 原子锁存与任务准入
  │               npu_layer_top
  │                      ├─ 输入缓存与 gather
  │                      ├─ Dense 阵列 / DW16 / 张量执行
  │                      ├─ 时分量化与输出行缓存
  │                      └─ block DMA 与排空保护
  │                                  │ 256 bit 块服务
  │                           npu_service_axi128
  │                                  │ AXI128 与 CDC
  └─ 完成检查 / CPU 解码及 NMS         │
                                     ▼
                           共享 DDR fabric 125 MHz
                    ┌────────────────┼─────────────────┐
                    │                │                 │
Video 采集预处理 → 输入槽       参数与工作区         九头输出槽
800×600 → 320×320                    │                 │
                    └── NPU 直接读写 ┘                 ▼
                                      CPU 有限框列表 → Video 同帧显示
```

上图为依据正式源连接整理的架构示意，不是仿真波形。数据和控制通过各自跨域桥连接；只有共享 fabric 内的一条正式 DDR 原生适配路径，不为 NPU 再建立第二个独立 DDR 控制器。

### 2.2 责任划分

| 模块 | 职责 | 关键约束 |
|---|---|---|
| Video | 采集、缩放、补边、BGR NCHW 写入和显示扫描 | 输入完成后移交对应槽；NPU 不负责 HDMI 与缩放硬件 |
| CPU 图驱动 | 模型级校验、引用解析、冷预检、逐算子执行和 ACK | 保持整帧工作区所有权；不复制输入像素 |
| NPU 单算子核 | 参数准入、通用算子、局部分块、量化和 DDR 搬运 | 保留数值、地址、身份、超时和取消保护 |
| CPU 后处理 | 读取概率及 bbox，筛选、解码、排序、NMS 和结果组装 | 当前候选截断及部分排序差异仍待修正 |
| 平台与 fabric | MMIO/数据 CDC、共享仲裁、写完成、会话复位 | 完成身份与 epoch 贯通，不能用局部计算完成代替 DDR 可见 |

当前正式 NPU 清单为 `config/npu_layer_sources.f` 的 21 个文件。旧自主 Graph、整模型 CRC 扫描、帧执行壳和硬件检测 POST 未被正式清单选中。保留在磁盘中的模块不代表实例化资源。[R2][R4]

## 3 YuNet 模型与整数部署

### 3.1 固定图与算子清单

原始模型为 `face_detection_yunet_2023mar.onnx`，原始 SHA256 为 `8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4`。原图输入为 640×640；部署派生图固定为 320×320，删除未使用的 kps 输出依赖分支。保留分支的权重不变，派生图另行保存和校验。[R5]

融合 ReLU 后，NPM3 部署程序共 79 条记录，程序头和每条记录均为 128 B，因此 `128 + 79×128 = 10,240 B`。

| opcode | 算子 | 记录数 | 执行位置与语义 |
|---|---|---:|---|
| 1 | Dense Conv | 30 | NPU；23 个 1×1 与 7 个 3×3 |
| 2 | Depthwise Conv | 17 | NPU；3×3，通道独立累加 |
| 3 | Add | 2 | NPU；两路尺度对齐后一次舍入 |
| 4 | MaxPool | 4 | NPU；2×2、stride 2、pad 0、floor |
| 5 | Resize | 2 | NPU；nearest ×2、asymmetric、floor |
| 6 | Transpose | 9 | NPU；当前受支持的固定维序转换 |
| 7 | Reshape | 9 | NPU；编码不变，按部署地址和长度搬运 |
| 8 | Sigmoid | 6 | NPU；cls/obj 概率变换，CPU 不重复执行 |
| 合计 | — | 79 | 无整张特征图的软件算子回退 |

算子数由 `compile_report.json` 的 `opcode_counts` 核对，不按原始 ONNX 节点总数估计。当前支持固定图需要的参数范围，不能据此宣称兼容任意 ONNX、动态尺寸或任意 Transpose。[R6][R7]

### 3.2 输入契约

```text
800×600 RGB888 原图
 → 固定双线性缩至 320×240
 → BGR 通道顺序
 → 上下各补 40 行原始值 0
 → UINT8 NCHW [1,3,320,320] 写 DDR
```

行步长 320 B，平面步长 102,400 B，总长 307,200 B。输入 scale=1、zero-point=0，不附加 `/255`，不补 C8 通道。Video 写入最终输入槽后，NPU 直接读该槽；CPU 只绑定地址和帧身份。补边、双线性舍入和通道布局沿用冻结的预处理版本 1，并以张量逐字节对比验收。[R1][R5][R8]

### 3.3 数值编码与算术

| 数据 | 当前数值契约 |
|---|---|
| 输入像素 | UINT8，0…255，scale=1 |
| 权重 | 逐输出通道对称 INT8，−127…127，zero-point=0 |
| Conv 与 ReLU 融合输出 | UINT8，0…255 |
| 其他内部 Conv 及 cls/obj logits | INT8，−127…127 |
| bbox 末层与后续重排 | INT16，−32767…32767 |
| Bias 与通用累加语义 | INT32；完整 K 后加一次 Bias |
| Requant | 正 INT31 multiplier，INT64 乘积，右移 1…62，RNE 后饱和 |
| Sigmoid 输出 | UINT16 Q0.16，scale=1/65536，1 饱和为 65535 |

U8 数据进入有符号乘法端口前必须零扩展，S8 数据符号扩展。`128…255` 不能按负数解释。完整 K 求和后才进行 Bias 和重定标，跨 K 块不能提前截断或饱和。

RNE 为半数取偶，包含负数半值。Add 先对两输入分别乘尺度系数，在宽中间域求和，再统一舍入一次。Pool、Resize、Transpose 和 Reshape 保留原编码，不新增量化边界。冻结参数和主机整数参考见 `integer_numerics_v1.json` 与 `ptq_integer.py`。[R5]

### 3.4 九头输出布局

候选位置为 `40×40 + 20×20 + 10×10 = 2100`。每个位置只有 `cls + obj + 4 bbox` 共 6 个值，全部以 16 bit 最终头格式交接，逻辑有效数据 `2100×6×2 = 25,200 B`。各头按部署清单分配物理跨度，合计 26,368 B。

| 头 | 编码 | 有效元素 | 字节偏移 | 有效字节 | 分配字节 |
|---|---|---:|---:|---:|---:|
| cls_8 | U16 Q0.16 | 1600 | 0 | 3200 | 3328 |
| cls_16 | U16 Q0.16 | 400 | 3328 | 800 | 1024 |
| cls_32 | U16 Q0.16 | 100 | 4352 | 200 | 256 |
| obj_8 | U16 Q0.16 | 1600 | 4608 | 3200 | 3328 |
| obj_16 | U16 Q0.16 | 400 | 7936 | 800 | 1024 |
| obj_32 | U16 Q0.16 | 100 | 8960 | 200 | 256 |
| bbox_8 | S16 | 1600×4 | 9216 | 12800 | 12800 |
| bbox_16 | S16 | 400×4 | 22016 | 3200 | 3328 |
| bbox_32 | S16 | 100×4 | 25344 | 800 | 1024 |
| 合计 | 小端 | 12600 | — | 25200 | 26368 |

bbox 的各尺度倍率以机器契约为准；用于展示的近似值分别为 `9.49192189732e−5`、`4.54262956314e−5`、`9.38788198714e−5`。不能把格式中保留的关键点字段解释为有效输出，也不能继续用含 10 个关键点坐标的 16 字段公式计算当前输出。[R5][R6][R8]

### 3.5 软件精度基线

PTQ 使用 train 中 512 张图进行校准，采用 bbox16 方案，并对全部 3226 张 WIDER val 执行软件整数评价。

| 难度 | FP32 AP | bbox16 AP | AP 下降 |
|---|---:|---:|---:|
| Easy | 78.3929% | 78.2039% | 0.1889 个百分点 |
| Medium | 67.2333% | 66.9742% | 0.2591 个百分点 |
| Hard | 31.5613% | 31.3584% | 0.2029 个百分点 |

这是冻结预处理、候选及评价规则下的软件数值基线。当前 CPU 后处理有已知差异，以上 AP 不等于融合固件、实板摄像头或当前 NMS 实现已经达到同样结果。320 输入对小脸的限制也仍存在。[R5][R9]

## 4 NPU 微架构

NPU 是 SoC 中执行 YuNet 检测网络算子的硬件加速器。CPU 决定运行哪一层，并提供该层的参数和张量地址。NPU 从共享 DDR 读取输入特征与权重，完成卷积或辅助运算，将结果写回 DDR。中间层的结果供下一层读取，最后九个检测头的结果交给 CPU 解码和筛选人脸框。

本章的 14 幅波形图均为 ModelSim Wave 窗口的真实截图，数据来自已有仿真的归档 VCD，经原生 vcd2wlf 转换后打开。双窗口图按原始像素上下拼接，未重绘曲线或补造信号。各图使用各自归档测试的配置与时间轴；这次换图不代表重新运行仿真、布局布线或上板测试。

图 1 左侧的控制路径连接 CPU 和层控制器。CPU 通过寄存器提交任务，层控制器选择执行通路，再向 CPU 报告完成状态。沿图的上部和右侧可以跟踪数据流。Data Streamer 组织输入、参数和输出，Conv. Core 完成乘加与量化，辅助算子按需要调用共享量化器 Q。

![TriHaRiscv NPU 架构，Data Streamer 与 Conv. Core](TriHaRiscv_NPU_Reference_Style.png)

图 1　TriHaRiscv NPU 的模块与数据通路。虚线框内的 MAC 小矩形示意可调的 Dense 阵列，DW16 位于阵列下方。右侧为两条卷积通路共享的量化器 Q，底部双向连线表示 Add / Sigmoid 对 Q 的请求与返回。

### 4.1 TriHaRiscv CPU、AXI4-Lite MMIO 与 Layer Controller

控制路径负责把 CPU 提交的一层任务执行到完成。软件管理算子顺序和帧的归属，硬件负责层内分块、执行和写回。

#### 4.1.1 TriHaRiscv CPU

CPU 持有帧槽和模型工作区，决定每层何时启动、数据写到哪里。固件从 NPM3 程序取出下一条算子记录，将相对引用解析为本帧的输入、输出和工作区地址，并分配任务标签（tag）。九个检测头全部写回后，CPU 读取同一帧的结果，执行检测框解码和筛选。

在实际 CPU 执行固件的两帧 SoC 仿真中，CPU 分别在第 47,661,880 和 68,447,136 个周期收取结果。每帧九头的 26,368 B 均与参考值一致。该结果取自整机日志，下面的寄存器波形则单独观察 CPU 所访问的硬件端点。[R3]

#### 4.1.2 AXI4-Lite MMIO

MMIO 是固件提交任务和读取状态的寄存器窗口。CPU 依次写入算子描述和地址绑定，最后写 START。端点接受 START 时锁存 32 个算子字与 7 个绑定字，形成这一次层执行的输入。完成后，CPU 从同一窗口读取完成记录，再写 ACK 释放记录。特征、权重与输出像素由独立的块 DMA 搬运。该端点的完成握手见下方 IRQ / Status 波形。[R4][R7]

#### 4.1.3 Layer Controller / Decode

层控制器把一条算子描述转换为层内的执行顺序，对应 `npu_layer_top` 和层执行器 `b03_layer_exec_payload`。预检检查形状、通道关系、数据类型、参数和地址边界。执行时，图中 Decode 按算子类型选择 Dense、DW 或 Auxiliary。以普通卷积为例，控制器依次安排参数和窗口装载、阵列清零、沿 K 维发射及排空、量化和输出写回。当前模型的卷积准入要求 K≤128，空间算子还需满足行缓存容量约束。[R4][R7]

在主机代理驱动同一单层接口的回归中，首次模型预检完成 79 条记录，两帧合计执行 158 条记录。计分板记录 221,817 次 DMA 完成，每帧写回的九头数据均通过比对。这里核对的是层控制器接受、执行和完成算子的能力。见 DBG 第 167 篇及 SOC 的 `build/soc/cpu_graph_rtl/20261102T034122_779389Z/result.json`。

#### 4.1.4 IRQ / Status

该模块把任务完成或出错的状态反馈给 CPU。层核给出完成信号、块 DMA 空闲且外部适配器允许发布后，MMIO 保持完成记录。当前 `face_avatar` 固件通过 `npu_graph_collect()` 轮询，读到 HELD 后核对 status、tag、算子序号、epoch 和 published，再写身份匹配的 ACK。硬件也提供可使能的中断，`triha_compute_system` 将 NPU 和 Video 中断汇入 CPU 外部中断输入。下图采样的是 MMIO 完成通道及其发布条件。[R2][R4][R7]

![单算子启动、完成退休与故障](assets/01_layer_mmio_actual_vcd.png)

图 2　MMIO 端点仿真（100 MHz，DBG 第 167 篇）；ModelSim Wave 原生窗口截图。

约 4 µs 处，层核拉高 done_valid 时 retired 仍为 0，done_ready 随之保持为 0。后面的两次故障注入分别使用错误的 tag 和变化的 epoch。控制器必须先核对身份与退休条件，才能发布完成。

### 4.2 DMA、AXI4 与 Banked Buffers

这组模块在共享 DDR 与计算通路之间搬运张量。DDR 保存跨层使用的数据，片上缓冲保存当前计算块需要反复使用的数据，DMA 负责两者之间的传输。

#### 4.2.1 AXI4 / Shared External Memory

共享 DDR 用于在 Video、NPU 和 CPU 之间交接张量。首层从 Video 已写好的输入槽取数，中间层按程序给出的工作区偏移读写，输出算子将头数据写到对应帧槽。CPU 与 NPU 共用 100 MHz 时钟，DDR 用户接口为 125 MHz。NPU 的块请求经 `npu_service_axi128` 转换为 AXI128 事务，再经跨域桥与共享互连访问 DDR。下面 DMA 小节的双时钟域波形展示一次读写如何走完这条路径。[R4][R8]

#### 4.2.2 DMA

**DMA** 对应 `b03_block_dma_compact`。它接收方向、偏移、长度、客户端身份及 tag，将一个请求保持到读写和完成响应均已处理。局部一拍为 32 B，适配器用两个 16 B AXI 拍传送这 32 B，按 AXI 突发上限和 4 KiB 边界拆分。行尾或张量首尾仅部分字节有效时，由写掩码保护相邻数据。控制器在输入取数、输出行写和向量访存之间选择当前请求方。图中的 Vector DMA 是其中一个请求方，上方的 DMA 为这三类请求提供公用块传输服务。[R4][R7][R8]

![独立读写桥中的突发、背压与完成](assets/npu_dma_retirement.png)

图 3　块传输的读写和退休（DBG 第 46 篇独立桥仿真，本地域 100 MHz，UI 域 125 MHz）；ModelSim Wave 原生窗口截图。

本窗口按原始时间轴展示 case 17～20 的写入、读回及完成握手，可核对 100 MHz 本地域与 125 MHz UI 域的时钟，以及 done_valid / done_ready 的交接。原测试连接 HMIC 和两颗 x16 DDR3 器件模型；突发长度与数据正确性结论沿用归档计分板记录。

#### 4.2.3 Banked Buffers (IFM / Weights / OFM)

图中这一条带汇总三类片上存储。IFM 缓冲保留可复用的特征行和窗口，Weights 缓冲按当前输出通道组供数，OFM 缓冲把多个计算拍产生的结果排成可写回的行。三者的端口分别在下节的 Feature Input、Weight Input 和 Feature Output Row Buffer 下给出实测波形，可分别观察特征行复用、带标签的权重读返回以及输出尾块的有效字节。层间完整张量保存在 DDR 工作区或帧输出槽。

### 4.3 Data Streamer 的输入、参数与输出端

Data Streamer 把 DDR 中按地址存放的张量组织成计算单元需要的窗口和通道组，再把结果拼成可写回的块。图中向下的箭头表示特征、权重和量化参数输入，右侧向上的箭头表示输出行写回。

#### 4.3.1 Vector DMA Read / Write

向量读写端口负责为 Add、Sigmoid、Transpose 和 Reshape 搬运元素。`b03_vector_exec_compact` 经该端口发出带偏移和长度的块请求。Add 需要读取两个源张量，Reshape 可按连续块搬运已编码的元素，完成后都由向量端口直接写回 DDR。[R7]

![Vector DMA 的读数据接收和写数据受理](assets/vector_dma_rw.png)

图 4　向量执行器本地存储服务接口（Reshape，case 4，ModelSim Wave 原生窗口截图）。

上窗显示 debug_stage 从 29 转到 30，下窗从 28 转到 31。按同一归档 RTL 的状态定义，这些边界分别对应读数据接收和写数据受理。截图仅显示 VCD 实际记录的状态与完成信号；该归档没有直接记录 mem_r_ready、mem_w_valid，因此不再绘制由状态推导的握手曲线。12,800 个输出字节全部一致的结论来自原测试计分板。

#### 4.3.2 Feature Input

特征输入端将张量中的像素排列成当前计算拍所需的激活向量。`b03_model_input_payload` 读取输入行片，`b03_gather_lean` 按核位置、步长和补边选择窗口。普通卷积需要多个空间位置的激活，DW 按卷积核采样点（tap）和通道组取值，池化与缩放按采样坐标取值。[R7]

本地打包 FIFO 的 clear 清除占用计数和 `payload_live`，防止前一任务的字节进入新任务。新的完整载荷覆盖 bank 后，公开输出才重新生效。[R11]

![Feature Input 内部载荷与公开数据的时序](assets/03_fifo_payload_epoch_actual_vcd.png)

图 5　融合版选用的特征 FIFO 适配（DBG 第 169 篇组件仿真）；ModelSim Wave 原生窗口截图。

55 ns 附近清空后，私有 bank 仍可保留旧字节，但 payload_live 和计数都变为 0，公开输出为零。85 ns 后重新装载，有效数据与参考 FIFO 再次一致。

同一层的相邻窗口可能使用相同的输入行。行缓冲识别驻留命中后直接给 gather 供数，省去一次外部读。

![输入行驻留复用与窗口连续供数](assets/npu_input_gather.png)

图 6　输入行复用与窗口供数（DBG 第 96 篇 B03 组件仿真）；ModelSim Wave 原生窗口截图。

上窗是 Cin=64 的驻留命中，LOAD_ROWS 两拍完成，期间没有新的存储读取请求。下窗来自另一项 E1 gather 测试，可沿连续 K 请求看到 A 向量按序写入。两窗使用各自测试的时间轴。

#### 4.3.3 Weight Input

权重输入端从参数镜像装入本层的 INT8 权重。在每个 K 步，普通卷积从 B bank 读出一组输出通道的权重，DW 则对每个有效通道取该通道当前 tap 的权重。执行器在本次权重与对应特征均已到达时接受这组操作数。读响应携带请求标签，暂停期间必须保持可见数据稳定。[R7]

![Weight Input 相邻两行权重的读请求和返回](assets/weight_input_read.png)

图 7　B 权重行读取（B03 输入缓存组件，case 0，ModelSim Wave 原生窗口截图）。

两次 b_req_valid 分别请求第 0、1 行。b_rsp_valid 在 1.305 µs 和 1.355 µs 拉高，返回标签依次为 0x42000000、0x42000001。两次暂停期间响应都保持有效，b_rsp_error 为 0，每行返回的 16 字节均与参数文件相应位置一致。

#### 4.3.4 Bias / Multiplier / Shift

参数输入端按输出通道装载偏置、重定标乘数和移位数，保存在本地供 Shared Q 选择。当前融合 RTL 用 `param_group` 选出一组八个通道，每通道提供 32 位 bias、32 位 multiplier 和 6 位 shift。Bias 在卷积累加完成后才加入，multiplier 和 shift 决定如何把累加结果转换为输出的整数尺度。[R5][R7]

下图取自较早的输入缓存组件仿真。该快照并行引出了各通道的参数信号，可直接核对同一通道三个参数的装载值和生效时刻。

![卷积通道 5 的偏置、量化乘数、右移量及有效标志](assets/conv_channel_params.png)

图 8　卷积参数装载（B03 输入缓存组件，case 0，16 个输出通道，ModelSim Wave 原生窗口截图）。

通道 5 的偏置先在 0.585 µs 变为 −10,749，乘数与右移量在 0.875 µs 分别变为 1,686,676,122 和 40，与用例参数文件中的三个字段一致。shadow_valid[5] 在 1.125 µs 置位，param_valid 在 1.245 µs 拉高。截图选择通道 5 的原始总线切片和有效位；16 个通道全部有效、完整 shadow_valid 为 0xFFFF 的结论来自原测试记录。

#### 4.3.5 Feature Output Row Buffer

输出行缓存接收量化后的卷积结果，也接收 Pool / Resize 直接产生的采样结果。`b03_bank_array_payload` 的 O bank 按输出位置暂存数据，`b03_row_tile_store_rotate` 再按张量的内存顺序拼成写数据并生成字节使能，交给块 DMA。最后一个空间块或通道组不足时，仅写有效字节。

O 行缓存由四个 1024×32 bit 的 bank 组成，合计 16 KiB 逻辑容量。层准入检查 `ceil(Co/4) × ceil(Wout × 每元素字节数 / 4) ≤ 1024`，以保证一行的通道数据能放入每个 bank。输入和参数另有各自的 bank 和控制逻辑。[R4][R7]

![量化结果、输出缓存有效字节和本地读回](assets/npu_output_mask.png)

图 9　输出尾块写入（DBG 第 90 篇，16×16 阵列与 A/B/P/O 本地缓存的组件测试）；ModelSim Wave 原生窗口截图。

此用例有 7 个有效空间位置和 9 个有效输出通道，每个位置分为 8 个通道和 1 个尾通道。上窗显示原始 512 位 o_valid 有效字节位图，以十六进制显示；它是位图，不是字节计数器。下窗显示实际 host 请求与读响应。有效字节、尾通道及相邻位置保护由原计分板核对，旧图通过位图置位数生成的 o_valid_bytes 曲线已移除。

### 4.4 Conv. Core 的 Dense MAC 阵列

**Configurable Dense PE Array (M × 16)** 用于图中的 Std（普通卷积）和 PW（逐点卷积）。每个 MAC 小矩形表示一个乘加单元。行对应 M 个输出空间位置，列对应一组 16 个输出通道。对给定的位置和输出通道，MAC 沿输入通道和卷积核位置组成的 K 维累加。1×1 卷积只需遍历输入通道，普通 3×3 卷积还需遍历九个核位置。最后一块的行或列不足时，mask 选出有效结果。[R5][R7]

Dense 阵列对应 `b03_array_apmacc_rowctrl`。每个有效向量拍的峰值为 `16×M` 次 INT8 MAC，SIMD 映射下每两个乘加通道复用一个 APM，Dense 部分对应 `8×M` 个 APM。对当前准入范围，原始部分和的绝对值上界为 `128×255×127=4,145,280`，可装入有符号 24 bit 的 APM 累加通路。部分和随后按有符号值扩展到 INT32 语义，偏置和重定标交给 Shared Q。[R7][R10]

| 参数 | 影响 | 配置时机 |
|---|---|---|
| `M_LANES` | 改变 Dense 阵列的空间并行行数 M。当前输出通道组为 16，行掩码最多覆盖 16 行。 | RTL 综合前 |
| `QUANTIZER_LANES` | 改变物理量化通道数。当前实现提供 1、2 两种选择，对外保持八个元素一组的接口。 | RTL 综合前 |
| 形状、步长和地址 | 决定本层遍历的窗口、分块、尾块 mask 和读写目的地。 | CPU 提交算子时 |

以 100 MHz 计算，Dense 理论峰值为 `1.6×M` GMAC/s。层执行时间还包括装载、尾块、量化和写回等待。比较两次构建的结果时，应同时记录 M、量化并行度和内存服务条件。

![Dense 阵列 K 向量发射和累加器提交](assets/npu_dense_accumulate.png)

图 10　Dense 阵列的 K 维累加（DBG 第 90 篇，M=16 组件仿真）；ModelSim Wave 原生窗口截图。

上窗显示 K 向量的输入、提交及 accepted / retired 计数，acc_flat[31:0] 是第 0 路累加器的原始总线切片。下窗来自独立的 tile 组合测试，将 K=27 分成 16 项和 11 项。两窗分别使用各自测试的时间轴，单路切片不代表同时展示了全部阵列累加器。

### 4.5 DW16 的逐通道卷积

**DW16 — Channel-wise 3 × 3 Conv.** 负责逐通道卷积，最多并行计算 16 个通道。每个通道使用自己的卷积核，例如通道 c 的一个 3×3 输出只累加该通道窗口的九项乘积。控制器对普通卷积和逐点卷积启动 Dense 阵列，对逐通道卷积启动 DW16，两路结果汇入同一个 Q。DW16 在层核中实例化为 `b03_full_dw16_parallelfault`，正式清单选用本地 `b03_dw16_lane_write.v`。[R4][R7][R11]

每个有效通道在 first tap 取零基准。中间 tap 更新本通道部分和，合法 last tap 到达后才提交。通道 mask 屏蔽尾部无效项，tag 和有效位随流水向后传递。[R11]

![DW16 处理 17 通道尾块的层级计数](assets/dw16_case7.png)

图 11　DW16 空间层（B03 release，Q4 时分量化，ModelSim Wave 原生窗口截图）。

case 7 的输入、输出均为 17 通道，跨越一个完整 16 通道组和一个尾通道。4×19 个输出位置共记录 1,368 个 MAC 向量、304 个量化组和 4 行写回。2,584 B 的 S16 输出与参考逐字节一致。曲线采样的是层级计数与完成边界。

融合工程另对 DW16 按通道写入适配执行了 10,000 组任务。测试以独立整数参考核对有效通道结果，并逐周期比对公开端口。覆盖 K1/K9、符号扩展、暂停、取消和错误情况，全部通过。[R11]

### 4.6 Shared Q 的偏置、激活与重定标

**Shared Q / Bias / Act. / Requant.** 接受 Dense 或 DW 的完整部分和。对于卷积，Q 加一次 Bias，乘以该通道的 multiplier，按 shift 右移并做半数取偶舍入（RNE），最后按本层激活和目标类型限幅。融合 ReLU 输出 U8，线性输出按记录产生 S8 或 S16。Q 用 tag、mask 和 dtype 把结果与原来的位置和通道重新对应。层核按 `QUANTIZER_LANES` 实例化 `b03_quant8_tdm1` 或 `b03_quant8_tdm2`，分时处理外部的八元素组。[R4][R5][R7]

![Shared Q 的有符号舍入与 U8 限幅](assets/npu_q_rne.png)

图 12　Shared Q 的舍入边界（DBG 第 88 篇，早期八条物理量化通道的单元仿真）；ModelSim Wave 原生窗口截图。

上窗保留混合样本的输入与输出边界，下窗放大有符号重定标和 U8 限幅，可见 actual_lane0_rounded 为 −64 时 actual_lane0_value 为 0。数值正确性沿用原测试逐通道比对结果，单通道与双通道时分实现的延迟按各自配置计量。

### 4.7 Auxiliary Operators 辅助算子

层控制器按算子类型选择向量处理或空间采样。图中 Auxiliary Operators 与 Q 之间的双向箭头用于 Add 和 Sigmoid 的请求与返回。Pool / Resize 的箭头指向 OFM 行缓存，Transpose / Reshape 则从向量端口完成访存。当前模型的 79 条算子记录中，2 条 Add、6 条 Sigmoid、9 条 Transpose 和 9 条 Reshape 使用向量端口。见 DBG 第 179 篇。

#### 4.7.1 Add / Sigmoid 与共享量化器的握手

**Add** 合并两个输入张量。向量单元读取同一位置的两路激活，Q 分别乘以各路尺度系数，在宽中间域相加，再统一舍入和限幅。返回的值就是待写出的元素。

**Sigmoid** 将 S8 logits 转为 U16 Q0.16 概率。向量单元先请求 Q 生成查表索引，收到索引后访问冻结的概率表，再通过 Vector DMA 写回。两者共用 Q 接口，下面分上下窗口观察归档状态序列。

![Add 与 Sigmoid 请求并取回 Q 结果](assets/vector_q_requests.png)

图 13　向量执行器与 Q 交互的状态边界（B03 Q4 时分组件，ModelSim Wave 原生窗口截图）。

上、下窗分别显示 Add 和 Sigmoid 的第一组量化状态。debug_stage 是直接采样值：按同一归档 RTL，12 为 QPREP、14 为 QISSUE、15 为 QWAIT、16 为 SLREQ。Add 在 QWAIT 后回到 QPREP，Sigmoid 则转到 SLREQ。该 VCD 没有直接记录 q_in_valid / q_out_ready，新截图不包含推导的 valid/ready 曲线；请求与返回的解释依据原 RTL 状态定义，时间轴仅适用于图示 Q4 配置。

Add 和 Sigmoid 的系数由参数接收端从 DDR 装入。存储读返回可能出现在运算暂停期间，因此接收端要先保留返回字，再在允许执行时更新算子可使用的系数。下图展示辅助参数接收的一次暂停和恢复。

![暂停期间的辅助参数接收和恢复](assets/npu_aux_coeff_rx.png)

图 14　辅助系数接收（DBG 第 175 篇，R 拍预选辅助字的候选实现）；ModelSim Wave 原生窗口截图。

上窗在 run_ce=0 时接收读返回，私有寄存器保存 0x1E240。下窗在 CE 恢复后才更新公开 aux_coeff。截图同时保留 mem_r_valid / mem_r_ready、私有 aux_v0 与公开 aux_coeff，可区分接收和公开生效。该用例观察辅助参数通路，卷积权重、Bias 和 shift 由各自的参数字段选择。

#### 4.7.2 MaxPool / Resize 与输出行写回

MaxPool 从每个 2×2 窗口选出最大值。Resize 按最近邻坐标取样，将一个输入位置扩展到 2 倍高、2 倍宽的输出网格。两者保留输入的数值编码，采样结果直接进入 O 行缓存，由行写器提交 DMA。下面观察空间层回归中连续执行的池化和缩放用例。

![MaxPool 与 Resize 的空间层计数和完成时刻](assets/npu_pool_resize.png)

图 15　空间层与块 DMA 联合仿真，桥端采用字节存储模型（DBG 第 107 篇配图）；ModelSim Wave 原生窗口截图。

上窗截取 case 16（MaxPool）完成前后，下窗截取 case 17（Resize）完成前后。MAC 向量数和 Q 组数保持为 0，stat_rows 与 done_valid 显示最终行写回和完成握手。原计分板分别核对 MaxPool 的 7 行、18,368 字节（64 通道，7×41）和 Resize 的 40 行、4,560 字节（3 通道，40×38），所有输出字节均与独立整数参考一致。

#### 4.7.3 Transpose / Reshape 与向量端口

Transpose 改变元素的维序，按目标张量的坐标生成读写地址。Reshape 改变张量形状，保持元素序列。两者在向量端口搬运原编码的元素，均可直接写回。上文 Vector DMA Read / Write 的波形取自这里的 Reshape 用例，展示其读写阶段的原始状态边界。

组件回归中，Transpose 用例 2 搬运 4×1×17 个 I16 元素，136 B 输出全部匹配；Reshape 用例 4 搬运 6,400 个 I16 元素，12,800 B 输出全部匹配。覆盖 Add、Sigmoid、Transpose 和 Reshape 的 14 个用例合计核对 150,092 B，均与独立整数参考逐字节一致。该测试使用实际 E1 缓存、查找表和共享量化器，外部存储由本地模型提供。见 DBG 第 97 篇及 `build/platform/b03_vector_quant_tdm4_dev02/simulation/console.log`。

## 5 DDR 地址与完成语义

### 5.1 系统地址绑定

所有表中地址为当前 `config/soc_memory.json` 的 CPU 物理地址。模型记录内部保留相对引用；CPU 解析输入、输出和工作区引用后，向 MMIO 寄存器写入相对 `SOC_DDR_BASE=0x80000000` 的字节偏移，服务适配器只加一次基址。[R8]

| 区域 | 当前地址或尺寸 | 用途 |
|---|---|---|
| 输入 A/B/C | `0x82800000 / 0x82850000 / 0x828A0000` | 每槽 327,680 B，张量 307,200 B |
| 输出 A/B/C | `0x82900000 / 0x82940000 / 0x82980000` | 每槽 262,144 B，绑定对应 frame/slot/epoch |
| 模型程序 | `0x82B00000`，10,240 B | CPU 读取 NPM3 程序 |
| CPU 解码表 | `0x82B10000`，1,572,864 B | bbox 解码与定点转换使用 |
| 本模型工作区 | `0x83300000`，4,876,544 B | 当前模型张量与参数镜像 |
| 参数镜像 | workspace `+4,768,256`，108,288 B | 权重、Bias、重定标和算子辅助参数 |

工作区实际使用量与系统保留的 64 MiB WORKSPACE 区不同。当前参数镜像终点恰好为 `4,768,256+108,288=4,876,544`；程序虽放在 MODEL 大区，执行参数镜像位于工作区尾部，不应把权重数据统一描述为只从 MODEL 大区读取。

每个输出槽内保留：heads `+0`、26,368 B；result `+0x8000`、67,328 B；publish `+0x20000`、128 B。后两块是公共布局的保留区域，不表示单算子端点会写旧硬件 POST 结果或发布头。当前完成信息从 MMIO 完成寄存器读取，CPU 从 heads 生成软件结果。[R6][R8]

### 5.2 DMA 与共享互连

NPU 局部服务采用 256 bit 数据和 32 B 对齐请求，最多 16 个逻辑 beat。`npu_service_axi128` 转为 128 bit AXI4，每个逻辑块低 128 bit 先行，并重新按 AXI 最多 16 beat 和 4 KiB 边界拆分。两个接口的 beat 宽度不同，不能直接沿用同一个 burst 拍数。

源/目的张量可以按元素对齐；DMA 对外请求对齐，并用字节掩码保持首尾非有效字节。DDR 原生列边界检查使用最终地址，不能只检查模型相对偏移。共享数据和 MMIO 不可缓存，不建立 CPU 可缓存别名；当前板级缓存访问关闭也不能取消后续一致性规则。[R2][R4][R8]

### 5.3 计算结束与结果发布

完成必须依次满足：层核完成、局部 DMA 无在途、外部服务适配器允许发布。`npu_layer_top` 将 `!dma_busy && publish_permission_i` 交给 MMIO 作为退休条件。CPU 只有在 HELD、完成状态成功、tag/op/epoch 一致且 `published=1` 时，才能消费结果或推进下一层。

IRQ W1C 只清通知状态；ACK 只确认已有完成记录。ACK 不承担取消，不释放显示仍持有的原图。任意超时、身份错误或运行中 epoch 改变都使当前推理失效；在途事务按平台契约排空后协调恢复，不读取旧头继续显示。[R2][R4]

## 6 单算子提交与结果交接

固件通过 32 bit AXI4-Lite 写入一条算子记录和地址绑定，写 START 启动执行。一次中间层结束后，CPU 轮询完成状态、核对任务身份并写 ACK，然后提交下一条记录。最后一层完成后，CPU 从当前槽读取九个输出头，执行解码与 NMS，再归还图计算的工作区。[R4][R7]

## 7 CPU 驱动与模型启动

### 7.1 模型校验和图遍历

`npu_graph_validate()` 检查 NPM3 头、模型身份、输入和工作区尺寸、九头偏移、程序 CRC、逐记录 CRC、参数 CRC、算子形状与引用范围。参数扫描结束后重新检查平台身份。epoch 未变化且模型不可变时可复用校验上下文；每次 issue 仍读取记录并核对已保存的 CRC。

模型第一次使用时，CPU 先提交 79 次 `PREFLIGHT=1` 的逐层数值预检，预检不写模型输出；再执行 79 层。热帧在同一有效模型和 epoch 下只执行 79 层。更换模型或重定位前必须停止任务、排空并失效旧校验上下文；不能边执行边改参数。

`npu_graph_collect()` 为协作轮询接口，每次最多收取一个完成并启动下一算子；中间返回 PENDING。只有最后一层成功发布后才调用 `npu_cpu_post_heads()`。最终结果 ACK 后归还图计算所有权；显示的 raw 引用继续按 Video 的 commit/release 协议管理。[R2][R7]

### 7.2 冷启动与运行顺序

1. FPGA 配置后等待 PLL、DDR 初始化和各域复位释放，读取当前 epoch。
2. UART 初始化装载 program、parameter、CPU post table 及三槽 heads 初始段；完成传输校验和封存后才允许 CPU 启动推理。
3. CPU 核对模型包、公共地址与槽所有权；冷启动执行模型级校验和 79 次预检。
4. Video 提交完整模型输入槽，CPU 绑定 frame/slot/epoch，逐层启动 NPU。
5. 最后一层成功后，CPU 读取概率和 bbox，执行后处理并向 Video 提交同帧结果。
6. NPU 完成 ACK 与显示旧帧 release 分别退休，槽满足全部引用条件后才能复用。

UART 在此流程中承担上电初始化，不在每帧中与 PC 交互。当前六段有效载荷合计 1,770,496 B，115200 bit/s、8N1 下仅原始载荷串行下界约 153.7 s；现有分包协议连同开销的理论下界约 170.5 s，现场应按数分钟等待。两者均为装载估算，不是每帧计算耗时。[R3]

### 7.3 当前 CPU 后处理

CPU 读取 NPU 已执行 Sigmoid 的概率头，以乘积阈值筛选，访问解码表形成框，去除 letterbox 后映射到 800×600 原图，再排序和 NMS。当前代码阈值对应 score 0.6，IoU 使用 `inter×10 > union×3`，NMS 前最多保留 64 个候选，最终最多输出 16 框。

当前实现与冻结完整参考存在两项已复现问题：64 个高分重叠框加第 65 个低分独立人脸时，top64 截断会漏掉该独立框；按未舍入概率积排序时，最终 FP32 score 相同的候选顺序可能与参考不同。Q16 转换及在整数裁边框上计算 IoU 的差异也应纳入等价检查。

显示最多 16 框不能证明 NMS 只需输入 64 个候选。修正后需要重新验证候选集合、稳定排序、IoU 边界和质量指标；不能仅增加一个 Top-K 常量就宣称与原参考等价。[R9]

## 8 时钟 复位与跨域

| 域 | 频率与连接 | 检查重点 |
|---|---|---|
| CPU 与 NPU | 同一 GPLL 输出，100 MHz | 核对真实网络及逐层周期时间基准 |
| DDR UI、Video core、初始化 UART | 125 MHz | 125 MHz 为 IP 用户接口频率，不是 DDR 器件 CK |
| HDMI 输出像素 | 40 MHz | 扫描与图像提交按帧边界 |
| HDMI 配置 | 10 MHz | 配置时序与复位独立检查 |

板载 27 MHz 经 compute GPLL 生成 100 MHz。控制 AXI-Lite 和数据 AXI128 通过各自 CDC；跨域事件使用接收域复位释放后的同步链。计算 PLL 失锁由板级统一协调 DDR 控制器和所有者复位，不能只复位 NPU 再复用旧在途数据。[R2][R13]

![各接收域复位释放及同步链的实际波形](assets/02_local_reset_actual_vcd.png)

图 16　公共复位解除后，各域等待本域两个上升沿再释放；重复异步断言立即生效。这是当前本域释放与事件链的 RTL 证据，不包含后续局部七叶复位树候选的物理签核。[R3]

![输入流寄存反压的实际波形](assets/04_ingress_ready_actual_vcd.png)

图 17　两槽输入流缓冲满时，上游 ready 在时钟沿停止，下游 ready 的边沿间变化不组合穿透上游。该结构属于融合输入链对 125 MHz 域的时序处理，与 NPU 运算正确性分别验收。[R3]

内部时序发布门槛覆盖 12 个实际时钟、慢快角的 setup、hold、recovery、removal、pulse width，并额外核对 23 组 Gray 总线 max_skew 的约束与覆盖。单独 100 MHz 计算域通过、布局估计为正或路由命令成功，都不足以发布整板程序。[R3][R13]

## 9 资源与性能评估

### 9.1 已有配置的资源记录

下表对应 `M_LANES=2`、`QUANTIZER_LANES=1` 的融合构建快照，仅作为统一可调架构的一组已有数据。调整参数后，资源与时序按新构建记录更新。

| 阶段与范围 | LUT | FF | APM | DRM36K 等效 | 状态 |
|---|---:|---:|---:|---:|---|
| 正式融合 SYN | 43041 | 43775 | 58 | 77.5 | 综合结果 |
| 正式融合 dev_map | 43026 | 43673 | 58 | 77.5 | 映射结果 |
| 同快照完整后布线 | — | — | — | — | 尚未取得完整 STA 通过结论 |

以上数值引用第 168/169 篇的正式 FIFO mask 与 DW 按通道写入快照，范围包含 CPU、Video、互连和 NPU，并非 NPU 独占资源。后续辅助选择和复位树候选有各自资源与时序记录，不能把不同候选的最佳数字拼成一份已实现整板结果。[R3][R11][R12]

### 9.2 模型计算量与吞吐

320 框检测派生图的 Conv 总量为 84,523,000 MAC/帧，其中 Dense 68,837,800、DW 15,685,200。30 fps 的纯卷积需求为 2.53569 GMAC/s，尚未包括张量运算、量化、DMA、CPU 后处理与视频争用。[R5]

令计算时钟为 `f_clk`，Dense 空间并行度为 M，则 Dense 纯算术下界为 `68,837,800/(16×M×f_clk)`；当前 DW16 通路下界为 `15,685,200/(16×f_clk)`。在 100 MHz 下，按两者分时执行相加为 `T_conv,min(M)≈43.024/M+9.803 ms`。例如 M=2 时约 31.315 ms。这是持续满利用的推导，不含量化、访存、调度等开销，不能作为实际帧率保证。

### 9.3 当前整机仿真观测

以下已有结果使用 `M_LANES=2`、`QUANTIZER_LANES=1`、100 MHz。它们描述该参数组合，不限定其他规模配置的吞吐。

| 用例 | 两次 CPU 结果间隔 | 100 MHz 换算 | 等效结果频率 |
|---|---:|---:|---:|
| 零 RGB 空场景 | 20766391 周期 | 207.66391 ms | 约 4.82 次/s |
| 自然人脸场景 | 20785256 周期 | 207.85256 ms | 约 4.81 次/s |

该间隔来自实际 CPU、NPU、Video 与 CDC 的两帧 RTL 仿真，DDR 存储为代理。它不是单层 NPU 用时、纯 MODEL 用时或板上长期有效输出 fps。当前配置已明显超过 30 fps 对应 33.33 ms 和 24 fps 对应 41.67 ms 的间隔，性能仍需优化。[R3]

后续应分别累计 CPU 图解析和 MMIO、Dense、DW、量化、输入/参数 DMA、输出写回、CPU 后处理、共享仲裁等待、显示等待；统计热帧与冷模型开销，保留 frame_id 与实际显示提交时间。重显旧帧或同帧切换模式不能增加有效输出帧计数。

## 10 验证结果与复现入口

### 10.1 已有证据的实际范围

| 层次 | 已有结果 | 覆盖范围 |
|---|---|---|
| CPU 图驱动主机测试 | 582 项通过 | 实际 C 图驱动；MMIO 和内存为 mock |
| NPU MMIO RTL | 464 项通过 | AW/W 独立、背压、锁存、身份 ACK、退休门槛和故障 |
| 层核与 DMA 两帧 | 79 次预检、158 次执行；每帧 26368 B 一致 | 真实层核及 DMA；服务内存代理，无 CPU |
| 本地 FIFO 适配 | 3202888 检查通过 | 包含全部公开端口、CE、X 载荷、clear/reset |
| DW 本地适配 | 1781292 检查通过 | 10000 组、52578 tap、7476 结果及错误路径 |
| 新版实际 CPU 空场景 | PASS，0 错误 0 警告 | 六段 6916 包装载，4 采集、2 结果、2 显示、1 释放复用 |
| 新版实际 CPU 自然脸 | PASS，0 错误 0 警告 | 两帧各 1 脸，完整头和两完整显示帧逐像素核对 |
| 完整新融合 PDS 与 STA | 尚未通过最终验收 | 综合/映射数据已有，完整后布线签核未完成 |
| 新融合板测 | 待执行 | 不能用旧 B00/B01/B02 自检替代 |

自然脸用例原图框为 `(x=349, y=215, w=166, h=257)`。两份完整头、CPU 框及 800×600 显示像素均有匹配证据，但单张自然脸不覆盖密集多人、低分独立框和排序反例。[R2][R3][R11]

### 10.2 原始结果定位

| 证据 | SOC 下相对路径 |
|---|---|
| 当前功能与源码关联摘要 | `docs/npu/verification-20261103-payload-local-write.json` |
| 新版空场景整机 | `build/soc/face_system-20261102T181751_435455Z/result.json` |
| 新版自然脸整机 | `build/soc/face_system-20261102T183452_302498Z/result.json` |
| 原正式综合及物理尝试 | `build/video/pds/20261102T181751_328291Z/` |
| 参数适配来源 | `rtl/npu/PAYLOAD_ADAPTATIONS.json` |

原正式物理尝试后续因详细布线未收敛受控停止，完整 STA 未产生；后续候选仍单独保留身份。本文引用 SYN/dev_map 结果，不把已停止的原目录写为仍在运行或把工具中止写为完整 STA 失败。[R12]

### 10.3 复现入口

以下命令在 SOC 根目录执行，使用既有 Windows 工具环境和冻结资产路径；应另建输出目录保留本次运行，不覆盖历史报告。

```powershell
python scripts/soc/gen_layer_config.py --check
python scripts/soc/test_cpu_graph.py
python scripts/soc/check_cpu_graph_sources.py
python scripts/soc/run_cpu_graph_migration.py --full
python scripts/soc/run_face_avatar.py
python scripts/soc/run_face_system.py --board-profile --timeout 7200
```

生成检查确认 C/RTL 与配置一致；主机测试、层核测试和真实 CPU 整机测试分别给出结论。自然脸 fixture、实际 THB1 装载参数及发布审核应沿用对应结果目录和第 168 篇的冻结入口，不以默认零图用例替代自然脸验收。本次文档修订核对已有结果，没有重新运行上述长时仿真或物理实现。

## 11 待关闭问题与验收条件

| 项目 | 关闭条件 |
|---|---|
| CPU NMS 候选截断 | 保留独立低分框等反例通过；候选集合变化重新评估质量 |
| 稳定排序和几何等价 | 最终 score 并列、Q16、裁边、IoU 门限与固定参考一致或经正式修订 |
| 全板物理出口 | 同源源码/ELF/模型，12 钟全角五类时序及 23 组 max_skew 完整通过 |
| 新版实际板测 | DDR、HDMI、UART 初始化、框出现/移动/消失、复位重装和连续运行记录 |
| 性能目标 | 明确最终需求口径，给出有效输出 fps、延迟、抖动和丢帧测量 |
| 固定头像 | CPU 选择与素材装载、同帧提交、边界缩放/Alpha、资源和时序重新验收 |

B00/B01/B02 的 RAM、APM、DDR 自检和用户反馈是平台历史证据；其中 B02 是已验收自检程序，不是本版 YuNet 融合程序。发布包必须绑定实际合格的位流、掩码、模型、固件、STA/CDC 与同源功能证据。[R3][R14]

## 12 对原 SoC 规格的修改位置

随附完整规格修订稿保留原章节编号及 CPU、Video 正文，修改集中在以下 NPU 内容，并追加必要的集成状态说明。

| 原章节 | 修订内容 |
|---|---|
| 文档属性与第 1 章 | 增加 NPU 修订日期、当前实现与需求目标的区别 |
| 第 2 章 NPU 行与第 4 章职责 | 统一参数化计算规模、CPU 图调度/校验及九头边界 |
| 第 3.3 节 | 补 CPU/NPU 同根 100 MHz 与 DDR UI 125 MHz 的当前连接 |
| 第 6 章 | 替换固定图、混合位宽、九头布局和软件质量证据 |
| 第 7 章 | 加入确认的架构图，按图说明控制、DMA、Data Streamer、Conv. Core、辅助算子和共享 Q，并配模块波形 |
| 第 10.3 节 | 更新输入/输出槽、工作区及参数镜像；不改公共大区基址 |
| 第 11.1 与 11.2 节 | 更新 CPU 图驱动和MMIO 控制与结果交接 |
| 第 11.4 与 11.5 节 | 标明无关键点，记录 CPU 后处理实际行为与开放问题 |
| 第 12 至 14 章 | 补模型初始化、实际资源/周期和分层验证状态 |
| 第 18 至 20 章 | 补当前 NPU 验收项、摘要与证据索引 |

原 CPU 功能清单、Video 三模式和头像字段仍表示对应路线的设计目标；本次不据 NPU 调试资料宣称它们全部已实现，也不扩大本次修改为 CPU 或 Video 的独立规格重写。

## 13 依据文件与图片来源

下列路径以文首 SOC、DBG 为根。每份交付附带 `sources_manifest.json`，保存引用文件和图片的来源标识与 SHA256，便于追溯本次修订读取的快照。

| 编号 | 文件 | 主要用途 |
|---|---|---|
| R1 | SOC `docs/TriHaRiscv_SoC_Design_Spec_v0.6.md` | 原章节、全屏系统边界及原性能口径 |
| R2 | DBG `word/167_CPU图调度迁移与单算子接口实现验证.md` | 调度迁移、单算子控制、100 MHz 和分层测试 |
| R3 | DBG `word/168_CPU调度融合首版FPGA下载程序构建与验收.md` | 构建参数、整机回归、性能与发布门槛 |
| R4 | SOC `config/npu_layer_regs.json`、`config/npu_layer_sources.f`、`rtl/npu/npu_layer_top.v`、`rtl/npu/npu_layer_mmio.v` | 正式 ABI、文件闭包和完成条件 |
| R5 | DBG `word/11_YuNet模型与算子评估.md`、`word/24_INT8校准与整数数值方案.md`、`yunet/models/integer_numerics_v1.json` | 固定图、MAC、数值和 PTQ 评价 |
| R6 | DBG `yunet/reports/b03_runtime_v1/compile_report.json`、`runtime_decoded.json` | 79 算子、NPM3 和九头偏移 |
| R7 | SOC `sw/drivers/npu_graph.c`、`rtl/npu/upstream/b03/rtl/platform/b03_layer_exec_payload.v` | 准入、调度、量化选择及 O 缓存 |
| R8 | SOC `config/soc_memory.json`、`rtl/soc/npu_service_axi128.v` | 当前物理地址、相对绑定与 AXI 适配 |
| R9 | DBG `word/166_新版CPU融合工程审查与待统一接口.md`、SOC `sw/drivers/npu_cpu_post.c` | 后处理反例及当前软件实现 |
| R10 | DBG `word/107_B03紧凑运算与行存储规格.md` | APM SIMD 累加及历史数值推导，资源不移植到当前整板 |
| R11 | DBG `word/169_NPU数据载荷复位优化候选与验收门槛.md`、SOC `rtl/npu/PAYLOAD_ADAPTATIONS.json` | 已选择的 FIFO/DW 本地适配 |
| R12 | DBG `word/175_NPU辅助参数偏移预计算与时序收敛评估.md`、`word/176_NPU局部复位释放寄存树备选评估.md`、`word/178_整板布线拥塞定位与工具参数评估.md` | 候选身份和物理尝试边界 |
| R13 | DBG `word/177_CPU与NPU共用100MHz时钟核查.md` | 时钟核查与最终 STA/CDC 条件 |
| R14 | DBG `README.md` | 当前融合程序与 B00/B01/B02 的区别 |

| 图号 | 来源与验证记录 | 交付图片 |
|---|---|---|
| 图 1 | 用户提供的 [可编辑 draw.io 图源](TriHaRiscv_NPU_Reference_Style.drawio) | `TriHaRiscv_NPU_Reference_Style.png` |
| 图 2 | 归档 VCD `SOC/build/soc/cpu_graph_rtl/20261102T034839_254662Z/layer_mmio.vcd` | `assets/01_layer_mmio_actual_vcd.png` |
| 图 3 | 归档 VCD `DBG/build/platform/mem_bridge_v1_final/hmic_bridge.vcd` | `assets/npu_dma_retirement.png` |
| 图 4 | 归档 VCD `DBG/build/platform/b03_vector_quant_tdm4_dev02/simulation/trace.vcd` | `assets/vector_dma_rw.png` |
| 图 5 | 归档 VCD `SOC/build/npu/payload_reset/20261102T174626_621493Z/feature_payload.vcd` | `assets/03_fifo_payload_epoch_actual_vcd.png` |
| 图 6 | 归档 VCD `DBG/build/platform/b03_model_input_resident_v1/simulation/trace.vcd`；归档 VCD `DBG/build/platform/b03_gather_pipeline_dev02/simulation/trace.vcd` | `assets/npu_input_gather.png` |
| 图 7 | 归档 VCD `DBG/build/platform/b03_model_input_resident_v1/simulation/trace.vcd` | `assets/weight_input_read.png` |
| 图 8 | 归档 VCD `DBG/build/platform/b03_model_input_resident_v1/simulation/trace.vcd` | `assets/conv_channel_params.png` |
| 图 9 | 归档 VCD `DBG/build/platform/b03_model_tile_v1/tile/trace.vcd` | `assets/npu_output_mask.png` |
| 图 10 | 归档 VCD `DBG/build/platform/b03_model_tile_v1/array/trace.vcd`；归档 VCD `DBG/build/platform/b03_model_tile_v1/tile/trace.vcd` | `assets/npu_dense_accumulate.png` |
| 图 11 | 归档 VCD `DBG/build/platform/b03_layer_dma_release_dev01/simulation/trace.vcd` | `assets/dw16_case7.png` |
| 图 12 | 归档 VCD `DBG/build/platform/b03_model_q8_v1/simulation/trace.vcd` | `assets/npu_q_rne.png` |
| 图 13 | 归档 VCD `DBG/build/platform/b03_vector_quant_tdm4_dev02/simulation/trace.vcd` | `assets/vector_q_requests.png` |
| 图 14 | 归档 VCD `SOC/build/npu/aux_rx_words_ce0_wave/20261103T001244_162336Z/aux_rx_words.vcd` | `assets/npu_aux_coeff_rx.png` |
| 图 15 | 归档 VCD `DBG/build/platform/b03_layer_dma_release_dev01/simulation/trace.vcd` | `assets/npu_pool_resize.png` |
| 图 16 | DBG `word/仿真截图/CPU_graph_board_20261102_v1/01_local_reset_actual_vcd.png` | `assets/02_local_reset_actual_vcd.png` |
| 图 17 | DBG `word/仿真截图/CPU_graph_board_20261102_v1/02_ingress_ready_actual_vcd.png` | `assets/04_ingress_ready_actual_vcd.png` |

架构图沿用原 draw.io 图源及原导出图片，内容与字节均未改动。完整规格第 7 章对应的 14 幅波形替换为 ModelSim Wave 原生窗口截图；其他章节的 2 幅归档图保持原样。每幅新截图的同名 JSON 记录原始 VCD 的 SHA256、实际信号、绝对时间窗和原生截图面板；多面板仅上下拼接原始像素。`assets/native_exports/` 保留 ModelSim 直接导出的 PostScript 波形。旧图片的来源记录标为已被替代，原始归档测试结论不变。
