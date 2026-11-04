# TriHaRiscv 技术报告

本目录维护基于自研RISC-V CPU与NPU的异构视觉处理系统技术报告。正文直接编辑LaTeX，入口为 `latex/技术文档.tex`，编译结果为 `latex/技术文档.pdf`。

整机内容依据 `soc/face-box-integration` 分支的固定提交 `edfa1992f604e5887e04f7cad2d81aeff122dd4b`，对应发布包 `face-photo-20261104`。平台为盘古100pro+（MES2L676-100HP），主控PG2L100H-6IFBG676。CPU提交整帧任务，NPU执行YuNet计算图，CPU完成框解码、NMS及主人脸选择，Video在同帧800×600原图上绘制检测框或合成透明头像。

应用使用50 MHz单发射控制CPU及NPU，Video与DDR用户接口为125 MHz，输出像素时钟为40 MHz。采集端保存RGB888原图，并通过双线性缩放、上下补零生成320×320 UINT8 BGR NCHW输入。硬件UART装载器完成六段模型数据和一段RGBA头像写入，共2,032,640 B；程序在片上SRAM运行。初始模式为RAW，KEY1循环切换RAW、BOX和AVATAR，KEY0协调复位后需重新装载七段数据。

2.5说明主脸定位、最近邻纹理采样、alpha混合、无损行区间缓存及同帧显示提交。2.7列出本版整机综合资源：45,716 LUT、41,848 FF、113.5个DRM36K等效块及64个APM。3.2记录三模式、头像跟随、透明背景及无脸清除与恢复的板测验收，3.3列出内部后布线时序及50 MHz联合仿真的结果间隔，附录F给出自然人脸和零RGB场景的完整链路验证。证据集中在 `../verification/soc/face_photo_report_20261104/`；约2.77次/s为融合仿真的结果完成率，实板验收记录为功能观察。

CPU章节保留六级流水线的单/双发射通用设计、分支预测及Cache模块。独立CoreMark板测使用100 MHz，按单/双发射及本地SRAM/Cache＋DDR四种配置记录，原始截图、周期数和核资源统计保持各自构建范围。双发射证据见 `../verification/cpu/report_configurable_issue_2026-11-02/`；单发射板上采样及数字仿真见 `../verification/cpu/` 中对应索引。

附录A说明环境与方法，附录B记录CPU验证，附录C记录NPU组件验证，附录D、E记录系统接口与Video组件验证。NPU组件截图包含不同阵列规模和量化通路，按原用例配置解释；它们与附录F的整机运行配置分别列示。

## 文件组织

| 文件或目录 | 用途 |
| --- | --- |
| `模板.docx` | 官方格式参考 |
| `latex/技术文档.tex` | 章节顺序与文档入口 |
| `latex/metadata.tex` | 作品名称、附录显示开关 |
| `latex/triha-report.sty` | 字体、标题、页眉、图表样式 |
| `latex/chapters/` | 章节索引与按二级标题拆分的正文 |
| `figure/` | draw.io源图、导出PDF及官方页眉图片 |
| `reference/project.bib` | 参考文献数据 |
| `latex/scripts/build.ps1` | PDF编译脚本 |
| `latex/tests/test-template.ps1` | 文档结构与编译检查 |

## 正文结构

主文件为`latex/技术文档.tex`。`latex/chapters/`顶层的章节文件保留部分标题、附录设置及分节引用，每个二级标题（`\section`）的正文存放在同名章节子目录中。摘要与参考文献保留独立文件。

例如，2.2 CPU设计在`latex/chapters/02-system/02-CPU设计.tex`中修改；附录B在`latex/chapters/06-appendix/B-CPU仿真验证.tex`中修改。

| 章节 | 正文文件（相对于latex目录） |
| --- | --- |
| 摘要 | `chapters/00-abstract.tex` |
| 1.1 功能与特性 | `chapters/01-overview/01-功能与特性.tex` |
| 1.2 应用领域 | `chapters/01-overview/02-应用领域.tex` |
| 1.3 主要技术特点 | `chapters/01-overview/03-主要技术特点.tex` |
| 1.4 主要性能指标 | `chapters/01-overview/04-主要性能指标.tex` |
| 1.5 主要创新点 | `chapters/01-overview/05-主要创新点.tex` |
| 1.6 设计流程 | `chapters/01-overview/06-设计流程.tex` |
| 2.1 系统整体介绍 | `chapters/02-system/01-系统整体介绍.tex` |
| 2.2 CPU设计 | `chapters/02-system/02-CPU设计.tex` |
| 2.3 NPU设计 | `chapters/02-system/03-NPU设计.tex` |
| 2.4 系统互连与存储 | `chapters/02-system/04-系统互连与存储.tex` |
| 2.5 图像采集与显示链路 | `chapters/02-system/05-图像采集与显示链路.tex` |
| 2.6 模型部署与应用软件 | `chapters/02-system/06-模型部署与应用软件.tex` |
| 2.7 FPGA实现 | `chapters/02-system/07-FPGA实现.tex` |
| 3.1 整体介绍 | `chapters/03-results/01-整体介绍.tex` |
| 3.2 工程成果 | `chapters/03-results/02-工程成果.tex` |
| 3.3 特性成果 | `chapters/03-results/03-特性成果.tex` |
| 4.1 可扩展之处 | `chapters/04-summary/01-可扩展之处.tex` |
| 4.2 心得体会 | `chapters/04-summary/02-工程取舍与心得体会.tex` |
| 第五部分 参考文献 | `chapters/05-references.tex` |
| A 仿真环境与验证方法 | `chapters/06-appendix/A-仿真环境与验证方法.tex` |
| B CPU仿真验证 | `chapters/06-appendix/B-CPU仿真验证.tex` |
| C NPU仿真验证 | `chapters/06-appendix/C-NPU仿真验证.tex` |
| D 系统互连与存储仿真验证 | `chapters/06-appendix/D-系统互连与存储仿真验证.tex` |
| E 图像采集与显示链路仿真验证 | `chapters/06-appendix/E-图像采集与显示链路仿真验证.tex` |
| F 系统联合仿真验证 | `chapters/06-appendix/F-系统联合仿真验证.tex` |

设计正文按已实现系统的功能和工作过程描述。第三部分与附录中的待填写项用于补充实际测试数据、波形、日志、版本和报告编号。规格参数、优化参考及实测结果分别记录。

CPU设计按九节组织：CPU微架构、指令提取、指令译码、指令执行、存储访问、指令写回、流水线控制、存储系统、中断和异常。取指至写回按经典五级功能展开，各节说明其在实际六级中的位置；总体表格给出功能与流水级的对应关系。

附录B专注CPU功能验证，不重复正文CoreMark性能与板上调试说明。B.1逐项列出单发射配置适用的 `riscv-tests` 50项及ACT4 53项，不在表内重复支撑路径。清单保存在 `../verification/cpu/isa_support/`，2026-10-29实际回归分别50/50和53/53 PASS，逐项日志和提交支撑包已归档，不移用旧五级核的官方通过数。既有V01至V10定向证据见 `../verification/cpu/appendix_b3_isa_2026-10-29.json`；本次清单和文档输出绑定见 `../verification/cpu/appendix_b3_isa_case_list_2026-10-29.json`。

## 编辑约定

- 二级标题及其正文在对应分节文件中修改；部分标题和分节顺序在章节索引文件中修改，使用`\input{...}`接入。
- 分节文件首行的`% !TEX root = ../../技术文档.tex`指定统一编译入口，供VS Code及TeXstudio识别。
- 正文使用 `\chapter{标题}`、`\section{标题}` 和 `\subsection{标题}`，编号自动生成，不增加四级标题。
- 只为正文实际引用的图、表和标题添加 `\label{键}`，通过 `\ref{键}` 引用。
- 正文中的百分号、下划线和连接符号分别写为 `\%`、`\_`、`\&`。
- 正文从作品名称与摘要开始；所有页面沿用官方页眉图片及下横线。
- 标题编号后保留一个空格；两个字的短标题之间保留两个显式空格。
- 表格使用 `reporttable` 内的 `longtable`，允许按行跨页，续页重复表题和表头。平台配置表用字号、列型和列间距保持记录单行。
- 插图使用 `figure[!htbp]`，允许在当前位置、页顶、页底或浮动页排版。浮动比例、数量与图文间距在 `latex/triha-report.sty` 中统一设置。
- 附录开关在 `metadata.tex` 设置：`\reportdrafttrue` 显示附录；关闭草稿模式后由 `\releaseappendixtrue` 或 `\releaseappendixfalse` 控制。
- 参考文献条目在 `reference/project.bib` 中维护，正文用 `\cite{文献键}` 引用；第五部分通过BibTeX和 `gbt7714-numerical` 样式生成GB/T 7714数字顺序列表，仅列实际引用条目，不使用 `\nocite{*}`。
- 文献覆盖RISC-V与AXI规范、NPU数据复用与量化方法、YuNet及模型来源、VESA时序、CDC、CoreMark及CPU测试集。模型和ACT4引用固定提交；实际测试结果仍以工程归档中的配置、日志及哈希为依据。

## 插图

系统总图、模块图和设计流程分别使用 `figure/rv32-soc.drawio` 第1、2、4页；FPGA顶层架构使用同一文件第15页 `FPGA Top — Board Integration`。CPU与Video细节图使用 `figure/rv32-soc-redesign.drawio` 第5～14页。参考图单独保存在 `figure/ref.drawio`。

NPU图源为 `figure/TriHa_NPU_Microarchitecture_Flow_v1.drawio`：第1页用于2.3.1的微架构说明，第2页用于同节的硬件与模型协同设计流程，均原生导出为裁剪边界的矢量PDF。

附录C的10幅NPU仿真图位于 `figure/npu-simulation/`，来源为 `keep-s/npu_zgtc` 的固定提交 `3523d030ded5fc67f3324c54d8a1f1419ac90768`。截图采用ModelSim原生窗口；Dense图只取原图上半幅阵列波形，其余图片保持源文件字节不变。来源、原图校验值、截取范围及配套测试记录保存在 `../verification/npu/report_waveforms_3523d03/`。正文2.3通过附录引用对应验证内容。

| 附录位置 | 内容 | 图片（相对于 `figure/npu-simulation/`） |
| --- | --- | --- |
| C.1 计算正确性 | 普通卷积阵列、DW16尾通道、定点量化 | `dense-accumulate.png`、`dw16-tail-channel.png`、`quantization.png` |
| C.2 分块计算 | 输入行复用与窗口供数、输出尾块掩码 | `input-gather.png`、`output-mask.png` |
| C.3 DMA传输 | 独立读写桥与完成握手 | `dma-completion.png` |
| C.4 任务控制 | 单算子MMIO、FIFO清空与重装载 | `layer-mmio.png`、`fifo-clear.png` |
| C.5 辅助算子 | Add/Sigmoid量化状态、MaxPool/Resize行写回 | `vector-quantization.png`、`pool-resize.png` |

实物照片使用JPEG格式，长边2400像素、质量85；开发板特写旋转为横向，作品全景保留原方向，两图均保留完整画面。

| 文档位置 | 源图页码与内容 | 插图文件 |
| --- | --- | --- |
| 1.6 设计流程 | 第4页：设计流程 | `figure/rv32-soc-page4.pdf` |
| 2.3.1 NPU微架构 | NPU图源第2页：硬件与模型协同设计流程 | `figure/npu-design-flow.pdf` |
| 2.1.1 系统架构 | 第1页：TriHaRiscv SoC | `figure/rv32-soc-page1.pdf` |
| 2.1.2 模块功能 | 第2页：模块功能 | `figure/rv32-soc-page2.pdf` |
| 2.2.1 CPU微架构 | 第5页：六级CPU微架构（双发射配置） | `figure/rv32-soc-page5.pdf` |
| 2.2.2 指令提取 | 第6页：取指前端 | `figure/rv32-soc-page6.pdf` |
| 2.2.2 分支预测 | 第9页：BTB、BHT与RAS | `figure/rv32-soc-page9.pdf` |
| 2.2.2 指令FIFO | 第10页：六项环形存储与双队首 | `figure/rv32-soc-page10.pdf` |
| 2.2.3 指令译码 | 第11页：译码、前递与发射 | `figure/rv32-soc-page11.pdf` |
| 2.2.4 指令执行 | 第12页：双执行通路与共享资源 | `figure/rv32-soc-page12.pdf` |
| 2.2.5 存储访问 | 第14页：LSU请求与完成 | `figure/rv32-soc-page14.pdf` |
| 2.2.8 存储系统 | 第7页：CPU存储接口 | `figure/rv32-soc-page7.pdf` |
| 2.3.1 NPU微架构 | NPU图源第1页：NPU微架构 | `figure/npu-microarchitecture.pdf` |
| 2.5 图像采集与显示链路 | 第8页：视频子系统 | `figure/rv32-soc-page8.pdf` |
| 2.7 FPGA实现 | 绘图区第15页：FPGA顶层架构与板级接口 | `figure/fpga-top.pdf` |
| 2.7.1 目标平台 | 实拍：盘古100pro+开发板特写 | `figure/pangu100pro-board-photo.jpg` |
| 2.2.4 指令执行 | 第13页：整数ALU与ID/E1寄存 | `figure/rv32-soc-page13.pdf` |
| 3.2.4 应用演示 | 实拍：作品全景及视频演示环境 | `figure/triha-system-overview-photo.jpg` |

CPU图按模块总图和功能细节分别组织：总图保留IF1、IF2、ID、E1、E2、WB，功能图展开双队首、操作数前递、配对控制、共享单元、组合移位及访存状态。浅色分区区分功能区域，黑色实线表示数据关系，虚线表示控制关系；窄条及带内侧竖线的状态框表示寄存器。

Video图源展示采集、预处理、DDR帧存储、推理、后处理和帧同步控制。应用正文按发布配置说明原图与模型输入采集、检测框绘制及透明头像合成。

FPGA顶层图展示SoC、独立Video、AXI跨域桥、共享DDR互连、DDR控制器和串口装载器，标出FPGA边界及外部HDMI、DDR3和USB-UART连接。板级支撑逻辑统一表示时钟复位、HDMI初始化与按键/LED接口，所有连接线均可按折线编辑。

所有插图按正文宽度使用 `figure[!htbp]` 浮动排版，正文引用与图题、标签对应。整数ALU细节图位于正文2.2.4“指令执行”；附录B保留仿真波形及验证结果。

修改图源后，从对应源文件原生导出裁剪边界的单页矢量PDF，再运行 `latex/scripts/build.ps1`。第5～14页的导出来源与检查记录见 `figure/provenance/document-integration.json`；临时PNG/SVG预览不随工程维护。官方页眉为 `figure/template-header.png`。

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

