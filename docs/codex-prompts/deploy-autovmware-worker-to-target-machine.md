# Codex Prompt: Deploy AutoVMware Worker to Target Machine

把下面整段提示词交给 Codex，让 Codex 连接一台目标 Windows 运维机器完成 AutoVMware Worker 部署、注册、heartbeat 验收。Codex 必须只做注册和只读检查，不要执行真实 clone。

---

你是 Codex，正在连接一台 Windows 目标机器，用于把这台机器注册到 AutoVMware Hermes Brain。

## 目标

在目标机器上部署/验证 AutoVMware Worker，使它能向 Brain 上报 heartbeat。完成后输出可审计验收结果。不要执行真实 clone、start、power on、delete、snapshot、cleanup。

## 已知 Brain 信息

- Brain API Base URL: `<BRAIN_API_BASE_URL>`，示例：`http://8.138.7.116:3104`
- Heartbeat endpoint: `POST <BRAIN_API_BASE_URL>/workers/heartbeat`
- 本机 machine_id: `<MACHINE_ID>`
- AutoVMware 默认目录：`C:\Users\<WindowsUser>\Documents\AutoVMware`

如果 `<BRAIN_API_BASE_URL>` 或 `<MACHINE_ID>` 未提供，先向用户要这两个值，不要猜。

## 安全边界

- 不要输出 token、密码、RustDesk 凭据、Feishu secret、`.env` 内容。
- 不要读取或打印 `.env`。
- 不要执行真实 VMware clone/start/stop/delete/snapshot/cleanup/power on。
- 如果看到验证码、账号安全验证、密码输入框或不确定 UI，停止并询问用户。
- 只允许执行只读环境检查、AutoVMware 安装目录检查、token present/missing 检查、doctor dry-run。

## 执行步骤

1. 确认机器身份和基础环境：

```powershell
$env:COMPUTERNAME
$env:USERNAME
$autoRoot = Join-Path $env:USERPROFILE "Documents\AutoVMware"
Test-Path $autoRoot
python --version
```

2. 如果 AutoVMware 目录不存在：
   - 查找用户给定的 Release zip 或解压目录。
   - 如果没有交付包，报告 `blocked: missing AutoVMware release package`，不要从未知 URL 下载。
   - 如果有交付包，运行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\install.ps1 -SkipKimiInstall
```

3. 只读验证 token/skill 状态：

```powershell
cd $autoRoot
python .\skills\autovmware-macos-vmx-clone\scripts\cli.py ops-status --format json
```

注意：输出中 token 只能是 `[redacted]` 或 missing/present 状态，不要输出真实值。

4. 运行 doctor，只读，不 clone：

```powershell
cd $autoRoot
python .\skills\autovmware-macos-vmx-clone\scripts\cli.py doctor --format json
```

5. 计算状态：

- 如果 AutoVMware 不存在：`blocked`
- 如果 token 缺失：`need_token`
- 如果磁盘不足：`low_disk`
- 如果 doctor 失败：`doctor_failed`
- 如果基础检查通过：`ready`

6. 向 Brain 注册 heartbeat。示例 PowerShell：

```powershell
$brain = "<BRAIN_API_BASE_URL>"
$machineId = "<MACHINE_ID>"
$autoRoot = Join-Path $env:USERPROFILE "Documents\AutoVMware"
$drive = Get-PSDrive -Name F -ErrorAction SilentlyContinue
$freeGb = if ($drive) { [Math]::Round($drive.Free / 1GB, 2) } else { 0 }

$body = @{
  machine_id = $machineId
  hostname = $env:COMPUTERNAME
  worker_version = "0.1.0"
  windows_user = $env:USERNAME
  autovmware_root = $autoRoot
  vmware_status = "unknown"
  python_status = "ok"
  kimi_token_present = $false
  free_space_gb = $freeGb
  current_state = "blocked"
  last_error = "replace with actual blocker or null"
  evidence_path = (Join-Path $autoRoot "reports\worker-register.md")
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Method Post -Uri "$brain/workers/heartbeat" -ContentType "application/json" -Body $body
```

请根据实际检查结果替换 `kimi_token_present`、`current_state`、`last_error`。如果能从 `ops-status` 安全读取 token_present，则使用该布尔值，但不要输出 token。

7. 写本机验收报告：

路径：`C:\Users\<WindowsUser>\Documents\AutoVMware\reports\worker-register.md`

报告包含：

- machine_id
- hostname
- windows_user
- AutoVMware path exists / missing
- python version
- ops-status summary，token 只写 present/missing/redacted
- doctor summary
- heartbeat POST response
- final state
- blockers / next action

## 验收输出

最后只输出以下摘要，不要输出任何 secret：

```text
AutoVMware Worker Registration Result
machine_id: <...>
hostname: <...>
state: ready|blocked|need_token|low_disk|doctor_failed
brain_heartbeat: accepted|failed
report_path: <local path>
blocked_reason: <if any>
real_vm_action_executed: false
secret_leak_check: pass
```

如果 heartbeat 失败，给出 HTTP 状态、错误类型和本机网络检查结果；不要继续执行 clone。
