# Strict PDS report parsing; resource counts do not assert physical timing.
function Get-TrihaPdsResources([string] $Text) {
    $fields = [ordered]@{
        lut='Total LUTs';registers='Total Registers';latches='Total Latches'
        drm='Total DRM';apm='Total APMs';io='Total I/O ports'
    }
    $resources = [ordered]@{}
    foreach ($key in $fields.Keys) {
        $pattern = '(?m)^\s*' + [regex]::Escape($fields[$key]) + '\s*[:=]\s*(\d+(?:\.\d+)?)(?=\s|$)'
        $found = [regex]::Matches($Text,$pattern)
        if ($found.Count -ne 1) { throw "Missing/duplicate PDS resource field: $($fields[$key])" }
        $resources[$key] = [double]::Parse($found[0].Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)
    }
    return $resources
}

function Assert-TrihaPdsStages([string] $Text, [string] $Stage) {
    if ($Text -match '(?im)^\s*(E:|ERROR[: ]|FATAL[: ]|Critical Warning[: ])') {
        throw 'PDS reported an error; inspect the actual tool log.'
    }
    $stages = @('compile','synthesize')
    if ($Stage -eq 'map') { $stages += 'dev_map' }
    foreach ($required in $stages) {
        $pattern = '(?m)^Executing : ' + $required + '(?: [^\r\n]*)? successfully\.\s*$'
        if (-not [regex]::IsMatch($Text,$pattern)) { throw "Missing PDS stage success: $required" }
    }
}

function Get-TrihaPdsCells([string] $Text) {
    $cells = [ordered]@{}
    foreach ($item in [regex]::Matches($Text,'(?m)^(GTP_[A-Za-z0-9_]+)\s+(\d+) uses?\s*$')) {
        $name = $item.Groups[1].Value
        if ($cells.Contains($name)) { throw "Repeated primitive count: $name" }
        $cells[$name] = [long]$item.Groups[2].Value
    }
    if ($cells.Count -eq 0) { throw 'No actual PDS primitive usage.' }
    return $cells
}

function Assert-TrihaPdsConfiguration([string] $Text, [int] $Dual) {
    $expected = [ordered]@{
        SUPPORT_BRANCH_PREDICTION=1;SUPPORT_MULDIV=1;SUPPORT_SUPER=0;SUPPORT_MMU=0
        REGISTER_REDIRECT=1
        SUPPORT_DUAL_ISSUE=$Dual;SUPPORT_LOAD_BYPASS=1;SUPPORT_MUL_BYPASS=1
        SUPPORT_REGFILE_XILINX=0;EXTRA_DECODE_STAGE=0
    }
    $scopes = [ordered]@{
        'triha_core' = [ordered]@{DUAL_ISSUE=$Dual}
        'triha_core/u_cpu' = $expected
        'triha_core/u_cpu/u_frontend' = [ordered]@{REGISTER_REDIRECT=1;SUPPORT_MMU=0}
        'triha_core/u_cpu/u_frontend/u_fetch' = [ordered]@{SUPPORT_MMU=1}
        'triha_core/u_cpu/u_mmu' = [ordered]@{SUPPORT_MMU=0}
    }
    foreach ($scope in $scopes.Keys) {
        $pattern = '(?ms)^I: Module instance \{' + [regex]::Escape($scope) +
            '\} parameter value:\r?\n(.*?)(?=^I:|\z)'
        $blocks = [regex]::Matches($Text,$pattern)
        if ($blocks.Count -ne 1) { throw "Missing/duplicate elaborated CPU scope: $scope" }
        $keys = @($scopes[$scope].Keys)
        foreach ($key in $keys) {
            $values = [regex]::Matches($blocks[0].Groups[1].Value,
                '(?m)^\s*' + $key + " = (1|32)'b([01]+)\s*$")
            $wanted = $scopes[$scope][$key]
            if ($values.Count -ne 1 -or
                $values[0].Groups[2].Value.Length -ne [int]$values[0].Groups[1].Value -or
                [Convert]::ToUInt32($values[0].Groups[2].Value,2) -ne $wanted) {
                throw "Wrong/missing elaborated CPU parameter: $scope/$key; expected $wanted"
            }
        }
    }
    return $expected
}

function Get-TrihaPdsMappedResources([string] $Text) {
    $fields = [ordered]@{lut='LUT';registers='FF';drm='DRM';apm='APM';io='IO'}
    $resources = [ordered]@{}
    foreach ($key in $fields.Keys) {
        $found = [regex]::Matches($Text,'(?m)^\| ' + $fields[$key] + '\s+\|\s+(\d+(?:\.\d+)?)\s+\|')
        if ($found.Count -ne 1) { throw "Missing/duplicate mapped resource: $key" }
        $resources[$key] = [double]::Parse($found[0].Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)
    }
    return $resources
}
