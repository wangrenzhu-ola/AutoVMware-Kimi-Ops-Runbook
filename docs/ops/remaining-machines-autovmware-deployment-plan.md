# 剩余机器 AutoVMware 部署计划

本文用于把 rustDesk12 已验证的 AutoVMware 运维交付方式复制到剩余 Windows 机器。目标不是一次性远程硬跑所有真实克隆，而是按机器逐台完成安装和可用性验收，再按批次执行真实 VMware clone。

当前状态：

- rustDesk12 已远程部署 AutoVMware。
- 首轮 DEM-009 克隆实测已经证明 Kimi 可以发起批量 clone，并能产出路径、空间、截图和禁止动作记录。
- 首轮 5 台 clone 中，3 台完整完成，1 台不完整，1 台未形成完整产物。因此后续推广必须把“AutoVMware 安装成功”和“真实 clone 稳定完成”分成两个验收门。
- 飞书机器清单已通过本机登录态读取。清单包含 RustDesk ID 和连接凭据；本文只记录机器编号和批次，不把远程连接凭据复制进仓库。

## 机器清单字段

每台机器进入部署批次前，必须补齐这些字段：

| 字段 | 示例 | 必填原因 |
|---|---|---|
| 机器编号 | `rustDesk12` | 批次追踪和报告命名 |
| RustDesk ID | `<id>` | 远程连接入口 |
| Windows 用户 | `PC12` | 默认安装路径依赖用户目录 |
| 安装目录 | `C:\Users\PC12\Documents\AutoVMware` | 安装和 Kimi 工作目录 |
| 源 VMX | `F:\15.7.5\W1-OC-Mac-15.7.5\macOS 15\macOS 15.vmx` | clone 输入 |
| 输出目录 | `F:\VMs` | clone 输出 |
| F 盘剩余空间 | `<gb>` | 计算可 clone 数量 |
| VMware Workstation | `installed / missing` | 需要 `vmrun` 和 `vmware-vdiskmanager` |
| Python | `installed / missing` | 运行技能 CLI |
| Kimi CLI | `installed / missing` | 运维交互入口 |
| Kimi token | `present / missing` | 只记录状态，不记录 token |
| 目标 clone 数 | `<n>` | 每批最多 100 |
| 是否允许开机 | `false` | 默认不自动开机 |
| 负责人 | `<name>` | 授权和回滚联系人 |

## 分批策略

飞书清单当前共 30 台：

```text
PC6, PC7, PC10, PC12, PC13,
TC1, TC2,
JL1, JL2, JL3, JL4, JL5, JL6, JL7,
XY2, XY3, XY4,
XR1, XR2, XR3, XR4, XR5,
XT1, XT2, XT3,
YR1, YR2, YR3, YR4, YR5
```

已完成远程部署的机器：

```text
PC12 / rustDesk12
```

剩余 29 台按机房/分组推进：

| 批次 | 机器 | 目的 |
|---|---|---|
| Wave 0 | `PC13` | 与 PC12 同组，作为复制部署的第一台对照机 |
| Wave 1 | `PC6`, `PC7`, `PC10` | PC 组补齐，验证不同分组的基础环境差异 |
| Wave 2 | `TC1`, `TC2` | TC 组小批验证 |
| Wave 3 | `JL1`, `JL2`, `JL3`, `JL4`, `JL5`, `JL6`, `JL7` | 金鳞 JL 组批量推广 |
| Wave 4 | `XY2`, `XY3`, `XY4`, `XR1`, `XR2`, `XR3`, `XR4`, `XR5`, `XT1`, `XT2`, `XT3` | 祥云组批量推广 |
| Wave 5 | `YR1`, `YR2`, `YR3`, `YR4`, `YR5` | 焰燃组收尾 |

每个 wave 内先挑 1 台做完整安装和 doctor；通过后再推进该 wave 剩余机器。不要在同一时间对多个未验证分组执行真实 clone。

1. 先做只读盘点批次。
   - 目标：确认每台机器能远程连接、路径存在、磁盘空间足够、VMware 和 Python 可用。
   - 不安装新软件，不运行真实 clone，不读取 `.env`。

2. 再做安装批次。
   - 目标：在每台机器解压交付包并运行 `install.ps1`。
   - 如果机器缺 Kimi CLI，安装脚本可能安装 Kimi。通过 UI 安装或运行新下载软件时，需要在动作发生前再次确认。

3. 然后做 Kimi/token 批次。
   - 目标：按 `docs/ops/kimi-token-sop.md` 配置 `KIMI_API_KEY` 并验证 `ops-status`。
   - 不在聊天、截图、日志或 Issue 中出现真实 token。

4. 再做 doctor 验收批次。
   - 目标：每台机器运行 doctor，只读确认配置、源 VMX、目标盘空间、VMware CLI、Kimi CLI。
   - doctor 未通过的机器进入修复队列，不进入 clone 阶段。

5. 最后做真实 clone 批次。
   - 目标：每台机器按明确数量生成 plan，人工确认后执行真实 clone。
   - 每批最多 100 台。
   - 空间预算按 `clone_count * disk_gb + 100GB reserve` 检查。
   - 默认 `power_on=false`，不自动开机。

## 单机执行流程

### 0. 连接确认

通过 RustDesk 连接目标机器，确认桌面可操作、PowerShell 可打开、目标用户目录存在。

只读命令：

```powershell
$env:USERNAME
Test-Path C:\Users\$env:USERNAME\Documents
Get-PSDrive
```

### 1. 交付包准备

默认方式是使用 Release zip，不要求目标机安装 git。把交付包放到目标机后，在解压目录运行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\install.ps1 -SkipKimiInstall
```

如果允许安装或检查 Kimi CLI，则运行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\install.ps1
```

验收标准：

- `C:\Users\<user>\Documents\AutoVMware` 存在。
- `config\autovmware-macos-vmx-clone.json` 存在。
- `reports\dem009\screenshots` 存在。
- `config\kimi-token-status.json` 只包含 `[redacted]` 或 `[missing]`。

### 2. token 配置

按 SOP 向 Infra/Hermes 申请 token，只在目标 Windows 机器本地配置：

```powershell
[Environment]::SetEnvironmentVariable("KIMI_API_KEY", "<issued-token>", "User")
```

禁止把真实 token 粘贴到聊天、GitHub、CI 日志、截图或报告里。

验收命令：

```powershell
cd C:\Users\<user>\Documents\AutoVMware
python .\skills\autovmware-macos-vmx-clone\scripts\cli.py ops-status --format json
```

验收标准：

- `skill_available=true`
- `token_present=true`
- `token_value="[redacted]"`
- `real_vm_action_executed=false`
- `vmware_touched=false`

### 3. doctor 验收

```powershell
cd C:\Users\<user>\Documents\AutoVMware
python .\skills\autovmware-macos-vmx-clone\scripts\cli.py doctor --format markdown
```

验收标准：

- 源 VMX 存在。
- 输出盘存在。
- 剩余空间至少满足 1 台 clone 加 100GB 预留。
- `vmrun` 可找到。
- `vmware-vdiskmanager` 可找到。
- Kimi CLI 可用。

doctor 未通过时，停止在本机继续推进真实 clone，并记录失败项。

### 4. 生成 clone 计划

对通过 doctor 的机器，让 Kimi 生成计划但不要执行：

```text
使用 autovmware-macos-vmx-clone 技能，按默认配置克隆 <N> 个镜像。先检查空间，额外预留 100GB，再列出源 VMX、输出目录、名称前缀、每台内存、每台磁盘、是否开机、每个目标路径，等我确认后再执行。
```

验收标准：

- `clone_count` 在 1 到 100。
- `source_vmx`、`target_root`、`name_prefix`、`memory_gb`、`disk_gb`、`clone_mode`、`power_on`、`network`、`retention_policy` 全部列出。
- `power_on=false`，除非本轮明确授权开机。
- 每个目标 `.vmx` 路径可审计。
- 空间预算包含 100GB 预留。

### 5. 真实 clone 授权

真实 clone 前必须由负责人确认完整参数。确认话术：

```text
确认执行本次克隆：机器是 <machine_id>，源 VMX 是 <source_vmx>，数量 <N> 个，输出目录 <target_root>，名称前缀 <name_prefix>，每台内存 <memory_gb>GB，每台磁盘 <disk_gb>GB，clone_mode=<clone_mode>，network=<network>，power_on=false，保留策略 <retention_policy>，已确认空间预算包含 100GB 预留。
```

没有这句确认，不执行真实 clone。

### 6. clone 后验收

每台 clone 必须记录：

- 目标目录。
- 目标 `.vmx`。
- 目录大小。
- 是否完整。
- 是否截图。
- 截图路径。
- 是否开机。
- 是否触发禁止动作。
- 创建前后目标盘剩余空间。
- 批次开始时间、结束时间、总耗时。

通过标准：

- 每个目标 `.vmx` 存在。
- 目录大小合理，不出现明显不完整产物。
- 报告生成。
- 截图路径可追溯。
- 没有读取 `.env`。
- 没有运行 `scripts\deploy\start_all.ps1`。
- 没有未经授权 start / power on / delete / snapshot / cleanup。

## 批次推进规则

每台机器状态只能在这些状态中流转：

| 状态 | 进入条件 | 下一步 |
|---|---|---|
| `inventory_pending` | 只知道机器在清单里 | 补齐机器字段 |
| `remote_ok` | RustDesk 可连接 | 安装交付包 |
| `installed` | `install.ps1` 通过 | 配 token |
| `token_ok` | `ops-status` 通过 | 运行 doctor |
| `doctor_ok` | doctor 通过 | 生成 clone 计划 |
| `plan_ready` | Kimi 列出完整计划 | 等授权 |
| `clone_running` | 已授权真实 clone | 监控执行 |
| `clone_done` | 报告和截图完整 | 归档 |
| `blocked` | 任一门禁失败 | 修复后回到对应状态 |

不要跳过状态。尤其不能从 `installed` 直接进入真实 clone。

## 风险和回滚

- 如果安装失败：不要用 `-Force` 继续，除非负责人明确接受 blocker。
- 如果 token 缺失：只跑 mock 或只读检查，不进入真实 clone。
- 如果 doctor 失败：修复环境，不 clone。
- 如果 clone 中出现不完整目录：停止扩大批次，先记录目标路径、目录大小和错误输出。
- 如果需要删除不完整 clone：必须先列出精确目录，并得到删除授权；只能删除本轮创建的 clone，不能删除源 VMX 或模板目录。
- 如果发生未授权开机、删除、快照、清理：立即停止该机器操作，记录时间、动作、目标路径和可见证据。

## 需要补齐的下一步输入

请从飞书机器清单或远程机器只读检查中补齐以下内容。RustDesk ID 和密码继续保留在飞书，不落入仓库：

```text
machine_id:
rustdesk_id:
windows_user:
source_vmx:
target_root:
free_space_gb:
target_clone_count:
owner:
notes:
```

拿到清单后，按 `doctor_ok` 优先级排序：

1. 先部署磁盘空间最大、源 VMX 已存在、VMware 工具完整的机器。
2. 每台先做 1 到 3 个 clone 的小批验证。
3. 小批完整后再扩大到 10、50、100。
4. 出现不完整产物时停止扩大，先修工具稳定性。
