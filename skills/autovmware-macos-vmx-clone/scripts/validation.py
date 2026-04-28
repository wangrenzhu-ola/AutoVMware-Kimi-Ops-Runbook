"""DEM-009 AutoVMware macOS 克隆安全校验。"""

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
        raise GateError(ERROR_APPROVAL_MISSING, f"找不到审批文件：{path}")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise GateError(ERROR_APPROVAL_MISSING, f"审批文件不是合法 JSON：{exc}") from exc
    if not isinstance(payload, dict):
        raise GateError(ERROR_APPROVAL_MISSING, "审批文件必须是一个 JSON 对象")
    return Approval.from_dict(payload)


def validate_approval(approval: Approval, *, require_existing_source: bool = False) -> list[str]:
    warnings: list[str] = []

    if not approval.source_vmx:
        raise GateError(ERROR_APPROVAL_MISSING, "必须填写 source_vmx，也就是源 VMX 路径")
    if not approval.source_vmx.lower().endswith(".vmx"):
        raise GateError(ERROR_INVALID_PARAM, "source_vmx 必须以 .vmx 结尾")
    if not WINDOWS_ABSOLUTE.match(approval.source_vmx):
        raise GateError(ERROR_INVALID_PARAM, "source_vmx 必须是 Windows 绝对路径，例如 F:\\VMs\\macOS.vmx")
    if ".env" in approval.source_vmx.lower():
        raise GateError(ERROR_FORBIDDEN_ACTION, "source_vmx 不能引用 env 文件")

    if require_existing_source and not Path(approval.source_vmx).exists():
        raise GateError(ERROR_SOURCE_MISSING, f"源 VMX 不存在：{approval.source_vmx}")

    if not (MIN_CLONE_COUNT <= approval.clone_count <= MAX_CLONE_COUNT):
        raise GateError(ERROR_INVALID_PARAM, "clone_count 必须是 1 到 100")
    if not approval.target_root or not WINDOWS_ABSOLUTE.match(approval.target_root):
        raise GateError(ERROR_INVALID_PARAM, "target_root 必须是 Windows 绝对路径，例如 F:\\VMs")
    if not SAFE_PREFIX.match(approval.name_prefix):
        raise GateError(ERROR_INVALID_PARAM, "name_prefix 必须是 2 到 49 个字符，只能用字母、数字、下划线或短横线")
    if approval.memory_gb < MIN_MEMORY_GB:
        raise GateError(ERROR_INVALID_PARAM, f"memory_gb 至少要 {MIN_MEMORY_GB}")
    if approval.disk_gb < MIN_DISK_GB:
        raise GateError(ERROR_INVALID_PARAM, f"disk_gb 至少要 {MIN_DISK_GB}")
    if approval.clone_mode not in VALID_CLONE_MODES:
        raise GateError(ERROR_INVALID_PARAM, "clone_mode 只能是 linked 或 full")
    if approval.power_on is None:
        raise GateError(ERROR_APPROVAL_MISSING, "power_on 必须明确写 true 或 false")
    if not approval.network:
        raise GateError(ERROR_APPROVAL_MISSING, "必须填写 network")
    if not approval.retention_policy:
        raise GateError(ERROR_APPROVAL_MISSING, "必须填写 retention_policy")
    if approval.approved_action not in VALID_ACTIONS:
        raise GateError(ERROR_APPROVAL_MISSING, "approved_action 只能是 clone、delete、start、stop 之一")
    if approval.approved_action != "clone":
        warnings.append(f"审批动作是 {approval.approved_action}，本命令只生成克隆计划，不执行这个动作")
    if not approval.approved_by or not approval.approval_note:
        raise GateError(ERROR_APPROVAL_MISSING, "必须填写 approved_by 和 approval_note")

    target_root = PureWindowsPath(approval.target_root)
    source_parent = PureWindowsPath(approval.source_vmx).parent
    if str(target_root).lower().startswith(str(source_parent).lower()):
        raise GateError(ERROR_INVALID_PARAM, "target_root 不能放在源虚拟机目录里面")

    return warnings


def validate_free_space(free_gb: float | None, approval: Approval) -> None:
    if free_gb is None:
        return
    required = approval.estimated_budget_gb()
    if free_gb < required:
        raise GateError(ERROR_SPACE_LOW, f"剩余空间 {free_gb:.1f} GB 小于预算 {required} GB")


def assert_no_real_action(*, allow_real_action: bool, approval: Approval | None = None) -> None:
    if allow_real_action and approval is None:
        raise GateError(ERROR_APPROVAL_MISSING, "真实动作必须先通过审批校验")
    if not allow_real_action:
        raise GateError(ERROR_FORBIDDEN_ACTION, "默认禁止真实虚拟机动作")
