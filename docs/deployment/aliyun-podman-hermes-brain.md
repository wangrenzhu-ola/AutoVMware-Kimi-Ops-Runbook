# Aliyun Podman Hermes Brain Deployment

本文是 AutoVMware 飞书中枢大脑的工程化部署说明。目标运行时是阿里云 ECS 上的 Podman 容器，容器内运行 Hermes Gateway 连接飞书 websocket，同时运行轻量 Brain API 接收 AutoVMware Worker heartbeat。

## Resource assumptions checked on 2026-05-08

- OS: Ubuntu 24.04 LTS
- CPU: 4 cores
- Memory: 14Gi total，约 12Gi available
- Disk: root 49G，约 31G free；`/data` 独立 196G 数据盘
- Feishu OpenAPI egress: OK
- Podman: apt 可安装，当前非预装
- Suggested Brain API port: `3104`

## Runtime boundary

Accepted runtime must be the Podman container named `autovmware-hermes-brain`.

Do not use an existing host Hermes process as acceptance evidence. Host Hermes may be old, dirty, or manually started. Acceptance must show:

- `podman ps` contains `autovmware-hermes-brain`.
- `systemctl status autovmware-hermes-brain.service` is active.
- Podman persistent bind mounts use `/data/autovmware-hermes-brain/{hermes,state,logs}` on the ECS data disk.
- `curl http://127.0.0.1:3104/health` returns `ok=true`.
- A worker heartbeat can be posted and then read from `GET /workers`.
- Feishu bot sends/receives through the container runtime.
- No real secrets appear in logs or reports.

## Files

- `deploy/hermes-brain/Containerfile` — Hermes Brain image.
- `deploy/hermes-brain/env.example` — environment template; copy to ECS and fill secrets there.
- `deploy/hermes-brain/start.sh` — starts Brain API and Hermes Gateway.
- `deploy/hermes-brain/brain_api.py` — first-version heartbeat registry API.
- `scripts/deploy/aliyun-podman-hermes-brain.sh` — ECS install/build/deploy/status helper.
- `docs/control-plane/hermes-brain-worker-contract.md` — worker heartbeat contract.
- `docs/codex-prompts/deploy-autovmware-worker-to-target-machine.md` — prompt to hand to Codex for target-machine registration.

## ECS deployment steps

Run on ECS as root from a fresh checkout of this repo:

```bash
bash scripts/deploy/aliyun-podman-hermes-brain.sh install-podman
bash scripts/deploy/aliyun-podman-hermes-brain.sh build
bash scripts/deploy/aliyun-podman-hermes-brain.sh deploy
```

On first deploy, the script creates:

```text
/opt/autovmware-hermes-brain/brain.env
```

Fill real Feishu/model credentials in that file on ECS only. Do not commit it and do not print it.

Persistent Podman bind-mount data is stored on the ECS data disk:

```text
/data/autovmware-hermes-brain/hermes
/data/autovmware-hermes-brain/state
/data/autovmware-hermes-brain/logs
```

Do not move these data volumes back under `/opt`; `/opt` is for config/env and service metadata only.

## Status check

```bash
bash scripts/deploy/aliyun-podman-hermes-brain.sh status
curl -fsS http://127.0.0.1:3104/health
curl -fsS http://127.0.0.1:3104/workers
```

## Worker heartbeat smoke

```bash
curl -fsS -X POST http://127.0.0.1:3104/workers/heartbeat \
  -H 'Content-Type: application/json' \
  -d '{"machine_id":"smoke","hostname":"smoke","worker_version":"0.1.0","free_space_gb":100,"kimi_token_present":false,"current_state":"need_token","last_error":"smoke"}'
```

## Deployment handoff to Codex

When deploying to real AutoVMware target machines, do not let this repo agent directly operate those machines. Use:

```text
docs/codex-prompts/deploy-autovmware-worker-to-target-machine.md
```

Give Codex the `BRAIN_API_BASE_URL` and target `machine_id`. Codex must connect to the target machine, deploy or verify AutoVMware Worker, POST heartbeat, and return evidence. It must stop before any real clone.
