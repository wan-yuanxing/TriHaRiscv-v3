# TriHaRiscv 技术报告

本目录维护基于自研RISC-V CPU与NPU的异构视觉处理系统技术报告。平台采用盘古100pro+（MES2L676-100HP），主控为PG2L100H-6IFBG676。应用为YuNet人脸检测与预设动漫头像叠加，通过单路HDMI输出800×600全屏画面，支持RAW、BOX和AVATAR三种模式。

正文直接编辑LaTeX，入口为 `latex/技术文档.tex`，编译结果为 `latex/技术文档.pdf`。系统设计依据位于 `../TriHaRiscv_SoC_Design_Spec_v0.6.md`。

Video从同一800×600源帧生成RGB888原图、400×300 RGB888预览图和320×320 UINT8 BGR NCHW模型输入。模型分支采用固定5:2双线性缩放得到320×240有效图像，上下各补40行零值；每帧307200字节，输入槽间隔320 KiB。核心时钟125 MHz，输出像素时钟40 MHz，1056×628光栅对应约60.32 Hz。

2.5按图像采集、输入预处理、帧缓存管理、头像叠加和显示输出组织，正文包含视频子系统框图、采集参数、图像数据布局和光栅时序表。2.6同步输入格式、坐标恢复和帧调度，第三部分收录独立Video目标的连续三模式板测数据，附录E、F使用同一预处理与显示参数。板测采用测试框和算术纹理，新图更新率30.1548 fps；真实模型推理性能按整机测试单独记录。支撑材料见 ../verification/video/live_modes.md。

CPU章节采用 `D:/FPGA/TriHaRiscv-cpu-windows` 的六级单发射RV32IM/CSR设计：64位取指返回、512项BTB/BHT、4项RAS，GShare关闭。性能分别评估TCM和L1 Cache＋板载DDR两种配置；TCM以32 KiB本地SRAM实现，L1 I/D Cache各16 KiB，D-Cache采用写回与写分配。

TCM在两种配置中取得最高板测分数，CoreMark/MHz为3.055365628，CPU核6139 LUT，CoreMark/CPU LUT为0.049769761。文档以其2026-10-28通过100MHz实际后布线和板测的调试镜像讲解片上调试，list/matrix/state各有1024拍真实板上采样。证据为CPU工作树的 `docs/verification/cpu/sram_debug_led_fix_2026-10-28.md/.json`，原生数据位于 `build/cpu/sram-debug-ledreg-20261028-v2/captures-accepted/`。固件保留的5933-LUT打印值属于原发布版，正文按当前调试构建重新计算资源效率；原发布版5933 LUT及0.051497819独立保留。

L1 Cache＋板载DDR配置的2.497435168 CoreMark/MHz和6507个CPU核LUT引用同工作树的 `docs/verification/cpu/dcache_overlap_board.md/.json`，对应源码 `febadb3`、发布包 `cpu_ddr_coremark_on_478149ee9e63`，反映真实缓存及下级DDR共同参与的执行性能。

Cache/DDR版5次数字仿真的0.717562 WB观测IPC与TCM实物采样分开，不作为板测退休IPC。配置和接口依据 `rtl/cpu/`、`rtl/soc/`，缓存维护依据 `docs/verification/cpu/dcache_writeback.md`。本次两种配置的性能叙述、数据来源及文档输出绑定见 `../verification/cpu/memory_evaluation_report_2026-10-29.json`。

用户提供的两张串口实测原始截图按原文件字节保存在 `figure/cpu-tcm-coremark-uart-original.png` 和 `figure/cpu-l1-cache-ddr-coremark-uart-original.png`，插入CPU性能小节，未裁剪或改写图中文字。TCM图内5933 LUT及0.051497为原发布版固件打印值，与正文调试构建6139 LUT分开说明。原图哈希和本次PDF输出绑定见 `../verification/cpu/coremark_uart_screenshots_2026-10-29.json`；此前文档索引中的PDF哈希保留为历史输出。

本报告的板上波形图为 `figure/cpu-sram-{list,matrix,state}-native.png`。2026-10-29使用Fabric Debugger离线打开已核验的WDF副本，在最大化窗口中放大入口附近波形，将鼠标移到插图区域外后重新截图。插图中无鼠标指针及光晕，仅按原像素裁剪保留信号名、读值和软件采样刻度，不修补或重绘。完整2560×1392截图及加载记录保存在CPU工作树 `build/cpu/native-report-screenshots-20261029-v2/`，当前图形、裁剪区域、源证据及PDF绑定见 `../verification/cpu/sram_report_screenshots_2026-10-29_v2.json`；v1截图及索引保留为历史证据。金色游标0对应原始CSV索引1；`wb_pc_word`是PC右移2位后的值。

旧 `cpu-sram-*-board.pdf/.svg` 及 `sram_report_2026-10-28.json` 保留为上一版重绘图和文档的历史证据，不再作为当前插图绑定。旧 `cpu-cache-*-rtl` 图保留为数字仿真产物，正文不使用其代替片上采样。

## 文件组织

整核外部中断验证补入`figure/cpu-system-external-irq-modelsim-original.jpg`：单发射配置固定为512项直接映射BTB、512项BHT、4项RAS，GShare关闭，完成3582周期、864次退休和92次存储。原始波形、输入和日志登记在`../verification/cpu/system_support/irq-run-index.json`，增量提交包为`cpu-irq-support-2026-10-29.zip`；当前文档绑定见`../verification/cpu/system_irq_waveforms_2026-10-29.json`。

附录B的LSU与I/D Cache功能仿真补入4张原生ModelSim波形截图；本批4组正例共3014/3014项检查通过，4组错误注入被检出。源码、原始WLF/VCD、日志、截图及提交包登记在`../verification/cpu/module_support/memory-run-index.json`，文档输出绑定见`../verification/cpu/module_memory_waveforms_2026-10-29.json`。

B.4第一批整核系统仿真使用Cache开启/关闭的最小固件和独立路由测试。Cache开启完成1277项检查、3次受控异常返回，关闭Cache完成809项检查，路由测试完成476项检查；数据错误负例被检出。平台故障与MRET返回的原生波形图为`figure/cpu-system-cache-runtime-modelsim-original.jpg`，WLF/VCD、固件、日志和提交包登记在`../verification/cpu/system_support/system-run-index.json`，摘要绑定见`../verification/cpu/system_waveforms_2026-10-29.json`。该批使用行为级AXI内存模型，不代表物理DDR、CDC或后布线时序。

| 文件或目录 | 用途 |
| --- | --- |
| `模板.docx` | 官方格式参考 |
| `latex/技术文档.tex` | 章节顺序与文档入口 |
| `latex/metadata.tex` | 作品名称、附录显示开关 |
| `latex/triha-report.sty` | 字体、标题、页眉、图表样式 |
| `latex/chapters/` | 可编辑正文 |
| `figure/` | draw.io源图、导出PDF及官方页眉图片 |
| `reference/project.bib` | 参考文献数据 |
| `latex/scripts/build.ps1` | PDF编译脚本 |
| `latex/tests/test-template.ps1` | 文档结构与编译检查 |

## 正文结构

| 源文件 | 内容 |
| --- | --- |
| `00-abstract.tex` | 摘要与关键词 |
| `01-overview.tex` | 功能与特性、应用领域、主要技术特点、设计流程 |
| `02-system.tex` | 系统介绍、CPU、NPU、互连与存储、视频链路、模型部署与应用软件、FPGA实现 |
| `03-results.tex` | 整体介绍、工程成果、特性成果及性能数据 |
| `04-summary.tex` | 可扩展之处、工程取舍与心得体会 |
| `05-references.tex` | 参考文献 |
| `06-appendix.tex` | 附录A～F：仿真方法、CPU、NPU、互连与存储、视频、系统联合验证 |

设计正文按已实现系统的功能和工作过程描述。第三部分与附录中的待填写项用于补充实际测试数据、波形、日志、版本和报告编号。规格参数、优化参考及实测结果分别记录。

CPU设计按九节组织：CPU微架构、指令提取、指令译码、指令执行、存储访问、指令写回、流水线控制、存储系统、中断和异常。取指至写回按经典五级功能展开，各节说明其在实际六级中的位置；总体表格给出功能与流水级的对应关系。

附录B专注CPU功能验证，不重复正文CoreMark性能与板上调试说明。B.1逐项列出当前配置适用的 `riscv-tests` 50项及ACT4 53项，不在表内重复支撑路径。清单保存在 `../verification/cpu/isa_support/`，2026-10-29实际回归分别50/50和53/53 PASS，逐项日志和提交支撑包已归档，不移用旧五级核的官方通过数。既有V01至V10定向证据见 `../verification/cpu/appendix_b3_isa_2026-10-29.json`；本次清单和文档输出绑定见 `../verification/cpu/appendix_b3_isa_case_list_2026-10-29.json`。

## 编辑约定

- 正文使用 `\chapter{标题}`、`\section{标题}` 和 `\subsection{标题}`，编号自动生成，不增加四级标题。
- 只为正文实际引用的图、表和标题添加 `\label{键}`，通过 `\ref{键}` 引用。
- 正文中的百分号、下划线和连接符号分别写为 `\%`、`\_`、`\&`。
- 正文从作品名称与摘要开始；所有页面沿用官方页眉图片及下横线。
- 标题编号后保留一个空格；两个字的短标题之间保留两个显式空格。
- 表格使用 `reporttable` 内的 `longtable`，允许按行跨页，续页重复表题和表头。平台配置表用字号、列型和列间距保持记录单行。
- 插图使用 `figure[!htbp]`，允许在当前位置、页顶、页底或浮动页排版。浮动比例、数量与图文间距在 `latex/triha-report.sty` 中统一设置。
- 附录开关在 `metadata.tex` 设置：`\reportdrafttrue` 显示附录；关闭草稿模式后由 `\releaseappendixtrue` 或 `\releaseappendixfalse` 控制。
- 参考文献条目在 `reference/project.bib` 中维护，引用采用GB/T 7714数字顺序格式。

## 插图

`figure/rv32-soc.drawio` 是项目绘图区，共14页：系统架构、SoC顶层框图、FPGA顶层、开发流程图、CPU微架构、取指前端、CPU微架构备选、视频子系统、分支预测、指令FIFO、译码模块、执行阶段、ALU模块和LSU模块。参考图单独保存在 `figure/ref.drawio`。

| 章节 | 源图页码 | 导出文件 |
| --- | --- | --- |
| 1.4 设计流程 | 第4页 | `figure/rv32-soc-page4.pdf` |
| 2.1.1 系统架构 | 第1页：TriHaRiscv SoC | `figure/rv32-soc-page1.pdf` |
| 2.1.2 模块功能 | 第2页 | `figure/rv32-soc-page2.pdf` |
| 2.2.1 CPU微架构 | 第5页：CPU微架构 | `figure/rv32-soc-page5.pdf` |
| 2.2.2 指令提取 | 第6页：取指前端 | `figure/rv32-soc-page6.pdf` |
| 2.2.2 指令提取 | 第9页：分支预测 | `figure/rv32-soc-page9.pdf` |
| 2.2.2 指令提取 | 第10页：指令FIFO | `figure/rv32-soc-page10.pdf` |
| 2.2.3 指令译码 | 第11页：译码模块 | `figure/rv32-soc-page11.pdf` |
| 2.2.4 指令执行 | 第12页：执行阶段 | `figure/rv32-soc-page12.pdf` |
| 2.2.4 指令执行 | 第13页：ALU模块 | `figure/rv32-soc-page13.pdf` |
| 2.2.5 存储访问 | 第14页：LSU模块 | `figure/rv32-soc-page14.pdf` |
| 2.5 图像采集与显示链路 | 第8页：video | `figure/rv32-soc-page8.pdf` |
| 2.7 FPGA实现 | 第3页 | `figure/rv32-soc-page3.pdf` |

第5页用于2.2.1的CPU流水线架构图，以经典五级的IF、ID、EX、MEM、WB标明功能区域，并标注实际六级及IF1/IF2、IF2/ID、ID/E1、E1/E2、E2/WB寄存边界。图中展示PC/BPU、I/D Cache、FIFO、译码、寄存器堆、ALU、Branch、CSR、MUL、DIV、LSU及写回通路。IF1/IF2保存取指PC与预测信息，IF2/ID由指令FIFO承担；ID/E1归并表示各单元同拍锁存的状态与数据，整数运算、分支判断和访存地址计算位于该边界之前。

第6页用于2.2.2的取指前端框图，展示取指接口、PC与预测信息寄存、响应缓冲、BTB/BHT/RAS、指令FIFO及训练和重定向通路，连线标注RTL关键信号。正文说明请求接纳、返回包直通或暂存、单发射消费及重定向恢复。CPU微架构图和取指前端图均按正文宽度横向放置，图源代码分别位于2.2.1和2.2.2的引图说明之后，实际位置由浮动排版确定。

第9页作为2.2.2的分支预测框图，按正文宽度横向放置，展示512项BTB、512项两位计数器BHT、4项RAS、训练寄存器及下一PC和包内跳转标志的生成。虚线边界对应 `triha_npc`，训练寄存器位于 `triha_frontend`；连线采用实际端口和内部信号名，`branch_*_i`、`btb_is_*_w`等表示同组信号。正文按PC查询、BTB/BHT、RAS、预测选择和训练更新说明工作过程。

第10页作为2.2.2的指令FIFO结构框图，按正文宽度横向放置，展示 `triha_decode.v` 内的 `triha_fetch_fifo`：两个64位取指包槽共用读写指针及占用计数，包内两条指令分别维护有效位；低字预测跳转时屏蔽高字，全部有效字消费完毕后释放包槽。图中包含PC、取指错误和CSR分类提示的保存、双字输出、入队握手、背压及冲刷控制，采用 `EXTRA_DECODE_STAGE=0`、`OPC_INFO_W=2` 配置。正文说明数据采样与入队确认、按字消费与按包释放、满队列接纳时机，以及高字入口下双路消费与单发射的关系。

第11页用于2.2.3的译码模块逻辑框图，按正文宽度横向放置，展示指令译码、寄存器堆、指令选择、操作数选择、发射控制及执行、写回和旁路接口。取指FIFO在取指前端图中已经展开，本页从 `fetch0_*`、`fetch1_*` 候选指令接口开始。正文按并行译码、PC选字、寄存器预读、旁路选择、单发射控制和重定向说明工作过程，图中的Opcode Select表示操作数选择。图文依据单发射配置 `SUPPORT_DUAL_ISSUE=0`、`EXTRA_DECODE_STAGE=0`、`SUPPORT_MULDIV=1`，立即数在相应执行通路中生成。

第12页用于2.2.4的执行阶段模块框图，按正文宽度横向放置，展示ALU/Branch、MUL、DIV、CSR和LSU与译码/发射、流水线控制、写回/旁路及D-Cache的接口。ALU与分支合并对应同一整数执行模块，CSR包含CSR寄存器与异常控制；乘法保留普通结果及早期旁路，除法使用 `opcode0_*` 载荷和独立完成信号。E1/E2/WB状态跟踪与结果选择按功能归并，分支反馈返回发射控制。正文说明发射接口、各单元运算、分支反馈、CSR写回及流水线暂停，LSU访问过程由下一节展开。图中 `*` 表示同组接口，连线采用直角折线。

第13页用于2.2.4的ALU数据通路框图，展示加减、比较、逻辑、移位、结果选择和第一操作数直通，以及输入操作数选择和ID/E1结果寄存器。正文说明操作数来源、各类运算、链接地址生成、暂停保持和E1旁路。

第14页用于2.2.5的加载存储单元逻辑框图，展示地址生成、访问译码与对齐检查、存储数据处理、请求控制、2×36 bit请求信息FIFO、加载数据扩展、完成异常及独立旁路通路。正文说明请求接纳与响应完成、顺序返回匹配和异常地址传递。两张图均使用正文宽度和可浮动排版，图示及文字标注使用本项目功能名称。

修改图源后，将对应页导出为裁剪边界的单页PDF，再编译文档。官方页眉资源为 `figure/template-header.png`。

## 编译与检查

需要TeX Live中的XeLaTeX、latexmk和BibTeX。中文字体优先使用宋体、黑体，缺失时使用Fandol字体。

```powershell
$env:PATH = 'D:\texlive\2026\bin\windows;' + $env:PATH
& 'D:\FPGA\TriHaRiscv-main\docs\technical-report\latex\scripts\build.ps1'
```

输出为 `D:\FPGA\TriHaRiscv-main\docs\technical-report\latex\技术文档.pdf`。编辑器将 `latex/技术文档.tex` 设为主文件，使用XeLaTeX或latexmk构建。

```powershell
& 'D:\FPGA\TriHaRiscv-main\docs\technical-report\latex\tests\test-template.ps1'
& 'D:\FPGA\TriHaRiscv-main\docs\technical-report\latex\tests\test-template.ps1' -Compile
```

修改后检查编译日志，默认不渲染或预览PDF页面。构建脚本只编译，不生成或覆盖正文。

B.4补入Cache访存与中断交互：三个时刻各完成一次中断、MRET及恢复执行，目标加载和后继指令各退休一次；故意更改mepc的中断专用负例被检出。原生截图为`figure/cpu-system-cache-irq-modelsim-original.jpg`，支撑说明见`../verification/cpu/system_support/CACHE_IRQ_README.md`，运行摘要为`cache_irq_run_2026-10-29.json`。
