---
date: 2026-05-08
topic: autovmware-feishu-brain
focus: Feishu-operated central brain controlling every deployed AutoVMware computer
---

# Ideation: AutoVMware 飞书中枢大脑

## Codebase Context

本轮针对 `/Users/wangrenzhu/work/AutoVMware-Kimi-Ops-Runbook` 做了浅层扫描。仓库当前更像“AutoVMware + Kimi + PowerShell/Python 的 Windows 本地运维交付包”，而不是 fleet control plane。

项目形态：Python >=3.10 CLI/scripts、PowerShell install/bootstrap/acceptance/release scripts、pytest、YAML skill contract、JSON config。主要目录包括 `skills/autovmware-macos-vmx-clone`、`scripts/{acceptance,bootstrap,release}`、`docs/{ops,reports}`、`config`、`tests`。

现有强约束：`doctor/discover/generate-approval/validate/plan` 是只读；真实 clone 需要明确人工确认；clone count capped 1-100；磁盘预算需要 `clone_count * disk_gb + 100GB reserve`；默认 `power_on=false`；token 必须 redacted。

关键缺口：没有常驻 worker/daemon、machine registry、remote command bus、Feishu bot/webhook、queue、authz model、audit backend。默认配置仍偏 DEM-009/F:/PC12 场景。

历史学习：现有部署计划已经定义 Feishu 机器清单和状态门：`inventory_pending -> remote_ok -> installed -> token_ok -> doctor_ok -> plan_ready -> clone_running -> clone_done/blocked`。首批 Kimi 5 台 clone 只有 3 台完整、1 台 incomplete、1 台未完整形成，说明不能把“已安装 AutoVMware”当成“真实 clone 稳定”。RustDesk/GUI 远控被证明易受 PowerShell 特殊字符和 clipboard 影响，适合作为 bootstrap/rescue，不适合作为主命令平面。

## Ranked Ideas

### 1. Feishu 中枢大脑：消息先落 Task/Run，再路由到机器 worker

**Description:** 飞书不直接成为远程 shell，而是把用户意图编译成结构化 task/run：发起人、目标机器/机器组、动作、参数、风险等级、审批策略、过期时间。中央 brain 负责调度、状态门禁、审计和重试；每台 Windows AutoVMware worker 负责执行受控动作并回写结果。这样用户在飞书上操控的是一个生产控制面，而不是群聊机器人转发命令。

**Warrant:** `direct:` 仓库当前是本地 Kimi/PowerShell/Python safe local commands，明确缺少 daemon/registry/bus/bot/queue/authz/audit；用户目标是“能在飞书上操控一个大脑，控制每个部署了 AutoVMware 的电脑”。

**Rationale:** 这是从“单机 runbook”跃迁到“fleet brain”的核心抽象。只要 Task/Run 成立，审批、队列、证据、状态、并发、重试、权限都能围绕同一对象复用。

**Downsides:** 需要新增服务端控制面、数据模型、worker 协议和 Feishu bot；不是小修。

**Confidence:** 92%

**Complexity:** High

**Status:** Unexplored

### 2. 每台机器 worker heartbeat + 可调度性状态

**Description:** 每台部署 AutoVMware 的 Windows 机器运行轻量 worker，周期上报 `machine_id`、runner version、VMware/Python/Kimi 状态、token present/missing redacted、free space、当前任务、最近错误、last_heartbeat_at。中央 brain 只调度 heartbeat 新鲜、状态门满足、风险策略通过的机器。Feishu 里展示“哪些机器 ready、blocked、lost、需要人工救援”。

**Warrant:** `direct:` 现有计划已有 per-machine 字段和状态门；相邻经验明确建议 central scheduler + per-Windows worker；当前 repo 没有 agent daemon/registry/remote bus。

**Rationale:** fleet 控制的第一问题不是“能不能执行 clone”，而是“哪台机器现在可信、可用、可调度”。heartbeat 让电脑从黑盒远程桌面变成可观测 runtime。

**Downsides:** 需要处理 worker 安装、升级、掉线、版本兼容、安全鉴权。

**Confidence:** 90%

**Complexity:** Medium-High

**Status:** Unexplored

### 3. 把状态门升级为自动状态机，而不是人工 checklist

**Description:** 将 `inventory_pending -> remote_ok -> installed -> token_ok -> doctor_ok -> plan_ready -> clone_running -> clone_done/blocked` 变成严格状态机。每个状态定义进入条件、退出条件、超时、失败重试、需要人工确认的点、禁止跳转规则。Feishu 只展示“现在可做什么”和“为什么不能继续”，而不是让人读 runbook 判断下一步。

**Warrant:** `direct:` 部署计划已经定义完整状态门并明确不要跳过；首批 5 台只有 3 台完整，说明人工推进和稳定性门禁不足。

**Rationale:** 这能把安全 SOP 从文档转成系统行为，避免忙时跳步，也方便后续 wave rollout、失败暂停、自动恢复。

**Downsides:** 状态机设计需要覆盖异常路径；如果做得过重，初期会拖慢试验速度。

**Confidence:** 88%

**Complexity:** Medium

**Status:** Unexplored

### 4. Feishu 风险差异审批：确认授权对象，而不是确认聊天话术

**Description:** 真实 clone 前不再靠自然语言确认，而是生成带作用域的授权对象：`machine_id`、`clone_count`、`source_vmx`、`target_root`、`power_on`、磁盘 reserve、过期时间、审批人、审批来源。普通安全路径低摩擦确认；异常差异如 `power_on=true`、reserve 接近下限、目标路径非预期、clone count 高，审批卡突出风险差异。

**Warrant:** `direct:` 现有 skill/plan 要求真实 clone 前完整字段确认；当前安全规则包含 count cap、100GB reserve、默认 power_on=false、token redaction。

**Rationale:** 聊天确认在单机阶段可用，但 fleet 下容易出现确认对象不清、复制到错误机器、确认疲劳。授权对象能让 worker 和 brain 都能机器验证“这次是否被允许”。

**Downsides:** 需要接飞书审批/卡片能力和审批数据持久化；也需要定义哪些操作必须审批。

**Confidence:** 86%

**Complexity:** Medium

**Status:** Unexplored

### 5. 批次/Wave 调度器：自动 canary、暂停扩张、收口失败机器

**Description:** 中央 brain 按机器组和 batch 管理 rollout：每组先选一台 canary，完成 `clone_done` 且报告验证通过后，才允许扩展到 10/50/100。出现 incomplete clone、worker lost、磁盘不足或 forbidden-action 风险时自动暂停扩大，只允许诊断、清理、小批重试。Feishu 汇报不只显示“3/5 完成”，还自动给剩余机器的失败包和下一步建议。

**Warrant:** `direct:` 历史学习要求每组先验证一台再扩展；首批 5 台只有 3 台完整，1 incomplete，1 not fully formed；已有状态门和 per-machine 字段可作为调度输入。

**Rationale:** 这把首批失败暴露出的不稳定性转化为调度策略，避免 central brain 只是更快地把错误放大到所有电脑。

**Downsides:** 需要定义稳定性评分、暂停条件、恢复条件；短期会降低“看起来的速度”。

**Confidence:** 84%

**Complexity:** Medium

**Status:** Unexplored

### 6. Route evidence pack：每次 Feishu 指令自动生成验收证据包

**Description:** 每个 run 自动生成证据包：Feishu message id、task_id、run_id、选中的 runtime、worker PID/service status、端口/health、tools/capabilities、dry-run plan、tool call request/response 摘要、stdout/stderr/exit code、artifact/report 路径、audit log offset。Feishu 回复“完成”时同时给证据摘要和 report 链接/路径。

**Warrant:** `direct:` 用户验收严格要求真实黑盒留痕；gateway acceptance 需要 real Feishu send/receive、launchd/worker PID、route evidence；AutoVMware 报告已要求源 VMX、clone count、空间、截图、禁止动作、每机验证。

**Rationale:** 控制面能否被信任，取决于每次动作是否可追溯。证据包会把一次性操作沉淀为排障、审计、验收和知识复利资产。

**Downsides:** 日志量和隐私/redaction 复杂度上升；需要避免把证据系统做成泄密通道。

**Confidence:** 82%

**Complexity:** Medium

**Status:** Unexplored

### 7. Command manifest：把本地安全命令升级为远程可调度动作模板

**Description:** 为每个 AutoVMware 动作声明 manifest：`name`、`risk_level`、`required_capabilities`、`inputs_schema`、`dry_run_supported`、`approval_required`、`evidence_required`、`rollback/delete_strategy`。Feishu brain 只能调度 manifest 中声明过的动作；worker 只执行受控模板并返回结构化结果。

**Warrant:** `direct:` 当前仓库已有安全本地命令和 PowerShell/Python skill，但没有 fleet/control plane primitives；现有 schema/defaults 仍偏 DEM-009，容易把测试便利值当成控制面事实。

**Rationale:** manifest 是复利层：每新增一个动作，审批、审计、输入校验、证据包、测试都能自动继承，而不是为每个脚本重新写胶水。

**Downsides:** 初期需要梳理现有命令契约；过早抽象可能导致动作开发变慢。

**Confidence:** 78%

**Complexity:** Medium

**Status:** Unexplored

## Rejection Summary

| # | Idea | Reason Rejected |
|---|------|-----------------|
| 1 | 单纯做一个 Feishu bot 转发 CLI 命令 | 被更强的 Task/Run 控制面覆盖；直接转发会把聊天机器人做成脆弱远程 shell。 |
| 2 | 每台机器一张 Feishu 可执行体检卡 | 有价值但更像状态机/heartbeat 的 UI 表达，作为 survivor #2/#3 的 brainstorm variant 更合适。 |
| 3 | blocked 自动生成修复工单 | 有价值但被 route evidence pack + wave 收口失败包覆盖。 |
| 4 | 自动按机器准备度编队 | 被 wave 调度器覆盖；单独作为 idea 颗粒度偏窄。 |
| 5 | 操作者 timeline | 被 route evidence pack 覆盖；timeline 是证据包的展示层。 |
| 6 | 群聊降噪模式 | 必要但偏治理策略，不足以单独作为本轮核心产品改进；可纳入 Feishu gateway policy。 |
| 7 | RustDesk 降级为救援通道 | 重要判断，但更像架构原则，已并入 central brain + worker heartbeat 的 rationale。 |
| 8 | 敏感字段 redaction 管线 / credential lease | 必要安全基础，但当前 ideation 聚焦自动化控制面；可作为审批/证据包的硬约束。 |
| 9 | DEM-009 模板化为 scenario template | 方向正确但偏数据建模子问题；可并入 command manifest / inventory 设计。 |
| 10 | VMX/template registry | 有价值但更像后续 domain capability，优先级低于通用控制面、heartbeat、状态机。 |
| 11 | Feishu runbook memory | 符合复利，但当前更应先建立 run/evidence/audit 数据源；否则 memory 会缺乏稳定输入。 |
| 12 | WeChat break-glass 通道 | 符合既有治理，但不是 AutoVMware repo 自动化不足的核心解。 |

## Suggested Handoff

建议先进入 `gh:brainstorm` 深挖 Idea #1：`Feishu 中枢大脑：消息先落 Task/Run，再路由到机器 worker`。

原因：它会自然拆出最小 MVP 边界：Feishu intake、Task/Run schema、machine heartbeat、worker command runner、approval gate、evidence pack。后续 #2-#7 都能作为该 brainstorm 的组成模块，而不是分散成多个独立项目。
