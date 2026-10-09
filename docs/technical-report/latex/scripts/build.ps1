[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$latexDir = Split-Path -Parent $PSScriptRoot
foreach ($tool in @('latexmk', 'xelatex', 'bibtex')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Missing TeX tool: $tool" }
}
Push-Location $latexDir
try {
    & latexmk '-xelatex' '-synctex=1' '-interaction=nonstopmode' '-halt-on-error' '-file-line-error' 'main.tex'
    if ($LASTEXITCODE -ne 0) { throw 'LaTeX build failed. Inspect latex/main.log.' }
    Write-Output (Join-Path $latexDir 'main.pdf')
} finally {
    Pop-Location
}
