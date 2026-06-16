#!/usr/bin/env python3
"""Patch app-scoped private chat clear scope.

Adds an app setting for private chat clearing:
- single: clear only the current user's visible chat history
- both: clear both users' visible chat history

The patch stores per-user clear timestamps instead of marking mr_messages as
deleted, so the conversation remains in the message list.
"""

from datetime import datetime
from pathlib import Path
import os
import re
import shutil
import subprocess


ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"
APP = ROOT / "application/admin/controller/App.php"
APP_EDIT = ROOT / "application/admin/view/app/edit.html"


def backup(path: Path, suffix: str) -> None:
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
    mysql(
        """CREATE TABLE IF NOT EXISTS `im_chat_clear_state` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `appid` bigint(20) NOT NULL DEFAULT 0,
  `user_id` bigint(20) unsigned NOT NULL,
  `peer_id` bigint(20) unsigned NOT NULL,
  `clear_time` datetime NOT NULL,
  `scope` varchar(16) NOT NULL DEFAULT 'single',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_app_user_peer` (`appid`,`user_id`,`peer_id`),
  KEY `idx_app_peer` (`appid`,`peer_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"""
    )
    mysql(
        """UPDATE `mr_app`
SET `im_configuration` = JSON_SET(
  COALESCE(NULLIF(`im_configuration`, ''), '{}'),
  '$.clear_chat_history_scope',
  COALESCE(JSON_UNQUOTE(JSON_EXTRACT(COALESCE(NULLIF(`im_configuration`, ''), '{}'), '$.clear_chat_history_scope')), 'single')
)
WHERE JSON_VALID(COALESCE(NULLIF(`im_configuration`, ''), '{}')) = 1"""
    )


def patch_app_controller():
    source = APP.read_text(errors="ignore")
    original = source
    source = source.replace(
        '"message_recall_minutes":"2"}',
        '"message_recall_minutes":"2","clear_chat_history_scope":"single"}',
    )
    if '"clear_chat_history_scope" => (isset($data["clear_chat_history_scope"])' not in source:
        source = source.replace(
            '''                    "message_recall_minutes" => max(0, intval(isset($data["message_recall_minutes"]) ? $data["message_recall_minutes"] : 2)),
                ], JSON_UNESCAPED_UNICODE),''',
            '''                    "message_recall_minutes" => max(0, intval(isset($data["message_recall_minutes"]) ? $data["message_recall_minutes"] : 2)),
                    "clear_chat_history_scope" => (isset($data["clear_chat_history_scope"]) && strval($data["clear_chat_history_scope"]) == "both") ? "both" : "single",
                ], JSON_UNESCAPED_UNICODE),''',
            1,
        )
    if '"clear_chat_history_scope" => "single",' not in source:
        source = source.replace(
            '''                    "message_recall_minutes" => 2,
                ];''',
            '''                    "message_recall_minutes" => 2,
                    "clear_chat_history_scope" => "single",
                ];''',
            1,
        )
    save(APP, original, source, "clear_chat_scope")


def patch_app_edit_view():
    source = APP_EDIT.read_text(errors="ignore")
    original = source
    if 'name="clear_chat_history_scope"' not in source:
        block = '''                        <div class="blin-setting-row blin-clear-chat-scope-card">
                            <div class="blin-setting-copy">
                                <span class="blin-setting-title">清空聊天范围</span>
                                <small class="blin-setting-desc">单边只清除当前用户可见历史；双向会同时清除双方可见历史。两种模式都会保留消息列表里的会话入口。</small>
                            </div>
                            <div class="blin-segmented-switch" role="group" aria-label="清空聊天范围">
                                <input type="radio" id="clear_chat_history_scope_single" value="single" name="clear_chat_history_scope" class="btn-check" autocomplete="off" {if $data.im_configuration.clear_chat_history_scope=='single'} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-on" for="clear_chat_history_scope_single"><i class="mdi mdi-account-outline"></i>单边</label>
                                <input type="radio" id="clear_chat_history_scope_both" value="both" name="clear_chat_history_scope" class="btn-check" autocomplete="off" {if $data.im_configuration.clear_chat_history_scope=='both'} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-off" for="clear_chat_history_scope_both"><i class="mdi mdi-account-multiple-outline"></i>双向</label>
                            </div>
                        </div>
'''
        anchor_idx = source.find("blin-system-friend-switch-card")
        insert_idx = source.find('                        <div class="row g-3 mt-1">', anchor_idx)
        if anchor_idx < 0 or insert_idx < 0:
            raise SystemExit("APP_EDIT_INSERT_ANCHOR_NOT_FOUND")
        source = source[:insert_idx] + block + source[insert_idx:]
    save(APP_EDIT, original, source, "clear_chat_scope_view")


API_HELPERS = r'''
    // blin-chat-clear-scope
    private function blinEnsureChatClearTable()
    {
        static $ready = false;
        if ($ready) return;
        try {
            Db::execute("CREATE TABLE IF NOT EXISTS `im_chat_clear_state` (`id` bigint(20) unsigned NOT NULL AUTO_INCREMENT, `appid` bigint(20) NOT NULL DEFAULT 0, `user_id` bigint(20) unsigned NOT NULL, `peer_id` bigint(20) unsigned NOT NULL, `clear_time` datetime NOT NULL, `scope` varchar(16) NOT NULL DEFAULT 'single', `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP, `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (`id`), UNIQUE KEY `uniq_app_user_peer` (`appid`,`user_id`,`peer_id`), KEY `idx_app_peer` (`appid`,`peer_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
            $ready = true;
        } catch (\Exception $e) {}
    }

    private function blinChatClearScope()
    {
        $config = isset($this->app_info["im_configuration"]) && is_array($this->app_info["im_configuration"]) ? $this->app_info["im_configuration"] : [];
        $scope = isset($config["clear_chat_history_scope"]) ? strval($config["clear_chat_history_scope"]) : "single";
        return $scope === "both" ? "both" : "single";
    }

    private function blinUpsertChatClearState($userId, $peerId, $scope, $clearTime)
    {
        $this->blinEnsureChatClearTable();
        Db::execute("INSERT INTO `im_chat_clear_state` (`appid`,`user_id`,`peer_id`,`clear_time`,`scope`,`created_at`,`updated_at`) VALUES (:appid,:uid,:peer,:clear_time,:scope,:created_at,:updated_at) ON DUPLICATE KEY UPDATE `clear_time`=VALUES(`clear_time`),`scope`=VALUES(`scope`),`updated_at`=VALUES(`updated_at`)", [
            "appid" => intval($this->appid),
            "uid" => intval($userId),
            "peer" => intval($peerId),
            "clear_time" => $clearTime,
            "scope" => $scope,
            "created_at" => $clearTime,
            "updated_at" => $clearTime,
        ]);
    }

    private function blinChatClearTime($userId, $peerId)
    {
        $this->blinEnsureChatClearTable();
        try {
            $row = Db::table("im_chat_clear_state")
                ->where("appid", intval($this->appid))
                ->where("user_id", intval($userId))
                ->where("peer_id", intval($peerId))
                ->find();
            if ($row && isset($row["clear_time"]) && $row["clear_time"] !== "") {
                return strval($row["clear_time"]);
            }
        } catch (\Exception $e) {}
        return "";
    }

    private function blinChatClearWhere($userId, $peerId)
    {
        $clearTime = $this->blinChatClearTime($userId, $peerId);
        if ($clearTime === "") return "";
        return " AND create_time > '" . addslashes($clearTime) . "' ";
    }
'''


CLEAR_METHOD = r'''    //清空聊天记录
    public function clear_chat_history()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate($rule);
        $result = $validate->check($data);
        if (!$result) {
            $this->json(0, $validate->getError());
        }

        $user_all_info = $this->user_info;
        $peer_id = intval(input("peer_id") ?: input("friend_id") ?: input("receiver_id") ?: input("user_id"));
        if ($peer_id <= 0 || $peer_id == intval($user_all_info["id"])) {
            $this->json(0, "用户不存在");
        }
        $peer_info = Db::name("user")->where("id", $peer_id)->where("appid", $this->appid)->find();
        if (!$peer_info) {
            $this->json(0, "用户不存在");
        }

        $uid = intval($user_all_info["id"]);
        $scope = $this->blinChatClearScope();
        $now = date("Y-m-d H:i:s", time());
        $this->blinUpsertChatClearState($uid, $peer_id, $scope, $now);
        if ($scope === "both") {
            $this->blinUpsertChatClearState($peer_id, $uid, $scope, $now);
        }
        Db::name("messages")
            ->where("sender_id", $peer_id)
            ->where("receiver_id", $uid)
            ->where("is_read", 0)
            ->update(["is_read" => 1]);
        $this->json(1, $scope === "both" ? "双方聊天记录已清空" : "聊天记录已清空", [
            "scope" => $scope,
            "clear_time" => $now,
        ]);
    }
'''


def patch_api_controller():
    source = API.read_text(errors="ignore")
    original = source

    helper_pattern = re.compile(
        r"\n    // blin-chat-clear-scope\n.*?\n    //标记私聊消息为已读",
        re.S,
    )
    if helper_pattern.search(source):
        source = helper_pattern.sub("\n" + API_HELPERS + "\n    //标记私聊消息为已读", source, count=1)
    else:
        marker = "\n    //标记私聊消息为已读"
        if marker not in source:
            raise SystemExit("API_HELPER_MARKER_NOT_FOUND")
        source = source.replace(marker, "\n" + API_HELPERS + marker, 1)

    clear_pattern = re.compile(
        r"    //清空(?:双方)?聊天记录\s+public function clear_chat_history\(\)\s+\{.*?\n    \}\n\n    public function delete_chat_history\(\)",
        re.S,
    )
    if not clear_pattern.search(source):
        raise SystemExit("CLEAR_CHAT_HISTORY_METHOD_NOT_FOUND")
    source = clear_pattern.sub(CLEAR_METHOD + "\n    public function delete_chat_history()", source, count=1)

    if "$chat_clear_time = $this->blinChatClearTime($uid, $peer_id);" not in source:
        source = source.replace(
            '''                $peer_id = intval($value["sender_id"] == $uid ? $value["receiver_id"] : $value["sender_id"]);
                $user_info = Db::name("user")->where("id", $peer_id)->find();''',
            '''                $peer_id = intval($value["sender_id"] == $uid ? $value["receiver_id"] : $value["sender_id"]);
                $chat_clear_time = $this->blinChatClearTime($uid, $peer_id);
                $user_info = Db::name("user")->where("id", $peer_id)->find();''',
            1,
        )

    if '$row["is_chat_cleared"] = 1;' not in source:
        source = source.replace(
            '''                if (intval(isset($value["is_recalled"]) ? $value["is_recalled"] : 0) === 1) {
                    $row["content"] = "消息已撤回";
                    $row["message_type"] = 0;
                    $row["im_payload"] = [
                        "version"=>"1.0", "message_id"=>intval($value["id"]), "conversation_type"=>"single", "channel_type"=>1,
                        "from_uid"=>$this->appid . "_" . intval($value["sender_id"]), "to_uid"=>$this->appid . "_" . intval($value["receiver_id"]),
                        "from_user_id"=>intval($value["sender_id"]), "to_user_id"=>intval($value["receiver_id"]),
                        "msg_type"=>"recall", "message_type"=>0, "content"=>["message_id"=>intval($value["id"]), "text"=>"消息已撤回"],
                        "is_recalled"=>1, "create_time"=>$value["create_time"],
                    ];
                }

                if (intval($value["sender_id"]) == $uid) {''',
            '''                if (intval(isset($value["is_recalled"]) ? $value["is_recalled"] : 0) === 1) {
                    $row["content"] = "消息已撤回";
                    $row["message_type"] = 0;
                    $row["im_payload"] = [
                        "version"=>"1.0", "message_id"=>intval($value["id"]), "conversation_type"=>"single", "channel_type"=>1,
                        "from_uid"=>$this->appid . "_" . intval($value["sender_id"]), "to_uid"=>$this->appid . "_" . intval($value["receiver_id"]),
                        "from_user_id"=>intval($value["sender_id"]), "to_user_id"=>intval($value["receiver_id"]),
                        "msg_type"=>"recall", "message_type"=>0, "content"=>["message_id"=>intval($value["id"]), "text"=>"消息已撤回"],
                        "is_recalled"=>1, "create_time"=>$value["create_time"],
                    ];
                }
                if ($chat_clear_time !== "" && strtotime(strval($value["create_time"])) <= strtotime($chat_clear_time)) {
                    $row["msg_time"] = $chat_clear_time;
                    $row["content"] = "暂无聊天记录";
                    $row["image_path"] = "";
                    $row["message_type"] = 0;
                    $row["money_type"] = 0;
                    $row["im_payload"] = null;
                    $row["is_chat_cleared"] = 1;
                }

                if (intval($value["sender_id"]) == $uid) {''',
            1,
        )

    source = source.replace(
        '''                if (intval($value["sender_id"]) == $uid) {
                    $row["unread_quantity"] = 0;
                } else {
                    $row["unread_quantity"] = Db::name("messages")
                        ->where("sender_id", $peer_id)
                        ->where("receiver_id", $uid)
                        ->where("is_read", 0)
                        ->count();
                }''',
        '''                if (intval($value["sender_id"]) == $uid) {
                    $row["unread_quantity"] = 0;
                } else {
                    $unreadQuery = Db::name("messages")
                        ->where("sender_id", $peer_id)
                        ->where("receiver_id", $uid)
                        ->where("is_read", 0);
                    if ($chat_clear_time !== "") {
                        $unreadQuery = $unreadQuery->where("create_time", ">", $chat_clear_time);
                    }
                    $row["unread_quantity"] = $unreadQuery->count();
                }''',
        1,
    )

    source = source.replace(
        '''        Db::name("messages")->where("sender_id", $receiver_info["id"])->where("receiver_id", $user_all_info["id"])->where("is_read", 0)->update(["is_read" => 1]);
        $sql = "SELECT * FROM mr_messages WHERE is_deleted = 0 AND ((sender_id = {$user_all_info["id"]} AND receiver_id = {$receiver_info["id"]}) OR (sender_id = {$receiver_info["id"]} AND receiver_id = {$user_all_info["id"]})) ORDER BY create_time DESC LIMIT {$page_offect},{$pagesize};";
        $list = Db::query($sql);
        $count_sql = "SELECT IFNULL(count(*),0) as count FROM mr_messages WHERE is_deleted = 0 AND ((sender_id = {$user_all_info["id"]} AND receiver_id = {$receiver_info["id"]}) OR (sender_id = {$receiver_info["id"]} AND receiver_id = {$user_all_info["id"]})) ORDER BY create_time DESC;";''',
        '''        Db::name("messages")->where("sender_id", $receiver_info["id"])->where("receiver_id", $user_all_info["id"])->where("is_read", 0)->update(["is_read" => 1]);
        $clear_where = $this->blinChatClearWhere(intval($user_all_info["id"]), intval($receiver_info["id"]));
        $sql = "SELECT * FROM mr_messages WHERE is_deleted = 0 {$clear_where} AND ((sender_id = {$user_all_info["id"]} AND receiver_id = {$receiver_info["id"]}) OR (sender_id = {$receiver_info["id"]} AND receiver_id = {$user_all_info["id"]})) ORDER BY create_time DESC LIMIT {$page_offect},{$pagesize};";
        $list = Db::query($sql);
        $count_sql = "SELECT IFNULL(count(*),0) as count FROM mr_messages WHERE is_deleted = 0 {$clear_where} AND ((sender_id = {$user_all_info["id"]} AND receiver_id = {$receiver_info["id"]}) OR (sender_id = {$receiver_info["id"]} AND receiver_id = {$user_all_info["id"]})) ORDER BY create_time DESC;";''',
        1,
    )

    save(API, original, source, "clear_chat_scope_api")


if __name__ == "__main__":
    patch_database()
    patch_app_controller()
    patch_app_edit_view()
    patch_api_controller()
