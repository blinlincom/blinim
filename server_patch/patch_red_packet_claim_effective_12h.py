#!/usr/bin/env python3
from datetime import datetime
from pathlib import Path


API = Path("/www/wwwroot/blinlin/application/api/controller/Api.php")


def main() -> None:
    text = API.read_text(encoding="utf-8")
    old = '''            if (intval($locked["expire_time"]) <= time()) {
                Db::rollback();
                $this->blinExpireRedPackets($this->appid);
                $fresh = Db::name("im_red_packet_order")->where("id", intval($order["id"]))->find();
                $this->json(1, "红包已过期", ["red_packet"=>$this->blinRedPacketData($fresh ?: $order, intval($user["id"]))]);
            }
'''
    new = '''            if ($this->blinRedPacketEffectiveExpireTime($locked) <= time()) {
                Db::rollback();
                $this->blinExpireRedPackets($this->appid);
                $fresh = Db::name("im_red_packet_order")->where("id", intval($order["id"]))->find();
                $this->json(1, "红包已过期", ["red_packet"=>$this->blinRedPacketData($fresh ?: $order, intval($user["id"]))]);
            }
'''
    if old not in text:
        if "$this->blinRedPacketEffectiveExpireTime($locked) <= time()" in text:
            print("NO_CHANGE")
            return
        raise SystemExit("red packet claim effective expire anchor missing")
    backup = API.with_name(
        f"{API.name}.bak_red_packet_claim_effective_12h_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    backup.write_text(text, encoding="utf-8")
    API.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"PATCHED {API}")
    print(f"BACKUP {backup}")


if __name__ == "__main__":
    main()
