# TriHaRiscv v3 LaTeX 技术文档模板

本模板改为直接使用 LaTeX 写作。**`latex/chapters/*.tex` 是唯一正文源文件，可以直接编辑；编译不会重新生成或覆盖这些文件。** 不再维护 Markdown 正文，不需要 Pandoc、pandoc-crossref 或 Obsidian 同步。

保留官方“摘要 + 五部分”结构，按 RV32 CPU、INT8 NPU、DDR、视频链路和裸机软件调整内容。本文件是使用说明，不是技术报告正文；模板也不代表项目已通过整机验收。

## 文件与职责

```text
technical-report/
├── 模板.docx                   官方原件，保持不变
├── README.md                   使用说明
├── figure/                     官方页眉图片、TikZ 框图及后续照片/波形
├── reference/project.bib        参考文献
└── latex/
    ├── main.tex                文档入口及章节顺序
    ├── metadata.tex            作品名称、草稿和附录开关
    ├── triha-report.sty        中文版式、官方页眉和表格
    ├── chapters/               可直接编辑的 LaTeX 正文
    ├── scripts/build.ps1       仅编译，不同步正文
    ├── tests/test-template.ps1 模板与编译检查
    └── main.pdf                最新 PDF
```

## 编辑入口

| 文件                                 | 内容                         |
| ------------------------------------ | ---------------------------- |
| `latex/chapters/00-abstract.tex`   | 摘要及关键词                 |
| `latex/chapters/01-overview.tex`   | 第一部分，作品概述           |
| `latex/chapters/02-system.tex`     | 第二部分，系统组成及功能说明 |
| `latex/chapters/03-results.tex`    | 第三部分，完成情况及性能参数 |
| `latex/chapters/04-summary.tex`    | 第四部分，总结               |
| `latex/chapters/05-references.tex` | 第五部分，参考文献入口       |
| `latex/chapters/06-appendix.tex`   | 可选技术附录                 |

文档按照官方模板从作品名称和摘要开始，不设置独立封面。作品名称在 `latex/metadata.tex` 修改。替换正文的待填字段，删除不适用的设计，不手写章号、图表号或公式号。保留匿名要求，不加入学校、院系、导师或个人身份。

所有页面（包括作品名称与摘要页、目录、各部分首页、参考文献和附录）使用官方 Word 模板的居中原图及 0.75 pt 下横线。`figure/template-header.png` 原样提取自 `模板.docx` 的 `word/media/image1.png`，按约 65.158 × 11.924 mm 排版。

## 编译 PDF

只需要 TeX Live 中的 XeLaTeX、latexmk 和 BibTeX。中文字体优先使用 Windows 宋体/黑体，缺失时回退到 Fandol 字体。无需 Markdown 转换工具。

从仓库根目录执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\docs\technical-report\latex\scripts\build.ps1"
```

也可以在 `latex` 目录直接执行：

```powershell
latexmk -xelatex -synctex=1 main.tex
```

TeXstudio 等编辑器将 `latex/main.tex` 设为主文件，使用 XeLaTeX 或 latexmk 构建。latexmk 自动运行 BibTeX 和目录/引用所需的多轮编译。PowerShell 5.1/7 的脚本只负责文档构建，不替代工程的 WSL/Make/RTL 验证入口。

## 模板填写

直接在 `latex/metadata.tex` 设置：

```latex
\reportdrafttrue
\releaseappendixfalse
```

正文已经去除示例段落和提示框。直接替换各章节中的 `待填写`、`待确认` 字段；`\reportdrafttrue` 控制技术附录是否显示，正式稿可改为 `\reportdraftfalse`，也可通过 `\releaseappendixtrue` 单独启用附录。

## 常用 LaTeX 写法

```latex
\section{模块名称}
正文直接写在这里。引用工程资料使用 \cite{triha-map}。
见图、表和公式时使用对应的 `\ref`、`\eqref` 命令。

\begin{equation}
T = \frac{N_{\mathrm{cycles}}}{f_{\mathrm{CPU}}}
\label{eq:example}
\end{equation}
见式 \eqref{eq:example}。

\begin{figure}[htbp]
\centering
\includegraphics[width=0.85\linewidth]{../figure/board-photo.png}
\caption{对应提交版本的系统实拍}
\label{fig:board-photo}
\end{figure}
```

TikZ 框图直接修改 `figure/*.tex`，正文用 `\input{../figure/文件名}` 插入。短表沿用已有 `reporttable` 和 `tabular`；超过一页的表格用原生 `longtable`，不要不断缩小字号。普通正文中的 `%`、`_`、`&` 分别写成 `\%`、`\_`、`\&`。

参考文献在 `reference/project.bib` 维护，正文使用 `\cite{引用键}` 或 `\citep{引用键}`。正式报告只补充实际使用的标准、器件资料和论文，总数不超过 20 篇。工程内其他 Markdown 资料可以作为引用来源，但不负责更新本模板正文。

## 官方结构与项目边界

| 官方内容            | 本项目处理                                          |
| ------------------- | --------------------------------------------------- |
| 匿名作品名称与摘要  | 首页为作品名称和摘要，无独立封面；摘要建议 800 字内 |
| 概述六项内容        | 保留功能、应用、特点、指标、创新和流程              |
| 机械、SCH、PCB 成果 | 改为板卡/接口、RTL、数据通路和 CDC，不虚构自研硬件  |
| PC/云端界面         | 改为裸机 BSP、模型包、运行时及复现工具              |
| 实物照片和量化指标  | 保留，分别登记仿真、实现和板测证据                  |
| 可扩展之处和心得    | 保留，建议分别 300/1000 字内                        |
| 参考文献            | GB/T 7714 数字顺序格式，不虚构外部来源              |

概述六项建议字数依次为 400、400、400、200、200、200 字以内，最终人工复核。采用 RV32 产品及 `targets/pango676/` 活跃目标，不恢复 RV64，也不沿用冻结的 v2/Xilinx 板级结论。

项目早期 README 的“尚无 Pango 板卡实测”表述与后续记录有差异：2026 年 9 月 24 日 bring-up 记录包含 CPU+NPU GEMM 板上 smoke PASS，但同时明确时序、实际摄像头帧和完整网络仍需另证。模板只引用该项特定测试，不把它提升为整机完成。

每项性能数据绑定提交、配置、软件/位流哈希、输入样本、计时口径和原始证据。目标值、主机结果、单层结果、位流生成或局部 smoke 不替代整机签核。

## 模板检查与迁移记录

```powershell
& '.\latex\tests\test-template.ps1' -Compile
```

检查分章源文件、表格结构、官方页眉和编译告警，通过源码哈希确认构建不会覆盖正文、主文件或作品名称配置。文档构建不执行或宣称通过硬件仿真门禁。

- 官方结构来自本目录 `模板.docx`，原件未改；分章组织参考开题报告，但没有复制学校封面或高光谱内容。
- 参考文献样式复用 TeX Live 的 `gbt7714-numerical.bst`；在 `reference/project.bib` 中维护实际使用的文献。
- 2026-09-30 起以 LaTeX 正文为唯一源文件。
