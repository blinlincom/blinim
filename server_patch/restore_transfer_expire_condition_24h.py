#!/usr/bin/env python3
from datetime import datetime
from pathlib import Path


API = Path("/www/wwwroot/blinlin/application/api/controller/Api.php")


def main() -> None:
    text = API.read_text(encoding="utf-8")
    original = text
    replacements = [
        (
            '''                $locked = Db::name("im_transfer_order")->where("id", intval($order["id"]))->lock(true)->find();
                $effectiveExpireTime = $this->blinRedPacketEffectiveExpireTime($locked);
                if (!$locked || intval($locked["status"]) !== 0 || $effectiveExpireTime > time()) {
                    Db::commit();
                    continue;
                }
''',
            '''                $locked = Db::name("im_transfer_order")->where("id", intval($order["id"]))->lock(true)->find();
                if (!$locked || intval($locked["status"]) !== 0 || intval($locked["expire_time"]) > time()) {
                    Db::commit();
                    continue;
                }
''',
        ),
        (
            '''            if ($this->blinRedPacketEffectiveExpireTime($locked) <= time()) {
                Db::rollback();
                $this->blinExpirePendingTransfers($this->appid);
                $this->json(0, "转账已超过24小时，已退回");
            }
''',
            '''            if (intval($locked["expire_time"]) <= time()) {
                Db::rollback();
                $this->blinExpirePendingTransfers($this->appid);
                $this->json(0, "转账已超过24小时，已退回");
            }
''',
        ),
    ]
    for old, new in replacements:
        if old not in text:
            raise SystemExit(f"missing transfer restore anchor: {old[:120]}")
        text = text.replace(old, new, 1)
    if text == original:
        print("NO_CHANGE")
        return
    backup = API.with_name(
        f"{API.name}.bak_restore_transfer_expire_24h_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    backup.write_text(original, encoding="utf-8")
    API.write_text(text, encoding="utf-8")
    print(f"PATCHED {API}")
    print(f"BACKUP {backup}")


if __name__ == "__main__":
    main()
