#!/usr/bin/env python3
"""Patch ThinkPHP Api.php with a two-sided private chat history clear API.

Adds:
  POST /clear_chat_history
  Alias endpoints: /delete_chat_history, /clear_im_chat_history,
                   /delete_im_chat_history, /clear_chat_log, /delete_chat_log

The existing message list already hides rows where mr_messages.is_deleted = 1.
This patch applies the same filter to chat detail history and soft-deletes the
two users' private messages instead of physically deleting rows.
"""
from datetime import datetime
from pathlib import Path


api_path = Path("/www/wwwroot/blinlin/application/api/controller/Api.php")
source = api_path.read_text(errors="ignore")
original = source


def replace_once(text: str, old: str, new: str) -> str:
    if old not in text:
        return text
    return text.replace(old, new, 1)


history_sql_old = (
    '$sql = "SELECT * FROM mr_messages WHERE (sender_id = {$user_all_info["id"]} '
    'AND receiver_id = {$receiver_info["id"]}) OR (sender_id = {$receiver_info["id"]} '
    'AND receiver_id = {$user_all_info["id"]}) ORDER BY create_time DESC LIMIT {$page_offect},{$pagesize};";'
)
history_sql_new = (
    '$sql = "SELECT * FROM mr_messages WHERE is_deleted = 0 AND '
    '((sender_id = {$user_all_info["id"]} AND receiver_id = {$receiver_info["id"]}) '
    'OR (sender_id = {$receiver_info["id"]} AND receiver_id = {$user_all_info["id"]})) '
    'ORDER BY create_time DESC LIMIT {$page_offect},{$pagesize};";'
)
count_sql_old = (
    '$count_sql = "SELECT IFNULL(count(*),0) as count FROM mr_messages WHERE '
    '(sender_id = {$user_all_info["id"]} AND receiver_id = {$receiver_info["id"]}) '
    'OR (sender_id = {$receiver_info["id"]} AND receiver_id = {$user_all_info["id"]}) '
    'ORDER BY create_time DESC;";'
)
count_sql_new = (
    '$count_sql = "SELECT IFNULL(count(*),0) as count FROM mr_messages WHERE '
    'is_deleted = 0 AND ((sender_id = {$user_all_info["id"]} AND receiver_id = {$receiver_info["id"]}) '
    'OR (sender_id = {$receiver_info["id"]} AND receiver_id = {$user_all_info["id"]})) '
    'ORDER BY create_time DESC;";'
)

source = replace_once(source, history_sql_old, history_sql_new)
source = replace_once(source, count_sql_old, count_sql_new)

if "public function clear_chat_history()" not in source:
    marker = "\n    //获取消息详情\n    public function get_chat_log()"
    if marker not in source:
        raise SystemExit("GET_CHAT_LOG_MARKER_NOT_FOUND")

    code = r'''
    //清空双方聊天记录
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
        $now = date("Y-m-d H:i:s", time());
        $sql = "UPDATE mr_messages SET is_deleted = 1, update_time = '{$now}' WHERE is_deleted = 0 AND ((sender_id = {$uid} AND receiver_id = {$peer_id}) OR (sender_id = {$peer_id} AND receiver_id = {$uid}))";
        try {
            $count = Db::execute($sql);
        } catch (\Exception $e) {
            $sql = "UPDATE mr_messages SET is_deleted = 1 WHERE is_deleted = 0 AND ((sender_id = {$uid} AND receiver_id = {$peer_id}) OR (sender_id = {$peer_id} AND receiver_id = {$uid}))";
            $count = Db::execute($sql);
        }
        $this->json(1, "双方聊天记录已清空", ["count" => intval($count)]);
    }

    public function delete_chat_history()
    {
        return $this->clear_chat_history();
    }

    public function clear_im_chat_history()
    {
        return $this->clear_chat_history();
    }

    public function delete_im_chat_history()
    {
        return $this->clear_chat_history();
    }

    public function clear_chat_log()
    {
        return $this->clear_chat_history();
    }

    public function delete_chat_log()
    {
        return $this->clear_chat_history();
    }
'''
    source = source.replace(marker, "\n" + code + marker, 1)

if source == original:
    print("CLEAR_CHAT_HISTORY_API_ALREADY_UP_TO_DATE")
    raise SystemExit(0)

backup = api_path.with_name(
    "Api.php.bak_clear_chat_history_" + datetime.now().strftime("%Y%m%d%H%M%S")
)
backup.write_text(original)
api_path.write_text(source)
print("PATCHED_CLEAR_CHAT_HISTORY_API", backup)
