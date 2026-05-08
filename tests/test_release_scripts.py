from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent


def test_install_script_is_windows_powershell_5_safe() -> None:
    content = (REPO_ROOT / "install.ps1").read_text(encoding="utf-8")

    assert '$PSVersionTable.ContainsKey("Platform")' in content
    assert '$runningOnWindows = Test-RunningOnWindows' in content
    assert '$runningOnWindows = $PSVersionTable.Platform' not in content


def test_release_builder_encodes_powershell_scripts_with_utf8_bom() -> None:
    content = (REPO_ROOT / "scripts" / "release" / "build-release.ps1").read_text(
        encoding="utf-8"
    )

    assert "UTF8Encoding($true)" in content
    assert 'Filter "*.ps1"' in content
    assert '"install-latest.ps1"' in content
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

    assert "function Write-WarnCheck" in content
    assert 'Write-WarnCheck "Source VMX"' in content
    assert 'Write-WarnCheck "Target drive"' in content
    assert 'Write-WarnCheck "Target free space"' in content
    assert "$readinessWarnings = New-Object System.Collections.Generic.List[string]" in content
    assert 'Kimi should discover the real source image on this host.' in content
    assert 'Kimi should ask the operator for the real output drive.' in content
    assert 'The configured source VMX does not exist. Check the source image path.' not in content
    assert 'The clone output drive does not exist.' not in content
    assert 'Target drive free space is below the minimum budget' not in content


def test_install_script_prints_kimi_discovery_prompt() -> None:
    content = (REPO_ROOT / "install.ps1").read_text(encoding="utf-8")

    assert "function Write-KimiOperatorPrompt" in content
    assert "Kimi 操作指南" in content
    assert "----- 开始：复制给 Kimi 的中文提示词 -----" in content
    assert "你是这台 Windows 主机上的 AutoVMware macOS VMX 克隆运维助手。" in content
    assert "先搜索本机可用磁盘里的 macOS / Hackintosh .vmx 候选镜像" in content
    assert "询问运维选择哪个源 .vmx，并询问克隆数量；数量范围是 1 到 100。" in content
    assert "等待运维输入明确确认语句，才能执行任何真实克隆动作。" in content
    assert "----- 结束：复制给 Kimi 的中文提示词 -----" in content


def test_install_script_installs_and_verifies_kimi_cli() -> None:
    content = (REPO_ROOT / "install.ps1").read_text(encoding="utf-8")

    assert "function Install-KimiCli" in content
    assert 'Invoke-RestMethod -Uri "https://astral.sh/uv/install.ps1"' in content
    assert "& $uv tool install --python 3.13 kimi-cli" in content
    assert "function Update-CurrentPath" in content
    assert "function Find-KimiExecutable" in content
    assert 'Join-Path $userLocalBin "kimi.exe"' in content
    assert "& $kimiPath --version" in content
    assert "https://code.kimi.com/install.ps1" not in content


def test_install_script_recovers_release_skill_source_from_environment() -> None:
    content = (REPO_ROOT / "install.ps1").read_text(encoding="utf-8")

    assert "AUTOVMWARE_RELEASE_SKILL_SOURCE" in content
    assert "$SkillSource -eq $RepoRoot" in content
    assert "Using release skill source from AUTOVMWARE_RELEASE_SKILL_SOURCE" in content
    assert 'Write-Host ("Install target: {0}" -f $RepoRoot)' in content
    assert 'Write-Host ("Skill source: {0}" -f $SkillSource)' in content


def test_install_latest_downloads_and_runs_release_installer() -> None:
    content = (REPO_ROOT / "install-latest.ps1").read_text(encoding="utf-8")

    assert content.isascii()
    assert "releases/latest" in content
    assert "releases/tags/$tag" in content
    assert "AutoVMware-Kimi-Ops-v*.zip" in content
    assert "Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath" in content
    assert "Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force" in content
    assert 'Get-ChildItem -LiteralPath $extractDir -Recurse -File -Filter "install.ps1"' in content
    assert '[Environment]::GetFolderPath("MyDocuments")' in content
    assert '$skillSource = Join-Path $packageRoot "skills\\autovmware-macos-vmx-clone"' in content
    assert "$env:AUTOVMWARE_RELEASE_SKILL_SOURCE = $skillSource" in content
    assert '"-File", $installPath.FullName' in content
    assert '"-RepoRoot", $RepoRoot' in content
    assert '"-SkillSource", $skillSource' in content
    assert 'if (-not [string]::IsNullOrWhiteSpace($DummyKimiToken))' in content
    assert '"-DummyKimiToken", $DummyKimiToken' in content
    assert "& powershell.exe @installArgs" in content
    assert "if ($LASTEXITCODE -ne 0)" in content


def test_windows_ci_exercises_mock_install_and_ops_status() -> None:
    content = (REPO_ROOT / ".github" / "workflows" / "windows-kimi-ops-smoke.yml").read_text(
        encoding="utf-8"
    )

    assert "runs-on: windows-latest" in content
    assert "-MockMode" in content
    assert "dummy-ci-token-not-real" in content
    assert "ops-status --mock-token --format json" in content
    assert "token_value -ne \"[redacted]\"" in content
