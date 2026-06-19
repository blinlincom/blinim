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
        raise SystemExit(f"missing patch anchor: {old[:100]}")
    return text.replace(old, new, 1)


def patch_api() -> None:
    text = API.read_text(encoding="utf-8")
    original = text

    text = replace_once(
        text,
        '''    private function blinRedPacketGreeting($value)
    {
        $text = trim(strval($value));
        if ($text === "") $text = "恭喜发财，大吉大利";
        if (function_exists("mb_substr")) return mb_substr($text, 0, 80, "UTF-8");
        return substr($text, 0, 240);
    }
''',
        '''    private function blinRedPacketGreeting($value)
    {
        $text = trim(strval($value));
        if ($text === "") $text = "恭喜发财，大吉大利";
        if (function_exists("mb_substr")) return mb_substr($text, 0, 80, "UTF-8");
        return substr($text, 0, 240);
    }

    private function blinRedPacketExpireSeconds()
    {
        return 43200;
    }
''',
    )

    text = replace_once(
        text,
        '"expire_time"=>$now + 86400, "create_time"=>$now, "update_time"=>$now]);',
        '"expire_time"=>$now + $this->blinRedPacketExpireSeconds(), "create_time"=>$now, "update_time"=>$now]);',
    )
    text = replace_once(
        text,
        '"expire_time"=>$now + 86400, "create_time"=>$now, "update_time"=>$now]);',
        '"expire_time"=>$now + $this->blinRedPacketExpireSeconds(), "create_time"=>$now, "update_time"=>$now]);',
    )
    text = text.replace(
        "红包24小时未领取，余额已退回",
        "红包12小时未领取完，剩余金额已原路退回",
    )

    text = replace_once(
        text,
        '''        $this->blinExpirePendingTransfers($this->appid);
        $this->blinExpirePendingTransfers($this->appid);
        $this->blinExpirePendingTransfers($this->appid);
        $this->blinExpirePendingTransfers($this->appid);
        $user_info = $this->user_info;
''',
        '''        $this->blinExpirePendingTransfers($this->appid);
        $this->blinExpirePendingTransfers($this->appid);
        $this->blinExpirePendingTransfers($this->appid);
        $this->blinExpirePendingTransfers($this->appid);
        $this->blinExpireRedPackets($this->appid);
        $user_info = $this->user_info;
''',
    )

    if text != original:
        bak = backup(API, "red_packet_12h")
        API.write_text(text, encoding="utf-8")
        print(f"PATCHED {API}")
        print(f"BACKUP {bak}")
    else:
        print(f"NO_CHANGE {API}")


def patch_common() -> None:
    text = COMMON.read_text(encoding="utf-8")
    original = text

    text = replace_once(
        text,
        '''            //金币支付
            if ($order_info["payment_method"] == 0) {
''',
        '''            $paidAmount = isset($order_info["total_amount"]) ? $order_info["total_amount"] : 0;
            $receivedQuantity = isset($order_info["received_quantity"]) ? $order_info["received_quantity"] : 0;
            //金币支付
            if ($order_info["payment_method"] == 0) {
''',
    )

    replacements = [
        (
            'add_user_bill($user_info, 3, "-" . $order_info["received_quantity"], "购买商品" . $order_info["product_name"], 0, 0);',
            'add_user_bill($user_info, 3, "-" . $paidAmount, "购买商品" . $order_info["product_name"], 0, 0);',
        ),
        (
            'add_user_bill($user_info, 3, "-" . $order_info["received_quantity"], "购买商品", 0, 0);',
            'add_user_bill($user_info, 3, "-" . $paidAmount, "购买商品", 0, 0);',
        ),
        (
            'add_user_bill($user_info, 3, "-" . $order_info["received_quantity"], "购买商品", 1, 0);',
            'add_user_bill($user_info, 3, "-" . $paidAmount, "购买商品", 1, 0);',
        ),
    ]
    for old, new in replacements:
        if old not in text:
            raise SystemExit(f"missing bill anchor: {old}")
        text = text.replace(old, new)

    if text != original:
        bak = backup(COMMON, "shop_bill_paid_amount")
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
