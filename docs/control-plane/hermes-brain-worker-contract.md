# AutoVMware Hermes Brain / Worker Contract

本文定义飞书 Hermes Brain 与每台 AutoVMware Windows Worker 的第一版工程契约。目标是先把“机器是否可调度”打通，不执行真实 clone。

## Control-plane endpoints

第一版 Brain API 暴露在阿里云 ECS Podman 容器内，建议端口 `3104`：

- `GET /health`：Brain API 存活检查。
- `GET /workers`：查看当前 worker registry。
- `POST /workers/heartbeat`：目标机器上报 heartbeat。

Feishu websocket 由容器内 Hermes Gateway 负责；Worker API 由同容器 `brain_api.py` 负责。两者共享同一 Podman runtime 边界，但 secrets 不写入镜像。

## POST /workers/heartbeat

Worker 每 30-60 秒上报一次；目标机器部署阶段也可以手动上报一次作为注册验收。

```json
{
  "machine_id": "PC12",
  "hostname": "PC12-WIN",
  "worker_version": "0.1.0",
  "windows_user": "PC12",
  "autovmware_root": "C:\\Users\\PC12\\Documents\\AutoVMware",
  "vmware_status": "installed",
  "python_status": "ok",
  "kimi_token_present": true,
  "kimi_token_value": "[redacted]",
  "free_space_gb": 373.7,
  "current_state": "ready",
  "last_error": null,
  "evidence_path": "C:\\Users\\PC12\\Documents\\AutoVMware\\reports\\worker-register.md"
}
```

### Required fields

- `machine_id`
- `hostname`
- `worker_version`
- `free_space_gb`
- `kimi_token_present`
- `current_state`

### Allowed states

| State | Meaning | Next action |
|---|---|---|
| `ready` | Worker、Python、AutoVMware 基础检查通过，可以接受只读任务 | 允许 doctor/token-check/plan |
| `blocked` | 有明确阻塞，不能继续推进 | 生成失败包，等待人工处理 |
| `lost` | Brain 认为 heartbeat 超时 | 检查机器网络/worker service |
| `need_token` | Worker 可达但 Kimi token 缺失 | 本机安全配置 token，不在飞书/GitHub 输出 |
| `low_disk` | 目标盘不足 | 降低 clone_count 或释放磁盘 |
| `doctor_failed` | AutoVMware doctor 失败 | 修复 doctor blocker 后再上报 |
| `installed` | AutoVMware 已安装，但尚未 token/doctor OK | 进入 token-check |
| `token_ok` | token present 且 redacted | 进入 doctor |
| `doctor_ok` | doctor 通过 | 允许生成 plan |
| `plan_ready` | 计划已生成但未审批 | 等飞书/负责人审批 |

## Safety rules

- 第一阶段只做注册、heartbeat、doctor/token-check/plan；不执行真实 clone。
- 不执行真实 clone、start、power on、delete、snapshot、cleanup，除非后续 Story 明确授权并走飞书审批。
- Worker 不得把 Kimi token、Feishu secret、RustDesk 密码、Windows 密码、`.env` 内容写入 heartbeat、日志、截图或 GitHub Issue。
- Brain 保存敏感字段时必须 redacted。字段名包含 `token`、`password`、`secret`、`credential` 时默认脱敏；`kimi_token_present` 是布尔状态例外。
- `@所有人`、群公告和含糊批量指令不得触发真实机器动作。

## Acceptance checklist

1. ECS 上 Podman container `autovmware-hermes-brain` 运行。
2. `curl http://127.0.0.1:3104/health` 返回 `ok=true`。
3. 目标 Windows 机器用 Codex 执行部署提示词后，能 POST heartbeat 到 Brain。
4. `GET /workers` 能看到该 `machine_id`，且 token 只显示 present/redacted 状态。
5. 飞书询问机器状态时，Brain 能返回 ready / blocked / lost / need_token / low_disk / doctor_failed。
6. 验收报告包含 container status、worker heartbeat response、worker evidence path；不包含任何真实 secret。
