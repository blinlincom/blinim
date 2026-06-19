#!/usr/bin/env python3
"""Move red-packet spoof guard into the real group-message endpoint."""
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


BAD_LINE = '''            if (is_array($decoded) && isset($decoded["msg_type"]) && strval($decoded["msg_type"]) === "red_packet") $this->json(0, "群普通消息接口不能发送红包，请使用群红包接口");
'''

GOOD_BLOCK = '''            if (is_array($decoded) && isset($decoded["msg_type"]) && strval($decoded["msg_type"]) === "red_packet") {
                $this->json(0, "群普通消息接口不能发送红包，请使用群红包接口");
            }
'''


def main() -> None:
    source = API.read_text(errors="ignore")
    original = source
    source = source.replace(BAD_LINE, "")
    marker = '''            if (is_array($decoded)) $payload = $decoded;
        }
        $content = isset($data["content"]) ? strval($data["content"]) : "";
'''
    replacement = '''            if (is_array($decoded)) $payload = $decoded;
''' + GOOD_BLOCK + '''        }
        $content = isset($data["content"]) ? strval($data["content"]) : "";
'''
    if GOOD_BLOCK not in source:
        if marker not in source:
            raise SystemExit("GROUP_SEND_GUARD_MARKER_NOT_FOUND")
        source = source.replace(marker, replacement, 1)
    if source == original:
        print("RED_PACKET_GUARD_ALREADY_FIXED")
        return
    print("PATCH_Api.php_BACKUP", backup(API, "red_packet_guard_fix"))
    API.write_text(source)
    print("PATCHED_RED_PACKET_GUARD_FIX")


if __name__ == "__main__":
    main()
