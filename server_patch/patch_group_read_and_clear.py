#!/usr/bin/env python3
"""Patch group read state and per-user group conversation clearing."""

from datetime import datetime
from pathlib import Path
import shutil


ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"


def backup(path: Path, suffix: str) -> None:
    target = path.with_name(
        f"{path.name}.bak_{suffix}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    shutil.copy2(path, target)
    print("BACKUP", target)


HELPERS = r'''
    // blin-group-read-clear-start
    private function blinEnsureGroupReadClearTables()
    {
        static $ready = false;
        if ($ready) return;
        try {
            Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_group_read_state` (`id` bigint(20) unsigned NOT NULL AUTO_INCREMENT, `appid` bigint(20) NOT NULL DEFAULT 0, `group_id` bigint(20) unsigned NOT NULL DEFAULT 0, `user_id` bigint(20) unsigned NOT NULL DEFAULT 0, `last_read_message_id` bigint(20) unsigned NOT NULL DEFAULT 0, `last_read_at` datetime DEFAULT NULL, `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP, `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (`id`), UNIQUE KEY `uniq_group_user` (`appid`,`group_id`,`user_id`), KEY `idx_user` (`appid`,`user_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
            Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_group_clear_state` (`id` bigint(20) unsigned NOT NULL AUTO_INCREMENT, `appid` bigint(20) NOT NULL DEFAULT 0, `group_id` bigint(20) unsigned NOT NULL DEFAULT 0, `user_id` bigint(20) unsigned NOT NULL DEFAULT 0, `clear_message_id` bigint(20) unsigned NOT NULL DEFAULT 0, `clear_time` datetime NOT NULL, `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP, `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (`id`), UNIQUE KEY `uniq_group_user` (`appid`,`group_id`,`user_id`), KEY `idx_user` (`appid`,`user_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
            $ready = true;
        } catch (\Exception $e) {}
    }

    private function blinGroupReadState($groupId, $userId)
    {
        $this->blinEnsureGroupReadClearTables();
        try {
            $row = Db::name("im_group_read_state")
                ->where("appid", intval($this->appid))
                ->where("group_id", intval($groupId))
                ->where("user_id", intval($userId))
                ->find();
            return $row ? $row : null;
        } catch (\Exception $e) {}
        return null;
    }

    private function blinGroupClearState($groupId, $userId)
    {
        $this->blinEnsureGroupReadClearTables();
        try {
            $row = Db::name("im_group_clear_state")
                ->where("appid", intval($this->appid))
                ->where("group_id", intval($groupId))
                ->where("user_id", intval($userId))
                ->find();
            return $row ? $row : null;
        } catch (\Exception $e) {}
        return null;
    }

    private function blinUpsertGroupReadState($groupId, $userId, $messageId, $readAt)
    {
        $this->blinEnsureGroupReadClearTables();
        Db::execute("INSERT INTO `mr_im_group_read_state` (`appid`,`group_id`,`user_id`,`last_read_message_id`,`last_read_at`,`created_at`,`updated_at`) VALUES (:appid,:group_id,:user_id,:message_id,:read_at,:created_at,:updated_at) ON DUPLICATE KEY UPDATE `last_read_message_id`=GREATEST(`last_read_message_id`, VALUES(`last_read_message_id`)),`last_read_at`=VALUES(`last_read_at`),`updated_at`=VALUES(`updated_at`)", [
            "appid" => intval($this->appid),
            "group_id" => intval($groupId),
            "user_id" => intval($userId),
            "message_id" => intval($messageId),
            "read_at" => $readAt,
            "created_at" => $readAt,
            "updated_at" => $readAt,
        ]);
    }

    private function blinUpsertGroupClearState($groupId, $userId, $messageId, $clearTime)
    {
        $this->blinEnsureGroupReadClearTables();
        Db::execute("INSERT INTO `mr_im_group_clear_state` (`appid`,`group_id`,`user_id`,`clear_message_id`,`clear_time`,`created_at`,`updated_at`) VALUES (:appid,:group_id,:user_id,:message_id,:clear_time,:created_at,:updated_at) ON DUPLICATE KEY UPDATE `clear_message_id`=GREATEST(`clear_message_id`, VALUES(`clear_message_id`)),`clear_time`=VALUES(`clear_time`),`updated_at`=VALUES(`updated_at`)", [
            "appid" => intval($this->appid),
            "group_id" => intval($groupId),
            "user_id" => intval($userId),
            "message_id" => intval($messageId),
            "clear_time" => $clearTime,
            "created_at" => $clearTime,
            "updated_at" => $clearTime,
        ]);
    }
    // blin-group-read-clear-end
'''


METHODS = r'''
    public function mark_group_chat_read()
    {
        $data = input();
        $rule = ["usertoken|用户token" => "require", "group_id|群ID" => "require|number"];
        $validate = new Validate($rule);
        if (!$validate->check($data)) $this->json(0, $validate->getError());
        $user = $this->im_group_user();
        $this->ensure_im_group_tables();
        $this->blinEnsureGroupReadClearTables();
        $groupId = intval($data["group_id"]);
        if (!$this->im_group_member($groupId, intval($user["id"]))) $this->json(0, "你不在该群聊中");
        $messageId = 0;
        $idsText = trim(strval(input("message_ids") ?: input("message_id")));
        if ($idsText !== "") {
            foreach (explode(",", $idsText) as $id) {
                $id = intval(trim($id));
                if ($id > $messageId) $messageId = $id;
            }
        }
        if ($messageId <= 0) {
            $messageId = intval(Db::name("im_group_messages")->where("appid", intval($this->appid))->where("group_id", $groupId)->max("id"));
        }
        $now = date("Y-m-d H:i:s");
        $this->blinUpsertGroupReadState($groupId, intval($user["id"]), $messageId, $now);
        $this->json(1, "群消息已读", ["count" => 0, "last_read_message_id" => $messageId, "last_read_at" => $now]);
    }

    public function read_group_chat_messages(){ return $this->mark_group_chat_read(); }
    public function mark_group_messages_read(){ return $this->mark_group_chat_read(); }
    public function mark_im_group_read(){ return $this->mark_group_chat_read(); }
    public function read_im_group_messages(){ return $this->mark_group_chat_read(); }

    public function clear_group_chat_history()
    {
        $data = input();
        $rule = ["usertoken|用户token" => "require", "group_id|群ID" => "require|number"];
        $validate = new Validate($rule);
        if (!$validate->check($data)) $this->json(0, $validate->getError());
        $user = $this->im_group_user();
        $this->ensure_im_group_tables();
        $this->blinEnsureGroupReadClearTables();
        $groupId = intval($data["group_id"]);
        if (!$this->im_group_member($groupId, intval($user["id"]))) $this->json(0, "你不在该群聊中");
        $messageId = intval(Db::name("im_group_messages")->where("appid", intval($this->appid))->where("group_id", $groupId)->max("id"));
        $now = date("Y-m-d H:i:s");
        $this->blinUpsertGroupClearState($groupId, intval($user["id"]), $messageId, $now);
        $this->blinUpsertGroupReadState($groupId, intval($user["id"]), $messageId, $now);
        $this->json(1, "群聊天记录已清空", ["clear_message_id" => $messageId, "clear_time" => $now]);
    }

    public function delete_group_chat_history(){ return $this->clear_group_chat_history(); }
    public function clear_im_group_chat_history(){ return $this->clear_group_chat_history(); }
    public function delete_im_group_chat_history(){ return $this->clear_group_chat_history(); }
    public function clear_group_chat_log(){ return $this->clear_group_chat_history(); }
    public function delete_group_conversation(){ return $this->clear_group_chat_history(); }
    public function remove_group_conversation(){ return $this->clear_group_chat_history(); }
    public function delete_group_message_session(){ return $this->clear_group_chat_history(); }
    public function delete_im_group_session(){ return $this->clear_group_chat_history(); }
    public function hide_group_conversation(){ return $this->clear_group_chat_history(); }
'''


def replace_once(source: str, old: str, new: str) -> str:
    if old not in source:
        raise SystemExit(f"marker_not_found:{old[:80]}")
    return source.replace(old, new, 1)


def main() -> None:
    source = API.read_text(errors="ignore")
    original = source

    if "// blin-group-read-clear-start" not in source:
        marker = "\n    private function im_group_user()"
        source = replace_once(source, marker, "\n" + HELPERS + marker)

    if "public function mark_group_chat_read()" not in source:
        marker = "\n    public function get_im_group_chat_log()"
        source = replace_once(source, marker, "\n" + METHODS + marker)

    if "mr_im_group_read_state" not in source.split("private function ensure_im_group_tables()", 1)[1].split("private function im_group_user()", 1)[0]:
        source = replace_once(
            source,
            '        Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_group_messages` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `group_id` int(11) NOT NULL DEFAULT 0, `sender_id` int(11) NOT NULL DEFAULT 0, `message_type` int(11) NOT NULL DEFAULT 0, `content` text, `payload` mediumtext, `client_msg_no` varchar(128) NOT NULL DEFAULT \'\', `create_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), KEY `idx_group_id` (`group_id`), KEY `idx_create_time` (`create_time`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");\n',
            '        Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_group_messages` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `group_id` int(11) NOT NULL DEFAULT 0, `sender_id` int(11) NOT NULL DEFAULT 0, `message_type` int(11) NOT NULL DEFAULT 0, `content` text, `payload` mediumtext, `client_msg_no` varchar(128) NOT NULL DEFAULT \'\', `create_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), KEY `idx_group_id` (`group_id`), KEY `idx_create_time` (`create_time`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");\n        $this->blinEnsureGroupReadClearTables();\n',
        )

    old_list = '        foreach ($rows as $k=>$v) $rows[$k]["my_role"] = $this->im_group_role_name($v["role"]);\n        $this->json(1, "success", ["list"=>$rows]);\n'
    new_list = '''        foreach ($rows as $k=>$v) {
            $rows[$k]["my_role"] = $this->im_group_role_name($v["role"]);
            $read = $this->blinGroupReadState(intval($v["id"]), intval($user["id"]));
            $clear = $this->blinGroupClearState(intval($v["id"]), intval($user["id"]));
            $lastReadId = $read ? intval($read["last_read_message_id"]) : 0;
            $clearId = $clear ? intval($clear["clear_message_id"]) : 0;
            if ($clearId > $lastReadId) $lastReadId = $clearId;
            $unreadQuery = Db::name("im_group_messages")->where("appid", intval($this->appid))->where("group_id", intval($v["id"]))->where("sender_id", "<>", intval($user["id"]));
            if ($lastReadId > 0) $unreadQuery = $unreadQuery->where("id", ">", $lastReadId);
            $rows[$k]["unread_count"] = intval($unreadQuery->count());
            $rows[$k]["unread_num"] = $rows[$k]["unread_count"];
            $rows[$k]["message_unread_count"] = $rows[$k]["unread_count"];
        }
        $this->json(1, "success", ["list"=>$rows]);
'''
    if old_list in source:
        source = source.replace(old_list, new_list, 1)

    old_query = '        $rows = Db::name("im_group_messages")->where("appid", $this->appid)->where("group_id", $groupId)->order("id desc")->limit($offset, $limit)->select();\n'
    new_query = '''        $clear = $this->blinGroupClearState($groupId, intval($user["id"]));
        $clearId = $clear ? intval($clear["clear_message_id"]) : 0;
        $messageQuery = Db::name("im_group_messages")->where("appid", $this->appid)->where("group_id", $groupId);
        if ($clearId > 0) $messageQuery = $messageQuery->where("id", ">", $clearId);
        $rows = $messageQuery->order("id desc")->limit($offset, $limit)->select();
'''
    if old_query in source:
        source = source.replace(old_query, new_query, 1)

    old_count = '        $count = Db::name("im_group_messages")->where("appid", $this->appid)->where("group_id", $groupId)->count();\n        $this->json(1, "success", ["list"=>$list, "pagecount"=>ceil($count / $limit) == 0 ? 1 : ceil($count / $limit), "current_number"=>$page]);\n'
    new_count = '''        $countQuery = Db::name("im_group_messages")->where("appid", $this->appid)->where("group_id", $groupId);
        if (isset($clearId) && $clearId > 0) $countQuery = $countQuery->where("id", ">", $clearId);
        $count = $countQuery->count();
        if ($page == 1) {
            $lastReadId = 0;
            foreach ($rows as $r) {
                if (intval($r["id"]) > $lastReadId) $lastReadId = intval($r["id"]);
            }
            if ($lastReadId > 0) $this->blinUpsertGroupReadState($groupId, intval($user["id"]), $lastReadId, date("Y-m-d H:i:s"));
        }
        $this->json(1, "success", ["list"=>$list, "pagecount"=>ceil($count / $limit) == 0 ? 1 : ceil($count / $limit), "current_number"=>$page]);
'''
    if old_count in source:
        source = source.replace(old_count, new_count, 1)

    for alias in [
        ("delete_conversation", "clear_chat_history"),
        ("remove_conversation", "clear_chat_history"),
        ("delete_message_session", "clear_chat_history"),
        ("delete_chat_session", "clear_chat_history"),
        ("hide_conversation", "clear_chat_history"),
    ]:
        name, target = alias
        if f"public function {name}()" not in source:
            marker = "    public function delete_chat_history()\n"
            source = replace_once(
                source,
                marker,
                f"    public function {name}(){{ return $this->{target}(); }}\n\n" + marker,
            )

    if source == original:
        print("NO_CHANGE", API)
        return
    backup(API, "group_read_clear")
    API.write_text(source)
    print("PATCHED", API)


if __name__ == "__main__":
    main()
