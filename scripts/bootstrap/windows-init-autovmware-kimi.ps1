param(
    [string]$RepoRoot = "C:\Users\PC12\Documents\AutoVMware",
    [string]$SkillSource = "",
    [switch]$SkipKimiInstall,
    [switch]$Force
)

$rootInstall = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "install.ps1"
if (-not (Test-Path -LiteralPath $rootInstall)) {
    throw "install.ps1 was not found at release root: $rootInstall"
}

& $rootInstall -RepoRoot $RepoRoot -SkillSource $SkillSource -SkipKimiInstall:$SkipKimiInstall -Force:$Force
