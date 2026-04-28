param(
    [string]$RepoRoot = "C:\Users\PC12\Documents\AutoVMware",
    [string]$SkillSource = "",
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

function Write-Check {
    param(
        [string]$Name,
        [bool]$Ok,
        [string]$Detail
    )
    $status = if ($Ok) { "PASS" } else { "FAIL" }
    $color = if ($Ok) { "Green" } else { "Red" }
    Write-Host ("[{0}] {1}: {2}" -f $status, $Name, $Detail) -ForegroundColor $color
}

function Test-Command {
    param([string]$Name)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    return $null -ne $command
}

function Find-Executable {
    param(
        [string]$CommandName,
        [string[]]$FallbackPaths
    )
    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }
    foreach ($path in $FallbackPaths) {
        if (Test-Path -LiteralPath $path) {
            return $path
        }
    }
    return $null
}

function Get-FreeGb {
    param([string]$Path)
    try {
        $driveName = ([System.IO.Path]::GetPathRoot($Path)).TrimEnd("\")
        $drive = Get-PSDrive -Name $driveName.TrimEnd(":") -ErrorAction Stop
        return [math]::Round($drive.Free / 1GB, 2)
    } catch {
        return $null
    }
}

function Invoke-PreflightDoctor {
    param(
        [string]$SkillSourcePath,
        [string]$TargetRepoRoot
    )

    Write-Step "Running preflight checks"
    $failures = New-Object System.Collections.Generic.List[string]

    $isWindows = $PSVersionTable.Platform -eq "Win32NT" -or $env:OS -eq "Windows_NT"
    Write-Check "Windows" $isWindows "This installer must run on the Windows AutoVMware host."
    if (-not $isWindows) { $failures.Add("Run this installer on the Windows target host.") }

    $psOk = $PSVersionTable.PSVersion.Major -ge 5
    Write-Check "PowerShell version" $psOk $PSVersionTable.PSVersion.ToString()
    if (-not $psOk) { $failures.Add("PowerShell 5 or newer is required.") }

    $pythonOk = Test-Command "python"
    Write-Check "Python" $pythonOk "python must be runnable from PATH. Python 3.10 or newer is recommended."
    if (-not $pythonOk) { $failures.Add("Install Python 3.10 or newer and add python to PATH.") }

    $skillOk = Test-Path -LiteralPath $SkillSourcePath
    Write-Check "Skill directory" $skillOk $SkillSourcePath
    if (-not $skillOk) { $failures.Add("The release package is missing the skill directory. Download the release zip again.") }

    $cliPath = Join-Path $SkillSourcePath "scripts\cli.py"
    $cliOk = Test-Path -LiteralPath $cliPath
    Write-Check "Skill script" $cliOk $cliPath
    if (-not $cliOk) { $failures.Add("The release package is missing cli.py. Download the release zip again.") }

    $configPath = Join-Path $SkillSourcePath "config\defaults.json"
    $configOk = Test-Path -LiteralPath $configPath
    Write-Check "Default config" $configOk $configPath
    if (-not $configOk) { $failures.Add("The release package is missing defaults.json. Download the release zip again.") }

    $config = $null
    if ($configOk) {
        try {
            $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
            Write-Check "Config format" $true "Config can be read."
        } catch {
            Write-Check "Config format" $false $_.Exception.Message
            $failures.Add("Default config JSON is invalid.")
        }
    }

    if ($null -ne $config) {
        $sourceVmxOk = Test-Path -LiteralPath $config.source_vmx
        Write-Check "Source VMX" $sourceVmxOk $config.source_vmx
        if (-not $sourceVmxOk) { $failures.Add("The configured source VMX does not exist. Check the source image path.") }

        $targetRoot = [string]$config.target_root
        $targetDrive = [System.IO.Path]::GetPathRoot($targetRoot)
        $targetDriveOk = -not [string]::IsNullOrWhiteSpace($targetDrive) -and (Test-Path -LiteralPath $targetDrive)
        Write-Check "Target drive" $targetDriveOk $targetDrive
        if (-not $targetDriveOk) { $failures.Add("The clone output drive does not exist.") }

        $freeGb = Get-FreeGb $targetRoot
        $minimumRequiredGb = ([int]$config.disk_gb) + 100
        $spaceOk = $null -ne $freeGb -and $freeGb -ge $minimumRequiredGb
        Write-Check "Target free space" $spaceOk ("free={0}GB, minimum={1}GB for install acceptance: one clone plus 100GB reserve" -f $freeGb, $minimumRequiredGb)
        if (-not $spaceOk) { $failures.Add("Target drive free space is below the minimum budget for one clone plus 100GB reserve.") }

        if ($null -ne $freeGb) {
            $maxCloneCount = [math]::Floor(($freeGb - 100) / [int]$config.disk_gb)
            if ($maxCloneCount -lt 0) { $maxCloneCount = 0 }
            if ($maxCloneCount -gt 100) { $maxCloneCount = 100 }
            Write-Host ("[INFO] With {0}GB per clone and 100GB reserved, the current drive can support up to {1} clones. Kimi will re-check space for the requested count before real clone." -f $config.disk_gb, $maxCloneCount) -ForegroundColor Yellow
        }
    }

    $vmrun = Find-Executable "vmrun" @(
        "C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe",
        "C:\Program Files\VMware\VMware Workstation\vmrun.exe"
    )
    $vmrunOk = -not [string]::IsNullOrWhiteSpace($vmrun)
    Write-Check "VMware vmrun" $vmrunOk $vmrun
    if (-not $vmrunOk) { $failures.Add("VMware Workstation vmrun.exe was not found.") }

    $vdisk = Find-Executable "vmware-vdiskmanager" @(
        "C:\Program Files (x86)\VMware\VMware Workstation\vmware-vdiskmanager.exe",
        "C:\Program Files\VMware\VMware Workstation\vmware-vdiskmanager.exe"
    )
    $vdiskOk = -not [string]::IsNullOrWhiteSpace($vdisk)
    Write-Check "VMware disk tool" $vdiskOk $vdisk
    if (-not $vdiskOk) { $failures.Add("VMware Workstation vmware-vdiskmanager.exe was not found.") }

    if ($failures.Count -gt 0 -and -not $Force) {
        Write-Host ""
        Write-Host "Preflight failed. The installer did not install Kimi or write config." -ForegroundColor Red
        foreach ($failure in $failures) {
            Write-Host "- $failure" -ForegroundColor Red
        }
        Write-Host ""
        Write-Host "Fix the issues above and run install.ps1 again. Use -Force only when the owner explicitly accepts these blockers." -ForegroundColor Yellow
        exit 2
    }

    if ($failures.Count -gt 0 -and $Force) {
        Write-Host "Preflight found blockers, but -Force was provided. Continue only if this was explicitly approved by the owner." -ForegroundColor Yellow
    }
}

if ([string]::IsNullOrWhiteSpace($SkillSource)) {
    $SkillSource = Join-Path $PSScriptRoot "skills\autovmware-macos-vmx-clone"
}

Invoke-PreflightDoctor -SkillSourcePath $SkillSource -TargetRepoRoot $RepoRoot

Write-Step "Checking Kimi CLI"
if (-not $SkipKimiInstall) {
    if (-not (Test-Command "kimi")) {
        Write-Host "kimi command was not found. Installing Kimi CLI through the official installer..."
        Invoke-RestMethod https://code.kimi.com/install.ps1 | Invoke-Expression
    } else {
        Write-Host "Kimi CLI is already available."
    }
}

if (Test-Command "kimi") {
    kimi --version
} else {
    Write-Warning "Kimi CLI was not found. Re-run without -SkipKimiInstall or install Kimi CLI manually."
}

Write-Step "Preparing AutoVMware directories"
New-Item -ItemType Directory -Force -Path $RepoRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $RepoRoot "config") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $RepoRoot "reports\dem009\screenshots") | Out-Null

$defaultConfigSource = Join-Path $SkillSource "config\defaults.json"
$defaultConfigTarget = Join-Path $RepoRoot "config\autovmware-macos-vmx-clone.json"

if (-not (Test-Path -LiteralPath $defaultConfigTarget)) {
    Copy-Item -LiteralPath $defaultConfigSource -Destination $defaultConfigTarget
    Write-Host "Created default config: $defaultConfigTarget"
} else {
    Write-Host "Config already exists; leaving it unchanged: $defaultConfigTarget"
}

Write-Step "Next steps"
Write-Host "1. Enter the AutoVMware directory and start Kimi:"
Write-Host "   cd $RepoRoot"
Write-Host "   kimi"
Write-Host ""
Write-Host "2. Ask Kimi to check the environment first:"
Write-Host "   Use the autovmware-macos-vmx-clone skill to run doctor only. Do not clone."
Write-Host ""
Write-Host "3. After doctor passes, ask Kimi to generate a default clone plan, up to 100 clones:"
Write-Host "   Use the autovmware-macos-vmx-clone skill to clone 100 images with the default config. Check space with 100GB reserved, list the plan, then wait for my confirmation."
Write-Host ""
Write-Host "4. Kimi must list the source VMX, output directory, count, power-on policy, and every target path before any real clone."
