# Kimi 运维部署与 token 发放 SOP

本文给运维和 Infra/Hermes 使用，目标是让 AutoVMware Kimi 运维服务可安装、可验证、可安全发放 token，同时避免真实凭证进入仓库、Issue 或 CI 日志。

## 1. 适用范围

- 适用：AutoVMware Windows 目标机上的 Kimi 运维服务安装、token 申请、配置、smoke 验证、轮换和撤销。
- 不适用：在 CI 中执行真实 VMware 克隆、启动、停止、删除或读取真实 VMware 凭证。

## 2. 谁可以申请 token

申请人必须满足：

- 是授权运维或 Infra 指定执行人。
- 有明确机器、环境、用途和负责人。
- 已安装或准备安装 AutoVMware Kimi 运维交付包。
- 接受不得把 token 写入 GitHub、聊天记录、CI 日志或截图的安全要求。

## 3. 申请信息字段

向 Infra/Hermes 申请时，使用以下字段，不要附带任何已有 token：

```text
申请类型: AutoVMware Kimi ops token
机器标识: <主机名/资产编号>
环境: <prod/staging/test>
用途: <例如 DEM-009 批量克隆运维>
负责人: <姓名/飞书/微信>
预计有效期: <例如 30 天>
安装目录: <例如 C:\Users\PC12\Documents\AutoVMware>
是否真实 VMware 环境: <是/否>
备注: <授权范围、窗口期、回滚联系人>
```

## 4. Infra/Hermes 发放流程

1. 核对申请人、机器、用途和有效期。
2. 生成或分配最小权限 token。
3. 记录 token 元数据：申请人、机器、用途、有效期、发放时间、撤销方式。
4. 使用批准的私密通道传递 token；不要通过 GitHub Issue、PR、CI 变量输出、公开群或普通日志传递。
5. 告知运维只把 token 配到本机环境变量或批准的本地 secret store。

## 5. 运维配置流程

在 Windows 目标机安装：

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\install.ps1 -SkipKimiInstall
```

安装后查看示例：

```powershell
Get-Content C:\Users\PC12\Documents\AutoVMware\config\kimi-ops.env.example
```

配置真实 token 时，推荐使用用户级环境变量，变量名默认是 `KIMI_API_KEY`：

```powershell
[Environment]::SetEnvironmentVariable("KIMI_API_KEY", "<issued-token>", "User")
```

注意：上面的 `<issued-token>` 只能在本机私密操作中替换，不能出现在 GitHub、聊天、截图或 CI 日志里。

## 6. 验证服务可用

真实机器上先查 Kimi ops 状态，不执行 VMware 动作：

```powershell
python .\skills\autovmware-macos-vmx-clone\scripts\cli.py ops-status --format json
```

预期：

- `skill_available` 为 `true`
- `token_present` 为 `true`
- `token_value` 只显示 `[redacted]`
- `real_vm_action_executed` 为 `false`
- `vmware_touched` 为 `false`

然后运行 doctor：

```powershell
python .\skills\autovmware-macos-vmx-clone\scripts\cli.py doctor --format markdown
```

只有 doctor 通过并且运维明确确认计划后，才能进入真实克隆。

## 7. CI / mock 模式

GitHub Windows CI 只能使用 dummy token，不触碰真实 VMware：

```powershell
.\install.ps1 -RepoRoot "$env:RUNNER_TEMP\AutoVMware" -MockMode -SkipKimiInstall -DummyKimiToken "dummy-ci-token-not-real"
python .\skills\autovmware-macos-vmx-clone\scripts\cli.py ops-status --mock-token --format json
```

CI 需要验证：

- Windows runner checkout 成功。
- Python / pytest 可用。
- 安装脚本在 `-MockMode` 下完成目录和模板生成。
- dummy token 只以 redacted 状态出现。
- `ops-status` 可查询到技能可用。
- 没有真实 VMware 动作。

## 8. 轮换和撤销

轮换：

1. Infra/Hermes 生成新 token。
2. 运维在本机替换 `KIMI_API_KEY`。
3. 运行 `ops-status` 和 doctor。
4. Infra/Hermes 撤销旧 token。
5. 记录轮换时间、执行人和验证结果。

撤销：

1. Infra/Hermes 将 token 设为失效。
2. 运维删除本机环境变量：

```powershell
[Environment]::SetEnvironmentVariable("KIMI_API_KEY", $null, "User")
```

3. 运行 `ops-status`，确认 `token_present=false` 或服务不可继续使用。
4. 在交付记录里只写 token 元数据，不写 token 值。

## 9. 禁止事项

- 禁止把真实 token 写进仓库、Issue、PR、CI secret 输出、日志或截图。
- 禁止 CI 连接真实 VMware 或执行真实 VM 操作。
- 禁止脚本打印 token 明文；状态里只能显示 `[redacted]` / `[missing]`。
- 禁止把 token 固化到 `install.ps1`、配置模板或技能脚本里。
