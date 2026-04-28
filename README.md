# AutoVMware Kimi 运维交付包

这个交付包是给运维人员用的，不是开发仓库。运维不需要安装 git，不需要 clone 代码仓库，也不需要理解代码结构。默认流程只有三步：下载 Release 压缩包，解压，在 Windows 目标机运行 `install.ps1`。

## 先看效果

### 首轮批量克隆测试摘要

一句话指令即可发起批量克隆流程。首轮实测用 Kimi 发起 5 台 macOS VMware 克隆，流程记录了源 VMX、克隆参数、目标路径、F 盘空间变化、截图路径和禁止动作状态。

| 项 | 记录 |
|---|---|
| 源 VMX | `F:\15.7.5\W1-OC-Mac-15.7.5\macOS 15\macOS 15.vmx` |
| 克隆数量 | `5` |
| 输出目录 | `F:\VMs` |
| 名称前缀 | `dem009-batch` |
| 内存 | `8 GB` |
| 磁盘 | `64 GB` |
| 克隆方式 | `full` |
| 网络 | `nat` |
| 是否允许自动开机 | `false` |
| F 盘创建前 | `483.06 GB` |
| F 盘创建后 | `373.77 GB` |
| 空间消耗 | `109.29 GB` |

| 克隆机 | 结果 | 截图 |
|---|---|---|
| `dem009-batch-01` | 完整完成，VMX 存在，约 `33.49 GB` | `reports\dem009\screenshots\dem009-batch-01_screenshot.png` |
| `dem009-batch-02` | 完整完成，VMX 存在，约 `33.49 GB` | `reports\dem009\screenshots\dem009-batch-02_screenshot.png` |
| `dem009-batch-03` | 完整完成，VMX 存在，约 `33.19 GB` | `reports\dem009\screenshots\dem009-batch-03_screenshot.png` |
| `dem009-batch-04` | 不完整，VMX 存在但产物不完整，约 `0.14 GB` | 无 |
| `dem009-batch-05` | 未形成完整产物 | 无 |

本轮没有执行开机，也没有授权 VM start 或 power on。未读取 `.env`，未运行 `scripts\deploy\start_all.ps1`，未进入 DEM-009 U3。

耗时统计：本轮没有采集可靠的开始时间、结束时间和每台克隆耗时，所以不能写成实测耗时。按这次产物大小和 VMware full clone 的常见表现，给运维的排期预估如下：

| 批量规模 | 预估耗时 |
|---|---:|
| 5 台 | `45 到 90 分钟` |
| 10 台 | `1.5 到 3 小时` |
| 50 台 | `8 到 15 小时` |
| 100 台 | `16 到 30 小时` |

这个预估包含磁盘复制、VMX 改写、基础验证和截图采集时间，不包含人工等待确认、排队等待、失败重试和删除清理。后续 Kimi 执行时需要在报告里补充：批次开始时间、批次结束时间、总耗时、每台开始/结束/耗时、失败或重试耗时。

当前交付包已把单批上限改为 100 台。执行前必须按数量检查磁盘空间，并额外预留 100GB。更多细节仍保留在 `docs\reports\dem009\first-batch-clone-evidence.md`。

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
