param(
    [string]$RepoRoot = "C:\Users\PC12\Documents\AutoVMware",
    [string]$SkillSource = "",
    [string]$KimiTokenEnvVar = "KIMI_API_KEY",
    [string]$KimiApiKey = "",
    [string]$KimiBaseUrl = "https://api.kimi.com/coding/v1",
    [string]$KimiModelName = "kimi-for-coding",
    [string]$DummyKimiToken = "",
    [switch]$PromptKimiApiKey,
    [switch]$MockMode,
    [switch]$SkipKimiInstall,
    [switch]$SkipKimiLaunch,
    [switch]$Force
)

$rootInstall = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "install.ps1"
if (-not (Test-Path -LiteralPath $rootInstall)) {
    throw "在交付包根目录没有找到 install.ps1：$rootInstall"
}

& $rootInstall -RepoRoot $RepoRoot -SkillSource $SkillSource -KimiTokenEnvVar $KimiTokenEnvVar -KimiApiKey $KimiApiKey -KimiBaseUrl $KimiBaseUrl -KimiModelName $KimiModelName -DummyKimiToken $DummyKimiToken -PromptKimiApiKey:$PromptKimiApiKey -MockMode:$MockMode -SkipKimiInstall:$SkipKimiInstall -SkipKimiLaunch:$SkipKimiLaunch -Force:$Force
