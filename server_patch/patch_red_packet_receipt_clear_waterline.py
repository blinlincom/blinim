#!/usr/bin/env python3
"""Make red-packet receipts and chat clearing respect the real timeline.

Receipt messages must use the claim timestamp, not the time when an already
claimed packet is opened again. Clearing a conversation must also remove the
WukongIM recent conversation for that user so old receipts do not come back as
the latest conversation preview.
"""
from pathlib import Path
import shutil
import time


ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "app/api/controller/Api.php"


def backup(path: Path) -> None:
    shutil.copy2(
        path,
        path.with_suffix(
            path.suffix
            + f".bak_red_packet_clear_waterline_{time.strftime('%Y%m%d%H%M%S')}"
        ),
    )


def replace_once(source: str, old: str, new: str, label: str) -> str:
    if new in source:
        return source
    if old not in source:
        raise SystemExit(f"{label} target not found")
    return source.replace(old, new, 1)


backup(API)
source = API.read_text(errors="ignore")

helper_marker = "    private function blinCreateRedPacketReceiptMessage($order, $claimAmount, $claimer)\n"
helper = """    private function blinRedPacketReceiptTimestamp($order, $claimerId)
    {
        try {
            $claim = Db::name("im_red_packet_claim")
                ->where("appid", intval($this->appid))
                ->where("red_packet_id", intval($order["id"]))
                ->where("user_id", intval($claimerId))
                ->field("create_time")
                ->find();
            if ($claim && intval($claim["create_time"]) > 0) {
                return intval($claim["create_time"]);
            }
        } catch (\\Exception $e) {}
        return time();
    }

    private function blinApplyRedPacketReceiptTime($payload, $receiptTimestamp, $receiptTimeText)
    {
        if (!is_array($payload)) return $payload;
        $payload["timestamp"] = intval($receiptTimestamp);
        $payload["create_time"] = $receiptTimeText;
        if (isset($payload["content"]) && is_array($payload["content"])) {
            $payload["content"]["timestamp"] = intval($receiptTimestamp);
            $payload["content"]["create_time"] = $receiptTimeText;
        }
        return $payload;
    }

"""
if "private function blinRedPacketReceiptTimestamp(" not in source:
    if helper_marker not in source:
        raise SystemExit("red-packet receipt create marker not found")
    source = source.replace(helper_marker, helper + helper_marker, 1)

old_now = """            $clientNo = $this->blinRedPacketReceiptClientNo($order, intval($claimer["id"]));
            $now = date("Y-m-d H:i:s");
"""
new_now = """            $clientNo = $this->blinRedPacketReceiptClientNo($order, intval($claimer["id"]));
            $receiptTimestamp = $this->blinRedPacketReceiptTimestamp($order, intval($claimer["id"]));
            $now = date("Y-m-d H:i:s", $receiptTimestamp);
"""
source = replace_once(source, old_now, new_now, "receipt timestamp")

old_group_existing = """                if ($existing) {
                    $payload = isset($existing["payload"]) && $existing["payload"] !== "" ? json_decode(strval($existing["payload"]), true) : null;
                    return is_array($payload) ? $payload : null;
                }
"""
new_group_existing = """                if ($existing) {
                    $payload = isset($existing["payload"]) && $existing["payload"] !== "" ? json_decode(strval($existing["payload"]), true) : null;
                    return is_array($payload) ? $this->blinApplyRedPacketReceiptTime($payload, $receiptTimestamp, $now) : null;
                }
"""
source = replace_once(source, old_group_existing, new_group_existing, "group existing receipt time")

old_private_existing = """            if ($existing) {
                $payload = isset($existing["im_payload"]) && $existing["im_payload"] !== "" ? json_decode(strval($existing["im_payload"]), true) : null;
                return is_array($payload) ? $payload : null;
            }
"""
new_private_existing = """            if ($existing) {
                $payload = isset($existing["im_payload"]) && $existing["im_payload"] !== "" ? json_decode(strval($existing["im_payload"]), true) : null;
                return is_array($payload) ? $this->blinApplyRedPacketReceiptTime($payload, $receiptTimestamp, $now) : null;
            }
"""
source = replace_once(source, old_private_existing, new_private_existing, "private existing receipt time")

old_group_payload = """                $payload = $this->blinRedPacketReceiptPayload($order, $claimer, $sender, $messageId, $clientNo, $claimAmount, $group);
                $encoded = json_encode($payload, JSON_UNESCAPED_UNICODE);
"""
new_group_payload = """                $payload = $this->blinApplyRedPacketReceiptTime($this->blinRedPacketReceiptPayload($order, $claimer, $sender, $messageId, $clientNo, $claimAmount, $group), $receiptTimestamp, $now);
                $encoded = json_encode($payload, JSON_UNESCAPED_UNICODE);
"""
source = replace_once(source, old_group_payload, new_group_payload, "group receipt payload time")

old_private_payload = """            $payload = $this->blinRedPacketReceiptPayload($order, $claimer, $sender, $messageId, $clientNo, $claimAmount);
            $encoded = json_encode($payload, JSON_UNESCAPED_UNICODE);
"""
new_private_payload = """            $payload = $this->blinApplyRedPacketReceiptTime($this->blinRedPacketReceiptPayload($order, $claimer, $sender, $messageId, $clientNo, $claimAmount), $receiptTimestamp, $now);
            $encoded = json_encode($payload, JSON_UNESCAPED_UNICODE);
"""
source = replace_once(source, old_private_payload, new_private_payload, "private receipt payload time")

source = source.replace('"msg_timestamp" => time(),', '"msg_timestamp" => $receiptTimestamp,', 1)

old_private_clear = """        $this->blinUpsertChatClearState($uid, $peer_id, $scope, $now);
        if ($scope === "both") {
            $this->blinUpsertChatClearState($peer_id, $uid, $scope, $now);
        }
        Db::name("messages")
"""
new_private_clear = """        $this->blinUpsertChatClearState($uid, $peer_id, $scope, $now);
        if ($scope === "both") {
            $this->blinUpsertChatClearState($peer_id, $uid, $scope, $now);
        }
        if (config("wukongim.enable")) {
            try {
                $wkim = new \\app\\common\\tool\\WukongIM();
                $wkim->deleteConversation($this->appid . "_" . $uid, $this->appid . "_" . $peer_id, 1);
                if ($scope === "both") {
                    $wkim->deleteConversation($this->appid . "_" . $peer_id, $this->appid . "_" . $uid, 1);
                }
            } catch (\\Exception $e) {
                $this->json(0, "消息服务清空失败：" . $e->getMessage());
            }
        }
        Db::name("messages")
"""
source = replace_once(source, old_private_clear, new_private_clear, "private Wukong conversation clear")

old_group_clear = """        $groupId = intval($data["group_id"]);
        if (!$this->im_group_member($groupId, intval($user["id"]))) $this->json(0, "你不在该群聊中");
        $messageId = intval(Db::name("im_group_messages")->where("appid", intval($this->appid))->where("group_id", $groupId)->max("id"));
        $now = date("Y-m-d H:i:s");
        $this->blinUpsertGroupClearState($groupId, intval($user["id"]), $messageId, $now);
        $this->blinUpsertGroupReadState($groupId, intval($user["id"]), $messageId, $now);
        $this->json(1, "群聊天记录已清空", ["clear_message_id" => $messageId, "clear_time" => $now]);
"""
new_group_clear = """        $groupId = intval($data["group_id"]);
        if (!$this->im_group_member($groupId, intval($user["id"]))) $this->json(0, "你不在该群聊中");
        $group = Db::name("im_groups")->where("appid", intval($this->appid))->where("id", $groupId)->where("status", 1)->find();
        if (!$group) $this->json(0, "群聊不存在");
        $messageId = intval(Db::name("im_group_messages")->where("appid", intval($this->appid))->where("group_id", $groupId)->max("id"));
        $now = date("Y-m-d H:i:s");
        $this->blinUpsertGroupClearState($groupId, intval($user["id"]), $messageId, $now);
        $this->blinUpsertGroupReadState($groupId, intval($user["id"]), $messageId, $now);
        if (config("wukongim.enable")) {
            try {
                (new \\app\\common\\tool\\WukongIM())->deleteConversation($this->appid . "_" . intval($user["id"]), strval($group["group_no"]), 2);
            } catch (\\Exception $e) {
                $this->json(0, "消息服务清空失败：" . $e->getMessage());
            }
        }
        $this->json(1, "群聊天记录已清空", ["clear_message_id" => $messageId, "clear_time" => $now]);
"""
source = replace_once(source, old_group_clear, new_group_clear, "group Wukong conversation clear")

API.write_text(source)
print("patched red-packet receipt timeline and conversation clearing")
