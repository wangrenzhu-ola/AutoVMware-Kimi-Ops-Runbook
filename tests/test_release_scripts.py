from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent


def test_install_script_is_windows_powershell_5_safe_ascii() -> None:
    content = (REPO_ROOT / "install.ps1").read_text(encoding="utf-8")

    assert content.isascii()
    assert '$PSVersionTable.ContainsKey("Platform")' in content
    assert '$runningOnWindows = Test-RunningOnWindows' in content
    assert '$runningOnWindows = $PSVersionTable.Platform' not in content


def test_release_builder_encodes_powershell_scripts_with_utf8_bom() -> None:
    content = (REPO_ROOT / "scripts" / "release" / "build-release.ps1").read_text(
        encoding="utf-8"
    )

    assert "UTF8Encoding($true)" in content
    assert 'Filter "*.ps1"' in content
    assert '"config"' in content


def test_release_package_includes_kimi_ops_config_template() -> None:
    assert (REPO_ROOT / "config" / "kimi-ops.example.json").exists()


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
