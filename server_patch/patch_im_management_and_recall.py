#!/usr/bin/env python3
"""Patch IM management scope, friend requests, recall, QR and decimal wallet."""

from datetime import datetime
from pathlib import Path
import os
import re
import shutil
import subprocess


ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"
APP = ROOT / "application/admin/controller/App.php"
IM = ROOT / "application/admin/controller/Im.php"
SYSTEM = ROOT / "application/admin/controller/System.php"
APP_EDIT = ROOT / "application/admin/view/app/edit.html"
IM_VIEW = ROOT / "application/admin/view/im/login_session.html"


def backup(path: Path, suffix: str) -> None:
    if not path.exists():
        return
    target = path.with_name(
        f"{path.name}.bak_{suffix}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    shutil.copy2(path, target)
    print("BACKUP", target)


def save(path: Path, original: str, source: str, suffix: str) -> bool:
    if source == original:
        print("NO_CHANGE", path)
        return False
    backup(path, suffix)
    path.write_text(source)
    print("PATCHED", path)
    return True


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
    if not env_path.exists():
        return values
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


def mysql(sql: str, ignore=()):
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
        err = result.stderr.strip()
        if any(item in err for item in ignore):
            print("MYSQL_IGNORE", err)
            return ""
        raise SystemExit(err)
    if result.stdout.strip():
        print(result.stdout.strip())
    return result.stdout


def patch_database():
    stmts = [
        ("ALTER TABLE `mr_user` MODIFY COLUMN `money` decimal(16,2) NOT NULL DEFAULT 0.00", ()),
        ("ALTER TABLE `mr_messages` ADD COLUMN `is_recalled` tinyint(1) NOT NULL DEFAULT 0", ("Duplicate column name",)),
        ("ALTER TABLE `mr_messages` ADD COLUMN `recall_time` datetime DEFAULT NULL", ("Duplicate column name",)),
        ("ALTER TABLE `mr_messages` ADD COLUMN `recall_user_id` bigint(20) NOT NULL DEFAULT 0", ("Duplicate column name",)),
        ("ALTER TABLE `mr_im_group_messages` ADD COLUMN `is_recalled` tinyint(1) NOT NULL DEFAULT 0", ("Duplicate column name",)),
        ("ALTER TABLE `mr_im_group_messages` ADD COLUMN `recall_time` datetime DEFAULT NULL", ("Duplicate column name",)),
        ("ALTER TABLE `mr_im_group_messages` ADD COLUMN `recall_user_id` int(11) NOT NULL DEFAULT 0", ("Duplicate column name",)),
        ("ALTER TABLE `im_friends` ADD COLUMN `appid` bigint(20) NOT NULL DEFAULT 0 AFTER `id`", ("Duplicate column name",)),
        ("ALTER TABLE `im_friend_requests` ADD COLUMN `appid` bigint(20) NOT NULL DEFAULT 0 AFTER `id`", ("Duplicate column name",)),
        ("ALTER TABLE `im_friends` ADD KEY `idx_app_user` (`appid`,`user_id`)", ("Duplicate key name",)),
        ("ALTER TABLE `im_friend_requests` ADD KEY `idx_app_to_status` (`appid`,`to_user_id`,`status`)", ("Duplicate key name",)),
    ]
    for sql, ignore in stmts:
        mysql(sql, ignore)
    mysql("UPDATE `im_friends` f JOIN `mr_user` u ON u.id=f.user_id SET f.appid=u.appid WHERE f.appid=0")
    mysql("UPDATE `im_friend_requests` r JOIN `mr_user` u ON u.id=r.from_user_id SET r.appid=u.appid WHERE r.appid=0")
    mysql(
        """UPDATE `mr_app`
SET `im_configuration` = JSON_SET(
  COALESCE(NULLIF(`im_configuration`, ''), '{}'),
  '$.message_recall_minutes',
  COALESCE(JSON_UNQUOTE(JSON_EXTRACT(COALESCE(NULLIF(`im_configuration`, ''), '{}'), '$.message_recall_minutes')), '2')
)
WHERE JSON_VALID(COALESCE(NULLIF(`im_configuration`, ''), '{}')) = 1"""
    )
    mysql(
        """INSERT INTO `mr_admin_permission` (`pid`,`name`,`url`,`icon`,`sort`,`is_out`,`is_menu`)
SELECT 135,'登录会话','im/login_session','mdi-cellphone-link',10,2,1
WHERE NOT EXISTS (SELECT 1 FROM `mr_admin_permission` WHERE `url`='im/login_session')""",
        ("Duplicate entry",),
    )


def patch_app_controller():
    source = APP.read_text(errors="ignore")
    original = source
    source = source.replace(
        '"system_friend_welcome":"欢迎使用，有问题可以直接联系我。"}',
        '"system_friend_welcome":"欢迎使用，有问题可以直接联系我。","message_recall_minutes":"2"}',
    )
    if '"message_recall_minutes" => max(0, intval(isset($data["message_recall_minutes"])' not in source:
        source = source.replace(
            '''                    "system_friend_welcome" => trim(strval(isset($data["system_friend_welcome"]) ? $data["system_friend_welcome"] : "")),
                ], JSON_UNESCAPED_UNICODE),''',
            '''                    "system_friend_welcome" => trim(strval(isset($data["system_friend_welcome"]) ? $data["system_friend_welcome"] : "")),
                    "message_recall_minutes" => max(0, intval(isset($data["message_recall_minutes"]) ? $data["message_recall_minutes"] : 2)),
                ], JSON_UNESCAPED_UNICODE),''',
            1,
        )
    if '"message_recall_minutes" => 2,' not in source:
        source = source.replace(
            '''                    "system_friend_welcome" => "欢迎使用，有问题可以直接联系我。",
                ];''',
            '''                    "system_friend_welcome" => "欢迎使用，有问题可以直接联系我。",
                    "message_recall_minutes" => 2,
                ];''',
            1,
        )
    save(APP, original, source, "im_recall_config")


def patch_app_edit_view():
    source = APP_EDIT.read_text(errors="ignore")
    original = source
    if 'name="message_recall_minutes"' not in source:
        source = source.replace(
            '''                            <div class="col-md-8">
                                <label class="form-label">系统好友欢迎语</label>
                                <input type="text" class="form-control" name="system_friend_welcome" value="{$data.im_configuration.system_friend_welcome}" placeholder="欢迎使用，有问题可以直接联系我。">
                            </div>
                        </div>''',
            '''                            <div class="col-md-8">
                                <label class="form-label">系统好友欢迎语</label>
                                <input type="text" class="form-control" name="system_friend_welcome" value="{$data.im_configuration.system_friend_welcome}" placeholder="欢迎使用，有问题可以直接联系我。">
                            </div>
                            <div class="col-md-4">
                                <label class="form-label">消息撤回时间（分钟）</label>
                                <input type="number" min="0" class="form-control" name="message_recall_minutes" value="{$data.im_configuration.message_recall_minutes}" placeholder="2">
                                <small>设置 0 表示不允许普通用户撤回。</small>
                            </div>
                        </div>''',
            1,
        )
    save(APP_EDIT, original, source, "im_recall_config_view")


API_BLOCK = r'''
    // blin-im-friend-recall-qr-wallet
    private function blinEnsureFriendTables()
    {
        try {
            Db::execute("CREATE TABLE IF NOT EXISTS `im_friends` (`id` bigint(20) unsigned NOT NULL AUTO_INCREMENT, `appid` bigint(20) NOT NULL DEFAULT 0, `user_id` bigint(20) unsigned NOT NULL, `friend_id` bigint(20) unsigned NOT NULL, `status` tinyint(4) NOT NULL DEFAULT 1, `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP, `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (`id`), UNIQUE KEY `uniq_friend_pair` (`user_id`,`friend_id`), KEY `idx_app_user` (`appid`,`user_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
            Db::execute("CREATE TABLE IF NOT EXISTS `im_friend_requests` (`id` bigint(20) unsigned NOT NULL AUTO_INCREMENT, `appid` bigint(20) NOT NULL DEFAULT 0, `from_user_id` bigint(20) unsigned NOT NULL, `to_user_id` bigint(20) unsigned NOT NULL, `message` varchar(255) NOT NULL DEFAULT '', `status` tinyint(4) NOT NULL DEFAULT 0, `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP, `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (`id`), UNIQUE KEY `uniq_friend_request` (`from_user_id`,`to_user_id`), KEY `idx_app_to_status` (`appid`,`to_user_id`,`status`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
        } catch (\Exception $e) {}
    }

    private function blinUpsertFriend($userId, $friendId)
    {
        $now = date("Y-m-d H:i:s");
        $appid = intval($this->appid);
        foreach ([[intval($userId), intval($friendId)], [intval($friendId), intval($userId)]] as $pair) {
            Db::execute("INSERT INTO `im_friends` (`appid`,`user_id`,`friend_id`,`status`,`created_at`,`updated_at`) VALUES (:appid,:uid,:fid,1,:now,:now2) ON DUPLICATE KEY UPDATE `appid`=VALUES(`appid`),`status`=1,`updated_at`=VALUES(`updated_at`)", ["appid"=>$appid, "uid"=>$pair[0], "fid"=>$pair[1], "now"=>$now, "now2"=>$now]);
        }
    }

    private function blinFriendUser($userId)
    {
        return Db::name("user")->where("appid", $this->appid)->where("id", intval($userId))->field("id,username,nickname,usertx,signature")->find();
    }

    private function blinFriendEvent($toUserId, $action, $fromUser, $message = "")
    {
        if (!config("wukongim.enable")) return;
        try {
            $fromUid = $this->appid . "_" . intval($fromUser["id"]);
            $toUid = $this->appid . "_" . intval($toUserId);
            $clientNo = "friend_" . $action . "_" . intval($fromUser["id"]) . "_" . intval($toUserId) . "_" . time();
            $payload = [
                "version"=>"1.0",
                "client_msg_no"=>$clientNo,
                "from_uid"=>$fromUid,
                "to_uid"=>$toUid,
                "from_user_id"=>intval($fromUser["id"]),
                "to_user_id"=>intval($toUserId),
                "msg_type"=>"friend",
                "content"=>[
                    "action"=>$action,
                    "user_id"=>intval($fromUser["id"]),
                    "from_user_id"=>intval($fromUser["id"]),
                    "nickname"=>strval($fromUser["nickname"] ?: $fromUser["username"]),
                    "avatar"=>strval($fromUser["usertx"]),
                    "message"=>$message,
                ],
                "create_time"=>date("Y-m-d H:i:s"),
            ];
            (new \app\common\tool\WukongIM())->sendPersonMessage($fromUid, $toUid, $payload, $clientNo);
        } catch (\Exception $e) {}
    }

    public function get_friends()
    {
        $this->blinEnsureFriendTables();
        $user = $this->user_info;
        $rows = Db::table("im_friends")->alias("f")
            ->join("mr_user u", "u.id=f.friend_id")
            ->where("f.user_id", intval($user["id"]))
            ->where("f.status", 1)
            ->where("u.appid", $this->appid)
            ->field("u.id,u.username,u.nickname,u.usertx,u.signature,f.updated_at")
            ->order("f.updated_at", "desc")
            ->select();
        $this->json(1, "success", ["list"=>$rows]);
    }

    public function get_friend_list(){ return $this->get_friends(); }

    public function is_friend()
    {
        $this->blinEnsureFriendTables();
        $user = $this->user_info;
        $friendId = intval(input("friend_id") ?: input("user_id"));
        $friend = $this->blinFriendUser($friendId);
        if (!$friend) $this->json(1, "success", ["is_friend"=>0]);
        $exists = Db::table("im_friends")->where("user_id", intval($user["id"]))->where("friend_id", $friendId)->where("status", 1)->find();
        $this->json(1, "success", ["is_friend"=>$exists ? 1 : 0]);
    }

    public function add_friend()
    {
        $this->blinEnsureFriendTables();
        $user = $this->user_info;
        $friendId = intval(input("friend_id") ?: input("user_id"));
        if ($friendId <= 0 || $friendId == intval($user["id"])) $this->json(0, "用户不存在");
        $friend = $this->blinFriendUser($friendId);
        if (!$friend) $this->json(0, "用户不存在");
        $exists = Db::table("im_friends")->where("user_id", intval($user["id"]))->where("friend_id", $friendId)->where("status", 1)->find();
        if ($exists) $this->json(1, "已经是好友了");
        $message = trim(strval(input("message") ?: "你好，我想添加你为好友"));
        $now = date("Y-m-d H:i:s");
        Db::execute("INSERT INTO `im_friend_requests` (`appid`,`from_user_id`,`to_user_id`,`message`,`status`,`created_at`,`updated_at`) VALUES (:appid,:from_id,:to_id,:message,0,:created,:updated) ON DUPLICATE KEY UPDATE `appid`=VALUES(`appid`),`message`=VALUES(`message`),`status`=0,`updated_at`=VALUES(`updated_at`)", ["appid"=>intval($this->appid), "from_id"=>intval($user["id"]), "to_id"=>$friendId, "message"=>$message, "created"=>$now, "updated"=>$now]);
        $this->blinFriendEvent($friendId, "request", $user, $message);
        $this->json(1, "已发送好友申请");
    }

    public function apply_friend(){ return $this->add_friend(); }

    public function get_friend_requests()
    {
        $this->blinEnsureFriendTables();
        $user = $this->user_info;
        $direction = trim(strval(input("direction") ?: "incoming"));
        $query = Db::table("im_friend_requests")->alias("r")
            ->join("mr_user fu", "fu.id=r.from_user_id")
            ->join("mr_user tu", "tu.id=r.to_user_id")
            ->where("r.appid", $this->appid);
        if ($direction === "outgoing") {
            $query->where("r.from_user_id", intval($user["id"]));
        } elseif ($direction === "all") {
            $uid = intval($user["id"]);
            $query->where("(r.from_user_id={$uid} OR r.to_user_id={$uid})");
        } else {
            $query->where("r.to_user_id", intval($user["id"]));
        }
        $rows = $query->field("r.*,fu.username as from_username,fu.nickname as from_nickname,fu.usertx as from_avatar,tu.username as to_username,tu.nickname as to_nickname,tu.usertx as to_avatar")
            ->order("r.updated_at", "desc")
            ->limit($this->limit)
            ->page($this->page)
            ->select();
        foreach ($rows as $k=>$row) {
            $status = intval($row["status"]);
            $rows[$k]["title"] = "好友申请";
            $rows[$k]["content"] = ($row["from_nickname"] ?: $row["from_username"]) . " 请求添加你为好友：" . $row["message"];
            $rows[$k]["request_status"] = $status;
            $rows[$k]["status_text"] = $status == 1 ? "已通过" : ($status == 2 ? "已拒绝" : "待处理");
            $rows[$k]["user_id"] = intval($row["from_user_id"]);
            $rows[$k]["friend_id"] = intval($row["from_user_id"]);
            $rows[$k]["create_time"] = $row["created_at"];
        }
        $this->json(1, "success", ["list"=>$rows]);
    }

    public function friend_requests(){ return $this->get_friend_requests(); }

    public function handle_friend_request()
    {
        $this->blinEnsureFriendTables();
        $user = $this->user_info;
        $fromId = intval(input("from_user_id") ?: input("friend_id") ?: input("user_id"));
        $action = strtolower(trim(strval(input("action") ?: (intval(input("status")) == 2 ? "reject" : "accept"))));
        if ($fromId <= 0 || $fromId == intval($user["id"])) $this->json(0, "申请用户不存在");
        $request = Db::table("im_friend_requests")->where("appid", $this->appid)->where("from_user_id", $fromId)->where("to_user_id", intval($user["id"]))->find();
        if (!$request) $this->json(0, "好友申请不存在");
        $fromUser = $this->blinFriendUser($fromId);
        if (!$fromUser) $this->json(0, "申请用户不存在");
        $now = date("Y-m-d H:i:s");
        if (in_array($action, ["reject","refuse","deny"])) {
            Db::table("im_friend_requests")->where("id", $request["id"])->update(["status"=>2, "updated_at"=>$now]);
            $this->blinFriendEvent($fromId, "rejected", $user, "");
            $this->json(1, "已拒绝好友申请");
        }
        Db::table("im_friend_requests")->where("id", $request["id"])->update(["status"=>1, "updated_at"=>$now]);
        $this->blinUpsertFriend(intval($user["id"]), $fromId);
        $this->blinFriendEvent($fromId, "accepted", $user, "");
        $this->json(1, "已通过好友申请");
    }

    public function friend_request_handle(){ return $this->handle_friend_request(); }

    public function delete_friend()
    {
        $this->blinEnsureFriendTables();
        $user = $this->user_info;
        $friendId = intval(input("friend_id") ?: input("user_id"));
        if ($friendId <= 0 || $friendId == intval($user["id"])) $this->json(0, "用户不存在");
        if (!$this->blinFriendUser($friendId)) $this->json(0, "用户不存在");
        $now = date("Y-m-d H:i:s");
        Db::table("im_friends")->where("user_id", intval($user["id"]))->where("friend_id", $friendId)->update(["status"=>0, "updated_at"=>$now]);
        Db::table("im_friends")->where("user_id", $friendId)->where("friend_id", intval($user["id"]))->update(["status"=>0, "updated_at"=>$now]);
        $this->json(1, "已删除好友");
    }

    public function remove_friend(){ return $this->delete_friend(); }
    public function del_friend(){ return $this->delete_friend(); }

    private function blinRecallLimitSeconds()
    {
        $config = isset($this->app_info["im_configuration"]) && is_array($this->app_info["im_configuration"]) ? $this->app_info["im_configuration"] : [];
        $minutes = intval(isset($config["message_recall_minutes"]) ? $config["message_recall_minutes"] : 2);
        return $minutes <= 0 ? 0 : $minutes * 60;
    }

    private function blinRecallPayload($messageId, $clientNo, $fromUserId, $toUid, $channelType, $text = "消息已撤回")
    {
        $clientNo = $clientNo ?: ("recall_" . $messageId . "_" . time());
        return [
            "version"=>"1.0",
            "message_id"=>intval($messageId),
            "client_msg_no"=>$clientNo,
            "from_uid"=>$this->appid . "_" . intval($fromUserId),
            "to_uid"=>$toUid,
            "from_user_id"=>intval($fromUserId),
            "to_user_id"=>0,
            "channel_type"=>intval($channelType),
            "msg_type"=>"recall",
            "message_type"=>0,
            "content"=>["message_id"=>intval($messageId), "client_msg_no"=>$clientNo, "text"=>$text],
            "create_time"=>date("Y-m-d H:i:s"),
        ];
    }

    public function recall_message()
    {
        $user = $this->user_info;
        $messageId = intval(input("message_id") ?: input("id"));
        $groupId = intval(input("group_id"));
        if ($messageId <= 0) $this->json(0, "消息不存在");
        $limit = $this->blinRecallLimitSeconds();
        if ($limit <= 0) $this->json(0, "当前应用未开启消息撤回");
        $now = date("Y-m-d H:i:s");
        if ($groupId > 0) {
            $row = Db::name("im_group_messages")->where("appid", $this->appid)->where("group_id", $groupId)->where("id", $messageId)->find();
            if (!$row) $this->json(0, "消息不存在");
            if (intval($row["sender_id"]) !== intval($user["id"])) $this->json(0, "只能撤回自己发送的消息");
            if (time() - strtotime($row["create_time"]) > $limit) $this->json(0, "消息已超过可撤回时间");
            if (intval(isset($row["is_recalled"]) ? $row["is_recalled"] : 0) === 1) $this->json(1, "消息已撤回");
            Db::name("im_group_messages")->where("id", $messageId)->update(["is_recalled"=>1, "recall_time"=>$now, "recall_user_id"=>intval($user["id"]), "content"=>"[消息已撤回]"]);
            $group = Db::name("im_groups")->where("appid", $this->appid)->where("id", $groupId)->find();
            $clientNo = "";
            $payloadOld = json_decode(strval($row["payload"]), true);
            if (is_array($payloadOld) && isset($payloadOld["client_msg_no"])) $clientNo = strval($payloadOld["client_msg_no"]);
            $payload = $this->blinRecallPayload($messageId, $clientNo, intval($user["id"]), $group ? $group["group_no"] : strval($groupId), 2, "撤回了一条消息");
            $payload["group_id"] = $groupId;
            $payload["group_no"] = $group ? $group["group_no"] : "";
            try { if (config("wukongim.enable") && $group) (new \app\common\tool\WukongIM())->sendMessage($this->appid . "_" . intval($user["id"]), $group["group_no"], 2, $payload, "recall_" . $messageId . "_" . time()); } catch (\Exception $e) {}
            $this->json(1, "消息已撤回", ["message_id"=>$messageId, "payload"=>$payload]);
        }
        $row = Db::name("messages")->where("id", $messageId)->find();
        if (!$row) $this->json(0, "消息不存在");
        if (intval($row["sender_id"]) !== intval($user["id"])) $this->json(0, "只能撤回自己发送的消息");
        $receiver = $this->blinFriendUser(intval($row["receiver_id"]));
        if (!$receiver) $this->json(0, "消息不存在");
        if (time() - strtotime($row["create_time"]) > $limit) $this->json(0, "消息已超过可撤回时间");
        if (intval(isset($row["is_recalled"]) ? $row["is_recalled"] : 0) === 1) $this->json(1, "消息已撤回");
        Db::name("messages")->where("id", $messageId)->update(["is_recalled"=>1, "recall_time"=>$now, "recall_user_id"=>intval($user["id"]), "content"=>"[消息已撤回]"]);
        $clientNo = "";
        $payloadOld = json_decode(strval(isset($row["im_payload"]) ? $row["im_payload"] : ""), true);
        if (is_array($payloadOld) && isset($payloadOld["client_msg_no"])) $clientNo = strval($payloadOld["client_msg_no"]);
        $payload = $this->blinRecallPayload($messageId, $clientNo, intval($user["id"]), $this->appid . "_" . intval($row["receiver_id"]), 1, "撤回了一条消息");
        $payload["to_user_id"] = intval($row["receiver_id"]);
        try { if (config("wukongim.enable")) (new \app\common\tool\WukongIM())->sendPersonMessage($this->appid . "_" . intval($user["id"]), $this->appid . "_" . intval($row["receiver_id"]), $payload, "recall_" . $messageId . "_" . time()); } catch (\Exception $e) {}
        $this->json(1, "消息已撤回", ["message_id"=>$messageId, "payload"=>$payload]);
    }

    public function revoke_message(){ return $this->recall_message(); }
    public function withdraw_message(){ return $this->recall_message(); }

    private function blinQrSign($userId)
    {
        return sha1($this->appid . "|" . intval($userId) . "|" . $this->app_info["appkey"]);
    }

    public function get_user_qr()
    {
        $user = $this->user_info;
        $payload = ["type"=>"blin_user_qr", "appid"=>intval($this->appid), "user_id"=>intval($user["id"]), "sign"=>$this->blinQrSign($user["id"])];
        $this->json(1, "success", ["qr_data"=>json_encode($payload, JSON_UNESCAPED_UNICODE), "user"=>["id"=>intval($user["id"]), "username"=>$user["username"], "nickname"=>$user["nickname"], "avatar"=>$user["usertx"]]]);
    }

    public function scan_user_qr()
    {
        $raw = trim(strval(input("qr_data") ?: input("code") ?: input("text")));
        $data = json_decode($raw, true);
        if (!is_array($data) && preg_match('/user_id=([0-9]+)/', $raw, $m)) {
            $data = ["appid"=>intval(input("appid") ?: $this->appid), "user_id"=>intval($m[1]), "sign"=>strval(input("sign"))];
        }
        if (!is_array($data)) $this->json(0, "二维码无效");
        if (intval($data["appid"]) !== intval($this->appid)) $this->json(0, "二维码不属于当前应用");
        $userId = intval($data["user_id"]);
        if ($userId <= 0 || strval($data["sign"]) !== $this->blinQrSign($userId)) $this->json(0, "二维码校验失败");
        $target = $this->blinFriendUser($userId);
        if (!$target) $this->json(0, "用户不存在");
        if (intval(input("apply")) === 1) {
            $_POST["friend_id"] = $userId;
            return $this->add_friend();
        }
        $this->json(1, "success", ["user"=>$target]);
    }

'''


def patch_api_controller():
    source = API.read_text(errors="ignore")
    original = source
    if "blin-im-friend-recall-qr-wallet" not in source:
        marker = "\n    //搜索用户接口\n"
        if marker not in source:
            raise SystemExit("API_MARKER_NOT_FOUND")
        source = source.replace(marker, "\n" + API_BLOCK + marker, 1)

    # Keep friend requests out of forum/system notification APIs.
    source = source.replace(
        '$where = "m.appid = {$this->appid} and (m.user_id = {$user_all_info["id"]} or (m.send_to=0 and m.user_id=0))";',
        '$where = "m.appid = {$this->appid} and m.type <> 20 and (m.user_id = {$user_all_info["id"]} or (m.send_to=0 and m.user_id=0))";',
    )
    source = source.replace(
        '$where = "m.status = 0 and m.appid = {$this->appid} and (m.user_id = {$user_all_info["id"]} or (m.send_to=0 and m.user_id=0))";',
        '$where = "m.status = 0 and m.appid = {$this->appid} and m.type <> 20 and (m.user_id = {$user_all_info["id"]} or (m.send_to=0 and m.user_id=0))";',
    )

    if '$data["money"] = round(floatval($data["money"]), 2);' not in source:
        source = source.replace(
            '''            if (!$result) {
                $this->json(0, $validate->getError());
            }
            //判断不能给自己转账''',
            '''            if (!$result) {
                $this->json(0, $validate->getError());
            }
            $data["money"] = round(floatval($data["money"]), 2);
            if ($data["money"] <= 0) {
                $this->json(0, "转账金额必须大于0");
            }
            //判断不能给自己转账''',
            1,
        )
        source = source.replace(
            '$transfer_handling_fee = (int)($data["money"] * $this->app_info["forum_configuration"]["transfer_handling_fee"]);',
            '$transfer_handling_fee = round(floatval($data["money"]) * floatval($this->app_info["forum_configuration"]["transfer_handling_fee"]), 2);',
            1,
        )

    save(API, original, source, "friend_recall_qr_wallet")


def patch_im_controller():
    source = IM.read_text(errors="ignore")
    original = source
    if "public function login_session()" not in source:
        source = source.replace(
            "    public function online_user(){ return $this->simple('im_online_status','update_time'); }\n",
            r'''    public function online_user(){ return $this->simple('im_online_status','update_time'); }

    public function login_session()
    {
        if (Request::isAjax() || input('callback') != '') {
            if (Request::isPost() && trim(input('op')) === 'kick') {
                $id = intval(input('id'));
                $row = Db::name('user_login_session')->where('id', $id)->find();
                if (!$row) return $this->imFail('会话不存在');
                $this->blinRequireApp($row['appid']);
                Db::name('user_login_session')->where('id', $id)->delete();
                Db::name('online_record')->where('appid', intval($row['appid']))->where('token', $row['token'])->delete();
                try { (new \app\common\tool\WukongIM())->forceDeviceQuit(intval($row['appid']) . '_' . intval($row['user_id'])); } catch (\Exception $e) {}
                return $this->imOk('已踢下线');
            }
            $limit = input('limit') ? intval(input('limit')) : 10;
            $page = input('page') ? intval(input('page')) : 1;
            $query = Db::name('user_login_session')->alias('s')->leftJoin('user u', 'u.id=s.user_id');
            $countQuery = Db::name('user_login_session')->alias('s')->leftJoin('user u', 'u.id=s.user_id');
            $appid = input('appid');
            if ($appid !== '') {
                $this->blinRequireApp($appid);
                $query->where('s.appid', intval($appid));
                $countQuery->where('s.appid', intval($appid));
            } else {
                $this->blinScopeQuery($query, 's.appid');
                $this->blinScopeQuery($countQuery, 's.appid');
            }
            $keyword = trim(input('keyword'));
            if ($keyword !== '') {
                $query->where(function($q) use ($keyword) {
                    $q->where('u.username','like','%'.$keyword.'%')->whereOr('u.nickname','like','%'.$keyword.'%')->whereOr('s.user_id','like','%'.$keyword.'%')->whereOr('s.token','like','%'.$keyword.'%');
                });
                $countQuery->where(function($q) use ($keyword) {
                    $q->where('u.username','like','%'.$keyword.'%')->whereOr('u.nickname','like','%'.$keyword.'%')->whereOr('s.user_id','like','%'.$keyword.'%')->whereOr('s.token','like','%'.$keyword.'%');
                });
            }
            $rows = $query->field('s.*,u.username,u.nickname')->order('s.last_activity_time','desc')->page($page,$limit)->select();
            foreach ($rows as $k=>$v) {
                $rows[$k]['login_time_text'] = intval($v['login_time']) > 0 ? date('Y-m-d H:i:s', intval($v['login_time'])) : '';
                $rows[$k]['last_activity_time_text'] = intval($v['last_activity_time']) > 0 ? date('Y-m-d H:i:s', intval($v['last_activity_time'])) : '';
            }
            return $this->jsonp(['rows'=>$rows, 'total'=>$countQuery->count()]);
        }
        return $this->fetch();
    }
''',
            1,
        )
    if "$this->blinRequireUid($uid);" not in source[source.find("public function conversation_manage"):source.find("public function message_manage")]:
        source = source.replace(
            "                if ($uid === '') return $this->imFail('请输入UID');\n",
            "                if ($uid === '') return $this->imFail('请输入UID');\n                $this->blinRequireUid($uid);\n",
            1,
        )
        source = source.replace(
            "                if ($cid === '') return $this->imFail('请输入频道ID');\n",
            "                if ($cid === '') return $this->imFail('请输入频道ID');\n                if ($ct === 1) $this->blinRequireUid($cid);\n",
            1,
        )
    save(IM, original, source, "login_session_scope")


def patch_login_session_view():
    source = r'''{extend name="layout" /}
{block name="body"}
<div class="container-fluid p-t-15">
  <div class="row"><div class="col-lg-12"><div class="card">
    <header class="card-header"><div class="card-title">登录会话</div></header>
    <div class="card-body">
      <div class="row search-box">
        <div class="col-md-2 mb-2"><input class="form-control" id="appid" placeholder="APPID"></div>
        <div class="col-md-3 mb-2"><input class="form-control" id="keyword" placeholder="用户名/昵称/用户ID/token"></div>
        <div class="col-md-2 mb-2"><button class="btn btn-default" onclick="$('#table').bootstrapTable('refresh');"><i class="mdi mdi-magnify"></i> 搜索</button></div>
      </div>
      <table id="table"></table>
    </div>
  </div></div></div>
</div>
{/block}
{block name="js"}
<script>
window.parent.$("#iframe-content .mt-nav-bar").find('a.active').text("登录会话");
function kick(id){ if(!confirm('确认踢该设备下线？')) return; $.post('{:url("login_session")}',{op:'kick',id:id},function(res){ if(res.code==1){notify.success(res.msg||'成功');$('#table').bootstrapTable('refresh');}else{notify.error(res.msg||'失败')} },'json'); }
$('#table').bootstrapTable({
  classes: 'table table-bordered table-hover table-striped lyear-table',
  url: '{:url("login_session")}',
  uniqueId: 'id', idField: 'id', dataType: 'jsonp', method: 'get',
  pagination: true, sidePagination: 'server', pageSize: 10, pageList: [5,10,25,50,100],
  showColumns: true, showRefresh: true, totalField: 'total',
  queryParams: function(params){ return {limit:params.limit, page:(params.offset/params.limit)+1, appid:$('#appid').val(), keyword:$('#keyword').val()}; },
  columns: [
    {field:'id',title:'ID'},
    {field:'appid',title:'APPID'},
    {field:'user_id',title:'用户ID'},
    {field:'username',title:'账号'},
    {field:'nickname',title:'昵称'},
    {field:'terminal',title:'终端'},
    {field:'platform',title:'平台'},
    {field:'device',title:'设备'},
    {field:'login_ip',title:'登录IP'},
    {field:'login_time_text',title:'登录时间'},
    {field:'last_activity_time_text',title:'最后活跃'},
    {field:'operate',title:'操作',formatter:function(v,row){return '<button class="btn btn-sm btn-danger" onclick="kick('+row.id+')">踢下线</button>';}}
  ]
});
</script>
{/block}
'''
    original = IM_VIEW.read_text(errors="ignore") if IM_VIEW.exists() else ""
    if original != source:
        backup(IM_VIEW, "login_session_view")
        IM_VIEW.write_text(source)
        print("PATCHED", IM_VIEW)


def patch_system_controller():
    source = SYSTEM.read_text(errors="ignore")
    original = source
    if "Db::name('message_notification')->insert($add_data);\n        $sent = 0;" in source:
        source = source.replace(
            "        Db::name('message_notification')->insert($add_data);\n        $sent = 0;",
            "        $sent = 0;\n        if ($sendAsIm !== 1) {\n            Db::name('message_notification')->insert($add_data);\n        }",
            1,
        )
        source = source.replace(
            '$this->success($sendAsIm === 1 ? ("添加成功，已发送私聊 " . $sent . " 条") : "添加成功！");',
            '$this->success($sendAsIm === 1 ? ("已通过系统账号发送私聊 " . $sent . " 条") : "通知添加成功！");',
            1,
        )
    save(SYSTEM, original, source, "admin_im_not_mixed")


def main():
    patch_database()
    patch_app_controller()
    patch_app_edit_view()
    patch_api_controller()
    patch_im_controller()
    patch_login_session_view()
    patch_system_controller()


if __name__ == "__main__":
    main()
