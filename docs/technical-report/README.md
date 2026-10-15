# TriHaRiscv 技术报告

本目录维护 TriHaRiscv 的 LaTeX 技术报告，涵盖 CPU、NPU、系统互连与存储、视频链路、模型部署和 FPGA 实现。目标平台为盘古100pro+（MES2L676-100HP），主控器件为 PG2L100H-6IFBG676。

正文直接编辑 `latex/chapters/*.tex`，文档入口为 `latex/main.tex`，编译输出为 `latex/main.pdf`。

## 目录结构

```text
technical-report/
├── 模板.docx                    官方格式参考
├── README.md                    文档使用说明
├── AGENTS.md                    文档维护约定
├── figure/                      draw.io 源图、导出插图和官方页眉图片
├── reference/project.bib        参考文献
└── latex/
    ├── main.tex                 文档入口与章节顺序
    ├── metadata.tex             作品名称与附录开关
    ├── triha-report.sty          字体、标题、页眉及图表样式
    ├── chapters/                正文源文件
    ├── scripts/build.ps1        PDF 编译脚本
    ├── tests/test-template.ps1  文档检查脚本
    └── main.pdf                 编译结果
```

## 正文结构

| 源文件 | 内容 |
| --- | --- |
| `latex/chapters/00-abstract.tex` | 作品名称、摘要和关键词 |
| `latex/chapters/01-overview.tex` | 第一部分：功能与特性、应用领域、主要技术特点、设计流程 |
| `latex/chapters/02-system.tex` | 第二部分：系统整体介绍、CPU设计、NPU设计、系统互连与存储、图像采集与显示链路、模型部署、FPGA实现 |
| `latex/chapters/03-results.tex` | 第三部分：整体介绍、工程成果、特性成果 |
| `latex/chapters/04-summary.tex` | 第四部分：可扩展之处、工程取舍与心得体会 |
| `latex/chapters/05-references.tex` | 第五部分：参考文献 |
| `latex/chapters/06-appendix.tex` | 附录A～F：仿真环境与方法、CPU、NPU、互连与存储、视频链路、系统联合仿真验证 |

## 编辑约定

- 在章节源文件中填写正文，使用 `\chapter{标题}`、`\section{标题}` 和 `\subsection{标题}`；章节序号自动生成，不写进标题内容。
- 架构与功能按设计方案撰写，可以先于代码实现；测试结果和性能数据按实际记录填写。
- 只为正文实际引用的标题、图和表添加 `\label{引用键}`，并通过 `\ref{引用键}` 引用；公式引用使用 `\eqref{引用键}`。
- 参考文献在 `reference/project.bib` 中维护，正文使用 `\cite{引用键}`，采用 GB/T 7714 数字顺序格式。
- 正文中的 `%`、`_` 和 `&` 分别写为 `\%`、`\_` 和 `\&`。
- 所有页面使用官方页眉图片及下横线，正文从作品名称与摘要开始，无独立封面。
- 标题编号后保留一个空格，两字短标题之间保留两个空格；样式统一在 `latex/triha-report.sty` 中设置。

作品名称和附录显示方式在 `latex/metadata.tex` 中设置：

| 开关 | 附录显示 |
| --- | --- |
| `\reportdrafttrue` | 显示附录 |
| `\reportdraftfalse`、`\releaseappendixtrue` | 显示附录 |
| `\reportdraftfalse`、`\releaseappendixfalse` | 隐藏附录 |

## 插图与表格

`figure/rv32-soc.drawio` 的四页分别用于系统架构、SoC模块、FPGA顶层模块和设计流程图，对应导出文件为：

| 章节 | 图源页码 | 插图文件 |
| --- | --- | --- |
| 1.4 设计流程 | 第4页 | `figure/rv32-soc-page4.pdf` |
| 2.1.1 系统架构 | 第1页 | `figure/rv32-soc-page1.pdf` |
| 2.1.2 模块功能 | 第2页 | `figure/rv32-soc-page2.pdf` |
| 2.7 FPGA实现 | 第3页 | `figure/rv32-soc-page3.pdf` |

修改图源后，将相应页面导出为单页、裁剪边界的 PDF，并替换对应插图文件。LaTeX 编译直接读取这些 PDF。官方页眉使用 `figure/template-header.png`。

表格在 `reporttable` 环境内使用 `longtable`，允许按行跨页。续页通过 `\endfirsthead`、`\endhead` 和 `\endfoot` 重复表题、表头及底线。平台配置表使用 `lll` 列型保持每条记录一行，通过字号和列间距控制宽度。

## 编译与检查

需要 TeX Live 的 XeLaTeX、latexmk 和 BibTeX。中文字体优先使用宋体、黑体，缺失时使用 Fandol 字体。

本机从任意目录运行：

```powershell
$env:PATH = 'D:\texlive\2026\bin\windows;' + $env:PATH
& 'D:\FPGA\TriHaRiscv-v3\docs\technical-report\latex\scripts\build.ps1'
```

输出文件为 `D:\FPGA\TriHaRiscv-v3\docs\technical-report\latex\main.pdf`。构建脚本只编译，不生成或覆盖正文源文件。编辑器将 `latex/main.tex` 设为主文件，使用 XeLaTeX 或 latexmk 构建。

结构检查及编译检查：

```powershell
& 'D:\FPGA\TriHaRiscv-v3\docs\technical-report\latex\tests\test-template.ps1'
& 'D:\FPGA\TriHaRiscv-v3\docs\technical-report\latex\tests\test-template.ps1' -Compile
```

修改后以编译日志确认结果，默认不渲染或预览 PDF 页面。检查项包括章节结构、图表引用、官方页眉、跨页表格和构建前后的源文件一致性。
