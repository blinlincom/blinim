#!/usr/bin/env python3
"""Patch backend app scope, admin IM user binding, app notifications and default IM groups."""

from datetime import datetime
from pathlib import Path
import os
import shutil
import subprocess


ROOT = Path("/www/wwwroot/blinlin")
ADMIN_SCOPE_PATCH = Path("/tmp/patch_admin_app_scope.py")
BACKEND = ROOT / "application/admin/controller/Backend.php"
LOGIN = ROOT / "application/admin/controller/Login.php"
ADMIN = ROOT / "application/admin/controller/Admin.php"
APP = ROOT / "application/admin/controller/App.php"
USER = ROOT / "application/admin/controller/User.php"
IM = ROOT / "application/admin/controller/Im.php"
API = ROOT / "application/api/controller/Api.php"
BASE = ROOT / "application/api/controller/BaseController.php"
ADMIN_INDEX = ROOT / "application/admin/view/admin/index.html"
APP_EDIT = ROOT / "application/admin/view/app/edit.html"


def backup(path, suffix):
    target = path.with_name(
        f"{path.name}.bak_{suffix}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    shutil.copy2(path, target)
    return target


def save_if_changed(path, original, source, suffix):
    if source == original:
        return False
    print("PATCH_BACKUP", backup(path, suffix))
    path.write_text(source)
    print("PATCHED", path)
    return True


def replace_once(source, old, new, label):
    if new in source:
        return source
    if old not in source:
        raise SystemExit(f"MARKER_NOT_FOUND:{label}")
    return source.replace(old, new, 1)


def insert_before_last_class_brace(source, block, marker):
    if marker in source:
        return source
    pos = source.rfind("\n}")
    if pos == -1:
        raise SystemExit(f"CLASS_END_NOT_FOUND:{marker}")
    return source[:pos] + "\n" + block + source[pos:]


def db_config():
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


def mysql(args):
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
            *args,
        ],
        universal_newlines=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        check=False,
    )


def run_admin_scope_patch():
    if not ADMIN_SCOPE_PATCH.exists():
        raise SystemExit("ADMIN_SCOPE_PATCH_MISSING")
    result = subprocess.run(["python3", str(ADMIN_SCOPE_PATCH)], universal_newlines=True)
    if result.returncode != 0:
        raise SystemExit(result.returncode)


def patch_database():
    ddl = [
        "CREATE TABLE IF NOT EXISTS `mr_im_groups` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `group_no` varchar(64) NOT NULL DEFAULT '', `name` varchar(100) NOT NULL DEFAULT '', `avatar` varchar(500) NOT NULL DEFAULT '', `notice` varchar(1000) NOT NULL DEFAULT '', `owner_id` int(11) NOT NULL DEFAULT 0, `member_count` int(11) NOT NULL DEFAULT 0, `mute_all` tinyint(1) NOT NULL DEFAULT 0, `status` tinyint(1) NOT NULL DEFAULT 1, `default_group` tinyint(1) NOT NULL DEFAULT 0, `create_time` datetime DEFAULT NULL, `update_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), UNIQUE KEY `uk_group_no` (`group_no`), KEY `idx_app_default` (`appid`,`default_group`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
        "CREATE TABLE IF NOT EXISTS `mr_im_group_members` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `group_id` int(11) NOT NULL DEFAULT 0, `user_id` int(11) NOT NULL DEFAULT 0, `role` tinyint(1) NOT NULL DEFAULT 0, `nickname` varchar(100) NOT NULL DEFAULT '', `mute_until` datetime DEFAULT NULL, `status` tinyint(1) NOT NULL DEFAULT 1, `create_time` datetime DEFAULT NULL, `update_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), UNIQUE KEY `uk_group_user` (`group_id`,`user_id`), KEY `idx_app_user` (`appid`,`user_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
        "CREATE TABLE IF NOT EXISTS `mr_im_group_messages` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `group_id` int(11) NOT NULL DEFAULT 0, `sender_id` int(11) NOT NULL DEFAULT 0, `message_type` int(11) NOT NULL DEFAULT 0, `content` text, `payload` mediumtext, `client_msg_no` varchar(128) NOT NULL DEFAULT '', `create_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), KEY `idx_group_id` (`group_id`), KEY `idx_create_time` (`create_time`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
    ]
    for sql in ddl:
        run = mysql(["-e", sql])
        if run.returncode != 0:
            raise SystemExit(run.stderr.strip() or "GROUP_TABLE_DDL_FAILED")
    columns = {
        "mr_im_groups": {
            "avatar": "ALTER TABLE `mr_im_groups` ADD COLUMN `avatar` varchar(500) NOT NULL DEFAULT '' AFTER `name`",
            "notice": "ALTER TABLE `mr_im_groups` ADD COLUMN `notice` varchar(1000) NOT NULL DEFAULT '' AFTER `avatar`",
            "owner_id": "ALTER TABLE `mr_im_groups` ADD COLUMN `owner_id` int(11) NOT NULL DEFAULT 0 AFTER `notice`",
            "mute_all": "ALTER TABLE `mr_im_groups` ADD COLUMN `mute_all` tinyint(1) NOT NULL DEFAULT 0 AFTER `member_count`",
            "default_group": "ALTER TABLE `mr_im_groups` ADD COLUMN `default_group` tinyint(1) NOT NULL DEFAULT 0 AFTER `status`",
            "update_time": "ALTER TABLE `mr_im_groups` ADD COLUMN `update_time` datetime DEFAULT NULL",
        },
        "mr_im_group_members": {
            "role": "ALTER TABLE `mr_im_group_members` ADD COLUMN `role` tinyint(1) NOT NULL DEFAULT 0 AFTER `user_id`",
            "nickname": "ALTER TABLE `mr_im_group_members` ADD COLUMN `nickname` varchar(100) NOT NULL DEFAULT '' AFTER `role`",
            "mute_until": "ALTER TABLE `mr_im_group_members` ADD COLUMN `mute_until` datetime DEFAULT NULL AFTER `nickname`",
            "update_time": "ALTER TABLE `mr_im_group_members` ADD COLUMN `update_time` datetime DEFAULT NULL",
        },
        "mr_im_group_messages": {
            "payload": "ALTER TABLE `mr_im_group_messages` ADD COLUMN `payload` mediumtext NULL AFTER `content`",
            "client_msg_no": "ALTER TABLE `mr_im_group_messages` ADD COLUMN `client_msg_no` varchar(128) NOT NULL DEFAULT '' AFTER `payload`",
        },
    }
    for table, table_columns in columns.items():
        for column, sql in table_columns.items():
            check = mysql(["-Nse", f"SHOW COLUMNS FROM `{table}` LIKE '{column}'"])
            if check.returncode != 0:
                raise SystemExit(check.stderr.strip() or f"MYSQL_CHECK_FAILED:{table}.{column}")
            if check.stdout.strip():
                continue
            run = mysql(["-e", sql])
            if run.returncode != 0:
                raise SystemExit(run.stderr.strip() or f"MYSQL_ALTER_FAILED:{table}.{column}")
            print("DB_ADDED", table, column)


def patch_base_controller():
    source = BASE.read_text(errors="ignore")
    original = source
    source = replace_once(
        source,
        """            if (!isset($result["im_configuration"]["voice_message_switch"])) {
                $result["im_configuration"]["voice_message_switch"] = "0";
            }""",
        """            $imDefaults = [
                "voice_message_switch" => "0",
                "admin_app_message_switch" => "0",
                "default_group_switch" => "0",
                "default_group_join_switch" => "0",
                "default_group_id" => "0",
                "default_group_name" => "",
                "default_group_avatar" => "",
                "default_group_notice" => "",
                "default_group_owner_id" => "0",
            ];
            $result["im_configuration"] = array_merge($imDefaults, $result["im_configuration"]);
            if (!isset($result["im_configuration"]["voice_message_switch"])) {
                $result["im_configuration"]["voice_message_switch"] = "0";
            }""",
        "base_im_defaults",
    )
    save_if_changed(BASE, original, source, "default_group_base")


def patch_app_controller():
    source = APP.read_text(errors="ignore")
    original = source
    source = source.replace(
        '"im_configuration" => \'{"voice_message_switch":"0"}\',',
        '"im_configuration" => \'{"voice_message_switch":"0","admin_app_message_switch":"0","default_group_switch":"0","default_group_join_switch":"0","default_group_id":"0","default_group_name":"","default_group_avatar":"","default_group_notice":"","default_group_owner_id":"0"}\',',
    )
    source = replace_once(
        source,
        """                "announcement_configuration" => json_encode($announcement_configuration, JSON_UNESCAPED_UNICODE),
                "im_configuration" => json_encode(array("voice_message_switch" => isset($data["voice_message_switch"]) ? intval($data["voice_message_switch"]) : 1), JSON_UNESCAPED_UNICODE),
                "forum_configuration" => json_encode($forum_configuration, JSON_UNESCAPED_UNICODE),""",
        """                "announcement_configuration" => json_encode($announcement_configuration, JSON_UNESCAPED_UNICODE),
                "im_configuration" => json_encode([
                    "voice_message_switch" => isset($data["voice_message_switch"]) ? intval($data["voice_message_switch"]) : 1,
                    "admin_app_message_switch" => isset($data["admin_app_message_switch"]) ? intval($data["admin_app_message_switch"]) : 1,
                    "default_group_switch" => isset($data["default_group_switch"]) ? intval($data["default_group_switch"]) : 1,
                    "default_group_join_switch" => isset($data["default_group_join_switch"]) ? intval($data["default_group_join_switch"]) : 1,
                    "default_group_id" => intval(isset($data["default_group_id"]) ? $data["default_group_id"] : 0),
                    "default_group_name" => trim(strval(isset($data["default_group_name"]) ? $data["default_group_name"] : "")),
                    "default_group_avatar" => trim(strval(isset($data["default_group_avatar"]) ? $data["default_group_avatar"] : "")),
                    "default_group_notice" => trim(strval(isset($data["default_group_notice"]) ? $data["default_group_notice"] : "")),
                    "default_group_owner_id" => intval(isset($data["default_group_owner_id"]) ? $data["default_group_owner_id"] : 0),
                ], JSON_UNESCAPED_UNICODE),
                "forum_configuration" => json_encode($forum_configuration, JSON_UNESCAPED_UNICODE),""",
        "app_save_im_config",
    )
    source = replace_once(
        source,
        """            $update_data = [
                "appname" => $data["appname"],""",
        """            $defaultGroupId = intval(isset($data["default_group_id"]) ? $data["default_group_id"] : 0);
            if ($defaultGroupId > 0) {
                $defaultGroup = Db::name("im_groups")->where("appid", intval($data["appid"]))->where("id", $defaultGroupId)->find();
                if (!$defaultGroup) return $this->error("默认群不属于该应用");
            }
            $defaultGroupOwnerId = intval(isset($data["default_group_owner_id"]) ? $data["default_group_owner_id"] : 0);
            if ($defaultGroupOwnerId > 0) {
                $ownerUser = Db::name("user")->where("appid", intval($data["appid"]))->where("id", $defaultGroupOwnerId)->find();
                if (!$ownerUser) return $this->error("默认群主用户不属于该应用");
            }
            $update_data = [
                "appname" => $data["appname"],""",
        "app_validate_default_group",
    )
    source = replace_once(
        source,
        """                if (!isset($result["im_configuration"]["voice_message_switch"])) {
                    $result["im_configuration"]["voice_message_switch"] = 0;
                }""",
        """                $imDefaults = [
                    "voice_message_switch" => 0,
                    "admin_app_message_switch" => 0,
                    "default_group_switch" => 0,
                    "default_group_join_switch" => 0,
                    "default_group_id" => 0,
                    "default_group_name" => "",
                    "default_group_avatar" => "",
                    "default_group_notice" => "",
                    "default_group_owner_id" => 0,
                ];
                $result["im_configuration"] = array_merge($imDefaults, $result["im_configuration"]);
                if (!isset($result["im_configuration"]["voice_message_switch"])) {
                    $result["im_configuration"]["voice_message_switch"] = 0;
                }""",
        "app_im_config_defaults",
    )
    source = replace_once(
        source,
        """        if ($data["title"] == "" || $data["content"] == "" || $data["appid"] == "") {
            return $this->error("请填写完整");
        }""",
        """        if ($data["title"] == "" || $data["content"] == "" || $data["appid"] == "") {
            return $this->error("请填写完整");
        }
        $appInfo = Db::name("app")->where("appid", intval($data["appid"]))->find();
        if (!$appInfo) return $this->error("应用不存在");
        $imConfig = isset($appInfo["im_configuration"]) && $appInfo["im_configuration"] ? json_decode($appInfo["im_configuration"], true) : [];
        if (!is_array($imConfig)) $imConfig = [];
        if (intval(isset($imConfig["admin_app_message_switch"]) ? $imConfig["admin_app_message_switch"] : 0) !== 0) {
            return $this->error("该应用已关闭后台发消息");
        }""",
        "app_message_switch_guard",
    )
    save_if_changed(APP, original, source, "default_group_app")


def patch_app_edit_view():
    source = APP_EDIT.read_text(errors="ignore")
    original = source
    source = replace_once(
        source,
        """                        <div class="blin-setting-row blin-voice-message-switch-card">
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
                        </div>""",
        """                        <div class="blin-setting-row blin-voice-message-switch-card">
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
                        </div>
                        <div class="blin-setting-row blin-admin-message-switch-card">
                            <div class="blin-setting-copy">
                                <span class="blin-setting-title">后台应用消息</span>
                                <small class="blin-setting-desc">开启后，管理员可在后台给该应用内用户发送消息通知。</small>
                            </div>
                            <div class="blin-segmented-switch" role="group" aria-label="后台应用消息">
                                <input type="radio" id="admin_app_message_switch_on" value="0" name="admin_app_message_switch" class="btn-check" autocomplete="off" {if $data.im_configuration.admin_app_message_switch==0} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-on" for="admin_app_message_switch_on"><i class="mdi mdi-check-circle-outline"></i>开启</label>
                                <input type="radio" id="admin_app_message_switch_off" value="1" name="admin_app_message_switch" class="btn-check" autocomplete="off" {if $data.im_configuration.admin_app_message_switch==1} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-off" for="admin_app_message_switch_off"><i class="mdi mdi-close-circle-outline"></i>关闭</label>
                            </div>
                        </div>
                        <div class="blin-setting-row blin-default-group-switch-card">
                            <div class="blin-setting-copy">
                                <span class="blin-setting-title">默认应用群</span>
                                <small class="blin-setting-desc">开启后，可为该应用维护一个默认官方群，客户端群聊列表会正常展示。</small>
                            </div>
                            <div class="blin-segmented-switch" role="group" aria-label="默认应用群">
                                <input type="radio" id="default_group_switch_on" value="0" name="default_group_switch" class="btn-check" autocomplete="off" {if $data.im_configuration.default_group_switch==0} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-on" for="default_group_switch_on"><i class="mdi mdi-check-circle-outline"></i>开启</label>
                                <input type="radio" id="default_group_switch_off" value="1" name="default_group_switch" class="btn-check" autocomplete="off" {if $data.im_configuration.default_group_switch==1} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-off" for="default_group_switch_off"><i class="mdi mdi-close-circle-outline"></i>关闭</label>
                            </div>
                        </div>
                        <div class="blin-setting-row blin-default-group-join-switch-card">
                            <div class="blin-setting-copy">
                                <span class="blin-setting-title">注册自动入群</span>
                                <small class="blin-setting-desc">开启后，新注册用户自动加入该应用默认群；关闭后只保留手动入群。</small>
                            </div>
                            <div class="blin-segmented-switch" role="group" aria-label="注册自动入群">
                                <input type="radio" id="default_group_join_switch_on" value="0" name="default_group_join_switch" class="btn-check" autocomplete="off" {if $data.im_configuration.default_group_join_switch==0} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-on" for="default_group_join_switch_on"><i class="mdi mdi-check-circle-outline"></i>开启</label>
                                <input type="radio" id="default_group_join_switch_off" value="1" name="default_group_join_switch" class="btn-check" autocomplete="off" {if $data.im_configuration.default_group_join_switch==1} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-off" for="default_group_join_switch_off"><i class="mdi mdi-close-circle-outline"></i>关闭</label>
                            </div>
                        </div>
                        <div class="row g-3 mt-1">
                            <div class="col-md-3">
                                <label class="form-label">默认群ID</label>
                                <input type="number" class="form-control" name="default_group_id" value="{$data.im_configuration.default_group_id}" placeholder="留空自动创建">
                            </div>
                            <div class="col-md-3">
                                <label class="form-label">默认群主用户ID</label>
                                <input type="number" class="form-control" name="default_group_owner_id" value="{$data.im_configuration.default_group_owner_id}" placeholder="0 表示系统群">
                            </div>
                            <div class="col-md-6">
                                <label class="form-label">默认群名称</label>
                                <input type="text" class="form-control" name="default_group_name" value="{$data.im_configuration.default_group_name}" placeholder="例如：官方交流群">
                            </div>
                            <div class="col-md-12 file-group">
                                <label class="form-label">默认群头像</label>
                                <div class="input-group">
                                    <input type="text" class="form-control file-value" value="{$data.im_configuration.default_group_avatar}" name="default_group_avatar" placeholder="默认群头像" />
                                    <input type="file" name="file" class="hidden" style="display: none;" />
                                    <button class="btn btn-default file-browser" type="button">上传图片</button>
                                </div>
                            </div>
                            <div class="col-md-12">
                                <label class="form-label">默认群公告</label>
                                <textarea class="form-control" name="default_group_notice" placeholder="请输入群公告" style="height: 90px;">{$data.im_configuration.default_group_notice}</textarea>
                            </div>
                        </div>""",
        "app_view_im_group_config",
    )
    save_if_changed(APP_EDIT, original, source, "default_group_app_view")


GROUP_API_BLOCK = r'''

    // blin-im-group-api: IM group API and default application group support.
    private function blinImConfig($key = null, $default = null)
    {
        $config = isset($this->app_info["im_configuration"]) && is_array($this->app_info["im_configuration"]) ? $this->app_info["im_configuration"] : [];
        if ($key === null) return $config;
        return isset($config[$key]) ? $config[$key] : $default;
    }

    private function blinFeatureOpen($key)
    {
        return intval($this->blinImConfig($key, 0)) === 0;
    }

    private function ensure_im_group_tables()
    {
        Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_groups` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `group_no` varchar(64) NOT NULL DEFAULT '', `name` varchar(100) NOT NULL DEFAULT '', `avatar` varchar(500) NOT NULL DEFAULT '', `notice` varchar(1000) NOT NULL DEFAULT '', `owner_id` int(11) NOT NULL DEFAULT 0, `member_count` int(11) NOT NULL DEFAULT 0, `mute_all` tinyint(1) NOT NULL DEFAULT 0, `status` tinyint(1) NOT NULL DEFAULT 1, `default_group` tinyint(1) NOT NULL DEFAULT 0, `create_time` datetime DEFAULT NULL, `update_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), UNIQUE KEY `uk_group_no` (`group_no`), KEY `idx_app_default` (`appid`,`default_group`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
        Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_group_members` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `group_id` int(11) NOT NULL DEFAULT 0, `user_id` int(11) NOT NULL DEFAULT 0, `role` tinyint(1) NOT NULL DEFAULT 0, `nickname` varchar(100) NOT NULL DEFAULT '', `mute_until` datetime DEFAULT NULL, `status` tinyint(1) NOT NULL DEFAULT 1, `create_time` datetime DEFAULT NULL, `update_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), UNIQUE KEY `uk_group_user` (`group_id`,`user_id`), KEY `idx_app_user` (`appid`,`user_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
        Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_group_messages` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `group_id` int(11) NOT NULL DEFAULT 0, `sender_id` int(11) NOT NULL DEFAULT 0, `message_type` int(11) NOT NULL DEFAULT 0, `content` text, `payload` mediumtext, `client_msg_no` varchar(128) NOT NULL DEFAULT '', `create_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), KEY `idx_group_id` (`group_id`), KEY `idx_create_time` (`create_time`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
    }

    private function im_group_user()
    {
        if (!$this->user_info || !isset($this->user_info["id"])) $this->json(401, "未登录");
        return $this->user_info;
    }

    private function im_group_role_name($role)
    {
        $role = intval($role);
        if ($role >= 2) return "owner";
        if ($role === 1) return "admin";
        return "member";
    }

    private function im_group_member($groupId, $userId)
    {
        return Db::name("im_group_members")->where("appid", $this->appid)->where("group_id", intval($groupId))->where("user_id", intval($userId))->where("status", 1)->find();
    }

    private function im_group_can_manage($groupId, $userId)
    {
        $m = $this->im_group_member($groupId, $userId);
        return $m && intval($m["role"]) >= 1;
    }

    private function im_group_is_owner($groupId, $userId)
    {
        $m = $this->im_group_member($groupId, $userId);
        return $m && intval($m["role"]) >= 2;
    }

    private function blinGroupMemberIds($raw)
    {
        if (is_array($raw)) $items = $raw;
        else $items = preg_split("/[,，\s]+/", trim(strval($raw)));
        $ids = [];
        foreach ($items as $item) {
            $id = intval($item);
            if ($id > 0) $ids[] = $id;
        }
        return array_values(array_unique($ids));
    }

    private function blinGroupMessageType($payload, $content)
    {
        $type = is_array($payload) && isset($payload["msg_type"]) ? strval($payload["msg_type"]) : "";
        if ($type === "image") return 1;
        if ($type === "video") return 3;
        if ($type === "file") return 4;
        if ($type === "voice") return 5;
        if ($type === "call" || strpos($type, "group_call") === 0) return 6;
        return 0;
    }

    private function blinNormalizeGroupPayload($payload, $group, $sender, $messageId, $content, $clientNo)
    {
        if (!is_array($payload)) $payload = [];
        if (!isset($payload["msg_type"]) || $payload["msg_type"] === "") $payload["msg_type"] = "text";
        if (!isset($payload["content"])) $payload["content"] = $content;
        $payload["message_id"] = $messageId;
        $payload["from_user_id"] = intval($sender["id"]);
        $payload["to_user_id"] = intval($group["id"]);
        $payload["from_uid"] = $this->appid . "_" . intval($sender["id"]);
        $payload["to_uid"] = $group["group_no"];
        $payload["group_id"] = intval($group["id"]);
        $payload["group_no"] = $group["group_no"];
        $payload["client_msg_no"] = $clientNo;
        $payload["create_time"] = date("Y-m-d H:i:s");
        return $payload;
    }

    private function blinDefaultGroup()
    {
        if (!$this->blinFeatureOpen("default_group_switch")) return null;
        $this->ensure_im_group_tables();
        $groupId = intval($this->blinImConfig("default_group_id", 0));
        $name = trim(strval($this->blinImConfig("default_group_name", "")));
        if ($name === "") $name = isset($this->app_info["appname"]) ? $this->app_info["appname"] . "官方交流群" : "官方交流群";
        $avatar = trim(strval($this->blinImConfig("default_group_avatar", "")));
        if ($avatar === "" && isset($this->app_info["appicon"])) $avatar = $this->app_info["appicon"];
        $notice = trim(strval($this->blinImConfig("default_group_notice", "")));
        $ownerId = intval($this->blinImConfig("default_group_owner_id", 0));
        $now = date("Y-m-d H:i:s");
        $group = null;
        if ($groupId > 0) {
            $group = Db::name("im_groups")->where("appid", $this->appid)->where("id", $groupId)->find();
        }
        if (!$group) {
            $group = Db::name("im_groups")->where("appid", $this->appid)->where("default_group", 1)->where("status", 1)->order("id", "asc")->find();
        }
        if (!$group) {
            $groupNo = "default_group_" . $this->appid . "_" . time() . "_" . mt_rand(1000, 9999);
            $newId = Db::name("im_groups")->insertGetId(["appid"=>$this->appid, "group_no"=>$groupNo, "name"=>$name, "avatar"=>$avatar, "notice"=>$notice, "owner_id"=>$ownerId, "member_count"=>0, "mute_all"=>0, "status"=>1, "default_group"=>1, "create_time"=>$now, "update_time"=>$now]);
            $group = Db::name("im_groups")->where("id", $newId)->find();
        } else {
            Db::name("im_groups")->where("id", $group["id"])->update(["name"=>$name, "avatar"=>$avatar, "notice"=>$notice, "owner_id"=>$ownerId, "default_group"=>1, "status"=>1, "update_time"=>$now]);
            $group = Db::name("im_groups")->where("id", $group["id"])->find();
        }
        if ($ownerId > 0) $this->blinAddUserToGroup($group, $ownerId, 2);
        return $group;
    }

    private function blinAddUserToGroup($group, $userId, $role = 0)
    {
        if (!$group || intval($userId) <= 0) return false;
        $user = Db::name("user")->where("appid", $this->appid)->where("id", intval($userId))->find();
        if (!$user) return false;
        $now = date("Y-m-d H:i:s");
        $row = Db::name("im_group_members")->where("group_id", intval($group["id"]))->where("user_id", intval($userId))->find();
        $data = ["appid"=>$this->appid, "group_id"=>intval($group["id"]), "user_id"=>intval($userId), "role"=>intval($role), "nickname"=>isset($user["nickname"]) ? $user["nickname"] : "", "status"=>1, "update_time"=>$now];
        if ($row) {
            if (intval($row["role"]) > intval($role)) unset($data["role"]);
            Db::name("im_group_members")->where("id", $row["id"])->update($data);
        } else {
            $data["create_time"] = $now;
            Db::name("im_group_members")->insert($data);
        }
        $count = Db::name("im_group_members")->where("group_id", intval($group["id"]))->where("status", 1)->count();
        Db::name("im_groups")->where("id", intval($group["id"]))->update(["member_count"=>$count, "update_time"=>$now]);
        return true;
    }

    private function blinAutoJoinDefaultGroup($userId)
    {
        try {
            if (!$this->blinFeatureOpen("default_group_switch")) return;
            if (!$this->blinFeatureOpen("default_group_join_switch")) return;
            $group = $this->blinDefaultGroup();
            if ($group) $this->blinAddUserToGroup($group, intval($userId), 0);
        } catch (\Exception $e) {
        }
    }

    public function create_im_group()
    {
        $rule = ["usertoken|用户token" => "require", "name|群名称" => "require"];
        $data = input();
        $validate = new Validate($rule);
        if (!$validate->check($data)) $this->json(0, $validate->getError());
        $user = $this->im_group_user();
        $this->ensure_im_group_tables();
        $memberIds = $this->blinGroupMemberIds(isset($data["member_ids"]) ? $data["member_ids"] : input("user_ids"));
        $validUsers = [];
        if ($memberIds) {
            $validUsers = Db::name("user")->where("appid", $this->appid)->whereIn("id", $memberIds)->column("id");
        }
        $now = date("Y-m-d H:i:s");
        $groupNo = "group_" . $this->appid . "_" . time() . "_" . mt_rand(1000, 9999);
        $groupId = Db::name("im_groups")->insertGetId(["appid"=>$this->appid, "group_no"=>$groupNo, "name"=>trim(strval($data["name"])), "avatar"=>trim(strval(isset($data["avatar"]) ? $data["avatar"] : "")), "notice"=>trim(strval(isset($data["notice"]) ? $data["notice"] : "")), "owner_id"=>intval($user["id"]), "member_count"=>0, "status"=>1, "default_group"=>0, "create_time"=>$now, "update_time"=>$now]);
        $group = Db::name("im_groups")->where("id", $groupId)->find();
        $this->blinAddUserToGroup($group, intval($user["id"]), 2);
        foreach ($validUsers as $uid) $this->blinAddUserToGroup($group, intval($uid), 0);
        $group = Db::name("im_groups")->where("id", $groupId)->find();
        $group["group_id"] = intval($group["id"]);
        $group["my_role"] = "owner";
        $this->json(1, "创建成功", $group);
    }

    public function get_im_group_list()
    {
        $user = $this->im_group_user();
        $this->ensure_im_group_tables();
        if ($this->blinFeatureOpen("default_group_switch")) {
            $group = $this->blinDefaultGroup();
            if ($group && $this->blinFeatureOpen("default_group_join_switch")) $this->blinAddUserToGroup($group, intval($user["id"]), 0);
        }
        $rows = Db::name("im_group_members")->alias("m")->join("im_groups g", "g.id=m.group_id")->where("m.appid", $this->appid)->where("m.user_id", intval($user["id"]))->where("m.status", 1)->where("g.status", 1)->field("g.id,g.id as group_id,g.group_no,g.name,g.avatar,g.notice,g.owner_id,g.member_count,g.default_group,g.update_time,m.role")->order("g.default_group desc,g.update_time desc,g.id desc")->select();
        foreach ($rows as $k=>$v) $rows[$k]["my_role"] = $this->im_group_role_name($v["role"]);
        $this->json(1, "success", ["list"=>$rows]);
    }

    public function send_im_group_message()
    {
        $rule = ["usertoken|用户token" => "require", "group_id|群ID" => "require|number"];
        $data = input();
        $validate = new Validate($rule);
        if (!$validate->check($data)) $this->json(0, $validate->getError());
        $user = $this->im_group_user();
        $this->ensure_im_group_tables();
        $groupId = intval($data["group_id"]);
        $member = $this->im_group_member($groupId, intval($user["id"]));
        if (!$member) $this->json(0, "你不在该群聊中");
        $group = Db::name("im_groups")->where("appid", $this->appid)->where("id", $groupId)->where("status", 1)->find();
        if (!$group) $this->json(0, "群聊不存在");
        if (intval($group["mute_all"]) === 1 && intval($member["role"]) < 1) $this->json(0, "当前群聊已全员禁言");
        $payload = [];
        $rawPayload = input("im_payload") ?: input("payload");
        if ($rawPayload) {
            $decoded = json_decode(strval($rawPayload), true);
            if (is_array($decoded)) $payload = $decoded;
        }
        $content = isset($data["content"]) ? strval($data["content"]) : "";
        if ($content === "" && isset($payload["content"])) {
            $content = is_array($payload["content"]) ? json_encode($payload["content"], JSON_UNESCAPED_UNICODE) : strval($payload["content"]);
        }
        $clientNo = isset($payload["client_msg_no"]) ? strval($payload["client_msg_no"]) : ("group_msg_" . $groupId . "_" . time() . "_" . mt_rand(1000,9999));
        $messageType = $this->blinGroupMessageType($payload, $content);
        $messageId = Db::name("im_group_messages")->insertGetId(["appid"=>$this->appid, "group_id"=>$groupId, "sender_id"=>intval($user["id"]), "message_type"=>$messageType, "content"=>$content, "payload"=>"", "client_msg_no"=>$clientNo, "create_time"=>date("Y-m-d H:i:s")]);
        $payload = $this->blinNormalizeGroupPayload($payload, $group, $user, $messageId, $content, $clientNo);
        Db::name("im_group_messages")->where("id", $messageId)->update(["payload"=>json_encode($payload, JSON_UNESCAPED_UNICODE)]);
        Db::name("im_groups")->where("id", $groupId)->update(["update_time"=>date("Y-m-d H:i:s")]);
        try {
            if (config("wukongim.enable")) {
                $wkim = new \app\common\tool\WukongIM();
                $wkim->sendMessage($this->appid . "_" . intval($user["id"]), $group["group_no"], 2, $payload, $clientNo, ["no_persist"=>0,"red_dot"=>1,"sync_once"=>0]);
            }
        } catch (\Exception $e) {
        }
        $this->json(1, "发送成功", ["message_id"=>$messageId, "payload"=>$payload]);
    }

    public function get_im_group_chat_log()
    {
        $rule = ["usertoken|用户token" => "require", "group_id|群ID" => "require|number"];
        $data = input();
        $validate = new Validate($rule);
        if (!$validate->check($data)) $this->json(0, $validate->getError());
        $user = $this->im_group_user();
        $this->ensure_im_group_tables();
        $groupId = intval($data["group_id"]);
        if (!$this->im_group_member($groupId, intval($user["id"]))) $this->json(0, "你不在该群聊中");
        $limit = intval(input("limit") ?: $this->limit);
        if ($limit <= 0 || $limit > 100) $limit = 30;
        $page = intval(input("page") ?: $this->page);
        if ($page <= 0) $page = 1;
        $offset = ($page - 1) * $limit;
        $rows = Db::name("im_group_messages")->where("appid", $this->appid)->where("group_id", $groupId)->order("id desc")->limit($offset, $limit)->select();
        $list = [];
        foreach ($rows as $r) {
            $payload = $r["payload"];
            $list[] = ["message"=>["id"=>$r["id"], "sender_id"=>$r["sender_id"], "receiver_id"=>$groupId, "message_type"=>$r["message_type"], "content"=>$r["content"], "im_payload"=>$payload, "create_time"=>$r["create_time"]]];
        }
        $count = Db::name("im_group_messages")->where("appid", $this->appid)->where("group_id", $groupId)->count();
        $this->json(1, "success", ["list"=>$list, "pagecount"=>ceil($count / $limit) == 0 ? 1 : ceil($count / $limit), "current_number"=>$page]);
    }

    public function get_im_group_info()
    {
        $rule = ["usertoken|用户token" => "require", "group_id|群ID" => "require|number"];
        $data = input();
        $validate = new Validate($rule);
        if (!$validate->check($data)) $this->json(0, $validate->getError());
        $user = $this->im_group_user();
        $this->ensure_im_group_tables();
        $groupId = intval($data["group_id"]);
        $member = $this->im_group_member($groupId, intval($user["id"]));
        if (!$member) $this->json(0, "你不在该群聊中");
        $group = Db::name("im_groups")->where("appid", $this->appid)->where("id", $groupId)->where("status", 1)->find();
        if (!$group) $this->json(0, "群聊不存在");
        $group["group_id"] = intval($group["id"]);
        $group["my_role"] = $this->im_group_role_name($member["role"]);
        $this->json(1, "success", $group);
    }

    public function get_im_group_members()
    {
        $rule = ["usertoken|用户token" => "require", "group_id|群ID" => "require|number"];
        $data = input();
        $validate = new Validate($rule);
        if (!$validate->check($data)) $this->json(0, $validate->getError());
        $user = $this->im_group_user();
        $this->ensure_im_group_tables();
        $groupId = intval($data["group_id"]);
        if (!$this->im_group_member($groupId, intval($user["id"]))) $this->json(0, "你不在该群聊中");
        $rows = Db::name("im_group_members")->alias("m")->join("user u", "u.id=m.user_id", "LEFT")->where("m.appid", $this->appid)->where("m.group_id", $groupId)->where("m.status", 1)->field("m.user_id,m.role,m.nickname,u.username,u.nickname as user_nickname,u.usertx")->order("m.role desc,m.id asc")->select();
        $list = [];
        foreach ($rows as $r) {
            $nick = $r["nickname"] ?: ($r["user_nickname"] ?: $r["username"]);
            $list[] = ["user_id"=>intval($r["user_id"]), "nickname"=>$nick, "avatar"=>isset($r["usertx"]) ? $r["usertx"] : "", "role"=>$this->im_group_role_name($r["role"])];
        }
        $this->json(1, "success", ["list"=>$list]);
    }

    public function update_im_group()
    {
        $rule = ["usertoken|用户token" => "require", "group_id|群ID" => "require|number"];
        $data = input();
        $validate = new Validate($rule);
        if (!$validate->check($data)) $this->json(0, $validate->getError());
        $user = $this->im_group_user();
        $this->ensure_im_group_tables();
        $groupId = intval($data["group_id"]);
        if (!$this->im_group_can_manage($groupId, intval($user["id"]))) $this->json(0, "没有群管理权限");
        $update = ["update_time"=>date("Y-m-d H:i:s")];
        if (isset($data["name"]) || isset($data["group_name"])) $update["name"] = trim(strval(isset($data["name"]) ? $data["name"] : $data["group_name"]));
        if (isset($data["avatar"]) || isset($data["group_avatar"])) $update["avatar"] = trim(strval(isset($data["avatar"]) ? $data["avatar"] : $data["group_avatar"]));
        if (isset($data["notice"])) $update["notice"] = trim(strval($data["notice"]));
        Db::name("im_groups")->where("appid", $this->appid)->where("id", $groupId)->update($update);
        $group = Db::name("im_groups")->where("appid", $this->appid)->where("id", $groupId)->find();
        $this->json(1, "更新成功", $group ?: []);
    }

    public function add_im_group_members()
    {
        $rule = ["usertoken|用户token" => "require", "group_id|群ID" => "require|number"];
        $data = input();
        $validate = new Validate($rule);
        if (!$validate->check($data)) $this->json(0, $validate->getError());
        $user = $this->im_group_user();
        $this->ensure_im_group_tables();
        $groupId = intval($data["group_id"]);
        if (!$this->im_group_can_manage($groupId, intval($user["id"]))) $this->json(0, "没有群管理权限");
        $group = Db::name("im_groups")->where("appid", $this->appid)->where("id", $groupId)->where("status", 1)->find();
        if (!$group) $this->json(0, "群聊不存在");
        $ids = $this->blinGroupMemberIds(isset($data["user_ids"]) ? $data["user_ids"] : input("member_ids"));
        if (!$ids) $this->json(0, "请选择成员");
        foreach ($ids as $uid) $this->blinAddUserToGroup($group, $uid, 0);
        $this->json(1, "已邀请成员");
    }

    public function remove_im_group_member()
    {
        $rule = ["usertoken|用户token" => "require", "group_id|群ID" => "require|number"];
        $data = input();
        $validate = new Validate($rule);
        if (!$validate->check($data)) $this->json(0, $validate->getError());
        $user = $this->im_group_user();
        $groupId = intval($data["group_id"]);
        $uid = intval(isset($data["user_id"]) ? $data["user_id"] : input("member_id"));
        if ($uid <= 0) $this->json(0, "请选择成员");
        if (!$this->im_group_can_manage($groupId, intval($user["id"]))) $this->json(0, "没有群管理权限");
        $target = $this->im_group_member($groupId, $uid);
        if (!$target) $this->json(0, "成员不存在");
        if (intval($target["role"]) >= 2) $this->json(0, "不能移除群主");
        Db::name("im_group_members")->where("group_id", $groupId)->where("user_id", $uid)->update(["status"=>0, "update_time"=>date("Y-m-d H:i:s")]);
        $count = Db::name("im_group_members")->where("group_id", $groupId)->where("status", 1)->count();
        Db::name("im_groups")->where("id", $groupId)->update(["member_count"=>$count, "update_time"=>date("Y-m-d H:i:s")]);
        $this->json(1, "已移除成员");
    }

    public function set_im_group_admin()
    {
        $rule = ["usertoken|用户token" => "require", "group_id|群ID" => "require|number"];
        $data = input();
        $validate = new Validate($rule);
        if (!$validate->check($data)) $this->json(0, $validate->getError());
        $user = $this->im_group_user();
        $groupId = intval($data["group_id"]);
        $uid = intval(isset($data["user_id"]) ? $data["user_id"] : input("member_id"));
        if ($uid <= 0) $this->json(0, "请选择成员");
        if (!$this->im_group_is_owner($groupId, intval($user["id"]))) $this->json(0, "只有群主可以设置管理员");
        $target = $this->im_group_member($groupId, $uid);
        if (!$target || intval($target["role"]) >= 2) $this->json(0, "成员不存在或不能修改群主");
        $admin = intval(input("admin")) === 1 || strval(input("role")) === "admin";
        Db::name("im_group_members")->where("group_id", $groupId)->where("user_id", $uid)->update(["role"=>$admin ? 1 : 0, "update_time"=>date("Y-m-d H:i:s")]);
        $this->json(1, $admin ? "已设为管理员" : "已取消管理员");
    }

    public function transfer_im_group()
    {
        $rule = ["usertoken|用户token" => "require", "group_id|群ID" => "require|number"];
        $data = input();
        $validate = new Validate($rule);
        if (!$validate->check($data)) $this->json(0, $validate->getError());
        $user = $this->im_group_user();
        $groupId = intval($data["group_id"]);
        $uid = intval(isset($data["user_id"]) ? $data["user_id"] : input("new_owner_id"));
        if (!$this->im_group_is_owner($groupId, intval($user["id"]))) $this->json(0, "只有群主可以转让");
        if (!$this->im_group_member($groupId, $uid)) $this->json(0, "新群主不在群内");
        Db::name("im_group_members")->where("group_id", $groupId)->where("user_id", intval($user["id"]))->update(["role"=>1, "update_time"=>date("Y-m-d H:i:s")]);
        Db::name("im_group_members")->where("group_id", $groupId)->where("user_id", $uid)->update(["role"=>2, "update_time"=>date("Y-m-d H:i:s")]);
        Db::name("im_groups")->where("id", $groupId)->update(["owner_id"=>$uid, "update_time"=>date("Y-m-d H:i:s")]);
        $this->json(1, "已转让群主");
    }

    public function leave_im_group()
    {
        $rule = ["usertoken|用户token" => "require", "group_id|群ID" => "require|number"];
        $data = input();
        $validate = new Validate($rule);
        if (!$validate->check($data)) $this->json(0, $validate->getError());
        $user = $this->im_group_user();
        $groupId = intval($data["group_id"]);
        if ($this->im_group_is_owner($groupId, intval($user["id"]))) $this->json(0, "群主请先转让或解散群");
        Db::name("im_group_members")->where("group_id", $groupId)->where("user_id", intval($user["id"]))->update(["status"=>0, "update_time"=>date("Y-m-d H:i:s")]);
        $count = Db::name("im_group_members")->where("group_id", $groupId)->where("status", 1)->count();
        Db::name("im_groups")->where("id", $groupId)->update(["member_count"=>$count, "update_time"=>date("Y-m-d H:i:s")]);
        $this->json(1, "已退出群聊");
    }

    public function dismiss_im_group()
    {
        $rule = ["usertoken|用户token" => "require", "group_id|群ID" => "require|number"];
        $data = input();
        $validate = new Validate($rule);
        if (!$validate->check($data)) $this->json(0, $validate->getError());
        $user = $this->im_group_user();
        $groupId = intval($data["group_id"]);
        if (!$this->im_group_is_owner($groupId, intval($user["id"]))) $this->json(0, "只有群主可以解散群");
        Db::name("im_groups")->where("appid", $this->appid)->where("id", $groupId)->update(["status"=>0, "update_time"=>date("Y-m-d H:i:s")]);
        Db::name("im_group_members")->where("group_id", $groupId)->update(["status"=>0, "update_time"=>date("Y-m-d H:i:s")]);
        $this->json(1, "已解散群聊");
    }
'''


def patch_api_controller():
    source = API.read_text(errors="ignore")
    original = source
    source = insert_before_last_class_brace(source, GROUP_API_BLOCK, "blin-im-group-api")
    if "blinAutoJoinDefaultGroup($user_id)" not in source:
        source = source.replace(
            '$user_id = Db::name("user")->insertGetId($add);',
            '$user_id = Db::name("user")->insertGetId($add);' + "\n            $this->blinAutoJoinDefaultGroup($user_id);",
        )
    save_if_changed(API, original, source, "default_group_api")


def main():
    run_admin_scope_patch()
    patch_database()
    patch_base_controller()
    patch_app_controller()
    patch_app_edit_view()
    patch_api_controller()


if __name__ == "__main__":
    main()
