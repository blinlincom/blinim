#!/usr/bin/env python3
"""Patch admin IM private messages and app default system-friend settings."""

from datetime import datetime
from pathlib import Path
import os
import shutil
import subprocess


ROOT = Path("/www/wwwroot/blinlin")
APP = ROOT / "application/admin/controller/App.php"
SYSTEM = ROOT / "application/admin/controller/System.php"
INDEX = ROOT / "application/admin/controller/Index.php"
API = ROOT / "application/api/controller/Api.php"
BASE = ROOT / "application/api/controller/BaseController.php"
APP_EDIT = ROOT / "application/admin/view/app/edit.html"
MESSAGE_VIEW = ROOT / "application/admin/view/system/message_notification.html"


def backup(path, suffix):
    target = path.with_name("%s.bak_%s_%s" % (path.name, suffix, datetime.now().strftime("%Y%m%d%H%M%S")))
    shutil.copy2(path, target)
    print("PATCH_BACKUP", target)


def save(path, original, source, suffix):
    if source == original:
        print("NO_CHANGE", path)
        return False
    backup(path, suffix)
    path.write_text(source)
    print("PATCHED", path)
    return True


def replace_once(source, old, new, label):
    if new in source:
        return source
    if old not in source:
        raise SystemExit("MARKER_NOT_FOUND:%s" % label)
    return source.replace(old, new, 1)


def replace_all(source, old, new, label, min_count=1):
    count = source.count(old)
    if count == 0:
        if new in source:
            return source
        raise SystemExit("MARKER_NOT_FOUND:%s" % label)
    if count < min_count:
        raise SystemExit("MARKER_COUNT_LOW:%s:%s" % (label, count))
    return source.replace(old, new)


def insert_before_last_class_brace(source, block, marker):
    if marker in source:
        return source
    pos = source.rfind("\n}")
    if pos == -1:
        raise SystemExit("CLASS_END_NOT_FOUND:%s" % marker)
    return source[:pos] + "\n" + block.rstrip() + "\n" + source[pos:]


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


def mysql(sql):
    config = db_config()
    env = os.environ.copy()
    env["MYSQL_PWD"] = config["password"]
    result = subprocess.run(
        [
            "mysql",
            "-h%s" % config["hostname"],
            "-u%s" % config["username"],
            "-P%s" % (config.get("hostport") or "3306"),
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
    if result.returncode != 0:
        raise SystemExit(result.stderr)
    if result.stdout.strip():
        print(result.stdout.strip())


def patch_database():
    try:
        mysql("ALTER TABLE `mr_message_notification` ADD COLUMN `is_admin` tinyint(1) NOT NULL DEFAULT 0")
    except SystemExit as exc:
        if "Duplicate column name" not in str(exc):
            raise
        print("DB_EXISTS is_admin")
    mysql(
        """UPDATE `mr_app`
SET `im_configuration` = JSON_SET(
    COALESCE(NULLIF(`im_configuration`, ''), '{}'),
    '$.system_friend_switch', COALESCE(JSON_UNQUOTE(JSON_EXTRACT(COALESCE(NULLIF(`im_configuration`, ''), '{}'), '$.system_friend_switch')), '0'),
    '$.system_friend_user_id', COALESCE(JSON_UNQUOTE(JSON_EXTRACT(COALESCE(NULLIF(`im_configuration`, ''), '{}'), '$.system_friend_user_id')), '0'),
    '$.system_friend_welcome', COALESCE(JSON_UNQUOTE(JSON_EXTRACT(COALESCE(NULLIF(`im_configuration`, ''), '{}'), '$.system_friend_welcome')), '欢迎使用，有问题可以直接联系我。')
)
WHERE JSON_VALID(COALESCE(NULLIF(`im_configuration`, ''), '{}')) = 1"""
    )


def patch_app_controller():
    source = APP.read_text()
    original = source
    source = replace_once(
        source,
        '"im_configuration" => \'{"voice_message_switch":"0","admin_app_message_switch":"0","default_group_switch":"0","default_group_join_switch":"0","default_group_id":"0","default_group_name":"","default_group_avatar":"","default_group_notice":"","default_group_owner_id":"0"}\',',
        '"im_configuration" => \'{"voice_message_switch":"0","admin_app_message_switch":"0","default_group_switch":"0","default_group_join_switch":"0","default_group_id":"0","default_group_name":"","default_group_avatar":"","default_group_notice":"","default_group_owner_id":"0","system_friend_switch":"0","system_friend_user_id":"0","system_friend_welcome":"欢迎使用，有问题可以直接联系我。"}\',',
        "app_add_im_defaults",
    )
    source = replace_once(
        source,
        '''                    "default_group_owner_id" => intval(isset($data["default_group_owner_id"]) ? $data["default_group_owner_id"] : 0),
                ], JSON_UNESCAPED_UNICODE),''',
        '''                    "default_group_owner_id" => intval(isset($data["default_group_owner_id"]) ? $data["default_group_owner_id"] : 0),
                    "system_friend_switch" => isset($data["system_friend_switch"]) ? intval($data["system_friend_switch"]) : 1,
                    "system_friend_user_id" => intval(isset($data["system_friend_user_id"]) ? $data["system_friend_user_id"] : 0),
                    "system_friend_welcome" => trim(strval(isset($data["system_friend_welcome"]) ? $data["system_friend_welcome"] : "")),
                ], JSON_UNESCAPED_UNICODE),''',
        "app_save_system_friend",
    )
    source = replace_once(
        source,
        '''            $defaultGroupOwnerId = intval(isset($data["default_group_owner_id"]) ? $data["default_group_owner_id"] : 0);
            if ($defaultGroupOwnerId > 0) {
                $ownerUser = Db::name("user")->where("appid", intval($data["appid"]))->where("id", $defaultGroupOwnerId)->find();
                if (!$ownerUser) return $this->error("默认群主用户不属于该应用");
            }
            $update_data = [''',
        '''            $defaultGroupOwnerId = intval(isset($data["default_group_owner_id"]) ? $data["default_group_owner_id"] : 0);
            if ($defaultGroupOwnerId > 0) {
                $ownerUser = Db::name("user")->where("appid", intval($data["appid"]))->where("id", $defaultGroupOwnerId)->find();
                if (!$ownerUser) return $this->error("默认群主用户不属于该应用");
            }
            $systemFriendUserId = intval(isset($data["system_friend_user_id"]) ? $data["system_friend_user_id"] : 0);
            if ($systemFriendUserId > 0) {
                $systemFriendUser = Db::name("user")->where("appid", intval($data["appid"]))->where("id", $systemFriendUserId)->find();
                if (!$systemFriendUser) return $this->error("系统好友用户不属于该应用");
            }
            $update_data = [''',
        "app_validate_system_friend_user",
    )
    source = replace_once(
        source,
        '''                    "default_group_owner_id" => 0,
                ];''',
        '''                    "default_group_owner_id" => 0,
                    "system_friend_switch" => 0,
                    "system_friend_user_id" => 0,
                    "system_friend_welcome" => "欢迎使用，有问题可以直接联系我。",
                ];''',
        "app_edit_im_defaults",
    )
    save(APP, original, source, "admin_system_friend_app")


def patch_base_controller():
    source = BASE.read_text()
    original = source
    source = replace_once(
        source,
        '''                "default_group_owner_id" => "0",
            ];''',
        '''                "default_group_owner_id" => "0",
                "system_friend_switch" => "0",
                "system_friend_user_id" => "0",
                "system_friend_welcome" => "欢迎使用，有问题可以直接联系我。",
            ];''',
        "base_im_defaults",
    )
    save(BASE, original, source, "system_friend_base")


def patch_app_edit_view():
    source = APP_EDIT.read_text()
    original = source
    insert = '''                        <div class="blin-setting-row blin-system-friend-switch-card">
                            <div class="blin-setting-copy">
                                <span class="blin-setting-title">注册自动加系统好友</span>
                                <small class="blin-setting-desc">开启后，新用户注册成功会自动和系统用户互为好友；后台也可用该系统号给用户发私聊。</small>
                            </div>
                            <div class="blin-segmented-switch" role="group" aria-label="注册自动加系统好友">
                                <input type="radio" id="system_friend_switch_on" value="0" name="system_friend_switch" class="btn-check" autocomplete="off" {if $data.im_configuration.system_friend_switch==0} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-on" for="system_friend_switch_on"><i class="mdi mdi-check-circle-outline"></i>开启</label>
                                <input type="radio" id="system_friend_switch_off" value="1" name="system_friend_switch" class="btn-check" autocomplete="off" {if $data.im_configuration.system_friend_switch==1} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-off" for="system_friend_switch_off"><i class="mdi mdi-close-circle-outline"></i>关闭</label>
                            </div>
                        </div>
                        <div class="row g-3 mt-1">
                            <div class="col-md-4">
                                <label class="form-label">系统好友用户ID</label>
                                <input type="number" class="form-control" name="system_friend_user_id" value="{$data.im_configuration.system_friend_user_id}" placeholder="0 表示自动创建系统号">
                            </div>
                            <div class="col-md-8">
                                <label class="form-label">系统好友欢迎语</label>
                                <input type="text" class="form-control" name="system_friend_welcome" value="{$data.im_configuration.system_friend_welcome}" placeholder="欢迎使用，有问题可以直接联系我。">
                            </div>
                        </div>
'''
    source = replace_once(
        source,
        '''                        <div class="row g-3 mt-1">
                            <div class="col-md-3">
                                <label class="form-label">默认群ID</label>''',
        insert + '''                        <div class="row g-3 mt-1">
                            <div class="col-md-3">
                                <label class="form-label">默认群ID</label>''',
        "app_edit_system_friend_fields",
    )
    save(APP_EDIT, original, source, "system_friend_app_view")


ADMIN_HELPERS = r'''
    // blin-admin-system-friend-message
    protected function blinAppImConfig($appid)
    {
        $app = Db::name("app")->where("appid", intval($appid))->find();
        if (!$app) return [];
        $config = isset($app["im_configuration"]) && $app["im_configuration"] ? json_decode($app["im_configuration"], true) : [];
        if (!is_array($config)) $config = [];
        return array_merge([
            "admin_app_message_switch" => 0,
            "system_friend_switch" => 0,
            "system_friend_user_id" => 0,
            "system_friend_welcome" => "欢迎使用，有问题可以直接联系我。",
        ], $config);
    }

    protected function blinEnsureFriendPair($appid, $userId, $friendId)
    {
        $appid = intval($appid);
        $userId = intval($userId);
        $friendId = intval($friendId);
        if ($appid <= 0 || $userId <= 0 || $friendId <= 0 || $userId === $friendId) return false;
        $u1 = Db::name("user")->where("appid", $appid)->where("id", $userId)->find();
        $u2 = Db::name("user")->where("appid", $appid)->where("id", $friendId)->find();
        if (!$u1 || !$u2) return false;
        $now = date("Y-m-d H:i:s");
        foreach ([[$userId, $friendId], [$friendId, $userId]] as $pair) {
            $row = Db::table("im_friends")->where("user_id", $pair[0])->where("friend_id", $pair[1])->find();
            if ($row) {
                Db::table("im_friends")->where("id", $row["id"])->update(["status"=>1, "updated_at"=>$now]);
            } else {
                Db::table("im_friends")->insert(["user_id"=>$pair[0], "friend_id"=>$pair[1], "status"=>1, "created_at"=>$now, "updated_at"=>$now]);
            }
        }
        return true;
    }

    protected function blinEnsureSystemUser($appid)
    {
        $appid = intval($appid);
        $this->blinRequireApp($appid);
        $config = $this->blinAppImConfig($appid);
        $userId = intval(isset($config["system_friend_user_id"]) ? $config["system_friend_user_id"] : 0);
        if ($userId > 0) {
            $user = Db::name("user")->where("appid", $appid)->where("id", $userId)->find();
            if ($user) return $user;
        }
        $username = "system_" . $appid;
        $user = Db::name("user")->where("appid", $appid)->where("username", $username)->find();
        if ($user) return $user;
        $app = Db::name("app")->where("appid", $appid)->find();
        $userinfo = $app && isset($app["userinfo_configuration"]) ? json_decode($app["userinfo_configuration"], true) : [];
        if (!is_array($userinfo)) $userinfo = [];
        $salt = getRandChar(6);
        $now = date("Y-m-d H:i:s");
        $avatar = isset($userinfo["usertx"]) && $userinfo["usertx"] ? $userinfo["usertx"] : "/static/images/initial_photo/user.png";
        $userId = Db::name("user")->insertGetId([
            "appid"=>$appid,
            "username"=>$username,
            "password"=>md5(getRandChar(16) . $salt),
            "salt"=>$salt,
            "usertx"=>$avatar,
            "nickname"=>"系统助手",
            "money"=>0,
            "integral"=>0,
            "viptime"=>0,
            "userbg"=>isset($userinfo["userbg"]) ? $userinfo["userbg"] : "",
            "signature"=>"官方系统账号",
            "create_time"=>$now,
            "register_ip"=>get_client_ip(),
            "invitecode"=>function_exists("enerate_invitation_code") ? enerate_invitation_code() : getRandChar(8),
        ]);
        $this->blinUpdateAppImConfig($appid, ["system_friend_user_id"=>$userId]);
        if (config("wukongim.enable")) {
            try { (new \app\common\tool\WukongIM())->addSystemUids([$appid . "_" . $userId]); } catch (\Exception $e) {}
        }
        return Db::name("user")->where("id", $userId)->find();
    }

    protected function blinUpdateAppImConfig($appid, $patch)
    {
        $app = Db::name("app")->where("appid", intval($appid))->find();
        if (!$app) return false;
        $config = isset($app["im_configuration"]) && $app["im_configuration"] ? json_decode($app["im_configuration"], true) : [];
        if (!is_array($config)) $config = [];
        $config = array_merge($config, $patch);
        Db::name("app")->where("appid", intval($appid))->update(["im_configuration"=>json_encode($config, JSON_UNESCAPED_UNICODE)]);
        return true;
    }

    protected function blinSendAdminPrivateMessage($appid, $fromUserId, $toUserId, $content, $title = "")
    {
        $appid = intval($appid);
        $fromUserId = intval($fromUserId);
        $toUserId = intval($toUserId);
        $content = trim(strval($content));
        if ($appid <= 0 || $fromUserId <= 0 || $toUserId <= 0 || $content === "") return 0;
        $from = Db::name("user")->where("appid", $appid)->where("id", $fromUserId)->find();
        $to = Db::name("user")->where("appid", $appid)->where("id", $toUserId)->find();
        if (!$from || !$to) return 0;
        $this->blinEnsureFriendPair($appid, $fromUserId, $toUserId);
        $now = date("Y-m-d H:i:s");
        $messageId = Db::name("messages")->insertGetId([
            "sender_id"=>$fromUserId,
            "receiver_id"=>$toUserId,
            "content"=>$content,
            "create_time"=>$now,
            "message_type"=>0,
            "is_read"=>0,
            "is_deleted"=>0,
            "image_path"=>"",
            "pid"=>0,
            "money_type"=>0,
            "file_path"=>"",
            "file_name"=>"",
        ]);
        $clientNo = "admin_msg_" . $messageId . "_" . time();
        $fromUid = $appid . "_" . $fromUserId;
        $toUid = $appid . "_" . $toUserId;
        $payload = [
            "version"=>"1.0",
            "message_id"=>intval($messageId),
            "client_msg_no"=>$clientNo,
            "conversation_type"=>"single",
            "channel_type"=>1,
            "from_uid"=>$fromUid,
            "to_uid"=>$toUid,
            "from_user_id"=>$fromUserId,
            "to_user_id"=>$toUserId,
            "msg_type"=>"text",
            "message_type"=>0,
            "content"=>["text"=>$content, "title"=>$title],
            "legacy"=>["type"=>0, "content"=>$content, "image_path"=>"", "sender_id"=>$fromUserId, "receiver_id"=>$toUserId, "money_type"=>0],
            "create_time"=>$now,
            "source"=>"admin",
        ];
        Db::name("messages")->where("id", $messageId)->update(["im_payload"=>json_encode($payload, JSON_UNESCAPED_UNICODE)]);
        try {
            Db::name("im_message_log")->insert([
                "appid"=>$appid,
                "message_id"=>"local_" . $messageId,
                "client_msg_no"=>$clientNo,
                "message_seq"=>0,
                "from_uid"=>$fromUid,
                "from_user_id"=>$fromUserId,
                "channel_id"=>$toUid,
                "channel_user_id"=>$toUserId,
                "channel_type"=>1,
                "message_type"=>0,
                "content"=>$content,
                "payload"=>json_encode($payload, JSON_UNESCAPED_UNICODE),
                "raw_data"=>json_encode($payload, JSON_UNESCAPED_UNICODE),
                "msg_timestamp"=>time(),
                "status"=>0,
                "audit_status"=>0,
                "operator_id"=>isset($this->admin_info["id"]) ? intval($this->admin_info["id"]) : 0,
                "create_time"=>$now,
            ]);
        } catch (\Exception $e) {}
        if (config("wukongim.enable")) {
            try { (new \app\common\tool\WukongIM())->sendPersonMessage($fromUid, $toUid, $payload, $clientNo); } catch (\Exception $e) {}
        }
        return $messageId;
    }
'''


def patch_system_controller():
    source = SYSTEM.read_text()
    original = source
    if "\\app\\common\\tool\\WukongIM" not in source:
        source = source.replace("use think\\facade\\Request;\n", "use think\\facade\\Request;\nuse app\\common\\tool\\WukongIM;\n")
    source = insert_before_last_class_brace(source, ADMIN_HELPERS, "blin-admin-system-friend-message")
    old = '''        $userid = input("post.userid");
        $appid = input("post.appid");
        $pic_url = input("post.pic_url");
        if ($title == '' || $content == '' || $appid == '') {
            $this->error("请输入完整！");
        }
        $add_data = [
            "title" => $title,
            "content" => $content,
            "appid" => $appid,
            "send_to" => 0,
            "type" => 0,
            "pic_url" => $pic_url,
            "user_id" => $userid,
            "time" => date("Y-m-d H:i:s"),
            "is_admin" => 1,
        ];
        Db::name('message_notification')->insert($add_data);
        $this->success("添加成功！");'''
    new = '''        $userid = intval(input("post.userid"));
        $appid = intval(input("post.appid"));
        $pic_url = input("post.pic_url");
        $sendAsIm = intval(input("post.send_as_im"));
        if ($title == '' || $content == '' || $appid == '') {
            $this->error("请输入完整！");
        }
        $this->blinRequireApp($appid);
        $appInfo = Db::name("app")->where("appid", $appid)->find();
        if (!$appInfo) $this->error("应用不存在");
        $imConfig = $this->blinAppImConfig($appid);
        if (intval(isset($imConfig["admin_app_message_switch"]) ? $imConfig["admin_app_message_switch"] : 0) !== 0) {
            $this->error("该应用已关闭后台发消息");
        }
        if ($userid > 0) {
            $targetUser = Db::name("user")->where("appid", $appid)->where("id", $userid)->find();
            if (!$targetUser) $this->error("用户不属于该应用");
        }
        $add_data = [
            "title" => $title,
            "content" => $content,
            "appid" => $appid,
            "send_to" => 0,
            "type" => 0,
            "pic_url" => $pic_url,
            "user_id" => $userid,
            "time" => date("Y-m-d H:i:s"),
            "is_admin" => 1,
        ];
        Db::name('message_notification')->insert($add_data);
        $sent = 0;
        if ($sendAsIm === 1) {
            $admin = Db::name("admin")->where("id", intval($this->admin_info["id"]))->find();
            $fromUserId = 0;
            if ($admin && intval(isset($admin["front_appid"]) ? $admin["front_appid"] : 0) === $appid && intval(isset($admin["front_user_id"]) ? $admin["front_user_id"] : 0) > 0) {
                $fromUserId = intval($admin["front_user_id"]);
            }
            if ($fromUserId <= 0) {
                $systemUser = $this->blinEnsureSystemUser($appid);
                $fromUserId = intval($systemUser["id"]);
            }
            $targets = [];
            if ($userid > 0) {
                $targets[] = $userid;
            } else {
                $targets = Db::name("user")->where("appid", $appid)->where("id", "<>", $fromUserId)->column("id");
            }
            foreach ($targets as $targetId) {
                if (intval($targetId) === $fromUserId) continue;
                if ($this->blinSendAdminPrivateMessage($appid, $fromUserId, intval($targetId), $content, $title)) $sent++;
            }
        }
        $this->success($sendAsIm === 1 ? ("添加成功，已发送私聊 " . $sent . " 条") : "添加成功！");'''
    source = replace_once(source, old, new, "system_message_notification_add")
    save(SYSTEM, original, source, "admin_im_message_system")


def patch_message_view():
    source = MESSAGE_VIEW.read_text()
    original = source
    source = replace_once(
        source,
        '''                <div class="mb-3">
                    <label for="add_userid" class="form-label">用户</label>
                    <select class="form-control selectpicker" data-live-search="true" id="add_userid">
                    </select>
                    <small>不选择则发送给全体用户</small>
                </div>''',
        '''                <div class="mb-3">
                    <label for="add_userid" class="form-label">用户</label>
                    <select class="form-control selectpicker" data-live-search="true" id="add_userid">
                    </select>
                    <small>不选择则发送给全体用户</small>
                </div>
                <div class="form-check form-switch mb-2">
                    <input class="form-check-input" type="checkbox" id="add_send_as_im" checked>
                    <label class="form-check-label" for="add_send_as_im">同时发送为 IM 私聊消息</label>
                </div>''',
        "message_view_send_as_im",
    )
    source = replace_once(
        source,
        '''                userid: add_userid''',
        '''                userid: add_userid,
                send_as_im: $("#add_send_as_im").is(":checked") ? 1 : 0''',
        "message_view_ajax_send_as_im",
    )
    source = replace_once(
        source,
        '''                        str += '<option value="' + list[index].id + '" data-tokens="' + list[index].id + '">' + list[index].username + '</option>';''',
        '''                        var label = list[index].username;
                        if (list[index].nickname) label += ' / ' + list[index].nickname;
                        if (list[index].is_system == 1) label += '（系统号）';
                        str += '<option value="' + list[index].id + '" data-tokens="' + list[index].id + ' ' + label + '">' + label + '</option>';''',
        "message_view_user_label",
    )
    save(MESSAGE_VIEW, original, source, "admin_im_message_view")


def patch_index_controller():
    source = INDEX.read_text()
    original = source
    source = replace_once(
        source,
        '''        $appid = input("appid");
        $result = Db::name("user")->where("appid", $appid)->field("id,username")->select();
        return $this->success("获取用户列表成功！", "", $result);''',
        '''        $appid = intval(input("appid"));
        if (method_exists($this, "blinRequireApp")) $this->blinRequireApp($appid);
        $app = Db::name("app")->where("appid", $appid)->find();
        $config = $app && isset($app["im_configuration"]) ? json_decode($app["im_configuration"], true) : [];
        if (!is_array($config)) $config = [];
        $systemUserId = intval(isset($config["system_friend_user_id"]) ? $config["system_friend_user_id"] : 0);
        $result = Db::name("user")->where("appid", $appid)->field("id,username,nickname")->select();
        foreach ($result as $key => $value) {
            $result[$key]["is_system"] = $systemUserId > 0 && intval($value["id"]) === $systemUserId ? 1 : 0;
        }
        return $this->success("获取用户列表成功！", "", $result);''',
        "index_obtain_users_system_flag",
    )
    save(INDEX, original, source, "admin_im_message_index")


def patch_api_controller():
    source = API.read_text()
    original = source
    source = replace_all(
        source,
        '''            $user_id = Db::name("user")->insertGetId($add);
            $this->blinAutoJoinDefaultGroup($user_id);''',
        '''            $user_id = Db::name("user")->insertGetId($add);
            $this->blinAfterUserRegister($user_id);''',
        "api_register_after_hook_indented",
        min_count=2,
    )
    source = replace_once(
        source,
        '''        $user_id = Db::name("user")->insertGetId($add);
            $this->blinAutoJoinDefaultGroup($user_id);''',
        '''        $user_id = Db::name("user")->insertGetId($add);
        $this->blinAfterUserRegister($user_id);''',
        "api_register_after_hook_3",
    )
    source = replace_once(
        source,
        r'''    private function blinAutoJoinDefaultGroup($userId)
    {
        try {
            if (!$this->blinFeatureOpen("default_group_switch")) return;
            if (!$this->blinFeatureOpen("default_group_join_switch")) return;
            $group = $this->blinDefaultGroup();
            if ($group) $this->blinAddUserToGroup($group, intval($userId), 0);
        } catch (\Exception $e) {
        }
    }''',
        r'''    private function blinAutoJoinDefaultGroup($userId)
    {
        try {
            if (!$this->blinFeatureOpen("default_group_switch")) return;
            if (!$this->blinFeatureOpen("default_group_join_switch")) return;
            $group = $this->blinDefaultGroup();
            if ($group) $this->blinAddUserToGroup($group, intval($userId), 0);
        } catch (\Exception $e) {
        }
    }

    private function blinAfterUserRegister($userId)
    {
        $this->blinAutoJoinDefaultGroup($userId);
        $this->blinAutoAddSystemFriend($userId);
    }

    private function blinEnsureFriendPair($userId, $friendId)
    {
        $userId = intval($userId);
        $friendId = intval($friendId);
        if ($userId <= 0 || $friendId <= 0 || $userId === $friendId) return false;
        $u1 = Db::name("user")->where("appid", $this->appid)->where("id", $userId)->find();
        $u2 = Db::name("user")->where("appid", $this->appid)->where("id", $friendId)->find();
        if (!$u1 || !$u2) return false;
        $now = date("Y-m-d H:i:s");
        foreach ([[$userId, $friendId], [$friendId, $userId]] as $pair) {
            $row = Db::table("im_friends")->where("user_id", $pair[0])->where("friend_id", $pair[1])->find();
            if ($row) {
                Db::table("im_friends")->where("id", $row["id"])->update(["status"=>1, "updated_at"=>$now]);
            } else {
                Db::table("im_friends")->insert(["user_id"=>$pair[0], "friend_id"=>$pair[1], "status"=>1, "created_at"=>$now, "updated_at"=>$now]);
            }
        }
        return true;
    }

    private function blinEnsureSystemFriendUser()
    {
        $userId = intval($this->blinImConfig("system_friend_user_id", 0));
        if ($userId > 0) {
            $user = Db::name("user")->where("appid", $this->appid)->where("id", $userId)->find();
            if ($user) return $user;
        }
        $username = "system_" . $this->appid;
        $user = Db::name("user")->where("appid", $this->appid)->where("username", $username)->find();
        if ($user) return $user;
        $userinfo = isset($this->app_info["userinfo_configuration"]) && is_array($this->app_info["userinfo_configuration"]) ? $this->app_info["userinfo_configuration"] : [];
        $salt = getRandChar(6);
        $userId = Db::name("user")->insertGetId([
            "appid"=>$this->appid,
            "username"=>$username,
            "password"=>md5(getRandChar(16) . $salt),
            "salt"=>$salt,
            "usertx"=>isset($userinfo["usertx"]) ? $userinfo["usertx"] : "/static/images/initial_photo/user.png",
            "nickname"=>"系统助手",
            "money"=>0,
            "integral"=>0,
            "viptime"=>0,
            "userbg"=>isset($userinfo["userbg"]) ? $userinfo["userbg"] : "",
            "signature"=>"官方系统账号",
            "create_time"=>date("Y-m-d H:i:s"),
            "register_ip"=>get_client_ip(),
            "invitecode"=>function_exists("enerate_invitation_code") ? enerate_invitation_code() : getRandChar(8),
        ]);
        $config = isset($this->app_info["im_configuration"]) && is_array($this->app_info["im_configuration"]) ? $this->app_info["im_configuration"] : [];
        $config["system_friend_user_id"] = $userId;
        Db::name("app")->where("appid", $this->appid)->update(["im_configuration"=>json_encode($config, JSON_UNESCAPED_UNICODE)]);
        if (config("wukongim.enable")) {
            try { (new \app\common\tool\WukongIM())->addSystemUids([$this->appid . "_" . $userId]); } catch (\Exception $e) {}
        }
        return Db::name("user")->where("id", $userId)->find();
    }

    private function blinAutoAddSystemFriend($userId)
    {
        try {
            if (!$this->blinFeatureOpen("system_friend_switch")) return;
            $systemUser = $this->blinEnsureSystemFriendUser();
            if (!$systemUser) return;
            $systemUserId = intval($systemUser["id"]);
            if ($systemUserId <= 0 || $systemUserId === intval($userId)) return;
            $this->blinEnsureFriendPair(intval($userId), $systemUserId);
            $welcome = trim(strval($this->blinImConfig("system_friend_welcome", "")));
            if ($welcome !== "") {
                $this->blinSystemFriendWelcomeMessage($systemUser, intval($userId), $welcome);
            }
        } catch (\Exception $e) {
        }
    }

    private function blinSystemFriendWelcomeMessage($systemUser, $targetUserId, $content)
    {
        $target = Db::name("user")->where("appid", $this->appid)->where("id", intval($targetUserId))->find();
        if (!$systemUser || !$target) return 0;
        $now = date("Y-m-d H:i:s");
        $messageId = Db::name("messages")->insertGetId(["sender_id"=>intval($systemUser["id"]), "receiver_id"=>intval($targetUserId), "content"=>$content, "create_time"=>$now, "message_type"=>0, "is_read"=>0, "is_deleted"=>0, "image_path"=>"", "pid"=>0, "money_type"=>0, "file_path"=>"", "file_name"=>""]);
        $clientNo = "system_welcome_" . $messageId . "_" . time();
        $fromUid = $this->appid . "_" . intval($systemUser["id"]);
        $toUid = $this->appid . "_" . intval($targetUserId);
        $payload = ["version"=>"1.0", "message_id"=>intval($messageId), "client_msg_no"=>$clientNo, "conversation_type"=>"single", "channel_type"=>1, "from_uid"=>$fromUid, "to_uid"=>$toUid, "from_user_id"=>intval($systemUser["id"]), "to_user_id"=>intval($targetUserId), "msg_type"=>"text", "message_type"=>0, "content"=>["text"=>$content], "legacy"=>["type"=>0, "content"=>$content, "image_path"=>"", "sender_id"=>intval($systemUser["id"]), "receiver_id"=>intval($targetUserId), "money_type"=>0], "create_time"=>$now, "source"=>"system_welcome"];
        Db::name("messages")->where("id", $messageId)->update(["im_payload"=>json_encode($payload, JSON_UNESCAPED_UNICODE)]);
        try { Db::name("im_message_log")->insert(["appid"=>intval($this->appid), "message_id"=>"local_" . $messageId, "client_msg_no"=>$clientNo, "message_seq"=>0, "from_uid"=>$fromUid, "from_user_id"=>intval($systemUser["id"]), "channel_id"=>$toUid, "channel_user_id"=>intval($targetUserId), "channel_type"=>1, "message_type"=>0, "content"=>$content, "payload"=>json_encode($payload, JSON_UNESCAPED_UNICODE), "raw_data"=>json_encode($payload, JSON_UNESCAPED_UNICODE), "msg_timestamp"=>time(), "status"=>0, "audit_status"=>0, "create_time"=>$now]); } catch (\Exception $e) {}
        if (config("wukongim.enable")) {
            try { (new \app\common\tool\WukongIM())->sendPersonMessage($fromUid, $toUid, $payload, $clientNo); } catch (\Exception $e) {}
        }
        return $messageId;
    }''',
        "api_system_friend_helpers",
    )
    save(API, original, source, "api_system_friend")


def main():
    patch_database()
    patch_app_controller()
    patch_base_controller()
    patch_app_edit_view()
    patch_system_controller()
    patch_message_view()
    patch_index_controller()
    patch_api_controller()


if __name__ == "__main__":
    main()
