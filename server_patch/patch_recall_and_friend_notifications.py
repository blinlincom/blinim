#!/usr/bin/env python3
"""Make recall state durable in history and persist friend request notices."""

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


def replace_once(source: str, old: str, new: str, label: str) -> str:
    if old not in source:
        raise SystemExit(f"{label}_MARKER_NOT_FOUND")
    return source.replace(old, new, 1)


def main() -> None:
    source = API.read_text(errors="ignore")
    original = source

    if "private function blinFriendNotification(" not in source:
        source = replace_once(
            source,
            '''    private function blinFriendEvent($toUserId, $action, $fromUser, $message = "")
    {''',
            '''    private function blinFriendNotification($toUserId, $action, $fromUser, $message = "")
    {
        try {
            $name = strval($fromUser["nickname"] ?: $fromUser["username"]);
            $title = "好友申请";
            $content = $name . " 请求添加你为好友：" . $message;
            if ($action === "accepted") {
                $title = "好友申请已通过";
                $content = $name . " 已通过你的好友申请";
            } elseif ($action === "rejected") {
                $title = "好友申请已拒绝";
                $content = $name . " 已拒绝你的好友申请";
            }
            Db::name("message_notification")->insert([
                "appid" => intval($this->appid),
                "user_id" => intval($toUserId),
                "title" => $title,
                "content" => $content,
                "send_to" => 0,
                "type" => 20,
                "status" => 0,
                "postid" => intval($fromUser["id"]),
                "time" => date("Y-m-d H:i:s"),
            ]);
        } catch (\\Exception $e) {}
    }

    private function blinFriendEvent($toUserId, $action, $fromUser, $message = "")
    {
        $this->blinFriendNotification($toUserId, $action, $fromUser, $message);''',
            "friend_notification_method",
        )

    if '"is_recalled" => intval(isset($value["is_recalled"]) ? $value["is_recalled"] : 0),' not in source:
        source = replace_once(
            source,
            '''                $row["receiver_id"] = intval($value["receiver_id"]);

                $row["im_payload"] = null;''',
            '''                $row["receiver_id"] = intval($value["receiver_id"]);
                $row["is_recalled"] = intval(isset($value["is_recalled"]) ? $value["is_recalled"] : 0);

                $row["im_payload"] = null;''',
            "conversation_recall_flag",
        )

    if '"msg_type"=>"recall", "message_type"=>0, "content"=>["message_id"=>intval($value["id"]), "text"=>"消息已撤回"]' not in source:
        source = replace_once(
            source,
            '''                } catch (\\Exception $e) {
                    $row["im_payload"] = null;
                }

                if (intval($value["sender_id"]) == $uid) {''',
            '''                } catch (\\Exception $e) {
                    $row["im_payload"] = null;
                }
                if (intval(isset($value["is_recalled"]) ? $value["is_recalled"] : 0) === 1) {
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
            "conversation_recall_payload",
        )

    if '$result[$key]["message"]["is_recalled"] = intval(isset($value["is_recalled"]) ? $value["is_recalled"] : 0);' not in source:
        source = replace_once(
            source,
            '''            $result[$key]["message"]["read"] = intval($value["is_read"]) == 1;
            $result[$key]["is_read"] = intval($value["is_read"]);''',
            '''            $result[$key]["message"]["read"] = intval($value["is_read"]) == 1;
            $result[$key]["message"]["is_recalled"] = intval(isset($value["is_recalled"]) ? $value["is_recalled"] : 0);
            $result[$key]["is_read"] = intval($value["is_read"]);''',
            "chat_recall_flag",
        )

    if 'if (intval(isset($value["is_recalled"]) ? $value["is_recalled"] : 0) === 1) {\n                $msg_type = "recall";' not in source:
        source = replace_once(
            source,
            '''            }
            $result[$key]["message"]["im_payload"] = [
                "version" => "1.0",''',
            '''            }
            if (intval(isset($value["is_recalled"]) ? $value["is_recalled"] : 0) === 1) {
                $msg_type = "recall";
                $im_content = ["message_id" => intval($value["id"]), "text" => "消息已撤回"];
                $result[$key]["message"]["content"] = "消息已撤回";
                $result[$key]["message"]["message_type"] = 0;
            }
            $result[$key]["message"]["im_payload"] = [
                "version" => "1.0",''',
            "chat_recall_payload",
        )

    if '"is_recalled" => intval(isset($value["is_recalled"]) ? $value["is_recalled"] : 0),\n                "read" => intval($value["is_read"]) == 1,' not in source:
        source = replace_once(
            source,
            '''                "is_read" => intval($value["is_read"]),
                "read" => intval($value["is_read"]) == 1,''',
            '''                "is_read" => intval($value["is_read"]),
                "is_recalled" => intval(isset($value["is_recalled"]) ? $value["is_recalled"] : 0),
                "read" => intval($value["is_read"]) == 1,''',
            "chat_payload_recall_flag",
        )

    if '$isRecalled = intval(isset($r["is_recalled"]) ? $r["is_recalled"] : 0);' not in source:
        source = replace_once(
            source,
            '''        foreach ($rows as $r) {
            $payload = $r["payload"];
            $list[] = ["message"=>["id"=>$r["id"], "sender_id"=>$r["sender_id"], "receiver_id"=>$groupId, "message_type"=>$r["message_type"], "content"=>$r["content"], "im_payload"=>$payload, "create_time"=>$r["create_time"]]];
        }''',
            '''        foreach ($rows as $r) {
            $isRecalled = intval(isset($r["is_recalled"]) ? $r["is_recalled"] : 0);
            $payload = $r["payload"];
            if ($isRecalled === 1) {
                $payload = json_encode([
                    "version"=>"1.0", "message_id"=>intval($r["id"]), "conversation_type"=>"group", "channel_type"=>2,
                    "from_uid"=>$this->appid . "_" . intval($r["sender_id"]), "to_uid"=>"",
                    "from_user_id"=>intval($r["sender_id"]), "to_user_id"=>0, "group_id"=>$groupId,
                    "msg_type"=>"recall", "message_type"=>0, "content"=>["message_id"=>intval($r["id"]), "text"=>"消息已撤回"],
                    "is_recalled"=>1, "create_time"=>$r["create_time"],
                ], JSON_UNESCAPED_UNICODE);
            }
            $list[] = ["message"=>["id"=>$r["id"], "sender_id"=>$r["sender_id"], "receiver_id"=>$groupId, "message_type"=>$isRecalled === 1 ? 0 : $r["message_type"], "content"=>$isRecalled === 1 ? "消息已撤回" : $r["content"], "is_recalled"=>$isRecalled, "im_payload"=>$payload, "create_time"=>$r["create_time"]]];
        }''',
            "group_recall_history",
        )

    if source != original:
        backup(API, "recall_friend_notifications")
        API.write_text(source)
        print("PATCHED", API)
    else:
        print("NO_CHANGE", API)


if __name__ == "__main__":
    main()
