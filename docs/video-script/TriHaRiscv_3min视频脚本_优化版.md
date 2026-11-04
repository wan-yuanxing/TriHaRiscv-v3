# TriHaRiscv 三分钟项目介绍视频脚本 · 优化版

作品名称：**基于RISC-V CPU与NPU的异构视觉处理系统**  
事实基线：2026年11月3日；当前主工程 `TriHaRiscv-main`；应用发布版 `face-box-20261103`。CPU性能分别引用对应冻结配置的独立板测。  
成片时间轴：**00:00–03:00，共180秒、8个连续分镜**；实板演示40秒。  
旁白：553个汉字，不计标题、时间标签、标点及英文缩写。考虑技术词读音和句间停顿，预计口播约156秒，合理范围146–164秒；剩余时间安排看表、换镜和原速观察。此为文本估时，尚未录音测时。

## 一、完整分镜

旁白栏与纯旁白TXT逐字一致。素材编号在第三节给出绝对路径；“待制作/待拍摄”属于制作状态，不作为成片字幕。屏幕文字分批出现，避免同时堆放全部参数。

| 时间 / 时长 | 镜头内容 | 完整旁白 | 关键字幕 | 对应素材 | 尚需补拍或制作 |
|---|---|---|---|---|---|
| **00:00–00:15 / 15秒**<br>作品介绍与实机效果 | 00:00–00:04：真实检测画面与开发板同框。00:04–00:09：叠入作品名。00:09–00:15：转为CPU、NPU、Video简图，突出CPU。 | 大家好，这是 TriHaRiscv。我们在紫光同创 FPGA 上构建 RISC-V 处理器，用性能测试和人脸检测，展示处理器设计与系统协同。 | TriHaRiscv<br>基于RISC-V CPU与NPU的异构视觉处理系统<br>盘古100pro+ · PG2L100H | M01（实物照片）；A01实拍可截取开场，状态为待拍摄。 | G01：标题与系统简图待制作；A01：动态开场待拍摄。 |
| **00:15–00:40 / 25秒**<br>CPU流水线与单/双发射 | 00:15–00:22：横向展开六级流水线。00:22–00:32：并排演示单发射与双发射，配对条件不满足时B槽留空。00:32–00:40：放大指令供给和前递通路，再接“性能 / 资源”两个比较维度。仅突出相关局部，不将整张复杂图缩小。 | CPU 采用六级顺序流水线，可在综合时选择单发射或双发射。单发射每周期最多发射一条指令，双发射在满足配对条件时最多发射两条。我们围绕两种配置设计指令供给和数据前递通路，再通过实测比较性能与资源开销。 | 六级顺序流水线 · 单/双发射（综合时选择）<br>Verilog · RV32IM / Zicsr / Zifencei<br>流水级标签：IF1、IF2、ID、E1、E2、WB | M02（CPU架构图）；S2、S3提供功能与结构依据。 | G02：六级高亮、单/双发射配对动画待制作。 |
| **00:40–00:55 / 15秒**<br>缓存、分支预测与控制 | 00:40–00:47：Cache与预测器局部依次高亮。00:47–00:55：串口结果、异常/中断示意与架构图切换。参数分两张字幕呈现。 | 缓存复用指令和数据，分支预测提前选择取指方向。配合异常、中断处理和串口调试，我们检查不同存储条件下的程序运行情况。 | 图1：I/D Cache各16 KiB · 两路组相联 · 32 B行<br>图2：BTB / BHT / RAS · 异常/中断 · UART | M03（取指前端）；M08（仿真）；S3提供Cache及控制依据。 | G03：Cache/预测器局部图与分批参数字幕待制作。 |
| **00:55–01:25 / 30秒**<br>CoreMark实测与性能分析 | 00:55–01:01：真实串口截图，放大5000次迭代、计时、CRC及BOARD_PASS。01:01–01:10：四配置表，按SRAM、Cache＋DDR分组显现。01:10–01:17：高亮双发射得分及同存储条件下的约34.0% / 26.2%差异。01:17–01:25：切换高亮到单发射的CoreMark/LUT，揭示性能与资源取舍。 | 在一百兆赫兹下，四组配置均完成五千次迭代，运行超过十秒。双发射配合片上存储，达到每兆赫兹四点零九三分。双发射配置得分更高，单发射配置的单位逻辑资源性能更好。这里比较的是完整配置，差异不能全部归因于发射宽度。 | CPU独立板测 · 100 MHz · CoreMark 1.0<br>5000次迭代 · 每组>10秒<br>比较表见下节；末屏：双发射得分更高 / 单发射单位资源性能更高 | M04–M07（四配置串口原图）；S5、S6、S11、S12。 | G04：四配置比较表及分步高亮待制作。原始串口截图已存在。 |
| **01:25–01:40 / 15秒**<br>分层验证与片上波形 | 01:25–01:29：ModelSim原始仿真波形。01:29–01:32：完整实板串口测试结果。01:32–01:40：Fabric Debugger原始采样，局部放大指令完成与流水线状态，保留信号名和刻度。 | 验证分为三层：指令集和模块仿真检查功能，实板测试核对运行结果，片上逻辑分析观察流水线状态。测试结果与原始波形一并保存。 | ModelSim：指令集及模块仿真<br>实板测试：串口原始记录<br>Fabric Debugger：片上采样（单发射TCM） | M08（ModelSim）；M04或M06（板测）；M09–M11（Fabric Debugger）。 | G05：波形局部放大与来源标签待制作；不需要重新采集片上波形。 |
| **01:40–02:05 / 25秒**<br>CPU/NPU协同与应用架构 | 01:40–01:47：从“CPU独立性能测试”转到“应用控制配置”，显示精简单发射、关闭Cache、CPU/NPU 50 MHz。01:47–01:56：数据流按预处理、NPU卷积、CPU后处理依次高亮。01:56–02:05：指向Video输出，并用帧号及三帧槽小图保留原图和结果的对应关系。 | 进入应用，我们采用关闭缓存的精简单发射 CPU 承担调度，CPU 与 NPU 运行在五十兆赫兹。YuNet 的主要卷积由 NPU 以八位定点运算完成，硬件支持普通卷积和深度卷积。CPU 再完成检测框解码和非极大值抑制。 | 精简单发射 · Cache关闭 · CPU/NPU 50 MHz<br>YuNet · 8位定点 · 普通/深度卷积<br>CPU：调度 / 解码 / NMS | M12（NPU微架构）；S3、S4、S8、S13。 | G06：任务分工数据流和三帧槽示意待制作。 |
| **02:05–02:45 / 40秒**<br>真实FPGA人脸检测演示 | 02:05–02:45：待拍摄的40秒连续实板过程。采用同一段原速视频，按下方五个拍摄窗口完成连接展示、入画出框、移动更新、无脸清框和持续更新；可裁切放大输出屏，但不改变时间进程。 | 现在看实板演示：视频源连接开发板，处理后的画面送到显示器。输入为八百乘六百。人脸入画后出现检测框；位置改变，框随之更新。系统将检测结果与对应的原始画面匹配，再叠加检测框。切换到无人脸画面，框消失，后续画面仍继续更新。 | 真实实板运行 · 800×600 HDMI<br>入画出框 → 移动更新 → 无脸清框<br>原速呈现，不叠加未实测的FPS或延迟数字 | M01只可说明连接关系；实际动态过程使用A01，当前待拍摄。功能依据S9。 | A01：连接、入画、移动、无脸、持续更新五项均待拍摄；不能用验收JSON替代视频。 |
| **02:45–03:00 / 15秒**<br>成果总结 | 02:45–02:52：回到作品实物，依次出现“可配置CPU”“性能板测”“真实人脸检测”。02:52–02:59：展示源码、发布包与技术报告。02:59–03:00：作品名定格。 | 我们已完成可配置 CPU 的性能板测和人脸检测整机功能验证，并归档源码、位流与复现材料。后续将补充应用测速，优化计算与搬运。谢谢。 | 已完成：CPU设计与板测 / 人脸检测整机验证<br>源码 · 位流 · 复现材料<br>下一步：应用测速与优化 | M01；S8发布包说明；技术报告及发布目录截图待制作。 | G07：成果收束画面、发布目录截图和尾卡待制作。 |

### 第4段：四配置性能画面

固定标题：**CPU独立板测｜100 MHz｜CoreMark 1.0｜5000次迭代｜每组>10秒**。

| 配置 | CoreMark/MHz | CPU核LUT | CoreMark/LUT |
|---|---:|---:|---:|
| 单发射＋SRAM | 3.055 | 6,139 | **0.04977** |
| 双发射＋SRAM | **4.093** | 9,677 | 0.04229 |
| 单发射＋Cache＋DDR | 2.497 | 6,507 | **0.03838** |
| 双发射＋Cache＋DDR | **3.152** | 9,707 | 0.03247 |

先显示真实串口结果，再显示表格。按存储条件分成两组；先高亮得分，再高亮CoreMark/LUT，不让观众同时寻找所有数字。

- **性能比较：**SRAM配置中，双发射CoreMark/MHz比单发射高约34.0%；Cache＋DDR中高约26.2%。按表中数值计算分别为 `(4.093/3.055−1)×100%` 和 `(3.152/2.497−1)×100%`；采用原始未取整分数，保留一位小数仍为34.0%和26.2%。
- **资源取舍：**两种存储条件下，双发射得分更高，但CoreMark/LUT均低于相应单发射配置。CPU核LUT不含整机、DDR控制器等资源。
- **屏幕脚注：**“不同完整配置的比较；差异不全由发射宽度产生。”100 MHz为已验证工作点，不写成最高Fmax或官方认证成绩。
- **计时复核：**单发射SRAM、双发射SRAM、单发射Cache＋DDR、双发射Cache＋DDR依次为16.3647、12.2166、20.0205、15.8621秒，均超过10秒。
- **原始截图差异：**M06固件打印的是原发布版5,933 LUT；本稿按技术报告调试构建口径保留6,139 LUT及0.04977。不得改写原始截图。M06首次使用时加注“图内资源为原发布值；比较表采用调试构建口径”，以S5的资源说明为依据。

### 第6段：从CPU测试转入应用

图中明确分成两种配置，不使用同一个“100 MHz双发射”标签贯穿视频：

| 场景 | CPU配置 | 频率与分工 |
|---|---|---|
| CPU独立性能板测 | 单/双发射；SRAM或Cache＋DDR | CPU 100 MHz；测CoreMark和CPU核资源。 |
| 当前人脸检测整机 | 精简单发射；Cache关闭 | CPU/NPU 50 MHz；CPU调度、解码及NMS，NPU执行主要卷积。 |

应用数据流按 **HDMI输入 → 图像预处理 → NPU卷积计算 → CPU检测结果处理 → HDMI显示** 制作。

主图下方的小示意保留“原图帧号—检测帧号”的对应关系及A/B/C三帧槽，表示采集、处理和显示各自持有的槽。模型输入320×320、8位数据格式等信息在局部短标签出现。图示不能画成系统只有一块帧缓冲，也不能暗示采集、计算与显示已达到未测得的满速并行。

### 第7段：40秒实板拍摄单

**A01状态：五项均待拍摄。** 已有人工板测验收记录，尚未收到可剪辑的动态录像。下表规定拍摄动作与观察窗口，不定义或承诺响应延迟。

| 时间 | 时长 | 拍摄动作与观察对象 | 对应旁白安排 |
|---|---:|---|---|
| 02:05–02:14 | 9秒 | 输入视频源、FPGA板和输出屏同框，拍到实际HDMI连接；显示800×600短标签。 | 从“现在看实板演示”读到“输入为八百乘六百”。 |
| 02:14–02:22 | 8秒 | 人脸进入输入画面，保留真实等待，拍到输出检测框出现。 | “人脸入画后出现检测框”；余时观看。 |
| 02:22–02:33 | 11秒 | 改变人脸位置，输入与输出保持可比，观察框更新。 | 从“位置改变”读到“再叠加检测框”；留出观察空隙。 |
| 02:33–02:40 | 7秒 | 切换无人脸画面，拍到框消失。 | “切换到无人脸画面，框消失”；余时观看。 |
| 02:40–02:45 | 5秒 | 持续改变无脸输入内容，拍到输出继续更新。 | “后续画面仍继续更新”；保留片刻现场声。 |

尽量一次连续拍满40秒。可做同步画中画或画面裁切，不加速、不跳过推理等待；实际动作若未落入建议窗口，应调整动作节奏重新拍摄，不能剪掉等待伪造效果。画面扫描频率、独立Video测试帧率及仿真结果速率均不作为应用推理FPS展示。

## 二、技术信息与事实范围

CPU设计以六级顺序流水线和综合时可选单/双发射为重点。保留RV32IM、Zicsr、Zifencei、Verilog、前递、动态分支预测及两路I/D Cache；这些共同构成可配置处理器，不逐项包装成独立创新。

应用采用YuNet/B03框检测部署图：NPU执行计算图，以8位定点运算支持普通卷积与深度卷积，CPU执行调度、检测框解码和非极大值抑制，Video按帧号把检测结果叠加到对应原图。8位激活为U8/S8、权重为S8，完整结果接口为INT32；不把普通卷积所有内部累加器笼统说成32位。

| 保留信息 | 呈现位置与范围 |
|---|---|
| I/D Cache各16 KiB、两路组相联、32 B行；D-Cache写回/写分配 | 第3段图示和技术依据；属于通用CPU配置，应用版关闭Cache。 |
| BTB/BHT/RAS、机器模式异常与中断、UART | 第3段局部字幕；不连续口播器件参数。 |
| riscv-tests 50/50、ACT4 53/53 | 作为第5段可选角标，须标注“单发射配置仿真”；不扩大到全部版本。 |
| ModelSim仿真与Fabric Debugger片上采样 | 第5段分别标注；片上采样来自单发射TCM调试配置。 |
| CPU/NPU 50 MHz、Video/DDR 125 MHz、像素40 MHz | 第6段突出50 MHz，其余保留在制作依据，不挤入旁白。 |
| 整机42,531 LUT、43,408 FF、77.5 DRM36K等效块、58 APM | 保留为综合阶段资料；结尾不集中展示，不与CPU核资源混算。 |
| 内部后布线最差Setup +0.183 ns、Hold +0.108 ns | 保留为内部路径证据；不声称外部HDMI I/O AC已正式签核。 |

当前已验收功能为出框、位置更新、无脸清框与画面继续更新。持续实板推理FPS、端到端延迟和识别准确率仍无本稿可用的实测数据。头像替换、五点、风格迁移及表情识别不纳入本片。

选题一的高阶模型文字为YOLO或轻量版大模型，当前部署为YuNet。本片展示已有AI协同成果，不宣称该模型条款或全部高阶要求已满足。该差异保留在制作依据，不新增实验或迁移方案。

## 三、素材清单

以下12项静态素材已核对文件存在，可按本稿裁切、放大或加标签；动态效果不能由静态照片替代。

| 编号 | 素材用途 | 现有文件 | 状态 |
|---|---|---|---|
| M01 | 实物与连接照片 | [triha-system-overview-photo.jpg](<D:/FPGA/TriHaRiscv-main/docs/technical-report/figure/triha-system-overview-photo.jpg>) | 已有静态素材 |
| M02 | CPU六级架构图 | [rv32-soc-page5.pdf](<D:/FPGA/TriHaRiscv-main/docs/technical-report/figure/rv32-soc-page5.pdf>) | 已有静态素材 |
| M03 | CPU取指前端图 | [rv32-soc-page6.pdf](<D:/FPGA/TriHaRiscv-main/docs/technical-report/figure/rv32-soc-page6.pdf>) | 已有静态素材 |
| M04 | 双发射SRAM串口原图 | [cpu-dualissue-sram-coremark-uart-original.png](<D:/FPGA/TriHaRiscv-main/docs/technical-report/figure/cpu-dualissue-sram-coremark-uart-original.png>) | 已有静态素材 |
| M05 | 双发射Cache＋DDR串口原图 | [cpu-dualissue-cache-ddr-coremark-uart-original.png](<D:/FPGA/TriHaRiscv-main/docs/technical-report/figure/cpu-dualissue-cache-ddr-coremark-uart-original.png>) | 已有静态素材 |
| M06 | 单发射SRAM/TCM串口原图 | [cpu-tcm-coremark-uart-original.png](<D:/FPGA/TriHaRiscv-main/docs/technical-report/figure/cpu-tcm-coremark-uart-original.png>) | 已有静态素材 |
| M07 | 单发射Cache＋DDR串口原图 | [cpu-l1-cache-ddr-coremark-uart-original.png](<D:/FPGA/TriHaRiscv-main/docs/technical-report/figure/cpu-l1-cache-ddr-coremark-uart-original.png>) | 已有静态素材 |
| M08 | ModelSim外部中断仿真 | [cpu-system-external-irq-modelsim-original.jpg](<D:/FPGA/TriHaRiscv-main/docs/technical-report/figure/cpu-system-external-irq-modelsim-original.jpg>) | 已有静态素材 |
| M09 | Fabric Debugger链表采样 | [cpu-sram-list-native.png](<D:/FPGA/TriHaRiscv-main/docs/technical-report/figure/cpu-sram-list-native.png>) | 已有静态素材 |
| M10 | Fabric Debugger矩阵采样 | [cpu-sram-matrix-native.png](<D:/FPGA/TriHaRiscv-main/docs/technical-report/figure/cpu-sram-matrix-native.png>) | 已有静态素材 |
| M11 | Fabric Debugger状态机采样 | [cpu-sram-state-native.png](<D:/FPGA/TriHaRiscv-main/docs/technical-report/figure/cpu-sram-state-native.png>) | 已有静态素材 |
| M12 | NPU微架构图 | [npu-microarchitecture.pdf](<D:/FPGA/TriHaRiscv-main/docs/technical-report/figure/npu-microarchitecture.pdf>) | 已有静态素材 |

A01为待拍摄实板录像；G01–G07为待制作的标题、图示、高亮、性能比较、波形标签、数据流与尾卡。本次交付是视频文稿，未将这些后期素材写成已完成文件。

## 四、技术依据

| 索引 | 文件 | 支持内容 |
|---|---|---|
| S1 | [选题一要求](<D:/FPGA/TriHaRiscv-v3/docs/紫光同创选题指南.pdf>) | PDF第9–11页，印刷页7–9；延用上一轮已核对内容。 |
| S2 | [当前功能配置](<D:/FPGA/TriHaRiscv-main/docs/technical-report/latex/chapters/01-overview/01-功能与特性.tex>) | Verilog、RV32IM、Zicsr、Zifencei、CPU与应用配置。 |
| S3 | [CPU设计](<D:/FPGA/TriHaRiscv-main/docs/technical-report/latex/chapters/02-system/02-CPU设计.tex>) | 六级顺序、综合时单/双发射、前递、Cache、预测器与精简控制配置。 |
| S4 | [NPU设计](<D:/FPGA/TriHaRiscv-main/docs/technical-report/latex/chapters/02-system/03-NPU设计.tex>) | 8位定点、普通/深度卷积、计算图执行及数值格式。 |
| S5 | [性能与片上采样](<D:/FPGA/TriHaRiscv-main/docs/technical-report/latex/chapters/03-results/03-特性成果.tex>) | 四配置板测、资源口径、片上波形及单发射TCM截图差异说明。 |
| S6 | [CPU板测证据索引](<D:/FPGA/TriHaRiscv-main/docs/verification/cpu/report_configurable_issue_2026-11-02/README.md>) | 双发射板测、原图、测试条件及独立运行的周期差异。 |
| S7 | [单发射ISA回归](<D:/FPGA/TriHaRiscv-main/docs/verification/cpu/isa_support/README.md>) | riscv-tests 50/50、ACT4 53/53；不扩大到全部CPU配置。 |
| S8 | [当前应用发布版](<D:/FPGA/TriHaRiscv-main/releases/face-box-20261103/README.md>) | 50/125/40 MHz、YuNet/B03框检测与已验收功能。 |
| S9 | [实板功能验收](<D:/FPGA/TriHaRiscv-main/docs/verification/soc/face_box_report_20261103/evidence/video/face_box_board_acceptance_20261103.json>) | 出框、位置更新、无脸清框、持续更新；没有自动录制视频或实板FPS。 |
| S10 | [整机证据与统计范围](<D:/FPGA/TriHaRiscv-main/docs/verification/soc/face_box_report_20261103/README.md>) | 综合资源、内部时序、仿真结果间隔的适用范围。 |
| S11 | [性能指标表](<D:/FPGA/TriHaRiscv-main/docs/technical-report/latex/chapters/01-overview/04-主要性能指标.tex>) | 本稿四行数据的直接核对依据。 |
| S12 | [原图及复算索引](<D:/FPGA/TriHaRiscv-main/docs/verification/cpu/report_configurable_issue_2026-11-02/benchmark-index.json>) | 双发射完整周期、CPU核LUT、精确分数及原图哈希。 |
| S13 | [应用顶层配置（只读核对）](<D:/FPGA/TriHaRiscv-main/fpga/pg2l100h/rtl/triha_face_board_top.sv>) | CACHE_ENABLE=0、MINIMAL_CONTROL_CPU=1；本轮不修改。 |

本轮仅修改视频文稿，不改变RTL、约束、模型或硬件配置，不启动新的硬件测试。已知原图与报告的统计口径差异在本稿及优化说明中登记，不猜测修正原始证据。

