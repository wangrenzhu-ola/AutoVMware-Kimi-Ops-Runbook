# DEM-009 首轮批量克隆实证报告

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

## 耗时估算

本轮没有采集可靠的开始时间、结束时间和每台克隆耗时，所以不能写成实测耗时。按这次产物大小和 VMware full clone 的常见表现，给运维的排期预估如下：

| 批量规模 | 预估耗时 |
|---|---:|
| 5 台 | `45 到 90 分钟` |
| 10 台 | `1.5 到 3 小时` |
| 50 台 | `8 到 15 小时` |
| 100 台 | `16 到 30 小时` |

这个预估包含磁盘复制、VMX 改写、基础验证和截图采集时间，不包含人工等待确认、排队等待、失败重试和删除清理。后续报告必须补充真实开始时间、结束时间、总耗时和每台耗时。

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
