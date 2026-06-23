#!/usr/bin/env python3
"""Use the current appid when API endpoints send email verification codes."""

from datetime import datetime
from pathlib import Path
import os
import re
import shutil
import subprocess


ROOT = Path(os.environ.get("BLIN_ROOT", "/www/wwwroot/blinlin"))
API = ROOT / "app/api/controller/Api.php"
EMAIL_TOOL = ROOT / "app/common/tool/Email.php"


def backup(path: Path, suffix: str) -> None:
    stamp = datetime.now().strftime("%Y%m%d%H%M%S")
    target = path.with_name(f"{path.name}.bak_{suffix}_{stamp}")
    shutil.copy2(path, target)
    print("BACKUP", target)


def save_if_changed(path: Path, original: str, source: str, suffix: str) -> bool:
    if source == original:
        print("NO_CHANGE", path)
        return False
    backup(path, suffix)
    path.write_text(source, encoding="utf-8")
    print("UPDATED", path)
    return True


def patch_api() -> bool:
    source = API.read_text(encoding="utf-8", errors="ignore")
    original = source

    # API requests already resolve the current app into $this->appid. Without
    # passing it here, Email falls back to appid=0/request param and misses
    # per-app email_configuration.
    source = re.sub(
        r"new Email\(([^;\n]+?)\)",
        lambda match: match.group(0)
        if "$this->appid" in match.group(0)
        else f"new Email({match.group(1)}, $this->appid)",
        source,
    )

    return save_if_changed(API, original, source, "api_email_appid_scope")


def verify() -> None:
    for path in [API, EMAIL_TOOL]:
        result = subprocess.Popen(
            ["php", "-l", str(path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        output = result.communicate()[0].decode("utf-8", "ignore").strip()
        print(output)
        if result.returncode != 0:
            raise SystemExit(result.returncode)


def main() -> None:
    changed = patch_api()
    verify()
    print(f"email appid scope patch applied, changed={1 if changed else 0}")


if __name__ == "__main__":
    main()
