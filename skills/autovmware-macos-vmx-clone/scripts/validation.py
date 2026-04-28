"""Validation gates for the DEM-009 AutoVMware macOS clone skill."""

from __future__ import annotations

import json
import re
from pathlib import Path, PureWindowsPath
from typing import Any

from schema import (
    ERROR_APPROVAL_MISSING,
    ERROR_FORBIDDEN_ACTION,
    ERROR_INVALID_PARAM,
    ERROR_SOURCE_MISSING,
    ERROR_SPACE_LOW,
    MAX_CLONE_COUNT,
    MIN_CLONE_COUNT,
    MIN_DISK_GB,
    MIN_MEMORY_GB,
    VALID_ACTIONS,
    VALID_CLONE_MODES,
    Approval,
)

WINDOWS_ABSOLUTE = re.compile(r"^[A-Za-z]:\\")
SAFE_PREFIX = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{1,48}$")


class GateError(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message

    def to_dict(self) -> dict[str, str]:
        return {"ok": "false", "code": self.code, "message": self.message}


def load_approval(path: Path) -> Approval:
    if not path.exists():
        raise GateError(ERROR_APPROVAL_MISSING, f"approval JSON not found: {path}")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise GateError(ERROR_APPROVAL_MISSING, f"approval JSON is invalid: {exc}") from exc
    if not isinstance(payload, dict):
        raise GateError(ERROR_APPROVAL_MISSING, "approval JSON must be an object")
    return Approval.from_dict(payload)


def validate_approval(approval: Approval, *, require_existing_source: bool = False) -> list[str]:
    warnings: list[str] = []

    if not approval.source_vmx:
        raise GateError(ERROR_APPROVAL_MISSING, "source_vmx is required")
    if not approval.source_vmx.lower().endswith(".vmx"):
        raise GateError(ERROR_INVALID_PARAM, "source_vmx must end with .vmx")
    if not WINDOWS_ABSOLUTE.match(approval.source_vmx):
        raise GateError(ERROR_INVALID_PARAM, "source_vmx must be an absolute Windows path")
    if ".env" in approval.source_vmx.lower():
        raise GateError(ERROR_FORBIDDEN_ACTION, "source_vmx must not reference env files")

    if require_existing_source and not Path(approval.source_vmx).exists():
        raise GateError(ERROR_SOURCE_MISSING, f"source_vmx does not exist: {approval.source_vmx}")

    if not (MIN_CLONE_COUNT <= approval.clone_count <= MAX_CLONE_COUNT):
        raise GateError(ERROR_INVALID_PARAM, "clone_count must be from 1 to 5")
    if not approval.target_root or not WINDOWS_ABSOLUTE.match(approval.target_root):
        raise GateError(ERROR_INVALID_PARAM, "target_root must be an absolute Windows path")
    if not SAFE_PREFIX.match(approval.name_prefix):
        raise GateError(ERROR_INVALID_PARAM, "name_prefix must be 2-49 chars using letters, numbers, underscore, or hyphen")
    if approval.memory_gb < MIN_MEMORY_GB:
        raise GateError(ERROR_INVALID_PARAM, f"memory_gb must be at least {MIN_MEMORY_GB}")
    if approval.disk_gb < MIN_DISK_GB:
        raise GateError(ERROR_INVALID_PARAM, f"disk_gb must be at least {MIN_DISK_GB}")
    if approval.clone_mode not in VALID_CLONE_MODES:
        raise GateError(ERROR_INVALID_PARAM, "clone_mode must be linked or full")
    if approval.power_on is None:
        raise GateError(ERROR_APPROVAL_MISSING, "power_on must be explicit true or false")
    if not approval.network:
        raise GateError(ERROR_APPROVAL_MISSING, "network is required")
    if not approval.retention_policy:
        raise GateError(ERROR_APPROVAL_MISSING, "retention_policy is required")
    if approval.approved_action not in VALID_ACTIONS:
        raise GateError(ERROR_APPROVAL_MISSING, "approved_action must be one of clone, delete, start, stop")
    if approval.approved_action != "clone":
        warnings.append(f"approval is for {approval.approved_action}; clone planning will not execute this action")
    if not approval.approved_by or not approval.approval_note:
        raise GateError(ERROR_APPROVAL_MISSING, "approved_by and approval_note are required")

    target_root = PureWindowsPath(approval.target_root)
    source_parent = PureWindowsPath(approval.source_vmx).parent
    if str(target_root).lower().startswith(str(source_parent).lower()):
        raise GateError(ERROR_INVALID_PARAM, "target_root must not be inside the source VM directory")

    return warnings


def validate_free_space(free_gb: float | None, approval: Approval) -> None:
    if free_gb is None:
        return
    required = approval.estimated_budget_gb()
    if free_gb < required:
        raise GateError(ERROR_SPACE_LOW, f"free space {free_gb:.1f} GB is below required budget {required} GB")


def assert_no_real_action(*, allow_real_action: bool, approval: Approval | None = None) -> None:
    if allow_real_action and approval is None:
        raise GateError(ERROR_APPROVAL_MISSING, "real action requires validated approval")
    if not allow_real_action:
        raise GateError(ERROR_FORBIDDEN_ACTION, "real VM actions are disabled by default")
