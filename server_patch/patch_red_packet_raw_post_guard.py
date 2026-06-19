#!/usr/bin/env python3
"""Add raw POST red-packet guards before framework input normalization."""
from datetime import datetime
from pathlib import Path


ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"


def backup(path: Path, suffix: str) -> str:
    target = path.with_name(
        f"{path.name}.bak_{suffix}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    target.write_text(path.read_text(errors="ignore"))
    return str(target)


HELPER = r'''
    // blin-red-packet-raw-post-guard
    private function blinRawPayloadIsRedPacket($payloadText, $msgTypeText = "")
    {
        if (trim(strval($msgTypeText)) === "red_packet") {
            return true;
        }
        $text = strval($payloadText);
        if ($text === "") {
            return false;
        }
        $decoded = json_decode($text, true);
        if (is_array($decoded) && isset($decoded["msg_type"]) && strval($decoded["msg_type"]) === "red_packet") {
            return true;
        }
        return preg_match('/"msg_type"\s*:\s*"red_packet"/', $text) === 1;
    }

'''

PRIVATE_RAW_GUARD = '''        $raw_post_private_payload = isset($_POST["im_payload"]) ? $_POST["im_payload"] : (isset($_POST["payload"]) ? $_POST["payload"] : "");
        $raw_post_private_type = isset($_POST["msg_type"]) ? $_POST["msg_type"] : "";
        if ($this->blinRawPayloadIsRedPacket($raw_post_private_payload, $raw_post_private_type)) {
            $this->json(0, "普通消息接口不能发送红包，请使用红包接口");
        }
'''

GROUP_RAW_GUARD = '''        $raw_post_group_payload = isset($_POST["im_payload"]) ? $_POST["im_payload"] : (isset($_POST["payload"]) ? $_POST["payload"] : "");
        $raw_post_group_type = isset($_POST["msg_type"]) ? $_POST["msg_type"] : "";
        if ($this->blinRawPayloadIsRedPacket($raw_post_group_payload, $raw_post_group_type)) {
            $this->json(0, "群普通消息接口不能发送红包，请使用群红包接口");
        }
'''


def main() -> None:
    source = API.read_text(errors="ignore")
    original = source
    if "blinRawPayloadIsRedPacket" not in source:
        marker = "    // blin-red-packet-start\n"
        if marker not in source:
            raise SystemExit("RED_PACKET_BLOCK_MARKER_NOT_FOUND")
        source = source.replace(marker, HELPER + marker, 1)
    if "$raw_post_private_payload" not in source:
        marker = '''        $client_payload = input("im_payload") ?: input("payload");
        $client_msg_no_from_payload = "";
'''
        if marker not in source:
            raise SystemExit("PRIVATE_RAW_GUARD_MARKER_NOT_FOUND")
        source = source.replace(marker, marker + PRIVATE_RAW_GUARD, 1)
    if "$raw_post_group_payload" not in source:
        marker = '''        $payload = [];
        $rawPayload = input("im_payload") ?: input("payload");
'''
        if marker not in source:
            raise SystemExit("GROUP_RAW_GUARD_MARKER_NOT_FOUND")
        source = source.replace(marker, marker + GROUP_RAW_GUARD, 1)
    if source == original:
        print("RED_PACKET_RAW_POST_GUARD_ALREADY_PRESENT")
        return
    print("PATCH_Api.php_BACKUP", backup(API, "red_packet_raw_post_guard"))
    API.write_text(source)
    print("PATCHED_RED_PACKET_RAW_POST_GUARD")


if __name__ == "__main__":
    main()
