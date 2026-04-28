# AutoVMware Kimi 运维交付包

这个交付包是给运维人员用的，不是开发仓库。运维不需要安装 git，不需要 clone 代码仓库，也不需要理解代码结构。默认流程只有三步：下载 Release 压缩包，解压，在 Windows 目标机运行 `install.ps1`。

## 先看效果

### DEM-009 首轮批量克隆实证报告

这份报告来自 DEM-009 首轮 macOS VMX 批量克隆实测。它的目的不是写方案，而是证明运维可以通过一句明确指令触发批量克隆流程，并得到可审计的路径、空间、截图和错误记录。

## 结论

- 已验证：一条指令可以让 Kimi 按固定参数发起 5 台 macOS VMware 克隆流程。
- 已验证：流程会记录源 VMX、目标目录、每台克隆机路径、F 盘空间变化、截图路径和禁止动作状态。
- 已验证：不授权开机时，流程不会执行 VM start 或 power on。
- 已暴露：首轮 5 台里，3 台完整完成，1 台不完整，1 台未形成完整产物。这个结果已经被报告记录，后续应继续优化克隆工具的稳定性。
- 运维使用方式：当前每批最多 100 台。执行前必须按数量检查磁盘空间，并额外预留 100GB。需要更多机器时，按批次重复执行，这样能保留审批、空间检查和删除边界。

## 源镜像

```text
F:\15.7.5\W1-OC-Mac-15.7.5\macOS 15\macOS 15.vmx
```

只读发现结果：

- 源 VMX 存在。
- 源目录大小约 `33.35 GB`。
- macOS 指示：`macos-15`。

## 克隆参数

| 项 | 值 |
|---|---|
| 克隆数量 | `5` |
| 输出目录 | `F:\VMs` |
| 名称前缀 | `dem009-batch` |
| 每台内存 | `8 GB` |
| 每台磁盘 | `64 GB` |
| 克隆方式 | `full` |
| 网络 | `nat` |
| 是否允许自动开机 | `false` |
| 保留策略 | `keep` |

## F 盘空间变化

| 阶段 | F 盘剩余空间 |
|---|---:|
| 创建前 | `483.06 GB` |
| 创建后 | `373.77 GB` |
| 消耗 | `109.29 GB` |

## 每台克隆结果

| 克隆机 | 目标 VMX | 结果 | 目录大小 | 截图路径 |
|---|---|---|---:|---|
| `dem009-batch-01` | `F:\VMs\dem009-batch-01\dem009-batch-01.vmx` | 完整完成，VMX 存在 | `33.49 GB` | `C:\Users\PC12\Documents\AutoVMware\reports\dem009\screenshots\dem009-batch-01_screenshot.png` |
| `dem009-batch-02` | `F:\VMs\dem009-batch-02\dem009-batch-02.vmx` | 完整完成，VMX 存在 | `33.49 GB` | `C:\Users\PC12\Documents\AutoVMware\reports\dem009\screenshots\dem009-batch-02_screenshot.png` |
| `dem009-batch-03` | `F:\VMs\dem009-batch-03\dem009-batch-03.vmx` | 完整完成，VMX 存在 | `33.19 GB` | `C:\Users\PC12\Documents\AutoVMware\reports\dem009\screenshots\dem009-batch-03_screenshot.png` |
| `dem009-batch-04` | `F:\VMs\dem009-batch-04\dem009-batch-04.vmx` | 不完整，VMX 存在但产物不完整 | `0.14 GB` | 无 |
| `dem009-batch-05` | `F:\VMs\dem009-batch-05\dem009-batch-05.vmx` | 未形成完整产物 | 未确认 | 无 |

## 是否执行过开机

没有。

首轮授权明确写了 `power_on=false`，实测过程没有授权、也没有执行 VM start 或 power on。

## 禁止动作记录

- 未读取或输出 `.env`。
- 未运行 `scripts\deploy\start_all.ps1`。
- 未进入 DEM-009 U3。
- 未授权开机，因此未执行开机。
- 克隆过程中曾出现重命名不完整目录的建议，但该动作没有被授权执行。
- 删除动作在后续对话中被打断，没有完成验证，因此不能声称已删除。

## 截图证据

首轮报告记录的截图路径如下：

```text
C:\Users\PC12\Documents\AutoVMware\reports\dem009\screenshots\dem009-batch-01_screenshot.png
C:\Users\PC12\Documents\AutoVMware\reports\dem009\screenshots\dem009-batch-02_screenshot.png
C:\Users\PC12\Documents\AutoVMware\reports\dem009\screenshots\dem009-batch-03_screenshot.png
```

这些截图保存在 Windows AutoVMware 目标机上，不在本交付仓库里。

## 下一步

1. 在运维机上先运行 `install.ps1`。
2. 让 Kimi 运行 doctor。
3. 用一句话发起批量计划，例如：“按默认配置克隆 100 个镜像，先检查空间，额外预留 100GB，再列计划，等我确认。”
4. Kimi 列出源 VMX、输出目录、目标路径、是否开机和空间预算。
5. 运维确认后再执行真实克隆。
6. 每批最多 100 台。要更多机器时按批次重复执行，并保留每批报告。

## 下载和安装

默认安装方式是下载 Release，不是 clone 仓库。

到 Release 页面下载最新的 `AutoVMware-Kimi-Ops-v*.zip`。Release 标题和说明是中文，附件文件名保留英文是为了避免 Windows 或浏览器下载时出现乱码。下载后在 Windows 目标机解压，然后在解压目录运行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\install.ps1
```

安装脚本会先检查环境。检查不通过时，脚本会直接停下，不会安装 Kimi，也不会写配置。

脚本会检查：

- 当前机器是不是 Windows。
- PowerShell 版本是否够用。
- `python` 是否可用。
- 交付包里的技能文件是否完整。
- 默认配置是否能读取。
- 源 VMX 是否存在。
- 目标盘是否存在、空间是否够。
- VMware Workstation 的 `vmrun` 和 `vmware-vdiskmanager` 是否能找到。

检查通过后，脚本才会：

- 安装或检查 Kimi CLI。
- 创建 `C:\Users\PC12\Documents\AutoVMware\config`。
- 创建 `C:\Users\PC12\Documents\AutoVMware\reports\dem009\screenshots`。
- 复制默认配置到 `C:\Users\PC12\Documents\AutoVMware\config\autovmware-macos-vmx-clone.json`。如果这个配置已经存在，不会覆盖。
- 打印下一步怎么和 Kimi 说。

如果只想检查和准备目录，不安装 Kimi CLI：

```powershell
.\install.ps1 -SkipKimiInstall
```

如果检查失败，先按提示修环境，再重新运行。只有负责人明确接受风险时才使用：

```powershell
.\install.ps1 -Force
```

## 默认测试配置

交付包内置当前测试环境参数：

| 项 | 默认值 |
|---|---|
| 源 VMX | `F:\15.7.5\W1-OC-Mac-15.7.5\macOS 15\macOS 15.vmx` |
| 克隆输出目录 | `F:\VMs` |
| 名称前缀 | `dem009-batch` |
| 内存 | `8GB` |
| 磁盘 | `64GB` |
| 克隆方式 | `full` |
| 是否自动开机 | `false`，默认不开机 |
| 网络 | `nat` |
| 保留策略 | `keep`，默认保留 |

可编辑配置位置：

```text
C:\Users\PC12\Documents\AutoVMware\config\autovmware-macos-vmx-clone.json
```

## 运维日常使用

进入 AutoVMware 目录，启动 Kimi：

```powershell
cd C:\Users\PC12\Documents\AutoVMware
kimi
```

先让 Kimi 检查环境：

```text
使用 autovmware-macos-vmx-clone 技能，先运行 doctor，只检查环境，不要克隆。
```

检查通过后，如果要按默认配置克隆 100 个镜像：

```text
使用 autovmware-macos-vmx-clone 技能，按默认配置克隆 100 个镜像。先检查空间，额外预留 100GB，再生成计划并把参数列出来，等我确认后再执行。
```

如果当前会话已经明确在这个技能里，也可以只输入：

```text
5
```

Kimi 必须把这个数字理解成“克隆数量是 5”，先生成计划、列出参数，不能直接开始真实克隆。

所有克隆相关操作都必须通过 Kimi 发起，不给运维直接手工跑脚本。原因是 Kimi 会先检查环境，发现路径、空间、VMware 工具或配置有问题时，可以继续追问运维并修正配置；手工跑命令容易跳过这些交互检查。

## 真实克隆前必须确认

Kimi 在执行真实克隆前，必须先列出这些内容：

- 源 VMX 路径。
- 克隆数量。
- 输出目录。
- 名称前缀。
- 每台虚拟机内存。
- 每台虚拟机磁盘。
- 克隆方式。
- 是否允许自动开机。
- 网络设置。
- 保留策略。
- 每个克隆机的目标目录和 `.vmx` 路径。

确认话术示例：

```text
确认执行本次克隆：源 VMX 是 F:\15.7.5\W1-OC-Mac-15.7.5\macOS 15\macOS 15.vmx，数量 100 个，输出目录 F:\VMs，名称前缀 dem009-batch，不自动开机，完整克隆，已确认空间预算包含 100GB 预留。
```

没有这句明确确认，Kimi 不允许执行真实克隆。

## 修改配置

如果要换源镜像、输出目录或参数，可以让 Kimi 用自然语言帮忙改配置：

```text
使用 autovmware-macos-vmx-clone 技能配置环境。源 VMX 改成 D:\Templates\macOS\macOS.vmx，输出目录改成 F:\VMs，默认一次最多克隆 100 个，内存 8GB，磁盘 64GB，不自动开机，NAT 网络。只改配置并运行 doctor，不要克隆。
```

Kimi 应该只做三件事：

1. 复述配置。
2. 等运维确认后写配置。
3. 运行 doctor，并把检查结果发给运维确认。

doctor 没通过前，不允许克隆。

## 禁止事项

- 不读取或输出 `.env` 内容。
- 运维不直接手工执行克隆脚本，必须让 Kimi 通过技能执行。
- 不运行 `scripts\deploy\start_all.ps1`，除非负责人单独授权。
- 不进入 DEM-009 U3。
- 未经当前会话明确授权，不执行真实创建、启动、停止、删除、克隆或清理虚拟机。
- 删除克隆机前，必须再次列出精确目录并得到确认。
- 只允许删除本轮创建的克隆机，不允许删除源 VMX 或模板目录。
- 每次真实动作都必须写入报告。

## 报告必须包含

- 源 VMX。
- 克隆参数。
- 每个克隆机的目标路径。
- 每个克隆机的验证结果。
- 每个截图路径。
- 创建前后 F 盘剩余空间。
- 是否执行过开机。
- 错误、限制、下一步。
- 是否触发禁止动作。

## 出问题怎么办

先让 Kimi 检查环境：

```text
使用 autovmware-macos-vmx-clone 技能运行 doctor，只检查，不要克隆。
```

如果路径不确定、磁盘空间不足、工具行为不清楚、Kimi 输出被污染，立刻停止，不继续执行真实虚拟机动作。

## 维护者发布 Release

维护者在仓库根目录运行：

```powershell
.\scripts\release\build-release.ps1 -Version 0.1.1
```

然后把生成的 zip 上传到 GitHub Release。Release 标题和说明用中文写，运维只需要下载 zip，不需要 git。
