[CmdletBinding()]
param([switch]$Compile)

$ErrorActionPreference = 'Stop'
$latexDir = Split-Path -Parent $PSScriptRoot
$documentDir = Split-Path -Parent $latexDir
$utf8 = [Text.Encoding]::UTF8
foreach ($relativePath in @('技术文档.tex', 'triha-report.sty', 'metadata.tex', 'scripts/build.ps1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $latexDir $relativePath))) { throw "Missing file: $relativePath" }
}
foreach ($obsoletePath in @('scripts/build-from-markdown.ps1', 'scripts/document-filter.lua')) {
    if (Test-Path -LiteralPath (Join-Path $latexDir $obsoletePath)) { throw "Obsolete conversion workflow remains: $obsoletePath" }
}
$main = [IO.File]::ReadAllText((Join-Path $latexDir '技术文档.tex'), $utf8)
$metadata = [IO.File]::ReadAllText((Join-Path $latexDir 'metadata.tex'), $utf8)
if ($main -match 'build-mode') { throw 'Document mode must not depend on a generated file.' }
if ($metadata -notmatch '\\newif\\ifreportdraft') { throw 'Draft mode must be directly editable in metadata.tex.' }
$headerAsset = Join-Path $documentDir 'figure/template-header.png'
if (-not (Test-Path -LiteralPath $headerAsset -PathType Leaf)) { throw 'Official template header asset is missing.' }
$style = [IO.File]::ReadAllText((Join-Path $latexDir 'triha-report.sty'), $utf8)
if ([regex]::Matches($style, '\\fancyhead\[C\]\{\\officialreportheader\}').Count -ne 2) { throw 'Both normal and chapter-opening pages must use the official header.' }
if (($main + $style) -match 'makereportcover|\\begin\{titlepage\}|\\thispagestyle\{empty\}') { throw 'The document must not contain a separate cover or suppress the official header.' }
if ($style -match 'writingnote|reportwritingbox|tcolorbox|填写提示') { throw 'Prompt-box workflow must be removed.' }
foreach ($headingLevel in @('chapter', 'section', 'subsection')) {
    $headingSettings = [regex]::Match($style, '(?m)^  ' + $headingLevel + '=.*$').Value
    if (-not $headingSettings.Contains('aftername={\ }')) { throw "Expected one explicit space after $headingLevel numbering." }
}
if (-not $style.Contains('contentsname={目\ \ 录}')) { throw 'The contents heading must use two explicit spaces between its characters.' }
if (-not $style.Contains('tocline={\CTEXnumberline{#1}#2}') -or -not $style.Contains('\settowidth{\@tempdima}{#1\ }')) { throw 'Contents numbering must use its natural width followed by one explicit space.' }
if (-not $style.Contains('labelsep=space')) { throw 'Figure and table captions must use one space after their numbering.' }
$build = Join-Path $latexDir 'scripts/build.ps1'
$chaptersDir = Join-Path $latexDir 'chapters'
$chapters = @(Get-ChildItem -LiteralPath $chaptersDir -Filter '*.tex' -File)
if ($chapters.Count -ne 7) { throw 'Expected seven top-level LaTeX chapter entries.' }
$allChapterSources = @(Get-ChildItem -LiteralPath $chaptersDir -Filter '*.tex' -File -Recurse)
function Read-ReportSource {
    param([string]$Path, [string[]]$Stack = @())
    $fullPath = [IO.Path]::GetFullPath($Path)
    if ($Stack -contains $fullPath) { throw "Cyclic LaTeX input: $fullPath" }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Missing LaTeX source: $fullPath" }
    $text = [IO.File]::ReadAllText($fullPath, $utf8)
    return [regex]::Replace($text, '(?m)^[ \t]*\\input\{([^}\r\n]+)\}[ \t]*(?:\r?\n|\z)', {
        param($inputMatch)
        $relative = $inputMatch.Groups[1].Value
        if (-not [IO.Path]::HasExtension($relative)) { $relative += '.tex' }
        $child = [IO.Path]::GetFullPath((Join-Path $latexDir $relative))
        if (-not $child.StartsWith($chaptersDir + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Chapter input must stay inside chapters/: $relative"
        }
        Read-ReportSource -Path $child -Stack ($Stack + $fullPath)
    })
}
$splitChapterCounts = @{
    '01-overview.tex' = 6
    '02-system.tex' = 7
    '03-results.tex' = 3
    '04-summary.tex' = 2
    '06-appendix.tex' = 6
}
$sectionSourcePaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($chapter in $chapters) {
    $text = [IO.File]::ReadAllText($chapter.FullName, $utf8)
    if ([regex]::Matches($text, '\\chapter\*?\{').Count -ne 1) { throw "Expected one chapter heading: $($chapter.Name)" }
    if ($splitChapterCounts.ContainsKey($chapter.Name)) {
        if ($text -match '\\section\{') { throw "Second-level headings belong in section files: $($chapter.Name)" }
        $inputs = [regex]::Matches($text, '\\input\{([^}]+)\}')
        if ($inputs.Count -ne $splitChapterCounts[$chapter.Name]) { throw "Unexpected section file count: $($chapter.Name)" }
        foreach ($entry in $inputs) {
            $sectionPath = [IO.Path]::GetFullPath((Join-Path $latexDir ($entry.Groups[1].Value + '.tex')))
            if (-not $sectionSourcePaths.Add($sectionPath)) { throw "Section source included twice: $sectionPath" }
            if (-not (Test-Path -LiteralPath $sectionPath -PathType Leaf)) { throw "Missing section source: $sectionPath" }
            $sectionText = [IO.File]::ReadAllText($sectionPath, $utf8)
            if ([regex]::Matches($sectionText, '(?m)^\\section\{').Count -ne 1 -or $sectionText -match '\\chapter\*?\{') {
                throw "Each section source must contain one second-level heading: $sectionPath"
            }
            $rootDirective = [regex]::Match($sectionText, '^% !TEX root = ([^\r\n]+)')
            if (-not $rootDirective.Success) { throw "Missing editor root directive: $sectionPath" }
            $editorRoot = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $sectionPath) $rootDirective.Groups[1].Value))
            if ($editorRoot -ne (Join-Path $latexDir '技术文档.tex')) { throw "Incorrect editor root: $sectionPath" }
        }
    }
}
if ($allChapterSources.Count -ne ($chapters.Count + $sectionSourcePaths.Count)) { throw 'Unreferenced section source exists in chapters/.' }
$overview = Read-ReportSource (Join-Path $chaptersDir '01-overview.tex')
$designFlowSection = [regex]::Match($overview, '(?s)\\section\{设计流程\}(.*?)(?=\\section\{|\z)').Groups[1].Value
$designFlowFigure = Join-Path $documentDir 'figure/rv32-soc-page4.pdf'
if (-not (Test-Path -LiteralPath $designFlowFigure -PathType Leaf)) { throw 'The exported fourth-page design flow diagram is missing.' }
if ($designFlowSection -notmatch '\\includegraphics\[[^]]+\]\{\.\./figure/rv32-soc-page4\.pdf\}' -or $designFlowSection -notmatch '\\caption\{TriHaRiscv设计流程\}\\label\{fig:design-flow\}') { throw 'The fourth-page design flow diagram must remain under section 1.6.' }
if ($designFlowSection -notmatch '\\ref\{fig:design-flow\}' -or $designFlowSection -match '待填写：') { throw 'Section 1.6 must describe and reference the design flow diagram.' }
foreach ($flowTopic in @('CPU', 'NPU', 'YuNet', 'Video', '独立验证', '系统集成', '融合仿真', 'FPGA板测', 'CoreMark', '资源', '时序', '结果间隔')) {
    if (-not $designFlowSection.Contains($flowTopic)) { throw "Missing design flow description: $flowTopic" }
}
if (-not $designFlowSection.Contains('并行开发CPU、NPU和Video')) { throw 'The concise design flow must preserve the three development routes.' }
$system = Read-ReportSource (Join-Path $chaptersDir '02-system.tex')
$results = Read-ReportSource (Join-Path $chaptersDir '03-results.tex')
$summary = Read-ReportSource (Join-Path $chaptersDir '04-summary.tex')
$appendix = Read-ReportSource (Join-Path $chaptersDir '06-appendix.tex')
$abstract = [IO.File]::ReadAllText((Join-Path $chaptersDir '00-abstract.tex'), $utf8)
$sourceTexts = @(Get-ChildItem -LiteralPath $documentDir -Recurse -File | Where-Object { $_.Extension -in @('.tex', '.sty') } | ForEach-Object { [IO.File]::ReadAllText($_.FullName, $utf8) })
$documentText = $sourceTexts -join "`n"
$referencedLabels = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($referenceMatch in [regex]::Matches($documentText, '\\(?:ref|pageref|eqref|autoref|nameref|cref|Cref|vref|Vref)\*?\s*\{([^}]+)\}|\\hyperref\s*\[([^]]+)\]')) {
    $referenceKeys = if ($referenceMatch.Groups[1].Success) { $referenceMatch.Groups[1].Value } else { $referenceMatch.Groups[2].Value }
    foreach ($referenceKey in ($referenceKeys -split ',')) { [void]$referencedLabels.Add($referenceKey.Trim()) }
}
$definedLabels = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($labelMatch in [regex]::Matches($documentText, '\\label\{([^}]+)\}')) {
    $labelKey = $labelMatch.Groups[1].Value
    if (-not $definedLabels.Add($labelKey)) { throw "Duplicate document label: $labelKey" }
    if (-not $referencedLabels.Contains($labelKey)) { throw "Unreferenced document label: $labelKey" }
}
foreach ($referenceKey in $referencedLabels) {
    if (-not $definedLabels.Contains($referenceKey)) { throw "Undefined document reference: $referenceKey" }
}
if (-not $abstract.Contains('摘\ \ 要') -or -not $summary.Contains('\chapter{总\ \ 结}') -or -not $appendix.Contains('\chapter*{附\ \ 录}') -or -not $appendix.Contains('\addcontentsline{toc}{chapter}{附\ \ 录}')) { throw 'Two-character headings must use two explicit spaces between their characters.' }
$chapterSectionSpecs = @(
    @{ Number = '1'; Text = $overview; Sections = @('功能与特性', '应用领域', '主要技术特点', '主要性能指标', '主要创新点', '设计流程') },
    @{ Number = '3'; Text = $results; Sections = @('整体介绍', '工程成果', '特性成果') },
    @{ Number = '4'; Text = $summary; Sections = @('可扩展之处', '心得体会') }
)
foreach ($chapterSpec in $chapterSectionSpecs) {
    $sections = @([regex]::Matches($chapterSpec.Text, '\\section\{([^}]+)\}') | ForEach-Object { $_.Groups[1].Value })
    if (($sections -join '|') -cne ($chapterSpec.Sections -join '|')) { throw "Unexpected section titles in chapter $($chapterSpec.Number)." }
}
if ($summary -match '\\(?:subsection|subsubsection|paragraph|subparagraph)\*?\{') { throw 'Chapter 4 must contain only chapter and section headings.' }
if ($results -match '\\(?:subsubsection|paragraph|subparagraph)\*?\{') { throw 'Chapter 3 must not contain headings below subsection level.' }
$resultsSections = @(
    @{ Title = '整体介绍'; Number = '3.1'; Subsections = @() },
    @{ Title = '工程成果'; Number = '3.2'; Subsections = @('硬件成果', '软件成果', '功能验证', '应用演示') },
    @{ Title = '特性成果'; Number = '3.3'; Subsections = @('CPU性能', 'CPU流水线效率', 'NPU性能', '系统性能', 'FPGA实现指标') }
)
foreach ($sectionSpec in $resultsSections) {
    $sectionPattern = '(?s)\\section\{' + [regex]::Escape($sectionSpec.Title) + '\}(.*?)(?=\\section\{|\z)'
    $sectionText = [regex]::Match($results, $sectionPattern).Groups[1].Value
    $subsections = @([regex]::Matches($sectionText, '\\subsection\{([^}]+)\}') | ForEach-Object { $_.Groups[1].Value })
    if (($subsections -join '|') -cne ($sectionSpec.Subsections -join '|')) { throw "Incorrect results subsection structure: $($sectionSpec.Title)" }
}
$expectedCpuSubsections = @('CPU微架构', '指令提取', '指令译码', '指令执行', '存储访问', '指令写回', '流水线控制', '存储系统', '中断和异常')
$cpuSection = [regex]::Match($system, '(?s)\\section\{CPU设计\}(.*?)(?=\\section\{|\z)')
$cpuSubsections = @([regex]::Matches($cpuSection.Groups[1].Value, '\\subsection\{([^}]+)\}') | ForEach-Object { $_.Groups[1].Value })
if (($cpuSubsections -join '|') -cne ($expectedCpuSubsections -join '|')) { throw 'Expected nine CPU design subheadings in the requested order.' }
$expectedAcceleratorSubsections = @('NPU微架构', 'PE计算单元', '卷积计算通路', '算子控制器', '片上缓冲', 'DMA控制器', '卷积窗口生成', '辅助算子单元', '定点后处理单元', '寄存器接口')
$acceleratorSection = [regex]::Match($system, '(?s)\\section\{NPU设计\}(.*?)(?=\\section\{|\z)')
$acceleratorSubsections = @([regex]::Matches($acceleratorSection.Groups[1].Value, '\\subsection\{([^}]+)\}') | ForEach-Object { $_.Groups[1].Value })
if (($acceleratorSubsections -join '|') -cne ($expectedAcceleratorSubsections -join '|')) { throw 'Unexpected NPU design subheadings or order.' }
$integrationSections = @(
    @{ Title = '系统整体介绍'; Number = '2.1'; Subsections = @('系统架构', '模块功能') },
    @{ Title = '系统互连与存储'; Number = '2.4'; Subsections = @('总线结构', '存储组织', '访问仲裁', 'DDR带宽预算', '共享数据访问约定') },
    @{ Title = '图像采集与显示链路'; Number = '2.5'; Subsections = @('图像采集', '输入预处理', '帧缓存管理', '图像叠加', '显示输出') },
    @{ Title = '模型部署与应用软件'; Number = '2.6'; Subsections = @('模型选型', '量化方案', '模型导出', '算子映射', '检测后处理', '裸机运行时', '帧调度', '异常处理') },
    @{ Title = 'FPGA实现'; Number = '2.7'; Subsections = @('目标平台', '资源统计', '工程配置', '时钟复位', '板级接口', '实现约束') }
)
foreach ($sectionSpec in $integrationSections) {
    $sectionPattern = '(?s)\\section\{' + [regex]::Escape($sectionSpec.Title) + '\}(.*?)(?=\\section\{|\z)'
    $sectionText = [regex]::Match($system, $sectionPattern).Groups[1].Value
    $subsections = @([regex]::Matches($sectionText, '\\subsection\{([^}]+)\}') | ForEach-Object { $_.Groups[1].Value })
    if (($subsections -join '|') -cne ($sectionSpec.Subsections -join '|')) { throw "Incorrect subsection structure: $($sectionSpec.Title)" }
}
$architectureSection = [regex]::Match($system, '(?s)\\subsection\{系统架构\}(.*?)(?=\\subsection\{|\\section\{|\z)').Groups[1].Value
$architectureFigure = Join-Path $documentDir 'figure/rv32-soc-page1.pdf'
if (-not (Test-Path -LiteralPath $architectureFigure -PathType Leaf)) { throw 'The exported SoC and external video architecture diagram is missing.' }
if ($architectureSection -notmatch '\\includegraphics\[[^]]+\]\{\.\./figure/rv32-soc-page1\.pdf\}' -or $architectureSection -notmatch '\\label\{fig:system-architecture\}') { throw 'The SoC and external video architecture diagram must remain under section 2.1.1.' }
if ($architectureSection -notmatch '\\ref\{fig:system-architecture\}' -or $architectureSection -match '待填写：') { throw 'Section 2.1.1 must describe and reference the system architecture diagram.' }
[xml]$architectureDrawing = [IO.File]::ReadAllText((Join-Path $documentDir 'figure/rv32-soc.drawio'), $utf8)
$architecturePage = $architectureDrawing.SelectSingleNode('/mxfile/diagram[1]')
if ($null -eq $architecturePage) { throw 'The first-page system architecture diagram is missing.' }
$videoContainer = $architecturePage.SelectSingleNode('mxGraphModel/root/mxCell[@vertex="1" and contains(@value,"Video") and contains(@value,"Subsystem")]')
$socContainer = $architecturePage.SelectSingleNode('mxGraphModel/root/mxCell[@id="JKjM34i8VMpzc6x9dMq6-1"]')
if ($null -eq $videoContainer -or $null -eq $socContainer -or $videoContainer.parent -ne $socContainer.parent) { throw 'Video must be a sibling of the SoC, not part of its container.' }
$videoBounds = $videoContainer.mxGeometry
$socBounds = $socContainer.mxGeometry
$overlapsHorizontally = [double]$videoBounds.x -lt ([double]$socBounds.x + [double]$socBounds.width) -and ([double]$videoBounds.x + [double]$videoBounds.width) -gt [double]$socBounds.x
$overlapsVertically = [double]$videoBounds.y -lt ([double]$socBounds.y + [double]$socBounds.height) -and ([double]$videoBounds.y + [double]$videoBounds.height) -gt [double]$socBounds.y
if ($overlapsHorizontally -and $overlapsVertically) { throw 'Video must remain outside the SoC boundary.' }
if (-not $architectureSection.Contains('视频子系统在FPGA顶层与SoC并列连接')) { throw 'The architecture description must identify video as external to the SoC.' }
$moduleSection = [regex]::Match($system, '(?s)\\subsection\{模块功能\}(.*?)(?=\\subsection\{|\\section\{|\z)').Groups[1].Value
if ($moduleSection -notmatch '\\caption\{SoC模块功能表\}') { throw 'The module-function table must remain under module functions.' }
$storageSection = [regex]::Match($system, '(?s)\\subsection\{存储组织\}(.*?)(?=\\subsection\{|\\section\{|\z)').Groups[1].Value
if ($storageSection -notmatch '\\caption\{系统地址映射表\}') { throw 'The address-space table must remain under storage organization.' }
$operatorSection = [regex]::Match($system, '(?s)\\subsection\{算子映射\}(.*?)(?=\\subsection\{|\\section\{|\z)').Groups[1].Value
if ($operatorSection -notmatch '\\caption\{算子执行方式表\}') { throw 'The operator-backend table must remain under operator mapping.' }
$platformSection = [regex]::Match($system, '(?s)\\subsection\{目标平台\}(.*?)(?=\\subsection\{|\\section\{|\z)').Groups[1].Value
if ($platformSection -notmatch '\\label\{tbl:platform\}') { throw 'The platform configuration table must remain under the target platform.' }
$appendixSectionSpecs = @(
    @{ Title = '仿真环境与验证方法'; Subsections = @('工具配置', '测试平台') },
    @{ Title = 'CPU仿真验证'; Subsections = @('指令集验证', '单元级仿真验证', '模块级仿真验证', '系统级仿真验证') },
    @{ Title = 'NPU仿真验证'; Subsections = @('计算正确性', '分块计算', 'DMA传输', '任务控制', '辅助算子') },
    @{ Title = '系统互连与存储仿真验证'; Subsections = @('CPU主端控制与外设访问', '共享存储与地址译码') },
    @{ Title = '图像采集与显示链路仿真验证'; Subsections = @('四类系统级场景', '采集与槽所有权', '共享DDR背压与采显联合', '紧凑显示组件回归') },
    @{ Title = '系统联合仿真验证'; Subsections = @('完整模型推理', '连续帧处理', '运行配置', '结果核对') }
)
$expectedAppendixSections = @($appendixSectionSpecs | ForEach-Object { $_.Title })
$appendixSections = @([regex]::Matches($appendix, '\\section\{([^}]+)\}') | ForEach-Object { $_.Groups[1].Value })
if (($appendixSections -join '|') -cne ($expectedAppendixSections -join '|')) { throw 'Expected six simulation-validation appendix sections in A-F order.' }
if ($appendix -notmatch '\\renewcommand\{\\thesection\}\{\\Alph\{section\}\}') { throw 'Appendix sections must use automatic alphabetic numbering.' }
if ($appendix -match '\\(?:paragraph|subparagraph)\*?\{') { throw 'The appendix must not contain headings below subsubsection level.' }
foreach ($sectionSpec in $appendixSectionSpecs) {
    $sectionPattern = '(?s)\\section\{' + [regex]::Escape($sectionSpec.Title) + '\}(.*?)(?=\\section\{|\z)'
    $sectionText = [regex]::Match($appendix, $sectionPattern).Groups[1].Value
    $subsections = @([regex]::Matches($sectionText, '\\subsection\{([^}]+)\}') | ForEach-Object { $_.Groups[1].Value })
    if (($subsections -join '|') -cne ($sectionSpec.Subsections -join '|')) { throw "Incorrect appendix subsection structure: $($sectionSpec.Title)" }
}
if ($system -match '\\begin\{tabular\}|\\resizebox' -or [regex]::Matches($system, '\\begin\{longtable\}').Count -ne [regex]::Matches($system, '\\begin\{reporttable\}').Count) { throw 'Report tables must allow page breaks without unbreakable table boxes.' }
if (($overview + $system + $results) -match 'writingnote|reportwritingbox|填写提示|示例正文|示范正文') { throw 'Example or prompt content remains in the editable chapters.' }
$bibliographyPath = Join-Path $documentDir 'reference/project.bib'
$bibliography = [IO.File]::ReadAllText($bibliographyPath, $utf8)
$bibliographyKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($entry in [regex]::Matches($bibliography, '(?m)^\s*@(?!comment\b|string\b|preamble\b)\w+\s*\{\s*([^,\s]+)\s*,')) {
    if (-not $bibliographyKeys.Add($entry.Groups[1].Value)) { throw "Duplicate bibliography key: $($entry.Groups[1].Value)" }
}
if ($bibliographyKeys.Count -eq 0) { throw 'The bibliography must contain the sources cited in the report.' }
$citationKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($citation in [regex]::Matches($documentText, '\\cite(?:p|t|alt|alp|author|year(?:par)?)?\*?(?:\[[^\]]*\]){0,2}\{([^}]+)\}')) {
    foreach ($key in ($citation.Groups[1].Value -split ',')) { [void]$citationKeys.Add($key.Trim()) }
}
foreach ($key in $citationKeys) {
    if (-not $bibliographyKeys.Contains($key)) { throw "Citation has no bibliography entry: $key" }
}
foreach ($key in $bibliographyKeys) {
    if (-not $citationKeys.Contains($key)) { throw "Bibliography entry is not cited: $key" }
}
if ($documentText -match '\\nocite\s*\{\s*\*\s*\}') { throw 'Do not list uncited bibliography entries with nocite{*}.' }
$referenceChapter = [IO.File]::ReadAllText((Join-Path $chaptersDir '05-references.tex'), $utf8)
if (-not $referenceChapter.Contains('\bibliographystyle{gbt7714-numerical}') -or -not $referenceChapter.Contains('\bibliography{../reference/project}')) {
    throw 'The references chapter must generate the GB/T 7714 numerical bibliography.'
}
if ($Compile) {
    $authorSources = @($allChapterSources.FullName) + @((Join-Path $latexDir 'metadata.tex'), (Join-Path $latexDir '技术文档.tex'), $bibliographyPath)
    $sourceHashes = @{}
    foreach ($source in $authorSources) { $sourceHashes[$source] = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash }
    & $build
    if ($LASTEXITCODE -ne 0) { throw 'PDF compilation failed.' }
    foreach ($source in $authorSources) {
        if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $sourceHashes[$source]) { throw "Build overwrote an editable source: $source" }
    }
    $pdf = Get-Item -LiteralPath (Join-Path $latexDir '技术文档.pdf')
    if ($pdf.Length -lt 20000) { throw 'Generated PDF is unexpectedly small.' }
    $log = [IO.File]::ReadAllText((Join-Path $latexDir '技术文档.log'), $utf8)
    if ($log -match 'There were undefined references|There were undefined citations|Empty `thebibliography|Overfull \\[hv]box|Missing character:|Package fancyhdr Warning:') {
        throw 'PDF has unresolved references, overflowing text, missing glyphs, or insufficient header space.'
    }
    $compiledBibliography = [IO.File]::ReadAllText((Join-Path $latexDir '技术文档.bbl'), $utf8)
    $compiledBibliographyKeys = @([regex]::Matches($compiledBibliography, '(?m)^\\bibitem(?:\[[^\r\n]*\])?\{([^}\r\n]+)\}') | ForEach-Object { $_.Groups[1].Value })
    if ($compiledBibliographyKeys.Count -ne $citationKeys.Count) { throw 'Compiled bibliography does not match the cited source count.' }
    foreach ($key in $citationKeys) {
        if ($compiledBibliographyKeys -cnotcontains $key) { throw "Citation missing from compiled bibliography: $key" }
    }
    $toc = [IO.File]::ReadAllText((Join-Path $latexDir '技术文档.toc'), $utf8)
    foreach ($chapterSpec in $chapterSectionSpecs) {
        $sectionPattern = '\\contentsline \{section\}\{\\numberline \{(' + $chapterSpec.Number + '\.\d+)\}([^}]+)\}'
        $compiledSections = @([regex]::Matches($toc, $sectionPattern))
        if ($compiledSections.Count -ne $chapterSpec.Sections.Count) { throw "Incorrect compiled section count in chapter $($chapterSpec.Number)." }
        for ($sectionIndex = 0; $sectionIndex -lt $compiledSections.Count; $sectionIndex++) {
            $entry = $compiledSections[$sectionIndex]
            $number = $chapterSpec.Number + '.' + ($sectionIndex + 1)
            if ($entry.Groups[1].Value -cne $number -or $entry.Groups[2].Value -cne $chapterSpec.Sections[$sectionIndex]) { throw "Incorrect compiled section heading: $number" }
        }
    }
    if ($toc -match '\\contentsline \{(?:subsection|subsubsection)\}\{\\numberline \{4\.\d+\.\d+') { throw 'Compiled chapter 4 must not contain lower-level headings.' }
    $compiledCpuSubsections = @([regex]::Matches($toc, '\\contentsline \{subsection\}\{\\numberline \{(2\.2\.\d+)\}([^}]+)\}'))
    if ($compiledCpuSubsections.Count -ne $expectedCpuSubsections.Count) { throw 'Compiled contents must include nine CPU design subheadings under 2.2.' }
    for ($subsectionIndex = 0; $subsectionIndex -lt $compiledCpuSubsections.Count; $subsectionIndex++) {
        $entry = $compiledCpuSubsections[$subsectionIndex]
        $number = '2.2.' + ($subsectionIndex + 1)
        if ($entry.Groups[1].Value -cne $number -or $entry.Groups[2].Value -cne $expectedCpuSubsections[$subsectionIndex]) { throw 'Incorrect compiled CPU subheading title or numbering.' }
    }
    $compiledAcceleratorSubsections = @([regex]::Matches($toc, '\\contentsline \{subsection\}\{\\numberline \{(2\.3\.\d+)\}([^}]+)\}'))
    if ($compiledAcceleratorSubsections.Count -ne $expectedAcceleratorSubsections.Count) { throw 'Incorrect compiled NPU subsection count under 2.3.' }
    for ($subsectionIndex = 0; $subsectionIndex -lt $compiledAcceleratorSubsections.Count; $subsectionIndex++) {
        $entry = $compiledAcceleratorSubsections[$subsectionIndex]
        $number = '2.3.' + ($subsectionIndex + 1)
        if ($entry.Groups[1].Value -cne $number -or $entry.Groups[2].Value -cne $expectedAcceleratorSubsections[$subsectionIndex]) { throw 'Incorrect compiled AI accelerator subheading title or numbering.' }
    }
    foreach ($sectionSpec in ($integrationSections + $resultsSections)) {
        $sectionPattern = '\\contentsline \{section\}\{\\numberline \{' + [regex]::Escape($sectionSpec.Number) + '\}' + [regex]::Escape($sectionSpec.Title) + '\}'
        if ($toc -notmatch $sectionPattern) { throw "Incorrect compiled section title or numbering: $($sectionSpec.Title)" }
        $subsectionPattern = '\\contentsline \{subsection\}\{\\numberline \{(' + [regex]::Escape($sectionSpec.Number) + '\.\d+)\}([^}]+)\}'
        $compiledSubsections = @([regex]::Matches($toc, $subsectionPattern))
        if ($compiledSubsections.Count -ne $sectionSpec.Subsections.Count) { throw "Incorrect compiled subsection count: $($sectionSpec.Title)" }
        for ($subsectionIndex = 0; $subsectionIndex -lt $compiledSubsections.Count; $subsectionIndex++) {
            $entry = $compiledSubsections[$subsectionIndex]
            $number = $sectionSpec.Number + '.' + ($subsectionIndex + 1)
            if ($entry.Groups[1].Value -cne $number -or $entry.Groups[2].Value -cne $sectionSpec.Subsections[$subsectionIndex]) { throw "Incorrect compiled subheading: $number" }
        }
    }
    $compiledAppendixSections = @([regex]::Matches($toc, '\\contentsline \{section\}\{\\numberline \{([A-Z])\}([^}]+)\}'))
    if ($compiledAppendixSections.Count -ne $expectedAppendixSections.Count) { throw 'Compiled contents must include only appendix sections A-F.' }
    for ($sectionIndex = 0; $sectionIndex -lt $compiledAppendixSections.Count; $sectionIndex++) {
        $letter = [string][char](65 + $sectionIndex)
        $entry = $compiledAppendixSections[$sectionIndex]
        if ($entry.Groups[1].Value -cne $letter -or $entry.Groups[2].Value -cne $expectedAppendixSections[$sectionIndex]) { throw 'Incorrect compiled appendix title or numbering.' }
        $sectionSpec = $appendixSectionSpecs[$sectionIndex]
        $subsectionPattern = '\\contentsline \{subsection\}\{\\numberline \{(' + $letter + '\.\d+)\}([^}]+)\}'
        $compiledSubsections = @([regex]::Matches($toc, $subsectionPattern))
        if ($compiledSubsections.Count -ne $sectionSpec.Subsections.Count) { throw "Incorrect compiled subsection count in appendix $letter." }
        for ($subsectionIndex = 0; $subsectionIndex -lt $compiledSubsections.Count; $subsectionIndex++) {
            $entry = $compiledSubsections[$subsectionIndex]
            $number = $letter + '.' + ($subsectionIndex + 1)
            if ($entry.Groups[1].Value -cne $number -or $entry.Groups[2].Value -cne $sectionSpec.Subsections[$subsectionIndex]) { throw "Incorrect compiled appendix subheading: $number" }
        }
    }
}
Write-Output 'PASS: editable LaTeX sources, official headers, report structure, and non-overwriting builds.'
