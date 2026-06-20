#!/usr/bin/env python3
from pathlib import Path
import shutil
import time

path = Path("/www/wwwroot/blinlin/application/api/controller/Api.php")
source = path.read_text()
backup = path.with_suffix(path.suffix + f".bak_red_packet_claim_state_bill_{time.strftime('%Y%m%d%H%M%S')}")
shutil.copy2(path, backup)

def replace_once(old: str, new: str) -> None:
    global source
    if old not in source:
        raise SystemExit(f"pattern not found:\n{old[:240]}")
    source = source.replace(old, new, 1)

helper_marker = '''    private function blinMessageRedPacketContent($message, $scope = "single")
'''
helper_code = '''    private function blinRedPacketUserDisplayName($userId)
    {
        try {
            $user = Db::name("user")->where("appid", intval($this->appid))->where("id", intval($userId))->find();
            if ($user) {
                $name = isset($user["nickname"]) && trim(strval($user["nickname"])) !== "" ? strval($user["nickname"]) : (isset($user["username"]) ? strval($user["username"]) : "");
                if (trim($name) !== "") return $name;
            }
        } catch (\\Exception $e) {}
        return "用户" . intval($userId);
    }

    private function blinRedPacketGroupDisplayName($groupId)
    {
        try {
            $group = Db::name("im_groups")->where("appid", intval($this->appid))->where("id", intval($groupId))->find();
            if ($group && isset($group["name"]) && trim(strval($group["name"])) !== "") return strval($group["name"]);
        } catch (\\Exception $e) {}
        return "群聊" . intval($groupId);
    }

    private function blinRedPacketClaimRemark($order, $claimAmount, $newRemainingCount, $newStatus)
    {
        $claimAmount = $this->blinRedPacketMoneyText($claimAmount);
        $totalCount = max(1, intval($order["total_count"]));
        $claimedCount = max(0, $totalCount - intval($newRemainingCount));
        if (intval($order["channel_type"]) == 2) {
            $packetName = strval($order["packet_type"]) === "lucky" ? "拼手气红包" : "普通红包";
            $tail = "已领" . $claimedCount . "/" . $totalCount;
            if (intval($newStatus) == 1 || intval($newRemainingCount) <= 0) $tail = "已领完";
            return "领取群" . $packetName . $claimAmount . "（" . $tail . "）";
        }
        return "领取个人红包" . $claimAmount . "（已领取）";
    }

    private function blinRedPacketSenderRemark($order)
    {
        $totalCount = max(1, intval($order["total_count"]));
        $remainingCount = max(0, intval($order["remaining_count"]));
        $claimedCount = max(0, $totalCount - $remainingCount);
        $remainingAmount = $this->blinRedPacketMoneyText($order["remaining_amount"]);
        $status = intval($order["status"]);
        if (intval($order["channel_type"]) == 2) {
            $groupName = $this->blinRedPacketGroupDisplayName(intval($order["group_id"]));
            $packetName = strval($order["packet_type"]) === "lucky" ? "拼手气红包" : "普通红包";
            if ($status == 2) {
                $refundAmount = isset($order["refund_amount"]) && strval($order["refund_amount"]) !== "" ? $this->blinRedPacketMoneyText($order["refund_amount"]) : $remainingAmount;
                return "发到群聊「" . $groupName . "」的" . $packetName . "（已退回剩余" . $refundAmount . "，已领取" . $claimedCount . "/" . $totalCount . "）";
            }
            if ($status == 1 || $remainingCount <= 0) return "发到群聊「" . $groupName . "」的" . $packetName . "（已领完" . $claimedCount . "/" . $totalCount . "）";
            return "发到群聊「" . $groupName . "」的" . $packetName . "（已领取" . $claimedCount . "/" . $totalCount . "，剩余" . $remainingCount . "个）";
        }
        $receiverName = $this->blinRedPacketUserDisplayName(intval($order["receiver_id"]));
        if ($status == 2) {
            $refundAmount = isset($order["refund_amount"]) && strval($order["refund_amount"]) !== "" ? $this->blinRedPacketMoneyText($order["refund_amount"]) : $remainingAmount;
            return "发给" . $receiverName . "的红包（12小时未领取，已退回" . $refundAmount . "）";
        }
        if ($status == 1 || $remainingCount <= 0) return "发给" . $receiverName . "的红包（已领取）";
        return "发给" . $receiverName . "的红包（待领取）";
    }

    private function blinUpdateRedPacketSenderBillRemark($order)
    {
        try {
            if (!$order) return;
            $remark = $this->blinRedPacketSenderRemark($order);
            $amount = "-" . $this->blinRedPacketMoneyText($order["amount"]);
            $query = Db::name("transaction_statement")
                ->where("appid", intval($order["appid"]))
                ->where("userid", intval($order["sender_id"]))
                ->where("transaction_type", 15)
                ->where("type", intval($order["money_type"]))
                ->where("transaction_amount", $amount)
                ->where("remark", "like", "%红包%");
            if (isset($order["create_time"]) && intval($order["create_time"]) > 0) {
                $start = date("Y-m-d H:i:s", max(0, intval($order["create_time"]) - 600));
                $end = date("Y-m-d H:i:s", intval($order["create_time"]) + 600);
                $query = $query->where("transaction_date", "between", [$start, $end]);
            }
            $bill = $query->order("id desc")->find();
            if ($bill) {
                Db::name("transaction_statement")->where("id", intval($bill["id"]))->update(["remark" => $remark]);
            }
        } catch (\\Exception $e) {}
    }

'''
if "private function blinRedPacketClaimRemark(" not in source:
    source = source.replace(helper_marker, helper_code + helper_marker, 1)

replace_once(
'''            if ($msg_type == "image") {
''',
'''            if ($msg_type == "red_packet") {
                $im_content = $this->blinMessageRedPacketContent($value, "single");
            } elseif ($msg_type == "image") {
''')

replace_once(
'''                Db::commit();
                $this->blinUpdateRedPacketPayload($locked);
            } catch (\\Exception $e) {
''',
'''                Db::commit();
                $this->blinUpdateRedPacketPayload($locked);
                $locked["refund_amount"] = $this->blinRedPacketMoneyText($refund);
                $this->blinUpdateRedPacketSenderBillRemark($locked);
            } catch (\\Exception $e) {
''')

replace_once(
'''                Db::commit();
                $this->blinUpdateRedPacketPayload($locked);
                $this->json(1, "红包已领完", ["red_packet"=>$this->blinRedPacketData($locked, intval($user["id"]))]);
''',
'''                Db::commit();
                $this->blinUpdateRedPacketPayload($locked);
                $this->blinUpdateRedPacketSenderBillRemark($locked);
                $this->json(1, "红包已领完", ["red_packet"=>$this->blinRedPacketData($locked, intval($user["id"]))]);
''')

replace_once(
'''            Db::name("im_red_packet_claim")->insert(["appid"=>intval($this->appid), "red_packet_id"=>intval($locked["id"]), "user_id"=>intval($user["id"]), "amount"=>$claimAmount, "money_type"=>intval($locked["money_type"]), "create_time"=>time()]);
            Db::name("im_red_packet_order")->where("id", intval($locked["id"]))->update(["remaining_amount"=>$this->blinRedPacketMoneyText($newRemainingCents / 100), "remaining_count"=>$newRemainingCount, "status"=>$newStatus, "update_time"=>time()]);
            add_user_bill(["id"=>intval($user["id"]), "appid"=>intval($this->appid)], 15, "+" . $claimAmount, intval($locked["channel_type"]) == 2 ? "领取群红包" : "领取红包", intval($locked["money_type"]), 0);
            $locked["remaining_amount"] = $this->blinRedPacketMoneyText($newRemainingCents / 100);
''',
'''            Db::name("im_red_packet_claim")->insert(["appid"=>intval($this->appid), "red_packet_id"=>intval($locked["id"]), "user_id"=>intval($user["id"]), "amount"=>$claimAmount, "money_type"=>intval($locked["money_type"]), "create_time"=>time()]);
            Db::name("im_red_packet_order")->where("id", intval($locked["id"]))->update(["remaining_amount"=>$this->blinRedPacketMoneyText($newRemainingCents / 100), "remaining_count"=>$newRemainingCount, "status"=>$newStatus, "update_time"=>time()]);
            $claimRemark = $this->blinRedPacketClaimRemark($locked, $claimAmount, $newRemainingCount, $newStatus);
            add_user_bill(["id"=>intval($user["id"]), "appid"=>intval($this->appid)], 15, "+" . $claimAmount, $claimRemark, intval($locked["money_type"]), 0);
            $locked["remaining_amount"] = $this->blinRedPacketMoneyText($newRemainingCents / 100);
''')

replace_once(
'''            Db::commit();
            $this->blinUpdateRedPacketPayload($locked);
            $fresh = Db::name("im_red_packet_order")->where("id", intval($locked["id"]))->find();
''',
'''            Db::commit();
            $this->blinUpdateRedPacketPayload($locked);
            $this->blinUpdateRedPacketSenderBillRemark($locked);
            $fresh = Db::name("im_red_packet_order")->where("id", intval($locked["id"]))->find();
''')

path.write_text(source)
print(f"patched {path}")
print(f"backup {backup}")
