#!/usr/bin/env python3
from datetime import datetime
from pathlib import Path


API = Path("/www/wwwroot/blinlin/application/api/controller/Api.php")


def main() -> None:
    text = API.read_text(encoding="utf-8")
    original = text
    replacements = [
        (
            '"expire_time"=>$now + $this->blinRedPacketExpireSeconds(),\n'
            '                "create_time"=>$now,',
            '"expire_time"=>$now + 86400,\n'
            '                "create_time"=>$now,',
        ),
        (
            '"expire_time"=>$now + $this->blinRedPacketExpireSeconds(), "status_text"=>"pending"',
            '"expire_time"=>$now + 86400, "status_text"=>"pending"',
        ),
    ]
    for old, new in replacements:
        if old not in text:
            raise SystemExit(f"missing group transfer anchor: {old}")
        text = text.replace(old, new, 1)
    if text == original:
        print("NO_CHANGE")
        return
    backup = API.with_name(
        f"{API.name}.bak_restore_group_transfer_24h_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    backup.write_text(original, encoding="utf-8")
    API.write_text(text, encoding="utf-8")
    print(f"PATCHED {API}")
    print(f"BACKUP {backup}")


if __name__ == "__main__":
    main()
