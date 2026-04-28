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
    $status = if ($Ok) { "通过" } else { "失败" }
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

    Write-Step "开始安装前检查"
    $failures = New-Object System.Collections.Generic.List[string]

    $isWindows = $PSVersionTable.Platform -eq "Win32NT" -or $env:OS -eq "Windows_NT"
    Write-Check "Windows 系统" $isWindows "这个安装脚本只能在 Windows AutoVMware 主机上运行。"
    if (-not $isWindows) { $failures.Add("请在 Windows 目标机上运行这个安装脚本。") }

    $psOk = $PSVersionTable.PSVersion.Major -ge 5
    Write-Check "PowerShell 版本" $psOk $PSVersionTable.PSVersion.ToString()
    if (-not $psOk) { $failures.Add("需要 PowerShell 5 或更新版本。") }

    $pythonOk = Test-Command "python"
    Write-Check "Python" $pythonOk "需要能直接运行 python，版本建议 3.10 或更新。"
    if (-not $pythonOk) { $failures.Add("请安装 Python 3.10 或更新版本，并把 python 加到 PATH。") }

    $skillOk = Test-Path -LiteralPath $SkillSourcePath
    Write-Check "技能目录" $skillOk $SkillSourcePath
    if (-not $skillOk) { $failures.Add("交付包里缺少技能目录。请重新下载 Release 压缩包。") }

    $cliPath = Join-Path $SkillSourcePath "scripts\cli.py"
    $cliOk = Test-Path -LiteralPath $cliPath
    Write-Check "技能脚本" $cliOk $cliPath
    if (-not $cliOk) { $failures.Add("交付包里缺少技能脚本 cli.py。请重新下载 Release 压缩包。") }

    $configPath = Join-Path $SkillSourcePath "config\defaults.json"
    $configOk = Test-Path -LiteralPath $configPath
    Write-Check "默认配置" $configOk $configPath
    if (-not $configOk) { $failures.Add("交付包里缺少默认配置 defaults.json。请重新下载 Release 压缩包。") }

    $config = $null
    if ($configOk) {
        try {
            $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
            Write-Check "配置格式" $true "配置能正常读取。"
        } catch {
            Write-Check "配置格式" $false $_.Exception.Message
            $failures.Add("默认配置 JSON 格式不正确。")
        }
    }

    if ($null -ne $config) {
        $sourceVmxOk = Test-Path -LiteralPath $config.source_vmx
        Write-Check "源 VMX" $sourceVmxOk $config.source_vmx
        if (-not $sourceVmxOk) { $failures.Add("配置里的源 VMX 不存在。请确认源镜像路径。") }

        $targetRoot = [string]$config.target_root
        $targetDrive = [System.IO.Path]::GetPathRoot($targetRoot)
        $targetDriveOk = -not [string]::IsNullOrWhiteSpace($targetDrive) -and (Test-Path -LiteralPath $targetDrive)
        Write-Check "输出盘" $targetDriveOk $targetDrive
        if (-not $targetDriveOk) { $failures.Add("克隆输出目录所在磁盘不存在。") }

        $freeGb = Get-FreeGb $targetRoot
        $requiredGb = ([int]$config.disk_gb * 5) + 40
        $spaceOk = $null -ne $freeGb -and $freeGb -ge $requiredGb
        Write-Check "输出盘剩余空间" $spaceOk ("剩余={0}GB，默认 5 个克隆至少需要={1}GB" -f $freeGb, $requiredGb)
        if (-not $spaceOk) { $failures.Add("输出盘剩余空间不足，达不到默认 5 个克隆的预算。") }
    }

    $vmrun = Find-Executable "vmrun" @(
        "C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe",
        "C:\Program Files\VMware\VMware Workstation\vmrun.exe"
    )
    $vmrunOk = -not [string]::IsNullOrWhiteSpace($vmrun)
    Write-Check "VMware vmrun" $vmrunOk $vmrun
    if (-not $vmrunOk) { $failures.Add("找不到 VMware Workstation 的 vmrun.exe。") }

    $vdisk = Find-Executable "vmware-vdiskmanager" @(
        "C:\Program Files (x86)\VMware\VMware Workstation\vmware-vdiskmanager.exe",
        "C:\Program Files\VMware\VMware Workstation\vmware-vdiskmanager.exe"
    )
    $vdiskOk = -not [string]::IsNullOrWhiteSpace($vdisk)
    Write-Check "VMware 磁盘工具" $vdiskOk $vdisk
    if (-not $vdiskOk) { $failures.Add("找不到 VMware Workstation 的 vmware-vdiskmanager.exe。") }

    if ($failures.Count -gt 0 -and -not $Force) {
        Write-Host ""
        Write-Host "检查失败。脚本没有执行安装，也没有写配置。" -ForegroundColor Red
        foreach ($failure in $failures) {
            Write-Host "- $failure" -ForegroundColor Red
        }
        Write-Host ""
        Write-Host "请先修复上面的问题，再重新运行 install.ps1。只有负责人明确接受这些阻断项时，才允许使用 -Force。" -ForegroundColor Yellow
        exit 2
    }

    if ($failures.Count -gt 0 -and $Force) {
        Write-Host "检查发现阻断项，但你使用了 -Force，脚本会继续执行。请确认这是负责人允许的操作。" -ForegroundColor Yellow
    }
}

if ([string]::IsNullOrWhiteSpace($SkillSource)) {
    $SkillSource = Join-Path $PSScriptRoot "skills\autovmware-macos-vmx-clone"
}

Invoke-PreflightDoctor -SkillSourcePath $SkillSource -TargetRepoRoot $RepoRoot

Write-Step "检查 Kimi CLI"
if (-not $SkipKimiInstall) {
    if (-not (Test-Command "kimi")) {
        Write-Host "本机没有 kimi 命令，开始通过官方脚本安装 Kimi CLI..."
        Invoke-RestMethod https://code.kimi.com/install.ps1 | Invoke-Expression
    } else {
        Write-Host "Kimi CLI 已经可用。"
    }
}

if (Test-Command "kimi") {
    kimi --version
} else {
    Write-Warning "没有找到 Kimi CLI。请去掉 -SkipKimiInstall 重新运行，或手工安装 Kimi CLI。"
}

Write-Step "准备 AutoVMware 目录"
New-Item -ItemType Directory -Force -Path $RepoRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $RepoRoot "config") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $RepoRoot "reports\dem009\screenshots") | Out-Null

$defaultConfigSource = Join-Path $SkillSource "config\defaults.json"
$defaultConfigTarget = Join-Path $RepoRoot "config\autovmware-macos-vmx-clone.json"

if (-not (Test-Path -LiteralPath $defaultConfigTarget)) {
    Copy-Item -LiteralPath $defaultConfigSource -Destination $defaultConfigTarget
    Write-Host "已创建默认配置：$defaultConfigTarget"
} else {
    Write-Host "配置已经存在，本次不覆盖：$defaultConfigTarget"
}

Write-Step "下一步操作"
Write-Host "1. 进入 AutoVMware 目录并启动 Kimi："
Write-Host "   cd $RepoRoot"
Write-Host "   kimi"
Write-Host ""
Write-Host "2. 让 Kimi 先检查环境："
Write-Host "   使用 autovmware-macos-vmx-clone 技能运行 doctor，只检查，不要克隆。"
Write-Host ""
Write-Host "3. 检查通过后，再让 Kimi 按默认配置生成 5 个克隆计划："
Write-Host "   使用 autovmware-macos-vmx-clone 技能，按默认配置克隆 5 个镜像。先列计划，等我确认。"
Write-Host ""
Write-Host "4. Kimi 必须先列出源 VMX、输出目录、数量、是否开机和每个目标路径，等确认后才能真实克隆。"
