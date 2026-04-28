param(
    [string]$RepoRoot = "C:\Users\PC12\Documents\AutoVMware",
    [string]$SkillSource = "",
    [switch]$SkipKimiInstall
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Test-Command {
    param([string]$Name)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    return $null -ne $command
}

Write-Step "Checking base tools"
if (-not (Test-Command "python")) {
    throw "Python is not on PATH. Install Python 3.10+ before running this initializer."
}
if (-not (Test-Command "git")) {
    throw "Git is not on PATH. Install Git for Windows before running this initializer."
}

Write-Step "Ensuring Kimi CLI"
if (-not $SkipKimiInstall) {
    if (-not (Test-Command "kimi")) {
        Write-Host "Installing Kimi CLI through the official installer..."
        Invoke-RestMethod https://code.kimi.com/install.ps1 | Invoke-Expression
    } else {
        Write-Host "Kimi CLI already exists on PATH."
    }
}

if (Test-Command "kimi") {
    kimi --version
} else {
    Write-Warning "Kimi CLI was not found. Re-run without -SkipKimiInstall or install it manually."
}

Write-Step "Preparing AutoVMware repo folders"
New-Item -ItemType Directory -Force -Path $RepoRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $RepoRoot "config") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $RepoRoot "reports\dem009\screenshots") | Out-Null

if ([string]::IsNullOrWhiteSpace($SkillSource)) {
    $SkillSource = Join-Path (Get-Location) "skills\autovmware-macos-vmx-clone"
}

$defaultConfigSource = Join-Path $SkillSource "config\defaults.json"
$defaultConfigTarget = Join-Path $RepoRoot "config\autovmware-macos-vmx-clone.json"

if (Test-Path -LiteralPath $defaultConfigSource) {
    if (-not (Test-Path -LiteralPath $defaultConfigTarget)) {
        Copy-Item -LiteralPath $defaultConfigSource -Destination $defaultConfigTarget
        Write-Host "Created default config: $defaultConfigTarget"
    } else {
        Write-Host "Config already exists, leaving it unchanged: $defaultConfigTarget"
    }
} else {
    Write-Warning "Default config source not found: $defaultConfigSource"
}

Write-Step "Next commands for operators"
Write-Host "1. Open Kimi Code in the AutoVMware repo:"
Write-Host "   cd $RepoRoot"
Write-Host "   kimi"
Write-Host ""
Write-Host "2. Ask Kimi to run the skill doctor:"
Write-Host "   use autovmware-macos-vmx-clone doctor"
Write-Host ""
Write-Host "3. After doctor passes, request a default batch by count:"
Write-Host "   use autovmware-macos-vmx-clone clone 5"
Write-Host ""
Write-Host "4. Kimi must echo source_vmx, target_root, clone_count, power_on, and target paths before any real VM clone."
