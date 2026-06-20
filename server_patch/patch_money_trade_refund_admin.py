#!/usr/bin/env python3
from pathlib import Path
import os
import shutil
import time


ROOT = Path(os.environ.get("BLIN_ROOT", "/www/wwwroot/blinlin"))
API = ROOT / "application/api/controller/Api.php"
APP = ROOT / "application/admin/controller/App.php"
IM = ROOT / "application/admin/controller/Im.php"
APP_EDIT = ROOT / "application/admin/view/app/edit.html"
RED_PACKET_VIEW = ROOT / "application/admin/view/im/red_packet_records.html"
TRANSFER_VIEW = ROOT / "application/admin/view/im/transfer_records.html"


def backup(path: Path) -> None:
    stamp = time.strftime("%Y%m%d%H%M%S")
    dst = path.with_suffix(path.suffix + f".bak_money_trade_{stamp}")
    shutil.copy2(path, dst)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")


def replace_once(text: str, old: str, new: str, desc: str) -> str:
    if old not in text:
        raise RuntimeError(f"missing anchor: {desc}")
    return text.replace(old, new, 1)


def replace_between(text: str, start_marker: str, end_marker: str, new: str, desc: str) -> str:
    start = text.find(start_marker)
    if start < 0:
        raise RuntimeError(f"missing start anchor: {desc}")
    end = text.find(end_marker, start)
    if end < 0:
        raise RuntimeError(f"missing end anchor: {desc}")
    return text[:start] + new + text[end:]


def patch_api() -> None:
    path = API
    backup(path)
    text = read(path)

    if "blin-money-trade-config-start" not in text:
        text = replace_once(
            text,
            '''    private function blinTransferStatusText($status)
    {
        $status = intval($status);
        if ($status == 1) {
            return "accepted";
        }
        if ($status == 2) {
            return "refunded";
        }
        return "pending";
    }

    private function blinTransferData($order)
''',
            '''    private function blinTransferStatusText($status)
    {
        $status = intval($status);
        if ($status == 1) {
            return "accepted";
        }
        if ($status == 2) {
            return "refunded";
        }
        return "pending";
    }

    // blin-money-trade-config-start
    private function blinMoneyExpireHours($key, $defaultHours)
    {
        $config = isset($this->app_info["forum_configuration"]) && is_array($this->app_info["forum_configuration"]) ? $this->app_info["forum_configuration"] : [];
        $raw = isset($config[$key]) ? $config[$key] : $defaultHours;
        $hours = floatval($raw);
        if ($hours <= 0) {
            $hours = floatval($defaultHours);
        }
        if ($hours < 1) {
            $hours = 1;
        }
        if ($hours > 720) {
            $hours = 720;
        }
        return $hours;
    }

    private function blinMoneyExpireHoursText($key, $defaultHours)
    {
        $hours = $this->blinMoneyExpireHours($key, $defaultHours);
        return rtrim(rtrim(number_format($hours, 2, ".", ""), "0"), ".");
    }

    private function blinTransferExpireSeconds()
    {
        return max(3600, intval(round($this->blinMoneyExpireHours("transfer_refund_hours", 24) * 3600)));
    }

    private function blinMoneyTradeNo($prefix)
    {
        $prefix = strtoupper(preg_replace("/[^A-Z0-9]/", "", strval($prefix)));
        if ($prefix === "") {
            $prefix = "TR";
        }
        $appPart = str_pad(strval(intval($this->appid) % 10000), 4, "0", STR_PAD_LEFT);
        return $prefix . $appPart . date("YmdHis") . str_pad(strval(mt_rand(0, 999999)), 6, "0", STR_PAD_LEFT) . str_pad(strval(mt_rand(0, 9999)), 4, "0", STR_PAD_LEFT);
    }

    private function blinEnsureTransferTradeNos()
    {
        try {
            $rows = Db::name("im_transfer_order")->where("trade_no", "")->limit(100)->select();
            foreach (($rows ?: []) as $row) {
                Db::name("im_transfer_order")->where("id", intval($row["id"]))->where("trade_no", "")->update(["trade_no" => $this->blinMoneyTradeNo("TR")]);
            }
        } catch (\\Exception $e) {}
    }

    private function blinEnsureRedPacketTradeNos()
    {
        try {
            $rows = Db::name("im_red_packet_order")->where("trade_no", "")->limit(100)->select();
            foreach (($rows ?: []) as $row) {
                Db::name("im_red_packet_order")->where("id", intval($row["id"]))->where("trade_no", "")->update(["trade_no" => $this->blinMoneyTradeNo("RP")]);
            }
        } catch (\\Exception $e) {}
    }

    private function blinMoneyNotifyUser($appid, $userId, $title, $content, $type = 21)
    {
        try {
            $userId = intval($userId);
            if ($userId <= 0) return;
            Db::name("message_notification")->insert([
                "appid" => intval($appid),
                "user_id" => $userId,
                "title" => strval($title),
                "content" => strval($content),
                "send_to" => 0,
                "type" => intval($type),
                "status" => 0,
                "postid" => 0,
                "time" => date("Y-m-d H:i:s", time()),
            ]);
        } catch (\\Exception $e) {}
    }
    // blin-money-trade-config-end

    private function blinTransferData($order)
''',
            "insert API money trade helpers",
        )

    if "blin-money-trade-columns-start" not in text:
        text = replace_once(
            text,
            '''        $this->blinTransferAddColumnIfMissing("mr_im_transfer_order", "group_message_id", "ALTER TABLE `mr_im_transfer_order` ADD COLUMN `group_message_id` bigint(20) NOT NULL DEFAULT 0 AFTER `message_id`");
        $this->blinTransferAddColumnIfMissing("mr_im_transfer_order", "channel_type", "ALTER TABLE `mr_im_transfer_order` ADD COLUMN `channel_type` tinyint(1) NOT NULL DEFAULT 1 COMMENT '1 single, 2 group' AFTER `client_msg_no`");
        $this->blinTransferAddColumnIfMissing("mr_im_transfer_order", "group_id", "ALTER TABLE `mr_im_transfer_order` ADD COLUMN `group_id` bigint(20) NOT NULL DEFAULT 0 AFTER `receiver_id`");
        try { Db::execute("ALTER TABLE `mr_im_transfer_order` ADD KEY `idx_group_msg` (`appid`,`group_message_id`)"); } catch (\\Exception $e) {}
        try { Db::execute("ALTER TABLE `mr_im_transfer_order` ADD KEY `idx_channel_group` (`appid`,`channel_type`,`group_id`,`status`)"); } catch (\\Exception $e) {}
''',
            '''        $this->blinTransferAddColumnIfMissing("mr_im_transfer_order", "group_message_id", "ALTER TABLE `mr_im_transfer_order` ADD COLUMN `group_message_id` bigint(20) NOT NULL DEFAULT 0 AFTER `message_id`");
        $this->blinTransferAddColumnIfMissing("mr_im_transfer_order", "channel_type", "ALTER TABLE `mr_im_transfer_order` ADD COLUMN `channel_type` tinyint(1) NOT NULL DEFAULT 1 COMMENT '1 single, 2 group' AFTER `client_msg_no`");
        $this->blinTransferAddColumnIfMissing("mr_im_transfer_order", "group_id", "ALTER TABLE `mr_im_transfer_order` ADD COLUMN `group_id` bigint(20) NOT NULL DEFAULT 0 AFTER `receiver_id`");
        // blin-money-trade-columns-start
        $this->blinTransferAddColumnIfMissing("mr_im_transfer_order", "trade_no", "ALTER TABLE `mr_im_transfer_order` ADD COLUMN `trade_no` varchar(64) NOT NULL DEFAULT '' AFTER `client_msg_no`");
        $this->blinTransferAddColumnIfMissing("mr_im_transfer_order", "refund_source", "ALTER TABLE `mr_im_transfer_order` ADD COLUMN `refund_source` varchar(32) NOT NULL DEFAULT '' AFTER `refund_time`");
        $this->blinTransferAddColumnIfMissing("mr_im_transfer_order", "refund_operator", "ALTER TABLE `mr_im_transfer_order` ADD COLUMN `refund_operator` varchar(64) NOT NULL DEFAULT '' AFTER `refund_source`");
        try { Db::execute("ALTER TABLE `mr_im_transfer_order` ADD KEY `idx_trade_no` (`appid`,`trade_no`)"); } catch (\\Exception $e) {}
        $this->blinEnsureTransferTradeNos();
        // blin-money-trade-columns-end
        try { Db::execute("ALTER TABLE `mr_im_transfer_order` ADD KEY `idx_group_msg` (`appid`,`group_message_id`)"); } catch (\\Exception $e) {}
        try { Db::execute("ALTER TABLE `mr_im_transfer_order` ADD KEY `idx_channel_group` (`appid`,`channel_type`,`group_id`,`status`)"); } catch (\\Exception $e) {}
''',
            "add transfer columns",
        )

    if "blin-money-red-packet-columns-start" not in text:
        text = replace_once(
            text,
            '''            Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_red_packet_claim` (`id` bigint(20) NOT NULL AUTO_INCREMENT, `appid` bigint(20) NOT NULL DEFAULT 0, `red_packet_id` bigint(20) NOT NULL DEFAULT 0, `user_id` bigint(20) NOT NULL DEFAULT 0, `amount` decimal(16,2) NOT NULL DEFAULT '0.00', `money_type` tinyint(1) NOT NULL DEFAULT 0, `create_time` int(11) NOT NULL DEFAULT 0, PRIMARY KEY (`id`), UNIQUE KEY `uniq_packet_user` (`appid`,`red_packet_id`,`user_id`), KEY `idx_packet` (`appid`,`red_packet_id`,`id`), KEY `idx_user` (`appid`,`user_id`,`id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
        } catch (\\Exception $e) {}
''',
            '''            Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_red_packet_claim` (`id` bigint(20) NOT NULL AUTO_INCREMENT, `appid` bigint(20) NOT NULL DEFAULT 0, `red_packet_id` bigint(20) NOT NULL DEFAULT 0, `user_id` bigint(20) NOT NULL DEFAULT 0, `amount` decimal(16,2) NOT NULL DEFAULT '0.00', `money_type` tinyint(1) NOT NULL DEFAULT 0, `create_time` int(11) NOT NULL DEFAULT 0, PRIMARY KEY (`id`), UNIQUE KEY `uniq_packet_user` (`appid`,`red_packet_id`,`user_id`), KEY `idx_packet` (`appid`,`red_packet_id`,`id`), KEY `idx_user` (`appid`,`user_id`,`id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
        } catch (\\Exception $e) {}
        // blin-money-red-packet-columns-start
        $this->blinTransferAddColumnIfMissing("mr_im_red_packet_order", "trade_no", "ALTER TABLE `mr_im_red_packet_order` ADD COLUMN `trade_no` varchar(64) NOT NULL DEFAULT '' AFTER `client_msg_no`");
        $this->blinTransferAddColumnIfMissing("mr_im_red_packet_order", "refund_source", "ALTER TABLE `mr_im_red_packet_order` ADD COLUMN `refund_source` varchar(32) NOT NULL DEFAULT '' AFTER `refund_time`");
        $this->blinTransferAddColumnIfMissing("mr_im_red_packet_order", "refund_operator", "ALTER TABLE `mr_im_red_packet_order` ADD COLUMN `refund_operator` varchar(64) NOT NULL DEFAULT '' AFTER `refund_source`");
        try { Db::execute("ALTER TABLE `mr_im_red_packet_order` ADD KEY `idx_trade_no` (`appid`,`trade_no`)"); } catch (\\Exception $e) {}
        $this->blinEnsureRedPacketTradeNos();
        // blin-money-red-packet-columns-end
''',
            "add red packet columns",
        )

    text = replace_once(
        text,
        '''        $channelType = intval(isset($order["channel_type"]) ? $order["channel_type"] : 1);
        $groupMessageId = intval(isset($order["group_message_id"]) ? $order["group_message_id"] : 0);
        $messageId = intval($channelType == 2 && $groupMessageId > 0 ? $groupMessageId : $order["message_id"]);
        return [
''',
        '''        $channelType = intval(isset($order["channel_type"]) ? $order["channel_type"] : 1);
        $groupMessageId = intval(isset($order["group_message_id"]) ? $order["group_message_id"] : 0);
        $messageId = intval($channelType == 2 && $groupMessageId > 0 ? $groupMessageId : $order["message_id"]);
        $expireTime = intval(isset($order["expire_time"]) ? $order["expire_time"] : 0);
        $tradeNo = isset($order["trade_no"]) ? strval($order["trade_no"]) : "";
        return [
''',
        "fix transfer expire time and trade no locals",
    )

    text = replace_once(
        text,
        '''            "client_msg_no" => strval($order["client_msg_no"]),
            "sender_id" => intval($order["sender_id"]),
''',
        '''            "client_msg_no" => strval($order["client_msg_no"]),
            "trade_no" => $tradeNo,
            "transaction_no" => $tradeNo,
            "sender_id" => intval($order["sender_id"]),
''',
        "add transfer trade no data",
    )

    text = text.replace(
        '''        $content["transfer_id"] = intval($transfer["id"]);
        $content["expires_at"] = intval($transfer["expire_time"]) > 0 ? date("Y-m-d H:i:s", intval($transfer["expire_time"])) : "";
''',
        '''        $content["transfer_id"] = intval($transfer["id"]);
        if (isset($transfer["trade_no"]) && trim(strval($transfer["trade_no"])) !== "") {
            $content["trade_no"] = strval($transfer["trade_no"]);
            $content["transaction_no"] = strval($transfer["trade_no"]);
        }
        $content["expires_at"] = intval($transfer["expire_time"]) > 0 ? date("Y-m-d H:i:s", intval($transfer["expire_time"])) : "";
''',
        2,
    )

    text = replace_once(
        text,
        '''                "note" => isset($order["note"]) ? $order["note"] : "",
                "expire_time" => intval($order["expire_time"]),
                "status_text" => $this->blinTransferStatusText($order["status"]),
''',
        '''                "note" => isset($order["note"]) ? $order["note"] : "",
                "expire_time" => intval($order["expire_time"]),
                "trade_no" => isset($order["trade_no"]) ? strval($order["trade_no"]) : "",
                "status_text" => $this->blinTransferStatusText($order["status"]),
''',
        "add trade no to transfer payload update",
    )

    text = replace_once(
        text,
        '''                $content["transfer_id"] = intval($order["id"]);
                $content["expires_at"] = intval($order["expire_time"]) > 0 ? date("Y-m-d H:i:s", intval($order["expire_time"])) : "";
''',
        '''                $content["transfer_id"] = intval($order["id"]);
                $content["trade_no"] = isset($order["trade_no"]) ? strval($order["trade_no"]) : "";
                $content["transaction_no"] = $content["trade_no"];
                $content["expires_at"] = intval($order["expire_time"]) > 0 ? date("Y-m-d H:i:s", intval($order["expire_time"])) : "";
''',
        "add trade no to message transfer content",
    )

    text = replace_between(
        text,
        "    private function blinExpirePendingTransfers($appid = null)\n",
        "    private function blinSendTransferReceipt",
        '''    private function blinExpirePendingTransfers($appid = null)
    {
        $this->blinEnsureTransferTable();
        $appid = $appid === null ? intval($this->appid) : intval($appid);
        $orders = [];
        try {
            $orders = Db::name("im_transfer_order")->where("appid", $appid)->where("status", 0)->where("expire_time", "<=", time())->limit(50)->select();
        } catch (\\Exception $e) {
            return;
        }
        foreach ($orders as $order) {
            Db::startTrans();
            try {
                $locked = Db::name("im_transfer_order")->where("id", intval($order["id"]))->lock(true)->find();
                if (!$locked || intval($locked["status"]) !== 0 || intval($locked["expire_time"]) > time()) {
                    Db::commit();
                    continue;
                }
                $field = $this->blinTransferBalanceField($locked["money_type"]);
                $refund = floatval($locked["amount"]) + (intval($locked["fee_payer"]) == 1 ? floatval($locked["fee"]) : 0);
                $sender = Db::name("user")->where("id", intval($locked["sender_id"]))->where("appid", intval($locked["appid"]))->lock(true)->find();
                if ($sender && $refund > 0) {
                    Db::name("user")->where("id", intval($locked["sender_id"]))->update([$field => floatval($sender[$field]) + $refund]);
                    $tradeNo = isset($locked["trade_no"]) ? strval($locked["trade_no"]) : "";
                    $tradeText = $tradeNo !== "" ? "（交易单号：" . $tradeNo . "）" : "";
                    add_user_bill(["id" => intval($locked["sender_id"]), "appid" => intval($locked["appid"])], 9, "+" . $this->blinTransferMoneyText($refund), "转账超时未领取，已退回" . $tradeText, intval($locked["money_type"]), 0);
                    add_user_bill(["id" => intval($locked["receiver_id"]), "appid" => intval($locked["appid"])], 9, "0.00", "转账超时未领取，系统已退回给对方" . $tradeText, intval($locked["money_type"]), 0);
                }
                $now = time();
                Db::name("im_transfer_order")->where("id", intval($locked["id"]))->update(["status" => 2, "refund_time" => $now, "refund_source" => "timeout", "refund_operator" => "system", "update_time" => $now]);
                $locked["status"] = 2;
                $locked["refund_time"] = $now;
                $locked["refund_source"] = "timeout";
                $locked["refund_operator"] = "system";
                Db::commit();
                $this->blinUpdateTransferMessagePayload($locked);
                $noticeTrade = isset($locked["trade_no"]) && strval($locked["trade_no"]) !== "" ? "交易单号：" . strval($locked["trade_no"]) . "，" : "";
                $this->blinMoneyNotifyUser($locked["appid"], $locked["sender_id"], "转账已退回", $noticeTrade . "对方超时未收款，" . $this->blinTransferMoneyText($refund) . "已退回到你的账户");
                $this->blinMoneyNotifyUser($locked["appid"], $locked["receiver_id"], "转账已退回", $noticeTrade . "转账已超时，系统已退回给转出方");
            } catch (\\Exception $e) {
                try { Db::rollback(); } catch (\\Exception $rollbackException) {}
            }
        }
    }

''',
        "update transfer timeout refund",
    )

    text = text.replace('"转账已超过24小时，已退回"', '"转账已超过" . $this->blinMoneyExpireHoursText("transfer_refund_hours", 24) . "小时，已退回"')
    text = text.replace('$transfer_expire_time = time() + 86400;', '$transfer_expire_time = time() + $this->blinTransferExpireSeconds();')
    text = text.replace('"expire_time"=>$now + 86400,', '"expire_time"=>$transferExpireTime,')
    text = text.replace('"expire_time"=>$now + 86400, "status_text"=>"pending"', '"expire_time"=>$transferExpireTime, "trade_no"=>$tradeNo, "status_text"=>"pending"')
    text = text.replace('"expire_time"=>$transferExpireTime, "status_text"=>"pending"', '"expire_time"=>$transferExpireTime, "trade_no"=>$tradeNo, "status_text"=>"pending"')

    text = replace_once(
        text,
        '''        $feePayer = isset($this->app_info["forum_configuration"]["deduction_method_for_handling_fees"]) && intval($this->app_info["forum_configuration"]["deduction_method_for_handling_fees"]) == 1 ? 1 : 0;
        $holdAmount = $this->blinTransferMoneyText(floatval($amount) + ($feePayer == 1 ? floatval($fee) : 0));
        $note = trim(strval(isset($data["note"]) ? $data["note"] : input("remark")));
''',
        '''        $feePayer = isset($this->app_info["forum_configuration"]["deduction_method_for_handling_fees"]) && intval($this->app_info["forum_configuration"]["deduction_method_for_handling_fees"]) == 1 ? 1 : 0;
        $holdAmount = $this->blinTransferMoneyText(floatval($amount) + ($feePayer == 1 ? floatval($fee) : 0));
        $transferExpireTime = time() + $this->blinTransferExpireSeconds();
        $tradeNo = $this->blinMoneyTradeNo("TR");
        $note = trim(strval(isset($data["note"]) ? $data["note"] : input("remark")));
''',
        "group transfer expire/trade locals",
    )

    text = replace_once(
        text,
        '''                "client_msg_no"=>$clientNo,
                "channel_type"=>2,
                "sender_id"=>intval($sender["id"]),
''',
        '''                "client_msg_no"=>$clientNo,
                "trade_no"=>$tradeNo,
                "channel_type"=>2,
                "sender_id"=>intval($sender["id"]),
''',
        "group transfer insert trade no",
    )

    text = replace_once(
        text,
        '''                "hold_amount" => $hold_amount,
                "note" => $transfer_note,
                "expire_time" => $transfer_expire_time,
''',
        '''                "hold_amount" => $hold_amount,
                "note" => $transfer_note,
                "expire_time" => $transfer_expire_time,
                "trade_no" => $this->blinMoneyTradeNo("TR"),
''',
        "private transfer pending trade no",
    )

    text = replace_once(
        text,
        '''                    "message_id" => intval($message_id),
                    "client_msg_no" => $client_msg_no_from_payload !== "" ? $client_msg_no_from_payload : "",
                    "sender_id" => intval($user_all_info["id"]),
''',
        '''                    "message_id" => intval($message_id),
                    "client_msg_no" => $client_msg_no_from_payload !== "" ? $client_msg_no_from_payload : "",
                    "trade_no" => strval($pending_transfer["trade_no"]),
                    "sender_id" => intval($user_all_info["id"]),
''',
        "private transfer insert trade no",
    )

    text = replace_once(
        text,
        '''    private function blinRedPacketExpireSeconds()
    {
        return 43200;
    }
''',
        '''    private function blinRedPacketExpireSeconds()
    {
        return max(3600, intval(round($this->blinMoneyExpireHours("red_packet_refund_hours", 12) * 3600)));
    }
''',
        "red packet configurable expire",
    )

    text = replace_once(
        text,
        '''            "client_msg_no" => strval($order["client_msg_no"]),
            "sender_id" => intval($order["sender_id"]),
''',
        '''            "client_msg_no" => strval($order["client_msg_no"]),
            "trade_no" => isset($order["trade_no"]) ? strval($order["trade_no"]) : "",
            "transaction_no" => isset($order["trade_no"]) ? strval($order["trade_no"]) : "",
            "sender_id" => intval($order["sender_id"]),
''',
        "red packet data trade no",
    )

    text = text.replace("红包12小时未领取完，剩余金额已原路退回", "红包超时未领取完，剩余金额已原路退回")
    text = text.replace("红包（12小时未领取，已退回", "红包（超时未领取，已退回")

    text = replace_once(
        text,
        '''                    if ($sender) {
                        Db::name("user")->where("id", intval($locked["sender_id"]))->update([$field => floatval($sender[$field]) + $refund]);
                        add_user_bill(["id"=>intval($locked["sender_id"]), "appid"=>intval($locked["appid"])], 15, "+" . $this->blinRedPacketMoneyText($refund), "红包超时未领取完，剩余金额已原路退回", intval($locked["money_type"]), 0);
                    }
                }
                $now = time();
                Db::name("im_red_packet_order")->where("id", intval($locked["id"]))->update(["status"=>2, "remaining_amount"=>"0.00", "remaining_count"=>0, "expire_time"=>$effectiveExpireTime, "refund_time"=>$now, "update_time"=>$now]);
''',
        '''                    if ($sender) {
                        Db::name("user")->where("id", intval($locked["sender_id"]))->update([$field => floatval($sender[$field]) + $refund]);
                        $tradeNo = isset($locked["trade_no"]) ? strval($locked["trade_no"]) : "";
                        $tradeText = $tradeNo !== "" ? "（交易单号：" . $tradeNo . "）" : "";
                        add_user_bill(["id"=>intval($locked["sender_id"]), "appid"=>intval($locked["appid"])], 15, "+" . $this->blinRedPacketMoneyText($refund), "红包超时未领取完，剩余金额已原路退回" . $tradeText, intval($locked["money_type"]), 0);
                    }
                }
                $now = time();
                Db::name("im_red_packet_order")->where("id", intval($locked["id"]))->update(["status"=>2, "remaining_amount"=>"0.00", "remaining_count"=>0, "expire_time"=>$effectiveExpireTime, "refund_time"=>$now, "refund_source"=>"timeout", "refund_operator"=>"system", "update_time"=>$now]);
''',
        "red packet timeout refund update",
    )

    text = replace_once(
        text,
        '''                $locked["refund_time"] = $now;
                Db::commit();
                $this->blinUpdateRedPacketPayload($locked);
                $locked["refund_amount"] = $this->blinRedPacketMoneyText($refund);
                $this->blinUpdateRedPacketSenderBillRemark($locked);
''',
        '''                $locked["refund_time"] = $now;
                $locked["refund_source"] = "timeout";
                $locked["refund_operator"] = "system";
                Db::commit();
                $this->blinUpdateRedPacketPayload($locked);
                $locked["refund_amount"] = $this->blinRedPacketMoneyText($refund);
                $this->blinUpdateRedPacketSenderBillRemark($locked);
                $noticeTrade = isset($locked["trade_no"]) && strval($locked["trade_no"]) !== "" ? "交易单号：" . strval($locked["trade_no"]) . "，" : "";
                $this->blinMoneyNotifyUser($locked["appid"], $locked["sender_id"], "红包已退回", $noticeTrade . "红包超时未领取完，剩余" . $this->blinRedPacketMoneyText($refund) . "已退回");
                if (intval($locked["channel_type"]) == 1) {
                    $this->blinMoneyNotifyUser($locked["appid"], $locked["receiver_id"], "红包已退回", $noticeTrade . "红包已超时退回，无法继续领取");
                }
''',
        "red packet timeout notification",
    )

    text = replace_once(
        text,
        '''            $now = time();
            $messageId = Db::name("messages")->insertGetId(["appid"=>intval($this->appid), "sender_id"=>intval($sender["id"]), "receiver_id"=>intval($receiver["id"]), "content"=>"[红包] " . $greeting, "create_time"=>date("Y-m-d H:i:s", $now), "message_type"=>0, "image_path"=>"", "pid"=>0, "money_type"=>$moneyType, "im_payload"=>"", "client_msg_no"=>$clientNo, "file_path"=>"", "file_name"=>""]);
            $orderId = Db::name("im_red_packet_order")->insertGetId(["appid"=>intval($this->appid), "message_id"=>intval($messageId), "group_message_id"=>0, "client_msg_no"=>$clientNo, "sender_id"=>intval($sender["id"]), "receiver_id"=>intval($receiver["id"]), "group_id"=>0, "channel_type"=>1, "packet_type"=>"normal", "amount"=>$amount, "remaining_amount"=>$amount, "total_count"=>1, "remaining_count"=>1, "money_type"=>$moneyType, "greeting"=>$greeting, "status"=>0, "expire_time"=>$now + $this->blinRedPacketExpireSeconds(), "create_time"=>$now, "update_time"=>$now]);
''',
        '''            $now = time();
            $tradeNo = $this->blinMoneyTradeNo("RP");
            $messageId = Db::name("messages")->insertGetId(["appid"=>intval($this->appid), "sender_id"=>intval($sender["id"]), "receiver_id"=>intval($receiver["id"]), "content"=>"[红包] " . $greeting, "create_time"=>date("Y-m-d H:i:s", $now), "message_type"=>0, "image_path"=>"", "pid"=>0, "money_type"=>$moneyType, "im_payload"=>"", "client_msg_no"=>$clientNo, "file_path"=>"", "file_name"=>""]);
            $orderId = Db::name("im_red_packet_order")->insertGetId(["appid"=>intval($this->appid), "message_id"=>intval($messageId), "group_message_id"=>0, "client_msg_no"=>$clientNo, "trade_no"=>$tradeNo, "sender_id"=>intval($sender["id"]), "receiver_id"=>intval($receiver["id"]), "group_id"=>0, "channel_type"=>1, "packet_type"=>"normal", "amount"=>$amount, "remaining_amount"=>$amount, "total_count"=>1, "remaining_count"=>1, "money_type"=>$moneyType, "greeting"=>$greeting, "status"=>0, "expire_time"=>$now + $this->blinRedPacketExpireSeconds(), "create_time"=>$now, "update_time"=>$now]);
''',
        "private red packet trade no",
    )

    text = replace_once(
        text,
        '''            $now = time();
            $messageId = Db::name("im_group_messages")->insertGetId(["appid"=>intval($this->appid), "group_id"=>$groupId, "sender_id"=>intval($sender["id"]), "message_type"=>0, "content"=>"[红包] " . $greeting, "payload"=>"", "client_msg_no"=>$clientNo, "create_time"=>date("Y-m-d H:i:s", $now)]);
            $orderId = Db::name("im_red_packet_order")->insertGetId(["appid"=>intval($this->appid), "message_id"=>0, "group_message_id"=>intval($messageId), "client_msg_no"=>$clientNo, "sender_id"=>intval($sender["id"]), "receiver_id"=>0, "group_id"=>$groupId, "channel_type"=>2, "packet_type"=>$packetType, "amount"=>$amount, "remaining_amount"=>$amount, "total_count"=>$count, "remaining_count"=>$count, "money_type"=>$moneyType, "greeting"=>$greeting, "status"=>0, "expire_time"=>$now + $this->blinRedPacketExpireSeconds(), "create_time"=>$now, "update_time"=>$now]);
''',
        '''            $now = time();
            $tradeNo = $this->blinMoneyTradeNo("RP");
            $messageId = Db::name("im_group_messages")->insertGetId(["appid"=>intval($this->appid), "group_id"=>$groupId, "sender_id"=>intval($sender["id"]), "message_type"=>0, "content"=>"[红包] " . $greeting, "payload"=>"", "client_msg_no"=>$clientNo, "create_time"=>date("Y-m-d H:i:s", $now)]);
            $orderId = Db::name("im_red_packet_order")->insertGetId(["appid"=>intval($this->appid), "message_id"=>0, "group_message_id"=>intval($messageId), "client_msg_no"=>$clientNo, "trade_no"=>$tradeNo, "sender_id"=>intval($sender["id"]), "receiver_id"=>0, "group_id"=>$groupId, "channel_type"=>2, "packet_type"=>$packetType, "amount"=>$amount, "remaining_amount"=>$amount, "total_count"=>$count, "remaining_count"=>$count, "money_type"=>$moneyType, "greeting"=>$greeting, "status"=>0, "expire_time"=>$now + $this->blinRedPacketExpireSeconds(), "create_time"=>$now, "update_time"=>$now]);
''',
        "group red packet trade no",
    )

    write(path, text)


def patch_app() -> None:
    path = APP
    backup(path)
    text = read(path)
    text = text.replace(
        '"transfer_switch":"0","red_packet_switch":"0","transfer_handling_fee":"0","post_tipping_time_limit"',
        '"transfer_switch":"0","red_packet_switch":"0","transfer_refund_hours":"24","red_packet_refund_hours":"12","transfer_handling_fee":"0","post_tipping_time_limit"',
        1,
    )
    text = replace_once(
        text,
        '''                "transfer_switch" => isset($data["transfer_switch"]) ? intval($data["transfer_switch"]) : 0,
                "red_packet_switch" => isset($data["red_packet_switch"]) ? intval($data["red_packet_switch"]) : 0,
                "transfer_handling_fee" => $data["transfer_handling_fee"],
''',
        '''                "transfer_switch" => isset($data["transfer_switch"]) ? intval($data["transfer_switch"]) : 0,
                "red_packet_switch" => isset($data["red_packet_switch"]) ? intval($data["red_packet_switch"]) : 0,
                "transfer_refund_hours" => isset($data["transfer_refund_hours"]) && floatval($data["transfer_refund_hours"]) > 0 ? min(720, max(1, floatval($data["transfer_refund_hours"]))) : 24,
                "red_packet_refund_hours" => isset($data["red_packet_refund_hours"]) && floatval($data["red_packet_refund_hours"]) > 0 ? min(720, max(1, floatval($data["red_packet_refund_hours"]))) : 12,
                "transfer_handling_fee" => $data["transfer_handling_fee"],
''',
        "save refund hour config",
    )
    text = replace_once(
        text,
        '''                if (!isset($result["forum_configuration"]["transfer_handling_fee"])) {
                    $result["forum_configuration"]["transfer_handling_fee"] = 0;
                }
''',
        '''                if (!isset($result["forum_configuration"]["transfer_refund_hours"])) {
                    $result["forum_configuration"]["transfer_refund_hours"] = 24;
                }
                if (!isset($result["forum_configuration"]["red_packet_refund_hours"])) {
                    $result["forum_configuration"]["red_packet_refund_hours"] = 12;
                }
                if (!isset($result["forum_configuration"]["transfer_handling_fee"])) {
                    $result["forum_configuration"]["transfer_handling_fee"] = 0;
                }
''',
        "edit defaults refund hour config",
    )
    write(path, text)


def patch_app_edit() -> None:
    path = APP_EDIT
    backup(path)
    text = read(path)
    if 'name="transfer_refund_hours"' not in text:
        text = replace_once(
            text,
            '''                            <div class="col-md-4">
                                <label for="transfer_handling_fee">转账手续费</label>
                                <input type="number" step="0.01" class="form-control" name="transfer_handling_fee" value="{$data.forum_configuration.transfer_handling_fee}">
                                <small>填写0则无手续费；20%可填写0.2，填写1会按1%兼容处理，100才表示100%；金币余额支持两位小数，手续费会按两位小数计算</small>
                            </div>
''',
            '''                            <div class="col-md-4">
                                <label for="transfer_refund_hours">转账未收自动退回</label>
                                <input type="number" min="1" max="720" step="1" class="form-control" name="transfer_refund_hours" value="{$data.forum_configuration.transfer_refund_hours}">
                                <small>单位：小时。到期未收款会原路退回，并发送系统通知。</small>
                            </div>
                            <div class="col-md-4">
                                <label for="red_packet_refund_hours">红包未领完自动退回</label>
                                <input type="number" min="1" max="720" step="1" class="form-control" name="red_packet_refund_hours" value="{$data.forum_configuration.red_packet_refund_hours}">
                                <small>单位：小时。到期未领完会退回剩余金额。</small>
                            </div>
                            <div class="col-md-4">
                                <label for="transfer_handling_fee">转账手续费</label>
                                <input type="number" step="0.01" class="form-control" name="transfer_handling_fee" value="{$data.forum_configuration.transfer_handling_fee}">
                                <small>填写0则无手续费；20%可填写0.2，填写1会按1%兼容处理，100才表示100%；金币余额支持两位小数，手续费会按两位小数计算</small>
                            </div>
''',
            "app edit refund hour inputs",
        )
    write(path, text)


IM_MONEY_BLOCK = r'''    // blin-money-records-start
    private function blinMoneyAdminAddColumnIfMissing($table, $column, $sql)
    {
        try {
            $row = Db::query("SHOW COLUMNS FROM `" . $table . "` LIKE '" . $column . "'");
            if (!$row) Db::execute($sql);
        } catch (\Exception $e) {}
    }

    private function blinMoneyAdminTradeNo($prefix, $appid = 0)
    {
        $prefix = strtoupper(preg_replace("/[^A-Z0-9]/", "", strval($prefix)));
        if ($prefix === "") $prefix = "TR";
        $appPart = str_pad(strval(intval($appid) % 10000), 4, "0", STR_PAD_LEFT);
        return $prefix . $appPart . date("YmdHis") . str_pad(strval(mt_rand(0, 999999)), 6, "0", STR_PAD_LEFT) . str_pad(strval(mt_rand(0, 9999)), 4, "0", STR_PAD_LEFT);
    }

    private function blinEnsureAdminMoneyTables()
    {
        $this->blinMoneyAdminAddColumnIfMissing("mr_im_transfer_order", "trade_no", "ALTER TABLE `mr_im_transfer_order` ADD COLUMN `trade_no` varchar(64) NOT NULL DEFAULT '' AFTER `client_msg_no`");
        $this->blinMoneyAdminAddColumnIfMissing("mr_im_transfer_order", "refund_source", "ALTER TABLE `mr_im_transfer_order` ADD COLUMN `refund_source` varchar(32) NOT NULL DEFAULT '' AFTER `refund_time`");
        $this->blinMoneyAdminAddColumnIfMissing("mr_im_transfer_order", "refund_operator", "ALTER TABLE `mr_im_transfer_order` ADD COLUMN `refund_operator` varchar(64) NOT NULL DEFAULT '' AFTER `refund_source`");
        $this->blinMoneyAdminAddColumnIfMissing("mr_im_red_packet_order", "trade_no", "ALTER TABLE `mr_im_red_packet_order` ADD COLUMN `trade_no` varchar(64) NOT NULL DEFAULT '' AFTER `client_msg_no`");
        $this->blinMoneyAdminAddColumnIfMissing("mr_im_red_packet_order", "refund_source", "ALTER TABLE `mr_im_red_packet_order` ADD COLUMN `refund_source` varchar(32) NOT NULL DEFAULT '' AFTER `refund_time`");
        $this->blinMoneyAdminAddColumnIfMissing("mr_im_red_packet_order", "refund_operator", "ALTER TABLE `mr_im_red_packet_order` ADD COLUMN `refund_operator` varchar(64) NOT NULL DEFAULT '' AFTER `refund_source`");
        try { Db::execute("ALTER TABLE `mr_im_transfer_order` ADD KEY `idx_trade_no` (`appid`,`trade_no`)"); } catch (\Exception $e) {}
        try { Db::execute("ALTER TABLE `mr_im_red_packet_order` ADD KEY `idx_trade_no` (`appid`,`trade_no`)"); } catch (\Exception $e) {}
        try {
            $rows = Db::name('im_transfer_order')->where('trade_no', '')->limit(100)->select();
            foreach (($rows ?: []) as $row) {
                Db::name('im_transfer_order')->where('id', intval($row['id']))->where('trade_no', '')->update(['trade_no'=>$this->blinMoneyAdminTradeNo('TR', intval($row['appid']))]);
            }
        } catch (\Exception $e) {}
        try {
            $rows = Db::name('im_red_packet_order')->where('trade_no', '')->limit(100)->select();
            foreach (($rows ?: []) as $row) {
                Db::name('im_red_packet_order')->where('id', intval($row['id']))->where('trade_no', '')->update(['trade_no'=>$this->blinMoneyAdminTradeNo('RP', intval($row['appid']))]);
            }
        } catch (\Exception $e) {}
    }

    private function blinMoneyAdminText($value)
    {
        return number_format(floatval($value), 2, '.', '');
    }

    private function blinMoneyAdminBalanceField($moneyType)
    {
        return intval($moneyType) == 1 ? 'integral' : 'money';
    }

    private function blinMoneyAdminNotifyUser($appid, $userId, $title, $content)
    {
        try {
            $userId = intval($userId);
            if ($userId <= 0) return;
            Db::name('message_notification')->insert([
                'appid'=>intval($appid),
                'user_id'=>$userId,
                'title'=>strval($title),
                'content'=>strval($content),
                'send_to'=>0,
                'type'=>21,
                'status'=>0,
                'postid'=>0,
                'time'=>date('Y-m-d H:i:s'),
            ]);
        } catch (\Exception $e) {}
    }

    private function blinMoneyAdminPatchPayload($raw, $fields)
    {
        $payload = json_decode(strval($raw), true);
        if (!is_array($payload)) $payload = [];
        $content = isset($payload['content']) && is_array($payload['content']) ? $payload['content'] : [];
        foreach ($fields as $k=>$v) $content[$k] = $v;
        $payload['content'] = $content;
        return json_encode($payload, JSON_UNESCAPED_UNICODE);
    }

    private function blinMoneyAdminTransferStatusText($status)
    {
        $status = intval($status);
        if ($status == 1) return 'accepted';
        if ($status == 2) return 'refunded';
        return 'pending';
    }

    private function blinMoneyAdminRedPacketStatusText($status)
    {
        $status = intval($status);
        if ($status == 1) return 'finished';
        if ($status == 2) return 'refunded';
        return 'pending';
    }

    private function blinMoneyAdminUpdateTransferPayload($order)
    {
        try {
            $tradeNo = isset($order['trade_no']) ? strval($order['trade_no']) : '';
            $fields = [
                'transfer_id'=>intval($order['id']),
                'trade_no'=>$tradeNo,
                'transaction_no'=>$tradeNo,
                'amount'=>$this->blinMoneyAdminText($order['amount']),
                'money_type'=>intval($order['money_type']),
                'payment'=>intval($order['money_type']),
                'status'=>$this->blinMoneyAdminTransferStatusText($order['status']),
                'expire_time'=>intval($order['expire_time']),
                'expires_at'=>intval($order['expire_time']) > 0 ? date('Y-m-d H:i:s', intval($order['expire_time'])) : '',
                'accepted_at'=>intval($order['accept_time']) > 0 ? date('Y-m-d H:i:s', intval($order['accept_time'])) : '',
                'refunded_at'=>intval($order['refund_time']) > 0 ? date('Y-m-d H:i:s', intval($order['refund_time'])) : '',
            ];
            if (intval(isset($order['channel_type']) ? $order['channel_type'] : 1) == 2) {
                $messageId = intval($order['group_message_id']);
                if ($messageId <= 0) return;
                $message = Db::name('im_group_messages')->where('id', $messageId)->find();
                if (!$message) return;
                Db::name('im_group_messages')->where('id', $messageId)->update(['payload'=>$this->blinMoneyAdminPatchPayload($message['payload'], $fields)]);
                return;
            }
            $messageId = intval($order['message_id']);
            if ($messageId <= 0) return;
            $message = Db::name('messages')->where('id', $messageId)->find();
            if (!$message) return;
            $encoded = $this->blinMoneyAdminPatchPayload($message['im_payload'], $fields);
            Db::name('messages')->where('id', $messageId)->update(['im_payload'=>$encoded]);
            try {
                $logs = Db::name('im_message_log')->where('message_id', 'local_' . $messageId)->select();
                foreach (($logs ?: []) as $log) {
                    Db::name('im_message_log')->where('id', intval($log['id']))->update(['payload'=>$this->blinMoneyAdminPatchPayload($log['payload'], $fields), 'raw_data'=>$this->blinMoneyAdminPatchPayload($log['raw_data'], $fields)]);
                }
            } catch (\Exception $e) {}
        } catch (\Exception $e) {}
    }

    private function blinMoneyAdminUpdateRedPacketPayload($order)
    {
        try {
            $tradeNo = isset($order['trade_no']) ? strval($order['trade_no']) : '';
            $fields = [
                'red_packet_id'=>intval($order['id']),
                'trade_no'=>$tradeNo,
                'transaction_no'=>$tradeNo,
                'amount'=>$this->blinMoneyAdminText($order['amount']),
                'total_amount'=>$this->blinMoneyAdminText($order['amount']),
                'remaining_amount'=>$this->blinMoneyAdminText($order['remaining_amount']),
                'total_count'=>intval($order['total_count']),
                'remaining_count'=>intval($order['remaining_count']),
                'claimed_count'=>max(0, intval($order['total_count']) - intval($order['remaining_count'])),
                'status'=>$this->blinMoneyAdminRedPacketStatusText($order['status']),
                'expire_time'=>intval($order['expire_time']),
                'expires_at'=>intval($order['expire_time']) > 0 ? date('Y-m-d H:i:s', intval($order['expire_time'])) : '',
                'refunded_at'=>intval($order['refund_time']) > 0 ? date('Y-m-d H:i:s', intval($order['refund_time'])) : '',
            ];
            if (intval($order['channel_type']) == 2) {
                $messageId = intval($order['group_message_id']);
                if ($messageId <= 0) return;
                $message = Db::name('im_group_messages')->where('id', $messageId)->find();
                if (!$message) return;
                Db::name('im_group_messages')->where('id', $messageId)->update(['payload'=>$this->blinMoneyAdminPatchPayload($message['payload'], $fields)]);
                return;
            }
            $messageId = intval($order['message_id']);
            if ($messageId <= 0) return;
            $message = Db::name('messages')->where('id', $messageId)->find();
            if (!$message) return;
            $encoded = $this->blinMoneyAdminPatchPayload($message['im_payload'], $fields);
            Db::name('messages')->where('id', $messageId)->update(['im_payload'=>$encoded]);
            try {
                $logs = Db::name('im_message_log')->where('message_id', 'local_' . $messageId)->select();
                foreach (($logs ?: []) as $log) {
                    Db::name('im_message_log')->where('id', intval($log['id']))->update(['payload'=>$this->blinMoneyAdminPatchPayload($log['payload'], $fields), 'raw_data'=>$this->blinMoneyAdminPatchPayload($log['raw_data'], $fields)]);
                }
            } catch (\Exception $e) {}
        } catch (\Exception $e) {}
    }

    private function blinMoneyAdminRefundTransfer()
    {
        $this->blinEnsureAdminMoneyTables();
        $id = intval(input('id'));
        if ($id <= 0) return $this->imFail('参数错误');
        $order = Db::name('im_transfer_order')->where('id', $id)->find();
        if (!$order) return $this->imFail('转账记录不存在');
        $this->blinRequireApp($order['appid']);
        if (intval($order['status']) == 1) return $this->imFail('对方已收款，不能退回');
        if (intval($order['status']) == 2) return $this->imOk('该转账已退回');
        $reason = trim(strval(input('reason')));
        if ($reason === '') $reason = '后台手动退回';
        Db::startTrans();
        try {
            $locked = Db::name('im_transfer_order')->where('id', $id)->lock(true)->find();
            if (!$locked || intval($locked['status']) !== 0) {
                Db::rollback();
                return $this->imFail('转账状态已变化，请刷新后再试');
            }
            $field = $this->blinMoneyAdminBalanceField($locked['money_type']);
            $refund = floatval($locked['amount']) + (intval($locked['fee_payer']) == 1 ? floatval($locked['fee']) : 0);
            $sender = Db::name('user')->where('id', intval($locked['sender_id']))->where('appid', intval($locked['appid']))->lock(true)->find();
            if (!$sender) throw new \Exception('SENDER_NOT_FOUND');
            if ($refund > 0) {
                Db::name('user')->where('id', intval($locked['sender_id']))->update([$field=>floatval($sender[$field]) + $refund]);
            }
            $tradeNo = isset($locked['trade_no']) ? strval($locked['trade_no']) : '';
            $tradeText = $tradeNo !== '' ? '（交易单号：' . $tradeNo . '）' : '';
            add_user_bill(['id'=>intval($locked['sender_id']), 'appid'=>intval($locked['appid'])], 9, '+' . $this->blinMoneyAdminText($refund), $reason . $tradeText, intval($locked['money_type']), 0);
            add_user_bill(['id'=>intval($locked['receiver_id']), 'appid'=>intval($locked['appid'])], 9, '0.00', '后台已退回转账，未入账' . $tradeText, intval($locked['money_type']), 0);
            $now = time();
            $operator = isset($this->admin_info['id']) ? strval($this->admin_info['id']) : 'admin';
            Db::name('im_transfer_order')->where('id', $id)->update(['status'=>2, 'refund_time'=>$now, 'refund_source'=>'admin', 'refund_operator'=>$operator, 'update_time'=>$now]);
            $locked['status'] = 2;
            $locked['refund_time'] = $now;
            $locked['refund_source'] = 'admin';
            $locked['refund_operator'] = $operator;
            Db::commit();
            $this->blinMoneyAdminUpdateTransferPayload($locked);
            $noticeTrade = $tradeNo !== '' ? '交易单号：' . $tradeNo . '，' : '';
            $this->blinMoneyAdminNotifyUser($locked['appid'], $locked['sender_id'], '转账已退回', $noticeTrade . '后台已将未收款转账退回，金额' . $this->blinMoneyAdminText($refund));
            $this->blinMoneyAdminNotifyUser($locked['appid'], $locked['receiver_id'], '转账已退回', $noticeTrade . '后台已将转账退回给转出方');
            return $this->imOk('退回成功', '', ['trade_no'=>$tradeNo]);
        } catch (\Exception $e) {
            try { Db::rollback(); } catch (\Exception $rollbackException) {}
            return $this->imFail('退回失败，请稍后再试');
        }
    }

    private function blinMoneyAdminRefundRedPacket()
    {
        $this->blinEnsureAdminMoneyTables();
        $id = intval(input('id'));
        if ($id <= 0) return $this->imFail('参数错误');
        $order = Db::name('im_red_packet_order')->where('id', $id)->find();
        if (!$order) return $this->imFail('红包记录不存在');
        $this->blinRequireApp($order['appid']);
        if (intval($order['status']) == 1 || floatval($order['remaining_amount']) <= 0) return $this->imFail('红包已领完，不能退回');
        if (intval($order['status']) == 2) return $this->imOk('该红包已退回');
        $reason = trim(strval(input('reason')));
        if ($reason === '') $reason = '后台手动退回红包';
        Db::startTrans();
        try {
            $locked = Db::name('im_red_packet_order')->where('id', $id)->lock(true)->find();
            if (!$locked || intval($locked['status']) !== 0 || floatval($locked['remaining_amount']) <= 0) {
                Db::rollback();
                return $this->imFail('红包状态已变化，请刷新后再试');
            }
            $refund = floatval($locked['remaining_amount']);
            $field = $this->blinMoneyAdminBalanceField($locked['money_type']);
            $sender = Db::name('user')->where('id', intval($locked['sender_id']))->where('appid', intval($locked['appid']))->lock(true)->find();
            if (!$sender) throw new \Exception('SENDER_NOT_FOUND');
            Db::name('user')->where('id', intval($locked['sender_id']))->update([$field=>floatval($sender[$field]) + $refund]);
            $tradeNo = isset($locked['trade_no']) ? strval($locked['trade_no']) : '';
            $tradeText = $tradeNo !== '' ? '（交易单号：' . $tradeNo . '）' : '';
            add_user_bill(['id'=>intval($locked['sender_id']), 'appid'=>intval($locked['appid'])], 15, '+' . $this->blinMoneyAdminText($refund), $reason . $tradeText, intval($locked['money_type']), 0);
            $now = time();
            $operator = isset($this->admin_info['id']) ? strval($this->admin_info['id']) : 'admin';
            Db::name('im_red_packet_order')->where('id', $id)->update(['status'=>2, 'remaining_amount'=>'0.00', 'remaining_count'=>0, 'refund_time'=>$now, 'refund_source'=>'admin', 'refund_operator'=>$operator, 'update_time'=>$now]);
            $locked['status'] = 2;
            $locked['remaining_amount'] = '0.00';
            $locked['remaining_count'] = 0;
            $locked['refund_time'] = $now;
            $locked['refund_source'] = 'admin';
            $locked['refund_operator'] = $operator;
            Db::commit();
            $this->blinMoneyAdminUpdateRedPacketPayload($locked);
            $noticeTrade = $tradeNo !== '' ? '交易单号：' . $tradeNo . '，' : '';
            $this->blinMoneyAdminNotifyUser($locked['appid'], $locked['sender_id'], '红包已退回', $noticeTrade . '后台已退回未领取红包，剩余金额' . $this->blinMoneyAdminText($refund));
            if (intval($locked['channel_type']) == 1) {
                $this->blinMoneyAdminNotifyUser($locked['appid'], $locked['receiver_id'], '红包已退回', $noticeTrade . '红包已由后台退回，无法继续领取');
            }
            return $this->imOk('退回成功', '', ['trade_no'=>$tradeNo]);
        } catch (\Exception $e) {
            try { Db::rollback(); } catch (\Exception $rollbackException) {}
            return $this->imFail('退回失败，请稍后再试');
        }
    }

    public function transfer_records()
    {
        $this->blinEnsureAdminMoneyTables();
        if (Request::isPost() && trim(input('op')) === 'refund') {
            return $this->blinMoneyAdminRefundTransfer();
        }
        if (Request::isAjax() || input('callback') != '') {
            $limit = input('limit') ? intval(input('limit')) : 10;
            $page = input('page') ? intval(input('page')) : 1;
            $query = Db::name('im_transfer_order')->alias('t')
                ->leftJoin('app a', 'a.appid=t.appid')
                ->leftJoin('user su', 'su.id=t.sender_id')
                ->leftJoin('user ru', 'ru.id=t.receiver_id')
                ->leftJoin('im_groups g', 'g.id=t.group_id');
            $countQuery = Db::name('im_transfer_order')->alias('t');
            $appid = intval(input('appid'));
            if ($appid > 0) {
                $this->blinRequireApp($appid);
                $query->where('t.appid', $appid);
                $countQuery->where('t.appid', $appid);
            } else {
                $this->blinScopeQuery($query, 't.appid');
                $this->blinScopeQuery($countQuery, 't.appid');
            }
            $status = trim(strval(input('status', '')));
            if ($status !== '') {
                $query->where('t.status', intval($status));
                $countQuery->where('t.status', intval($status));
            }
            $channelType = intval(input('channel_type'));
            if ($channelType > 0) {
                $query->where('t.channel_type', $channelType);
                $countQuery->where('t.channel_type', $channelType);
            }
            $keyword = trim(input('keyword'));
            if ($keyword !== '') {
                $query->where(function($q) use ($keyword) {
                    $q->where('t.trade_no','like','%'.$keyword.'%')
                      ->whereOr('t.client_msg_no','like','%'.$keyword.'%')
                      ->whereOr('t.sender_id','like','%'.$keyword.'%')
                      ->whereOr('t.receiver_id','like','%'.$keyword.'%')
                      ->whereOr('su.username','like','%'.$keyword.'%')
                      ->whereOr('su.nickname','like','%'.$keyword.'%')
                      ->whereOr('ru.username','like','%'.$keyword.'%')
                      ->whereOr('ru.nickname','like','%'.$keyword.'%')
                      ->whereOr('g.name','like','%'.$keyword.'%');
                });
                $countQuery->where(function($q) use ($keyword) {
                    $q->where('trade_no','like','%'.$keyword.'%')
                      ->whereOr('client_msg_no','like','%'.$keyword.'%')
                      ->whereOr('sender_id','like','%'.$keyword.'%')
                      ->whereOr('receiver_id','like','%'.$keyword.'%');
                });
            }
            $total = $countQuery->count();
            $rows = $query->field('t.*,a.appname,su.username sender_username,su.nickname sender_nickname,ru.username receiver_username,ru.nickname receiver_nickname,g.name group_name')
                ->order('t.id','desc')->page($page,$limit)->select();
            foreach (($rows ?: []) as $k=>$v) {
                $rows[$k]['trade_no'] = isset($v['trade_no']) ? strval($v['trade_no']) : '';
                $rows[$k]['amount_text'] = $this->blinMoneyAdminText($v['amount']);
                $rows[$k]['hold_amount_text'] = $this->blinMoneyAdminText($v['hold_amount']);
                $rows[$k]['fee_text'] = $this->blinMoneyAdminText($v['fee']);
                $rows[$k]['sender_name'] = trim(strval($v['sender_nickname'])) !== '' ? $v['sender_nickname'] : $v['sender_username'];
                $rows[$k]['receiver_name'] = trim(strval($v['receiver_nickname'])) !== '' ? $v['receiver_nickname'] : $v['receiver_username'];
                $rows[$k]['channel_text'] = intval(isset($v['channel_type']) ? $v['channel_type'] : 1) == 2 ? '群聊' : '私聊';
                $rows[$k]['money_type_text'] = intval($v['money_type']) == 1 ? '积分' : '金币';
                $rows[$k]['status_text'] = intval($v['status']) == 1 ? '已收款' : (intval($v['status']) == 2 ? '已退回' : '待收款');
                $rows[$k]['can_refund'] = intval($v['status']) === 0 ? 1 : 0;
                $rows[$k]['create_time_text'] = intval($v['create_time']) > 0 ? date('Y-m-d H:i:s', intval($v['create_time'])) : '';
                $rows[$k]['accept_time_text'] = intval($v['accept_time']) > 0 ? date('Y-m-d H:i:s', intval($v['accept_time'])) : '';
                $rows[$k]['refund_time_text'] = intval($v['refund_time']) > 0 ? date('Y-m-d H:i:s', intval($v['refund_time'])) : '';
            }
            return $this->jsonp(['rows'=>$rows,'total'=>$total]);
        }
        return $this->fetch();
    }

    public function red_packet_records()
    {
        $this->blinEnsureAdminMoneyTables();
        if (Request::isPost() && trim(input('op')) === 'refund') {
            return $this->blinMoneyAdminRefundRedPacket();
        }
        if (Request::isAjax() || input('callback') != '') {
            $limit = input('limit') ? intval(input('limit')) : 10;
            $page = input('page') ? intval(input('page')) : 1;
            $query = Db::name('im_red_packet_order')->alias('r')
                ->leftJoin('app a', 'a.appid=r.appid')
                ->leftJoin('user su', 'su.id=r.sender_id')
                ->leftJoin('user ru', 'ru.id=r.receiver_id')
                ->leftJoin('im_groups g', 'g.id=r.group_id');
            $countQuery = Db::name('im_red_packet_order')->alias('r');
            $appid = intval(input('appid'));
            if ($appid > 0) {
                $this->blinRequireApp($appid);
                $query->where('r.appid', $appid);
                $countQuery->where('r.appid', $appid);
            } else {
                $this->blinScopeQuery($query, 'r.appid');
                $this->blinScopeQuery($countQuery, 'r.appid');
            }
            $status = trim(strval(input('status', '')));
            if ($status !== '') {
                $query->where('r.status', intval($status));
                $countQuery->where('r.status', intval($status));
            }
            $channelType = intval(input('channel_type'));
            if ($channelType > 0) {
                $query->where('r.channel_type', $channelType);
                $countQuery->where('r.channel_type', $channelType);
            }
            $keyword = trim(input('keyword'));
            if ($keyword !== '') {
                $query->where(function($q) use ($keyword) {
                    $q->where('r.trade_no','like','%'.$keyword.'%')
                      ->whereOr('r.client_msg_no','like','%'.$keyword.'%')
                      ->whereOr('r.sender_id','like','%'.$keyword.'%')
                      ->whereOr('r.receiver_id','like','%'.$keyword.'%')
                      ->whereOr('r.greeting','like','%'.$keyword.'%')
                      ->whereOr('su.username','like','%'.$keyword.'%')
                      ->whereOr('su.nickname','like','%'.$keyword.'%')
                      ->whereOr('ru.username','like','%'.$keyword.'%')
                      ->whereOr('ru.nickname','like','%'.$keyword.'%')
                      ->whereOr('g.name','like','%'.$keyword.'%');
                });
                $countQuery->where(function($q) use ($keyword) {
                    $q->where('trade_no','like','%'.$keyword.'%')
                      ->whereOr('client_msg_no','like','%'.$keyword.'%')
                      ->whereOr('sender_id','like','%'.$keyword.'%')
                      ->whereOr('receiver_id','like','%'.$keyword.'%')
                      ->whereOr('greeting','like','%'.$keyword.'%');
                });
            }
            $total = $countQuery->count();
            $rows = $query->field('r.*,a.appname,su.username sender_username,su.nickname sender_nickname,ru.username receiver_username,ru.nickname receiver_nickname,g.name group_name')
                ->order('r.id','desc')->page($page,$limit)->select();
            foreach (($rows ?: []) as $k=>$v) {
                $claimCount = Db::name('im_red_packet_claim')->where('appid', intval($v['appid']))->where('red_packet_id', intval($v['id']))->count();
                $claimAmount = Db::name('im_red_packet_claim')->where('appid', intval($v['appid']))->where('red_packet_id', intval($v['id']))->sum('amount');
                $rows[$k]['trade_no'] = isset($v['trade_no']) ? strval($v['trade_no']) : '';
                $rows[$k]['amount_text'] = $this->blinMoneyAdminText($v['amount']);
                $rows[$k]['remaining_amount_text'] = $this->blinMoneyAdminText($v['remaining_amount']);
                $rows[$k]['claimed_count'] = intval($claimCount);
                $rows[$k]['claimed_amount_text'] = $this->blinMoneyAdminText($claimAmount);
                $rows[$k]['sender_name'] = trim(strval($v['sender_nickname'])) !== '' ? $v['sender_nickname'] : $v['sender_username'];
                $rows[$k]['receiver_name'] = trim(strval($v['receiver_nickname'])) !== '' ? $v['receiver_nickname'] : $v['receiver_username'];
                $rows[$k]['channel_text'] = intval($v['channel_type']) == 2 ? '群聊' : '私聊';
                $rows[$k]['packet_type_text'] = strval($v['packet_type']) === 'lucky' ? '拼手气' : '普通';
                $rows[$k]['money_type_text'] = intval($v['money_type']) == 1 ? '积分' : '金币';
                $rows[$k]['status_text'] = intval($v['status']) == 1 ? '已领完' : (intval($v['status']) == 2 ? '已退回' : '领取中');
                $rows[$k]['can_refund'] = intval($v['status']) === 0 && floatval($v['remaining_amount']) > 0 ? 1 : 0;
                $rows[$k]['create_time_text'] = intval($v['create_time']) > 0 ? date('Y-m-d H:i:s', intval($v['create_time'])) : '';
                $rows[$k]['refund_time_text'] = intval($v['refund_time']) > 0 ? date('Y-m-d H:i:s', intval($v['refund_time'])) : '';
            }
            return $this->jsonp(['rows'=>$rows,'total'=>$total]);
        }
        return $this->fetch();
    }
    // blin-money-records-end
'''


def patch_im() -> None:
    path = IM
    backup(path)
    text = read(path)
    start = text.find("    // blin-money-records-start")
    end = text.find("    // blin-money-records-end", start)
    if start < 0 or end < 0:
        raise RuntimeError("missing Im money records block")
    end = text.find("\n", end)
    text = text[:start] + IM_MONEY_BLOCK + text[end + 1:]
    write(path, text)


TRANSFER_VIEW_TEXT = r'''{extend name="layout" /}
{block name="body"}
<div class="container-fluid p-t-15">
  <div class="row"><div class="col-lg-12"><div class="card">
    <header class="card-header"><div class="card-title">用户转账记录</div></header>
    <div class="card-body">
      <div class="row search-box">
        <div class="col-md-2 mb-2"><input class="form-control" id="appid" placeholder="APPID"></div>
        <div class="col-md-3 mb-2"><input class="form-control" id="keyword" placeholder="交易单号/用户/群聊/流水号"></div>
        <div class="col-md-2 mb-2"><select class="form-control" id="channel_type"><option value="">全部场景</option><option value="1">私聊</option><option value="2">群聊</option></select></div>
        <div class="col-md-2 mb-2"><select class="form-control" id="status"><option value="">全部状态</option><option value="0">待收款</option><option value="1">已收款</option><option value="2">已退回</option></select></div>
        <div class="col-md-2 mb-2"><button class="btn btn-default" onclick="$('#table').bootstrapTable('refresh');"><i class="mdi mdi-magnify"></i> 搜索</button></div>
      </div>
      <table id="table"></table>
    </div>
  </div></div></div>
</div>
<div class="modal fade" id="detailModal" tabindex="-1">
  <div class="modal-dialog modal-lg"><div class="modal-content">
    <div class="modal-header"><h6 class="modal-title">转账详情</h6><button type="button" class="btn-close" data-bs-dismiss="modal"></button></div>
    <div class="modal-body"><pre id="detailContent" style="white-space:pre-wrap;word-break:break-all;"></pre></div>
  </div></div>
</div>
{/block}
{block name="js"}
<script>
window.parent.$("#iframe-content .mt-nav-bar").find('a.active').text("用户转账记录");
function showDetail(row){ $('#detailContent').text(JSON.stringify(row,null,2)); $('#detailModal').modal('show'); }
function getSearchParams(){ return {appid: $('#appid').val(), keyword: $('#keyword').val(), channel_type: $('#channel_type').val(), status: $('#status').val()}; }
function resultOk(res){ return res && (res.code == 1 || res.status == 1); }
function refundTransfer(row){
  if(!row || row.can_refund != 1){ return; }
  var label = row.trade_no || ('ID ' + row.id);
  if(!confirm('确认退回这笔待收款转账？\n' + label)){ return; }
  $.post('{:url("transfer_records")}', {op:'refund', id:row.id, reason:'后台手动退回'}, function(res){
    alert(res && res.msg ? res.msg : (resultOk(res) ? '操作成功' : '操作失败'));
    if(resultOk(res)){ $('#table').bootstrapTable('refresh'); }
  }, 'json');
}
$('#table').bootstrapTable({
  classes: 'table table-bordered table-hover table-striped lyear-table',
  url: '{:url("transfer_records")}',
  uniqueId: 'id', idField: 'id', dataType: 'jsonp', method: 'get',
  pagination: true, sidePagination: 'server', pageSize: 10, pageList: [10,25,50,100],
  showColumns: true, showRefresh: true, showFullscreen: true, totalField: 'total',
  queryParams: function(params){ return Object.assign({limit:params.limit, page:(params.offset/params.limit)+1}, getSearchParams()); },
  columns: [
    {field:'id',title:'ID'},
    {field:'trade_no',title:'交易单号'},
    {field:'appid',title:'APPID'},
    {field:'appname',title:'应用'},
    {field:'channel_text',title:'场景'},
    {field:'group_name',title:'群聊'},
    {field:'sender_name',title:'转出用户'},
    {field:'receiver_name',title:'收款用户'},
    {field:'amount_text',title:'金额'},
    {field:'hold_amount_text',title:'扣款'},
    {field:'fee_text',title:'手续费'},
    {field:'money_type_text',title:'余额类型'},
    {field:'status_text',title:'状态'},
    {field:'create_time_text',title:'创建时间'},
    {field:'accept_time_text',title:'收款时间'},
    {field:'refund_time_text',title:'退回时间'},
    {field:'operate',title:'操作',formatter:function(v,row){
      var html = '<button class="btn btn-sm btn-default detail-btn">详情</button>';
      if(row.can_refund == 1){ html += ' <button class="btn btn-sm btn-danger refund-btn">退回</button>'; }
      return html;
    },events:{'click .detail-btn':function(e,v,row){showDetail(row);}, 'click .refund-btn':function(e,v,row){refundTransfer(row);}}}
  ]
});
</script>
{/block}
'''


RED_PACKET_VIEW_TEXT = r'''{extend name="layout" /}
{block name="body"}
<div class="container-fluid p-t-15">
  <div class="row"><div class="col-lg-12"><div class="card">
    <header class="card-header"><div class="card-title">用户红包记录</div></header>
    <div class="card-body">
      <div class="row search-box">
        <div class="col-md-2 mb-2"><input class="form-control" id="appid" placeholder="APPID"></div>
        <div class="col-md-3 mb-2"><input class="form-control" id="keyword" placeholder="交易单号/用户/群聊/祝福语/流水号"></div>
        <div class="col-md-2 mb-2"><select class="form-control" id="channel_type"><option value="">全部场景</option><option value="1">私聊</option><option value="2">群聊</option></select></div>
        <div class="col-md-2 mb-2"><select class="form-control" id="status"><option value="">全部状态</option><option value="0">领取中</option><option value="1">已领完</option><option value="2">已退回</option></select></div>
        <div class="col-md-2 mb-2"><button class="btn btn-default" onclick="$('#table').bootstrapTable('refresh');"><i class="mdi mdi-magnify"></i> 搜索</button></div>
      </div>
      <table id="table"></table>
    </div>
  </div></div></div>
</div>
<div class="modal fade" id="detailModal" tabindex="-1">
  <div class="modal-dialog modal-lg"><div class="modal-content">
    <div class="modal-header"><h6 class="modal-title">红包详情</h6><button type="button" class="btn-close" data-bs-dismiss="modal"></button></div>
    <div class="modal-body"><pre id="detailContent" style="white-space:pre-wrap;word-break:break-all;"></pre></div>
  </div></div>
</div>
{/block}
{block name="js"}
<script>
window.parent.$("#iframe-content .mt-nav-bar").find('a.active').text("用户红包记录");
function showDetail(row){ $('#detailContent').text(JSON.stringify(row,null,2)); $('#detailModal').modal('show'); }
function getSearchParams(){ return {appid: $('#appid').val(), keyword: $('#keyword').val(), channel_type: $('#channel_type').val(), status: $('#status').val()}; }
function resultOk(res){ return res && (res.code == 1 || res.status == 1); }
function refundRedPacket(row){
  if(!row || row.can_refund != 1){ return; }
  var label = row.trade_no || ('ID ' + row.id);
  if(!confirm('确认退回这个未领完红包？\n' + label)){ return; }
  $.post('{:url("red_packet_records")}', {op:'refund', id:row.id, reason:'后台手动退回红包'}, function(res){
    alert(res && res.msg ? res.msg : (resultOk(res) ? '操作成功' : '操作失败'));
    if(resultOk(res)){ $('#table').bootstrapTable('refresh'); }
  }, 'json');
}
$('#table').bootstrapTable({
  classes: 'table table-bordered table-hover table-striped lyear-table',
  url: '{:url("red_packet_records")}',
  uniqueId: 'id', idField: 'id', dataType: 'jsonp', method: 'get',
  pagination: true, sidePagination: 'server', pageSize: 10, pageList: [10,25,50,100],
  showColumns: true, showRefresh: true, showFullscreen: true, totalField: 'total',
  queryParams: function(params){ return Object.assign({limit:params.limit, page:(params.offset/params.limit)+1}, getSearchParams()); },
  columns: [
    {field:'id',title:'ID'},
    {field:'trade_no',title:'交易单号'},
    {field:'appid',title:'APPID'},
    {field:'appname',title:'应用'},
    {field:'channel_text',title:'场景'},
    {field:'packet_type_text',title:'类型'},
    {field:'group_name',title:'群聊'},
    {field:'sender_name',title:'发送用户'},
    {field:'receiver_name',title:'接收用户'},
    {field:'amount_text',title:'总金额'},
    {field:'claimed_amount_text',title:'已领取'},
    {field:'remaining_amount_text',title:'剩余'},
    {field:'claimed_count',title:'已领个数'},
    {field:'total_count',title:'总个数'},
    {field:'money_type_text',title:'余额类型'},
    {field:'status_text',title:'状态'},
    {field:'create_time_text',title:'创建时间'},
    {field:'refund_time_text',title:'退回时间'},
    {field:'operate',title:'操作',formatter:function(v,row){
      var html = '<button class="btn btn-sm btn-default detail-btn">详情</button>';
      if(row.can_refund == 1){ html += ' <button class="btn btn-sm btn-danger refund-btn">退回</button>'; }
      return html;
    },events:{'click .detail-btn':function(e,v,row){showDetail(row);}, 'click .refund-btn':function(e,v,row){refundRedPacket(row);}}}
  ]
});
</script>
{/block}
'''


def patch_views() -> None:
    backup(TRANSFER_VIEW)
    write(TRANSFER_VIEW, TRANSFER_VIEW_TEXT)
    backup(RED_PACKET_VIEW)
    write(RED_PACKET_VIEW, RED_PACKET_VIEW_TEXT)


def main() -> None:
    for p in [API, APP, IM, APP_EDIT, RED_PACKET_VIEW, TRANSFER_VIEW]:
        if not p.exists():
            raise RuntimeError(f"missing file: {p}")
    patch_api()
    patch_app()
    patch_app_edit()
    patch_im()
    patch_views()
    print("money trade refund admin patch applied")


if __name__ == "__main__":
    main()
