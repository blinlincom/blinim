#!/usr/bin/env python3
"""Fix admin email config display/save after app-scoped config was introduced."""

from datetime import datetime
from pathlib import Path
import os
import shutil
import subprocess


ROOT = Path(os.environ.get("BLIN_ROOT", "/www/wwwroot/blinlin"))
SYSTEM = ROOT / "app/admin/controller/System.php"


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

    decode_block = """    private function blinDecodeConfig($raw)
    {
        if (is_array($raw)) return $raw;
        $value = json_decode(strval($raw), true);
        return is_array($value) ? $value : [];
    }
"""
    merge_block = """

    private function blinMergeFilled($base, $override)
    {
        if (!is_array($base)) $base = [];
        if (!is_array($override)) $override = [];
        foreach ($override as $key => $value) {
            if (is_array($value)) {
                $base[$key] = $this->blinMergeFilled(isset($base[$key]) && is_array($base[$key]) ? $base[$key] : [], $value);
                continue;
            }
            if ($value === null) continue;
            if (is_string($value) && trim($value) === "") continue;
            $base[$key] = $value;
        }
        return $base;
    }
"""
    if "private function blinMergeFilled(" not in text:
        if decode_block not in text:
            raise SystemExit("decode block not found")
        text = text.replace(decode_block, decode_block + merge_block, 1)

    old = "        return array_merge(is_array($global) ? $global : [], is_array($local) ? $local : []);\n"
    new = "        return $this->blinMergeFilled(is_array($global) ? $global : [], is_array($local) ? $local : []);\n"
    if old in text:
        text = text.replace(old, new, 1)

    email_data = """            $data = [
                'username' => input("post.username"),
                'password' => input("post.password"),
                'host' => input("post.host"),
                'port' => input("post.port"),
                'fromName' => input("post.fromName"),
            ];
"""
    email_data_new = """            $data = [
                'username' => trim(strval(input("post.username"))),
                'password' => trim(strval(input("post.password"))),
                'host' => trim(strval(input("post.host"))),
                'port' => trim(strval(input("post.port"))),
                'fromName' => trim(strval(input("post.fromName"))),
            ];
            foreach (["username", "password", "host", "port"] as $required) {
                if ($data[$required] === "") {
                    $this->error("请填写完整邮箱配置");
                }
            }
"""
    if email_data in text:
        text = text.replace(email_data, email_data_new, 1)

    return write_if_changed(SYSTEM, before, text, "admin_email_config_persistence")


def verify():
    result = subprocess.Popen(
        ["php", "-l", str(SYSTEM)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    output = result.communicate()[0].decode("utf-8", "ignore").strip()
    print(output)
    if result.returncode != 0:
        raise SystemExit(result.returncode)


def main():
    changed = patch_system()
    verify()
    print("admin email config persistence patch applied, changed=%s" % (1 if changed else 0))


if __name__ == "__main__":
    main()
