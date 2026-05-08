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


def test_install_script_continues_when_default_clone_paths_need_discovery() -> None:
    content = (REPO_ROOT / "install.ps1").read_text(encoding="utf-8")

    assert "$readinessWarnings = New-Object System.Collections.Generic.List[string]" in content
    assert 'Kimi should discover the real source image on this host.' in content
    assert 'Kimi should ask the operator for the real output drive.' in content
    assert 'The configured source VMX does not exist. Check the source image path.' not in content
    assert 'The clone output drive does not exist.' not in content
    assert 'Target drive free space is below the minimum budget' not in content


def test_install_script_prints_kimi_discovery_prompt() -> None:
    content = (REPO_ROOT / "install.ps1").read_text(encoding="utf-8")

    assert "function Write-KimiOperatorPrompt" in content
    assert "----- BEGIN KIMI PROMPT -----" in content
    assert "Search available file-system drives for likely macOS or Hackintosh .vmx files" in content
    assert "Ask the operator to choose the source .vmx and clone count, from 1 to 100." in content
    assert "Stop and wait for explicit confirmation before any real clone action." in content


def test_windows_ci_exercises_mock_install_and_ops_status() -> None:
    content = (REPO_ROOT / ".github" / "workflows" / "windows-kimi-ops-smoke.yml").read_text(
        encoding="utf-8"
    )

    assert "runs-on: windows-latest" in content
    assert "-MockMode" in content
    assert "dummy-ci-token-not-real" in content
    assert "ops-status --mock-token --format json" in content
    assert "token_value -ne \"[redacted]\"" in content
