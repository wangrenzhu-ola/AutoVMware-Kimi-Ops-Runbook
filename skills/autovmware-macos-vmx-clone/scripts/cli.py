#!/usr/bin/env python3
"""CLI for safe DEM-009 AutoVMware macOS VMX clone discovery and planning."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

from validation import GateError, load_approval, validate_approval, validate_free_space

MAC_HINTS = ("macos", "mac os", "hackintosh", "opencore", "darwin", "ventura", "sonoma", "sequoia", "oc")
KNOWN_CANDIDATE = r"F:\15.7.5\W1-OC-Mac-15.7.5\macOS 15\macOS 15.vmx"
TOOL_HINTS = ("clone", "batch", "vm-create-macos", "vm_create_macos")
DEFAULT_CONFIG = Path(__file__).resolve().parent.parent / "config" / "defaults.json"


def drive_root(letter: str) -> Path:
    clean = letter.strip().rstrip(":\\/")
    if len(clean) != 1 or not clean.isalpha():
        raise GateError("E_INVALID_PARAM", "drive must be a single drive letter")
    return Path(f"{clean.upper()}:\\")


def disk_free_gb(path: Path) -> float | None:
    try:
        return round(shutil.disk_usage(path).free / (1024**3), 2)
    except OSError:
        return None


def score_vmx(path: Path) -> int:
    text = str(path).lower()
    return sum(1 for hint in MAC_HINTS if hint in text)


def discover_vmx(root: Path, *, limit: int = 25) -> list[dict[str, Any]]:
    candidates: list[dict[str, Any]] = []
    if not root.exists():
        return candidates
    for path in root.rglob("*.vmx"):
        lowered = str(path).lower()
        if ".env" in lowered:
            continue
        score = score_vmx(path)
        if score <= 0:
            continue
        try:
            stat = path.stat()
        except OSError:
            continue
        candidates.append(
            {
                "path": str(path),
                "score": score,
                "size_bytes": stat.st_size,
                "modified": datetime.fromtimestamp(stat.st_mtime).isoformat(timespec="seconds"),
            }
        )
    return sorted(candidates, key=lambda item: (-item["score"], item["path"].lower()))[:limit]


def discover_tooling(repo_root: Path) -> list[str]:
    if not repo_root.exists():
        return []
    matches: list[str] = []
    for path in repo_root.rglob("*"):
        if not path.is_file():
            continue
        lowered = path.name.lower()
        if ".env" in str(path).lower():
            continue
        if any(hint in lowered for hint in TOOL_HINTS):
            matches.append(str(path))
    return sorted(matches)[:50]


def load_config(path: Path | None = None) -> dict[str, Any]:
    config_path = path or DEFAULT_CONFIG
    if not config_path.exists():
        raise GateError("E_CONFIG_MISSING", f"config not found: {config_path}")
    try:
        payload = json.loads(config_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise GateError("E_INVALID_PARAM", f"config JSON is invalid: {exc}") from exc
    if not isinstance(payload, dict):
        raise GateError("E_INVALID_PARAM", "config must be a JSON object")
    return payload


def approval_from_config(config: dict[str, Any], clone_count: int) -> dict[str, Any]:
    payload = dict(config)
    payload["clone_count"] = clone_count
    payload.setdefault("approved_action", "clone")
    payload.setdefault("approved_by", "human")
    payload.setdefault("approval_note", "Generated from default skill config. Human must approve before execution.")
    return payload


def find_vmware_tools() -> dict[str, str | None]:
    common_roots = [
        Path(r"C:\Program Files (x86)\VMware\VMware Workstation"),
        Path(r"C:\Program Files\VMware\VMware Workstation"),
    ]
    result: dict[str, str | None] = {
        "vmrun": shutil.which("vmrun"),
        "vmware-vdiskmanager": shutil.which("vmware-vdiskmanager"),
    }
    for root in common_roots:
        for exe in ("vmrun.exe", "vmware-vdiskmanager.exe"):
            key = exe[:-4]
            if result.get(key):
                continue
            candidate = root / exe
            if candidate.exists():
                result[key] = str(candidate)
    return result


def doctor_result(config_path: Path | None = None) -> dict[str, Any]:
    config = load_config(config_path)
    approval = load_approval_from_payload(approval_from_config(config, int(config.get("clone_count", 1) or 1)))
    warnings = validate_approval(approval)
    source = Path(approval.source_vmx)
    target_root = Path(approval.target_root)
    root = Path(approval.target_root[:3])
    tools = find_vmware_tools()
    checks = {
        "python": sys.version.split()[0],
        "platform": sys.platform,
        "is_windows": os.name == "nt",
        "config_path": str(config_path or DEFAULT_CONFIG),
        "source_vmx_configured": bool(approval.source_vmx),
        "source_vmx_exists": source.exists() if os.name == "nt" else None,
        "target_root_exists": target_root.exists() if os.name == "nt" else None,
        "target_drive_free_gb": disk_free_gb(root),
        "vmrun": tools["vmrun"],
        "vmware_vdiskmanager": tools["vmware-vdiskmanager"],
        "kimi_cli": shutil.which("kimi"),
        "warnings": warnings,
    }
    blockers: list[str] = []
    if os.name == "nt":
        if not checks["source_vmx_exists"]:
            blockers.append("source_vmx does not exist")
        if not checks["vmrun"]:
            blockers.append("vmrun was not found")
        if not checks["vmware_vdiskmanager"]:
            blockers.append("vmware-vdiskmanager was not found")
        free_gb = checks["target_drive_free_gb"]
        if isinstance(free_gb, float):
            try:
                validate_free_space(free_gb, approval)
            except GateError as exc:
                blockers.append(exc.message)
    else:
        blockers.append("doctor is running outside Windows, so VMware paths cannot be fully verified")
    return {
        "ok": not blockers,
        "action": "doctor",
        "real_vm_action_executed": False,
        "checks": checks,
        "blockers": blockers,
        "forbidden_actions": "none",
    }


def load_approval_from_payload(payload: dict[str, Any]):
    from schema import Approval

    return Approval.from_dict(payload)


def make_plan(approval_path: Path, *, free_gb: float | None = None) -> dict[str, Any]:
    approval = load_approval(approval_path)
    warnings = validate_approval(approval)
    validate_free_space(free_gb, approval)
    return {
        "ok": True,
        "action": "plan_only",
        "real_vm_action_executed": False,
        "warnings": warnings,
        "approval": approval.__dict__,
        "estimated_budget_gb": approval.estimated_budget_gb(),
        "target_vmx_paths": approval.target_vmx_paths(),
        "hard_gates": [
            "approval JSON validated",
            "clone_count is 1..5",
            "power_on is explicit",
            "no env file path referenced",
            "plan generated without executing clone",
        ],
    }


def output_result(result: dict[str, Any], fmt: str) -> None:
    if fmt == "json":
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return
    print(markdown_result(result))


def markdown_result(result: dict[str, Any]) -> str:
    lines = ["# AutoVMware macOS VMX Clone Result", ""]
    for key in ("ok", "action", "real_vm_action_executed", "drive", "free_gb", "estimated_budget_gb"):
        if key in result:
            lines.append(f"- {key}: `{result[key]}`")
    if result.get("candidates"):
        lines.extend(["", "## Candidates"])
        for item in result["candidates"]:
            lines.append(f"- `{item['path']}` score={item['score']} modified={item['modified']}")
    if result.get("target_vmx_paths"):
        lines.extend(["", "## Planned Targets"])
        for path in result["target_vmx_paths"]:
            lines.append(f"- `{path}`")
    if result.get("tooling"):
        lines.extend(["", "## Tooling Hints"])
        for path in result["tooling"]:
            lines.append(f"- `{path}`")
    if result.get("warnings"):
        lines.extend(["", "## Warnings"])
        for warning in result["warnings"]:
            lines.append(f"- {warning}")
    if result.get("checks"):
        lines.extend(["", "## Doctor Checks"])
        for key, value in result["checks"].items():
            lines.append(f"- {key}: `{value}`")
    if result.get("blockers"):
        lines.extend(["", "## Blockers"])
        for blocker in result["blockers"]:
            lines.append(f"- {blocker}")
    return "\n".join(lines) + "\n"


def command_discover(args: argparse.Namespace) -> int:
    root = drive_root(args.drive)
    repo_root = Path.cwd()
    result = {
        "ok": True,
        "action": "discovery_only",
        "real_vm_action_executed": False,
        "drive": str(root),
        "free_gb": disk_free_gb(root),
        "known_candidate": KNOWN_CANDIDATE,
        "candidates": discover_vmx(root),
        "tooling": discover_tooling(repo_root),
        "forbidden_actions": "none",
    }
    output_result(result, args.format)
    return 0


def command_validate_approval(args: argparse.Namespace) -> int:
    approval = load_approval(Path(args.approval_json))
    warnings = validate_approval(approval)
    print(json.dumps({"ok": True, "warnings": warnings, "approval": approval.__dict__}, ensure_ascii=False, indent=2))
    return 0


def command_plan_clone(args: argparse.Namespace) -> int:
    approval = load_approval(Path(args.approval_json))
    root = Path(approval.target_root[:3])
    result = make_plan(Path(args.approval_json), free_gb=disk_free_gb(root))
    output_result(result, args.format)
    return 0


def command_generate_approval(args: argparse.Namespace) -> int:
    config = load_config(Path(args.config) if args.config else None)
    payload = approval_from_config(config, args.count)
    approval = load_approval_from_payload(payload)
    validate_approval(approval)
    output_path = Path(args.output)
    if ".env" in str(output_path).lower():
        raise GateError("E_FORBIDDEN_ACTION", "approval output must not be an env path")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"ok": True, "output": str(output_path), "real_vm_action_executed": False}, ensure_ascii=False, indent=2))
    return 0


def command_doctor(args: argparse.Namespace) -> int:
    result = doctor_result(Path(args.config) if args.config else None)
    output_result(result, args.format)
    return 0 if result["ok"] else 2


def command_report_template(args: argparse.Namespace) -> int:
    plan = make_plan(Path(args.approval_json))
    output_path = Path(args.output)
    if ".env" in str(output_path).lower():
        raise GateError("E_FORBIDDEN_ACTION", "report output must not be an env path")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# DEM-009 AutoVMware macOS Clone Report",
        "",
        f"- Source VMX: `{plan['approval']['source_vmx']}`",
        f"- Clone count: `{plan['approval']['clone_count']}`",
        f"- Target root: `{plan['approval']['target_root']}`",
        f"- Clone mode: `{plan['approval']['clone_mode']}`",
        f"- Power on approved: `{plan['approval']['power_on']}`",
        "- F drive free space before: `TODO`",
        "- F drive free space after: `TODO`",
        "- Forbidden actions: `TODO`",
        "",
        "## Planned Targets",
        *[f"- `{path}`" for path in plan["target_vmx_paths"]],
        "",
        "## Clone Verification",
        "- TODO: vmx exists for each clone",
        "- TODO: screenshot path for each started clone, if power-on was separately approved",
        "",
        "## Cleanup And Rerun",
        "- TODO: deletion approval, deletion evidence, rerun evidence",
    ]
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({"ok": True, "output": str(output_path), "real_vm_action_executed": False}, indent=2))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    discover = subparsers.add_parser("discover")
    discover.add_argument("--drive", default="F")
    discover.add_argument("--format", choices=("json", "markdown"), default="json")
    discover.set_defaults(func=command_discover)

    validate = subparsers.add_parser("validate-approval")
    validate.add_argument("--approval-json", required=True)
    validate.set_defaults(func=command_validate_approval)

    plan = subparsers.add_parser("plan-clone")
    plan.add_argument("--approval-json", required=True)
    plan.add_argument("--format", choices=("json", "markdown"), default="json")
    plan.set_defaults(func=command_plan_clone)

    generate = subparsers.add_parser("generate-approval")
    generate.add_argument("count", type=int)
    generate.add_argument("--config")
    generate.add_argument("--output", default="config/autovmware-macos-vmx-clone.approval.json")
    generate.set_defaults(func=command_generate_approval)

    doctor = subparsers.add_parser("doctor")
    doctor.add_argument("--config")
    doctor.add_argument("--format", choices=("json", "markdown"), default="markdown")
    doctor.set_defaults(func=command_doctor)

    report = subparsers.add_parser("report-template")
    report.add_argument("--approval-json", required=True)
    report.add_argument("--output", required=True)
    report.set_defaults(func=command_report_template)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except GateError as exc:
        print(json.dumps({"ok": False, "code": exc.code, "message": exc.message}, ensure_ascii=False, indent=2), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
