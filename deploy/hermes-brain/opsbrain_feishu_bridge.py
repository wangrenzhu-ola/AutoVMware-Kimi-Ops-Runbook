from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

APP_NAME = "Infra运维大脑 / OpsBrain"
RUNTIME_NAME = "autovmware-hermes-brain"
STAGE_SCOPE = "Stage-1：只读 health/status/worker registry/doctor；不执行 VMware 破坏性操作。"
DEFAULT_BRAIN_API_BASE = "http://127.0.0.1:3104"
SENSITIVE_KEYS = ("token", "secret", "password", "credential", "authorization", "encrypt", "key")
IDENTITY_KEYWORDS = ("你是谁", "当前身份", "身份", "identity", "who are you", "who r u")

# Kimi fallback configuration (replaces MiniMax M2.7)
KIMI_API_KEY = os.environ.get("KIMI_API_KEY", "")
KIMI_BASE_URL = os.environ.get("KIMI_BASE_URL", "https://api.kimi.com/v1")
KIMI_MODEL = os.environ.get("KIMI_MODEL", "kimi-k2.6")
OPS_KEYWORDS = (
    "vmware", "vmx", "clone", "克隆", "worker", "brain", "ops", "运维",
    "vmrun", "snapshot", "快照", "deploy", "部署", "heartbeat", "心跳",
    "doctor", "诊断", "health", "status", "状态", "kimi", "token",
    "podman", "ecs", "aliyun", "阿里云", "windows", "macos", "hackintosh",
    "disk", "磁盘", "space", "空间", "memory", "内存", "error", "错误",
    "fail", "失败", "log", "日志", "config", "配置", "install", "安装",
)


def is_ops_related(text: str) -> bool:
    lowered = text.lower()
    return any(keyword in lowered for keyword in OPS_KEYWORDS)


def kimi_chat(user_text: str) -> str | None:
    """Call Kimi API for ops-related non-/ops queries. Returns None on failure."""
    if not KIMI_API_KEY:
        return None
    url = f"{KIMI_BASE_URL}/chat/completions"
    payload = {
        "model": KIMI_MODEL,
        "messages": [
            {
                "role": "system",
                "content": (
                    "你是 Infra运维大脑（OpsBrain）的 AI 助手。"
                    "你只回答运维、VMware、AutoVMware、Worker 部署、Brain API 相关的问题。"
                    "如果问题与运维无关，礼貌地告诉用户你只会回答运维相关问题，并建议发送 /ops help 查看可用命令。"
                    "回答要简洁、专业、说人话。"
                ),
            },
            {"role": "user", "content": user_text},
        ],
        "temperature": 0.7,
        "max_tokens": 2048,
    }
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method="POST",
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "Authorization": f"Bearer {KIMI_API_KEY}",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            body = response.read().decode("utf-8")
            result = json.loads(body)
            choices = result.get("choices", [])
            if choices and isinstance(choices, list):
                content = choices[0].get("message", {}).get("content", "")
                if content:
                    return str(content).strip()
            return None
    except Exception as exc:
        print(f"opsbrain_feishu: kimi_chat failed: {exc}", flush=True)
        return None


def csv_set(value: str | None) -> set[str]:
    return {item.strip() for item in (value or "").split(",") if item.strip()}


def is_truthy(value: str | None) -> bool:
    return str(value or "").strip().lower() in {"1", "true", "yes", "y", "on"}


def redact(value: Any) -> Any:
    if isinstance(value, dict):
        result: dict[str, Any] = {}
        for key, item in value.items():
            lowered = str(key).lower()
            if any(marker in lowered for marker in SENSITIVE_KEYS) and lowered != "kimi_token_present":
                result[key] = "[redacted]"
            else:
                result[key] = redact(item)
        return result
    if isinstance(value, list):
        return [redact(item) for item in value]
    return value


def extract_text_from_message(message: Any) -> str:
    content = getattr(message, "content", "") or ""
    if not content:
        return ""
    try:
        payload = json.loads(content)
    except json.JSONDecodeError:
        return str(content).strip()
    if isinstance(payload, dict):
        text = payload.get("text")
        if isinstance(text, str):
            return text.strip()
    return str(content).strip()


def normalize_text(text: str) -> str:
    # Feishu mention text can contain generated mention prefixes. Keep command parsing simple.
    return " ".join(text.replace("\u00a0", " ").strip().split())


def is_identity_question(text: str) -> bool:
    lowered = text.lower()
    return any(keyword.lower() in lowered for keyword in IDENTITY_KEYWORDS)


def format_identity() -> str:
    return (
        f"我是 {APP_NAME}。\n"
        f"运行边界：{RUNTIME_NAME}（阿里云 Podman）。\n"
        f"{STAGE_SCOPE}\n"
        "可用命令：/ops health、/ops workers、/ops help。"
    )


def format_help() -> str:
    return (
        f"{APP_NAME} 可用命令：\n"
        "- /ops health：查看 Brain API 存活、worker_count 和运行边界\n"
        "- /ops workers：查看当前 Worker 注册摘要\n"
        "- /ops doctor：说明当前只读诊断边界\n"
        "- 你是谁 / 当前身份：查看身份\n"
        f"\n{STAGE_SCOPE}"
    )


def format_health(health: dict[str, Any], now: int | None = None) -> str:
    now = int(time.time()) if now is None else now
    ok = bool(health.get("ok"))
    service = health.get("service") or RUNTIME_NAME
    worker_count = health.get("worker_count", 0)
    status = "OK" if ok else "DEGRADED"
    return (
        f"OpsBrain health：{status}\n"
        f"service：{service}\n"
        f"runtime：{RUNTIME_NAME}\n"
        f"worker_count：{worker_count}\n"
        f"timestamp：{now}\n"
        f"scope：{STAGE_SCOPE}"
    )


def summarize_worker(machine_id: str, worker: dict[str, Any]) -> str:
    worker = redact(worker)
    hostname = worker.get("hostname", "unknown")
    state = worker.get("current_state", "unknown")
    version = worker.get("worker_version", "unknown")
    free_space = worker.get("free_space_gb", "unknown")
    kimi = worker.get("kimi_token_present", "unknown")
    heartbeat = worker.get("last_heartbeat_at", "unknown")
    return (
        f"- {machine_id} | host={hostname} | state={state} | "
        f"version={version} | free_gb={free_space} | kimi_token_present={kimi} | last_heartbeat={heartbeat}"
    )


def format_workers(state: dict[str, Any]) -> str:
    workers = state.get("workers") if isinstance(state, dict) else None
    if not isinstance(workers, dict) or not workers:
        return f"OpsBrain workers：0\nruntime：{RUNTIME_NAME}\n暂无已注册 Worker。"
    lines = [f"OpsBrain workers：{len(workers)}", f"runtime：{RUNTIME_NAME}"]
    for machine_id, worker in sorted(workers.items()):
        if isinstance(worker, dict):
            lines.append(summarize_worker(str(machine_id), worker))
        else:
            lines.append(f"- {machine_id} | invalid worker payload")
    return "\n".join(lines)


def format_doctor() -> str:
    return (
        "OpsBrain doctor：Stage-1 safe mode\n"
        f"runtime：{RUNTIME_NAME}\n"
        "当前仅开放只读 health/status/worker registry/doctor。\n"
        "不会执行 clone、start、power on、delete、snapshot、cleanup 等 VMware 操作。\n"
        "后续 destructive 运维动作必须进入单独 Story，并走飞书审批/留痕。"
    )


def http_json(method: str, url: str, payload: dict[str, Any] | None = None, headers: dict[str, str] | None = None, timeout: int = 10) -> dict[str, Any]:
    data = None if payload is None else json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(url, data=data, method=method, headers={"Content-Type": "application/json; charset=utf-8", **(headers or {})})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        body = response.read().decode("utf-8")
        return json.loads(body) if body else {}


class BrainClient:
    def __init__(self, base_url: str = DEFAULT_BRAIN_API_BASE) -> None:
        self.base_url = base_url.rstrip("/")

    def health(self) -> dict[str, Any]:
        return http_json("GET", f"{self.base_url}/health")

    def workers(self) -> dict[str, Any]:
        return http_json("GET", f"{self.base_url}/workers")


class OpsBrainRouter:
    def __init__(self, brain: BrainClient | None = None) -> None:
        self.brain = brain or BrainClient(os.environ.get("BRAIN_API_BASE", DEFAULT_BRAIN_API_BASE))

    def route(self, text: str) -> tuple[str | None, str]:
        normalized = normalize_text(text)
        lowered = normalized.lower()
        if lowered.startswith("/ops health") or lowered in {"/ops", "/ops status"}:
            return "health", format_health(redact(self.brain.health()))
        if lowered.startswith("/ops workers") or lowered.startswith("/ops worker"):
            return "workers", format_workers(redact(self.brain.workers()))
        if lowered.startswith("/ops doctor"):
            return "doctor", format_doctor()
        if lowered.startswith("/ops help") or lowered in {"help", "/help"}:
            return "help", format_help()
        if is_identity_question(normalized):
            return "identity", format_identity()
        if lowered.startswith("/ops"):
            return "unknown_ops", "未知 /ops 子命令。\n\n" + format_help()
        # Non-/ops text: try Kimi for ops-related queries
        if is_ops_related(normalized):
            llm_response = kimi_chat(normalized)
            if llm_response:
                return "llm_ops", llm_response
            # Kimi failed or no API key: fall back to help
            return "llm_fallback", "OpsBrain LLM 暂时不可用，请尝试 /ops help 查看命令。"
        return None, ""


class FeishuReplyClient:
    def __init__(self, app_id: str, app_secret: str) -> None:
        self.app_id = app_id
        self.app_secret = app_secret
        self._tenant_token: str | None = None
        self._tenant_token_expires_at = 0.0

    def tenant_token(self) -> str:
        if self._tenant_token and time.time() < self._tenant_token_expires_at - 60:
            return self._tenant_token
        payload = {"app_id": self.app_id, "app_secret": self.app_secret}
        data = http_json("POST", "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal", payload)
        if data.get("code") != 0 or not data.get("tenant_access_token"):
            raise RuntimeError(f"failed to get tenant_access_token: code={data.get('code')} msg={data.get('msg')}")
        self._tenant_token = str(data["tenant_access_token"])
        self._tenant_token_expires_at = time.time() + int(data.get("expire", 3600))
        return self._tenant_token

    def reply_text(self, message_id: str, text: str) -> dict[str, Any]:
        payload = {"msg_type": "text", "content": json.dumps({"text": text}, ensure_ascii=False)}
        token = self.tenant_token()
        return http_json(
            "POST",
            f"https://open.feishu.cn/open-apis/im/v1/messages/{message_id}/reply",
            payload,
            headers={"Authorization": f"Bearer {token}"},
        )


class OpsBrainFeishuBridge:
    def __init__(self) -> None:
        self.app_id = os.environ.get("FEISHU_APP_ID", "")
        self.app_secret = os.environ.get("FEISHU_APP_SECRET", "")
        self.encrypt_key = os.environ.get("FEISHU_ENCRYPT_KEY", "")
        self.verification_token = os.environ.get("FEISHU_VERIFICATION_TOKEN", "")
        self.allowed_users = csv_set(os.environ.get("FEISHU_ALLOWED_USERS"))
        self.allowed_chats = csv_set(os.environ.get("FEISHU_ALLOWED_CHATS"))
        self.allow_all_users = is_truthy(os.environ.get("FEISHU_ALLOW_ALL_USERS"))
        self.group_policy = os.environ.get("FEISHU_GROUP_POLICY", "allowlist").strip().lower()
        state_root = Path(os.environ.get("BRAIN_STATE_ROOT", "/opt/autovmware-hermes-brain/state"))
        self.seen_path = state_root / "feishu_seen_message_ids.json"
        self.last_chat_path = state_root / "feishu_last_chat.json"
        self.seen_ids = self._load_seen_ids()
        self.router = OpsBrainRouter()
        self.reply_client = FeishuReplyClient(self.app_id, self.app_secret)

    def _load_seen_ids(self) -> set[str]:
        try:
            data = json.loads(self.seen_path.read_text(encoding="utf-8"))
            return {str(item) for item in data[-500:]}
        except Exception:
            return set()

    def _save_seen_ids(self) -> None:
        self.seen_path.parent.mkdir(parents=True, exist_ok=True)
        self.seen_path.write_text(json.dumps(list(self.seen_ids)[-500:], ensure_ascii=False), encoding="utf-8")

    def _record_last_chat(self, *, chat_id: str, user_id: str, text: str) -> None:
        payload = {"chat_id": chat_id, "user_id": user_id, "last_text": text[:80], "updated_at": int(time.time())}
        self.last_chat_path.parent.mkdir(parents=True, exist_ok=True)
        self.last_chat_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    def _allowed(self, *, chat_id: str, user_id: str, chat_type: str) -> bool:
        if self.allow_all_users:
            return True
        if user_id and user_id in self.allowed_users:
            return True
        if chat_id and chat_id in self.allowed_chats:
            return True
        if chat_type != "p2p" and self.group_policy == "open":
            return True
        return False

    def on_message(self, data: Any) -> None:
        event = getattr(data, "event", None)
        message = getattr(event, "message", None)
        sender = getattr(event, "sender", None)
        sender_id = getattr(getattr(sender, "sender_id", None), "open_id", "") or getattr(sender, "sender_id", "") or ""
        message_id = str(getattr(message, "message_id", "") or "")
        chat_id = str(getattr(message, "chat_id", "") or "")
        chat_type = str(getattr(message, "chat_type", "") or "p2p")
        text = extract_text_from_message(message)
        if not message_id or not chat_id or not text:
            print("opsbrain_feishu: drop malformed message", flush=True)
            return
        if message_id in self.seen_ids:
            print(f"opsbrain_feishu: duplicate message_id={message_id[:10]}", flush=True)
            return
        self.seen_ids.add(message_id)
        self._save_seen_ids()
        self._record_last_chat(chat_id=chat_id, user_id=str(sender_id), text=text)
        if not self._allowed(chat_id=chat_id, user_id=str(sender_id), chat_type=chat_type):
            print(f"opsbrain_feishu: drop unauthorized chat={chat_id[:8]} user={str(sender_id)[:8]}", flush=True)
            return
        command, response = self.router.route(text)
        if not command:
            print(f"opsbrain_feishu: ignored text chat={chat_id[:8]} text={text[:40]!r}", flush=True)
            return
        print(f"opsbrain_feishu: command={command} chat={chat_id[:8]} message={message_id[:10]}", flush=True)
        result = self.reply_client.reply_text(message_id, response)
        if result.get("code") not in (0, None):
            print(f"opsbrain_feishu: reply failed code={result.get('code')} msg={result.get('msg')}", flush=True)
        else:
            print(f"opsbrain_feishu: reply sent command={command}", flush=True)

    def run(self) -> None:
        if not self.app_id or not self.app_secret:
            raise SystemExit("FEISHU_APP_ID/FEISHU_APP_SECRET required")
        import lark_oapi as lark
        from lark_oapi.event.dispatcher_handler import EventDispatcherHandler
        from lark_oapi.ws import Client as FeishuWSClient

        handler = (
            EventDispatcherHandler.builder(self.encrypt_key, self.verification_token)
            .register_p2_im_message_receive_v1(self.on_message)
            .build()
        )
        client = FeishuWSClient(
            self.app_id,
            self.app_secret,
            log_level=getattr(lark.LogLevel, "INFO"),
            event_handler=handler,
        )
        print(f"opsbrain_feishu: starting websocket runtime={RUNTIME_NAME}", flush=True)
        client.start()


if __name__ == "__main__":
    OpsBrainFeishuBridge().run()
