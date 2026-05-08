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

function Write-WarnCheck {
    param(
        [string]$Name,
        [string]$Detail
    )
    Write-Host ("[WARN] {0}: {1}" -f $Name, $Detail) -ForegroundColor Yellow
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

function Add-UserPathIfMissing {
    param([string]$PathToAdd)

    if ([string]::IsNullOrWhiteSpace($PathToAdd)) {
        return
    }

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $pathParts = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($userPath)) {
        $userPath.Split(";") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $pathParts.Add($_) }
    }

    $alreadyPresent = $false
    foreach ($entry in $pathParts) {
        if ($entry.TrimEnd("\") -ieq $PathToAdd.TrimEnd("\")) {
            $alreadyPresent = $true
        }
    }

    if (-not $alreadyPresent) {
        $pathParts.Add($PathToAdd)
        [Environment]::SetEnvironmentVariable("Path", (($pathParts | Select-Object -Unique) -join ";"), "User")
        Write-Host "Added Kimi bin directory to the user PATH for new PowerShell windows: $PathToAdd"
    }
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
        Add-UserPathIfMissing -PathToAdd (Split-Path -Parent $kimi)
        Update-CurrentPath
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

    Add-UserPathIfMissing -PathToAdd (Split-Path -Parent $kimi)
    Update-CurrentPath
    Write-Host "Kimi CLI installed: $kimi"
    return $kimi
}

function Get-KimiCommandLine {
    param([string]$KimiPath)

    if ([string]::IsNullOrWhiteSpace($KimiPath)) {
        return "kimi --yolo"
    }
    return ('& "{0}" --yolo' -f $KimiPath)
}

function Read-HiddenText {
    param([string]$Prompt)

    $secure = Read-Host $Prompt -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function ConvertTo-TomlString {
    param([string]$Value)
    if ($null -eq $Value) {
        return '""'
    }
    return ('"{0}"' -f (($Value -replace "\\", "\\") -replace '"', '\"'))
}

function Set-KimiCliAuth {
    param(
        [string]$ApiKey,
        [string]$TokenEnvVar,
        [string]$BaseUrl,
        [string]$ModelName
    )

    if ([string]::IsNullOrWhiteSpace($TokenEnvVar)) {
        $TokenEnvVar = "KIMI_API_KEY"
    }

    $effectiveApiKey = $ApiKey
    if ([string]::IsNullOrWhiteSpace($effectiveApiKey)) {
        $effectiveApiKey = [Environment]::GetEnvironmentVariable($TokenEnvVar, "Process")
    }
    if ([string]::IsNullOrWhiteSpace($effectiveApiKey)) {
        $effectiveApiKey = [Environment]::GetEnvironmentVariable($TokenEnvVar, "User")
    }
    if ([string]::IsNullOrWhiteSpace($effectiveApiKey) -and $TokenEnvVar -ne "KIMI_API_KEY") {
        $effectiveApiKey = [Environment]::GetEnvironmentVariable("KIMI_API_KEY", "Process")
    }
    if ([string]::IsNullOrWhiteSpace($effectiveApiKey) -and $TokenEnvVar -ne "KIMI_API_KEY") {
        $effectiveApiKey = [Environment]::GetEnvironmentVariable("KIMI_API_KEY", "User")
    }

    if ([string]::IsNullOrWhiteSpace($effectiveApiKey)) {
        Write-Host "Kimi API key was not provided. Kimi may ask for /login on first launch." -ForegroundColor Yellow
        return $false
    }

    [Environment]::SetEnvironmentVariable($TokenEnvVar, $effectiveApiKey, "User")
    Set-Item -Path ("Env:{0}" -f $TokenEnvVar) -Value $effectiveApiKey

    if ($TokenEnvVar -ne "KIMI_API_KEY") {
        [Environment]::SetEnvironmentVariable("KIMI_API_KEY", $effectiveApiKey, "User")
        $env:KIMI_API_KEY = $effectiveApiKey
    }

    [Environment]::SetEnvironmentVariable("KIMI_BASE_URL", $BaseUrl, "User")
    [Environment]::SetEnvironmentVariable("KIMI_MODEL_NAME", $ModelName, "User")
    $env:KIMI_BASE_URL = $BaseUrl
    $env:KIMI_MODEL_NAME = $ModelName

    $kimiDir = Join-Path $env:USERPROFILE ".kimi"
    New-Item -ItemType Directory -Force -Path $kimiDir | Out-Null
    $configPath = Join-Path $kimiDir "config.toml"
    $configContent = @(
        ("default_model = {0}" -f (ConvertTo-TomlString $ModelName)),
        "default_thinking = false",
        "default_yolo = false",
        "default_plan_mode = false",
        'theme = "dark"',
        "",
        ("[providers.{0}]" -f $ModelName),
        'type = "kimi"',
        ("base_url = {0}" -f (ConvertTo-TomlString $BaseUrl)),
        'api_key = "set-by-KIMI_API_KEY-env"',
        "",
        ("[models.{0}]" -f $ModelName),
        ("provider = {0}" -f (ConvertTo-TomlString $ModelName)),
        ("model = {0}" -f (ConvertTo-TomlString $ModelName)),
        "max_context_size = 262144",
        'capabilities = ["thinking"]',
        "",
        "[loop_control]",
        "max_steps_per_turn = 100",
        "max_retries_per_step = 3",
        "reserved_context_size = 50000",
        "compaction_trigger_ratio = 0.85"
    )
    $configContent | Set-Content -LiteralPath $configPath -Encoding UTF8

    Write-Host ("Configured Kimi CLI API-key auth: env={0}, base_url={1}, model={2}, config={3}, key=[redacted]" -f $TokenEnvVar, $BaseUrl, $ModelName, $configPath)
    return $true
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
    param(
        [string]$TargetRepoRoot,
        [string]$KimiCommand
    )

    Write-Step "Kimi 操作指南"
    Write-Host "先按下面 3 步操作："
    Write-Host ""
    Write-Host "1. 进入 AutoVMware 安装目录并打开 Kimi CLI："
    Write-Host "   cd $TargetRepoRoot"
    Write-Host "   $KimiCommand"
    Write-Host ""
    Write-Host "2. 复制下面两条分隔线之间的中文提示词，粘贴到 Kimi 里。"
    Write-Host "3. Kimi 会先只读发现候选 .vmx，询问源镜像、输出目录和克隆数量；没有看到最终计划并明确确认前，不会执行真实克隆。"
    Write-Host ""
    Write-Host "----- 开始：复制给 Kimi 的中文提示词 -----"
    Write-Host "你是这台 Windows 主机上的 AutoVMware macOS VMX 克隆运维助手。"
    Write-Host "请在这个目录中工作："
    Write-Host $TargetRepoRoot
    Write-Host ""
    Write-Host "目标："
    Write-Host "帮助运维找到需要克隆的 macOS / Hackintosh VMware .vmx 源镜像，确认克隆输出目录，询问需要克隆的数量，然后生成安全的克隆计划。"
    Write-Host ""
    Write-Host "工作规则："
    Write-Host "1. 不要读取、打印或暴露 .env 文件、token、密钥或任何秘密信息。"
    Write-Host "2. 在运维明确确认最终计划前，不要创建、启动、停止、删除、快照、清理或克隆任何虚拟机。"
    Write-Host "3. 第一阶段只能执行只读发现和 doctor 检查命令。"
    Write-Host "4. 先搜索本机可用磁盘里的 macOS / Hackintosh .vmx 候选镜像。优先使用内置 discover 命令，例如："
    Write-Host "   python .\skills\autovmware-macos-vmx-clone\scripts\cli.py discover --drive D --format markdown"
    Write-Host "5. 把候选 .vmx 路径、目标盘可用空间、建议输出目录展示给运维。"
    Write-Host "6. 询问运维选择哪个源 .vmx，并询问克隆数量；数量范围是 1 到 100。"
    Write-Host "7. 运维选择后，更新 config\autovmware-macos-vmx-clone.json，运行 doctor，生成 approval JSON，校验 approval JSON，然后运行 plan-clone。"
    Write-Host "8. 输出完整计划：源 .vmx、克隆数量、输出目录、内存、磁盘、克隆模式、是否开机、每一台目标虚拟机的 .vmx 路径。"
    Write-Host "9. 输出计划后必须停止，等待运维输入明确确认语句，才能执行任何真实克隆动作。"
    Write-Host "----- 结束：复制给 Kimi 的中文提示词 -----"
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
        if ($sourceVmxOk) { Write-Check "Source VMX" $true $config.source_vmx } else { Write-WarnCheck "Source VMX" $config.source_vmx }
        if (-not $sourceVmxOk) { $readinessWarnings.Add("The default source VMX does not exist. Kimi should discover the real source image on this host.") }

        $targetRoot = [string]$config.target_root
        $targetDrive = [System.IO.Path]::GetPathRoot($targetRoot)
        $targetDriveOk = -not [string]::IsNullOrWhiteSpace($targetDrive) -and (Test-Path -LiteralPath $targetDrive)
        if ($targetDriveOk) { Write-Check "Target drive" $true $targetDrive } else { Write-WarnCheck "Target drive" $targetDrive }
        if (-not $targetDriveOk) { $readinessWarnings.Add("The default clone output drive does not exist. Kimi should ask the operator for the real output drive.") }

        $freeGb = Get-FreeGb $targetRoot
        $minimumRequiredGb = ([int]$config.disk_gb) + 100
        $spaceOk = $null -ne $freeGb -and $freeGb -ge $minimumRequiredGb
        $spaceDetail = "free={0}GB, minimum={1}GB for install acceptance: one clone plus 100GB reserve" -f $freeGb, $minimumRequiredGb
        if ($spaceOk) { Write-Check "Target free space" $true $spaceDetail } else { Write-WarnCheck "Target free space" $spaceDetail }
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
        if ($vmrunOk) { Write-Check "VMware vmrun" $true $vmrun } else { Write-WarnCheck "VMware vmrun" $vmrun }
        if (-not $vmrunOk) { $readinessWarnings.Add("VMware Workstation vmrun.exe was not found. Kimi should report this before any real clone action.") }

        $vdisk = Find-Executable "vmware-vdiskmanager" @(
            "C:\Program Files (x86)\VMware\VMware Workstation\vmware-vdiskmanager.exe",
            "C:\Program Files\VMware\VMware Workstation\vmware-vdiskmanager.exe"
        )
        $vdiskOk = -not [string]::IsNullOrWhiteSpace($vdisk)
        if ($vdiskOk) { Write-Check "VMware disk tool" $true $vdisk } else { Write-WarnCheck "VMware disk tool" $vdisk }
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

if (-not [string]::IsNullOrWhiteSpace($env:AUTOVMWARE_RELEASE_SKILL_SOURCE) -and ($SkillSource -eq $RepoRoot -or -not (Test-Path -LiteralPath $SkillSource))) {
    Write-Host ("Using release skill source from AUTOVMWARE_RELEASE_SKILL_SOURCE: {0}" -f $env:AUTOVMWARE_RELEASE_SKILL_SOURCE) -ForegroundColor Yellow
    $SkillSource = $env:AUTOVMWARE_RELEASE_SKILL_SOURCE
}

Write-Host ("Install target: {0}" -f $RepoRoot)
Write-Host ("Skill source: {0}" -f $SkillSource)

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

Write-Step "Configuring Kimi CLI authentication"
$kimiAuthConfigured = $false
if ($MockMode) {
    Write-Host "Mock mode enabled; not writing real Kimi CLI authentication."
} else {
    if ($PromptKimiApiKey -and [string]::IsNullOrWhiteSpace($KimiApiKey)) {
        $KimiApiKey = Read-HiddenText "粘贴 Kimi API Key（输入不会显示）"
    }
    $kimiAuthConfigured = Set-KimiCliAuth -ApiKey $KimiApiKey -TokenEnvVar $KimiTokenEnvVar -BaseUrl $KimiBaseUrl -ModelName $KimiModelName
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
$tokenPresent = $kimiAuthConfigured -or (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($KimiTokenEnvVar))) -or (-not [string]::IsNullOrWhiteSpace($DummyKimiToken))
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

Write-Step "安装完成后的操作指南"
Write-Host "1. 进入 AutoVMware 安装目录并启动 Kimi："
Write-Host "   cd $RepoRoot"
$kimiCommand = Get-KimiCommandLine -KimiPath $kimiPath
Write-Host "   $kimiCommand"
Write-Host ""
Write-Host "2. 把下方中文提示词完整粘贴给 Kimi。Kimi 会先帮运维发现真实源 VMX，并询问要克隆几台。"
Write-Host ""
Write-Host "3. Kimi 必须先生成并展示计划，等运维明确确认后才允许执行真实克隆。"
Write-Host ""
if ($kimiAuthConfigured) {
    Write-Host "4. Kimi API Key 已写入本机用户环境变量和 Kimi CLI 配置，启动后通常不需要网页登录。不要把真实 token 粘贴到 GitHub、日志或聊天里。"
} else {
    Write-Host "4. 还没有检测到 Kimi API Key。首次启动如果要求登录，请先配置 KIMI_API_KEY，或重新运行安装器并传入 -KimiApiKey。"
}
Write-Host ""
Write-Host "5. 真实克隆前，Kimi 必须列出源 VMX、输出目录、克隆数量、是否开机、以及每一台目标虚拟机路径。"
Write-Host ""
Write-Host "提示：一键安装器是在子 PowerShell 里安装 Kimi 的，当前已打开的 PowerShell 可能还识别不了 kimi。上面打印的是可直接运行的完整命令；新开一个 PowerShell 后通常也可以直接运行 kimi。"

Write-KimiOperatorPrompt -TargetRepoRoot $RepoRoot -KimiCommand $kimiCommand
