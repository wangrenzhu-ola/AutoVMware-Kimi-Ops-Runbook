param(
    [string]$Version = "latest",
    [string]$WorkDir = "",
    [string]$RepoRoot = "",
    [string]$KimiTokenEnvVar = "KIMI_API_KEY",
    [string]$DummyKimiToken = "",
    [switch]$MockMode,
    [switch]$SkipKimiInstall,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Set-Tls12 {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

function Get-ReleaseInfo {
    param([string]$RequestedVersion)

    $repo = "wangrenzhu-ola/AutoVMware-Kimi-Ops-Runbook"
    if ($RequestedVersion -eq "latest") {
        $url = "https://api.github.com/repos/$repo/releases/latest"
    } else {
        $tag = $RequestedVersion
        if (-not $tag.StartsWith("v")) {
            $tag = "v$tag"
        }
        $url = "https://api.github.com/repos/$repo/releases/tags/$tag"
    }

    Invoke-RestMethod -Uri $url -Headers @{ "User-Agent" = "AutoVMware-Kimi-Ops-Installer" }
}

function Get-ReleaseZipAsset {
    param($Release)

    $asset = $Release.assets | Where-Object { $_.name -like "AutoVMware-Kimi-Ops-v*.zip" } | Select-Object -First 1
    if ($null -eq $asset) {
        throw "Release $($Release.tag_name) does not contain AutoVMware-Kimi-Ops zip asset."
    }
    return $asset
}

function Remove-DirectoryIfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

Set-Tls12

if ([string]::IsNullOrWhiteSpace($WorkDir)) {
    $WorkDir = Join-Path $env:TEMP "AutoVMware-Kimi-Ops-Installer"
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "AutoVMware"
}

Write-Step "Resolving AutoVMware Kimi Ops release"
$release = Get-ReleaseInfo -RequestedVersion $Version
$asset = Get-ReleaseZipAsset -Release $release

$downloadDir = Join-Path $WorkDir "download"
$extractDir = Join-Path $WorkDir "extract"
New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null
Remove-DirectoryIfExists -Path $extractDir
New-Item -ItemType Directory -Force -Path $extractDir | Out-Null

$zipPath = Join-Path $downloadDir $asset.name
Write-Host ("Release: {0}" -f $release.tag_name)
Write-Host ("Download: {0}" -f $asset.browser_download_url)
Write-Host ("Zip: {0}" -f $zipPath)

Write-Step "Downloading release package"
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -Headers @{ "User-Agent" = "AutoVMware-Kimi-Ops-Installer" }

Write-Step "Extracting release package"
Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force

$installPath = Get-ChildItem -LiteralPath $extractDir -Recurse -File -Filter "install.ps1" | Select-Object -First 1
if ($null -eq $installPath) {
    throw "Downloaded package does not contain install.ps1."
}

Write-Host ("Installer: {0}" -f $installPath.FullName)
$packageRoot = Split-Path -Parent $installPath.FullName
$skillSource = Join-Path $packageRoot "skills\autovmware-macos-vmx-clone"
if (-not (Test-Path -LiteralPath $skillSource)) {
    throw "Downloaded package does not contain skill directory: $skillSource"
}
Write-Host ("Skill source: {0}" -f $skillSource)

Write-Step "Running installer"
& $installPath.FullName `
    -RepoRoot $RepoRoot `
    -SkillSource $skillSource `
    -KimiTokenEnvVar $KimiTokenEnvVar `
    -DummyKimiToken $DummyKimiToken `
    -MockMode:$MockMode `
    -SkipKimiInstall:$SkipKimiInstall `
    -Force:$Force
