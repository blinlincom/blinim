#!/usr/bin/env python3
from datetime import datetime
from pathlib import Path

API = Path("/www/wwwroot/blinlin/application/api/controller/Api.php")


def backup(path: Path) -> Path:
    dst = path.with_name(
        f"{path.name}.bak_gif_payload_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    dst.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
    return dst


def replace_once(text: str, old: str, new: str) -> str:
    if old not in text:
        raise SystemExit(f"missing patch anchor: {old[:80]}")
    return text.replace(old, new, 1)


def main() -> None:
    text = API.read_text(encoding="utf-8")
    original = text

    old_history = '''            $im_content = ["text" => strval($value["content"] )];
            if ($msg_type == "image") {
                $im_content = ["url" => strval($value["image_path"]), "text" => strval($value["content"] )];
            } elseif ($msg_type == "transfer") {
'''
    new_history = '''            $im_content = ["text" => strval($value["content"] )];
            $payload_from_db = isset($value["im_payload"]) && $value["im_payload"] !== "" ? json_decode($value["im_payload"], true) : null;
            if ($msg_type == "image") {
                $im_content = ["url" => strval($value["image_path"]), "file_url" => strval($value["file_path"] ?: $value["image_path"]), "image_path" => strval($value["image_path"]), "file_path" => strval($value["file_path"] ?: $value["image_path"]), "name" => strval($value["file_name"]), "file_name" => strval($value["file_name"]), "text" => strval($value["content"] )];
                if (is_array($payload_from_db) && isset($payload_from_db["content"]) && is_array($payload_from_db["content"])) {
                    $im_content = array_merge($im_content, $payload_from_db["content"]);
                }
                $gif_text = trim(strval($value["content"]));
                $gif_name = strtolower(strval(isset($im_content["file_name"]) ? $im_content["file_name"] : (isset($im_content["name"]) ? $im_content["name"] : "")));
                $gif_url = strtolower(strval(isset($im_content["url"]) ? $im_content["url"] : (isset($im_content["image_path"]) ? $im_content["image_path"] : "")));
                $gif_format = strtolower(strval(isset($im_content["media_format"]) ? $im_content["media_format"] : (isset($im_content["format"]) ? $im_content["format"] : "")));
                if ($gif_text === "[GIF]" || $gif_format === "gif" || substr(parse_url($gif_name, PHP_URL_PATH) ?: $gif_name, -4) === ".gif" || substr(parse_url($gif_url, PHP_URL_PATH) ?: $gif_url, -4) === ".gif" || (isset($im_content["is_gif"]) && intval($im_content["is_gif"]) === 1) || (isset($im_content["animated"]) && (strval($im_content["animated"]) === "1" || strval($im_content["animated"]) === "true"))) {
                    $im_content["media_format"] = "gif";
                    $im_content["format"] = "gif";
                    $im_content["is_gif"] = 1;
                    $im_content["animated"] = 1;
                    if ($gif_text === "[GIF]") {
                        unset($im_content["text"]);
                    }
                }
            } elseif ($msg_type == "transfer") {
'''
    text = replace_once(text, old_history, new_history)

    old_voice_payload = '''                    $payload_from_db = isset($value["im_payload"]) && $value["im_payload"] !== "" ? json_decode($value["im_payload"], true) : null;
                    if (is_array($payload_from_db) && isset($payload_from_db["content"]) && is_array($payload_from_db["content"])) {
                        $im_content = array_merge($im_content, $payload_from_db["content"]);
                    }
'''
    new_voice_payload = '''                    if (is_array($payload_from_db) && isset($payload_from_db["content"]) && is_array($payload_from_db["content"])) {
                        $im_content = array_merge($im_content, $payload_from_db["content"]);
                    }
'''
    text = replace_once(text, old_voice_payload, new_voice_payload)

    old_legacy = '''                "legacy" => ["type"=>intval($value["message_type"]),"content"=>strval($value["content"]),"image_path"=>$value["image_path"],"sender_id"=>intval($value["sender_id"]),"receiver_id"=>intval($value["receiver_id"]),"money_type"=>intval($value["money_type"])],
'''
    new_legacy = '''                "legacy" => ["type"=>intval($value["message_type"]),"content"=>strval($value["content"]),"image_path"=>$value["image_path"],"file_path"=>isset($value["file_path"]) ? $value["file_path"] : "","file_name"=>isset($value["file_name"]) ? $value["file_name"] : "","sender_id"=>intval($value["sender_id"]),"receiver_id"=>intval($value["receiver_id"]),"money_type"=>intval($value["money_type"])],
'''
    text = replace_once(text, old_legacy, new_legacy)

    if text == original:
        print("NO_CHANGE")
        return
    bak = backup(API)
    API.write_text(text, encoding="utf-8")
    print(f"PATCHED {API}")
    print(f"BACKUP {bak}")


if __name__ == "__main__":
    main()
