---
name: "autovmware-macos-vmx-clone"
description: "用于 Windows AutoVMware 主机上的 macOS VMware VMX 克隆工作。先检查、再生成计划、再等人工确认。没有明确授权时不能执行真实虚拟机动作。"
version: "0.2.1"
metadata:
  hermes:
    tags: [autovmware, vmware, macos, dem009, safety]
---

# AutoVMware macOS VMX 克隆

这个技能给运维使用。原则很简单：先检查环境，再生成计划，再让人确认。没有确认，不做真实克隆。

命令示例：

```bash
python scripts/cli.py doctor --format markdown
python scripts/cli.py generate-approval 5 --output config/autovmware-macos-vmx-clone.approval.json
python scripts/cli.py discover --drive F --format markdown
python scripts/cli.py validate-approval --approval-json approval.json
python scripts/cli.py plan-clone --approval-json approval.json --format markdown
python scripts/cli.py report-template --approval-json approval.json --output reports/dem009/clone-report.md
```

### 默认测试配置

默认配置在 `config/defaults.json`：

- 源 VMX：`F:\15.7.5\W1-OC-Mac-15.7.5\macOS 15\macOS 15.vmx`
- 输出目录：`F:\VMs`
- 名称前缀：`dem009-batch`
- 内存：`8GB`
- 磁盘：`64GB`
- 克隆方式：`full`
- 自动开机：`false`
- 网络：`nat`
- 保留策略：`keep`

如果运维只输入一个数字，比如 `5`，就理解成“按默认配置克隆 5 个”。但仍然必须先生成审批文件和计划，列出完整参数，等人明确确认后才能执行真实克隆。

### 自然语言配置

如果运维说“帮我配置 VMware 克隆参数”，先问清楚：

1. 源 `.vmx` 路径。
2. 输出目录。
3. 名称前缀。
4. 内存。
5. 磁盘。
6. 克隆方式。
7. 网络。
8. 是否允许自动开机。
9. 保留策略。

写配置前先复述，等确认。写完配置后运行 `doctor`，把结果发给运维确认。不要克隆。

### 硬性规则

- 不读取或输出 `.env` 内容。
- 不运行测试、服务启动脚本或 `scripts\deploy\start_all.ps1`。
- 没有人明确授权时，不创建、启动、停止、删除、快照、清理、克隆任何虚拟机。
- discovery 和 doctor 只能只读。
- `clone_count` 只能是 1 到 5。
- `power_on` 必须明确写出，默认不开机。
- 命令返回非 0 或 `E_*` 错误时，立刻停止并汇报。
- `doctor`、`discover`、`generate-approval`、`validate-approval`、`plan-clone`、`report-template` 都不能执行真实虚拟机动作。

### 审批文件

真实克隆前，审批文件必须包含所有字段：

```json
{
  "source_vmx": "F:\\15.7.5\\W1-OC-Mac-15.7.5\\macOS 15\\macOS 15.vmx",
  "clone_count": 5,
  "target_root": "F:\\VMs",
  "name_prefix": "dem009-batch",
  "memory_gb": 8,
  "disk_gb": 64,
  "clone_mode": "full",
  "power_on": false,
  "network": "nat",
  "retention_policy": "keep",
  "approved_action": "clone",
  "approved_by": "human",
  "approval_note": "运维已确认源镜像、目标目录、数量和是否开机。"
}
```

### 标准流程

1. 先运行 `doctor`。
2. 如果运维输入 `5`，运行 `generate-approval 5`、`validate-approval`、`plan-clone`。
3. 把完整计划发给运维确认。
4. 只有运维明确确认后，才调用项目内已经批准的克隆工具。
5. 保存截图和报告。

### 报告证据

阶段报告要包含源 VMX、克隆数量、目标路径、创建前后剩余空间、每个克隆机的验证结果、是否开机、截图路径、是否触发禁止动作、清理结果和重跑结果。

## setup

用于自然语言配置默认克隆参数。只允许改配置和运行 doctor，不允许执行真实虚拟机动作。

## clone

用于按数量生成默认克隆计划。比如运维输入 `5`，先生成审批文件、校验、生成计划并展示完整参数。必须等人确认后才能真实克隆。

## discover

只读发现。搜索可能的 macOS `.vmx`，查看磁盘空间，查看 AutoVMware 里是否有克隆工具。不修改文件，不执行虚拟机动作。

## validate-approval

检查审批文件字段是否齐全、数量是否合法、路径是否安全、是否明确写出开机策略、内存和磁盘是否达标。不执行虚拟机动作。

## plan-clone

根据审批文件生成确定的克隆计划，列出每个目标 `.vmx` 路径和磁盘预算。不执行虚拟机动作。

## generate-approval

根据默认配置和克隆数量生成审批文件。比如输入 `5`，生成 5 个克隆的审批文件。不执行虚拟机动作。

## doctor

只读检查环境：配置是否能读、路径是否合法、Windows 上源 `.vmx` 是否存在、目标盘空间是否够、VMware CLI 是否存在、Kimi CLI 是否存在。不读取 `.env`，不执行虚拟机动作。

## report-template

生成阶段报告模板。报告里要补充截图路径、剩余空间、每个克隆机验证结果和禁止动作检查结果。
