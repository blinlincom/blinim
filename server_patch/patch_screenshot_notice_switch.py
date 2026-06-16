#!/usr/bin/env python3
"""Add app-level screenshot notice switch and per-group screenshot notice flag."""

from datetime import datetime
from pathlib import Path
import os
import re
import shutil
import subprocess


ROOT = Path("/www/wwwroot/blinlin")
APP = ROOT / "application/admin/controller/App.php"
BASE = ROOT / "application/api/controller/BaseController.php"
API = ROOT / "application/api/controller/Api.php"
APP_EDIT = ROOT / "application/admin/view/app/edit.html"


def backup(path: Path, suffix: str) -> Path:
    target = path.with_name(f"{path.name}.bak_{suffix}_{datetime.now().strftime('%Y%m%d%H%M%S')}")
    shutil.copy2(path, target)
    return target


def save(path: Path, original: str, source: str, suffix: str) -> bool:
    if source == original:
        return False
    print("PATCH_BACKUP", backup(path, suffix))
    path.write_text(source)
    print("PATCHED", path)
    return True


def db_config() -> dict:
    values = {
        "hostname": "127.0.0.1",
        "database": "blinlin",
        "username": "root",
        "password": "",
        "hostport": "3306",
    }
    env_path = ROOT / ".env"
    section = ""
    for raw in env_path.read_text(errors="ignore").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith(";"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip().lower()
            continue
        if section != "database" or "=" not in line:
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip().lower()
        value = value.strip().strip('"').strip("'")
        if key in values:
            values[key] = value
    return values


def mysql(sql: str) -> subprocess.CompletedProcess:
    config = db_config()
    env = os.environ.copy()
    env["MYSQL_PWD"] = config["password"]
    return subprocess.run(
        [
            "mysql",
            f"-h{config['hostname']}",
            f"-u{config['username']}",
            f"-P{config.get('hostport') or '3306'}",
            config["database"],
            "-e",
            sql,
        ],
        universal_newlines=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        check=False,
    )


def mysql_scalar(sql: str) -> str:
    config = db_config()
    env = os.environ.copy()
    env["MYSQL_PWD"] = config["password"]
    result = subprocess.run(
        [
            "mysql",
            f"-h{config['hostname']}",
            f"-u{config['username']}",
            f"-P{config.get('hostport') or '3306'}",
            config["database"],
            "-Nse",
            sql,
        ],
        universal_newlines=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(result.stderr.strip() or "MYSQL_QUERY_FAILED")
    return result.stdout.strip()


def patch_database() -> bool:
    changed = False
    if not mysql_scalar("SHOW COLUMNS FROM `mr_app` LIKE 'im_configuration'"):
        run = mysql("ALTER TABLE `mr_app` ADD COLUMN `im_configuration` text NULL")
        if run.returncode != 0:
            raise SystemExit(run.stderr.strip() or "ADD_IM_CONFIGURATION_FAILED")
        changed = True
    if not mysql_scalar("SHOW COLUMNS FROM `mr_im_groups` LIKE 'screenshot_notify_enabled'"):
        run = mysql(
            "ALTER TABLE `mr_im_groups` ADD COLUMN `screenshot_notify_enabled` tinyint(1) NOT NULL DEFAULT 0"
        )
        if run.returncode != 0:
            raise SystemExit(run.stderr.strip() or "ADD_SCREENSHOT_GROUP_COLUMN_FAILED")
        changed = True
    run = mysql(
        """UPDATE `mr_app`
SET `im_configuration` = JSON_SET(
    CASE
        WHEN JSON_VALID(COALESCE(NULLIF(`im_configuration`, ''), '{}')) = 1
        THEN COALESCE(NULLIF(`im_configuration`, ''), '{}')
        ELSE '{}'
    END,
    '$.screenshot_notice_switch',
    COALESCE(JSON_UNQUOTE(JSON_EXTRACT(
        CASE
            WHEN JSON_VALID(COALESCE(NULLIF(`im_configuration`, ''), '{}')) = 1
            THEN COALESCE(NULLIF(`im_configuration`, ''), '{}')
            ELSE '{}'
        END,
        '$.screenshot_notice_switch'
    )), '1')
)"""
    )
    if run.returncode != 0:
        raise SystemExit(run.stderr.strip() or "PATCH_APP_IM_CONFIGURATION_FAILED")
    return changed


def patch_base_controller() -> bool:
    source = BASE.read_text(errors="ignore")
    original = source
    if "screenshot_notice_switch" in source:
        return False
    source = re.sub(
        r'("voice_message_switch"\s*=>\s*["\']0["\'],)',
        r'\1\n                "screenshot_notice_switch" => "1",',
        source,
        count=1,
    )
    source = re.sub(
        r'(\$result\["im_configuration"\]\["voice_message_switch"\]\s*=\s*["\']0["\'];)',
        r'\1\n            if (!isset($result["im_configuration"]["screenshot_notice_switch"])) {\n                $result["im_configuration"]["screenshot_notice_switch"] = "1";\n            }',
        source,
        count=1,
    )
    return save(BASE, original, source, "screenshot_notice_base")


def _add_key_to_json_literal(source: str) -> str:
    if "screenshot_notice_switch" in source:
        return source
    return re.sub(
        r"(\"im_configuration\"\s*=>\s*'\{)([^']*)(\}'\s*,)",
        lambda m: (
            m.group(0)
            if "screenshot_notice_switch" in m.group(2)
            else f'{m.group(1)}{m.group(2)},"screenshot_notice_switch":"1"{m.group(3)}'
        ),
        source,
        count=1,
    )


def patch_app_controller() -> bool:
    source = APP.read_text(errors="ignore")
    original = source
    source = _add_key_to_json_literal(source)
    if '"screenshot_notice_switch" => isset($data["screenshot_notice_switch"])' not in source:
        source = re.sub(
            r'("voice_message_switch"\s*=>\s*isset\(\$data\["voice_message_switch"\]\)\s*\?\s*intval\(\$data\["voice_message_switch"\]\)\s*:\s*1,\n)',
            r'\1                    "screenshot_notice_switch" => isset($data["screenshot_notice_switch"]) ? intval($data["screenshot_notice_switch"]) : 1,\n',
            source,
            count=1,
        )
    if '"screenshot_notice_switch" => 1' not in source:
        source = re.sub(
            r'("voice_message_switch"\s*=>\s*0,\n)',
            r'\1                    "screenshot_notice_switch" => 1,\n',
            source,
            count=1,
        )
    return save(APP, original, source, "screenshot_notice_app")


def patch_app_edit() -> bool:
    source = APP_EDIT.read_text(errors="ignore")
    original = source
    if "screenshot_notice_switch" in source:
        return False
    block = '''                        <div class="blin-setting-row blin-screenshot-notice-switch-card">
                            <div class="blin-setting-copy">
                                <span class="blin-setting-title">截屏提醒</span>
                                <small class="blin-setting-desc">开启后，客户端可在个人聊天和群聊中发送截屏提醒；群聊还需群主单独开启。</small>
                            </div>
                            <div class="blin-segmented-switch" role="group" aria-label="截屏提醒">
                                <input type="radio" id="screenshot_notice_switch_on" value="0" name="screenshot_notice_switch" class="btn-check" autocomplete="off" {if $data.im_configuration.screenshot_notice_switch==0} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-on" for="screenshot_notice_switch_on"><i class="mdi mdi-check-circle-outline"></i>开启</label>
                                <input type="radio" id="screenshot_notice_switch_off" value="1" name="screenshot_notice_switch" class="btn-check" autocomplete="off" {if $data.im_configuration.screenshot_notice_switch==1} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-off" for="screenshot_notice_switch_off"><i class="mdi mdi-close-circle-outline"></i>关闭</label>
                            </div>
                        </div>
'''
    marker = '                        <div class="blin-setting-row blin-voice-message-switch-card">'
    if marker in source:
        source = source.replace(marker, block + marker, 1)
    else:
        card_marker = '<div class="card-title">即时通讯配置</div>'
        pos = source.find(card_marker)
        if pos < 0:
            raise SystemExit("APP_EDIT_IM_CARD_MARKER_NOT_FOUND")
        body_pos = source.find('<div class="card-body">', pos)
        if body_pos < 0:
            raise SystemExit("APP_EDIT_CARD_BODY_MARKER_NOT_FOUND")
        insert_at = source.find("\n", body_pos) + 1
        source = source[:insert_at] + block + source[insert_at:]
    return save(APP_EDIT, original, source, "screenshot_notice_view")


def patch_api() -> bool:
    source = API.read_text(errors="ignore")
    original = source
    if "screenshot_notify_enabled" not in source:
        source = source.replace(
            '$this->blinAddColumnIfMissing(\'mr_im_groups\', \'notice_pinned\', "ALTER TABLE `mr_im_groups` ADD COLUMN `notice_pinned` tinyint(1) NOT NULL DEFAULT 1 AFTER `admin_notice_enabled`");',
            '$this->blinAddColumnIfMissing(\'mr_im_groups\', \'notice_pinned\', "ALTER TABLE `mr_im_groups` ADD COLUMN `notice_pinned` tinyint(1) NOT NULL DEFAULT 1 AFTER `admin_notice_enabled`");\n        $this->blinAddColumnIfMissing(\'mr_im_groups\', \'screenshot_notify_enabled\', "ALTER TABLE `mr_im_groups` ADD COLUMN `screenshot_notify_enabled` tinyint(1) NOT NULL DEFAULT 0 AFTER `notice_pinned`");',
        )
        source = source.replace(
            '$noticePinned = $this->blinGroupBoolValue($data, ["notice_pinned"]);',
            '$screenshotNotify = $this->blinGroupBoolValue($data, ["screenshot_notify_enabled", "screenshot_notice_enabled"]);\n        if ($screenshotNotify !== null) {\n            if (!$isOwner) $this->json(0, "只有群主可以设置截屏提醒");\n            $update["screenshot_notify_enabled"] = $screenshotNotify;\n        }\n        $noticePinned = $this->blinGroupBoolValue($data, ["notice_pinned"]);',
            1,
        )
        source = source.replace(
            '$this->im_group_add_column(\'mr_im_groups\', \'update_time\', "ALTER TABLE `mr_im_groups` ADD COLUMN `update_time` datetime DEFAULT NULL");',
            '$this->im_group_add_column(\'mr_im_groups\', \'update_time\', "ALTER TABLE `mr_im_groups` ADD COLUMN `update_time` datetime DEFAULT NULL");\n        $this->im_group_add_column(\'mr_im_groups\', \'screenshot_notify_enabled\', "ALTER TABLE `mr_im_groups` ADD COLUMN `screenshot_notify_enabled` tinyint(1) NOT NULL DEFAULT 0");',
            1,
        )
        source = source.replace(
            "if (isset($data['avatar']) || isset($data['group_avatar'])) { $update['avatar'] = trim(strval(isset($data['avatar']) ? $data['avatar'] : $data['group_avatar'])); }\n        if (count($update) <= 1)",
            "if (isset($data['avatar']) || isset($data['group_avatar'])) { $update['avatar'] = trim(strval(isset($data['avatar']) ? $data['avatar'] : $data['group_avatar'])); }\n        if (isset($data['screenshot_notify_enabled']) || isset($data['screenshot_notice_enabled'])) { $update['screenshot_notify_enabled'] = intval(isset($data['screenshot_notify_enabled']) ? $data['screenshot_notify_enabled'] : $data['screenshot_notice_enabled']) == 1 ? 1 : 0; }\n        if (count($update) <= 1)",
            1,
        )
    return save(API, original, source, "screenshot_notice_api")


def main() -> None:
    changed = patch_database()
    changed = patch_base_controller() or changed
    changed = patch_app_controller() or changed
    changed = patch_app_edit() or changed
    changed = patch_api() or changed
    print("PATCHED_SCREENSHOT_NOTICE" if changed else "SCREENSHOT_NOTICE_ALREADY_UP_TO_DATE")


if __name__ == "__main__":
    main()
