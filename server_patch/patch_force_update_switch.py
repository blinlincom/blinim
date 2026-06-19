#!/usr/bin/env python3
"""Add force-update switch to app update config and admin UI."""
from datetime import datetime
from pathlib import Path
import os
import re
import subprocess


ROOT = Path("/www/wwwroot/blinlin")
ADMIN = ROOT / "application/admin/controller/App.php"
EDIT = ROOT / "application/admin/view/app/edit.html"


def backup(path: Path, suffix: str) -> str:
    target = path.with_name(
        f"{path.name}.bak_{suffix}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    target.write_text(path.read_text(errors="ignore"))
    return str(target)


def save_if_changed(path: Path, original: str, source: str, suffix: str) -> bool:
    if source == original:
        return False
    print(f"PATCH_{path.name}_BACKUP", backup(path, suffix))
    path.write_text(source)
    return True


def db_config() -> dict:
    values = {
        "hostname": "127.0.0.1",
        "database": "blinlin",
        "username": "root",
        "password": "",
        "hostport": "3306",
        "prefix": "mr_",
    }
    env_path = ROOT / ".env"
    if not env_path.exists():
        return values
    section = ""
    for raw in env_path.read_text(errors="ignore").splitlines():
        line = raw.strip()
        if not line or line.startswith(";") or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip().lower()
            continue
        if section != "database" or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip().lower()
        value = value.strip().strip('"').strip("'")
        if key in values:
            values[key] = value
    return values


def safe_table(prefix: str, name: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9_]*", prefix):
        raise SystemExit("UNSAFE_DATABASE_PREFIX")
    return f"`{prefix}{name}`"


def mysql(config: dict, sql: str) -> subprocess.CompletedProcess:
    env = os.environ.copy()
    env["MYSQL_PWD"] = config.get("password", "")
    cmd = [
        "mysql",
        f"-h{config.get('hostname') or '127.0.0.1'}",
        f"-u{config.get('username') or 'root'}",
        f"-P{config.get('hostport') or '3306'}",
        config.get("database") or "blinlin",
        "-Nse",
        sql,
    ]
    return subprocess.run(
        cmd,
        check=False,
        universal_newlines=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
    )


def patch_database() -> bool:
    config = db_config()
    table = safe_table(config.get("prefix", "mr_"), "app_updates")
    check = mysql(config, f"SHOW COLUMNS FROM {table} LIKE 'force_update'")
    if check.returncode != 0:
        raise SystemExit(check.stderr.strip() or "MYSQL_CHECK_FAILED")
    if check.stdout.strip():
        return False
    alter = mysql(
        config,
        f"ALTER TABLE {table} ADD COLUMN `force_update` tinyint(1) NOT NULL DEFAULT 0 AFTER `update_content`",
    )
    if alter.returncode != 0:
        raise SystemExit(alter.stderr.strip() or "MYSQL_PATCH_FAILED")
    print("PATCH_DATABASE_ADDED force_update")
    return True


def patch_admin_controller() -> bool:
    source = ADMIN.read_text(errors="ignore")
    original = source
    marker = '''                "update_content" => $data["update_content"],
'''
    line = '''                "force_update" => isset($data["force_update"]) ? intval($data["force_update"]) : 0,
'''
    if '"force_update" => isset($data["force_update"])' not in source:
        if marker not in source:
            raise SystemExit("APP_UPDATE_CONFIGURATION_MARKER_NOT_FOUND")
        source = source.replace(marker, marker + line, 1)
    marker = '''                $result["update_configuration"] = Db::name("app_updates")->where("appid", "=", $appid)->order("create_time", "desc")->find();
'''
    defaults = '''                if (!$result["update_configuration"]) {
                    $result["update_configuration"] = array("update_version" => "", "update_url" => "", "update_content" => "", "force_update" => 0);
                }
                if (!isset($result["update_configuration"]["force_update"])) {
                    $result["update_configuration"]["force_update"] = 0;
                }
'''
    if '"force_update" => 0' not in source and marker in source:
        source = source.replace(marker, marker + defaults, 1)
    return save_if_changed(ADMIN, original, source, "force_update_admin")


def force_update_html() -> str:
    return '''                            <div class="col-md-12">
                                <div class="blin-setting-row blin-force-update-switch-card">
                                    <div class="blin-setting-copy">
                                        <span class="blin-setting-title">强制更新</span>
                                        <small class="blin-setting-desc">开启后，客户端检测到新版本会自动弹出不可关闭的更新弹窗；关闭后用户可以稍后更新。</small>
                                    </div>
                                    <div class="blin-segmented-switch" role="group" aria-label="强制更新">
                                        <input type="radio" id="force_update_on" value="1" name="force_update" class="btn-check" autocomplete="off" {if $data.update_configuration.force_update==1} checked {/if}>
                                        <label class="blin-switch-choice blin-switch-choice-on" for="force_update_on"><i class="mdi mdi-lock-check-outline"></i>强制</label>
                                        <input type="radio" id="force_update_off" value="0" name="force_update" class="btn-check" autocomplete="off" {if $data.update_configuration.force_update!=1} checked {/if}>
                                        <label class="blin-switch-choice blin-switch-choice-off" for="force_update_off"><i class="mdi mdi-clock-outline"></i>可关闭</label>
                                    </div>
                                </div>
                            </div>
'''


def patch_edit() -> bool:
    source = EDIT.read_text(errors="ignore")
    original = source
    if "force_update" in source:
        return False
    marker = '''                            <div class="col-md-12">
                                <label for="update_content" class="form-label">更新内容</label>
                                <div class="input-group">
                                    <textarea class="form-control" id="update_content" name="update_content" placeholder="请输入更新内容" style="height: 100px;">{$data.update_configuration.update_content}</textarea>
                                </div>
                            </div>
'''
    if marker not in source:
        raise SystemExit("APP_EDIT_UPDATE_CONTENT_MARKER_NOT_FOUND")
    source = source.replace(marker, marker + force_update_html(), 1)
    return save_if_changed(EDIT, original, source, "force_update_view")


def main() -> None:
    changed_db = patch_database()
    changed_admin = patch_admin_controller()
    changed_edit = patch_edit()
    changed = changed_db or changed_admin or changed_edit
    print("PATCHED_FORCE_UPDATE_SWITCH" if changed else "FORCE_UPDATE_SWITCH_ALREADY_UP_TO_DATE")


if __name__ == "__main__":
    main()
