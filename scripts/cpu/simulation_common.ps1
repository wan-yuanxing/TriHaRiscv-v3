# Resolve installed primitive models without copying vendor tool sources.
function Get-TrihaPrimitiveModels([string] $Root, $LocalHashes, $ExternalHashes) {
    foreach($name in @('config/cpu_primitives.json','scripts/cpu/simulation_common.ps1')) {
        $LocalHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $Root $name) -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $config=Get-Content -LiteralPath (Join-Path $Root 'config/cpu_primitives.json') -Raw|ConvertFrom-Json
    if($config.schema_version -ne 1 -or @($config.simulation_models).Count -eq 0){throw 'Invalid CPU primitive model configuration.'}
    foreach($entry in $config.simulation_models) {
        if(-not [IO.Path]::IsPathRooted($entry.path) -or
            (Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.sha256) {
            throw "Installed CPU primitive model hash mismatch: $($entry.module)"
        }
        $ExternalHashes[$entry.path]=$entry.sha256
        $entry.path
    }
}

function Test-TrihaPrimitiveHashes($ExternalHashes) {
    foreach($name in $ExternalHashes.Keys) {
        if(-not (Test-Path -LiteralPath $name -PathType Leaf)){return $false}
        if((Get-FileHash -LiteralPath $name -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExternalHashes[$name]){return $false}
    }
    return $true
}
