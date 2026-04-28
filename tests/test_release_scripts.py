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
