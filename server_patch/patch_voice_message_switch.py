#!/usr/bin/env python3
"""Add per-app voice message switch to backend app config and admin UI."""
from datetime import datetime
from pathlib import Path
import os
import re


ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"
ADMIN = ROOT / "application/admin/controller/App.php"
EDIT = ROOT / "application/admin/view/app/edit.html"
API_BASE = ROOT / "application/api/controller/BaseController.php"


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
        "charset": "utf8",
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
        mapping = {
            "type": "type",
            "hostname": "hostname",
            "database": "database",
            "username": "username",
            "password": "password",
            "hostport": "hostport",
            "charset": "charset",
            "prefix": "prefix",
        }
        if key in mapping:
            values[mapping[key]] = value
    return values


def app_table_name(config: dict) -> str:
    prefix = config.get("prefix", "mr_")
    if not re.fullmatch(r"[A-Za-z0-9_]*", prefix):
        raise SystemExit("UNSAFE_DATABASE_PREFIX")
    return f"`{prefix}app`"


def patch_database() -> bool:
    config = db_config()
    table = app_table_name(config)
    try:
        import pymysql  # type: ignore
    except Exception:
        return _patch_database_with_mysql_cli(config, table)
    conn = pymysql.connect(
        host=config["hostname"],
        user=config["username"],
        password=config["password"],
        database=config["database"],
        port=int(config.get("hostport") or 3306),
        charset=config["charset"],
    )
    try:
        with conn.cursor() as cursor:
            cursor.execute(f"SHOW COLUMNS FROM {table} LIKE 'im_configuration'")
            if cursor.fetchone():
                return False
            cursor.execute(
                f"ALTER TABLE {table} ADD COLUMN `im_configuration` text NULL AFTER `announcement_configuration`"
            )
            cursor.execute(
                f"UPDATE {table} SET `im_configuration` = '{{\"voice_message_switch\":\"0\"}}' WHERE `im_configuration` IS NULL OR `im_configuration` = ''"
            )
        conn.commit()
        print("PATCH_DATABASE_ADDED im_configuration")
        return True
    finally:
        conn.close()


def _patch_database_with_mysql_cli(config: dict, table: str) -> bool:
    import subprocess

    env = os.environ.copy()
    env["MYSQL_PWD"] = config["password"]
    base_cmd = [
        "mysql",
        f"-h{config['hostname']}",
        f"-u{config['username']}",
        f"-P{config.get('hostport') or '3306'}",
        config["database"],
    ]
    check = subprocess.run(
        base_cmd + ["-Nse", f"SHOW COLUMNS FROM {table} LIKE 'im_configuration'"],
        check=False,
        universal_newlines=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
    )
    if check.returncode != 0:
        raise SystemExit(check.stderr.strip() or "MYSQL_CHECK_FAILED")
    if check.stdout.strip():
        return False
    sql = (
        f"ALTER TABLE {table} ADD COLUMN `im_configuration` text NULL AFTER `announcement_configuration`; "
        f"UPDATE {table} SET `im_configuration` = '{{\"voice_message_switch\":\"0\"}}' "
        "WHERE `im_configuration` IS NULL OR `im_configuration` = '';"
    )
    run = subprocess.run(
        base_cmd + ["-e", sql],
        check=False,
        universal_newlines=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
    )
    if run.returncode != 0:
        raise SystemExit(run.stderr.strip() or "MYSQL_PATCH_FAILED")
    print("PATCH_DATABASE_ADDED im_configuration")
    return True


def patch_api() -> bool:
    source = API.read_text(errors="ignore")
    original = source
    marker = '        $result["announcement_configuration"] = $this->app_info["announcement_configuration"];\n'
    line = '        $result["im_configuration"] = $this->app_info["im_configuration"];\n'
    if line not in source:
        if marker not in source:
            raise SystemExit("API_APP_INFO_MARKER_NOT_FOUND")
        source = source.replace(marker, marker + line, 1)
    return save_if_changed(API, original, source, "voice_message_switch_api")


def patch_api_base_controller() -> bool:
    source = API_BASE.read_text(errors="ignore")
    original = source
    marker = '            $result["announcement_configuration"] = json_decode($result["announcement_configuration"], true);\n'
    line = '            $result["im_configuration"] = isset($result["im_configuration"]) && $result["im_configuration"] ? json_decode($result["im_configuration"], true) : ["voice_message_switch" => "0"];\n'
    default_block = '''            if (!is_array($result["im_configuration"])) {
                $result["im_configuration"] = ["voice_message_switch" => "0"];
            }
            if (!isset($result["im_configuration"]["voice_message_switch"])) {
                $result["im_configuration"]["voice_message_switch"] = "0";
            }
'''
    if line not in source:
        if marker not in source:
            raise SystemExit("API_BASE_APP_INFO_MARKER_NOT_FOUND")
        source = source.replace(marker, marker + line, 1)
    if '$result["im_configuration"]["voice_message_switch"] = "0";' not in source:
        source = source.replace(line, line + default_block, 1)
    return save_if_changed(API_BASE, original, source, "voice_message_switch_api_base")


def _ensure_default_im_configuration(source: str) -> str:
    default_line = '            "im_configuration" => \'{"voice_message_switch":"0"}\',\n'
    if '"im_configuration" =>' in source:
        source = re.sub(
            r'''"im_configuration"\s*=>\s*'\{([^']*)\}',''',
            lambda match: match.group(0)
            if "voice_message_switch" in match.group(1)
            else match.group(0).replace(
                "}'", ',"voice_message_switch":"0"}\''
            ),
            source,
            count=1,
        )
        return source

    marker = '            "announcement_configuration" =>'
    index = source.find(marker)
    if index == -1:
        return source
    line_start = source.rfind("\n", 0, index) + 1
    return source[:line_start] + default_line + source[line_start:]


def _ensure_decode_defaults(source: str) -> str:
    block = '''                if (!isset($result["im_configuration"]) || empty($result["im_configuration"])) {
                    $result["im_configuration"] = array();
                } elseif (is_string($result["im_configuration"])) {
                    $result["im_configuration"] = json_decode($result["im_configuration"], true);
                }
                if (!is_array($result["im_configuration"])) {
                    $result["im_configuration"] = array();
                }
                if (!isset($result["im_configuration"]["voice_message_switch"])) {
                    $result["im_configuration"]["voice_message_switch"] = 0;
                }
'''
    if "voice_message_switch" in source and '$result["im_configuration"]["voice_message_switch"] = 0;' in source:
        return source
    markers = [
        '                $result["announcement_configuration"] = json_decode($result["announcement_configuration"], true);\n',
        '                $result["forum_configuration"] = json_decode($result["forum_configuration"], true);\n',
    ]
    for marker in markers:
        if marker in source:
            return source.replace(marker, marker + block, 1)
    return source


def _ensure_save_payload(source: str) -> str:
    line = '                "im_configuration" => json_encode(array("voice_message_switch" => isset($data["voice_message_switch"]) ? intval($data["voice_message_switch"]) : 1), JSON_UNESCAPED_UNICODE),\n'
    if '"voice_message_switch" => isset($data["voice_message_switch"])' in source:
        return source
    markers = [
        '                "announcement_configuration" => json_encode($announcement_configuration, JSON_UNESCAPED_UNICODE),\n',
        '                "forum_configuration" => json_encode($forum_configuration, JSON_UNESCAPED_UNICODE),\n',
    ]
    for marker in markers:
        if marker in source:
            return source.replace(marker, marker + line, 1)
    return source


def patch_admin_controller() -> bool:
    source = ADMIN.read_text(errors="ignore")
    original = source
    source = _ensure_default_im_configuration(source)
    source = _ensure_decode_defaults(source)
    source = _ensure_save_payload(source)
    if source == original:
        return False
    if '"im_configuration" =>' not in source:
        raise SystemExit("ADMIN_IM_CONFIGURATION_SAVE_MARKER_NOT_FOUND")
    return save_if_changed(ADMIN, original, source, "voice_message_switch_admin")


def _switch_html() -> str:
    return '''                        <div class="blin-setting-row blin-voice-message-switch-card">
                            <div class="blin-setting-copy">
                                <span class="blin-setting-title">语音消息</span>
                                <small class="blin-setting-desc">控制客户端个人聊天和群聊是否显示语音发送入口。关闭后不影响已收到语音的播放和历史消息展示。</small>
                            </div>
                            <div class="blin-segmented-switch" role="group" aria-label="语音消息开关">
                                <input type="radio" id="voice_message_switch_on" value="0" name="voice_message_switch" class="btn-check" autocomplete="off" {if $data.im_configuration.voice_message_switch==0} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-on" for="voice_message_switch_on"><i class="mdi mdi-check-circle-outline"></i>开启</label>
                                <input type="radio" id="voice_message_switch_off" value="1" name="voice_message_switch" class="btn-check" autocomplete="off" {if $data.im_configuration.voice_message_switch==1} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-off" for="voice_message_switch_off"><i class="mdi mdi-close-circle-outline"></i>关闭</label>
                            </div>
                        </div>'''


def patch_edit() -> bool:
    source = EDIT.read_text(errors="ignore")
    original = source
    if "voice_message_switch" in source:
        return False
    switch = _switch_html()
    markers = [
        '<div class="card-title">社区配置</div>',
        '<div class="card-title">论坛配置</div>',
        '<div class="card-title">应用配置</div>',
        '<div class="card-title">基础配置</div>',
    ]
    for marker in markers:
        if marker in source:
            insert_at = source.find(marker)
            card_start = source.rfind('<div class="card', 0, insert_at)
            if card_start == -1:
                continue
            source = source[:card_start] + '''                <div class="card">
                    <div class="card-header">
                        <div class="card-title">即时通讯配置</div>
                    </div>
                    <div class="card-body">
''' + switch + '''
                    </div>
                </div>
''' + source[card_start:]
            break
    if source == original:
        raise SystemExit("APP_EDIT_INSERT_MARKER_NOT_FOUND")
    return save_if_changed(EDIT, original, source, "voice_message_switch_view")


def main() -> None:
    changed_db = patch_database()
    changed_api = patch_api()
    changed_base = patch_api_base_controller()
    changed_admin = patch_admin_controller()
    changed_edit = patch_edit()
    changed = changed_db or changed_api or changed_base or changed_admin or changed_edit
    print("PATCHED_VOICE_MESSAGE_SWITCH" if changed else "VOICE_MESSAGE_SWITCH_ALREADY_UP_TO_DATE")


if __name__ == "__main__":
    main()
