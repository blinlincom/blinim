#!/usr/bin/env python3
"""Patch group messages to carry real sender name/avatar in payload/history."""

from datetime import datetime
from pathlib import Path
import re
import shutil


ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"
TRAIT = ROOT / "application/api/controller/traits/ImApiTrait.php"


def backup(path: Path, suffix: str) -> None:
    target = path.with_name(
        f"{path.name}.bak_{suffix}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    shutil.copy2(path, target)
    print("BACKUP", target)


def save(path: Path, original: str, source: str, suffix: str) -> bool:
    if source == original:
        print("NO_CHANGE", path)
        return False
    backup(path, suffix)
    path.write_text(source)
    print("PATCHED", path)
    return True


def patch_api(source: str) -> str:
    if '$payload["fromUser"] = ["id"=>intval($sender["id"])' not in source:
        source = source.replace(
            '''        $payload["from_uid"] = $this->appid . "_" . intval($sender["id"]);
        $payload["to_uid"] = $group["group_no"];
        $payload["group_id"] = intval($group["id"]);''',
            '''        $payload["from_uid"] = $this->appid . "_" . intval($sender["id"]);
        $payload["to_uid"] = $group["group_no"];
        $senderName = isset($sender["nickname"]) && trim(strval($sender["nickname"])) !== "" ? strval($sender["nickname"]) : (isset($sender["username"]) ? strval($sender["username"]) : ("用户" . intval($sender["id"])));
        $senderAvatar = isset($sender["usertx"]) ? strval($sender["usertx"]) : (isset($sender["avatar"]) ? strval($sender["avatar"]) : "");
        $payload["nickname"] = $senderName;
        $payload["avatar"] = $senderAvatar;
        $payload["fromUser"] = ["id"=>intval($sender["id"]), "username"=>isset($sender["username"]) ? strval($sender["username"]) : "", "nickname"=>$senderName, "usertx"=>$senderAvatar, "avatar"=>$senderAvatar];
        if (isset($payload["content"]) && is_array($payload["content"])) {
            $payload["content"]["nickname"] = $senderName;
            $payload["content"]["avatar"] = $senderAvatar;
        }
        $payload["group_id"] = intval($group["id"]);''',
            1,
        )

    old = '''        foreach ($rows as $r) {
            $payload = $r["payload"];
            $list[] = ["message"=>["id"=>$r["id"], "sender_id"=>$r["sender_id"], "receiver_id"=>$groupId, "message_type"=>$r["message_type"], "content"=>$r["content"], "im_payload"=>$payload, "create_time"=>$r["create_time"]]];
        }'''
    new = '''        foreach ($rows as $r) {
            $fromUser = Db::name("user")->where("appid", $this->appid)->where("id", intval($r["sender_id"]))->field("id,username,nickname,usertx")->find();
            if (!$fromUser) $fromUser = ["id"=>intval($r["sender_id"]), "username"=>"", "nickname"=>"用户" . intval($r["sender_id"]), "usertx"=>""];
            $senderName = isset($fromUser["nickname"]) && trim(strval($fromUser["nickname"])) !== "" ? strval($fromUser["nickname"]) : (isset($fromUser["username"]) ? strval($fromUser["username"]) : ("用户" . intval($r["sender_id"])));
            $senderAvatar = isset($fromUser["usertx"]) ? strval($fromUser["usertx"]) : "";
            $payload = $r["payload"];
            if ($payload !== "") {
                $decoded = json_decode(strval($payload), true);
                if (is_array($decoded)) {
                    $decoded["nickname"] = $senderName;
                    $decoded["avatar"] = $senderAvatar;
                    $decoded["fromUser"] = ["id"=>intval($fromUser["id"]), "username"=>isset($fromUser["username"]) ? strval($fromUser["username"]) : "", "nickname"=>$senderName, "usertx"=>$senderAvatar, "avatar"=>$senderAvatar];
                    if (isset($decoded["content"]) && is_array($decoded["content"])) {
                        $decoded["content"]["nickname"] = $senderName;
                        $decoded["content"]["avatar"] = $senderAvatar;
                    }
                    $payload = json_encode($decoded, JSON_UNESCAPED_UNICODE);
                }
            }
            $list[] = ["fromUser"=>$fromUser, "message"=>["id"=>$r["id"], "sender_id"=>$r["sender_id"], "receiver_id"=>$groupId, "message_type"=>$r["message_type"], "content"=>$r["content"], "im_payload"=>$payload, "create_time"=>$r["create_time"]]];
        }'''
    source = source.replace(old, new, 1)

    if (
        '$isRecalled = intval(isset($r["is_recalled"]) ? $r["is_recalled"] : 0);'
        in source
        and '$fromUser = Db::name("user")->where("appid", $this->appid)->where("id", intval($r["sender_id"]))'
        not in source
    ):
        source = source.replace(
            '''        foreach ($rows as $r) {
            $isRecalled = intval(isset($r["is_recalled"]) ? $r["is_recalled"] : 0);
            $payload = $r["payload"];''',
            '''        foreach ($rows as $r) {
            $isRecalled = intval(isset($r["is_recalled"]) ? $r["is_recalled"] : 0);
            $fromUser = Db::name("user")->where("appid", $this->appid)->where("id", intval($r["sender_id"]))->field("id,username,nickname,usertx")->find();
            if (!$fromUser) $fromUser = ["id"=>intval($r["sender_id"]), "username"=>"", "nickname"=>"用户" . intval($r["sender_id"]), "usertx"=>""];
            $senderName = isset($fromUser["nickname"]) && trim(strval($fromUser["nickname"])) !== "" ? strval($fromUser["nickname"]) : (isset($fromUser["username"]) ? strval($fromUser["username"]) : ("用户" . intval($r["sender_id"])));
            $senderAvatar = isset($fromUser["usertx"]) ? strval($fromUser["usertx"]) : "";
            $payload = $r["payload"];
            if ($payload !== "" && $isRecalled !== 1) {
                $decoded = json_decode(strval($payload), true);
                if (is_array($decoded)) {
                    $decoded["nickname"] = $senderName;
                    $decoded["avatar"] = $senderAvatar;
                    $decoded["fromUser"] = ["id"=>intval($fromUser["id"]), "username"=>isset($fromUser["username"]) ? strval($fromUser["username"]) : "", "nickname"=>$senderName, "usertx"=>$senderAvatar, "avatar"=>$senderAvatar];
                    if (isset($decoded["content"]) && is_array($decoded["content"])) {
                        $decoded["content"]["nickname"] = $senderName;
                        $decoded["content"]["avatar"] = $senderAvatar;
                    }
                    $payload = json_encode($decoded, JSON_UNESCAPED_UNICODE);
                }
            }''',
            1,
        )

    recall_pattern = re.compile(
        r'''(\$payload = json_encode\(\[\s*"version"=>"1\.0".*?"from_user_id"=>intval\(\$r\["sender_id"\]\), "to_user_id"=>0, "group_id"=>\$groupId,\s*)("msg_type"=>"recall")''',
        re.S,
    )
    source = recall_pattern.sub(
        r'''\1"nickname"=>isset($fromUser["nickname"]) ? $fromUser["nickname"] : "", "avatar"=>isset($fromUser["usertx"]) ? $fromUser["usertx"] : "", "fromUser"=>$fromUser,
                    \2''',
        source,
        count=1,
    )

    if '["fromUser"=>$fromUser, "message"=>' not in source:
        source = source.replace(
            '''            $list[] = ["message"=>["id"=>$r["id"], "sender_id"=>$r["sender_id"], "receiver_id"=>$groupId, "message_type"=>$isRecalled === 1 ? 0 : $r["message_type"], "content"=>$isRecalled === 1 ? "消息已撤回" : $r["content"], "is_recalled"=>$isRecalled, "im_payload"=>$payload, "create_time"=>$r["create_time"]]];''',
            '''            $list[] = ["fromUser"=>$fromUser, "message"=>["id"=>$r["id"], "sender_id"=>$r["sender_id"], "receiver_id"=>$groupId, "message_type"=>$isRecalled === 1 ? 0 : $r["message_type"], "content"=>$isRecalled === 1 ? "消息已撤回" : $r["content"], "is_recalled"=>$isRecalled, "im_payload"=>$payload, "create_time"=>$r["create_time"]]];''',
            1,
        )
    return source


def patch_trait(source: str) -> str:
    if "$payload['fromUser'] = ['id'=>intval($user['id'])" not in source:
        source = source.replace(
            '''        $payload['from_uid'] = $this->appid . '_' . intval($user['id']);
        $payload['to_uid'] = $group['group_no'];
        $payload['create_time'] = date('Y-m-d H:i:s');''',
            '''        $payload['from_uid'] = $this->appid . '_' . intval($user['id']);
        $payload['to_uid'] = $group['group_no'];
        $senderName = isset($user['nickname']) && trim(strval($user['nickname'])) !== '' ? strval($user['nickname']) : (isset($user['username']) ? strval($user['username']) : ('用户' . intval($user['id'])));
        $senderAvatar = isset($user['usertx']) ? strval($user['usertx']) : (isset($user['avatar']) ? strval($user['avatar']) : '');
        $payload['nickname'] = $senderName;
        $payload['avatar'] = $senderAvatar;
        $payload['fromUser'] = ['id'=>intval($user['id']), 'username'=>isset($user['username']) ? strval($user['username']) : '', 'nickname'=>$senderName, 'usertx'=>$senderAvatar, 'avatar'=>$senderAvatar];
        if (isset($payload['content']) && is_array($payload['content'])) {
            $payload['content']['nickname'] = $senderName;
            $payload['content']['avatar'] = $senderAvatar;
        }
        $payload['create_time'] = date('Y-m-d H:i:s');''',
            1,
        )

    old = '''        foreach (($rows ?: []) as $r) {
            $payload = isset($r['payload']) ? strval($r['payload']) : '';
            if ($payload !== '') {
                $decoded = json_decode($payload, true);
                if (is_array($decoded) && !isset($decoded['message_id'])) {
                    $decoded['message_id'] = intval($r['id']);
                    $payload = json_encode($decoded, JSON_UNESCAPED_UNICODE);
                }
            }
            $list[] = ['message'=>['id'=>intval($r['id']), 'message_id'=>intval($r['id']), 'sender_id'=>intval($r['sender_id']), 'receiver_id'=>$groupId, 'group_id'=>$groupId, 'message_type'=>intval($r['message_type']), 'content'=>$r['content'], 'im_payload'=>$payload, 'client_msg_no'=>isset($r['client_msg_no']) ? $r['client_msg_no'] : '', 'create_time'=>$r['create_time']]];
        }'''
    new = '''        foreach (($rows ?: []) as $r) {
            $fromUser = Db::name('user')->where('appid', $this->appid)->where('id', intval($r['sender_id']))->field('id,username,nickname,usertx')->find();
            if (!$fromUser) $fromUser = ['id'=>intval($r['sender_id']), 'username'=>'', 'nickname'=>'用户' . intval($r['sender_id']), 'usertx'=>''];
            $senderName = isset($fromUser['nickname']) && trim(strval($fromUser['nickname'])) !== '' ? strval($fromUser['nickname']) : (isset($fromUser['username']) ? strval($fromUser['username']) : ('用户' . intval($r['sender_id'])));
            $senderAvatar = isset($fromUser['usertx']) ? strval($fromUser['usertx']) : '';
            $payload = isset($r['payload']) ? strval($r['payload']) : '';
            if ($payload !== '') {
                $decoded = json_decode($payload, true);
                if (is_array($decoded)) {
                    if (!isset($decoded['message_id'])) $decoded['message_id'] = intval($r['id']);
                    $decoded['nickname'] = $senderName;
                    $decoded['avatar'] = $senderAvatar;
                    $decoded['fromUser'] = ['id'=>intval($fromUser['id']), 'username'=>isset($fromUser['username']) ? strval($fromUser['username']) : '', 'nickname'=>$senderName, 'usertx'=>$senderAvatar, 'avatar'=>$senderAvatar];
                    if (isset($decoded['content']) && is_array($decoded['content'])) {
                        $decoded['content']['nickname'] = $senderName;
                        $decoded['content']['avatar'] = $senderAvatar;
                    }
                    $payload = json_encode($decoded, JSON_UNESCAPED_UNICODE);
                }
            }
            $list[] = ['fromUser'=>$fromUser, 'message'=>['id'=>intval($r['id']), 'message_id'=>intval($r['id']), 'sender_id'=>intval($r['sender_id']), 'receiver_id'=>$groupId, 'group_id'=>$groupId, 'message_type'=>intval($r['message_type']), 'content'=>$r['content'], 'im_payload'=>$payload, 'client_msg_no'=>isset($r['client_msg_no']) ? $r['client_msg_no'] : '', 'create_time'=>$r['create_time']]];
        }'''
    source = source.replace(old, new, 1)
    return source


def main():
    for path, fn, suffix in (
        (API, patch_api, "group_sender_identity_api"),
        (TRAIT, patch_trait, "group_sender_identity_trait"),
    ):
        if not path.exists():
            continue
        original = path.read_text(errors="ignore")
        patched = fn(original)
        save(path, original, patched, suffix)


if __name__ == "__main__":
    main()
