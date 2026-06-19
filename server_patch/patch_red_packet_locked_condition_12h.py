#!/usr/bin/env python3
from datetime import datetime
from pathlib import Path


API = Path("/www/wwwroot/blinlin/application/api/controller/Api.php")


def main() -> None:
    text = API.read_text(encoding="utf-8")
    old = '''                $locked = Db::name("im_red_packet_order")->where("id", intval($order["id"]))->lock(true)->find();
                if (!$locked || intval($locked["status"]) !== 0 || intval($locked["expire_time"]) > time()) {
                    Db::commit();
                    continue;
                }
'''
    new = '''                $locked = Db::name("im_red_packet_order")->where("id", intval($order["id"]))->lock(true)->find();
                $effectiveExpireTime = $this->blinRedPacketEffectiveExpireTime($locked);
                if (!$locked || intval($locked["status"]) !== 0 || $effectiveExpireTime > time()) {
                    Db::commit();
                    continue;
                }
'''
    if old not in text:
        if "$effectiveExpireTime = $this->blinRedPacketEffectiveExpireTime($locked);" in text:
            print("NO_CHANGE")
            return
        raise SystemExit("red packet locked condition anchor missing")
    backup = API.with_name(
        f"{API.name}.bak_red_packet_locked_12h_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    backup.write_text(text, encoding="utf-8")
    API.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"PATCHED {API}")
    print(f"BACKUP {backup}")


if __name__ == "__main__":
    main()
