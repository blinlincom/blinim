#!/usr/bin/env python3
"""Persist red-packet receipt messages as normal WukongIM timeline messages.

For money flows, a red_packet_receipt must behave like a chat timeline message,
not like a weak system notice. WukongIM.php previously forced every system
notice to red_dot=0/sync_once=1, which made receipt ordering and history sync
unstable. This patch keeps red_packet_receipt persistent and synced.
"""
from pathlib import Path
import shutil
import time


ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "app/api/controller/Api.php"
WKIM = ROOT / "app/common/tool/WukongIM.php"


def backup(path: Path) -> None:
    shutil.copy2(
        path,
        path.with_suffix(
            path.suffix + f".bak_red_packet_receipt_{time.strftime('%Y%m%d%H%M%S')}"
        ),
    )


def replace_between(source: str, start_marker: str, end_marker: str, old: str, new: str, label: str) -> str:
    start = source.find(start_marker)
    if start < 0:
        raise SystemExit(f"{label} start marker not found")
    end = source.find(end_marker, start)
    if end < 0:
        raise SystemExit(f"{label} end marker not found")
    block = source[start:end]
    if old not in block and new not in block:
        raise SystemExit(f"{label} target block not found")
    if old in block:
        block = block.replace(old, new, 1)
        return source[:start] + block + source[end:]
    return source


backup(API)
backup(WKIM)

wukong = WKIM.read_text(errors="ignore")
old_notice = """        if (intval($sdkType) >= 1000) return true;
        return in_array($msgType, ['recall','transfer_receipt','red_packet_receipt','system','notice','screenshot'], true);
"""
new_notice = """        if ($msgType === 'red_packet_receipt') return false;
        if (intval($sdkType) >= 1000) return true;
        return in_array($msgType, ['recall','transfer_receipt','system','notice','screenshot'], true);
"""
if old_notice not in wukong and new_notice not in wukong:
    raise SystemExit("WukongIM isSystemNotice block not found")
if old_notice in wukong:
    WKIM.write_text(wukong.replace(old_notice, new_notice, 1))

api = API.read_text(errors="ignore")
old_time = '            "create_time" => date("Y-m-d H:i:s"),\n        ];\n'
new_time = '            "create_time" => date("Y-m-d H:i:s"),\n            "timestamp" => time(),\n        ];\n'
api = replace_between(
    api,
    "    private function blinRedPacketReceiptPayload(",
    "    private function blinCreateRedPacketReceiptMessage(",
    old_time,
    new_time,
    "red-packet receipt timestamp",
)

old_group_header = '(new \\app\\common\\tool\\WukongIM())->sendMessage($payload["from_uid"], $payload["to_uid"], 2, $payload, $clientNo, ["no_persist"=>0,"red_dot"=>0,"sync_once"=>1]);'
new_group_header = '(new \\app\\common\\tool\\WukongIM())->sendMessage($payload["from_uid"], $payload["to_uid"], 2, $payload, $clientNo, ["no_persist"=>0,"red_dot"=>1,"sync_once"=>0]);'
old_person_header = '(new \\app\\common\\tool\\WukongIM())->sendPersonMessage($payload["from_uid"], $payload["to_uid"], $payload, $clientNo, ["no_persist"=>0,"red_dot"=>0,"sync_once"=>1]);'
new_person_header = '(new \\app\\common\\tool\\WukongIM())->sendPersonMessage($payload["from_uid"], $payload["to_uid"], $payload, $clientNo, ["no_persist"=>0,"red_dot"=>1,"sync_once"=>0]);'
api = replace_between(
    api,
    "    private function blinCreateRedPacketReceiptMessage(",
    "    private function blinMessageRedPacketContent(",
    old_group_header,
    new_group_header,
    "red-packet receipt group push header",
)
api = replace_between(
    api,
    "    private function blinCreateRedPacketReceiptMessage(",
    "    private function blinMessageRedPacketContent(",
    old_person_header,
    new_person_header,
    "red-packet receipt person push header",
)
API.write_text(api)

print("patched red_packet_receipt WukongIM timeline behavior")
