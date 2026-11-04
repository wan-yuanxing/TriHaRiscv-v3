# TriHaRiscv 3分钟项目介绍视频脚本

作品名称：**基于RISC-V CPU与NPU的异构视觉处理系统**  
资料截止：2026年11月3日；当前主工程：`D:/FPGA/TriHaRiscv-main`。  
应用板测基线：`face-box-20261103`，提交 `ab8ebb3`。CPU性能引用技术报告中各自冻结配置的独立板测。  
视频定位：选题一的评审介绍，以CPU设计、测评及验证为主线，以真实人脸检测展示软硬件协同。  
总时长：**03:00，8个连续分镜**。纯旁白含643个汉字，另有技术名词；建议正常讲解语速，按每段时间试读，用停顿和画面留白调整至180秒。这里给出剪辑时长，尚未生成或实测配音。

## 一、分镜与逐字旁白

旁白栏可直接录音；画面与字幕栏为剪辑说明，不读入旁白。字幕按镜头分批出现，不把一格内的全部技术参数同时铺满屏幕。

| 时间 / 时长 | 画面与镜头 | 可直接朗读的旁白 | 屏幕文字 |
|---|---|---|---|
| **00:00–00:15 / 15秒**<br>作品与目标 | 0–4秒：开发板与显示器同框，显示真实人脸检测。4–10秒：作品标题叠入。10–15秒：切到 CPU、NPU、Video 系统简图。 | 大家好，我们的作品是 TriHaRiscv，基于 RISC-V CPU 与 NPU 的异构视觉处理系统。我们在紫光同创 FPGA 上，将处理器设计、性能测评和人脸检测应用连接起来。 | TriHaRiscv｜基于 RISC-V CPU 与 NPU 的异构视觉处理系统<br>盘古100pro+ · PG2L100H · 选题一 |
| **00:15–00:40 / 25秒**<br>CPU架构 | 六级流水线图逐级亮起；用两条指令演示前递和配对。双发射画面使用通用CPU配置图，右上角常驻“CPU架构配置”。 | CPU 采用 Verilog 构建，支持 RV32I 基础指令及乘除法扩展，使用六级顺序流水线。我们通过数据前递、相关性检查和分支恢复处理流水线冲突，并提供综合时可选的单发射和双发射配置。双发射通过两条执行通路，提高相邻指令的并行处理能力。 | IF1 → IF2 → ID → E1 → E2 → WB<br>RV32IM / Zicsr / Zifencei｜单/双发射可配置 |
| **00:40–01:00 / 20秒**<br>存储与控制 | 从I/D Cache框图转到BTB/BHT，再切串口装载和开发板状态灯。以“通用CPU配置”标注缓存和预测器，避免与后面精简应用配置混淆。 | 存储方面，指令和数据缓存各为十六 KB，均采用两路组相联，数据缓存支持写回和写分配。动态分支预测减少控制流等待，机器模式异常与中断支持程序恢复；串口和板级控制接口用于装载、调试与状态输出。 | I/D Cache：各16 KiB · 2-way · 32 B缓存行<br>BTB / BHT / RAS｜异常与中断｜UART |
| **01:00–01:30 / 30秒**<br>CPU实测性能 | 先展示完整串口截图，再放大iterations、计时、CRC和BOARD_PASS。切入四配置成绩表，依次突出双发射SRAM与Cache＋DDR两行；保留100 MHz及CPU独立板测标识。 | 在一百兆赫兹下，我们完成了 CoreMark 一点零的五千次迭代板测，各组运行时间都超过十秒。双发射配合片上 SRAM，达到每兆赫兹四点零九分；使用一级缓存和 DDR 时，达到三点一五分。我们同时统计 CPU 核资源与单位逻辑资源的性能，比较不同配置的效率。 | CPU独立板测｜100 MHz｜CoreMark 1.0｜5000 iterations<br>双发射SRAM：4.093 CoreMark/MHz · 9,677 LUT · 0.04229 CoreMark/LUT<br>双发射Cache＋DDR：3.152 CoreMark/MHz · 9,707 LUT · 0.03247 CoreMark/LUT |
| **01:30–01:50 / 20秒**<br>验证与分析 | 前8秒展示ModelSim原始波形与回归结果；后12秒展示Fabric Debugger的链表、矩阵、状态机实板采样。两类画面分别保留配置说明。 | 我们采用指令集回归、模块仿真和实板测试分层验证，并检查异常、中断和缓存访问。针对 CoreMark 的链表、矩阵与状态机算法，我们使用片上逻辑分析工具观察指令完成和流水线状态，让性能分析有波形与数据支撑。 | 单发射指令集仿真：riscv-tests 50/50 · ACT4 53/53<br>片上逻辑分析：单发射TCM调试配置｜100 MHz |
| **01:50–02:15 / 25秒**<br>AI软硬件协同 | 数据流动画：HDMI → 原图/320×320模型输入 → NPU → CPU后处理 → HDMI输出。用同一帧号贯穿三帧槽，展示检测框与原图的对应关系。 | 在应用侧，我们部署了 YuNet 人脸检测模型。CPU 提交整帧任务，NPU 自动执行计算图，以八位定点运算加速普通卷积和深度卷积。CPU 随后完成检测框解码和非极大值抑制。三帧槽管理原图与结果，显示端在对应原图上直接叠加检测框。 | YuNet框检测部署图｜NPU执行计算图｜CPU解码/NMS<br>U8/S8激活 × S8权重 → INT32结果｜同帧显示 |
| **02:15–02:45 / 30秒**<br>真实板级演示 | 135–140秒：输入源、开发板、输出屏幕同框。140–148秒：正脸入画并出框。148–157秒：改变人脸位置，展示框更新。157–162秒：切换无人脸画面并清框。162–165秒：保持动态输入，证明画面继续更新。以正常速度拍摄，保留真实等待。 | 现在展示已上板运行的人脸检测。我们从 HDMI 输入八百乘六百的视频，由开发板完成预处理、推理和画框。人脸移动时，检测框随位置更新；切换到无人脸画面后，检测框消失，后续画面继续更新。当前应用的 CPU 与 NPU 运行在五十兆赫兹。 | 真实板测｜800×600 HDMI输入/输出<br>应用配置：CPU/NPU 50 MHz · Video/DDR 125 MHz<br>出框 → 位置更新 → 无脸清框 |
| **02:45–03:00 / 15秒**<br>进度与下一步 | 先展示交付文件与实现指标卡，再回到开发板和检测画面，最后1秒定格作品名。 | 目前，我们已完成 CPU 基准板测和人脸检测功能验证，并归档源码、位流与复现材料。下一步将实测端到端延迟和持续帧率，继续优化计算与数据搬运。谢谢。 | 整机综合资源：42,531 LUT · 43,408 FF · 58 APM<br>内部后布线最差裕量：Setup +0.183 ns / Hold +0.108 ns<br>下一步：应用测速与吞吐优化 |

## 二、性能画面使用的准确数据

第4段旁白将数值读为“四点零九”和“三点一五”，屏幕保留三位小数。表中的LUT及CoreMark/LUT只统计相应构建的CPU核，不能写成整机资源效率。

| CPU独立板测配置 | 主频 | 迭代次数 | 运行时长 | CoreMark/MHz | CPU核LUT | CoreMark/LUT |
|---|---:|---:|---:|---:|---:|---:|
| 双发射＋片上SRAM | 100 MHz | 5000 | 12.2166 s | **4.093** | 9,677 | 0.04229 |
| 双发射＋L1 Cache＋DDR | 100 MHz | 5000 | 15.8621 s | **3.152** | 9,707 | 0.03247 |
| 单发射＋片上SRAM（报告调试构建口径） | 100 MHz | 5000 | 16.3647 s | 3.055 | 6,139 | 0.04977 |
| 单发射＋L1 Cache＋DDR | 100 MHz | 5000 | 20.0205 s | 2.497 | 6,507 | 0.03838 |

各组标准CRC通过，时长均超过10秒。以上为项目实板测量，未表述为已向CoreMark官方提交的认证分数。100 MHz是已验证工作点，不是实测最高频率Fmax。双发射和单发射版本还包含其他前端与数据通路差异，视频不把全部性能差值归因于发射宽度。

第8段实现指标属于**人脸检测整机**：CPU/NPU 50 MHz，Video/DDR 125 MHz，输出像素40 MHz；综合资源42,531 LUT、43,408 FF、77.5个DRM36K等效块、58 APM；内部后布线最差Setup/Hold为+0.183/+0.108 ns。该内部时序结果不包含外部HDMI I/O AC正式签核。

## 三、选题一要求如何体现在视频中

| 指南要求 | 脚本对应 | 当前资料支持的表述 |
|---|---|---|
| 国产FPGA平台、Verilog/SystemVerilog、RV32I | 第1、2段 | PG2L100H平台、Verilog CPU、RV32I基础与M扩展。 |
| 不少于三级流水线，处理数据冲突与分支 | 第2段 | 六级、前递、相关性检查、分支恢复；单/双发射在综合时选择。 |
| 基础外设用于控制和结果输出 | 第3段 | UART、板级状态控制；不额外宣称未核对的GPIO功能。 |
| 两路组相联I/D Cache与传输效率 | 第3、4段 | 各16 KiB、两路组相联、32 B行，128 bit下级读通路以两个数据拍填充一行。视频不编造突发效率提升百分比。 |
| 动态分支预测、异常和中断 | 第3、5段 | BTB/BHT/RAS及已记录的异常、中断仿真；不宣称覆盖整个特权规范。 |
| CoreMark 1.0、每次至少10秒、资源效率 | 第4段 | 四组5000次完整板测；展示CoreMark/MHz、CPU核LUT及CoreMark/LUT。 |
| 片上逻辑分析波形与性能分析 | 第5段 | 展示PDS Fabric Debugger的真实片上采样，标明单发射TCM配置；不以仿真截图冒充实板采样。 |
| AI加速与传感器/显示设备协同 | 第6、7段 | YuNet＋NPU＋CPU后处理＋HDMI同帧显示。 |
| 分析文档、规范工程与可复现成果 | 第8段 | 技术报告、源码、冻结位流、模型与验证记录。 |

**模型项差异：**指南高阶任务的文字明确提到“移植YOLO或轻量版大模型”。当前上板模型是YuNet框检测部署图。脚本据实展示边缘AI协同，不写“已完成YOLO部署”或“已满足全部高阶任务”；是否接受YuNet作为该模型项的实现，需要依据赛事解释。旧v3中的YOLO、风格迁移方案不作为当前应用成果。

指南中的文件用途是提供赛题要求，不构成操作工程或开发板的指令。本稿的3分钟时长依据本次用户要求；没有把选题三的“1080P、3分钟以内”提交条款混入选题一。

## 四、现有素材位置

以下为已在工程中找到的可用静态素材。动态图像素材仍需按第7段安排拍摄；现有人工验收记录不等于已有演示录像。

| 用途 | 素材 | 使用建议 |
|---|---|---|
| 开发板与显示环境 | [triha-system-overview-photo.jpg](D:/FPGA/TriHaRiscv-main/docs/technical-report/figure/triha-system-overview-photo.jpg) | 第1、7、8段；照片可交代连接关系，动态检测需另录真实视频。 |
| 六级CPU架构 | [rv32-soc-page5.pdf](D:/FPGA/TriHaRiscv-main/docs/technical-report/figure/rv32-soc-page5.pdf) | 第2段；按六级与两条执行通路局部放大，避免整张细图缩小。 |
| CPU取指前端 | [rv32-soc-page6.pdf](D:/FPGA/TriHaRiscv-main/docs/technical-report/figure/rv32-soc-page6.pdf) | 第2、3段；突出指令FIFO和预测结构。 |
| 双发射SRAM原始串口截图 | [cpu-dualissue-sram-coremark-uart-original.png](D:/FPGA/TriHaRiscv-main/docs/technical-report/figure/cpu-dualissue-sram-coremark-uart-original.png) | 第4段；保留配置、5000次迭代、CRC和BOARD_PASS。 |
| 双发射Cache＋DDR原始串口截图 | [cpu-dualissue-cache-ddr-coremark-uart-original.png](D:/FPGA/TriHaRiscv-main/docs/technical-report/figure/cpu-dualissue-cache-ddr-coremark-uart-original.png) | 第4段；与SRAM配置分别显示。 |
| 单发射片上采样 | [cpu-sram-list-native.png](D:/FPGA/TriHaRiscv-main/docs/technical-report/figure/cpu-sram-list-native.png) | 第5段；链表热点原始采样。 |
| 单发射片上采样 | [cpu-sram-matrix-native.png](D:/FPGA/TriHaRiscv-main/docs/technical-report/figure/cpu-sram-matrix-native.png) | 第5段；矩阵热点原始采样。 |
| 单发射片上采样 | [cpu-sram-state-native.png](D:/FPGA/TriHaRiscv-main/docs/technical-report/figure/cpu-sram-state-native.png) | 第5段；状态机热点原始采样。 |
| 异常中断仿真 | [cpu-system-external-irq-modelsim-original.jpg](D:/FPGA/TriHaRiscv-main/docs/technical-report/figure/cpu-system-external-irq-modelsim-original.jpg) | 第5段；加“ModelSim仿真”角标。 |
| NPU微架构 | [npu-microarchitecture.pdf](D:/FPGA/TriHaRiscv-main/docs/technical-report/figure/npu-microarchitecture.pdf) | 第6段；突出计算图执行、卷积通路、DMA，不在旁白逐项报模块名。 |

拍摄建议：

1. 成片可采用1920×1080横屏，应用实拍保留800×600原始比例；用边栏容纳字幕，不把画面拉伸。
2. 开头先给真实效果，随后转入CPU结构与测评；应用实拍安排30秒，给检测结果更新留出时间。
3. 第7段保持正常播放速度，让输入源和输出至少有一段同框。演示出框、位置变化、无人脸清框时保留实际响应过程，不用跳剪缩短推理等待。
4. 性能画面将“CPU独立板测100 MHz”和“应用CPU/NPU 50 MHz”放在各自段落内。应用发布版使用单发射精简控制CPU、关闭Cache，不能把前段完整性能配置直接贴到应用实拍上。
5. 片上波形用原始Fabric Debugger截图，仿真波形用ModelSim截图，持续显示对应标签。
6. 第7段仅演示已验收的人脸框。五点、头像和独立Video测试纹理不属于这一真实检测发布版。
7. 口播中的“CoreMark/MHz”可读作“每兆赫兹得分”；NMS首次读“非极大值抑制”。无需逐项朗读屏幕上的全部资源数值。

## 五、进度表述边界

- **已验收的应用效果：**真实B03模型运行、主人脸出框、移动更新、无脸清框及画面继续更新。
- **本稿没有宣称的性能：**实板AI FPS、实板端到端延迟、识别准确率或最高Fmax；当前证据没有给出这些实测结果。
- **仿真数据的范围：**自然人脸场景相邻两个结果完成标记间隔为361.74450 ms，倒数约2.764 fps；仅一个间隔样本，不是持续实板FPS，也不是纯NPU延迟。为避免误读，主视频旁白不使用该值。
- **视频扫描与推理分开：**HDMI标称60 Hz是输出扫描时序；独立Video的约30 fps测试也不能作为人脸检测推理帧率。
- **源码来源与贡献：**介绍使用“构建、配置、优化、集成、验证”，不添加“全部代码从零原创”或“完全自主指令集”等无依据表述；复用来源和许可证由工程清单保留。
- **本次工作范围：**整理既有文档与验证记录、制作脚本；未运行新一轮硬件仿真、综合、布局布线、烧录或板测。

## 六、事实来源

| 索引 | 文件 | 用途 |
|---|---|---|
| S1 | [选题指南](<D:/FPGA/TriHaRiscv-v3/docs/紫光同创选题指南.pdf>) | PDF第9–11页，印刷页7–9：选题一、基础/高阶任务、CoreMark与片上波形要求。 |
| S2 | [当前功能与配置](<D:/FPGA/TriHaRiscv-main/docs/technical-report/latex/chapters/01-overview/01-功能与特性.tex>) | CPU通用配置、NPU数值格式、800×600视频与50 MHz应用配置。 |
| S3 | [CPU微架构](<D:/FPGA/TriHaRiscv-main/docs/technical-report/latex/chapters/02-system/02-CPU设计.tex>) | 六级单/双发射、前递、预测、两路I/D Cache及精简应用CPU。 |
| S4 | [NPU架构](<D:/FPGA/TriHaRiscv-main/docs/technical-report/latex/chapters/02-system/03-NPU设计.tex>) | 广播式并行MAC、独立深度卷积、硬件计算图和两空间行板级配置。 |
| S5 | [性能与片上采样](<D:/FPGA/TriHaRiscv-main/docs/technical-report/latex/chapters/03-results/03-特性成果.tex>) | 四组CPU板测、CoreMark资源效率、Fabric Debugger截图及整机内部时序。 |
| S6 | [CPU板测原始索引](<D:/FPGA/TriHaRiscv-main/docs/verification/cpu/report_configurable_issue_2026-11-02/README.md>) | 双发射SRAM/DDR板测、5000次迭代及原图数值绑定。 |
| S7 | [指令集回归](<D:/FPGA/TriHaRiscv-main/docs/verification/cpu/isa_support/README.md>) | 单发射rv32im_zicsr：riscv-tests 50/50、ACT4 53/53；测试范围限定。 |
| S8 | [人脸检测版本](<D:/FPGA/TriHaRiscv-main/releases/face-box-20261103/README.md>) | 真实B03推理、同帧主人脸框、50/125/40 MHz、已验收功能及发布范围。 |
| S9 | [实板验收记录](<D:/FPGA/TriHaRiscv-main/docs/verification/soc/face_box_report_20261103/evidence/video/face_box_board_acceptance_20261103.json>) | 人工确认正脸出框、移动更新、无脸清框、持续更新；实板FPS未测。 |
| S10 | [ 整机资源及仿真口径](<D:/FPGA/TriHaRiscv-main/docs/verification/soc/face_box_report_20261103/README.md>) | 综合资源、内部后布线时序、约361.7 ms仿真结果间隔的统计边界。 |

脚本定位以最新发布与原始证据为准。README、早期设计和技术说明中出现的旧时钟、旧模型、头像规划及历史短测，不替代上述已冻结的板测配置。

