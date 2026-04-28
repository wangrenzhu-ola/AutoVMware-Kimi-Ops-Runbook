# AutoVMware macOS VMX Clone Runbook

本仓库当前交付目标是把 `autovmware-macos-vmx-clone` 技能部署给运维人员使用。部署成功后，运维可以在 Windows AutoVMware 仓库里直接和 Kimi 说话，但必须让 Kimi 使用固定技能和默认配置，不要随口执行 VMware 命令。

## 下载 Release 后一键初始化

运维人员不需要安装 git。进入 GitHub Release 页面，下载 `autovmware-kimi-ops-runbook-v*.zip`，在 Windows 目标机解压后运行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\install.ps1
```

脚本会做这些事：

- 先运行 install doctor。检查不通过时不会执行安装或写配置。
- 检查 Windows、PowerShell、`python`、技能文件、默认配置、源 VMX、目标盘、目标盘空间、`vmrun`、`vmware-vdiskmanager`。
- doctor 通过后，如本机没有 `kimi` 命令，使用 Kimi Code 官方安装脚本安装 Kimi CLI。
- 创建 `C:\Users\PC12\Documents\AutoVMware\config` 和 `reports\dem009\screenshots`。
- 复制默认配置到 `C:\Users\PC12\Documents\AutoVMware\config\autovmware-macos-vmx-clone.json`，如果目标配置已存在则不覆盖。
- 在脚本末尾打印后续 Kimi 使用命令。

如果只想准备目录、不安装 Kimi CLI：

```powershell
.\install.ps1 -SkipKimiInstall
```

如果 doctor 报出阻断项，先修复后重跑。只有运维明确接受阻断项时才使用：

```powershell
.\install.ps1 -Force
```

## 默认测试配置

技能内置当前 DEM-009 测试环境参数：

| 字段 | 默认值 |
|------|--------|
| `source_vmx` | `F:\15.7.5\W1-OC-Mac-15.7.5\macOS 15\macOS 15.vmx` |
| `target_root` | `F:\VMs` |
| `name_prefix` | `dem009-batch` |
| `memory_gb` | `8` |
| `disk_gb` | `64` |
| `clone_mode` | `full` |
| `power_on` | `false` |
| `network` | `nat` |
| `retention_policy` | `keep` |

配置文件位置：

```text
skills/autovmware-macos-vmx-clone/config/defaults.json
```

部署到 Windows AutoVMware 后，建议使用这份可编辑配置：

```text
C:\Users\PC12\Documents\AutoVMware\config\autovmware-macos-vmx-clone.json
```

## 运维怎么使用

进入 Windows AutoVMware 仓库：

```powershell
cd C:\Users\PC12\Documents\AutoVMware
kimi
```

先做只读体检：

```text
use autovmware-macos-vmx-clone doctor
```

如果 doctor 通过，按默认配置克隆 5 个镜像：

```text
use autovmware-macos-vmx-clone clone 5
```

也可以直接输入：

```text
5
```

但前提是当前 Kimi 会话已经明确处在 `autovmware-macos-vmx-clone` 技能上下文中。Kimi 应把单个数字解释为 `clone_count`，先生成 approval 和 plan，回显完整参数，再等待人工确认真实 clone。

## Kimi 必须回显的参数

真实克隆前，Kimi 必须展示这些字段并等待确认：

- `source_vmx`
- `clone_count`
- `target_root`
- `name_prefix`
- `memory_gb`
- `disk_gb`
- `clone_mode`
- `power_on`
- `network`
- `retention_policy`
- 每个 clone 的目标目录和 `.vmx` 路径

运维确认示例：

```text
确认执行本次 clone：source_vmx=F:\15.7.5\W1-OC-Mac-15.7.5\macOS 15\macOS 15.vmx, clone_count=5, target_root=F:\VMs, name_prefix=dem009-batch, power_on=false, clone_mode=full。
```

## Doctor 检查

Release 初始化脚本内置 install doctor，技能本身也提供只读 doctor：

```powershell
python skills\autovmware-macos-vmx-clone\scripts\cli.py doctor --format markdown
```

doctor 检查：

- 配置文件是否存在、能否解析。
- `source_vmx` 是否是 Windows 绝对 `.vmx` 路径。
- 在 Windows 上确认源 `.vmx` 是否存在。
- 目标盘剩余空间是否满足预算。
- VMware Workstation CLI：`vmrun`、`vmware-vdiskmanager`。
- Kimi CLI：`kimi`。
- 是否触发禁止动作。

doctor 不会创建、启动、停止、删除、注册、克隆任何 VM。

## 配置方式

如果要换镜像或换目录，让 Kimi 帮运维自然语言配置即可：

```text
use autovmware-macos-vmx-clone setup
我要把源 VMX 改成 D:\Templates\macOS\macOS.vmx，目标目录改成 F:\VMs，默认一次克隆 5 个，内存 8GB，磁盘 64GB，不自动开机，NAT 网络。
```

Kimi 应该只更新配置并运行 doctor。配置完成后，把配置摘要和 doctor 结果发给运维人工校验。doctor 没通过前，不允许执行 clone。

## 脚本命令

从默认配置生成 approval：

```powershell
python skills\autovmware-macos-vmx-clone\scripts\cli.py generate-approval 5 --output config\autovmware-macos-vmx-clone.approval.json
```

校验 approval：

```powershell
python skills\autovmware-macos-vmx-clone\scripts\cli.py validate-approval --approval-json config\autovmware-macos-vmx-clone.approval.json
```

生成非破坏性计划：

```powershell
python skills\autovmware-macos-vmx-clone\scripts\cli.py plan-clone --approval-json config\autovmware-macos-vmx-clone.approval.json --format markdown
```

生成报告模板：

```powershell
python skills\autovmware-macos-vmx-clone\scripts\cli.py report-template --approval-json config\autovmware-macos-vmx-clone.approval.json --output reports\dem009\dem009_clone_phase_report.md
```

## 安全边界

- 不读取或输出 `.env` 内容。
- 不运行 `scripts\deploy\start_all.ps1`，除非单独授权。
- 不进入 DEM-009 U3。
- 未经当前会话明确授权，不执行真实 VM create/start/stop/delete/clone/cleanup。
- 删除 clone 前必须再次列出精确目标路径并获得确认。
- 只允许删除本轮创建的 clone 目录或注册项，不允许删除源 VMX 或模板目录。
- 每次真实 VM 动作都必须写入报告。

## 报告要求

阶段报告必须包含：

- 源 VMX。
- clone 参数。
- 每个 clone 的目标路径。
- 每个 clone 的验证结果。
- 每个 clone 的截图路径。
- F 盘创建前后空间。
- 是否执行过 VM start/power on。
- 错误、限制、下一步。
- 是否触发禁止动作。

## 故障处理

如果出问题，先让 Kimi 运行：

```text
use autovmware-macos-vmx-clone doctor
```

如果 doctor 失败，先修配置或 VMware/Kimi 安装，再重新 doctor。路径不确定、磁盘空间不足、工具行为不清楚、Kimi 输出污染时，立即停止并汇报，不继续执行真实 VM 动作。

## 维护者发布 Release

维护者在本仓库根目录运行：

```powershell
.\scripts\release\build-release.ps1 -Version 0.1.0
```

然后把 `dist\autovmware-kimi-ops-runbook-v0.1.0.zip` 上传到 GitHub Release。运维只需要下载这个 zip，不需要 git 环境。
