from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path


SKILL_DIR = Path(__file__).parent.parent / "skills" / "autovmware-macos-vmx-clone"
SCRIPTS_DIR = SKILL_DIR / "scripts"


def load_module(name: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS_DIR / f"{name}.py")
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    sys.path.insert(0, str(SCRIPTS_DIR))
    try:
        spec.loader.exec_module(module)
    finally:
        sys.path.remove(str(SCRIPTS_DIR))
    return module


def valid_approval() -> dict:
    return {
        "source_vmx": r"F:\15.7.5\W1-OC-Mac-15.7.5\macOS 15\macOS 15.vmx",
        "clone_count": 100,
        "target_root": r"F:\VMs",
        "name_prefix": "DEM009-Mac",
        "memory_gb": 8,
        "disk_gb": 60,
        "clone_mode": "linked",
        "power_on": False,
        "network": "inherit",
        "retention_policy": "keep",
        "approved_action": "clone",
        "approved_by": "human",
        "approval_note": "Exact source, target, count, and power policy approved.",
    }


def test_valid_approval_builds_one_hundred_target_paths() -> None:
    schema = load_module("schema")
    validation = load_module("validation")

    approval = schema.Approval.from_dict(valid_approval())
    validation.validate_approval(approval)

    assert approval.target_names()[0] == "DEM009-Mac-1"
    assert approval.target_names()[-1] == "DEM009-Mac-100"
    assert len(approval.target_names()) == 100
    assert approval.estimated_budget_gb() == 2100


def test_rejects_clone_count_over_one_hundred() -> None:
    schema = load_module("schema")
    validation = load_module("validation")
    payload = valid_approval()
    payload["clone_count"] = 101

    approval = schema.Approval.from_dict(payload)

    try:
        validation.validate_approval(approval)
    except validation.GateError as exc:
        assert exc.code == "E_INVALID_PARAM"
    else:
        raise AssertionError("expected GateError")


def test_cli_plan_is_plan_only(tmp_path: Path, capsys) -> None:
    cli = load_module("cli")
    approval_path = tmp_path / "approval.json"
    approval_path.write_text(json.dumps(valid_approval()), encoding="utf-8")

    exit_code = cli.main(["plan-clone", "--approval-json", str(approval_path)])
    out = capsys.readouterr().out

    assert exit_code == 0
    payload = json.loads(out)
    assert payload["real_vm_action_executed"] is False
    assert payload["target_vmx_paths"][0] == r"F:\VMs\DEM009-Mac-1\DEM009-Mac-1.vmx"


def test_generate_approval_from_default_config(tmp_path: Path, capsys) -> None:
    cli = load_module("cli")
    output = tmp_path / "approval.json"

    exit_code = cli.main(["generate-approval", "100", "--output", str(output)])
    out = capsys.readouterr().out

    assert exit_code == 0
    payload = json.loads(out)
    approval = json.loads(output.read_text(encoding="utf-8"))
    assert payload["real_vm_action_executed"] is False
    assert approval["clone_count"] == 100
    assert approval["source_vmx"] == r"F:\15.7.5\W1-OC-Mac-15.7.5\macOS 15\macOS 15.vmx"
    assert approval["name_prefix"] == "dem009-batch"


def test_doctor_is_read_only_and_reports_non_windows_blocker(capsys) -> None:
    cli = load_module("cli")

    exit_code = cli.main(["doctor", "--format", "json"])
    out = capsys.readouterr().out

    payload = json.loads(out)
    assert payload["real_vm_action_executed"] is False
    if sys.platform != "win32":
        assert exit_code == 2
        assert "不是 Windows" in payload["blockers"][0]
