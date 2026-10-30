[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$latexDir = Split-Path -Parent $PSScriptRoot
foreach ($tool in @('latexmk', 'xelatex', 'bibtex')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Missing TeX tool: $tool" }
}
Push-Location $latexDir
try {
    & latexmk '-xelatex' '-synctex=1' '-interaction=nonstopmode' '-halt-on-error' '-file-line-error' '技术文档.tex'
    if ($LASTEXITCODE -ne 0) { throw 'LaTeX build failed. Inspect latex/技术文档.log.' }
    Write-Output (Join-Path $latexDir '技术文档.pdf')
} finally {
    Pop-Location
}
