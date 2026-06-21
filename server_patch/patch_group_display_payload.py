from pathlib import Path


ROOT = Path("/www/wwwroot/blinlin")
TRAIT = ROOT / "application/api/controller/traits/ImApiTrait.php"
API = ROOT / "application/api/controller/Api.php"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        print(f"{label}: already patched")
        return text
    if old not in text:
        raise RuntimeError(f"{label}: snippet not found")
    print(f"{label}: patched")
    return text.replace(old, new, 1)


def patch_after_anchor(text: str, anchor: str, old: str, new: str, label: str) -> str:
    start = text.find(anchor)
    if start < 0:
        raise RuntimeError(f"{label}: anchor not found")
    if new in text[start:]:
        print(f"{label}: already patched")
        return text
    index = text.find(old, start)
    if index < 0:
        raise RuntimeError(f"{label}: snippet not found after anchor")
    print(f"{label}: patched")
    return text[:index] + new + text[index + len(old):]


trait = TRAIT.read_text()
trait = replace_once(
    trait,
    """        $payload['group_id'] = $groupId;
        $payload['group_no'] = $group['group_no'];
        $payload['from_user_id'] = intval($user['id']);
""",
    """        $payload['group_id'] = $groupId;
        $payload['group_no'] = $group['group_no'];
        $groupName = isset($group['name']) && trim(strval($group['name'])) !== '' ? strval($group['name']) : '群聊';
        $groupAvatar = isset($group['avatar']) ? strval($group['avatar']) : '';
        $payload['group_name'] = $groupName;
        $payload['groupName'] = $groupName;
        $payload['group_avatar'] = $groupAvatar;
        $payload['groupAvatar'] = $groupAvatar;
        $payload['from_user_id'] = intval($user['id']);
""",
    "trait send group identity",
)
trait = replace_once(
    trait,
    """            $payload['content']['nickname'] = $senderName;
            $payload['content']['avatar'] = $senderAvatar;
""",
    """            $payload['content']['nickname'] = $senderName;
            $payload['content']['avatar'] = $senderAvatar;
            $payload['content']['group_id'] = $groupId;
            $payload['content']['group_name'] = $groupName;
            $payload['content']['groupName'] = $groupName;
            $payload['content']['group_avatar'] = $groupAvatar;
            $payload['content']['groupAvatar'] = $groupAvatar;
""",
    "trait send content group identity",
)
trait = replace_once(
    trait,
    """        $rows = $messageQuery->order('id desc')->limit($offset, $limit)->select();
        $list = [];
""",
    """        $groupName = isset($group['name']) && trim(strval($group['name'])) !== '' ? strval($group['name']) : '群聊';
        $groupAvatar = isset($group['avatar']) ? strval($group['avatar']) : '';
        $rows = $messageQuery->order('id desc')->limit($offset, $limit)->select();
        $list = [];
""",
    "trait history group vars",
)
trait = replace_once(
    trait,
    """                    $decoded['avatar'] = $senderAvatar;
                    $decoded['fromUser'] = ['id'=>intval($fromUser['id']), 'username'=>isset($fromUser['username']) ? strval($fromUser['username']) : '', 'nickname'=>$senderName, 'usertx'=>$senderAvatar, 'avatar'=>$senderAvatar];
""",
    """                    $decoded['avatar'] = $senderAvatar;
                    $decoded['group_id'] = $groupId;
                    $decoded['group_name'] = $groupName;
                    $decoded['groupName'] = $groupName;
                    $decoded['group_avatar'] = $groupAvatar;
                    $decoded['groupAvatar'] = $groupAvatar;
                    $decoded['fromUser'] = ['id'=>intval($fromUser['id']), 'username'=>isset($fromUser['username']) ? strval($fromUser['username']) : '', 'nickname'=>$senderName, 'usertx'=>$senderAvatar, 'avatar'=>$senderAvatar];
""",
    "trait history payload group identity",
)
trait = replace_once(
    trait,
    """                    if (isset($decoded['content']) && is_array($decoded['content'])) {
                        $decoded['content']['nickname'] = $senderName;
                        $decoded['content']['avatar'] = $senderAvatar;
                    }
""",
    """                    if (isset($decoded['content']) && is_array($decoded['content'])) {
                        $decoded['content']['nickname'] = $senderName;
                        $decoded['content']['avatar'] = $senderAvatar;
                        $decoded['content']['group_id'] = $groupId;
                        $decoded['content']['group_name'] = $groupName;
                        $decoded['content']['groupName'] = $groupName;
                        $decoded['content']['group_avatar'] = $groupAvatar;
                        $decoded['content']['groupAvatar'] = $groupAvatar;
                    }
""",
    "trait history content group identity",
)
TRAIT.write_text(trait)


api = API.read_text()
api = patch_after_anchor(
    api,
    "private function blinNormalizeGroupPayload",
    """        $senderAvatar = isset($sender["usertx"]) ? strval($sender["usertx"]) : (isset($sender["avatar"]) ? strval($sender["avatar"]) : "");
        $payload["nickname"] = $senderName;
""",
    """        $senderAvatar = isset($sender["usertx"]) ? strval($sender["usertx"]) : (isset($sender["avatar"]) ? strval($sender["avatar"]) : "");
        $groupName = isset($group["name"]) && trim(strval($group["name"])) !== "" ? strval($group["name"]) : "群聊";
        $groupAvatar = isset($group["avatar"]) ? strval($group["avatar"]) : "";
        $payload["nickname"] = $senderName;
""",
    "api normalize group vars",
)
api = patch_after_anchor(
    api,
    "private function blinNormalizeGroupPayload",
    """            $payload["content"]["nickname"] = $senderName;
            $payload["content"]["avatar"] = $senderAvatar;
""",
    """            $payload["content"]["nickname"] = $senderName;
            $payload["content"]["avatar"] = $senderAvatar;
            $payload["content"]["group_id"] = intval($group["id"]);
            $payload["content"]["group_name"] = $groupName;
            $payload["content"]["groupName"] = $groupName;
            $payload["content"]["group_avatar"] = $groupAvatar;
            $payload["content"]["groupAvatar"] = $groupAvatar;
""",
    "api normalize content group identity",
)
api = patch_after_anchor(
    api,
    "private function blinNormalizeGroupPayload",
    """        $payload["group_id"] = intval($group["id"]);
        $payload["group_no"] = $group["group_no"];
        $payload["client_msg_no"] = $clientNo;
""",
    """        $payload["group_id"] = intval($group["id"]);
        $payload["group_no"] = $group["group_no"];
        $payload["group_name"] = $groupName;
        $payload["groupName"] = $groupName;
        $payload["group_avatar"] = $groupAvatar;
        $payload["groupAvatar"] = $groupAvatar;
        $payload["client_msg_no"] = $clientNo;
""",
    "api normalize payload group identity",
)
api = patch_after_anchor(
    api,
    "public function get_im_group_chat_log()",
    """        $groupId = intval($data["group_id"]);
        if (!$this->im_group_member($groupId, intval($user["id"]))) $this->json(0, "你不在该群聊中");
        $limit = intval(input("limit") ?: $this->limit);
""",
    """        $groupId = intval($data["group_id"]);
        if (!$this->im_group_member($groupId, intval($user["id"]))) $this->json(0, "你不在该群聊中");
        $group = Db::name("im_groups")->where("appid", $this->appid)->where("id", $groupId)->where("status", 1)->find();
        if (!$group) $this->json(0, "群聊不存在");
        $groupName = isset($group["name"]) && trim(strval($group["name"])) !== "" ? strval($group["name"]) : "群聊";
        $groupAvatar = isset($group["avatar"]) ? strval($group["avatar"]) : "";
        $limit = intval(input("limit") ?: $this->limit);
""",
    "api history group lookup",
)
api = patch_after_anchor(
    api,
    "public function get_im_group_chat_log()",
    """                    $decoded["avatar"] = $senderAvatar;
                    $decoded["fromUser"] = ["id"=>intval($fromUser["id"]), "username"=>isset($fromUser["username"]) ? strval($fromUser["username"]) : "", "nickname"=>$senderName, "usertx"=>$senderAvatar, "avatar"=>$senderAvatar];
""",
    """                    $decoded["avatar"] = $senderAvatar;
                    $decoded["group_id"] = $groupId;
                    $decoded["group_name"] = $groupName;
                    $decoded["groupName"] = $groupName;
                    $decoded["group_avatar"] = $groupAvatar;
                    $decoded["groupAvatar"] = $groupAvatar;
                    $decoded["fromUser"] = ["id"=>intval($fromUser["id"]), "username"=>isset($fromUser["username"]) ? strval($fromUser["username"]) : "", "nickname"=>$senderName, "usertx"=>$senderAvatar, "avatar"=>$senderAvatar];
""",
    "api history payload group identity",
)
api = patch_after_anchor(
    api,
    "public function get_im_group_chat_log()",
    """                    if (isset($decoded["content"]) && is_array($decoded["content"])) {
                        $decoded["content"]["nickname"] = $senderName;
                        $decoded["content"]["avatar"] = $senderAvatar;
                    }
""",
    """                    if (isset($decoded["content"]) && is_array($decoded["content"])) {
                        $decoded["content"]["nickname"] = $senderName;
                        $decoded["content"]["avatar"] = $senderAvatar;
                        $decoded["content"]["group_id"] = $groupId;
                        $decoded["content"]["group_name"] = $groupName;
                        $decoded["content"]["groupName"] = $groupName;
                        $decoded["content"]["group_avatar"] = $groupAvatar;
                        $decoded["content"]["groupAvatar"] = $groupAvatar;
                    }
""",
    "api history content group identity",
)
api = patch_after_anchor(
    api,
    "public function get_im_group_chat_log()",
    """"from_user_id"=>intval($r["sender_id"]), "to_user_id"=>0, "group_id"=>$groupId,
                    "nickname"=>isset($fromUser["nickname"]) ? $fromUser["nickname"] : "", "avatar"=>isset($fromUser["usertx"]) ? $fromUser["usertx"] : "", "fromUser"=>$fromUser,
""",
    """"from_user_id"=>intval($r["sender_id"]), "to_user_id"=>0, "group_id"=>$groupId,
                    "group_name"=>$groupName, "groupName"=>$groupName, "group_avatar"=>$groupAvatar, "groupAvatar"=>$groupAvatar,
                    "nickname"=>isset($fromUser["nickname"]) ? $fromUser["nickname"] : "", "avatar"=>isset($fromUser["usertx"]) ? $fromUser["usertx"] : "", "fromUser"=>$fromUser,
""",
    "api recall history group identity",
)
api = patch_after_anchor(
    api,
    "private function blinGroupTransferPayloadJson",
    """        $senderName = isset($senderInfo["nickname"]) && trim(strval($senderInfo["nickname"])) !== "" ? strval($senderInfo["nickname"]) : (isset($senderInfo["username"]) ? strval($senderInfo["username"]) : ("用户" . intval($senderInfo["id"])));
        $senderAvatar = isset($senderInfo["usertx"]) ? strval($senderInfo["usertx"]) : (isset($senderInfo["avatar"]) ? strval($senderInfo["avatar"]) : "");
        $content["amount"] = $this->blinTransferMoneyText($transfer["amount"]);
""",
    """        $senderName = isset($senderInfo["nickname"]) && trim(strval($senderInfo["nickname"])) !== "" ? strval($senderInfo["nickname"]) : (isset($senderInfo["username"]) ? strval($senderInfo["username"]) : ("用户" . intval($senderInfo["id"])));
        $senderAvatar = isset($senderInfo["usertx"]) ? strval($senderInfo["usertx"]) : (isset($senderInfo["avatar"]) ? strval($senderInfo["avatar"]) : "");
        $groupName = isset($groupInfo["name"]) && trim(strval($groupInfo["name"])) !== "" ? strval($groupInfo["name"]) : "群聊";
        $groupAvatar = isset($groupInfo["avatar"]) ? strval($groupInfo["avatar"]) : "";
        $content["amount"] = $this->blinTransferMoneyText($transfer["amount"]);
""",
    "api group transfer vars",
)
api = patch_after_anchor(
    api,
    "private function blinGroupTransferPayloadJson",
    """        $content["group_id"] = intval($groupInfo["id"]);
        $content["channel_type"] = 2;
""",
    """        $content["group_id"] = intval($groupInfo["id"]);
        $content["group_name"] = $groupName;
        $content["groupName"] = $groupName;
        $content["group_avatar"] = $groupAvatar;
        $content["groupAvatar"] = $groupAvatar;
        $content["channel_type"] = 2;
""",
    "api group transfer content identity",
)
api = patch_after_anchor(
    api,
    "private function blinGroupTransferPayloadJson",
    """        $payload["group_id"] = intval($groupInfo["id"]);
        $payload["group_no"] = strval($groupInfo["group_no"]);
        $payload["msg_type"] = "transfer";
""",
    """        $payload["group_id"] = intval($groupInfo["id"]);
        $payload["group_no"] = strval($groupInfo["group_no"]);
        $payload["group_name"] = $groupName;
        $payload["groupName"] = $groupName;
        $payload["group_avatar"] = $groupAvatar;
        $payload["groupAvatar"] = $groupAvatar;
        $payload["msg_type"] = "transfer";
""",
    "api group transfer payload identity",
)
api = patch_after_anchor(
    api,
    "private function blinRedPacketPayloadArray",
    """        if ($channelType == 2) {
            $payload["group_id"] = intval($order["group_id"]);
            $payload["group_no"] = strval($target["group_no"]);
        }
""",
    """        if ($channelType == 2) {
            $groupName = isset($target["name"]) && trim(strval($target["name"])) !== "" ? strval($target["name"]) : "群聊";
            $groupAvatar = isset($target["avatar"]) ? strval($target["avatar"]) : "";
            $content["group_id"] = intval($order["group_id"]);
            $content["group_name"] = $groupName;
            $content["groupName"] = $groupName;
            $content["group_avatar"] = $groupAvatar;
            $content["groupAvatar"] = $groupAvatar;
            $payload["content"] = $content;
            $payload["group_id"] = intval($order["group_id"]);
            $payload["group_no"] = strval($target["group_no"]);
            $payload["group_name"] = $groupName;
            $payload["groupName"] = $groupName;
            $payload["group_avatar"] = $groupAvatar;
            $payload["groupAvatar"] = $groupAvatar;
        }
""",
    "api red packet group identity",
)
api = patch_after_anchor(
    api,
    "private function blinSendTransferReceipt",
    """                $senderAvatar = isset($fromUser["usertx"]) ? strval($fromUser["usertx"]) : (isset($fromUser["avatar"]) ? strval($fromUser["avatar"]) : "");
                $payload = [
""",
    """                $senderAvatar = isset($fromUser["usertx"]) ? strval($fromUser["usertx"]) : (isset($fromUser["avatar"]) ? strval($fromUser["avatar"]) : "");
                $groupName = isset($group["name"]) && trim(strval($group["name"])) !== "" ? strval($group["name"]) : "群聊";
                $groupAvatar = isset($group["avatar"]) ? strval($group["avatar"]) : "";
                $payload = [
""",
    "api group receipt vars",
)
api = patch_after_anchor(
    api,
    "private function blinSendTransferReceipt",
    """                    "group_id" => $groupId,
                    "group_no" => strval($group["group_no"]),
                    "msg_type" => "transfer_receipt",
""",
    """                    "group_id" => $groupId,
                    "group_no" => strval($group["group_no"]),
                    "group_name" => $groupName,
                    "groupName" => $groupName,
                    "group_avatar" => $groupAvatar,
                    "groupAvatar" => $groupAvatar,
                    "msg_type" => "transfer_receipt",
""",
    "api group receipt payload identity",
)
api = patch_after_anchor(
    api,
    "private function blinSendTransferReceipt",
    """                        "group_id" => $groupId,
                        "channel_type" => 2,
""",
    """                        "group_id" => $groupId,
                        "group_name" => $groupName,
                        "groupName" => $groupName,
                        "group_avatar" => $groupAvatar,
                        "groupAvatar" => $groupAvatar,
                        "channel_type" => 2,
""",
    "api group receipt content identity",
)
api = patch_after_anchor(
    api,
    "public function recall_message",
    """            $payload["group_id"] = $groupId;
            $payload["group_no"] = $group ? $group["group_no"] : "";
            try { if (config("wukongim.enable") && $group) (new \\app\\common\\tool\\WukongIM())->sendMessage($this->appid . "_" . intval($user["id"]), $group["group_no"], 2, $payload, "recall_" . $messageId . "_" . time()); } catch (\\Exception $e) {}
""",
    """            $payload["group_id"] = $groupId;
            $payload["group_no"] = $group ? $group["group_no"] : "";
            $payload["group_name"] = $group && isset($group["name"]) && trim(strval($group["name"])) !== "" ? strval($group["name"]) : "群聊";
            $payload["groupName"] = $payload["group_name"];
            $payload["group_avatar"] = $group && isset($group["avatar"]) ? strval($group["avatar"]) : "";
            $payload["groupAvatar"] = $payload["group_avatar"];
            try { if (config("wukongim.enable") && $group) (new \\app\\common\\tool\\WukongIM())->sendMessage($this->appid . "_" . intval($user["id"]), $group["group_no"], 2, $payload, "recall_" . $messageId . "_" . time()); } catch (\\Exception $e) {}
""",
    "api recall send group identity",
)
API.write_text(api)
