#!/usr/bin/env python3
"""Patch ThinkPHP Api.php with private-chat read receipt support.

Adds:
  POST /mark_chat_read
  Alias endpoints: /read_chat_messages, /mark_message_read

Also makes /get_chat_log return mr_messages.is_read in both the legacy message
envelope and the unified im_payload so Flutter can restore the double-check
state after reopening a chat.
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


if "public function mark_chat_read()" not in source:
    marker = "\n    //清空双方聊天记录\n    public function clear_chat_history()"
    if marker not in source:
        raise SystemExit("CLEAR_CHAT_HISTORY_MARKER_NOT_FOUND")

    code = r'''
    //标记私聊消息为已读
    public function mark_chat_read()
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

        $message_ids = [];
        $ids_text = strval(input("message_ids") ?: input("message_id"));
        if ($ids_text !== "") {
            foreach (explode(",", $ids_text) as $id) {
                $id = intval(trim($id));
                if ($id > 0) {
                    $message_ids[] = $id;
                }
            }
        }

        $query = Db::name("messages")
            ->where("sender_id", $peer_id)
            ->where("receiver_id", intval($user_all_info["id"]))
            ->where("is_read", 0);
        if (!empty($message_ids)) {
            $query = $query->where("id", "in", $message_ids);
        }
        $count = $query->update(["is_read" => 1]);
        $this->json(1, "已读成功", ["count" => intval($count)]);
    }

    public function read_chat_messages()
    {
        return $this->mark_chat_read();
    }

    public function mark_message_read()
    {
        return $this->mark_chat_read();
    }
'''
    source = source.replace(marker, "\n" + code + marker, 1)


client_payload_line = '        $client_payload = input("im_payload") ?: input("payload");\n'
client_payload_with_no = client_payload_line + (
    '        $client_msg_no_from_payload = "";\n'
    '        if ($client_payload) {\n'
    '            $decoded_client_no_payload = json_decode($client_payload, true);\n'
    '            if (is_array($decoded_client_no_payload) && isset($decoded_client_no_payload["client_msg_no"]) && strval($decoded_client_no_payload["client_msg_no"]) !== "") {\n'
    '                $client_msg_no_from_payload = strval($decoded_client_no_payload["client_msg_no"]);\n'
    '            }\n'
    '        }\n'
)
if "$client_msg_no_from_payload" not in source:
    source = replace_once(source, client_payload_line, client_payload_with_no)


source = replace_once(
    source,
    '        $im_client_no = "php_msg_" . $message_id . "_" . time();\n',
    '        $im_client_no = $client_msg_no_from_payload !== "" ? $client_msg_no_from_payload : ("php_msg_" . $message_id . "_" . time());\n',
)


before_select = (
    '        $pagesize = $this->limit;\n'
    '        $page_offect = ($this->page - 1) * $this->limit;\n'
)
after_select = before_select + (
    '        //进入聊天详情时，先把对方发给我的未读消息置为已读，保证本次返回也是最新状态。\n'
    '        Db::name("messages")->where("sender_id", $receiver_info["id"])->where("receiver_id", $user_all_info["id"])->where("is_read", 0)->update(["is_read" => 1]);\n'
)
if "保证本次返回也是最新状态" not in source:
    source = replace_once(source, before_select, after_select)


message_money = '            $result[$key]["message"]["money_type"] = $value["money_type"];\n'
message_read = message_money + (
    '            $result[$key]["message"]["is_read"] = intval($value["is_read"]);\n'
    '            $result[$key]["message"]["read"] = intval($value["is_read"]) == 1;\n'
    '            $result[$key]["is_read"] = intval($value["is_read"]);\n'
    '            $result[$key]["read"] = intval($value["is_read"]) == 1;\n'
)
if '$result[$key]["message"]["is_read"]' not in source:
    source = replace_once(source, message_money, message_read)


payload_type = '                "message_type" => intval($value["message_type"]),\n'
payload_read = payload_type + (
    '                "is_read" => intval($value["is_read"]),\n'
    '                "read" => intval($value["is_read"]) == 1,\n'
)
if '"is_read" => intval($value["is_read"])' not in source:
    source = replace_once(source, payload_type, payload_read)


if source == original:
    print("CHAT_READ_RECEIPTS_API_ALREADY_UP_TO_DATE")
    raise SystemExit(0)

backup = api_path.with_name(
    "Api.php.bak_chat_read_receipts_" + datetime.now().strftime("%Y%m%d%H%M%S")
)
backup.write_text(original)
api_path.write_text(source)
print("PATCHED_CHAT_READ_RECEIPTS_API", backup)
