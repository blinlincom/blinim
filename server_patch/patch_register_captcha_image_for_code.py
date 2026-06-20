#!/usr/bin/env python3
"""Allow register image captcha when email/mobile registration code is enabled."""

from datetime import datetime
from pathlib import Path
import os
import shutil


ROOT = Path(os.environ.get("BLIN_ROOT", "/www/wwwroot/blinlin"))
API = ROOT / "application/api/controller/Api.php"


def backup(path):
    stamp = datetime.now().strftime("%Y%m%d%H%M%S")
    shutil.copy2(path, path.with_name(f"{path.name}.bak_register_code_captcha_{stamp}"))


def main():
    before = API.read_text(encoding="utf-8", errors="ignore")
    old = """        //注册验证码
        if ($type == 2) {
            if ($this->app_info["registration_configuration"]["registration_code_switch"] == 1) {
                return $this->blinCreateImageCaptcha("register");
            }
            $this->json(0, '未开启注册图片验证码');
        }
"""
    new = """        //注册验证码。邮箱/手机号注册发码前也需要图片验证码，避免短信/邮件被刷。
        if ($type == 2) {
            $registerCodeSwitch = intval(isset($this->app_info["registration_configuration"]["registration_code_switch"]) ? $this->app_info["registration_configuration"]["registration_code_switch"] : 0);
            if (in_array($registerCodeSwitch, [1, 2, 3])) {
                return $this->blinCreateImageCaptcha("register");
            }
            $this->json(0, '未开启注册图片验证码');
        }
"""
    if new in before:
        print("PATCH_ALREADY_APPLIED")
        return
    if old not in before:
        raise RuntimeError("missing get_image_verification_code register block")
    after = before.replace(old, new, 1)
    backup(API)
    API.write_text(after, encoding="utf-8")
    print("PATCHED_REGISTER_CODE_IMAGE_CAPTCHA")


if __name__ == "__main__":
    main()
