#!/usr/bin/env python3
from pathlib import Path
import shutil
import time

path = Path("/www/wwwroot/blinlin/application/api/controller/Api.php")
source = path.read_text()
backup = path.with_suffix(path.suffix + f".bak_red_packet_sender_bill_amount_match_{time.strftime('%Y%m%d%H%M%S')}")
shutil.copy2(path, backup)

old = '''            $remark = $this->blinRedPacketSenderRemark($order);
            $amount = "-" . $this->blinRedPacketMoneyText($order["amount"]);
            $query = Db::name("transaction_statement")
                ->where("appid", intval($order["appid"]))
                ->where("userid", intval($order["sender_id"]))
                ->where("transaction_type", 15)
                ->where("type", intval($order["money_type"]))
                ->where("transaction_amount", $amount)
                ->where("remark", "like", "%红包%");
'''
new = '''            $remark = $this->blinRedPacketSenderRemark($order);
            $amountText = $this->blinRedPacketMoneyText($order["amount"]);
            $amountSimple = rtrim(rtrim($amountText, "0"), ".");
            if ($amountSimple === "") $amountSimple = $amountText;
            $amountList = ["-" . $amountText, "-" . $amountSimple];
            $query = Db::name("transaction_statement")
                ->where("appid", intval($order["appid"]))
                ->where("userid", intval($order["sender_id"]))
                ->where("transaction_type", 15)
                ->where("type", intval($order["money_type"]))
                ->where("transaction_amount", "in", array_values(array_unique($amountList)))
                ->where("remark", "like", "%红包%");
'''

if old not in source:
    raise SystemExit("sender bill amount match anchor not found")

path.write_text(source.replace(old, new, 1))
print(f"patched {path}")
print(f"backup {backup}")
