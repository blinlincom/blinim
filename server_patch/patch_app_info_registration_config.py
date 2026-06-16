#!/usr/bin/env python3
"""Expose app registration/login/invitation config to the Flutter client."""

from datetime import datetime
from pathlib import Path
import shutil


ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"


def backup(path: Path, suffix: str) -> None:
    target = path.with_name(
        f"{path.name}.bak_{suffix}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    shutil.copy2(path, target)
    print("BACKUP", target)


def main() -> None:
    source = API.read_text(errors="ignore")
    original = source
    marker = '        $result["announcement_configuration"] = $this->app_info["announcement_configuration"];\n'
    insert = (
        marker
        + '        $result["registration_configuration"] = $this->app_info["registration_configuration"];\n'
        + '        $result["login_configuration"] = $this->app_info["login_configuration"];\n'
        + '        $result["invitation_configuration"] = $this->app_info["invitation_configuration"];\n'
        + '        $result["security_configuration"] = $this->app_info["security_configuration"];\n'
    )
    if '$result["registration_configuration"] = $this->app_info["registration_configuration"];' not in source:
        if marker not in source:
            raise SystemExit("APP_INFO_MARKER_NOT_FOUND")
        source = source.replace(marker, insert, 1)
    if source != original:
        backup(API, "app_info_registration_config")
        API.write_text(source)
        print("PATCHED", API)
    else:
        print("NO_CHANGE", API)


if __name__ == "__main__":
    main()
