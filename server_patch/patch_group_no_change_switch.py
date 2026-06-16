#!/usr/bin/env python3
"""Add app-level group number change switch, payment flag and amount."""

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


def patch_database() -> bool:
    run = mysql(
        """UPDATE `mr_app`
SET `im_configuration` = JSON_SET(
    CASE
        WHEN JSON_VALID(COALESCE(NULLIF(`im_configuration`, ''), '{}')) = 1
        THEN COALESCE(NULLIF(`im_configuration`, ''), '{}')
        ELSE '{}'
    END,
    '$.group_no_change_enabled',
    COALESCE(JSON_UNQUOTE(JSON_EXTRACT(
        CASE WHEN JSON_VALID(COALESCE(NULLIF(`im_configuration`, ''), '{}')) = 1
             THEN COALESCE(NULLIF(`im_configuration`, ''), '{}') ELSE '{}' END,
        '$.group_no_change_enabled'
    )), '1'),
    '$.group_no_change_paid',
    COALESCE(JSON_UNQUOTE(JSON_EXTRACT(
        CASE WHEN JSON_VALID(COALESCE(NULLIF(`im_configuration`, ''), '{}')) = 1
             THEN COALESCE(NULLIF(`im_configuration`, ''), '{}') ELSE '{}' END,
        '$.group_no_change_paid'
    )), '1'),
    '$.group_no_change_amount',
    COALESCE(JSON_UNQUOTE(JSON_EXTRACT(
        CASE WHEN JSON_VALID(COALESCE(NULLIF(`im_configuration`, ''), '{}')) = 1
             THEN COALESCE(NULLIF(`im_configuration`, ''), '{}') ELSE '{}' END,
        '$.group_no_change_amount'
    )), '0')
)"""
    )
    if run.returncode != 0:
        raise SystemExit(run.stderr.strip() or "PATCH_GROUP_NO_CONFIG_DB_FAILED")
    return False


def add_json_literal_defaults(source: str) -> str:
    if "group_no_change_enabled" in source:
        return source
    return re.sub(
        r"(\"im_configuration\"\s*=>\s*'\{)([^']*)(\}'\s*,)",
        lambda m: (
            f'{m.group(1)}{m.group(2)},"group_no_change_enabled":"1",'
            f'"group_no_change_paid":"1","group_no_change_amount":"0"{m.group(3)}'
        ),
        source,
        count=1,
    )


def patch_app_controller() -> bool:
    source = APP.read_text(errors="ignore")
    original = source
    source = add_json_literal_defaults(source)
    if '"group_no_change_enabled" => isset($data["group_no_change_enabled"])' not in source:
        source = re.sub(
            r'("default_group_owner_id"\s*=>\s*intval\(isset\(\$data\["default_group_owner_id"\]\)\s*\?\s*\$data\["default_group_owner_id"\]\s*:\s*0\),\n)',
            r'\1                    "group_no_change_enabled" => isset($data["group_no_change_enabled"]) ? intval($data["group_no_change_enabled"]) : 1,\n                    "group_no_change_paid" => isset($data["group_no_change_paid"]) ? intval($data["group_no_change_paid"]) : 1,\n                    "group_no_change_amount" => isset($data["group_no_change_amount"]) ? floatval($data["group_no_change_amount"]) : 0,\n',
            source,
            count=1,
        )
    if '"group_no_change_enabled" => 1' not in source:
        source = re.sub(
            r'("default_group_owner_id"\s*=>\s*0,\n)',
            r'\1                    "group_no_change_enabled" => 1,\n                    "group_no_change_paid" => 1,\n                    "group_no_change_amount" => 0,\n',
            source,
            count=1,
        )
    return save(APP, original, source, "group_no_change_app")


def patch_base_controller() -> bool:
    source = BASE.read_text(errors="ignore")
    original = source
    if "group_no_change_enabled" in source:
        return False
    source = re.sub(
        r'("default_group_owner_id"\s*=>\s*["\']0["\'],\n)',
        r'\1                "group_no_change_enabled" => "1",\n                "group_no_change_paid" => "1",\n                "group_no_change_amount" => "0",\n',
        source,
        count=1,
    )
    return save(BASE, original, source, "group_no_change_base")


def patch_app_edit() -> bool:
    source = APP_EDIT.read_text(errors="ignore")
    original = source
    if "group_no_change_enabled" in source:
        return False
    block = '''                        <div class="blin-setting-row blin-group-no-change-switch-card">
                            <div class="blin-setting-copy">
                                <span class="blin-setting-title">群号修改</span>
                                <small class="blin-setting-desc">控制群主是否可以在客户端修改群号；开启后可选择是否付费。</small>
                            </div>
                            <div class="blin-segmented-switch" role="group" aria-label="群号修改">
                                <input type="radio" id="group_no_change_enabled_on" value="0" name="group_no_change_enabled" class="btn-check" autocomplete="off" {if $data.im_configuration.group_no_change_enabled==0} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-on" for="group_no_change_enabled_on"><i class="mdi mdi-check-circle-outline"></i>开启</label>
                                <input type="radio" id="group_no_change_enabled_off" value="1" name="group_no_change_enabled" class="btn-check" autocomplete="off" {if $data.im_configuration.group_no_change_enabled==1} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-off" for="group_no_change_enabled_off"><i class="mdi mdi-close-circle-outline"></i>关闭</label>
                            </div>
                        </div>
                        <div class="blin-setting-row blin-group-no-paid-switch-card">
                            <div class="blin-setting-copy">
                                <span class="blin-setting-title">群号付费修改</span>
                                <small class="blin-setting-desc">开启后，客户端会提示修改群号需要支付指定金额。</small>
                            </div>
                            <div class="blin-segmented-switch" role="group" aria-label="群号付费修改">
                                <input type="radio" id="group_no_change_paid_on" value="0" name="group_no_change_paid" class="btn-check" autocomplete="off" {if $data.im_configuration.group_no_change_paid==0} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-on" for="group_no_change_paid_on"><i class="mdi mdi-check-circle-outline"></i>开启</label>
                                <input type="radio" id="group_no_change_paid_off" value="1" name="group_no_change_paid" class="btn-check" autocomplete="off" {if $data.im_configuration.group_no_change_paid==1} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-off" for="group_no_change_paid_off"><i class="mdi mdi-close-circle-outline"></i>关闭</label>
                            </div>
                        </div>
                        <div class="row g-3 mt-1">
                            <div class="col-md-4">
                                <label class="form-label">群号修改金额</label>
                                <input type="number" step="0.01" min="0" class="form-control" name="group_no_change_amount" value="{$data.im_configuration.group_no_change_amount}" placeholder="0">
                            </div>
                        </div>
'''
    marker = '                        <div class="blin-setting-row blin-default-group-switch-card">'
    if marker in source:
        source = source.replace(marker, block + marker, 1)
    else:
        marker = '                        <div class="blin-setting-row blin-voice-message-switch-card">'
        if marker not in source:
            raise SystemExit("APP_EDIT_INSERT_MARKER_NOT_FOUND")
        source = source.replace(marker, block + marker, 1)
    return save(APP_EDIT, original, source, "group_no_change_view")


def patch_api() -> bool:
    source = API.read_text(errors="ignore")
    original = source
    if "blinGroupNoChangeConfig" not in source:
        helper = r'''
    private function blinGroupNoChangeConfig()
    {
        $config = isset($this->app_info["im_configuration"]) && is_array($this->app_info["im_configuration"]) ? $this->app_info["im_configuration"] : [];
        return [
            "group_no_change_enabled" => isset($config["group_no_change_enabled"]) ? intval($config["group_no_change_enabled"]) : 1,
            "group_no_change_paid" => isset($config["group_no_change_paid"]) ? intval($config["group_no_change_paid"]) : 1,
            "group_no_change_amount" => isset($config["group_no_change_amount"]) ? floatval($config["group_no_change_amount"]) : 0,
        ];
    }
'''
        marker = "\n    public function update_im_group()"
        if marker not in source:
            raise SystemExit("API_UPDATE_GROUP_MARKER_NOT_FOUND")
        source = source.replace(marker, "\n" + helper.rstrip() + "\n" + marker, 1)
    if '$group["config"] = $this->blinGroupNoChangeConfig();' not in source:
        source = re.sub(
            r'(\$group\["my_role"\]\s*=\s*\$this->im_group_role_name\(\$member\["role"\]\);\n)',
            r'\1        if (method_exists($this, "blinGroupNoChangeConfig")) $group["config"] = $this->blinGroupNoChangeConfig();\n',
            source,
            count=1,
        )
    if '后台未开启群号修改' not in source:
        source = source.replace(
            'if (!$isOwner) $this->json(0, "只有群主可以修改群号");',
            '$groupNoConfig = method_exists($this, "blinGroupNoChangeConfig") ? $this->blinGroupNoChangeConfig() : ["group_no_change_enabled"=>1];\n            if (intval(isset($groupNoConfig["group_no_change_enabled"]) ? $groupNoConfig["group_no_change_enabled"] : 1) !== 0) $this->json(0, "后台未开启群号修改");\n            if (!$isOwner) $this->json(0, "只有群主可以修改群号");',
            1,
        )
        source = source.replace(
            "if (!$isOwner) $this->json(0, \"只有群主可以修改群号\");",
            "$groupNoConfig = method_exists($this, \"blinGroupNoChangeConfig\") ? $this->blinGroupNoChangeConfig() : [\"group_no_change_enabled\"=>1];\n            if (intval(isset($groupNoConfig[\"group_no_change_enabled\"]) ? $groupNoConfig[\"group_no_change_enabled\"] : 1) !== 0) $this->json(0, \"后台未开启群号修改\");\n            if (!$isOwner) $this->json(0, \"只有群主可以修改群号\");",
            1,
        )
    return save(API, original, source, "group_no_change_api")


def main() -> None:
    changed = patch_database()
    changed = patch_app_controller() or changed
    changed = patch_base_controller() or changed
    changed = patch_app_edit() or changed
    changed = patch_api() or changed
    print("PATCHED_GROUP_NO_CHANGE_SWITCH" if changed else "GROUP_NO_CHANGE_SWITCH_ALREADY_UP_TO_DATE")


if __name__ == "__main__":
    main()
