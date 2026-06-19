#!/usr/bin/env python3
"""Add IM red packet orders, claim flow, and app switches."""
from datetime import datetime
from pathlib import Path
import re


ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"
ADMIN = ROOT / "application/admin/controller/App.php"
EDIT = ROOT / "application/admin/view/app/edit.html"


def backup(path: Path, suffix: str) -> str:
    target = path.with_name(
        f"{path.name}.bak_{suffix}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    target.write_text(path.read_text(errors="ignore"))
    return str(target)


def save_if_changed(path: Path, original: str, source: str, suffix: str) -> bool:
    if source == original:
        return False
    print(f"PATCH_{path.name}_BACKUP", backup(path, suffix))
    path.write_text(source)
    return True


def replace_method(source: str, signature: str, body: str) -> str:
    start = source.find(signature)
    if start < 0:
        raise SystemExit(f"METHOD_NOT_FOUND:{signature}")
    brace = source.find("{", start)
    if brace < 0:
        raise SystemExit(f"METHOD_BRACE_NOT_FOUND:{signature}")
    depth = 0
    end = brace
    for i in range(brace, len(source)):
        ch = source[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    if end <= brace:
        raise SystemExit(f"METHOD_END_NOT_FOUND:{signature}")
    return source[:start] + body + source[end:]


RED_PACKET_BLOCK = r'''
    // blin-red-packet-start
    private function blinMoneyFeatureOpen($key)
    {
        $config = isset($this->app_info["forum_configuration"]) && is_array($this->app_info["forum_configuration"]) ? $this->app_info["forum_configuration"] : [];
        return intval(isset($config[$key]) ? $config[$key] : 0) !== 1;
    }

    private function blinEnsureRedPacketTables()
    {
        try {
            Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_red_packet_order` (`id` bigint(20) NOT NULL AUTO_INCREMENT, `appid` bigint(20) NOT NULL DEFAULT 0, `message_id` bigint(20) NOT NULL DEFAULT 0, `group_message_id` bigint(20) NOT NULL DEFAULT 0, `client_msg_no` varchar(128) NOT NULL DEFAULT '', `sender_id` bigint(20) NOT NULL DEFAULT 0, `receiver_id` bigint(20) NOT NULL DEFAULT 0, `group_id` bigint(20) NOT NULL DEFAULT 0, `channel_type` tinyint(1) NOT NULL DEFAULT 1 COMMENT '1 single, 2 group', `packet_type` varchar(16) NOT NULL DEFAULT 'normal', `amount` decimal(16,2) NOT NULL DEFAULT '0.00', `remaining_amount` decimal(16,2) NOT NULL DEFAULT '0.00', `total_count` int(11) NOT NULL DEFAULT 1, `remaining_count` int(11) NOT NULL DEFAULT 1, `money_type` tinyint(1) NOT NULL DEFAULT 0, `greeting` varchar(255) NOT NULL DEFAULT '', `status` tinyint(1) NOT NULL DEFAULT 0 COMMENT '0 pending, 1 finished, 2 refunded', `expire_time` int(11) NOT NULL DEFAULT 0, `refund_time` int(11) NOT NULL DEFAULT 0, `create_time` int(11) NOT NULL DEFAULT 0, `update_time` int(11) NOT NULL DEFAULT 0, PRIMARY KEY (`id`), KEY `idx_app_msg` (`appid`,`message_id`), KEY `idx_group_msg` (`appid`,`group_message_id`), KEY `idx_client_no` (`appid`,`client_msg_no`), KEY `idx_sender` (`appid`,`sender_id`,`status`), KEY `idx_receiver` (`appid`,`receiver_id`,`status`), KEY `idx_group` (`appid`,`group_id`,`status`), KEY `idx_expire` (`appid`,`status`,`expire_time`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
            Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_red_packet_claim` (`id` bigint(20) NOT NULL AUTO_INCREMENT, `appid` bigint(20) NOT NULL DEFAULT 0, `red_packet_id` bigint(20) NOT NULL DEFAULT 0, `user_id` bigint(20) NOT NULL DEFAULT 0, `amount` decimal(16,2) NOT NULL DEFAULT '0.00', `money_type` tinyint(1) NOT NULL DEFAULT 0, `create_time` int(11) NOT NULL DEFAULT 0, PRIMARY KEY (`id`), UNIQUE KEY `uniq_packet_user` (`appid`,`red_packet_id`,`user_id`), KEY `idx_packet` (`appid`,`red_packet_id`,`id`), KEY `idx_user` (`appid`,`user_id`,`id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
        } catch (\Exception $e) {}
    }

    private function blinRedPacketMoneyText($value)
    {
        return number_format(floatval($value), 2, ".", "");
    }

    private function blinRedPacketBalanceField($moneyType)
    {
        return intval($moneyType) == 1 ? "integral" : "money";
    }

    private function blinRedPacketStatusText($status)
    {
        $status = intval($status);
        if ($status == 1) return "finished";
        if ($status == 2) return "refunded";
        return "pending";
    }

    private function blinRedPacketType($value)
    {
        $type = strtolower(trim(strval($value)));
        if (in_array($type, ["lucky", "random", "luck"])) return "lucky";
        return "normal";
    }

    private function blinRedPacketGreeting($value)
    {
        $text = trim(strval($value));
        if ($text === "") $text = "恭喜发财，大吉大利";
        if (function_exists("mb_substr")) return mb_substr($text, 0, 80, "UTF-8");
        return substr($text, 0, 240);
    }

    private function blinRedPacketNormalizeAmount($raw)
    {
        $value = str_replace(",", ".", trim(strval($raw)));
        if ($value === "" || !preg_match('/^\d+(\.\d{1,2})?$/', $value)) return "";
        $amount = round(floatval($value), 2);
        if ($amount <= 0) return "";
        return $this->blinRedPacketMoneyText($amount);
    }

    private function blinRedPacketClaims($redPacketId)
    {
        $rows = [];
        try {
            $rows = Db::name("im_red_packet_claim")->alias("c")
                ->join("user u", "u.id=c.user_id", "LEFT")
                ->where("c.appid", intval($this->appid))
                ->where("c.red_packet_id", intval($redPacketId))
                ->field("c.id,c.user_id,c.amount,c.money_type,c.create_time,u.username,u.nickname,u.usertx")
                ->order("c.id asc")
                ->select();
        } catch (\Exception $e) {
            return [];
        }
        $list = [];
        foreach ($rows as $row) {
            $nickname = trim(strval(isset($row["nickname"]) ? $row["nickname"] : "")) !== "" ? strval($row["nickname"]) : strval(isset($row["username"]) ? $row["username"] : ("用户" . intval($row["user_id"])));
            $list[] = [
                "id" => intval($row["id"]),
                "user_id" => intval($row["user_id"]),
                "nickname" => $nickname,
                "avatar" => isset($row["usertx"]) ? strval($row["usertx"]) : "",
                "amount" => $this->blinRedPacketMoneyText($row["amount"]),
                "money_type" => intval($row["money_type"]),
                "create_time" => intval($row["create_time"]),
                "create_time_text" => intval($row["create_time"]) > 0 ? date("Y-m-d H:i:s", intval($row["create_time"])) : "",
            ];
        }
        return $list;
    }

    private function blinRedPacketData($order, $viewerId = 0)
    {
        if (!$order) return [];
        $claims = $this->blinRedPacketClaims(intval($order["id"]));
        $myClaim = null;
        foreach ($claims as $claim) {
            if (intval($claim["user_id"]) === intval($viewerId)) {
                $myClaim = $claim;
                break;
            }
        }
        return [
            "red_packet_id" => intval($order["id"]),
            "message_id" => intval($order["message_id"]),
            "group_message_id" => intval($order["group_message_id"]),
            "client_msg_no" => strval($order["client_msg_no"]),
            "sender_id" => intval($order["sender_id"]),
            "receiver_id" => intval($order["receiver_id"]),
            "group_id" => intval($order["group_id"]),
            "channel_type" => intval($order["channel_type"]),
            "scope" => intval($order["channel_type"]) == 2 ? "group" : "single",
            "packet_type" => strval($order["packet_type"]),
            "packet_type_label" => strval($order["packet_type"]) === "lucky" ? "拼手气红包" : (intval($order["channel_type"]) == 2 ? "普通红包" : "红包"),
            "amount" => $this->blinRedPacketMoneyText($order["amount"]),
            "total_amount" => $this->blinRedPacketMoneyText($order["amount"]),
            "remaining_amount" => $this->blinRedPacketMoneyText($order["remaining_amount"]),
            "total_count" => intval($order["total_count"]),
            "count" => intval($order["total_count"]),
            "remaining_count" => intval($order["remaining_count"]),
            "claimed_count" => max(0, intval($order["total_count"]) - intval($order["remaining_count"])),
            "money_type" => intval($order["money_type"]),
            "greeting" => strval($order["greeting"]),
            "status" => $this->blinRedPacketStatusText($order["status"]),
            "expires_at" => intval($order["expire_time"]) > 0 ? date("Y-m-d H:i:s", intval($order["expire_time"])) : "",
            "expire_time" => intval($order["expire_time"]),
            "refunded_at" => intval($order["refund_time"]) > 0 ? date("Y-m-d H:i:s", intval($order["refund_time"])) : "",
            "claimed_by_me" => $myClaim ? 1 : 0,
            "my_claim_amount" => $myClaim ? $myClaim["amount"] : "",
            "claims" => $claims,
        ];
    }

    private function blinRedPacketPayloadArray($clientPayload, $messageId, $clientNo, $sender, $target, $order)
    {
        $payload = json_decode(strval($clientPayload), true);
        if (!is_array($payload)) $payload = [];
        $channelType = intval($order["channel_type"]);
        $content = isset($payload["content"]) && is_array($payload["content"]) ? $payload["content"] : [];
        $content = array_merge($content, $this->blinRedPacketData($order, 0));
        unset($content["claims"]);
        $content["red_packet_id"] = intval($order["id"]);
        $content["text"] = "[红包] " . strval($order["greeting"]);
        $senderName = isset($sender["nickname"]) && trim(strval($sender["nickname"])) !== "" ? strval($sender["nickname"]) : (isset($sender["username"]) ? strval($sender["username"]) : ("用户" . intval($sender["id"])));
        $senderAvatar = isset($sender["usertx"]) ? strval($sender["usertx"]) : (isset($sender["avatar"]) ? strval($sender["avatar"]) : "");
        $payload["version"] = isset($payload["version"]) ? $payload["version"] : "1.0";
        $payload["message_id"] = intval($messageId);
        $payload["client_msg_no"] = strval($clientNo);
        $payload["conversation_type"] = $channelType == 2 ? "group" : "single";
        $payload["channel_type"] = $channelType;
        $payload["from_uid"] = $this->appid . "_" . intval($sender["id"]);
        $payload["from_user_id"] = intval($sender["id"]);
        $payload["to_user_id"] = $channelType == 2 ? intval($order["group_id"]) : intval($target["id"]);
        $payload["to_uid"] = $channelType == 2 ? strval($target["group_no"]) : ($this->appid . "_" . intval($target["id"]));
        $payload["msg_type"] = "red_packet";
        $payload["message_type"] = 0;
        $payload["content"] = $content;
        $payload["nickname"] = $senderName;
        $payload["avatar"] = $senderAvatar;
        $payload["fromUser"] = ["id"=>intval($sender["id"]), "username"=>isset($sender["username"]) ? strval($sender["username"]) : "", "nickname"=>$senderName, "usertx"=>$senderAvatar, "avatar"=>$senderAvatar];
        if ($channelType == 2) {
            $payload["group_id"] = intval($order["group_id"]);
            $payload["group_no"] = strval($target["group_no"]);
        }
        $payload["legacy"] = ["type"=>0, "content"=>"[红包] " . strval($order["greeting"]), "image_path"=>"", "sender_id"=>intval($sender["id"]), "receiver_id"=>$channelType == 2 ? intval($order["group_id"]) : intval($target["id"]), "money_type"=>intval($order["money_type"])];
        $payload["create_time"] = isset($payload["create_time"]) && strval($payload["create_time"]) !== "" ? $payload["create_time"] : date("Y-m-d H:i:s", intval($order["create_time"]) > 0 ? intval($order["create_time"]) : time());
        return $payload;
    }

    private function blinUpdateRedPacketPayload($order)
    {
        try {
            if (!$order) return;
            $sender = Db::name("user")->where("id", intval($order["sender_id"]))->find();
            if (!$sender) $sender = ["id" => intval($order["sender_id"])];
            if (intval($order["channel_type"]) == 2) {
                $messageId = intval($order["group_message_id"]);
                if ($messageId <= 0) return;
                $message = Db::name("im_group_messages")->where("id", $messageId)->find();
                if (!$message) return;
                $group = Db::name("im_groups")->where("id", intval($order["group_id"]))->find();
                if (!$group) $group = ["id"=>intval($order["group_id"]), "group_no"=>""];
                $payload = $this->blinRedPacketPayloadArray($message["payload"], $messageId, strval($order["client_msg_no"]), $sender, $group, $order);
                Db::name("im_group_messages")->where("id", $messageId)->update(["payload"=>json_encode($payload, JSON_UNESCAPED_UNICODE), "content"=>"[红包] " . strval($order["greeting"])]);
            } else {
                $messageId = intval($order["message_id"]);
                if ($messageId <= 0) return;
                $message = Db::name("messages")->where("id", $messageId)->find();
                if (!$message) return;
                $receiver = Db::name("user")->where("id", intval($order["receiver_id"]))->find();
                if (!$receiver) $receiver = ["id"=>intval($order["receiver_id"])];
                $payload = $this->blinRedPacketPayloadArray($message["im_payload"], $messageId, strval($order["client_msg_no"]), $sender, $receiver, $order);
                $encoded = json_encode($payload, JSON_UNESCAPED_UNICODE);
                Db::name("messages")->where("id", $messageId)->update(["im_payload"=>$encoded, "content"=>"[红包] " . strval($order["greeting"])]);
                try {
                    $logs = Db::name("im_message_log")->where("message_id", "local_" . $messageId)->select();
                    foreach ($logs as $log) {
                        Db::name("im_message_log")->where("id", intval($log["id"]))->update(["payload"=>$encoded, "raw_data"=>$encoded, "content"=>"[红包] " . strval($order["greeting"])]);
                    }
                } catch (\Exception $e) {}
            }
        } catch (\Exception $e) {}
    }

    private function blinMessageRedPacketContent($message, $scope = "single")
    {
        $payloadRaw = $scope === "group" ? (isset($message["payload"]) ? $message["payload"] : "") : (isset($message["im_payload"]) ? $message["im_payload"] : "");
        $payload = json_decode(strval($payloadRaw), true);
        $content = is_array($payload) && isset($payload["content"]) && is_array($payload["content"]) ? $payload["content"] : ["text" => strval(isset($message["content"]) ? $message["content"] : "[红包]")];
        try {
            $query = Db::name("im_red_packet_order")->where("appid", intval($this->appid));
            if ($scope === "group") {
                $query = $query->where("group_message_id", intval($message["id"]));
            } else {
                $query = $query->where("message_id", intval($message["id"]));
            }
            $order = $query->find();
            if ($order) {
                $data = $this->blinRedPacketData($order, intval(isset($this->user_info["id"]) ? $this->user_info["id"] : 0));
                unset($data["claims"]);
                $content = array_merge($content, $data);
                $content["red_packet_id"] = intval($order["id"]);
                $content["text"] = "[红包] " . strval($order["greeting"]);
            }
        } catch (\Exception $e) {}
        return $content;
    }

    private function blinExpireRedPackets($appid = null)
    {
        $this->blinEnsureRedPacketTables();
        $appid = $appid === null ? intval($this->appid) : intval($appid);
        try {
            $orders = Db::name("im_red_packet_order")->where("appid", $appid)->where("status", 0)->where("expire_time", "<=", time())->limit(50)->select();
        } catch (\Exception $e) {
            return;
        }
        foreach ($orders as $order) {
            Db::startTrans();
            try {
                $locked = Db::name("im_red_packet_order")->where("id", intval($order["id"]))->lock(true)->find();
                if (!$locked || intval($locked["status"]) !== 0 || intval($locked["expire_time"]) > time()) {
                    Db::commit();
                    continue;
                }
                $refund = floatval($locked["remaining_amount"]);
                if ($refund > 0) {
                    $field = $this->blinRedPacketBalanceField($locked["money_type"]);
                    $sender = Db::name("user")->where("id", intval($locked["sender_id"]))->where("appid", intval($locked["appid"]))->lock(true)->find();
                    if ($sender) {
                        Db::name("user")->where("id", intval($locked["sender_id"]))->update([$field => floatval($sender[$field]) + $refund]);
                        add_user_bill(["id"=>intval($locked["sender_id"]), "appid"=>intval($locked["appid"])], 15, "+" . $this->blinRedPacketMoneyText($refund), "红包24小时未领取，余额已退回", intval($locked["money_type"]), 0);
                    }
                }
                $now = time();
                Db::name("im_red_packet_order")->where("id", intval($locked["id"]))->update(["status"=>2, "remaining_amount"=>"0.00", "remaining_count"=>0, "refund_time"=>$now, "update_time"=>$now]);
                $locked["status"] = 2;
                $locked["remaining_amount"] = "0.00";
                $locked["remaining_count"] = 0;
                $locked["refund_time"] = $now;
                Db::commit();
                $this->blinUpdateRedPacketPayload($locked);
            } catch (\Exception $e) {
                try { Db::rollback(); } catch (\Exception $rollbackException) {}
            }
        }
    }

    private function blinRedPacketDuplicateData($order, $viewerId = 0)
    {
        if (!$order) return [];
        $this->blinUpdateRedPacketPayload($order);
        $payload = [];
        if (intval($order["channel_type"]) == 2 && intval($order["group_message_id"]) > 0) {
            $message = Db::name("im_group_messages")->where("id", intval($order["group_message_id"]))->find();
            if ($message && isset($message["payload"])) {
                $decoded = json_decode(strval($message["payload"]), true);
                if (is_array($decoded)) $payload = $decoded;
            }
        } elseif (intval($order["message_id"]) > 0) {
            $message = Db::name("messages")->where("id", intval($order["message_id"]))->find();
            if ($message && isset($message["im_payload"])) {
                $decoded = json_decode(strval($message["im_payload"]), true);
                if (is_array($decoded)) $payload = $decoded;
            }
        }
        return [
            "message_id" => intval($order["message_id"] ?: $order["group_message_id"]),
            "payload" => $payload,
            "red_packet" => $this->blinRedPacketData($order, $viewerId),
            "duplicate" => 1,
        ];
    }

    private function blinSendRedPacketPush($payload, $clientNo)
    {
        try {
            if (!config("wukongim.enable")) return;
            $wkim = new \app\common\tool\WukongIM();
            if (intval($payload["channel_type"]) == 2) {
                $wkim->sendMessage($payload["from_uid"], $payload["to_uid"], 2, $payload, $clientNo, ["no_persist"=>0,"red_dot"=>1,"sync_once"=>0]);
            } else {
                $wkim->sendPersonMessage($payload["from_uid"], $payload["to_uid"], $payload, $clientNo);
            }
        } catch (\Exception $e) {}
    }

    public function send_im_red_packet()
    {
        $data = input();
        $rule = ["usertoken|用户token" => "require", "receiver_id|接收者用户ID" => "require|number"];
        $validate = new Validate($rule);
        if (!$validate->check($data)) $this->json(0, $validate->getError());
        if (!$this->blinMoneyFeatureOpen("red_packet_switch")) $this->json(0, "红包功能已关闭");
        $this->blinEnsureRedPacketTables();
        $this->blinExpireRedPackets($this->appid);
        $sender = $this->user_info;
        $receiver = Db::name("user")->where("appid", intval($this->appid))->where("id", intval($data["receiver_id"]))->find();
        if (!$receiver) $this->json(0, "用户不存在");
        if (intval($receiver["id"]) === intval($sender["id"])) $this->json(0, "不能给自己发红包");
        $friend = Db::table("im_friends")->where("user_id", intval($sender["id"]))->where("friend_id", intval($receiver["id"]))->where("status", 1)->find();
        if (!$friend) $this->json(0, "添加好友后才能发红包");
        $amount = $this->blinRedPacketNormalizeAmount(isset($data["amount"]) ? $data["amount"] : (isset($data["money"]) ? $data["money"] : input("content")));
        if ($amount === "") $this->json(0, "红包金额必须为数字，最多保留两位小数");
        $moneyType = isset($data["money_type"]) ? intval($data["money_type"]) : intval(input("payment"));
        if (!in_array($moneyType, [0, 1])) $this->json(0, "红包余额类型不合法");
        $greeting = $this->blinRedPacketGreeting(isset($data["greeting"]) ? $data["greeting"] : (isset($data["note"]) ? $data["note"] : input("remark")));
        $rawPayload = input("im_payload") ?: input("payload");
        $payloadData = $rawPayload ? json_decode(strval($rawPayload), true) : [];
        if (!is_array($payloadData)) $payloadData = [];
        $clientNo = $this->blinClientMsgNo(isset($payloadData["client_msg_no"]) ? strval($payloadData["client_msg_no"]) : (isset($data["client_msg_no"]) ? strval($data["client_msg_no"]) : ""));
        if ($clientNo === "") $clientNo = "red_packet_" . intval($sender["id"]) . "_" . intval($receiver["id"]) . "_" . time() . "_" . mt_rand(1000,9999);
        $existing = Db::name("im_red_packet_order")->where("appid", intval($this->appid))->where("channel_type", 1)->where("sender_id", intval($sender["id"]))->where("receiver_id", intval($receiver["id"]))->where("client_msg_no", $clientNo)->find();
        if ($existing) $this->json(1, "发送成功", $this->blinRedPacketDuplicateData($existing, intval($sender["id"])));
        Db::startTrans();
        try {
            $field = $this->blinRedPacketBalanceField($moneyType);
            $lockedSender = Db::name("user")->where("appid", intval($this->appid))->where("id", intval($sender["id"]))->lock(true)->find();
            if (!$lockedSender) throw new \Exception("SENDER_NOT_FOUND");
            if (floatval($lockedSender[$field]) < floatval($amount)) {
                Db::rollback();
                $this->json(0, $moneyType == 1 ? "积分不足" : "金币不足");
            }
            $now = time();
            $messageId = Db::name("messages")->insertGetId(["appid"=>intval($this->appid), "sender_id"=>intval($sender["id"]), "receiver_id"=>intval($receiver["id"]), "content"=>"[红包] " . $greeting, "create_time"=>date("Y-m-d H:i:s", $now), "message_type"=>0, "image_path"=>"", "pid"=>0, "money_type"=>$moneyType, "im_payload"=>"", "client_msg_no"=>$clientNo, "file_path"=>"", "file_name"=>""]);
            $orderId = Db::name("im_red_packet_order")->insertGetId(["appid"=>intval($this->appid), "message_id"=>intval($messageId), "group_message_id"=>0, "client_msg_no"=>$clientNo, "sender_id"=>intval($sender["id"]), "receiver_id"=>intval($receiver["id"]), "group_id"=>0, "channel_type"=>1, "packet_type"=>"normal", "amount"=>$amount, "remaining_amount"=>$amount, "total_count"=>1, "remaining_count"=>1, "money_type"=>$moneyType, "greeting"=>$greeting, "status"=>0, "expire_time"=>$now + 86400, "create_time"=>$now, "update_time"=>$now]);
            Db::name("user")->where("id", intval($sender["id"]))->update([$field => floatval($lockedSender[$field]) - floatval($amount)]);
            add_user_bill(["id"=>intval($sender["id"]), "appid"=>intval($this->appid)], 15, "-" . $amount, "发给" . (isset($receiver["nickname"]) && $receiver["nickname"] !== "" ? $receiver["nickname"] : $receiver["username"]) . "的红包（待领取）", $moneyType, 0);
            $order = Db::name("im_red_packet_order")->where("id", intval($orderId))->find();
            $payload = $this->blinRedPacketPayloadArray($rawPayload, $messageId, $clientNo, $sender, $receiver, $order);
            $encoded = json_encode($payload, JSON_UNESCAPED_UNICODE);
            Db::name("messages")->where("id", intval($messageId))->update(["im_payload"=>$encoded]);
            Db::name("im_message_log")->insert(["appid"=>intval($this->appid), "message_id"=>"local_" . intval($messageId), "client_msg_no"=>$clientNo, "message_seq"=>0, "from_uid"=>$payload["from_uid"], "from_user_id"=>intval($sender["id"]), "channel_id"=>$payload["to_uid"], "channel_user_id"=>intval($receiver["id"]), "channel_type"=>1, "message_type"=>0, "content"=>"[红包] " . $greeting, "payload"=>$encoded, "raw_data"=>$encoded, "msg_timestamp"=>$now, "status"=>0, "audit_status"=>0, "create_time"=>date("Y-m-d H:i:s", $now)]);
            Db::commit();
            $this->blinSendRedPacketPush($payload, $clientNo);
            $this->json(1, "发送成功", ["message_id"=>intval($messageId), "payload"=>$payload, "red_packet"=>$this->blinRedPacketData($order, intval($sender["id"]))]);
        } catch (\Exception $e) {
            try { Db::rollback(); } catch (\Exception $rollbackException) {}
            $existing = Db::name("im_red_packet_order")->where("appid", intval($this->appid))->where("channel_type", 1)->where("sender_id", intval($sender["id"]))->where("receiver_id", intval($receiver["id"]))->where("client_msg_no", $clientNo)->find();
            if ($existing) $this->json(1, "发送成功", $this->blinRedPacketDuplicateData($existing, intval($sender["id"])));
            $this->json(0, "红包发送失败，请稍后再试");
        }
    }

    public function send_red_packet(){ return $this->send_im_red_packet(); }
    public function send_private_red_packet(){ return $this->send_im_red_packet(); }

    public function send_im_group_red_packet()
    {
        $data = input();
        $rule = ["usertoken|用户token" => "require", "group_id|群ID" => "require|number"];
        $validate = new Validate($rule);
        if (!$validate->check($data)) $this->json(0, $validate->getError());
        if (!$this->blinMoneyFeatureOpen("red_packet_switch")) $this->json(0, "红包功能已关闭");
        $this->blinEnsureRedPacketTables();
        $this->blinExpireRedPackets($this->appid);
        $sender = $this->im_group_user();
        $this->ensure_im_group_tables();
        $groupId = intval($data["group_id"]);
        $member = $this->im_group_member($groupId, intval($sender["id"]));
        if (!$member) $this->json(0, "你不在该群聊中");
        $group = Db::name("im_groups")->where("appid", intval($this->appid))->where("id", $groupId)->where("status", 1)->find();
        if (!$group) $this->json(0, "群聊不存在");
        if (intval($group["mute_all"]) === 1 && intval($member["role"]) < 1) $this->json(0, "当前群聊已全员禁言");
        $amount = $this->blinRedPacketNormalizeAmount(isset($data["amount"]) ? $data["amount"] : (isset($data["money"]) ? $data["money"] : input("content")));
        if ($amount === "") $this->json(0, "红包金额必须为数字，最多保留两位小数");
        $count = max(1, intval(isset($data["count"]) ? $data["count"] : input("total_count")));
        $memberCount = intval(Db::name("im_group_members")->where("appid", intval($this->appid))->where("group_id", $groupId)->where("status", 1)->count());
        if ($memberCount > 0 && $count > $memberCount) $this->json(0, "红包个数不能超过群成员数量");
        if ($count > 100) $this->json(0, "单次最多发送100个红包");
        $totalCents = intval(round(floatval($amount) * 100));
        if ($totalCents < $count) $this->json(0, "红包金额不足，每个红包至少0.01");
        $moneyType = isset($data["money_type"]) ? intval($data["money_type"]) : intval(input("payment"));
        if (!in_array($moneyType, [0, 1])) $this->json(0, "红包余额类型不合法");
        $packetType = $this->blinRedPacketType(isset($data["packet_type"]) ? $data["packet_type"] : input("type"));
        $greeting = $this->blinRedPacketGreeting(isset($data["greeting"]) ? $data["greeting"] : (isset($data["note"]) ? $data["note"] : input("remark")));
        $rawPayload = input("im_payload") ?: input("payload");
        $payloadData = $rawPayload ? json_decode(strval($rawPayload), true) : [];
        if (!is_array($payloadData)) $payloadData = [];
        $clientNo = $this->blinClientMsgNo(isset($payloadData["client_msg_no"]) ? strval($payloadData["client_msg_no"]) : (isset($data["client_msg_no"]) ? strval($data["client_msg_no"]) : ""));
        if ($clientNo === "") $clientNo = "group_red_packet_" . $groupId . "_" . intval($sender["id"]) . "_" . time() . "_" . mt_rand(1000,9999);
        $existing = Db::name("im_red_packet_order")->where("appid", intval($this->appid))->where("channel_type", 2)->where("sender_id", intval($sender["id"]))->where("group_id", $groupId)->where("client_msg_no", $clientNo)->find();
        if ($existing) $this->json(1, "发送成功", $this->blinRedPacketDuplicateData($existing, intval($sender["id"])));
        Db::startTrans();
        try {
            $field = $this->blinRedPacketBalanceField($moneyType);
            $lockedSender = Db::name("user")->where("appid", intval($this->appid))->where("id", intval($sender["id"]))->lock(true)->find();
            if (!$lockedSender) throw new \Exception("SENDER_NOT_FOUND");
            if (floatval($lockedSender[$field]) < floatval($amount)) {
                Db::rollback();
                $this->json(0, $moneyType == 1 ? "积分不足" : "金币不足");
            }
            $now = time();
            $messageId = Db::name("im_group_messages")->insertGetId(["appid"=>intval($this->appid), "group_id"=>$groupId, "sender_id"=>intval($sender["id"]), "message_type"=>0, "content"=>"[红包] " . $greeting, "payload"=>"", "client_msg_no"=>$clientNo, "create_time"=>date("Y-m-d H:i:s", $now)]);
            $orderId = Db::name("im_red_packet_order")->insertGetId(["appid"=>intval($this->appid), "message_id"=>0, "group_message_id"=>intval($messageId), "client_msg_no"=>$clientNo, "sender_id"=>intval($sender["id"]), "receiver_id"=>0, "group_id"=>$groupId, "channel_type"=>2, "packet_type"=>$packetType, "amount"=>$amount, "remaining_amount"=>$amount, "total_count"=>$count, "remaining_count"=>$count, "money_type"=>$moneyType, "greeting"=>$greeting, "status"=>0, "expire_time"=>$now + 86400, "create_time"=>$now, "update_time"=>$now]);
            Db::name("user")->where("id", intval($sender["id"]))->update([$field => floatval($lockedSender[$field]) - floatval($amount)]);
            add_user_bill(["id"=>intval($sender["id"]), "appid"=>intval($this->appid)], 15, "-" . $amount, "发到群聊「" . strval($group["name"]) . "」的红包（待领取）", $moneyType, 0);
            $order = Db::name("im_red_packet_order")->where("id", intval($orderId))->find();
            $payload = $this->blinRedPacketPayloadArray($rawPayload, $messageId, $clientNo, $sender, $group, $order);
            Db::name("im_group_messages")->where("id", intval($messageId))->update(["payload"=>json_encode($payload, JSON_UNESCAPED_UNICODE)]);
            Db::name("im_groups")->where("id", $groupId)->update(["update_time"=>date("Y-m-d H:i:s", $now)]);
            Db::commit();
            $this->blinSendRedPacketPush($payload, $clientNo);
            $this->json(1, "发送成功", ["message_id"=>intval($messageId), "payload"=>$payload, "red_packet"=>$this->blinRedPacketData($order, intval($sender["id"]))]);
        } catch (\Exception $e) {
            try { Db::rollback(); } catch (\Exception $rollbackException) {}
            $existing = Db::name("im_red_packet_order")->where("appid", intval($this->appid))->where("channel_type", 2)->where("sender_id", intval($sender["id"]))->where("group_id", $groupId)->where("client_msg_no", $clientNo)->find();
            if ($existing) $this->json(1, "发送成功", $this->blinRedPacketDuplicateData($existing, intval($sender["id"])));
            $this->json(0, "群红包发送失败，请稍后再试");
        }
    }

    public function send_group_red_packet(){ return $this->send_im_group_red_packet(); }

    private function blinFindRedPacketOrderFromInput()
    {
        $this->blinEnsureRedPacketTables();
        $query = Db::name("im_red_packet_order")->where("appid", intval($this->appid));
        $redPacketId = intval(input("red_packet_id") ?: input("packet_id") ?: input("id"));
        if ($redPacketId > 0) return $query->where("id", $redPacketId)->find();
        $messageId = intval(input("message_id"));
        if ($messageId > 0) {
            $groupId = intval(input("group_id"));
            if ($groupId > 0) return $query->where("group_id", $groupId)->where("group_message_id", $messageId)->find();
            return $query->where("message_id", $messageId)->find();
        }
        $clientNo = $this->blinClientMsgNo(strval(input("client_msg_no")));
        if ($clientNo !== "") return $query->where("client_msg_no", $clientNo)->find();
        return null;
    }

    public function get_im_red_packet_detail()
    {
        $data = input();
        $validate = new Validate(["usertoken|用户token" => "require"]);
        if (!$validate->check($data)) $this->json(0, $validate->getError());
        $this->blinExpireRedPackets($this->appid);
        $user = $this->user_info;
        $order = $this->blinFindRedPacketOrderFromInput();
        if (!$order) $this->json(0, "红包不存在");
        if (intval($order["channel_type"]) == 2) {
            if (!$this->im_group_member(intval($order["group_id"]), intval($user["id"]))) $this->json(0, "你不在该群聊中");
        } elseif (intval($order["sender_id"]) !== intval($user["id"]) && intval($order["receiver_id"]) !== intval($user["id"])) {
            $this->json(0, "无权查看红包");
        }
        $this->json(1, "success", ["red_packet"=>$this->blinRedPacketData($order, intval($user["id"]))]);
    }

    public function claim_im_red_packet()
    {
        $data = input();
        $validate = new Validate(["usertoken|用户token" => "require"]);
        if (!$validate->check($data)) $this->json(0, $validate->getError());
        $this->blinEnsureRedPacketTables();
        $this->blinExpireRedPackets($this->appid);
        $user = $this->user_info;
        $order = $this->blinFindRedPacketOrderFromInput();
        if (!$order) $this->json(0, "红包不存在");
        if (intval($order["channel_type"]) == 2) {
            if (!$this->im_group_member(intval($order["group_id"]), intval($user["id"]))) $this->json(0, "你不在该群聊中");
        } else {
            if (intval($order["sender_id"]) !== intval($user["id"]) && intval($order["receiver_id"]) !== intval($user["id"])) $this->json(0, "无权查看红包");
            if (intval($order["sender_id"]) === intval($user["id"])) $this->json(1, "等待对方领取", ["red_packet"=>$this->blinRedPacketData($order, intval($user["id"]))]);
        }
        $claimed = Db::name("im_red_packet_claim")->where("appid", intval($this->appid))->where("red_packet_id", intval($order["id"]))->where("user_id", intval($user["id"]))->find();
        if ($claimed) $this->json(1, "已领取", ["claim"=>["amount"=>$this->blinRedPacketMoneyText($claimed["amount"])], "red_packet"=>$this->blinRedPacketData($order, intval($user["id"]))]);
        if (intval($order["status"]) == 2) $this->json(1, "红包已过期", ["red_packet"=>$this->blinRedPacketData($order, intval($user["id"]))]);
        if (intval($order["status"]) == 1 || intval($order["remaining_count"]) <= 0 || floatval($order["remaining_amount"]) <= 0) $this->json(1, "红包已领完", ["red_packet"=>$this->blinRedPacketData($order, intval($user["id"]))]);
        Db::startTrans();
        try {
            $locked = Db::name("im_red_packet_order")->where("id", intval($order["id"]))->lock(true)->find();
            if (!$locked || intval($locked["status"]) !== 0) {
                Db::rollback();
                $fresh = $locked ?: $order;
                $this->json(1, "红包状态已更新", ["red_packet"=>$this->blinRedPacketData($fresh, intval($user["id"]))]);
            }
            if (intval($locked["expire_time"]) <= time()) {
                Db::rollback();
                $this->blinExpireRedPackets($this->appid);
                $fresh = Db::name("im_red_packet_order")->where("id", intval($order["id"]))->find();
                $this->json(1, "红包已过期", ["red_packet"=>$this->blinRedPacketData($fresh ?: $order, intval($user["id"]))]);
            }
            $claimed = Db::name("im_red_packet_claim")->where("appid", intval($this->appid))->where("red_packet_id", intval($locked["id"]))->where("user_id", intval($user["id"]))->lock(true)->find();
            if ($claimed) {
                Db::commit();
                $this->json(1, "已领取", ["claim"=>["amount"=>$this->blinRedPacketMoneyText($claimed["amount"])], "red_packet"=>$this->blinRedPacketData($locked, intval($user["id"]))]);
            }
            $remainingCount = intval($locked["remaining_count"]);
            $remainingCents = intval(round(floatval($locked["remaining_amount"]) * 100));
            if ($remainingCount <= 0 || $remainingCents <= 0) {
                Db::name("im_red_packet_order")->where("id", intval($locked["id"]))->update(["status"=>1, "remaining_count"=>0, "remaining_amount"=>"0.00", "update_time"=>time()]);
                $locked["status"] = 1;
                $locked["remaining_count"] = 0;
                $locked["remaining_amount"] = "0.00";
                Db::commit();
                $this->blinUpdateRedPacketPayload($locked);
                $this->json(1, "红包已领完", ["red_packet"=>$this->blinRedPacketData($locked, intval($user["id"]))]);
            }
            if ($remainingCount <= 1) {
                $claimCents = $remainingCents;
            } elseif (strval($locked["packet_type"]) === "lucky") {
                $max = $remainingCents - ($remainingCount - 1);
                $averageDouble = max(1, intval(floor($remainingCents / $remainingCount * 2)));
                $upper = max(1, min($max, $averageDouble));
                $claimCents = mt_rand(1, $upper);
            } else {
                $claimCents = max(1, intval(floor($remainingCents / $remainingCount)));
            }
            $claimAmount = $this->blinRedPacketMoneyText($claimCents / 100);
            $newRemainingCents = max(0, $remainingCents - $claimCents);
            $newRemainingCount = max(0, $remainingCount - 1);
            $newStatus = ($newRemainingCount <= 0 || $newRemainingCents <= 0) ? 1 : 0;
            $field = $this->blinRedPacketBalanceField($locked["money_type"]);
            $receiver = Db::name("user")->where("appid", intval($this->appid))->where("id", intval($user["id"]))->lock(true)->find();
            if (!$receiver) throw new \Exception("USER_NOT_FOUND");
            Db::name("user")->where("id", intval($user["id"]))->update([$field => floatval($receiver[$field]) + floatval($claimAmount)]);
            Db::name("im_red_packet_claim")->insert(["appid"=>intval($this->appid), "red_packet_id"=>intval($locked["id"]), "user_id"=>intval($user["id"]), "amount"=>$claimAmount, "money_type"=>intval($locked["money_type"]), "create_time"=>time()]);
            Db::name("im_red_packet_order")->where("id", intval($locked["id"]))->update(["remaining_amount"=>$this->blinRedPacketMoneyText($newRemainingCents / 100), "remaining_count"=>$newRemainingCount, "status"=>$newStatus, "update_time"=>time()]);
            add_user_bill(["id"=>intval($user["id"]), "appid"=>intval($this->appid)], 15, "+" . $claimAmount, intval($locked["channel_type"]) == 2 ? "领取群红包" : "领取红包", intval($locked["money_type"]), 0);
            $locked["remaining_amount"] = $this->blinRedPacketMoneyText($newRemainingCents / 100);
            $locked["remaining_count"] = $newRemainingCount;
            $locked["status"] = $newStatus;
            Db::commit();
            $this->blinUpdateRedPacketPayload($locked);
            $fresh = Db::name("im_red_packet_order")->where("id", intval($locked["id"]))->find();
            $this->json(1, "领取成功", ["claim"=>["amount"=>$claimAmount], "red_packet"=>$this->blinRedPacketData($fresh ?: $locked, intval($user["id"]))]);
        } catch (\Exception $e) {
            try { Db::rollback(); } catch (\Exception $rollbackException) {}
            $this->json(0, "领取失败，请稍后再试");
        }
    }

    public function open_red_packet(){ return $this->claim_im_red_packet(); }
    public function receive_red_packet(){ return $this->claim_im_red_packet(); }
    public function get_red_packet_detail(){ return $this->get_im_red_packet_detail(); }
    // blin-red-packet-end

'''


def patch_api() -> bool:
    source = API.read_text(errors="ignore")
    original = source
    if "// blin-red-packet-start" not in source:
        marker = "    //发送消息\n"
        if marker not in source:
            raise SystemExit("SEND_MESSAGE_MARKER_NOT_FOUND")
        source = source.replace(marker, RED_PACKET_BLOCK + "\n" + marker, 1)

    if "if (!$this->blinMoneyFeatureOpen(\"transfer_switch\")) $this->json(0, \"转账功能已关闭\");" not in source:
        marker = '''        } elseif ($message_type == 2) {
'''
        if marker not in source:
            raise SystemExit("TRANSFER_BRANCH_MARKER_NOT_FOUND")
        source = source.replace(
            marker,
            marker
            + '''            if (!$this->blinMoneyFeatureOpen("transfer_switch")) $this->json(0, "转账功能已关闭");
''',
            1,
        )

    if "普通消息接口不能发送红包" not in source:
        marker = '''            if (is_array($decoded_client_no_payload) && isset($decoded_client_no_payload["client_msg_no"]) && strval($decoded_client_no_payload["client_msg_no"]) !== "") {
                $client_msg_no_from_payload = strval($decoded_client_no_payload["client_msg_no"]);
            }
'''
        replacement = marker + '''            if (is_array($decoded_client_no_payload) && isset($decoded_client_no_payload["msg_type"]) && strval($decoded_client_no_payload["msg_type"]) === "red_packet") {
                $this->json(0, "普通消息接口不能发送红包，请使用红包接口");
            }
'''
        if marker not in source:
            raise SystemExit("PRIVATE_PAYLOAD_DECODE_MARKER_NOT_FOUND")
        source = source.replace(marker, replacement, 1)

    if "群普通消息接口不能发送红包" not in source:
        marker = '''            if (is_array($decoded)) $payload = $decoded;
        }
        $content = isset($data["content"]) ? strval($data["content"]) : "";
'''
        replacement = '''            if (is_array($decoded)) $payload = $decoded;
            if (is_array($decoded) && isset($decoded["msg_type"]) && strval($decoded["msg_type"]) === "red_packet") {
                $this->json(0, "群普通消息接口不能发送红包，请使用群红包接口");
            }
        }
        $content = isset($data["content"]) ? strval($data["content"]) : "";
'''
        if marker not in source:
            raise SystemExit("GROUP_PAYLOAD_DECODE_MARKER_NOT_FOUND")
        source = source.replace(marker, replacement, 1)

    for needle in [
        "public function get_message_list()",
        "public function get_chat_log()",
        "public function get_im_group_chat_log()",
    ]:
        start = source.find(needle)
        if start >= 0:
            brace = source.find("{", start)
            insert_at = source.find("\n", brace) + 1
            next_chunk = source[insert_at : insert_at + 240]
            if "blinExpireRedPackets" not in next_chunk:
                source = (
                    source[:insert_at]
                    + "        $this->blinExpireRedPackets($this->appid);\n"
                    + source[insert_at:]
                )

    if "blinMessageRedPacketContent($value, \"single\")" not in source:
        marker = '''            if (intval(isset($value["is_recalled"]) ? $value["is_recalled"] : 0) === 1) {
'''
        block = '''            $payload_from_db_red_packet = isset($value["im_payload"]) && $value["im_payload"] !== "" ? json_decode($value["im_payload"], true) : null;
            if (is_array($payload_from_db_red_packet) && isset($payload_from_db_red_packet["msg_type"]) && strval($payload_from_db_red_packet["msg_type"]) === "red_packet") {
                $msg_type = "red_packet";
                $im_content = $this->blinMessageRedPacketContent($value, "single");
            }
'''
        if marker not in source:
            raise SystemExit("CHAT_HISTORY_RECALL_MARKER_NOT_FOUND")
        source = source.replace(marker, block + marker, 1)

    if "blinMessageRedPacketContent($r, \"group\")" not in source:
        marker = '''                    if (isset($decoded["content"]) && is_array($decoded["content"])) {
                        $decoded["content"]["nickname"] = $senderName;
                        $decoded["content"]["avatar"] = $senderAvatar;
                    }
'''
        block = marker + '''                    if (isset($decoded["msg_type"]) && strval($decoded["msg_type"]) === "red_packet") {
                        $decoded["content"] = array_merge($this->blinMessageRedPacketContent($r, "group"), ["nickname"=>$senderName, "avatar"=>$senderAvatar]);
                    }
'''
        if marker not in source:
            raise SystemExit("GROUP_HISTORY_CONTENT_MARKER_NOT_FOUND")
        source = source.replace(marker, block, 1)

    source = source.replace(
        "in_array($data[\"transaction_type\"], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14])",
        "in_array($data[\"transaction_type\"], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15])",
    )
    return save_if_changed(API, original, source, "red_packet_api")


def patch_admin() -> bool:
    source = ADMIN.read_text(errors="ignore")
    original = source
    source = source.replace(
        '"transfer_handling_fee":"0","post_tipping_time_limit"',
        '"transfer_switch":"0","red_packet_switch":"0","transfer_handling_fee":"0","post_tipping_time_limit"',
    )
    if '"transfer_switch" => isset($data["transfer_switch"])' not in source:
        marker = '''                "comment_interval_time" => $data["comment_interval_time"],
                "transfer_handling_fee" => $data["transfer_handling_fee"],
'''
        replacement = '''                "comment_interval_time" => $data["comment_interval_time"],
                "transfer_switch" => isset($data["transfer_switch"]) ? intval($data["transfer_switch"]) : 0,
                "red_packet_switch" => isset($data["red_packet_switch"]) ? intval($data["red_packet_switch"]) : 0,
                "transfer_handling_fee" => $data["transfer_handling_fee"],
'''
        if marker not in source:
            raise SystemExit("FORUM_CONFIG_TRANSFER_MARKER_NOT_FOUND")
        source = source.replace(marker, replacement, 1)
    if '["transfer_switch", "red_packet_switch"]' not in source:
        marker = '''                if (!isset($result["forum_configuration"]["transfer_handling_fee"])) {
                    $result["forum_configuration"]["transfer_handling_fee"] = 0;
                }
'''
        replacement = '''                foreach (["transfer_switch", "red_packet_switch"] as $moneySwitchKey) {
                    if (!isset($result["forum_configuration"][$moneySwitchKey])) {
                        $result["forum_configuration"][$moneySwitchKey] = 0;
                    }
                }
                if (!isset($result["forum_configuration"]["transfer_handling_fee"])) {
                    $result["forum_configuration"]["transfer_handling_fee"] = 0;
                }
'''
        if marker not in source:
            raise SystemExit("FORUM_CONFIG_DEFAULT_MARKER_NOT_FOUND")
        source = source.replace(marker, replacement, 1)
    return save_if_changed(ADMIN, original, source, "red_packet_admin")


SWITCH_HTML = '''                            <div class="col-md-6">
                                <div class="blin-setting-row">
                                    <div class="blin-setting-copy">
                                        <span class="blin-setting-title">转账功能</span>
                                        <small class="blin-setting-desc">关闭后客户端和接口都不能发起转账。</small>
                                    </div>
                                    <div class="blin-segmented-switch" role="group" aria-label="转账功能">
                                        <input type="radio" id="transfer_switch_on" value="0" name="transfer_switch" class="btn-check" autocomplete="off" {if $data.forum_configuration.transfer_switch==0} checked {/if}>
                                        <label class="blin-switch-choice blin-switch-choice-on" for="transfer_switch_on"><i class="mdi mdi-check-circle-outline"></i>开启</label>
                                        <input type="radio" id="transfer_switch_off" value="1" name="transfer_switch" class="btn-check" autocomplete="off" {if $data.forum_configuration.transfer_switch==1} checked {/if}>
                                        <label class="blin-switch-choice blin-switch-choice-off" for="transfer_switch_off"><i class="mdi mdi-close-circle-outline"></i>关闭</label>
                                    </div>
                                </div>
                            </div>
                            <div class="col-md-6">
                                <div class="blin-setting-row">
                                    <div class="blin-setting-copy">
                                        <span class="blin-setting-title">红包功能</span>
                                        <small class="blin-setting-desc">关闭后私聊红包和群红包都不可发送。</small>
                                    </div>
                                    <div class="blin-segmented-switch" role="group" aria-label="红包功能">
                                        <input type="radio" id="red_packet_switch_on" value="0" name="red_packet_switch" class="btn-check" autocomplete="off" {if $data.forum_configuration.red_packet_switch==0} checked {/if}>
                                        <label class="blin-switch-choice blin-switch-choice-on" for="red_packet_switch_on"><i class="mdi mdi-check-circle-outline"></i>开启</label>
                                        <input type="radio" id="red_packet_switch_off" value="1" name="red_packet_switch" class="btn-check" autocomplete="off" {if $data.forum_configuration.red_packet_switch==1} checked {/if}>
                                        <label class="blin-switch-choice blin-switch-choice-off" for="red_packet_switch_off"><i class="mdi mdi-close-circle-outline"></i>关闭</label>
                                    </div>
                                </div>
                            </div>
'''


def patch_edit() -> bool:
    source = EDIT.read_text(errors="ignore")
    original = source
    if "red_packet_switch_on" not in source:
        marker = '''                            <div class="col-md-4">
                                <label for="transfer_handling_fee">转账手续费</label>
'''
        if marker not in source:
            raise SystemExit("EDIT_TRANSFER_FEE_MARKER_NOT_FOUND")
        source = source.replace(marker, SWITCH_HTML + marker, 1)
    return save_if_changed(EDIT, original, source, "red_packet_view")


def main() -> None:
    changed_api = patch_api()
    changed_admin = patch_admin()
    changed_edit = patch_edit()
    changed = changed_api or changed_admin or changed_edit
    print("PATCHED_RED_PACKET_FEATURE" if changed else "RED_PACKET_FEATURE_ALREADY_UP_TO_DATE")


if __name__ == "__main__":
    main()
