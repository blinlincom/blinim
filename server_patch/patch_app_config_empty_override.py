#!/usr/bin/env python3
"""Prevent empty app-scoped config fields from overriding complete globals."""

from datetime import datetime
from pathlib import Path
import os
import shutil
import subprocess


ROOT = Path(os.environ.get("BLIN_ROOT", "/www/wwwroot/blinlin"))
CONFIG = ROOT / "app/common/tool/AppScopedConfig.php"


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


def patch_config():
    before = CONFIG.read_text(encoding="utf-8", errors="ignore")
    text = before

    marker = "    public static function mergeFilled("
    if marker not in text:
        insert_after = """    public static function decode($raw)
    {
        if (is_array($raw)) return $raw;
        $raw = trim(strval($raw));
        if ($raw === "") return [];
        $value = json_decode($raw, true);
        return is_array($value) ? $value : [];
    }
"""
        helper = """

    public static function mergeFilled($base, $override)
    {
        if (!is_array($base)) $base = [];
        if (!is_array($override)) $override = [];
        foreach ($override as $key => $value) {
            if (is_array($value)) {
                $base[$key] = self::mergeFilled(isset($base[$key]) && is_array($base[$key]) ? $base[$key] : [], $value);
                continue;
            }
            if ($value === null) continue;
            if (is_string($value) && trim($value) === "") continue;
            $base[$key] = $value;
        }
        return $base;
    }
"""
        if insert_after not in text:
            raise SystemExit("decode method anchor not found")
        text = text.replace(insert_after, insert_after + helper, 1)

    replacements = {
        'return array_merge(self::globalRow("email"), self::appColumn($appid, "email_configuration"));':
            'return self::mergeFilled(self::globalRow("email"), self::appColumn($appid, "email_configuration"));',
        'return array_merge(self::globalRow("AlibabaSample"), self::appColumn($appid, "sms_configuration"));':
            'return self::mergeFilled(self::globalRow("AlibabaSample"), self::appColumn($appid, "sms_configuration"));',
    }
    for old, new in replacements.items():
        if old in text:
            text = text.replace(old, new)

    return write_if_changed(CONFIG, before, text, "app_config_empty_override")


def verify():
    result = subprocess.Popen(
        ["php", "-l", str(CONFIG)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    output = result.communicate()[0].decode("utf-8", "ignore").strip()
    print(output)
    if result.returncode != 0:
        raise SystemExit(result.returncode)


def main():
    changed = patch_config()
    verify()
    print("app config empty override patch applied, changed=%s" % (1 if changed else 0))


if __name__ == "__main__":
    main()
