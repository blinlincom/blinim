#!/usr/bin/env python3
"""Fix private red-packet receipt delivery.

Private chat receipts use message_type=1004. Some upgraded databases still keep
mr_messages.message_type as tinyint(1), which rejects 1004 and makes the backend
return receipt=null. This patch makes the schema self-healing and keeps optional
message-log writes from breaking the actual receipt message and Wukong push.
"""
from pathlib import Path
import shutil
import time


ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "app/api/controller/Api.php"


def backup(path: Path) -> None:
    shutil.copy2(
        path,
        path.with_suffix(
            path.suffix
            + f".bak_red_packet_receipt_delivery_{time.strftime('%Y%m%d%H%M%S')}"
        ),
    )


backup(API)
source = API.read_text(errors="ignore")

marker = "        // blin-money-red-packet-columns-start\n"
schema_fix = (
    "        // blin-red-packet-message-type-start\n"
    '        try { Db::execute("ALTER TABLE `mr_messages` MODIFY COLUMN `message_type` int(11) DEFAULT 0"); } catch (\\Exception $e) {}\n'
    "        // blin-red-packet-message-type-end\n"
)
if "blin-red-packet-message-type-start" not in source:
    if marker not in source:
        raise SystemExit("red packet schema marker not found")
    source = source.replace(marker, schema_fix + marker, 1)

old_log = """            Db::name("im_message_log")->insert([
                "appid" => intval($this->appid),
                "message_id" => "local_" . intval($messageId),
                "client_msg_no" => $clientNo,
                "message_seq" => 0,
                "from_uid" => $payload["from_uid"],
                "from_user_id" => intval($claimer["id"]),
                "channel_id" => $payload["to_uid"],
                "channel_user_id" => intval($sender["id"]),
                "channel_type" => 1,
                "message_type" => 1004,
                "content" => strval($payload["content"]["text"]),
                "payload" => $encoded,
                "raw_data" => $encoded,
                "msg_timestamp" => time(),
                "status" => 0,
                "audit_status" => 0,
                "create_time" => $now,
            ]);
"""
new_log = """            try {
                Db::name("im_message_log")->insert([
                    "appid" => intval($this->appid),
                    "message_id" => "local_" . intval($messageId),
                    "client_msg_no" => $clientNo,
                    "message_seq" => 0,
                    "from_uid" => $payload["from_uid"],
                    "from_user_id" => intval($claimer["id"]),
                    "channel_id" => $payload["to_uid"],
                    "channel_user_id" => intval($sender["id"]),
                    "channel_type" => 1,
                    "message_type" => 1004,
                    "content" => strval($payload["content"]["text"]),
                    "payload" => $encoded,
                    "raw_data" => $encoded,
                    "msg_timestamp" => time(),
                    "status" => 0,
                    "audit_status" => 0,
                    "create_time" => $now,
                ]);
            } catch (\\Exception $e) {}
"""
if old_log in source:
    source = source.replace(old_log, new_log, 1)
elif new_log not in source:
    raise SystemExit("private receipt message-log block not found")

API.write_text(source)
print("patched private red-packet receipt delivery")
