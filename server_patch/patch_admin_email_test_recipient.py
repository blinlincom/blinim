#!/usr/bin/env python3
"""Persist the admin email test recipient on the email settings page."""

from datetime import datetime
from pathlib import Path
import os
import shutil
import subprocess


ROOT = Path(os.environ.get("BLIN_ROOT", "/www/wwwroot/blinlin"))
SYSTEM = ROOT / "app/admin/controller/System.php"
VIEW = ROOT / "app/admin/view/system/email.html"


def backup(path, suffix):
    stamp = datetime.now().strftime("%Y%m%d%H%M%S")
    target = path.with_name("%s.bak_%s_%s" % (path.name, suffix, stamp))
    shutil.copy2(path, target)
    print("BACKUP", target)


def write_if_changed(path, before, after, suffix):
    if before == after:
        print("NO_CHANGE", path)
        return False
    backup(path, suffix)
    path.write_text(after, encoding="utf-8")
    print("UPDATED", path)
    return True


def patch_system():
    before = SYSTEM.read_text(encoding="utf-8", errors="ignore")
    text = before

    old = """                'port' => trim(strval(input("post.port"))),
                'fromName' => trim(strval(input("post.fromName"))),
            ];
"""
    new = """                'port' => trim(strval(input("post.port"))),
                'fromName' => trim(strval(input("post.fromName"))),
                'toEmail' => trim(strval(input("post.toEmail"))),
            ];
"""
    if old in text:
        text = text.replace(old, new, 1)

    old = """        $email_info_value = $this->blinAppJsonConfig($appid, "email_configuration", $this->blinGlobalConfigRow("email"));
        $system_info = $this->blinSystemCodeConfig($appid);
"""
    new = """        $email_info_value = $this->blinAppJsonConfig($appid, "email_configuration", $this->blinGlobalConfigRow("email"));
        foreach (["username", "password", "host", "port", "fromName", "toEmail"] as $key) {
            if (!isset($email_info_value[$key])) $email_info_value[$key] = "";
        }
        $system_info = $this->blinSystemCodeConfig($appid);
"""
    if old in text:
        text = text.replace(old, new, 1)

    old = """        $appid = $this->blinConfigAppId();
        $toEmail = input("post.toEmail");
        $email = new Email($toEmail, $appid);
"""
    new = """        $appid = $this->blinConfigAppId();
        $toEmail = trim(strval(input("post.toEmail")));
        if ($toEmail === "") {
            $emailConfig = $this->blinAppJsonConfig($appid, "email_configuration", $this->blinGlobalConfigRow("email"));
            $toEmail = trim(strval(isset($emailConfig["toEmail"]) ? $emailConfig["toEmail"] : ""));
        }
        if ($toEmail === "") $this->error("请填写测试邮箱");
        $email = new Email($toEmail, $appid);
"""
    if old in text:
        text = text.replace(old, new, 1)

    return write_if_changed(SYSTEM, before, text, "admin_email_test_recipient")


def patch_view():
    before = VIEW.read_text(encoding="utf-8", errors="ignore")
    text = before.replace(
        'id="toEmail" name="toEmail" value="" placeholder="请输入测试邮箱"',
        'id="toEmail" name="toEmail" value="{$info.toEmail}" placeholder="请输入测试邮箱"',
        1,
    )
    return write_if_changed(VIEW, before, text, "admin_email_test_recipient")


def verify():
    for path in [SYSTEM]:
        result = subprocess.Popen(
            ["php", "-l", str(path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        output = result.communicate()[0].decode("utf-8", "ignore").strip()
        print(output)
        if result.returncode != 0:
            raise SystemExit(result.returncode)


def main():
    changed = 0
    changed += 1 if patch_system() else 0
    changed += 1 if patch_view() else 0
    verify()
    print("admin email test recipient patch applied, changed=%s" % changed)


if __name__ == "__main__":
    main()
