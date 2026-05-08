param(
    [string]$RepoRoot = "C:\Users\PC12\Documents\AutoVMware",
    [string]$SkillSource = "",
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

function Get-UserLocalBinPath {
    if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        return $null
    }
    return Join-Path $env:USERPROFILE ".local\bin"
}

function Update-CurrentPath {
    $pathParts = New-Object System.Collections.Generic.List[string]

    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if (-not [string]::IsNullOrWhiteSpace($machinePath)) {
        $machinePath.Split(";") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $pathParts.Add($_) }
    }

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not [string]::IsNullOrWhiteSpace($userPath)) {
        $userPath.Split(";") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $pathParts.Add($_) }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:Path)) {
        $env:Path.Split(";") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $pathParts.Add($_) }
    }

    $userLocalBin = Get-UserLocalBinPath
    if (-not [string]::IsNullOrWhiteSpace($userLocalBin)) {
        $pathParts.Add($userLocalBin)
    }

    $env:Path = ($pathParts | Select-Object -Unique) -join ";"
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

function Find-KimiExecutable {
    $fallbacks = @()
    $userLocalBin = Get-UserLocalBinPath
    if (-not [string]::IsNullOrWhiteSpace($userLocalBin)) {
        $fallbacks += (Join-Path $userLocalBin "kimi.exe")
        $fallbacks += (Join-Path $userLocalBin "kimi")
    }
    return Find-Executable "kimi" $fallbacks
}

function Find-UvExecutable {
    $fallbacks = @()
    $userLocalBin = Get-UserLocalBinPath
    if (-not [string]::IsNullOrWhiteSpace($userLocalBin)) {
        $fallbacks += (Join-Path $userLocalBin "uv.exe")
        $fallbacks += (Join-Path $userLocalBin "uv")
    }
    return Find-Executable "uv" $fallbacks
}

function Install-KimiCli {
    Update-CurrentPath

    $kimi = Find-KimiExecutable
    if (-not [string]::IsNullOrWhiteSpace($kimi)) {
        Write-Host "Kimi CLI is already available: $kimi"
        return $kimi
    }

    Write-Host "kimi command was not found. Installing uv and kimi-cli..."
    $uv = Find-UvExecutable
    if ([string]::IsNullOrWhiteSpace($uv)) {
        Write-Host "uv command was not found. Installing uv through the official installer..."
        Invoke-RestMethod -Uri "https://astral.sh/uv/install.ps1" | Invoke-Expression
        Update-CurrentPath
        $uv = Find-UvExecutable
    }

    if ([string]::IsNullOrWhiteSpace($uv)) {
        throw "uv was not found after installation. Restart PowerShell and run install.ps1 again, or install uv manually."
    }

    Write-Host "Using uv: $uv"
    & $uv tool install --python 3.13 kimi-cli
    if ($LASTEXITCODE -ne 0) {
        throw "uv failed to install kimi-cli."
    }

    Update-CurrentPath
    $kimi = Find-KimiExecutable
    if ([string]::IsNullOrWhiteSpace($kimi)) {
        throw "kimi-cli installation finished, but kimi was not found on PATH or in the user local bin directory. Restart PowerShell and run install.ps1 again."
    }

    Write-Host "Kimi CLI installed: $kimi"
    return $kimi
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

function Test-RunningOnWindows {
    if ($PSVersionTable.ContainsKey("Platform")) {
        return $PSVersionTable.Platform -eq "Win32NT"
    }
    return $env:OS -eq "Windows_NT"
}

function Write-KimiOperatorPrompt {
    param([string]$TargetRepoRoot)

    Write-Step "Kimi operator prompt"
    Write-Host "Open Kimi CLI from the AutoVMware directory:"
    Write-Host "   cd $TargetRepoRoot"
    Write-Host "   kimi"
    Write-Host ""
    Write-Host "Paste this prompt into Kimi:"
    Write-Host "----- BEGIN KIMI PROMPT -----"
    Write-Host "You are the AutoVMware macOS VMX clone operator on this Windows host."
    Write-Host "Work in this directory:"
    Write-Host $TargetRepoRoot
    Write-Host ""
    Write-Host "Goal:"
    Write-Host "Help operations find the source macOS VMware .vmx image, choose a clone output directory, ask how many clones to create, then generate a safe clone plan."
    Write-Host ""
    Write-Host "Rules:"
    Write-Host "1. Do not read or print .env files or secrets."
    Write-Host "2. Do not create, start, stop, delete, snapshot, clean, or clone any VM until the operator explicitly confirms the final plan."
    Write-Host "3. First run only read-only discovery and doctor commands."
    Write-Host "4. Search available file-system drives for likely macOS or Hackintosh .vmx files. Prefer the built-in discover command, for example:"
    Write-Host "   python .\skills\autovmware-macos-vmx-clone\scripts\cli.py discover --drive D --format markdown"
    Write-Host "5. Show the operator the candidate .vmx paths, target drive free space, and a recommended output directory."
    Write-Host "6. Ask the operator to choose the source .vmx and clone count, from 1 to 100."
    Write-Host "7. After the operator chooses, update config\autovmware-macos-vmx-clone.json, run doctor, generate an approval JSON, validate it, and run plan-clone."
    Write-Host "8. Print the complete plan: source .vmx, clone count, output directory, memory, disk, clone mode, power-on policy, and every target .vmx path."
    Write-Host "9. Stop and wait for explicit confirmation before any real clone action."
    Write-Host "----- END KIMI PROMPT -----"
}

function Invoke-PreflightDoctor {
    param(
        [string]$SkillSourcePath,
        [string]$TargetRepoRoot,
        [bool]$UseMockMode
    )

    Write-Step "Running preflight checks"
    $failures = New-Object System.Collections.Generic.List[string]
    $readinessWarnings = New-Object System.Collections.Generic.List[string]

    $runningOnWindows = Test-RunningOnWindows
    Write-Check "Windows" $runningOnWindows "This installer must run on the Windows AutoVMware host."
    if (-not $runningOnWindows) { $failures.Add("Run this installer on the Windows target host.") }

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

    if ($UseMockMode) {
        Write-Check "Mock mode" $true "Skipping real VMX, target drive, and VMware CLI checks for CI or dry-run validation."
    }

    if ($null -ne $config -and -not $UseMockMode) {
        $sourceVmxOk = Test-Path -LiteralPath $config.source_vmx
        Write-Check "Source VMX" $sourceVmxOk $config.source_vmx
        if (-not $sourceVmxOk) { $readinessWarnings.Add("The default source VMX does not exist. Kimi should discover the real source image on this host.") }

        $targetRoot = [string]$config.target_root
        $targetDrive = [System.IO.Path]::GetPathRoot($targetRoot)
        $targetDriveOk = -not [string]::IsNullOrWhiteSpace($targetDrive) -and (Test-Path -LiteralPath $targetDrive)
        Write-Check "Target drive" $targetDriveOk $targetDrive
        if (-not $targetDriveOk) { $readinessWarnings.Add("The default clone output drive does not exist. Kimi should ask the operator for the real output drive.") }

        $freeGb = Get-FreeGb $targetRoot
        $minimumRequiredGb = ([int]$config.disk_gb) + 100
        $spaceOk = $null -ne $freeGb -and $freeGb -ge $minimumRequiredGb
        Write-Check "Target free space" $spaceOk ("free={0}GB, minimum={1}GB for install acceptance: one clone plus 100GB reserve" -f $freeGb, $minimumRequiredGb)
        if (-not $spaceOk) { $readinessWarnings.Add("The default clone output path does not have a verified space budget. Kimi must re-check space after the operator chooses the output directory and clone count.") }

        if ($null -ne $freeGb) {
            $maxCloneCount = [math]::Floor(($freeGb - 100) / [int]$config.disk_gb)
            if ($maxCloneCount -lt 0) { $maxCloneCount = 0 }
            if ($maxCloneCount -gt 100) { $maxCloneCount = 100 }
            Write-Host ("[INFO] With {0}GB per clone and 100GB reserved, the current drive can support up to {1} clones. Kimi will re-check space for the requested count before real clone." -f $config.disk_gb, $maxCloneCount) -ForegroundColor Yellow
        }
    }

    if (-not $UseMockMode) {
        $vmrun = Find-Executable "vmrun" @(
            "C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe",
            "C:\Program Files\VMware\VMware Workstation\vmrun.exe"
        )
        $vmrunOk = -not [string]::IsNullOrWhiteSpace($vmrun)
        Write-Check "VMware vmrun" $vmrunOk $vmrun
        if (-not $vmrunOk) { $readinessWarnings.Add("VMware Workstation vmrun.exe was not found. Kimi should report this before any real clone action.") }

        $vdisk = Find-Executable "vmware-vdiskmanager" @(
            "C:\Program Files (x86)\VMware\VMware Workstation\vmware-vdiskmanager.exe",
            "C:\Program Files\VMware\VMware Workstation\vmware-vdiskmanager.exe"
        )
        $vdiskOk = -not [string]::IsNullOrWhiteSpace($vdisk)
        Write-Check "VMware disk tool" $vdiskOk $vdisk
        if (-not $vdiskOk) { $readinessWarnings.Add("VMware Workstation vmware-vdiskmanager.exe was not found. Kimi should report this before any real clone action.") }
    }

    if ($readinessWarnings.Count -gt 0) {
        Write-Host ""
        Write-Host "Install can continue. Kimi must resolve these readiness items before cloning:" -ForegroundColor Yellow
        foreach ($warning in $readinessWarnings) {
            Write-Host "- $warning" -ForegroundColor Yellow
        }
    }

    if ($failures.Count -gt 0 -and -not $Force) {
        Write-Host ""
        Write-Host "Preflight failed because the release package or base runtime is not usable." -ForegroundColor Red
        foreach ($failure in $failures) {
            Write-Host "- $failure" -ForegroundColor Red
        }
        Write-Host ""
        Write-Host "Fix the issues above and run install.ps1 again." -ForegroundColor Yellow
        exit 2
    }

    if ($failures.Count -gt 0 -and $Force) {
        Write-Host "Preflight found blockers, but -Force was provided. Continue only if this was explicitly approved by the owner." -ForegroundColor Yellow
    }
}

if ([string]::IsNullOrWhiteSpace($SkillSource)) {
    $SkillSource = Join-Path $PSScriptRoot "skills\autovmware-macos-vmx-clone"
}

Invoke-PreflightDoctor -SkillSourcePath $SkillSource -TargetRepoRoot $RepoRoot -UseMockMode ([bool]$MockMode)

Write-Step "Checking Kimi CLI"
$kimiPath = $null
if ($MockMode) {
    Write-Host "Mock mode enabled; not installing or calling real Kimi CLI."
} elseif (-not $SkipKimiInstall) {
    $kimiPath = Install-KimiCli
} else {
    Update-CurrentPath
    $kimiPath = Find-KimiExecutable
}

if ((-not $MockMode) -and (-not [string]::IsNullOrWhiteSpace($kimiPath))) {
    & $kimiPath --version
} elseif ($MockMode) {
    Write-Host "Kimi CLI version check skipped in mock mode."
} else {
    Write-Warning "Kimi CLI was not found because -SkipKimiInstall was provided. Re-run without -SkipKimiInstall to install it."
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

$tokenExamplePath = Join-Path $RepoRoot "config\kimi-ops.env.example"
$tokenExample = @(
    "# Copy to a local secret store or machine-level environment setup. Do not commit real values.",
    ("{0}=replace-with-issued-token" -f $KimiTokenEnvVar),
    "AUTOVMWARE_KIMI_TOKEN_MODE=env"
)
$tokenExample | Set-Content -LiteralPath $tokenExamplePath -Encoding ASCII
Write-Host "Created token configuration example: $tokenExamplePath"

$tokenStatusPath = Join-Path $RepoRoot "config\kimi-token-status.json"
$tokenPresent = (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($KimiTokenEnvVar))) -or (-not [string]::IsNullOrWhiteSpace($DummyKimiToken))
$tokenStatus = [ordered]@{
    ok = $true
    token_env_var = $KimiTokenEnvVar
    token_present = $tokenPresent
    token_value = $(if ($tokenPresent) { "[redacted]" } else { "[missing]" })
    token_mode = $(if ($MockMode) { "mock-dummy" } else { "env" })
    mock_mode = [bool]$MockMode
    real_vm_action_executed = $false
}
$tokenStatus | ConvertTo-Json | Set-Content -LiteralPath $tokenStatusPath -Encoding ASCII
Write-Host "Created redacted token status: $tokenStatusPath"

Write-Step "Next steps"
Write-Host "1. Enter the AutoVMware directory and start Kimi:"
Write-Host "   cd $RepoRoot"
Write-Host "   kimi"
Write-Host ""
Write-Host "2. Paste the operator prompt below into Kimi. Kimi should discover the real source VMX and ask how many clones to create."
Write-Host ""
Write-Host "3. Kimi must generate and show a plan first, then wait for explicit confirmation before real clone."
Write-Host ""
Write-Host "4. Before using Kimi, request a token from Infra/Hermes, set it in the machine environment variable shown in config\\kimi-ops.env.example, and never paste the real token into GitHub, logs, or chat."
Write-Host ""
Write-Host "5. Kimi must list the source VMX, output directory, count, power-on policy, and every target path before any real clone."

Write-KimiOperatorPrompt -TargetRepoRoot $RepoRoot
