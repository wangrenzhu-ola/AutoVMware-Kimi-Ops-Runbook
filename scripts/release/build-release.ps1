param(
    [string]$Version = "0.1.0",
    [string]$OutputDir = "dist"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$packageFolder = "AutoVMware-Kimi-Ops-v$Version"
$zipName = "AutoVMware-Kimi-Ops-v$Version.zip"
$staging = Join-Path $repoRoot ".release\$packageFolder"
$zipPath = Join-Path $repoRoot "$OutputDir\$zipName"

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
    "docs",
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
Write-Host "Release 压缩包已生成：$zipPath"
