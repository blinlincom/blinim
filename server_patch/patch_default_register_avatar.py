#!/usr/bin/env python3
"""Use the app-level default user avatar for all generated registrations."""

from datetime import datetime
from pathlib import Path
import os
import shutil


ROOT = Path(os.environ.get("BLIN_ROOT", "/www/wwwroot/blinlin"))
API = ROOT / "application/api/controller/Api.php"


def backup(path):
    stamp = datetime.now().strftime("%Y%m%d%H%M%S")
    shutil.copy2(path, path.with_name(f"{path.name}.bak_default_avatar_{stamp}"))


def replace_function(source, name, replacement):
    needle = f"    private function {name}()"
    start = source.find(needle)
    if start < 0:
        raise RuntimeError(f"missing function {name}")
    brace = source.find("{", start)
    depth = 0
    for index in range(brace, len(source)):
        char = source[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[:start] + replacement + source[index + 1 :]
    raise RuntimeError(f"missing function end for {name}")


def main():
    before = API.read_text(encoding="utf-8", errors="ignore")
    replacement = '''    private function blinRandomAvatar()
    {
        $userinfo = isset($this->app_info["userinfo_configuration"]) ? $this->app_info["userinfo_configuration"] : [];
        if (is_string($userinfo)) {
            $decoded = json_decode($userinfo, true);
            $userinfo = is_array($decoded) ? $decoded : [];
        }
        $avatar = isset($userinfo["usertx"]) ? trim(strval($userinfo["usertx"])) : "";
        if ($avatar !== "") {
            return $avatar;
        }
        return request()->domain() . "/static/images/initial_photo/user.png";
    }'''
    if replacement in before:
        print("PATCH_ALREADY_APPLIED")
        return
    after = replace_function(before, "blinRandomAvatar", replacement)
    backup(API)
    API.write_text(after, encoding="utf-8")
    print("PATCHED_DEFAULT_REGISTER_AVATAR")


if __name__ == "__main__":
    main()
