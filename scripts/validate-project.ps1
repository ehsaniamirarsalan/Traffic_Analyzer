[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$required = @(
    'compose.yaml',
    'traffic.ps1',
    'docker\otvision\Dockerfile',
    'docker\otanalytics\Dockerfile',
    'USER_MANUAL.md',
    'config\analytics\README.md'
)

$missing = @()
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot $relative))) {
        $missing += $relative
    }
}
if ($missing.Count -gt 0) {
    throw "Missing project files: $($missing -join ', ')"
}

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $ProjectRoot 'traffic.ps1'),
    [ref]$tokens,
    [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) {
    $parseErrors | ForEach-Object { Write-Error $_.Message }
    throw 'traffic.ps1 has PowerShell syntax errors.'
}

$compose = Get-Content -LiteralPath (Join-Path $ProjectRoot 'compose.yaml') -Raw
foreach ($service in 'otvision-cpu', 'otvision-gpu', 'otanalytics') {
    if ($compose -notmatch "(?m)^  $([regex]::Escape($service)):") {
        throw "Compose service '$service' is missing."
    }
}

Write-Host 'Static project validation passed.' -ForegroundColor Green
