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
    $status = if ($Ok) { "OK" } else { "FAIL" }
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

    Write-Step "Running install doctor"
    $failures = New-Object System.Collections.Generic.List[string]

    $isWindows = $PSVersionTable.Platform -eq "Win32NT" -or $env:OS -eq "Windows_NT"
    Write-Check "Windows" $isWindows "This installer is for the Windows AutoVMware host."
    if (-not $isWindows) { $failures.Add("Run this installer on Windows.") }

    $psOk = $PSVersionTable.PSVersion.Major -ge 5
    Write-Check "PowerShell" $psOk $PSVersionTable.PSVersion.ToString()
    if (-not $psOk) { $failures.Add("PowerShell 5 or newer is required.") }

    $pythonOk = Test-Command "python"
    Write-Check "Python" $pythonOk "Python 3.10+ must be on PATH."
    if (-not $pythonOk) { $failures.Add("Install Python 3.10+ and add python to PATH.") }

    $skillOk = Test-Path -LiteralPath $SkillSourcePath
    Write-Check "Skill folder" $skillOk $SkillSourcePath
    if (-not $skillOk) { $failures.Add("Skill folder is missing from the release package.") }

    $cliPath = Join-Path $SkillSourcePath "scripts\cli.py"
    $cliOk = Test-Path -LiteralPath $cliPath
    Write-Check "Skill CLI" $cliOk $cliPath
    if (-not $cliOk) { $failures.Add("Skill CLI is missing from the release package.") }

    $configPath = Join-Path $SkillSourcePath "config\defaults.json"
    $configOk = Test-Path -LiteralPath $configPath
    Write-Check "Default config" $configOk $configPath
    if (-not $configOk) { $failures.Add("Default config is missing from the release package.") }

    $config = $null
    if ($configOk) {
        try {
            $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
            Write-Check "Config JSON" $true "Parsed successfully."
        } catch {
            Write-Check "Config JSON" $false $_.Exception.Message
            $failures.Add("Default config JSON is invalid.")
        }
    }

    if ($null -ne $config) {
        $sourceVmxOk = Test-Path -LiteralPath $config.source_vmx
        Write-Check "Source VMX" $sourceVmxOk $config.source_vmx
        if (-not $sourceVmxOk) { $failures.Add("Configured source_vmx does not exist.") }

        $targetRoot = [string]$config.target_root
        $targetDrive = [System.IO.Path]::GetPathRoot($targetRoot)
        $targetDriveOk = -not [string]::IsNullOrWhiteSpace($targetDrive) -and (Test-Path -LiteralPath $targetDrive)
        Write-Check "Target drive" $targetDriveOk $targetDrive
        if (-not $targetDriveOk) { $failures.Add("Target drive for clone output does not exist.") }

        $freeGb = Get-FreeGb $targetRoot
        $requiredGb = ([int]$config.disk_gb * 5) + 40
        $spaceOk = $null -ne $freeGb -and $freeGb -ge $requiredGb
        Write-Check "Target free space" $spaceOk ("free={0}GB required_at_least={1}GB" -f $freeGb, $requiredGb)
        if (-not $spaceOk) { $failures.Add("Target drive free space is below the default 5-clone budget.") }
    }

    $vmrun = Find-Executable "vmrun" @(
        "C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe",
        "C:\Program Files\VMware\VMware Workstation\vmrun.exe"
    )
    $vmrunOk = -not [string]::IsNullOrWhiteSpace($vmrun)
    Write-Check "vmrun" $vmrunOk $vmrun
    if (-not $vmrunOk) { $failures.Add("VMware Workstation vmrun.exe was not found.") }

    $vdisk = Find-Executable "vmware-vdiskmanager" @(
        "C:\Program Files (x86)\VMware\VMware Workstation\vmware-vdiskmanager.exe",
        "C:\Program Files\VMware\VMware Workstation\vmware-vdiskmanager.exe"
    )
    $vdiskOk = -not [string]::IsNullOrWhiteSpace($vdisk)
    Write-Check "vmware-vdiskmanager" $vdiskOk $vdisk
    if (-not $vdiskOk) { $failures.Add("VMware Workstation vmware-vdiskmanager.exe was not found.") }

    if ($failures.Count -gt 0 -and -not $Force) {
        Write-Host ""
        Write-Host "Doctor failed. No install actions were executed." -ForegroundColor Red
        foreach ($failure in $failures) {
            Write-Host "- $failure" -ForegroundColor Red
        }
        Write-Host ""
        Write-Host "Fix the failures and run install.ps1 again. Use -Force only if an operator intentionally accepts these blockers." -ForegroundColor Yellow
        exit 2
    }

    if ($failures.Count -gt 0 -and $Force) {
        Write-Host "Doctor found blockers, but -Force was provided. Continuing." -ForegroundColor Yellow
    }
}

if ([string]::IsNullOrWhiteSpace($SkillSource)) {
    $SkillSource = Join-Path $PSScriptRoot "skills\autovmware-macos-vmx-clone"
}

Invoke-PreflightDoctor -SkillSourcePath $SkillSource -TargetRepoRoot $RepoRoot

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

Write-Step "Preparing AutoVMware folders"
New-Item -ItemType Directory -Force -Path $RepoRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $RepoRoot "config") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $RepoRoot "reports\dem009\screenshots") | Out-Null

$defaultConfigSource = Join-Path $SkillSource "config\defaults.json"
$defaultConfigTarget = Join-Path $RepoRoot "config\autovmware-macos-vmx-clone.json"

if (-not (Test-Path -LiteralPath $defaultConfigTarget)) {
    Copy-Item -LiteralPath $defaultConfigSource -Destination $defaultConfigTarget
    Write-Host "Created default config: $defaultConfigTarget"
} else {
    Write-Host "Config already exists, leaving it unchanged: $defaultConfigTarget"
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
