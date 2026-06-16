#!/usr/bin/env python3
"""Enable voice message type 5 in the PHP IM send_message API."""
from datetime import datetime
from pathlib import Path


ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"


def backup(path: Path) -> Path:
    target = path.with_name(
        f"{path.name}.bak_voice_msgtype_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    target.write_text(path.read_text(errors="ignore"))
    return target


def replace_once(source: str, old: str, new: str) -> str:
    if new in source:
        return source
    if old not in source:
        raise SystemExit(f"MARKER_NOT_FOUND:{old[:100]}")
    return source.replace(old, new, 1)


def main() -> None:
    source = API.read_text(errors="ignore")
    original = source

    source = replace_once(
        source,
        "if (in_array($message_type, [1, 3, 4])) {",
        "if (in_array($message_type, [1, 3, 4, 5])) {",
    )
    source = replace_once(
        source,
        '$content = input("content") ?: ($message_type == 1 ? "[图片]" : ($message_type == 4 ? "[视频]" : "[文件]"));',
        '$content = input("content") ?: ($message_type == 1 ? "[图片]" : ($message_type == 4 ? "[视频]" : ($message_type == 5 ? "[语音]" : "[文件]")));',
    )
    source = replace_once(
        source,
        '''} elseif (intval($sql_message_type) == 4) {
                $im_msg_type = "video";
            }''',
        '''} elseif (intval($sql_message_type) == 4) {
                $im_msg_type = "video";
            } elseif (intval($sql_message_type) == 5) {
                $im_msg_type = "voice";
            }''',
    )
    source = replace_once(
        source,
        '''} elseif ($im_msg_type == "file" || $im_msg_type == "video") {
                $im_content = array_merge(["url" => strval($file_path ?: $image_path), "name" => strval($file_name), "text" => strval($content)], $im_content);
            }''',
        '''} elseif ($im_msg_type == "file" || $im_msg_type == "video" || $im_msg_type == "voice") {
                $im_content = array_merge(["url" => strval($file_path ?: $image_path), "file_url" => strval($file_path ?: $image_path), "name" => strval($file_name), "text" => strval($content)], $im_content);
                if ($im_msg_type == "voice") {
                    $im_content["duration"] = isset($im_content["duration"]) ? $im_content["duration"] : intval(input("duration"));
                    $im_content["media_type"] = "audio";
                }
            }''',
    )
    source = replace_once(
        source,
        '''"msg_type" => intval($sql_message_type) == 1 ? "image" : (intval($sql_message_type) == 2 ? "transfer" : (intval($sql_message_type) == 3 ? "file" : (intval($sql_message_type) == 4 ? "video" : "text")))''',
        '''"msg_type" => intval($sql_message_type) == 1 ? "image" : (intval($sql_message_type) == 2 ? "transfer" : (intval($sql_message_type) == 3 ? "file" : (intval($sql_message_type) == 4 ? "video" : (intval($sql_message_type) == 5 ? "voice" : "text"))))''',
    )
    source = replace_once(
        source,
        '''} elseif (intval($value["message_type"]) == 2) {
                $msg_type = "transfer";
            }
            $im_content = ["text" => strval($value["content"] )];
            if ($msg_type == "image") {
                $im_content = ["url" => strval($value["image_path"]), "text" => strval($value["content"] )];
            } elseif ($msg_type == "transfer") {
                $im_content = ["amount" => strval($value["content"]), "money_type" => intval($value["money_type"]), "status" => "success"];
            }''',
        '''} elseif (intval($value["message_type"]) == 2) {
                $msg_type = "transfer";
            } elseif (intval($value["message_type"]) == 3) {
                $msg_type = "file";
            } elseif (intval($value["message_type"]) == 4) {
                $msg_type = "video";
            } elseif (intval($value["message_type"]) == 5) {
                $msg_type = "voice";
            }
            $im_content = ["text" => strval($value["content"] )];
            if ($msg_type == "image") {
                $im_content = ["url" => strval($value["image_path"]), "text" => strval($value["content"] )];
            } elseif ($msg_type == "transfer") {
                $im_content = ["amount" => strval($value["content"]), "money_type" => intval($value["money_type"]), "status" => "success"];
            } elseif ($msg_type == "file" || $msg_type == "video" || $msg_type == "voice") {
                $im_content = ["url" => strval($value["file_path"] ?: $value["image_path"]), "file_url" => strval($value["file_path"] ?: $value["image_path"]), "name" => strval($value["file_name"]), "text" => strval($value["content"] )];
                if ($msg_type == "voice") {
                    $im_content["duration"] = 0;
                    $im_content["media_type"] = "audio";
                    $payload_from_db = isset($value["im_payload"]) && $value["im_payload"] !== "" ? json_decode($value["im_payload"], true) : null;
                    if (is_array($payload_from_db) && isset($payload_from_db["content"]) && is_array($payload_from_db["content"])) {
                        $im_content = array_merge($im_content, $payload_from_db["content"]);
                    }
                }
            }''',
    )

    if source == original:
        print("ALREADY_PATCHED", API)
        return

    backup_path = backup(API)
    API.write_text(source)
    print("PATCHED", API)
    print("BACKUP", backup_path)


if __name__ == "__main__":
    main()
