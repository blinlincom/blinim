from pathlib import Path
import shutil
import time


ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"
TRAIT = ROOT / "application/api/controller/traits/ImApiTrait.php"
ADMIN = ROOT / "application/admin/controller/Im.php"
VIEW_DIR = ROOT / "application/admin/view/im"


def backup(path: Path) -> None:
    if path.exists():
        shutil.copy2(path, path.with_suffix(path.suffix + f".bak_group_transfer_{time.strftime('%Y%m%d%H%M%S')}"))


def write_if_changed(path: Path, text: str) -> None:
    old = path.read_text(encoding="utf-8")
    if old != text:
        backup(path)
        path.write_text(text, encoding="utf-8")


def insert_before(text: str, needle: str, payload: str) -> str:
    if payload.strip() in text:
        return text
    idx = text.find(needle)
    if idx < 0:
        raise RuntimeError(f"needle not found: {needle[:80]}")
    return text[:idx] + payload + "\n" + text[idx:]


def insert_after(text: str, needle: str, payload: str) -> str:
    if payload.strip() in text:
        return text
    idx = text.find(needle)
    if idx < 0:
        raise RuntimeError(f"needle not found: {needle[:80]}")
    idx += len(needle)
    return text[:idx] + "\n" + payload + text[idx:]


def patch_api() -> None:
    text = API.read_text(encoding="utf-8")

    add_column_helper = r'''
    private function blinTransferAddColumnIfMissing($table, $column, $sql)
    {
        try {
            $row = Db::query("SHOW COLUMNS FROM `" . $table . "` LIKE '" . $column . "'");
            if (!$row) Db::execute($sql);
        } catch (\Exception $e) {}
    }

'''
    if "private function blinTransferAddColumnIfMissing" not in text:
        text = insert_before(text, "    private function blinEnsureTransferTable()", add_column_helper)

    old = '''    private function blinEnsureTransferTable()
    {
        try {
            Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_transfer_order` (`id` bigint(20) NOT NULL AUTO_INCREMENT, `appid` bigint(20) NOT NULL DEFAULT 0, `message_id` bigint(20) NOT NULL DEFAULT 0, `client_msg_no` varchar(128) NOT NULL DEFAULT '', `sender_id` bigint(20) NOT NULL DEFAULT 0, `receiver_id` bigint(20) NOT NULL DEFAULT 0, `amount` decimal(16,2) NOT NULL DEFAULT '0.00', `money_type` tinyint(1) NOT NULL DEFAULT 0, `fee` decimal(16,2) NOT NULL DEFAULT '0.00', `fee_payer` tinyint(1) NOT NULL DEFAULT 0 COMMENT '0 receiver, 1 sender', `hold_amount` decimal(16,2) NOT NULL DEFAULT '0.00', `note` varchar(255) NOT NULL DEFAULT '', `status` tinyint(1) NOT NULL DEFAULT 0 COMMENT '0 pending, 1 accepted, 2 refunded', `expire_time` int(11) NOT NULL DEFAULT 0, `accept_time` int(11) NOT NULL DEFAULT 0, `refund_time` int(11) NOT NULL DEFAULT 0, `create_time` int(11) NOT NULL DEFAULT 0, `update_time` int(11) NOT NULL DEFAULT 0, PRIMARY KEY (`id`), KEY `idx_app_msg` (`appid`,`message_id`), KEY `idx_client_no` (`appid`,`client_msg_no`), KEY `idx_receiver` (`appid`,`receiver_id`,`status`), KEY `idx_sender` (`appid`,`sender_id`,`status`), KEY `idx_expire` (`appid`,`status`,`expire_time`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
        } catch (\\Exception $e) {}
    }
'''
    new = '''    private function blinEnsureTransferTable()
    {
        try {
            Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_transfer_order` (`id` bigint(20) NOT NULL AUTO_INCREMENT, `appid` bigint(20) NOT NULL DEFAULT 0, `message_id` bigint(20) NOT NULL DEFAULT 0, `client_msg_no` varchar(128) NOT NULL DEFAULT '', `sender_id` bigint(20) NOT NULL DEFAULT 0, `receiver_id` bigint(20) NOT NULL DEFAULT 0, `amount` decimal(16,2) NOT NULL DEFAULT '0.00', `money_type` tinyint(1) NOT NULL DEFAULT 0, `fee` decimal(16,2) NOT NULL DEFAULT '0.00', `fee_payer` tinyint(1) NOT NULL DEFAULT 0 COMMENT '0 receiver, 1 sender', `hold_amount` decimal(16,2) NOT NULL DEFAULT '0.00', `note` varchar(255) NOT NULL DEFAULT '', `status` tinyint(1) NOT NULL DEFAULT 0 COMMENT '0 pending, 1 accepted, 2 refunded', `expire_time` int(11) NOT NULL DEFAULT 0, `accept_time` int(11) NOT NULL DEFAULT 0, `refund_time` int(11) NOT NULL DEFAULT 0, `create_time` int(11) NOT NULL DEFAULT 0, `update_time` int(11) NOT NULL DEFAULT 0, PRIMARY KEY (`id`), KEY `idx_app_msg` (`appid`,`message_id`), KEY `idx_client_no` (`appid`,`client_msg_no`), KEY `idx_receiver` (`appid`,`receiver_id`,`status`), KEY `idx_sender` (`appid`,`sender_id`,`status`), KEY `idx_expire` (`appid`,`status`,`expire_time`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
        } catch (\\Exception $e) {}
        // blin-group-transfer-columns
        $this->blinTransferAddColumnIfMissing("mr_im_transfer_order", "group_message_id", "ALTER TABLE `mr_im_transfer_order` ADD COLUMN `group_message_id` bigint(20) NOT NULL DEFAULT 0 AFTER `message_id`");
        $this->blinTransferAddColumnIfMissing("mr_im_transfer_order", "channel_type", "ALTER TABLE `mr_im_transfer_order` ADD COLUMN `channel_type` tinyint(1) NOT NULL DEFAULT 1 COMMENT '1 single, 2 group' AFTER `client_msg_no`");
        $this->blinTransferAddColumnIfMissing("mr_im_transfer_order", "group_id", "ALTER TABLE `mr_im_transfer_order` ADD COLUMN `group_id` bigint(20) NOT NULL DEFAULT 0 AFTER `receiver_id`");
        try { Db::execute("ALTER TABLE `mr_im_transfer_order` ADD KEY `idx_group_msg` (`appid`,`group_message_id`)"); } catch (\\Exception $e) {}
        try { Db::execute("ALTER TABLE `mr_im_transfer_order` ADD KEY `idx_channel_group` (`appid`,`channel_type`,`group_id`,`status`)"); } catch (\\Exception $e) {}
    }
'''
    if old in text:
        text = text.replace(old, new)
    elif "blin-group-transfer-columns" not in text:
        raise RuntimeError("blinEnsureTransferTable block not found")
    text = text.replace("$this->blinAddColumnIfMissing(\"mr_im_transfer_order\"", "$this->blinTransferAddColumnIfMissing(\"mr_im_transfer_order\"")

    old = '''    private function blinTransferData($order)
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
'''
    new = '''    private function blinTransferData($order)
    {
        if (!$order) {
            return [];
        }
        $channelType = intval(isset($order["channel_type"]) ? $order["channel_type"] : 1);
        $groupMessageId = intval(isset($order["group_message_id"]) ? $order["group_message_id"] : 0);
        $messageId = intval($channelType == 2 && $groupMessageId > 0 ? $groupMessageId : $order["message_id"]);
        return [
            "transfer_id" => intval($order["id"]),
            "message_id" => $messageId,
            "private_message_id" => intval($order["message_id"]),
            "group_message_id" => $groupMessageId,
            "client_msg_no" => strval($order["client_msg_no"]),
            "sender_id" => intval($order["sender_id"]),
            "receiver_id" => intval($order["receiver_id"]),
            "target_user_id" => intval($order["receiver_id"]),
            "group_id" => intval(isset($order["group_id"]) ? $order["group_id"] : 0),
            "channel_type" => $channelType,
            "scope" => $channelType == 2 ? "group" : "single",
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
'''
    if old in text:
        text = text.replace(old, new)

    marker = "    // blin-group-transfer-helper-start"
    helper = r'''
    // blin-group-transfer-helper-start
    private function blinGroupTransferPayloadJson($clientPayload, $messageId, $clientNo, $senderInfo, $receiverInfo, $groupInfo, $transfer)
    {
        $payload = json_decode(strval($clientPayload), true);
        if (!is_array($payload)) {
            $payload = [];
        }
        $content = isset($payload["content"]) && is_array($payload["content"]) ? $payload["content"] : [];
        $receiverName = isset($receiverInfo["nickname"]) && trim(strval($receiverInfo["nickname"])) !== "" ? strval($receiverInfo["nickname"]) : (isset($receiverInfo["username"]) ? strval($receiverInfo["username"]) : ("用户" . intval($receiverInfo["id"])));
        $receiverAvatar = isset($receiverInfo["usertx"]) ? strval($receiverInfo["usertx"]) : (isset($receiverInfo["avatar"]) ? strval($receiverInfo["avatar"]) : "");
        $senderName = isset($senderInfo["nickname"]) && trim(strval($senderInfo["nickname"])) !== "" ? strval($senderInfo["nickname"]) : (isset($senderInfo["username"]) ? strval($senderInfo["username"]) : ("用户" . intval($senderInfo["id"])));
        $senderAvatar = isset($senderInfo["usertx"]) ? strval($senderInfo["usertx"]) : (isset($senderInfo["avatar"]) ? strval($senderInfo["avatar"]) : "");
        $content["amount"] = $this->blinTransferMoneyText($transfer["amount"]);
        $content["money_type"] = intval($transfer["money_type"]);
        $content["payment"] = intval($transfer["money_type"]);
        $content["type"] = intval($transfer["money_type"]);
        $content["status"] = isset($transfer["status_text"]) ? strval($transfer["status_text"]) : "pending";
        $content["transfer_id"] = intval($transfer["id"]);
        $content["message_id"] = intval($messageId);
        $content["group_message_id"] = intval($messageId);
        $content["group_id"] = intval($groupInfo["id"]);
        $content["channel_type"] = 2;
        $content["scope"] = "group";
        $content["receiver_id"] = intval($receiverInfo["id"]);
        $content["target_user_id"] = intval($receiverInfo["id"]);
        $content["target_nickname"] = $receiverName;
        $content["target_avatar"] = $receiverAvatar;
        $content["text"] = "[转账] ¥" . $content["amount"] . " 给 " . $receiverName;
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
        $payload["conversation_type"] = "group";
        $payload["channel_type"] = 2;
        $payload["from_uid"] = $this->appid . "_" . intval($senderInfo["id"]);
        $payload["to_uid"] = strval($groupInfo["group_no"]);
        $payload["from_user_id"] = intval($senderInfo["id"]);
        $payload["to_user_id"] = intval($groupInfo["id"]);
        $payload["group_id"] = intval($groupInfo["id"]);
        $payload["group_no"] = strval($groupInfo["group_no"]);
        $payload["msg_type"] = "transfer";
        $payload["message_type"] = 2;
        $payload["content"] = $content;
        $payload["nickname"] = $senderName;
        $payload["avatar"] = $senderAvatar;
        $payload["fromUser"] = ["id"=>intval($senderInfo["id"]), "username"=>isset($senderInfo["username"]) ? strval($senderInfo["username"]) : "", "nickname"=>$senderName, "usertx"=>$senderAvatar, "avatar"=>$senderAvatar];
        $payload["legacy"] = ["type" => 2, "content" => $content["amount"], "image_path" => "", "sender_id" => intval($senderInfo["id"]), "receiver_id" => intval($groupInfo["id"]), "money_type" => intval($transfer["money_type"])];
        $payload["create_time"] = isset($payload["create_time"]) && strval($payload["create_time"]) !== "" ? $payload["create_time"] : date("Y-m-d H:i:s", time());
        return json_encode($payload, JSON_UNESCAPED_UNICODE);
    }
    // blin-group-transfer-helper-end

'''
    if marker not in text:
        text = insert_before(text, "    private function blinUpdateTransferMessagePayload($order)", helper)

    old = '''    private function blinUpdateTransferMessagePayload($order)
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
            } catch (\\Exception $e) {}
        } catch (\\Exception $e) {}
    }
'''
    new = '''    private function blinUpdateTransferMessagePayload($order)
    {
        try {
            $channelType = intval(isset($order["channel_type"]) ? $order["channel_type"] : 1);
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
            if ($channelType == 2) {
                $messageId = intval(isset($order["group_message_id"]) ? $order["group_message_id"] : 0);
                if ($messageId <= 0) {
                    return;
                }
                $message = Db::name("im_group_messages")->where("id", $messageId)->find();
                if (!$message) {
                    return;
                }
                $group = Db::name("im_groups")->where("id", intval(isset($order["group_id"]) ? $order["group_id"] : 0))->find();
                if (!$group) {
                    $group = ["id" => intval(isset($order["group_id"]) ? $order["group_id"] : 0), "group_no" => ""];
                }
                $payloadJson = $this->blinGroupTransferPayloadJson($message["payload"], $messageId, isset($message["client_msg_no"]) ? $message["client_msg_no"] : $order["client_msg_no"], $sender, $receiver, $group, $transfer);
                Db::name("im_group_messages")->where("id", $messageId)->update(["payload" => $payloadJson, "content" => $this->blinTransferMoneyText($order["amount"])]);
                return;
            }
            $messageId = intval($order["message_id"]);
            if ($messageId <= 0) {
                return;
            }
            $message = Db::name("messages")->where("id", $messageId)->find();
            if (!$message) {
                return;
            }
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
            } catch (\\Exception $e) {}
        } catch (\\Exception $e) {}
    }
'''
    if old in text:
        text = text.replace(old, new)

    old_q = '''        } elseif (isset($data["message_id"]) && intval($data["message_id"]) > 0) {
            $query = $query->where("message_id", intval($data["message_id"]));
'''
    new_q = '''        } elseif (isset($data["message_id"]) && intval($data["message_id"]) > 0) {
            $messageIdInput = intval($data["message_id"]);
            $query = $query->where(function($q) use ($messageIdInput) {
                $q->where("message_id", $messageIdInput)->whereOr("group_message_id", $messageIdInput);
            });
'''
    text = text.replace(old_q, new_q)

    endpoint_marker = "    // blin-group-transfer-endpoint-start"
    endpoint = r'''
    // blin-group-transfer-endpoint-start
    private function blinGroupTransferDuplicateData($order, $viewerId = 0)
    {
        if (!$order) return [];
        $this->blinUpdateTransferMessagePayload($order);
        $payload = [];
        if (intval(isset($order["group_message_id"]) ? $order["group_message_id"] : 0) > 0) {
            $message = Db::name("im_group_messages")->where("id", intval($order["group_message_id"]))->find();
            if ($message && isset($message["payload"])) {
                $decoded = json_decode(strval($message["payload"]), true);
                if (is_array($decoded)) $payload = $decoded;
            }
        }
        return [
            "message_id" => intval(isset($order["group_message_id"]) ? $order["group_message_id"] : 0),
            "payload" => $payload,
            "transfer" => $this->blinTransferData($order),
            "duplicate" => 1,
        ];
    }

    public function send_im_group_transfer()
    {
        $data = input();
        $rule = ["usertoken|用户token" => "require", "group_id|群ID" => "require|number"];
        $validate = new Validate($rule);
        if (!$validate->check($data)) $this->json(0, $validate->getError());
        if (!$this->blinMoneyFeatureOpen("transfer_switch")) $this->json(0, "转账功能已关闭");
        $this->blinEnsureTransferTable();
        $this->blinExpirePendingTransfers($this->appid);
        $sender = $this->im_group_user();
        $this->ensure_im_group_tables();
        $groupId = intval($data["group_id"]);
        $senderMember = $this->im_group_member($groupId, intval($sender["id"]));
        if (!$senderMember) $this->json(0, "你不在该群聊中");
        $group = Db::name("im_groups")->where("appid", intval($this->appid))->where("id", $groupId)->where("status", 1)->find();
        if (!$group) $this->json(0, "群聊不存在");
        if (intval($group["mute_all"]) === 1 && intval($senderMember["role"]) < 1) $this->json(0, "当前群聊已全员禁言");
        $receiverId = intval(isset($data["receiver_id"]) ? $data["receiver_id"] : (isset($data["target_user_id"]) ? $data["target_user_id"] : input("member_id")));
        if ($receiverId <= 0) $this->json(0, "请选择收款人");
        if ($receiverId == intval($sender["id"])) $this->json(0, "不能给自己转账");
        $receiverMember = $this->im_group_member($groupId, $receiverId);
        if (!$receiverMember) $this->json(0, "收款人不在该群聊中");
        $receiver = Db::name("user")->where("appid", intval($this->appid))->where("id", $receiverId)->find();
        if (!$receiver) $this->json(0, "收款用户不存在");
        $moneyRaw = isset($data["money"]) ? $data["money"] : (isset($data["amount"]) ? $data["amount"] : input("content"));
        $moneyRaw = str_replace(",", ".", trim(strval($moneyRaw)));
        if ($moneyRaw === "" || !preg_match('/^\d+(\.\d{1,2})?$/', $moneyRaw)) {
            $this->json(0, "转账金额必须为数字，最多保留两位小数");
        }
        $amount = $this->blinTransferMoneyText(round(floatval($moneyRaw), 2));
        if (floatval($amount) <= 0) $this->json(0, "转账金额必须大于0");
        $moneyType = isset($data["money_type"]) ? intval($data["money_type"]) : intval(input("payment"));
        if (!in_array($moneyType, [0, 1])) $this->json(0, "转账方式不合法");
        $transferRate = isset($this->app_info["forum_configuration"]["transfer_handling_fee"]) ? floatval($this->app_info["forum_configuration"]["transfer_handling_fee"]) : 0;
        $fee = $this->blinTransferMoneyText(round(floatval($amount) * $transferRate, 2));
        $feePayer = isset($this->app_info["forum_configuration"]["deduction_method_for_handling_fees"]) && intval($this->app_info["forum_configuration"]["deduction_method_for_handling_fees"]) == 1 ? 1 : 0;
        $holdAmount = $this->blinTransferMoneyText(floatval($amount) + ($feePayer == 1 ? floatval($fee) : 0));
        $note = trim(strval(isset($data["note"]) ? $data["note"] : input("remark")));
        if (function_exists("mb_substr")) $note = mb_substr($note, 0, 80, "UTF-8"); else $note = substr($note, 0, 240);
        $rawPayload = input("im_payload") ?: input("payload");
        $payloadData = $rawPayload ? json_decode(strval($rawPayload), true) : [];
        if (!is_array($payloadData)) $payloadData = [];
        $clientNo = $this->blinClientMsgNo(isset($payloadData["client_msg_no"]) ? strval($payloadData["client_msg_no"]) : (isset($data["client_msg_no"]) ? strval($data["client_msg_no"]) : ""));
        if ($clientNo === "") $clientNo = "group_transfer_" . $groupId . "_" . intval($sender["id"]) . "_" . $receiverId . "_" . time() . "_" . mt_rand(1000,9999);
        $existing = Db::name("im_transfer_order")->where("appid", intval($this->appid))->where("channel_type", 2)->where("sender_id", intval($sender["id"]))->where("group_id", $groupId)->where("client_msg_no", $clientNo)->find();
        if ($existing) $this->json(1, "发送成功", $this->blinGroupTransferDuplicateData($existing, intval($sender["id"])));
        Db::startTrans();
        try {
            $field = $this->blinTransferBalanceField($moneyType);
            $lockedSender = Db::name("user")->where("appid", intval($this->appid))->where("id", intval($sender["id"]))->lock(true)->find();
            if (!$lockedSender) throw new \Exception("SENDER_NOT_FOUND");
            if (floatval($lockedSender[$field]) < floatval($holdAmount)) {
                Db::rollback();
                $this->json(0, $moneyType == 1 ? "积分不足" : "金币不足");
            }
            $now = time();
            $messageId = Db::name("im_group_messages")->insertGetId(["appid"=>intval($this->appid), "group_id"=>$groupId, "sender_id"=>intval($sender["id"]), "message_type"=>2, "content"=>$amount, "payload"=>"", "client_msg_no"=>$clientNo, "create_time"=>date("Y-m-d H:i:s", $now)]);
            $orderId = Db::name("im_transfer_order")->insertGetId([
                "appid"=>intval($this->appid),
                "message_id"=>0,
                "group_message_id"=>intval($messageId),
                "client_msg_no"=>$clientNo,
                "channel_type"=>2,
                "sender_id"=>intval($sender["id"]),
                "receiver_id"=>$receiverId,
                "group_id"=>$groupId,
                "amount"=>$amount,
                "money_type"=>$moneyType,
                "fee"=>$fee,
                "fee_payer"=>$feePayer,
                "hold_amount"=>$holdAmount,
                "note"=>$note,
                "status"=>0,
                "expire_time"=>$now + 86400,
                "create_time"=>$now,
                "update_time"=>$now,
            ]);
            Db::name("user")->where("id", intval($sender["id"]))->update([$field => floatval($lockedSender[$field]) - floatval($holdAmount)]);
            $receiverName = isset($receiver["nickname"]) && trim(strval($receiver["nickname"])) !== "" ? strval($receiver["nickname"]) : strval($receiver["username"]);
            $feeText = floatval($fee) > 0 ? "，手续费" . $fee : "";
            add_user_bill(["id"=>intval($sender["id"]), "appid"=>intval($this->appid)], 9, "-" . $holdAmount, "在群聊「" . strval($group["name"]) . "」转账给" . $receiverName . "（待对方确认收款" . $feeText . "）", $moneyType, 0);
            $order = Db::name("im_transfer_order")->where("id", intval($orderId))->find();
            $transfer = ["id"=>intval($orderId), "amount"=>$amount, "money_type"=>$moneyType, "note"=>$note, "expire_time"=>$now + 86400, "status_text"=>"pending"];
            $payloadJson = $this->blinGroupTransferPayloadJson($rawPayload, $messageId, $clientNo, $sender, $receiver, $group, $transfer);
            $payload = json_decode($payloadJson, true);
            if (!is_array($payload)) $payload = [];
            Db::name("im_group_messages")->where("id", intval($messageId))->update(["payload"=>$payloadJson]);
            Db::name("im_groups")->where("id", $groupId)->update(["update_time"=>date("Y-m-d H:i:s", $now)]);
            Db::commit();
            try {
                if (config("wukongim.enable")) {
                    $wkim = new \app\common\tool\WukongIM();
                    $wkim->sendMessage($payload["from_uid"], $payload["to_uid"], 2, $payload, $clientNo, ["no_persist"=>0,"red_dot"=>1,"sync_once"=>0]);
                }
            } catch (\Exception $e) {}
            $this->json(1, "发送成功", ["message_id"=>intval($messageId), "payload"=>$payload, "transfer"=>$this->blinTransferData($order)]);
        } catch (\Exception $e) {
            try { Db::rollback(); } catch (\Exception $rollbackException) {}
            $existing = Db::name("im_transfer_order")->where("appid", intval($this->appid))->where("channel_type", 2)->where("sender_id", intval($sender["id"]))->where("group_id", $groupId)->where("client_msg_no", $clientNo)->find();
            if ($existing) $this->json(1, "发送成功", $this->blinGroupTransferDuplicateData($existing, intval($sender["id"])));
            $this->json(0, "群转账发送失败，请稍后再试");
        }
    }

    public function send_group_transfer(){ return $this->send_im_group_transfer(); }
    // blin-group-transfer-endpoint-end

'''
    if endpoint_marker not in text:
        text = insert_before(text, "    public function send_group_red_packet(){ return $this->send_im_group_red_packet(); }", endpoint)

    write_if_changed(API, text)


def patch_trait() -> None:
    text = TRAIT.read_text(encoding="utf-8")

    old = '''        if ($raw === 'video') return 3;
        if ($raw === 'file') return 4;
'''
    new = '''        if ($raw === 'video') return 3;
        if ($raw === 'file') return 4;
        if ($raw === 'transfer') return 2;
'''
    text = text.replace(old, new)

    old_guard = '''        if (trim($rawMsgType) === 'red_packet' || preg_match('/"msg_type"\\\\s*:\\\\s*"red_packet"/', strval($payloadRaw))) {
            $this->json(0, '群普通消息接口不能发送红包，请使用群红包接口');
        }
'''
    new_guard = '''        if (in_array(trim($rawMsgType), ['red_packet', 'transfer'], true) || preg_match('/"msg_type"\\\\s*:\\\\s*"(red_packet|transfer)"/', strval($payloadRaw)) || intval(isset($data['message_type']) ? $data['message_type'] : 0) === 2) {
            $this->json(0, '群普通消息接口不能发送红包或转账，请使用专用接口');
        }
'''
    text = text.replace(old_guard, new_guard)

    helper_marker = "    // blin-group-transfer-trait-history"
    helper = r'''
    // blin-group-transfer-trait-history
    private function blinTraitTransferMoneyText($value)
    {
        return number_format(floatval($value), 2, ".", "");
    }

    private function blinTraitTransferStatusText($status)
    {
        $status = intval($status);
        if ($status == 1) return "accepted";
        if ($status == 2) return "refunded";
        return "pending";
    }

    private function blinTraitGroupTransferContent($message)
    {
        $payload = json_decode(strval(isset($message['payload']) ? $message['payload'] : ''), true);
        $content = is_array($payload) && isset($payload['content']) && is_array($payload['content']) ? $payload['content'] : [];
        try {
            $order = Db::name('im_transfer_order')
                ->where('appid', intval($this->appid))
                ->where('group_message_id', intval($message['id']))
                ->find();
            if (!$order) return $content;
            $receiver = Db::name('user')->where('appid', intval($this->appid))->where('id', intval($order['receiver_id']))->field('id,username,nickname,usertx')->find();
            $targetName = $receiver ? (trim(strval($receiver['nickname'])) !== '' ? strval($receiver['nickname']) : strval($receiver['username'])) : ('用户' . intval($order['receiver_id']));
            $targetAvatar = $receiver && isset($receiver['usertx']) ? strval($receiver['usertx']) : '';
            return array_merge($content, [
                'transfer_id' => intval($order['id']),
                'message_id' => intval($order['group_message_id']),
                'private_message_id' => intval($order['message_id']),
                'group_message_id' => intval($order['group_message_id']),
                'client_msg_no' => strval($order['client_msg_no']),
                'sender_id' => intval($order['sender_id']),
                'receiver_id' => intval($order['receiver_id']),
                'target_user_id' => intval($order['receiver_id']),
                'target_nickname' => $targetName,
                'target_avatar' => $targetAvatar,
                'group_id' => intval($order['group_id']),
                'channel_type' => 2,
                'scope' => 'group',
                'amount' => $this->blinTraitTransferMoneyText($order['amount']),
                'money_type' => intval($order['money_type']),
                'payment' => intval($order['money_type']),
                'status' => $this->blinTraitTransferStatusText($order['status']),
                'expires_at' => intval($order['expire_time']) > 0 ? date('Y-m-d H:i:s', intval($order['expire_time'])) : '',
                'expire_time' => intval($order['expire_time']),
                'accepted_at' => intval($order['accept_time']) > 0 ? date('Y-m-d H:i:s', intval($order['accept_time'])) : '',
                'refunded_at' => intval($order['refund_time']) > 0 ? date('Y-m-d H:i:s', intval($order['refund_time'])) : '',
                'text' => '[转账] ¥' . $this->blinTraitTransferMoneyText($order['amount']) . ' 给 ' . $targetName,
            ]);
        } catch (\Exception $e) {}
        return $content;
    }

'''
    if helper_marker not in text:
        text = insert_before(text, "    public function send_im_group_message()", helper)

    old_history = '''                    if (isset($decoded['msg_type']) && strval($decoded['msg_type']) === 'red_packet') {
                        $decoded['content'] = array_merge($this->blinTraitRedPacketContent($r, intval($user['id'])), ['nickname'=>$senderName, 'avatar'=>$senderAvatar]);
                    }
'''
    new_history = '''                    if (isset($decoded['msg_type']) && strval($decoded['msg_type']) === 'red_packet') {
                        $decoded['content'] = array_merge($this->blinTraitRedPacketContent($r, intval($user['id'])), ['nickname'=>$senderName, 'avatar'=>$senderAvatar]);
                    }
                    if (isset($decoded['msg_type']) && strval($decoded['msg_type']) === 'transfer') {
                        $decoded['content'] = array_merge($this->blinTraitGroupTransferContent($r), ['nickname'=>$senderName, 'avatar'=>$senderAvatar]);
                    }
'''
    text = text.replace(old_history, new_history)

    write_if_changed(TRAIT, text)


def patch_admin() -> None:
    text = ADMIN.read_text(encoding="utf-8")
    marker = "    // blin-money-records-start"
    methods = r'''
    // blin-money-records-start
    public function transfer_records()
    {
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
                    $q->where('t.client_msg_no','like','%'.$keyword.'%')
                      ->whereOr('t.sender_id','like','%'.$keyword.'%')
                      ->whereOr('t.receiver_id','like','%'.$keyword.'%')
                      ->whereOr('su.username','like','%'.$keyword.'%')
                      ->whereOr('su.nickname','like','%'.$keyword.'%')
                      ->whereOr('ru.username','like','%'.$keyword.'%')
                      ->whereOr('ru.nickname','like','%'.$keyword.'%')
                      ->whereOr('g.name','like','%'.$keyword.'%');
                });
                $countQuery->where(function($q) use ($keyword) {
                    $q->where('client_msg_no','like','%'.$keyword.'%')
                      ->whereOr('sender_id','like','%'.$keyword.'%')
                      ->whereOr('receiver_id','like','%'.$keyword.'%');
                });
            }
            $total = $countQuery->count();
            $rows = $query->field('t.*,a.appname,su.username sender_username,su.nickname sender_nickname,ru.username receiver_username,ru.nickname receiver_nickname,g.name group_name')
                ->order('t.id','desc')->page($page,$limit)->select();
            foreach (($rows ?: []) as $k=>$v) {
                $rows[$k]['amount_text'] = number_format(floatval($v['amount']), 2, '.', '');
                $rows[$k]['hold_amount_text'] = number_format(floatval($v['hold_amount']), 2, '.', '');
                $rows[$k]['fee_text'] = number_format(floatval($v['fee']), 2, '.', '');
                $rows[$k]['sender_name'] = trim(strval($v['sender_nickname'])) !== '' ? $v['sender_nickname'] : $v['sender_username'];
                $rows[$k]['receiver_name'] = trim(strval($v['receiver_nickname'])) !== '' ? $v['receiver_nickname'] : $v['receiver_username'];
                $rows[$k]['channel_text'] = intval(isset($v['channel_type']) ? $v['channel_type'] : 1) == 2 ? '群聊' : '私聊';
                $rows[$k]['money_type_text'] = intval($v['money_type']) == 1 ? '积分' : '金币';
                $rows[$k]['status_text'] = intval($v['status']) == 1 ? '已收款' : (intval($v['status']) == 2 ? '已退回' : '待收款');
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
                    $q->where('r.client_msg_no','like','%'.$keyword.'%')
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
                    $q->where('client_msg_no','like','%'.$keyword.'%')
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
                $rows[$k]['amount_text'] = number_format(floatval($v['amount']), 2, '.', '');
                $rows[$k]['remaining_amount_text'] = number_format(floatval($v['remaining_amount']), 2, '.', '');
                $rows[$k]['claimed_count'] = intval($claimCount);
                $rows[$k]['claimed_amount_text'] = number_format(floatval($claimAmount), 2, '.', '');
                $rows[$k]['sender_name'] = trim(strval($v['sender_nickname'])) !== '' ? $v['sender_nickname'] : $v['sender_username'];
                $rows[$k]['receiver_name'] = trim(strval($v['receiver_nickname'])) !== '' ? $v['receiver_nickname'] : $v['receiver_username'];
                $rows[$k]['channel_text'] = intval($v['channel_type']) == 2 ? '群聊' : '私聊';
                $rows[$k]['packet_type_text'] = strval($v['packet_type']) === 'lucky' ? '拼手气' : '普通';
                $rows[$k]['money_type_text'] = intval($v['money_type']) == 1 ? '积分' : '金币';
                $rows[$k]['status_text'] = intval($v['status']) == 1 ? '已领完' : (intval($v['status']) == 2 ? '已退回' : '领取中');
                $rows[$k]['create_time_text'] = intval($v['create_time']) > 0 ? date('Y-m-d H:i:s', intval($v['create_time'])) : '';
                $rows[$k]['refund_time_text'] = intval($v['refund_time']) > 0 ? date('Y-m-d H:i:s', intval($v['refund_time'])) : '';
            }
            return $this->jsonp(['rows'=>$rows,'total'=>$total]);
        }
        return $this->fetch();
    }
    // blin-money-records-end

'''
    if marker not in text:
        text = insert_before(text, "    protected function simple($table,$order)", methods)
    text = text.replace(
        """            $appid = input('appid');
            if ($appid !== '') {
                $this->blinRequireApp($appid);
                $query->where('t.appid', intval($appid));
                $countQuery->where('t.appid', intval($appid));
            } else {
                $this->blinScopeQuery($query, 't.appid');
                $this->blinScopeQuery($countQuery, 't.appid');
            }
            $status = input('status');
            if ($status !== '') {
                $query->where('t.status', intval($status));
                $countQuery->where('t.status', intval($status));
            }
            $channelType = input('channel_type');
            if ($channelType !== '') {
                $query->where('t.channel_type', intval($channelType));
                $countQuery->where('t.channel_type', intval($channelType));
            }
""",
        """            $appid = intval(input('appid'));
            if ($appid > 0) {
                $this->blinRequireApp($appid);
                $query->where('t.appid', $appid);
                $countQuery->where('t.appid', $appid);
            } else {
                $this->blinScopeQuery($query, 't.appid');
                $this->blinScopeQuery($countQuery, 't.appid');
            }
            $status = input('status');
            if ($status !== '' && intval($status) >= 0) {
                $query->where('t.status', intval($status));
                $countQuery->where('t.status', intval($status));
            }
            $channelType = intval(input('channel_type'));
            if ($channelType > 0) {
                $query->where('t.channel_type', $channelType);
                $countQuery->where('t.channel_type', $channelType);
            }
""",
    )
    text = text.replace(
        """            $appid = input('appid');
            if ($appid !== '') {
                $this->blinRequireApp($appid);
                $query->where('r.appid', intval($appid));
                $countQuery->where('r.appid', intval($appid));
            } else {
                $this->blinScopeQuery($query, 'r.appid');
                $this->blinScopeQuery($countQuery, 'r.appid');
            }
            $status = input('status');
            if ($status !== '') {
                $query->where('r.status', intval($status));
                $countQuery->where('r.status', intval($status));
            }
            $channelType = input('channel_type');
            if ($channelType !== '') {
                $query->where('r.channel_type', intval($channelType));
                $countQuery->where('r.channel_type', intval($channelType));
            }
""",
        """            $appid = intval(input('appid'));
            if ($appid > 0) {
                $this->blinRequireApp($appid);
                $query->where('r.appid', $appid);
                $countQuery->where('r.appid', $appid);
            } else {
                $this->blinScopeQuery($query, 'r.appid');
                $this->blinScopeQuery($countQuery, 'r.appid');
            }
            $status = input('status');
            if ($status !== '' && intval($status) >= 0) {
                $query->where('r.status', intval($status));
                $countQuery->where('r.status', intval($status));
            }
            $channelType = intval(input('channel_type'));
            if ($channelType > 0) {
                $query->where('r.channel_type', $channelType);
                $countQuery->where('r.channel_type', $channelType);
            }
""",
    )
    text = text.replace(
        """            $status = input('status');
            if ($status !== '' && intval($status) >= 0) {
                $query->where('t.status', intval($status));
                $countQuery->where('t.status', intval($status));
            }
""",
        """            $status = trim(strval(input('status', '')));
            if ($status !== '') {
                $query->where('t.status', intval($status));
                $countQuery->where('t.status', intval($status));
            }
""",
    )
    text = text.replace(
        """            $status = input('status');
            if ($status !== '' && intval($status) >= 0) {
                $query->where('r.status', intval($status));
                $countQuery->where('r.status', intval($status));
            }
""",
        """            $status = trim(strval(input('status', '')));
            if ($status !== '') {
                $query->where('r.status', intval($status));
                $countQuery->where('r.status', intval($status));
            }
""",
    )
    write_if_changed(ADMIN, text)


TRANSFER_VIEW = r'''{extend name="layout" /}
{block name="body"}
<div class="container-fluid p-t-15">
  <div class="row"><div class="col-lg-12"><div class="card">
    <header class="card-header"><div class="card-title">用户转账记录</div></header>
    <div class="card-body">
      <div class="row search-box">
        <div class="col-md-2 mb-2"><input class="form-control" id="appid" placeholder="APPID"></div>
        <div class="col-md-3 mb-2"><input class="form-control" id="keyword" placeholder="用户/群聊/流水号"></div>
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
$('#table').bootstrapTable({
  classes: 'table table-bordered table-hover table-striped lyear-table',
  url: '{:url("transfer_records")}',
  uniqueId: 'id', idField: 'id', dataType: 'jsonp', method: 'get',
  pagination: true, sidePagination: 'server', pageSize: 10, pageList: [10,25,50,100],
  showColumns: true, showRefresh: true, showFullscreen: true, totalField: 'total',
  queryParams: function(params){ return Object.assign({limit:params.limit, page:(params.offset/params.limit)+1}, getSearchParams()); },
  columns: [
    {field:'id',title:'ID'},
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
    {field:'operate',title:'操作',formatter:function(){return '<button class="btn btn-sm btn-default detail-btn">详情</button>';},events:{'click .detail-btn':function(e,v,row){showDetail(row);}}}
  ]
});
</script>
{/block}
'''


RED_PACKET_VIEW = r'''{extend name="layout" /}
{block name="body"}
<div class="container-fluid p-t-15">
  <div class="row"><div class="col-lg-12"><div class="card">
    <header class="card-header"><div class="card-title">用户红包记录</div></header>
    <div class="card-body">
      <div class="row search-box">
        <div class="col-md-2 mb-2"><input class="form-control" id="appid" placeholder="APPID"></div>
        <div class="col-md-3 mb-2"><input class="form-control" id="keyword" placeholder="用户/群聊/祝福语/流水号"></div>
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
$('#table').bootstrapTable({
  classes: 'table table-bordered table-hover table-striped lyear-table',
  url: '{:url("red_packet_records")}',
  uniqueId: 'id', idField: 'id', dataType: 'jsonp', method: 'get',
  pagination: true, sidePagination: 'server', pageSize: 10, pageList: [10,25,50,100],
  showColumns: true, showRefresh: true, showFullscreen: true, totalField: 'total',
  queryParams: function(params){ return Object.assign({limit:params.limit, page:(params.offset/params.limit)+1}, getSearchParams()); },
  columns: [
    {field:'id',title:'ID'},
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
    {field:'operate',title:'操作',formatter:function(){return '<button class="btn btn-sm btn-default detail-btn">详情</button>';},events:{'click .detail-btn':function(e,v,row){showDetail(row);}}}
  ]
});
</script>
{/block}
'''


def patch_views() -> None:
    VIEW_DIR.mkdir(parents=True, exist_ok=True)
    transfer = VIEW_DIR / "transfer_records.html"
    red = VIEW_DIR / "red_packet_records.html"
    if transfer.exists():
        old = transfer.read_text(encoding="utf-8")
        if old != TRANSFER_VIEW:
            backup(transfer)
    transfer.write_text(TRANSFER_VIEW, encoding="utf-8")
    if red.exists():
        old = red.read_text(encoding="utf-8")
        if old != RED_PACKET_VIEW:
            backup(red)
    red.write_text(RED_PACKET_VIEW, encoding="utf-8")


if __name__ == "__main__":
    patch_api()
    patch_trait()
    patch_admin()
    patch_views()
    print("group transfer and money record patch applied")
