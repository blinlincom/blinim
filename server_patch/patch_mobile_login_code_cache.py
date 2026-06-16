#!/usr/bin/env python3
"""Store mobile login verification codes by mobile number."""

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
    old = (
        '                    Cache::set($this->appid . "mobile_login" . get_client_ip(), '
        '["code" => $captcha, "mobile" => $mobile, "time" => time()], $phone_code_time);\n'
    )
    new = (
        '                    Cache::set($this->appid . "mobile_login" . $mobile, '
        '["code" => $captcha, "mobile" => $mobile, "time" => time()], $phone_code_time);\n'
        '                    Cache::set($this->appid . "mobile_login" . get_client_ip(), '
        '["code" => $captcha, "mobile" => $mobile, "time" => time()], $phone_code_time);\n'
    )
    if new not in source:
        if old not in source:
            raise SystemExit("MOBILE_LOGIN_CACHE_MARKER_NOT_FOUND")
        source = source.replace(old, new, 1)
    if source != original:
        backup(API, "mobile_login_code_cache")
        API.write_text(source)
        print("PATCHED", API)
    else:
        print("NO_CHANGE", API)


if __name__ == "__main__":
    main()
