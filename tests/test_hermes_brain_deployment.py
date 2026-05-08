from __future__ import annotations

import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


def read(path: str) -> str:
    return (REPO_ROOT / path).read_text(encoding="utf-8")


def test_podman_hermes_brain_deployment_artifacts_are_declared() -> None:
    containerfile = read("deploy/hermes-brain/Containerfile")
    env_example = read("deploy/hermes-brain/env.example")
    deploy_script = read("scripts/deploy/aliyun-podman-hermes-brain.sh")

    assert "HERMES_HOME" in containerfile
    assert "hermes_cli.main" in containerfile
    assert "gateway run" in containerfile
    assert "FEISHU_APP_ID=" in env_example
    assert "FEISHU_APP_SECRET=" in env_example
    assert "changeme" in env_example.lower()
    assert "podman" in deploy_script
    assert "autovmware-hermes-brain" in deploy_script
    assert "--replace" in deploy_script


def test_brain_contract_documents_worker_heartbeat_and_states() -> None:
    contract = read("docs/control-plane/hermes-brain-worker-contract.md")

    for field in [
        "machine_id",
        "hostname",
        "worker_version",
        "free_space_gb",
        "kimi_token_present",
        "current_state",
        "last_error",
    ]:
        assert field in contract

    for state in ["ready", "blocked", "lost", "need_token", "low_disk", "doctor_failed"]:
        assert state in contract

    assert "POST /workers/heartbeat" in contract
    assert "不执行真实 clone" in contract


def test_codex_target_machine_prompt_is_self_contained_and_safe() -> None:
    prompt = read("docs/codex-prompts/deploy-autovmware-worker-to-target-machine.md")

    assert "Codex" in prompt
    assert "AutoVMware" in prompt
    assert "Brain" in prompt
    assert "heartbeat" in prompt.lower()
    assert "不要执行真实 clone" in prompt
    assert "不要输出 token" in prompt
    assert "验收输出" in prompt
    assert re.search(r"machine_id", prompt)


def test_linux_ci_validates_podman_brain_artifacts() -> None:
    workflow = read(".github/workflows/linux-brain-ci.yml")

    assert "runs-on: ubuntu-latest" in workflow
    assert "python -m pytest -q" in workflow
    assert "podman" in workflow.lower()
    assert "deploy/hermes-brain/Containerfile" in workflow
    assert "tests/test_hermes_brain_deployment.py" in workflow
