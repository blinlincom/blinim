#!/usr/bin/env python3
from pathlib import Path
import shutil
import time

path = Path("/www/wwwroot/blinlin/application/api/controller/Api.php")
source = path.read_text()
backup = path.with_suffix(path.suffix + f".bak_private_red_packet_history_type_{time.strftime('%Y%m%d%H%M%S')}")
shutil.copy2(path, backup)

old = '''            $im_content = ["text" => strval($value["content"] )];
            $payload_from_db = isset($value["im_payload"]) && $value["im_payload"] !== "" ? json_decode($value["im_payload"], true) : null;
            if ($msg_type == "red_packet") {
'''
new = '''            $im_content = ["text" => strval($value["content"] )];
            $payload_from_db = isset($value["im_payload"]) && $value["im_payload"] !== "" ? json_decode($value["im_payload"], true) : null;
            if (is_array($payload_from_db) && isset($payload_from_db["msg_type"]) && strval($payload_from_db["msg_type"]) === "red_packet") {
                $msg_type = "red_packet";
            }
            if ($msg_type == "red_packet") {
'''

if old not in source:
    raise SystemExit("private red packet history type anchor not found")

path.write_text(source.replace(old, new, 1))
print(f"patched {path}")
print(f"backup {backup}")
