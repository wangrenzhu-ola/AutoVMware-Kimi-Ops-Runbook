param(
    [string]$Version = "0.1.0",
    [string]$OutputDir = "dist"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$packageName = "autovmware-kimi-ops-runbook-v$Version"
$staging = Join-Path $repoRoot ".release\$packageName"
$zipPath = Join-Path $repoRoot "$OutputDir\$packageName.zip"

if (Test-Path -LiteralPath $staging) {
    Remove-Item -LiteralPath $staging -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $staging | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $repoRoot $OutputDir) | Out-Null

$items = @(
    "README.md",
    "install.ps1",
    "pyproject.toml",
    "uv.lock",
    "scripts",
    "skills",
    "tests"
)

foreach ($item in $items) {
    $source = Join-Path $repoRoot $item
    if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination $staging -Recurse
    }
}

Get-ChildItem -LiteralPath $staging -Recurse -Force -Directory -Filter "__pycache__" | Remove-Item -Recurse -Force
Get-ChildItem -LiteralPath $staging -Recurse -Force -Directory -Filter ".pytest_cache" | Remove-Item -Recurse -Force
Get-ChildItem -LiteralPath $staging -Recurse -Force -Directory -Filter ".venv" | Remove-Item -Recurse -Force

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

Compress-Archive -LiteralPath $staging -DestinationPath $zipPath
Write-Host "Release package created: $zipPath"
