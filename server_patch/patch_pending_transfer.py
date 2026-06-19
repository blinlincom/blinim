#!/usr/bin/env python3
"""Patch IM transfer flow to pending receive, accept, and 24h refund."""
from datetime import datetime
from pathlib import Path


ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"


def backup(path: Path) -> str:
    target = path.with_name(
        f"{path.name}.bak_pending_transfer_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    target.write_text(path.read_text(errors="ignore"))
    return str(target)


HELPER_BLOCK = r'''
    // blin-pending-transfer-start
    private function blinEnsureTransferTable()
    {
        try {
            Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_transfer_order` (`id` bigint(20) NOT NULL AUTO_INCREMENT, `appid` bigint(20) NOT NULL DEFAULT 0, `message_id` bigint(20) NOT NULL DEFAULT 0, `client_msg_no` varchar(128) NOT NULL DEFAULT '', `sender_id` bigint(20) NOT NULL DEFAULT 0, `receiver_id` bigint(20) NOT NULL DEFAULT 0, `amount` decimal(16,2) NOT NULL DEFAULT '0.00', `money_type` tinyint(1) NOT NULL DEFAULT 0, `fee` decimal(16,2) NOT NULL DEFAULT '0.00', `fee_payer` tinyint(1) NOT NULL DEFAULT 0 COMMENT '0 receiver, 1 sender', `hold_amount` decimal(16,2) NOT NULL DEFAULT '0.00', `note` varchar(255) NOT NULL DEFAULT '', `status` tinyint(1) NOT NULL DEFAULT 0 COMMENT '0 pending, 1 accepted, 2 refunded', `expire_time` int(11) NOT NULL DEFAULT 0, `accept_time` int(11) NOT NULL DEFAULT 0, `refund_time` int(11) NOT NULL DEFAULT 0, `create_time` int(11) NOT NULL DEFAULT 0, `update_time` int(11) NOT NULL DEFAULT 0, PRIMARY KEY (`id`), KEY `idx_app_msg` (`appid`,`message_id`), KEY `idx_client_no` (`appid`,`client_msg_no`), KEY `idx_receiver` (`appid`,`receiver_id`,`status`), KEY `idx_sender` (`appid`,`sender_id`,`status`), KEY `idx_expire` (`appid`,`status`,`expire_time`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
        } catch (\Exception $e) {}
    }

    private function blinTransferMoneyText($value)
    {
        return number_format(floatval($value), 2, ".", "");
    }

    private function blinTransferBalanceField($moneyType)
    {
        return intval($moneyType) == 1 ? "integral" : "money";
    }

    private function blinTransferStatusText($status)
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
    {
        if (!$order) {
            return [];
        }
        return [
            "transfer_id" => intval($order["id"]),
            "message_id" => intval($order["message_id"]),
            "client_msg_no" => strval($order["client_msg_no"]),
            "amount" => $this->blinTransferMoneyText($order["amount"]),
            "money_type" => intval($order["money_type"]),
            "payment" => intval($order["money_type"]),
            "status" => $this->blinTransferStatusText($order["status"]),
            "expires_at" => intval($order["expire_time"]) > 0 ? date("Y-m-d H:i:s", intval($order["expire_time"])) : "",
            "expire_time" => intval($order["expire_time"]),
            "accepted_at" => intval($order["accept_time"]) > 0 ? date("Y-m-d H:i:s", intval($order["accept_time"])) : "",
            "refunded_at" => intval($order["refund_time"]) > 0 ? date("Y-m-d H:i:s", intval($order["refund_time"])) : "",
        ];
    }

    private function blinTransferPayloadJson($clientPayload, $messageId, $clientNo, $senderInfo, $receiverInfo, $transfer)
    {
        $payload = json_decode(strval($clientPayload), true);
        if (!is_array($payload)) {
            $payload = [];
        }
        $content = isset($payload["content"]) && is_array($payload["content"]) ? $payload["content"] : [];
        $content["amount"] = $this->blinTransferMoneyText($transfer["amount"]);
        $content["money_type"] = intval($transfer["money_type"]);
        $content["payment"] = intval($transfer["money_type"]);
        $content["type"] = intval($transfer["money_type"]);
        $content["status"] = isset($transfer["status_text"]) ? strval($transfer["status_text"]) : "pending";
        $content["transfer_id"] = intval($transfer["id"]);
        $content["expires_at"] = intval($transfer["expire_time"]) > 0 ? date("Y-m-d H:i:s", intval($transfer["expire_time"])) : "";
        $content["expire_time"] = intval($transfer["expire_time"]);
        if (isset($transfer["note"]) && trim(strval($transfer["note"])) !== "") {
            $content["note"] = trim(strval($transfer["note"]));
        }
        if (isset($transfer["accepted_at"]) && intval($transfer["accepted_at"]) > 0) {
            $content["accepted_at"] = date("Y-m-d H:i:s", intval($transfer["accepted_at"]));
        }
        if (isset($transfer["refunded_at"]) && intval($transfer["refunded_at"]) > 0) {
            $content["refunded_at"] = date("Y-m-d H:i:s", intval($transfer["refunded_at"]));
        }
        $payload["version"] = isset($payload["version"]) ? $payload["version"] : "1.0";
        $payload["message_id"] = intval($messageId);
        $payload["client_msg_no"] = strval($clientNo);
        $payload["conversation_type"] = "single";
        $payload["channel_type"] = 1;
        $payload["from_uid"] = $this->appid . "_" . intval($senderInfo["id"]);
        $payload["to_uid"] = $this->appid . "_" . intval($receiverInfo["id"]);
        $payload["from_user_id"] = intval($senderInfo["id"]);
        $payload["to_user_id"] = intval($receiverInfo["id"]);
        $payload["msg_type"] = "transfer";
        $payload["message_type"] = 2;
        $payload["content"] = $content;
        $payload["legacy"] = ["type" => 2, "content" => $content["amount"], "image_path" => "", "sender_id" => intval($senderInfo["id"]), "receiver_id" => intval($receiverInfo["id"]), "money_type" => intval($transfer["money_type"])];
        $payload["create_time"] = isset($payload["create_time"]) && strval($payload["create_time"]) !== "" ? $payload["create_time"] : date("Y-m-d H:i:s", time());
        return json_encode($payload, JSON_UNESCAPED_UNICODE);
    }

    private function blinUpdateTransferMessagePayload($order)
    {
        try {
            $messageId = intval($order["message_id"]);
            if ($messageId <= 0) {
                return;
            }
            $message = Db::name("messages")->where("id", $messageId)->find();
            if (!$message) {
                return;
            }
            $sender = Db::name("user")->where("id", intval($order["sender_id"]))->find();
            $receiver = Db::name("user")->where("id", intval($order["receiver_id"]))->find();
            if (!$sender) {
                $sender = ["id" => intval($order["sender_id"])];
            }
            if (!$receiver) {
                $receiver = ["id" => intval($order["receiver_id"])];
            }
            $transfer = [
                "id" => intval($order["id"]),
                "amount" => $order["amount"],
                "money_type" => intval($order["money_type"]),
                "note" => isset($order["note"]) ? $order["note"] : "",
                "expire_time" => intval($order["expire_time"]),
                "status_text" => $this->blinTransferStatusText($order["status"]),
                "accepted_at" => intval(isset($order["accept_time"]) ? $order["accept_time"] : 0),
                "refunded_at" => intval(isset($order["refund_time"]) ? $order["refund_time"] : 0),
            ];
            $payloadJson = $this->blinTransferPayloadJson($message["im_payload"], $messageId, isset($message["client_msg_no"]) ? $message["client_msg_no"] : $order["client_msg_no"], $sender, $receiver, $transfer);
            Db::name("messages")->where("id", $messageId)->update(["im_payload" => $payloadJson]);
            try {
                $logs = Db::name("im_message_log")->where("message_id", "local_" . $messageId)->select();
                foreach ($logs as $log) {
                    $payload = json_decode(strval($log["payload"]), true);
                    $next = json_decode($payloadJson, true);
                    if (!is_array($payload) || !is_array($next)) {
                        continue;
                    }
                    $payload["content"] = $next["content"];
                    $payload["msg_type"] = "transfer";
                    $payload["message_type"] = 2;
                    $encoded = json_encode($payload, JSON_UNESCAPED_UNICODE);
                    Db::name("im_message_log")->where("id", intval($log["id"]))->update(["payload" => $encoded, "raw_data" => $encoded, "content" => $this->blinTransferMoneyText($order["amount"])]);
                }
            } catch (\Exception $e) {}
        } catch (\Exception $e) {}
    }

    private function blinMessageTransferContent($message)
    {
        $content = ["amount" => $this->blinTransferMoneyText(isset($message["content"]) ? $message["content"] : 0), "money_type" => intval(isset($message["money_type"]) ? $message["money_type"] : 0), "status" => "pending"];
        $payload = json_decode(strval(isset($message["im_payload"]) ? $message["im_payload"] : ""), true);
        if (is_array($payload) && isset($payload["content"]) && is_array($payload["content"])) {
            $content = array_merge($content, $payload["content"]);
        }
        try {
            $order = Db::name("im_transfer_order")->where("appid", intval($this->appid))->where("message_id", intval($message["id"]))->find();
            if ($order) {
                $content["amount"] = $this->blinTransferMoneyText($order["amount"]);
                $content["money_type"] = intval($order["money_type"]);
                $content["payment"] = intval($order["money_type"]);
                $content["status"] = $this->blinTransferStatusText($order["status"]);
                $content["transfer_id"] = intval($order["id"]);
                $content["expires_at"] = intval($order["expire_time"]) > 0 ? date("Y-m-d H:i:s", intval($order["expire_time"])) : "";
                $content["expire_time"] = intval($order["expire_time"]);
                if (intval($order["accept_time"]) > 0) {
                    $content["accepted_at"] = date("Y-m-d H:i:s", intval($order["accept_time"]));
                }
                if (intval($order["refund_time"]) > 0) {
                    $content["refunded_at"] = date("Y-m-d H:i:s", intval($order["refund_time"]));
                }
            }
        } catch (\Exception $e) {}
        return $content;
    }

    private function blinExpirePendingTransfers($appid = null)
    {
        $this->blinEnsureTransferTable();
        $appid = $appid === null ? intval($this->appid) : intval($appid);
        $orders = [];
        try {
            $orders = Db::name("im_transfer_order")->where("appid", $appid)->where("status", 0)->where("expire_time", "<=", time())->limit(50)->select();
        } catch (\Exception $e) {
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
                    add_user_bill(["id" => intval($locked["sender_id"]), "appid" => intval($locked["appid"])], 9, "+" . $this->blinTransferMoneyText($refund), "转账24小时未领取，已退回", intval($locked["money_type"]), 0);
                }
                add_user_bill(["id" => intval($locked["receiver_id"]), "appid" => intval($locked["appid"])], 9, "0.00", "转账24小时未领取，系统已退回给对方", intval($locked["money_type"]), 0);
                $now = time();
                Db::name("im_transfer_order")->where("id", intval($locked["id"]))->update(["status" => 2, "refund_time" => $now, "update_time" => $now]);
                $locked["status"] = 2;
                $locked["refund_time"] = $now;
                Db::commit();
                $this->blinUpdateTransferMessagePayload($locked);
            } catch (\Exception $e) {
                try { Db::rollback(); } catch (\Exception $rollbackException) {}
            }
        }
    }

    private function blinSendTransferReceipt($order, $action)
    {
        try {
            $sender = Db::name("user")->where("id", intval($order["sender_id"]))->find();
            $receiver = Db::name("user")->where("id", intval($order["receiver_id"]))->find();
            if (!$sender || !$receiver) {
                return;
            }
            $amount = $this->blinTransferMoneyText($order["amount"]);
            $accepted = $action === "accepted";
            $text = $accepted ? ("已收款 ¥" . $amount) : ("已退回转账 ¥" . $amount);
            $clientNo = "transfer_receipt_" . intval($order["id"]) . "_" . $action . "_" . time();
            $fromUser = $receiver;
            $toUser = $sender;
            $messageId = Db::name("messages")->insertGetId([
                "appid" => intval($this->appid),
                "sender_id" => intval($fromUser["id"]),
                "receiver_id" => intval($toUser["id"]),
                "content" => $text,
                "create_time" => date("Y-m-d H:i:s", time()),
                "message_type" => 0,
                "image_path" => "",
                "pid" => 0,
                "money_type" => intval($order["money_type"]),
                "im_payload" => "",
                "client_msg_no" => $clientNo,
                "file_path" => "",
                "file_name" => "",
            ]);
            $payload = [
                "version" => "1.0",
                "message_id" => intval($messageId),
                "client_msg_no" => $clientNo,
                "conversation_type" => "single",
                "channel_type" => 1,
                "from_uid" => $this->appid . "_" . intval($fromUser["id"]),
                "to_uid" => $this->appid . "_" . intval($toUser["id"]),
                "from_user_id" => intval($fromUser["id"]),
                "to_user_id" => intval($toUser["id"]),
                "msg_type" => "transfer_receipt",
                "message_type" => 0,
                "content" => [
                    "text" => $text,
                    "action" => $action,
                    "transfer_id" => intval($order["id"]),
                    "message_id" => intval($order["message_id"]),
                    "amount" => $amount,
                    "status" => $accepted ? "accepted" : "refunded",
                ],
                "legacy" => ["type" => 0, "content" => $text, "image_path" => "", "sender_id" => intval($fromUser["id"]), "receiver_id" => intval($toUser["id"]), "money_type" => intval($order["money_type"])],
                "create_time" => date("Y-m-d H:i:s", time()),
            ];
            $encoded = json_encode($payload, JSON_UNESCAPED_UNICODE);
            Db::name("messages")->where("id", intval($messageId))->update(["im_payload" => $encoded]);
            try {
                Db::name("im_message_log")->insert(["appid"=>intval($this->appid),"message_id"=>"local_".$messageId,"client_msg_no"=>$clientNo,"message_seq"=>0,"from_uid"=>$payload["from_uid"],"from_user_id"=>intval($fromUser["id"]),"channel_id"=>$payload["to_uid"],"channel_user_id"=>intval($toUser["id"]),"channel_type"=>1,"message_type"=>0,"content"=>$text,"payload"=>$encoded,"raw_data"=>$encoded,"msg_timestamp"=>time(),"status"=>0,"audit_status"=>0,"create_time"=>$payload["create_time"]]);
            } catch (\Exception $e) {}
            try {
                if (config('wukongim.enable')) {
                    $wkim = new \app\common\tool\WukongIM();
                    $wkim->sendPersonMessage($payload["from_uid"], $payload["to_uid"], $payload, $clientNo);
                }
            } catch (\Exception $e) {}
        } catch (\Exception $e) {}
    }

    public function accept_im_transfer()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $this->blinEnsureTransferTable();
        $this->blinExpirePendingTransfers($this->appid);
        $user_all_info = $this->user_info;
        $query = Db::name("im_transfer_order")->where("appid", intval($this->appid))->where("receiver_id", intval($user_all_info["id"]));
        if (isset($data["transfer_id"]) && intval($data["transfer_id"]) > 0) {
            $query = $query->where("id", intval($data["transfer_id"]));
        } elseif (isset($data["message_id"]) && intval($data["message_id"]) > 0) {
            $query = $query->where("message_id", intval($data["message_id"]));
        } elseif (isset($data["client_msg_no"]) && trim(strval($data["client_msg_no"])) !== "") {
            $query = $query->where("client_msg_no", trim(strval($data["client_msg_no"])));
        } else {
            $this->json(0, "缺少转账信息");
        }
        $order = $query->find();
        if (!$order) {
            $this->json(0, "转账不存在");
        }
        if (intval($order["status"]) == 1) {
            $this->json(1, "已收款", $this->blinTransferData($order));
        }
        if (intval($order["status"]) == 2) {
            $this->json(0, "转账已退回");
        }
        if (intval($order["expire_time"]) <= time()) {
            $this->blinExpirePendingTransfers($this->appid);
            $this->json(0, "转账已超过24小时，已退回");
        }
        Db::startTrans();
        try {
            $locked = Db::name("im_transfer_order")->where("id", intval($order["id"]))->lock(true)->find();
            if (!$locked || intval($locked["status"]) !== 0) {
                Db::rollback();
                $this->json(0, "转账状态已变化，请刷新后再试");
            }
            if (intval($locked["expire_time"]) <= time()) {
                Db::rollback();
                $this->blinExpirePendingTransfers($this->appid);
                $this->json(0, "转账已超过24小时，已退回");
            }
            $field = $this->blinTransferBalanceField($locked["money_type"]);
            $receiver = Db::name("user")->where("id", intval($locked["receiver_id"]))->where("appid", intval($this->appid))->lock(true)->find();
            if (!$receiver) {
                throw new \Exception("RECEIVER_NOT_FOUND");
            }
            $fee = floatval($locked["fee"]);
            $credit = floatval($locked["amount"]) - (intval($locked["fee_payer"]) == 0 ? $fee : 0);
            if ($credit < 0) {
                $credit = 0;
            }
            Db::name("user")->where("id", intval($locked["receiver_id"]))->update([$field => floatval($receiver[$field]) + $credit]);
            add_user_bill(["id" => intval($locked["receiver_id"]), "appid" => intval($this->appid)], 9, "+" . $this->blinTransferMoneyText($credit), "收到转账", intval($locked["money_type"]), 0);
            if ($fee > 0 && isset($this->app_info["forum_configuration"]["designated_account"]) && intval($this->app_info["forum_configuration"]["designated_account"]) > 0) {
                $designatedId = intval($this->app_info["forum_configuration"]["designated_account"]);
                $designated = Db::name("user")->where("id", $designatedId)->lock(true)->find();
                if ($designated) {
                    Db::name("user")->where("id", $designatedId)->update([$field => floatval($designated[$field]) + $fee]);
                    add_user_bill(["id" => $designatedId, "appid" => intval($this->appid)], 9, "+" . $this->blinTransferMoneyText($fee), "收到转账手续费", intval($locked["money_type"]), 0);
                }
            }
            $now = time();
            Db::name("im_transfer_order")->where("id", intval($locked["id"]))->update(["status" => 1, "accept_time" => $now, "update_time" => $now]);
            $locked["status"] = 1;
            $locked["accept_time"] = $now;
            Db::commit();
            $this->blinUpdateTransferMessagePayload($locked);
            $this->blinSendTransferReceipt($locked, "accepted");
            $this->json(1, "收款成功", $this->blinTransferData($locked));
        } catch (\Exception $e) {
            try { Db::rollback(); } catch (\Exception $rollbackException) {}
            $this->json(0, "收款失败，请稍后再试");
        }
    }

    public function return_im_transfer()
    {
        $data = input();
        $rule = [
            'usertoken|用户token' => 'require',
        ];
        $validate = new Validate($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $this->blinEnsureTransferTable();
        $this->blinExpirePendingTransfers($this->appid);
        $user_all_info = $this->user_info;
        $query = Db::name("im_transfer_order")->where("appid", intval($this->appid))->where("receiver_id", intval($user_all_info["id"]));
        if (isset($data["transfer_id"]) && intval($data["transfer_id"]) > 0) {
            $query = $query->where("id", intval($data["transfer_id"]));
        } elseif (isset($data["message_id"]) && intval($data["message_id"]) > 0) {
            $query = $query->where("message_id", intval($data["message_id"]));
        } elseif (isset($data["client_msg_no"]) && trim(strval($data["client_msg_no"])) !== "") {
            $query = $query->where("client_msg_no", trim(strval($data["client_msg_no"])));
        } else {
            $this->json(0, "缺少转账信息");
        }
        $order = $query->find();
        if (!$order) {
            $this->json(0, "转账不存在");
        }
        if (intval($order["status"]) == 2) {
            $this->json(1, "已退回", $this->blinTransferData($order));
        }
        if (intval($order["status"]) == 1) {
            $this->json(0, "对方已收款，不能退回");
        }
        Db::startTrans();
        try {
            $locked = Db::name("im_transfer_order")->where("id", intval($order["id"]))->lock(true)->find();
            if (!$locked || intval($locked["status"]) !== 0) {
                Db::rollback();
                $this->json(0, "转账状态已变化，请刷新后再试");
            }
            $field = $this->blinTransferBalanceField($locked["money_type"]);
            $refund = floatval($locked["amount"]) + (intval($locked["fee_payer"]) == 1 ? floatval($locked["fee"]) : 0);
            $sender = Db::name("user")->where("id", intval($locked["sender_id"]))->where("appid", intval($this->appid))->lock(true)->find();
            if (!$sender) {
                throw new \Exception("SENDER_NOT_FOUND");
            }
            Db::name("user")->where("id", intval($locked["sender_id"]))->update([$field => floatval($sender[$field]) + $refund]);
            add_user_bill(["id" => intval($locked["sender_id"]), "appid" => intval($this->appid)], 9, "+" . $this->blinTransferMoneyText($refund), "对方已退回转账", intval($locked["money_type"]), 0);
            add_user_bill(["id" => intval($locked["receiver_id"]), "appid" => intval($this->appid)], 9, "0.00", "已退回对方转账（未入账）", intval($locked["money_type"]), 0);
            $now = time();
            Db::name("im_transfer_order")->where("id", intval($locked["id"]))->update(["status" => 2, "refund_time" => $now, "update_time" => $now]);
            $locked["status"] = 2;
            $locked["refund_time"] = $now;
            Db::commit();
            $this->blinUpdateTransferMessagePayload($locked);
            $this->blinSendTransferReceipt($locked, "returned");
            $this->json(1, "已退回", $this->blinTransferData($locked));
        } catch (\Exception $e) {
            try { Db::rollback(); } catch (\Exception $rollbackException) {}
            $this->json(0, "退回失败，请稍后再试");
        }
    }
    // blin-pending-transfer-end

'''


OLD_TRANSFER_BLOCK = r'''        } elseif ($message_type == 2) {
            $rule = [
                'money|转账金额' => 'require|number',
                'type|转账方式 0金币 1积分' => 'require|number|in:0,1',
            ];
            $validate = new Validate($rule);
            $result = $validate->check($data);
            if (!$result) {
                $this->json(0, $validate->getError());
            }
            $data["money"] = round(floatval($data["money"]), 2);
            if ($data["money"] <= 0) {
                $this->json(0, "转账金额必须大于0");
            }
            //判断不能给自己转账
            if ($data["receiver_id"] == $user_all_info["id"]) {
                $this->json(0, "不能给自己转账");
            }
            //计算手续费
            $transfer_handling_fee = round(floatval($data["money"]) * floatval($this->app_info["forum_configuration"]["transfer_handling_fee"]), 2);
            //判断手续费扣除方式
            $deduction_method_for_handling_fees = $this->app_info["forum_configuration"]["deduction_method_for_handling_fees"];
            //判断金额是否足够并扣除用户余额 并计算最终扣除的金额
            if ($data["type"] == 0) {
                //余额
                if ($deduction_method_for_handling_fees == 1) {
                    if ($user_all_info["money"] < ($data["money"] + $transfer_handling_fee)) {
                        $this->json(0, "金币不足");
                    }
                    //最终扣除的金额
                    $final_deduction_amount = $data["money"] + $transfer_handling_fee;
                } else {
                    if ($user_all_info["money"] < $data["money"]) {
                        $this->json(0, "金币不足");
                    }
                    $final_deduction_amount = $data["money"];
                }
                //扣除转账用户余额 和 手续费
                $user_all_info["money"] = $user_all_info["money"] - $final_deduction_amount;
                Db::name("user")->where("id", $user_all_info["id"])->update(["money" => $user_all_info["money"]]);
                add_user_bill($user_all_info, 9, "-" . $data["money"], "转账给" . $receiver_info["nickname"] . "手续费为：" . $transfer_handling_fee, 0);
                //增加接收用户金币
                //计算接收用户最终增加的金额
                if ($deduction_method_for_handling_fees == 1) {
                    $receiver_info["money"] = $receiver_info["money"] + $data["money"];
                } else {
                    $receiver_info["money"] = $receiver_info["money"] + $data["money"] - $transfer_handling_fee;
                }
                Db::name("user")->where("id", $receiver_info["id"])->update(["money" => $receiver_info["money"]]);
                add_user_bill($receiver_info, 9, "+" . $data["money"], "收到" . $user_all_info["nickname"] . "转账", 0);
                //如果手续费扣除方式为1 则需要把手续费转给指定用户
                if ($this->app_info["forum_configuration"]["designated_account"] != 0) {
                    //查询手续费转给的用户
                    $designated_account_userid = $this->app_info["forum_configuration"]["designated_account"];
                    $designated_account_info = Db::name("user")->where("id", $designated_account_userid)->find();
                    if ($designated_account_info) {
                        $designated_account_info["money"] = $designated_account_info["money"] + $transfer_handling_fee;
                        Db::name("user")->where("id", $designated_account_userid)->update(["money" => $designated_account_info["money"]]);
                        add_user_bill($receiver_info, 9, "+" . $transfer_handling_fee, "收到" . $user_all_info["nickname"] . "的转账手续费", 0);
                    }
                }
            } elseif ($data["type"] == 1) {
                //积分
                if ($deduction_method_for_handling_fees == 1) {
                    if ($user_all_info["integral"] < ($data["money"] + $transfer_handling_fee)) {
                        $this->json(0, "积分不足");
                    }
                    //最终扣除的金额
                    $final_deduction_amount = $data["money"] + $transfer_handling_fee;
                } else {
                    if ($user_all_info["integral"] < $data["money"]) {
                        $this->json(0, "积分不足");
                    }
                    $final_deduction_amount = $data["money"];
                }
                //扣除转账用户积分 和 手续费
                $user_all_info["integral"] = $user_all_info["integral"] - $final_deduction_amount;
                Db::name("user")->where("id", $user_all_info["id"])->update(["integral" => $user_all_info["integral"]]);
                add_user_bill($user_all_info, 9, "-" . $data["money"], "转账给" . $receiver_info["nickname"] . "手续费为：" . $transfer_handling_fee, 1);
                //增加接收用户积分
                //计算接收用户最终增加的金额
                if ($deduction_method_for_handling_fees == 1) {
                    $receiver_info["integral"] = $receiver_info["integral"] + $data["money"];
                } else {
                    $receiver_info["integral"] = $receiver_info["integral"] + $data["money"] - $transfer_handling_fee;
                }
                Db::name("user")->where("id", $receiver_info["id"])->update(["integral" => $receiver_info["integral"]]);
                add_user_bill($receiver_info, 9, "+" . $data["money"], "收到" . $user_all_info["nickname"] . "转账", 1);
                //如果手续费扣除方式为1 则需要把手续费转给指定用户
                if ($this->app_info["forum_configuration"]["designated_account"] != 0) {
                    //查询手续费转给的用户
                    $designated_account_userid = $this->app_info["forum_configuration"]["designated_account"];
                    $designated_account_info = Db::name("user")->where("id", $designated_account_userid)->find();
                    if ($designated_account_info) {
                        $designated_account_info["integral"] = $designated_account_info["integral"] + $transfer_handling_fee;
                        Db::name("user")->where("id", $designated_account_userid)->update(["integral" => $designated_account_info["integral"]]);
                        add_user_bill($receiver_info, 9, "+" . $transfer_handling_fee, "收到" . $user_all_info["nickname"] . "的转账手续费", 1);
                    }
                }
            } else {
                $this->json(0, "转账方式不合法");
            }
            $sql_message_type = 2;
            $content = number_format(floatval($data["money"]), 2, ".", "");
            $money_type = $data["type"];
'''


NEW_TRANSFER_BLOCK = r'''        } elseif ($message_type == 2) {
            $money_raw = isset($data["money"]) ? $data["money"] : (isset($data["amount"]) ? $data["amount"] : input("content"));
            $money_raw = str_replace(",", ".", trim(strval($money_raw)));
            if ($money_raw === "" || !preg_match('/^\d+(\.\d{1,2})?$/', $money_raw)) {
                $this->json(0, "转账金额必须为数字，最多保留两位小数");
            }
            $data["money"] = round(floatval($money_raw), 2);
            $data["type"] = isset($data["type"]) ? intval($data["type"]) : intval(input("payment"));
            if (!in_array($data["type"], [0, 1])) {
                $this->json(0, "转账方式不合法");
            }
            if ($data["money"] <= 0) {
                $this->json(0, "转账金额必须大于0");
            }
            if (intval($data["receiver_id"]) == intval($user_all_info["id"])) {
                $this->json(0, "不能给自己转账");
            }
            $transfer_rate = isset($this->app_info["forum_configuration"]["transfer_handling_fee"]) ? floatval($this->app_info["forum_configuration"]["transfer_handling_fee"]) : 0;
            $transfer_handling_fee = round(floatval($data["money"]) * $transfer_rate, 2);
            $deduction_method_for_handling_fees = isset($this->app_info["forum_configuration"]["deduction_method_for_handling_fees"]) ? intval($this->app_info["forum_configuration"]["deduction_method_for_handling_fees"]) : 0;
            $fee_payer = $deduction_method_for_handling_fees == 1 ? 1 : 0;
            $hold_amount = round(floatval($data["money"]) + ($fee_payer == 1 ? $transfer_handling_fee : 0), 2);
            $transfer_note = trim(strval(isset($data["note"]) ? $data["note"] : input("remark")));
            $transfer_expire_time = time() + 86400;
            $transfer_status = "pending";
            $pending_transfer = [
                "amount" => $data["money"],
                "money_type" => intval($data["type"]),
                "fee" => $transfer_handling_fee,
                "fee_payer" => $fee_payer,
                "hold_amount" => $hold_amount,
                "note" => $transfer_note,
                "expire_time" => $transfer_expire_time,
            ];
            $sql_message_type = 2;
            $content = number_format(floatval($data["money"]), 2, ".", "");
            $money_type = $data["type"];
'''


OLD_INSERT_BLOCK = r'''        try {
            $message_id = Db::name("messages")->insertGetId($add_message);
        } catch (\Exception $e) {
            // blin-private-duplicate-insert-race
            if ($client_msg_no_from_payload !== "") {
                $existing_message = Db::name("messages")
                    ->where("appid", intval($this->appid))
                    ->where("sender_id", intval($user_all_info["id"]))
                    ->where("receiver_id", intval($receiver_info["id"]))
                    ->where("client_msg_no", $client_msg_no_from_payload)
                    ->find();
                if ($existing_message) {
                    $this->json(1, "发送成功", ["message_id" => intval($existing_message["id"]), "duplicate" => 1]);
                }
            }
            $this->json(0, "消息发送失败，请稍后再试");
        }
'''


NEW_INSERT_BLOCK = r'''        if (isset($pending_transfer) && intval($sql_message_type) == 2) {
            $this->blinEnsureTransferTable();
            Db::startTrans();
            try {
                $balance_field = $this->blinTransferBalanceField($pending_transfer["money_type"]);
                $sender_locked = Db::name("user")->where("id", intval($user_all_info["id"]))->where("appid", intval($this->appid))->lock(true)->find();
                if (!$sender_locked) {
                    throw new \Exception("SENDER_NOT_FOUND");
                }
                if (floatval($sender_locked[$balance_field]) < floatval($pending_transfer["hold_amount"])) {
                    Db::rollback();
                    $this->json(0, intval($pending_transfer["money_type"]) == 1 ? "积分不足" : "金币不足");
                }
                $message_id = Db::name("messages")->insertGetId($add_message);
                $transfer_order_id = Db::name("im_transfer_order")->insertGetId([
                    "appid" => intval($this->appid),
                    "message_id" => intval($message_id),
                    "client_msg_no" => $client_msg_no_from_payload !== "" ? $client_msg_no_from_payload : "",
                    "sender_id" => intval($user_all_info["id"]),
                    "receiver_id" => intval($receiver_info["id"]),
                    "amount" => $this->blinTransferMoneyText($pending_transfer["amount"]),
                    "money_type" => intval($pending_transfer["money_type"]),
                    "fee" => $this->blinTransferMoneyText($pending_transfer["fee"]),
                    "fee_payer" => intval($pending_transfer["fee_payer"]),
                    "hold_amount" => $this->blinTransferMoneyText($pending_transfer["hold_amount"]),
                    "note" => strval($pending_transfer["note"]),
                    "status" => 0,
                    "expire_time" => intval($pending_transfer["expire_time"]),
                    "create_time" => time(),
                    "update_time" => time(),
                ]);
                $pending_transfer["id"] = intval($transfer_order_id);
                $pending_transfer["message_id"] = intval($message_id);
                $pending_transfer["status_text"] = "pending";
                $client_payload = $this->blinTransferPayloadJson($client_payload, $message_id, $client_msg_no_from_payload !== "" ? $client_msg_no_from_payload : ("php_msg_" . $message_id . "_" . time()), $user_all_info, $receiver_info, $pending_transfer);
                Db::name("messages")->where("id", intval($message_id))->update(["im_payload" => $client_payload]);
                $add_message["im_payload"] = $client_payload;
                Db::name("user")->where("id", intval($user_all_info["id"]))->update([$balance_field => floatval($sender_locked[$balance_field]) - floatval($pending_transfer["hold_amount"])]);
                $fee_text = floatval($pending_transfer["fee"]) > 0 ? "，手续费" . $this->blinTransferMoneyText($pending_transfer["fee"]) : "";
                add_user_bill(["id" => intval($user_all_info["id"]), "appid" => intval($this->appid)], 9, "-" . $this->blinTransferMoneyText($pending_transfer["hold_amount"]), "转账给" . $receiver_info["nickname"] . "（待对方确认收款" . $fee_text . "）", intval($pending_transfer["money_type"]), 0);
                Db::commit();
            } catch (\Exception $e) {
                try { Db::rollback(); } catch (\Exception $rollbackException) {}
                if ($client_msg_no_from_payload !== "") {
                    $existing_message = Db::name("messages")
                        ->where("appid", intval($this->appid))
                        ->where("sender_id", intval($user_all_info["id"]))
                        ->where("receiver_id", intval($receiver_info["id"]))
                        ->where("client_msg_no", $client_msg_no_from_payload)
                        ->find();
                    if ($existing_message) {
                        $duplicate_data = ["message_id" => intval($existing_message["id"]), "duplicate" => 1];
                        $duplicate_transfer = Db::name("im_transfer_order")->where("appid", intval($this->appid))->where("message_id", intval($existing_message["id"]))->find();
                        if ($duplicate_transfer) {
                            $duplicate_data["transfer"] = $this->blinTransferData($duplicate_transfer);
                        }
                        $this->json(1, "发送成功", $duplicate_data);
                    }
                }
                $this->json(0, "转账发送失败，请稍后再试");
            }
        } else {
            try {
                $message_id = Db::name("messages")->insertGetId($add_message);
            } catch (\Exception $e) {
                // blin-private-duplicate-insert-race
                if ($client_msg_no_from_payload !== "") {
                    $existing_message = Db::name("messages")
                        ->where("appid", intval($this->appid))
                        ->where("sender_id", intval($user_all_info["id"]))
                        ->where("receiver_id", intval($receiver_info["id"]))
                        ->where("client_msg_no", $client_msg_no_from_payload)
                        ->find();
                    if ($existing_message) {
                        $this->json(1, "发送成功", ["message_id" => intval($existing_message["id"]), "duplicate" => 1]);
                    }
                }
                $this->json(0, "消息发送失败，请稍后再试");
            }
        }
'''


def patch_source(source: str) -> str:
    if "blin-pending-transfer-start" not in source:
        marker = "\n    //发送消息\n"
        if marker not in source:
            raise SystemExit("SEND_MESSAGE_MARKER_NOT_FOUND")
        source = source.replace(marker, "\n" + HELPER_BLOCK + marker, 1)

    source = source.replace(
        'if (!in_array($data["transaction_type"], [0, 1, 2, 3, 4, 5, 6, 7, 8])) {',
        'if (!in_array($data["transaction_type"], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14])) {',
    )

    expire_sender_bill = '                    add_user_bill(["id" => intval($locked["sender_id"]), "appid" => intval($locked["appid"])], 9, "+" . $this->blinTransferMoneyText($refund), "转账24小时未领取，已退回", intval($locked["money_type"]), 0);\n'
    expire_receiver_bill = '                    add_user_bill(["id" => intval($locked["receiver_id"]), "appid" => intval($locked["appid"])], 9, "0.00", "转账24小时未领取，系统已退回给对方", intval($locked["money_type"]), 0);\n'
    if expire_receiver_bill not in source and expire_sender_bill in source:
        source = source.replace(
            expire_sender_bill,
            expire_sender_bill + expire_receiver_bill,
            1,
        )

    return_sender_bill = '            add_user_bill(["id" => intval($locked["sender_id"]), "appid" => intval($this->appid)], 9, "+" . $this->blinTransferMoneyText($refund), "对方已退回转账", intval($locked["money_type"]), 0);\n'
    return_receiver_bill = '            add_user_bill(["id" => intval($locked["receiver_id"]), "appid" => intval($this->appid)], 9, "0.00", "已退回对方转账（未入账）", intval($locked["money_type"]), 0);\n'
    if return_receiver_bill not in source and return_sender_bill in source:
        source = source.replace(
            return_sender_bill,
            return_sender_bill + return_receiver_bill,
            1,
        )

    if OLD_TRANSFER_BLOCK in source:
        source = source.replace(OLD_TRANSFER_BLOCK, NEW_TRANSFER_BLOCK, 1)
    elif "转账金额必须为数字，最多保留两位小数" not in source:
        raise SystemExit("TRANSFER_BLOCK_NOT_FOUND")

    if OLD_INSERT_BLOCK in source:
        source = source.replace(OLD_INSERT_BLOCK, NEW_INSERT_BLOCK, 1)
    elif "isset($pending_transfer) && intval($sql_message_type) == 2" not in source:
        raise SystemExit("MESSAGE_INSERT_BLOCK_NOT_FOUND")

    duplicate_block = '''            if ($existing_message) {
                $this->json(1, "发送成功", ["message_id" => intval($existing_message["id"]), "duplicate" => 1]);
            }
'''
    duplicate_with_transfer = '''            if ($existing_message) {
                $duplicate_data = ["message_id" => intval($existing_message["id"]), "duplicate" => 1];
                $duplicate_transfer = Db::name("im_transfer_order")->where("appid", intval($this->appid))->where("message_id", intval($existing_message["id"]))->find();
                if ($duplicate_transfer) {
                    $duplicate_data["transfer"] = $this->blinTransferData($duplicate_transfer);
                }
                $this->json(1, "发送成功", $duplicate_data);
            }
'''
    source = source.replace(duplicate_block, duplicate_with_transfer)

    source = source.replace(
        '$im_content = ["amount" => strval($content), "money_type" => intval($money_type), "status" => "success"];',
        '$im_content = array_merge($im_content, ["amount" => strval($content), "money_type" => intval($money_type), "status" => isset($transfer_status) ? $transfer_status : (isset($im_content["status"]) ? strval($im_content["status"]) : "pending")]);\n                if (isset($transfer_order_id)) { $im_content["transfer_id"] = intval($transfer_order_id); }\n                if (isset($transfer_expire_time)) { $im_content["expires_at"] = date("Y-m-d H:i:s", intval($transfer_expire_time)); $im_content["expire_time"] = intval($transfer_expire_time); }',
    )
    source = source.replace(
        '$im_content = ["amount" => strval($value["content"]), "money_type" => intval($value["money_type"]), "status" => "success"];',
        '$im_content = $this->blinMessageTransferContent($value);',
    )

    source = source.replace(
        '$user_info = $this->user_info;\n        $where = "userid = {$user_info[\'id\']} and appid = {$this->appid}";',
        '$this->blinExpirePendingTransfers($this->appid);\n        $user_info = $this->user_info;\n        $where = "userid = {$user_info[\'id\']} and appid = {$this->appid}";',
        1,
    )
    source = source.replace(
        '''        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $user_all_info = $this->user_info;
        $receiver_info = Db::name("user")->where("id", $data["receiver_id"])->where("appid", $this->appid)->find();
''',
        '''        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $this->blinExpirePendingTransfers($this->appid);
        $user_all_info = $this->user_info;
        $receiver_info = Db::name("user")->where("id", $data["receiver_id"])->where("appid", $this->appid)->find();
''',
        1,
    )
    source = source.replace(
        '''    public function get_message_list()
    {
        $data = input();
''',
        '''    public function get_message_list()
    {
        $this->blinExpirePendingTransfers($this->appid);
        $data = input();
''',
        1,
    )
    source = source.replace(
        '''    public function get_chat_log()
    {
        $data = input();
''',
        '''    public function get_chat_log()
    {
        $this->blinExpirePendingTransfers($this->appid);
        $data = input();
''',
        1,
    )

    source = source.replace(
        '$this->json(1, "发送成功", ["message_id" => $message_id, "im_log_error" => $im_log_error]);',
        '$response_data = ["message_id" => $message_id, "im_log_error" => $im_log_error];\n        if (isset($transfer_order_id)) {\n            $transfer_order = Db::name("im_transfer_order")->where("id", intval($transfer_order_id))->find();\n            if ($transfer_order) { $response_data["transfer"] = $this->blinTransferData($transfer_order); }\n        }\n        $this->json(1, "发送成功", $response_data);',
    )

    return source


def main() -> None:
    source = API.read_text(errors="ignore")
    patched = patch_source(source)
    if patched == source:
        print("PENDING_TRANSFER_ALREADY_UP_TO_DATE")
        return
    print("PATCH_API_BACKUP", backup(API))
    API.write_text(patched)
    print("PATCHED_PENDING_TRANSFER")


if __name__ == "__main__":
    main()
