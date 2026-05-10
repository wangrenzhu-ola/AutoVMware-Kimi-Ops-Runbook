param(
    [string]$Version = "0.1.7",
    [string]$RepoRoot = "C:\Users\PC12\Documents\AutoVMware",
    [switch]$DryRun
)

$ErrorActionPreference = "Continue"
Set-StrictMode -Version Latest

$releaseName = "AutoVMware-Kimi-Ops-v$Version"
$releaseUrl = "https://github.com/wangrenzhu-ola/AutoVMware-Kimi-Ops-Runbook/releases/download/v$Version/$releaseName.zip"
$downloadDir = Join-Path $env:USERPROFILE "Downloads"
$zipPath = Join-Path $downloadDir "$releaseName.zip"
$extractRoot = Join-Path $env:USERPROFILE "Documents\$releaseName-test"
$packageRoot = Join-Path $extractRoot $releaseName
$reportDir = Join-Path $RepoRoot "reports\acceptance"
$reportPath = Join-Path $reportDir ("kimi-clean-install-{0}.md" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

function Add-Line {
    param([string]$Text = "")
    $Text | Out-File -LiteralPath $reportPath -Encoding utf8 -Append
}

function Add-Command {
    param(
        [string]$Title,
        [scriptblock]$Command
    )
    Add-Line ""
    Add-Line "## $Title"
    Add-Line '```text'
    try {
        $output = & $Command 2>&1 | Out-String
        Add-Line $output.TrimEnd()
    } catch {
        Add-Line $_.Exception.Message
    }
    Add-Line '```'
}

function Remove-PathSafely {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if ($Path -like "$RepoRoot*") { Add-Line ("- 跳过 AutoVMware 目录：``{0}``" -f $Path); return }
    if ($Path -like "F:\*") { Add-Line ("- 跳过 F 盘路径：``{0}``" -f $Path); return }
    if (-not (Test-Path -LiteralPath $Path)) { Add-Line ("- 不存在：``{0}``" -f $Path); return }
    Add-Line ("- 删除：``{0}``" -f $Path)
    if (-not $DryRun) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Continue
    }
}

New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
Add-Line "# AutoVMware Kimi Release 人工验收记录"
Add-Line ""
Add-Line "- 时间：`$(Get-Date -Format s)`"
Add-Line "- Release：`v$Version`"
Add-Line ("- 下载地址：``{0}``" -f $releaseUrl)
Add-Line "- 干跑模式：`$DryRun`"
Add-Line "- 禁止动作：未执行 VM clone/start/stop/delete/snapshot/cleanup/power on；未读取 .env。"

Add-Command "清理前 Kimi 命令位置" {
    where.exe kimi
    Get-Command kimi -All | Format-List Source,Version
}

$candidatePaths = New-Object System.Collections.Generic.List[string]
try {
    where.exe kimi 2>$null | ForEach-Object { if ($_ -and -not $candidatePaths.Contains($_)) { $candidatePaths.Add($_) } }
} catch {}
try {
    Get-Command kimi -All -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Source -and -not $candidatePaths.Contains($_.Source)) { $candidatePaths.Add($_.Source) }
    }
} catch {}

$knownDirs = @(
    (Join-Path $env:USERPROFILE ".kimi"),
    (Join-Path $env:USERPROFILE ".config\kimi"),
    (Join-Path $env:USERPROFILE ".config\kimi-code"),
    (Join-Path $env:APPDATA "kimi"),
    (Join-Path $env:APPDATA "Kimi"),
    (Join-Path $env:APPDATA "kimi-code"),
    (Join-Path $env:APPDATA "Kimi Code"),
    (Join-Path $env:LOCALAPPDATA "kimi"),
    (Join-Path $env:LOCALAPPDATA "Kimi"),
    (Join-Path $env:LOCALAPPDATA "kimi-code"),
    (Join-Path $env:LOCALAPPDATA "Kimi Code")
)

Add-Line ""
Add-Line "## 本次清理对象"
foreach ($path in $candidatePaths) { Add-Line ("- Kimi 命令文件：``{0}``" -f $path) }
foreach ($path in $knownDirs) { Add-Line ("- Kimi 配置或缓存目录：``{0}``" -f $path) }

Add-Line ""
Add-Line "## 执行清理"
foreach ($path in $candidatePaths) { Remove-PathSafely -Path $path }
foreach ($path in $knownDirs) { Remove-PathSafely -Path $path }

Add-Command "清理后 Kimi 命令位置" {
    where.exe kimi
    Get-Command kimi -All | Format-List Source,Version
}

Add-Line ""
Add-Line "## 下载和解压 Release"
Add-Line ("- zip：``{0}``" -f $zipPath)
Add-Line ("- 解压目录：``{0}``" -f $extractRoot)
try {
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null
        if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
        if (Test-Path -LiteralPath $extractRoot) { Remove-Item -LiteralPath $extractRoot -Recurse -Force }
        Invoke-WebRequest -Uri $releaseUrl -OutFile $zipPath
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force
    }
    Add-Line "- 下载解压结果：完成"
} catch {
    Add-Line "- 下载解压结果：失败：$($_.Exception.Message)"
}

$installPath = Join-Path $packageRoot "install.ps1"
Add-Command "安装脚本验收" {
    if (Test-Path -LiteralPath $installPath) {
        Push-Location $packageRoot
        try {
            powershell -NoProfile -ExecutionPolicy Bypass -File $installPath
        } finally {
            Pop-Location
        }
    } else {
        "找不到 install.ps1：$installPath"
    }
}

$configPath = Join-Path $RepoRoot "config\autovmware-macos-vmx-clone.json"
$cliPath = Join-Path $packageRoot "skills\autovmware-macos-vmx-clone\scripts\cli.py"
Add-Command "技能 doctor 验收" {
    if (Test-Path -LiteralPath $cliPath) {
        python $cliPath doctor --config $configPath --format markdown
    } else {
        "找不到 cli.py：$cliPath"
    }
}

$readmePath = Join-Path $packageRoot "README.md"
Add-Command "README 标题验收" {
    if (Test-Path -LiteralPath $readmePath) {
        Select-String -LiteralPath $readmePath -Pattern '^#|^## ' | Select-Object -First 20
    } else {
        "找不到 README.md：$readmePath"
    }
}

Add-Command "验收后 Kimi 命令位置" {
    where.exe kimi
    Get-Command kimi -All | Format-List Source,Version
}

Add-Line ""
Add-Line "## 结论占位"
Add-Line "- 安装是否通过：请查看上面的安装脚本验收输出。"
Add-Line "- doctor 是否通过：请查看上面的技能 doctor 验收输出。"
Add-Line "- 禁止动作：脚本未包含任何 VM clone/start/stop/delete/snapshot/cleanup/power on 命令。"
Add-Line ("- 报告路径：``{0}``" -f $reportPath)

Write-Host "验收完成。报告路径：$reportPath"
