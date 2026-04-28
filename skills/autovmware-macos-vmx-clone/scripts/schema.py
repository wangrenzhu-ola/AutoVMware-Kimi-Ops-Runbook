"""Data schema for the DEM-009 AutoVMware macOS clone skill."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import PureWindowsPath
from typing import Any

ERROR_INVALID_PARAM = "E_INVALID_PARAM"
ERROR_SOURCE_MISSING = "E_SOURCE_MISSING"
ERROR_SPACE_LOW = "E_SPACE_LOW"
ERROR_APPROVAL_MISSING = "E_APPROVAL_MISSING"
ERROR_FORBIDDEN_ACTION = "E_FORBIDDEN_ACTION"

VALID_CLONE_MODES = {"linked", "full"}
VALID_ACTIONS = {"clone", "delete", "start", "stop"}
MAX_CLONE_COUNT = 5
MIN_CLONE_COUNT = 1
MIN_MEMORY_GB = 8
MIN_DISK_GB = 60
LINKED_CLONE_BUDGET_GB = 20
SAFETY_MARGIN_GB = 40


@dataclass(frozen=True)
class Approval:
    source_vmx: str
    clone_count: int
    target_root: str
    name_prefix: str
    memory_gb: int
    disk_gb: int
    clone_mode: str
    power_on: bool
    network: str
    retention_policy: str
    approved_action: str
    approved_by: str
    approval_note: str

    @classmethod
    def from_dict(cls, payload: dict[str, Any]) -> "Approval":
        return cls(
            source_vmx=str(payload.get("source_vmx", "")).strip(),
            clone_count=int(payload.get("clone_count", 0)),
            target_root=str(payload.get("target_root", "")).strip(),
            name_prefix=str(payload.get("name_prefix", "")).strip(),
            memory_gb=int(payload.get("memory_gb", 0)),
            disk_gb=int(payload.get("disk_gb", 0)),
            clone_mode=str(payload.get("clone_mode", "")).strip().lower(),
            power_on=payload.get("power_on") if isinstance(payload.get("power_on"), bool) else None,  # type: ignore[arg-type]
            network=str(payload.get("network", "")).strip(),
            retention_policy=str(payload.get("retention_policy", "")).strip(),
            approved_action=str(payload.get("approved_action", "")).strip().lower(),
            approved_by=str(payload.get("approved_by", "")).strip(),
            approval_note=str(payload.get("approval_note", "")).strip(),
        )

    def target_names(self) -> list[str]:
        return [f"{self.name_prefix}-{index}" for index in range(1, self.clone_count + 1)]

    def target_vmx_paths(self) -> list[str]:
        root = PureWindowsPath(self.target_root)
        return [str(root / name / f"{name}.vmx") for name in self.target_names()]

    def estimated_budget_gb(self) -> int:
        per_clone = LINKED_CLONE_BUDGET_GB if self.clone_mode == "linked" else max(MIN_DISK_GB, self.disk_gb)
        return per_clone * self.clone_count + SAFETY_MARGIN_GB
