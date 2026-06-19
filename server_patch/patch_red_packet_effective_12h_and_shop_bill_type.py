#!/usr/bin/env python3
from datetime import datetime
from pathlib import Path


ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"
COMMON = ROOT / "application/common.php"


def backup(path: Path, tag: str) -> Path:
    dst = path.with_name(
        f"{path.name}.bak_{tag}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    dst.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
    return dst


def replace_once(text: str, old: str, new: str) -> str:
    if old not in text:
        raise SystemExit(f"missing patch anchor: {old[:120]}")
    return text.replace(old, new, 1)


def patch_api() -> None:
    text = API.read_text(encoding="utf-8")
    original = text

    text = replace_once(
        text,
        '''    private function blinRedPacketExpireSeconds()
    {
        return 43200;
    }
''',
        '''    private function blinRedPacketExpireSeconds()
    {
        return 43200;
    }

    private function blinRedPacketEffectiveExpireTime($order)
    {
        if (!$order) return 0;
        $storedExpire = intval(isset($order["expire_time"]) ? $order["expire_time"] : 0);
        $createTime = intval(isset($order["create_time"]) ? $order["create_time"] : 0);
        $twelveHourExpire = $createTime > 0 ? $createTime + $this->blinRedPacketExpireSeconds() : 0;
        if ($storedExpire > 0 && $twelveHourExpire > 0) return min($storedExpire, $twelveHourExpire);
        return $storedExpire > 0 ? $storedExpire : $twelveHourExpire;
    }
''',
    )

    text = replace_once(
        text,
        '''        if (!$order) return [];
        $claims = $this->blinRedPacketClaims(intval($order["id"]));
''',
        '''        if (!$order) return [];
        $expireTime = $this->blinRedPacketEffectiveExpireTime($order);
        $claims = $this->blinRedPacketClaims(intval($order["id"]));
''',
    )
    text = replace_once(
        text,
        '''            "expires_at" => intval($order["expire_time"]) > 0 ? date("Y-m-d H:i:s", intval($order["expire_time"])) : "",
            "expire_time" => intval($order["expire_time"]),
''',
        '''            "expires_at" => $expireTime > 0 ? date("Y-m-d H:i:s", $expireTime) : "",
            "expire_time" => $expireTime,
''',
    )

    text = replace_once(
        text,
        '''        try {
            $orders = Db::name("im_red_packet_order")->where("appid", $appid)->where("status", 0)->where("expire_time", "<=", time())->limit(50)->select();
        } catch (\\Exception $e) {
''',
        '''        try {
            $now = time();
            $createDeadline = $now - $this->blinRedPacketExpireSeconds();
            $orders = Db::name("im_red_packet_order")
                ->where("appid", $appid)
                ->where("status", 0)
                ->where("(expire_time <= " . intval($now) . " OR (create_time > 0 AND create_time <= " . intval($createDeadline) . "))")
                ->limit(50)
                ->select();
        } catch (\\Exception $e) {
''',
    )
    text = replace_once(
        text,
        '''                $locked = Db::name("im_red_packet_order")->where("id", intval($order["id"]))->lock(true)->find();
                if (!$locked || intval($locked["status"]) !== 0 || intval($locked["expire_time"]) > time()) {
                    Db::commit();
                    continue;
                }
''',
        '''                $locked = Db::name("im_red_packet_order")->where("id", intval($order["id"]))->lock(true)->find();
                $effectiveExpireTime = $this->blinRedPacketEffectiveExpireTime($locked);
                if (!$locked || intval($locked["status"]) !== 0 || $effectiveExpireTime > time()) {
                    Db::commit();
                    continue;
                }
''',
    )
    text = replace_once(
        text,
        '''                Db::name("im_red_packet_order")->where("id", intval($locked["id"]))->update(["status"=>2, "remaining_amount"=>"0.00", "remaining_count"=>0, "refund_time"=>$now, "update_time"=>$now]);
                $locked["status"] = 2;
''',
        '''                Db::name("im_red_packet_order")->where("id", intval($locked["id"]))->update(["status"=>2, "remaining_amount"=>"0.00", "remaining_count"=>0, "expire_time"=>$effectiveExpireTime, "refund_time"=>$now, "update_time"=>$now]);
                $locked["expire_time"] = $effectiveExpireTime;
                $locked["status"] = 2;
''',
    )
    text = replace_once(
        text,
        '''            if (intval($locked["expire_time"]) <= time()) {
                Db::rollback();
                $this->blinExpireRedPackets($this->appid);
''',
        '''            if ($this->blinRedPacketEffectiveExpireTime($locked) <= time()) {
                Db::rollback();
                $this->blinExpireRedPackets($this->appid);
''',
    )

    if text != original:
        bak = backup(API, "red_packet_effective_12h")
        API.write_text(text, encoding="utf-8")
        print(f"PATCHED {API}")
        print(f"BACKUP {bak}")
    else:
        print(f"NO_CHANGE {API}")


def patch_common() -> None:
    text = COMMON.read_text(encoding="utf-8")
    original = text

    text = text.replace(
        '"money" => $user_info["money"] - (int)$order_info["total_amount"]',
        '"money" => $user_info["money"] - $paidAmount',
        1,
    )
    text = replace_once(
        text,
        '''                    Db::name("user")->where("id", $user_info["id"])
                        ->where("integral", ">", 0)
                        ->update([
                            "viptime" => $viptime,
                            "integral" => $user_info["integral"] - $order_info["total_amount"]
                        ]);
                    add_user_bill($user_info, 3, "-" . $paidAmount, "购买商品", 0, 0);
''',
        '''                    Db::name("user")->where("id", $user_info["id"])
                        ->where("integral", ">", 0)
                        ->update([
                            "viptime" => $viptime,
                            "integral" => $user_info["integral"] - $paidAmount
                        ]);
                    add_user_bill($user_info, 3, "-" . $paidAmount, "购买商品", 1, 0);
''',
    )
    text = text.replace(
        '"money" => $user_info["money"] - $order_info["total_amount"]',
        '"money" => $user_info["money"] - $paidAmount',
    )
    text = text.replace(
        '"integral" => $user_info["integral"] - $order_info["total_amount"]',
        '"integral" => $user_info["integral"] - $paidAmount',
    )

    if text != original:
        bak = backup(COMMON, "shop_bill_type")
        COMMON.write_text(text, encoding="utf-8")
        print(f"PATCHED {COMMON}")
        print(f"BACKUP {bak}")
    else:
        print(f"NO_CHANGE {COMMON}")


def main() -> None:
    patch_api()
    patch_common()


if __name__ == "__main__":
    main()
