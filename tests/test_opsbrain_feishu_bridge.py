from __future__ import annotations

import importlib.util
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
BRIDGE_PATH = REPO_ROOT / "deploy" / "hermes-brain" / "opsbrain_feishu_bridge.py"

spec = importlib.util.spec_from_file_location("opsbrain_feishu_bridge", BRIDGE_PATH)
assert spec and spec.loader
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class FakeBrain:
    def health(self):
        return {"ok": True, "service": "autovmware-hermes-brain", "worker_count": 2}

    def workers(self):
        return {
            "workers": {
                "win-1": {
                    "hostname": "WIN-A",
                    "worker_version": "0.1.0",
                    "current_state": "ready",
                    "free_space_gb": 42,
                    "kimi_token_present": True,
                    "kimi_token": "must-not-leak",
                    "last_heartbeat_at": 1780000000,
                }
            }
        }


def test_ops_health_routes_to_brain_health() -> None:
    router = bridge.OpsBrainRouter(FakeBrain())

    command, text = router.route("/ops health")

    assert command == "health"
    assert "OpsBrain health：OK" in text
    assert "worker_count：2" in text
    assert "autovmware-hermes-brain" in text
    assert "Stage-1" in text


def test_ops_workers_summarizes_and_redacts_sensitive_fields() -> None:
    router = bridge.OpsBrainRouter(FakeBrain())

    command, text = router.route("/ops workers")

    assert command == "workers"
    assert "OpsBrain workers：1" in text
    assert "win-1" in text
    assert "host=WIN-A" in text
    assert "state=ready" in text
    assert "must-not-leak" not in text
    assert "kimi_token=" not in text


def test_identity_is_opsbrain_not_generic_hermes() -> None:
    router = bridge.OpsBrainRouter(FakeBrain())

    command, text = router.route("你当前身份是？")

    assert command == "identity"
    assert "Infra运维大脑 / OpsBrain" in text
    assert "Hermes Agent" not in text
    assert "可用命令" in text


def test_unknown_ops_command_returns_help_not_generic_unknown() -> None:
    router = bridge.OpsBrainRouter(FakeBrain())

    command, text = router.route("/ops reboot all")

    assert command == "unknown_ops"
    assert "未知 /ops 子命令" in text
    assert "/ops health" in text
    assert "不会" not in text or "VMware" in text


def test_plain_unrelated_text_is_ignored() -> None:
    router = bridge.OpsBrainRouter(FakeBrain())

    command, text = router.route("hello")

    assert command is None
    assert text == ""


def test_ops_related_text_without_minimax_api_key_returns_fallback() -> None:
    """When MINIMAX_API_KEY is not set, ops-related text returns fallback help."""
    router = bridge.OpsBrainRouter(FakeBrain())

    command, text = router.route("vmrun 是什么？")

    assert command == "llm_fallback"
    assert "暂时不可用" in text
    assert "/ops help" in text


def test_non_ops_text_is_ignored() -> None:
    """Non-ops text without /ops prefix is still ignored."""
    router = bridge.OpsBrainRouter(FakeBrain())

    command, text = router.route("今天天气怎么样")

    assert command is None
    assert text == ""
