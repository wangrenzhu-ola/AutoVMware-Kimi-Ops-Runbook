from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent


def test_install_script_is_windows_powershell_5_safe_ascii() -> None:
    content = (REPO_ROOT / "install.ps1").read_text(encoding="utf-8")

    assert content.isascii()


def test_release_builder_encodes_powershell_scripts_with_utf8_bom() -> None:
    content = (REPO_ROOT / "scripts" / "release" / "build-release.ps1").read_text(
        encoding="utf-8"
    )

    assert "UTF8Encoding($true)" in content
    assert 'Filter "*.ps1"' in content


def test_install_script_supports_mock_token_mode_without_real_vmware() -> None:
    content = (REPO_ROOT / "install.ps1").read_text(encoding="utf-8")

    assert "[switch]$MockMode" in content
    assert "[string]$DummyKimiToken" in content
    assert "Skipping real VMX, target drive, and VMware CLI checks" in content
    assert "[redacted]" in content


def test_windows_ci_exercises_mock_install_and_ops_status() -> None:
    content = (REPO_ROOT / ".github" / "workflows" / "windows-kimi-ops-smoke.yml").read_text(
        encoding="utf-8"
    )

    assert "runs-on: windows-latest" in content
    assert "-MockMode" in content
    assert "dummy-ci-token-not-real" in content
    assert "ops-status --mock-token --format json" in content
    assert "token_value -ne \"[redacted]\"" in content
