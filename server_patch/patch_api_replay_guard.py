#!/usr/bin/env python3
"""Add API request signing/replay protection and IM message idempotency."""

from datetime import datetime
from pathlib import Path
import os
import re
import shutil
import subprocess


ROOT = Path("/www/wwwroot/blinlin")
BASE = ROOT / "application/api/controller/BaseController.php"
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


def replace_once(source: str, old: str, new: str, label: str) -> str:
    if old not in source:
        raise SystemExit(f"{label}_MARKER_NOT_FOUND")
    return source.replace(old, new, 1)


def replace_guard_methods(source: str) -> str:
    marker = "\n    // blin-api-replay-guard"
    end_marker = "\n    //更新用户在线记录"
    if marker not in source:
        return source.replace(end_marker, GUARD_METHODS + end_marker, 1)
    start = source.index(marker)
    end = source.index(end_marker, start)
    return source[:start] + GUARD_METHODS + source[end:]


def db_config():
    values = {
        "hostname": "127.0.0.1",
        "database": "blinlin",
        "username": "root",
        "password": "",
        "hostport": "3306",
    }
    env_path = ROOT / ".env"
    section = ""
    if not env_path.exists():
        return values
    for raw in env_path.read_text(errors="ignore").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith(";"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip().lower()
            continue
        if section != "database" or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip().lower()
        value = value.strip().strip('"').strip("'")
        if key in values:
            values[key] = value
    return values


def mysql(sql: str, ignore=()):
    config = db_config()
    env = os.environ.copy()
    env["MYSQL_PWD"] = config["password"]
    result = subprocess.run(
        [
            "mysql",
            f"-h{config['hostname']}",
            f"-u{config['username']}",
            f"-P{config.get('hostport') or '3306'}",
            config["database"],
            "-e",
            sql,
        ],
        universal_newlines=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        check=False,
    )
    if result.returncode != 0:
        err = result.stderr.strip()
        if any(item in err for item in ignore):
            print("MYSQL_IGNORE", err)
            return ""
        raise SystemExit(err)
    if result.stdout.strip():
        print(result.stdout.strip())
    return result.stdout


def patch_database():
    mysql(
        """CREATE TABLE IF NOT EXISTS `mr_api_nonce` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `appid` int(11) NOT NULL DEFAULT 0,
  `nonce` varchar(160) NOT NULL DEFAULT '',
  `token_hash` varchar(64) NOT NULL DEFAULT '',
  `action` varchar(80) NOT NULL DEFAULT '',
  `ip` varchar(64) NOT NULL DEFAULT '',
  `create_time` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_app_nonce` (`appid`,`nonce`),
  KEY `idx_create_time` (`create_time`),
  KEY `idx_token_action` (`token_hash`,`action`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"""
    )
    mysql(
        "ALTER TABLE `mr_messages` ADD COLUMN `appid` int(11) NOT NULL DEFAULT 0 AFTER `id`",
        ("Duplicate column name",),
    )
    mysql(
        "ALTER TABLE `mr_messages` ADD COLUMN `client_msg_no` varchar(128) DEFAULT NULL AFTER `im_payload`",
        ("Duplicate column name",),
    )
    mysql(
        """UPDATE `mr_messages` m
LEFT JOIN `mr_user` u ON u.id = m.sender_id
SET m.appid = IFNULL(u.appid, 0)
WHERE m.appid = 0"""
    )
    mysql(
        "ALTER TABLE `mr_messages` ADD UNIQUE KEY `uk_private_client_msg_no` (`appid`,`sender_id`,`receiver_id`,`client_msg_no`)",
        ("Duplicate key name", "Duplicate entry"),
    )
    mysql(
        "ALTER TABLE `mr_im_group_messages` MODIFY `client_msg_no` varchar(128) DEFAULT NULL",
        (),
    )
    mysql(
        "ALTER TABLE `mr_im_group_messages` ADD UNIQUE KEY `uk_group_client_msg_no` (`appid`,`group_id`,`sender_id`,`client_msg_no`)",
        ("Duplicate key name", "Duplicate entry"),
    )


GUARD_METHODS = r'''

    // blin-api-replay-guard
    protected function blinRequestGuard()
    {
        $method = strtoupper(isset($_SERVER["REQUEST_METHOD"]) ? $_SERVER["REQUEST_METHOD"] : "");
        if ($method === "OPTIONS") {
            exit();
        }
        $action = strtolower(trim(strval(Request::action() ?: input("action"))));
        if ($action === "wukongim_webhook") {
            return true;
        }
        $this->blinActionRateLimit($action);
        $skipNonceActions = ["get_image_verification_code"];
        $security = isset($this->app_info["security_configuration"]) && is_array($this->app_info["security_configuration"]) ? $this->app_info["security_configuration"] : [];
        $signEnabled = intval(isset($security["security_switch"]) ? $security["security_switch"] : 1) === 0
            && intval(isset($security["data_signature"]) ? $security["data_signature"] : 1) === 0;
        if (!$signEnabled) {
            if (input("sign") !== "" && input("appkey") !== "") {
                $optionalSign = strval(input("sign"));
                $optionalLocalSign = $this->blinBuildRequestSign(input(""), $this->appkey);
                if (hash_equals($optionalLocalSign, $optionalSign)) {
                    $this->blinVerifyBodyHash(input(""));
                    $this->blinValidateClientDevice();
                }
            }
            if (!in_array($action, $skipNonceActions) && input("nonce") !== "" && input("sign") !== "") {
                $this->blinNonceGuard($action, false);
            }
            return true;
        }
        $appkey = strval(input("appkey"));
        if ($appkey === "" || !hash_equals(strval($this->appkey), $appkey)) {
            $this->json(0, "appkey错误");
        }
        $timestamp = input("timestamp") ?: input("time");
        $window = intval(isset($security["time_difference_verification"]) ? $security["time_difference_verification"] : 300);
        if ($window <= 0) {
            $window = 300;
        }
        $this->checkTimeOffset($timestamp, $window);
        $sign = strval(input("sign"));
        if ($sign === "") {
            $this->json(0, "sign不能为空");
        }
        $localSign = $this->blinBuildRequestSign(input(""), $this->appkey);
        if (!hash_equals($localSign, $sign)) {
            $this->json(0, "签名校验失败");
        }
        $this->blinVerifyBodyHash(input(""));
        $this->blinValidateClientDevice();
        if (!in_array($action, $skipNonceActions)) {
            $this->blinNonceGuard($action, true);
        }
        return true;
    }

    protected function blinBuildRequestSign($params, $secretKey)
    {
        if (!is_array($params)) {
            $params = [];
        }
        foreach (["sign", "file", "files", "action", "s"] as $key) {
            if (isset($params[$key])) {
                unset($params[$key]);
            }
        }
        ksort($params, SORT_STRING);
        $signString = "";
        foreach ($params as $key => $value) {
            if (is_array($value)) {
                $encoded = json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            } else {
                $encoded = json_encode(strval($value), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            }
            $signString .= $key . "=" . $encoded . "&";
        }
        $signString .= "secretKey=" . $secretKey;
        return md5(stripslashes($signString));
    }

    protected function blinBuildRequestBodyHash($params)
    {
        if (!is_array($params)) {
            $params = [];
        }
        foreach (["sign", "body_hash", "file", "files", "action", "s"] as $key) {
            if (isset($params[$key])) {
                unset($params[$key]);
            }
        }
        ksort($params, SORT_STRING);
        $bodyString = "";
        foreach ($params as $key => $value) {
            if (is_array($value)) {
                $encoded = json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            } else {
                $encoded = json_encode(strval($value), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            }
            $bodyString .= $key . "=" . $encoded . "&";
        }
        return hash("sha256", stripslashes($bodyString));
    }

    protected function blinVerifyBodyHash($params)
    {
        $bodyHash = strtolower(trim(strval(input("body_hash") ?: "")));
        if ($bodyHash === "") {
            return true;
        }
        if (!preg_match('/^[a-f0-9]{64}$/', $bodyHash)) {
            $this->json(0, "请求体校验失败");
        }
        $localHash = $this->blinBuildRequestBodyHash($params);
        if (!hash_equals($localHash, $bodyHash)) {
            $this->json(0, "请求体校验失败");
        }
        return true;
    }

    protected function blinValidateClientDevice()
    {
        $deviceId = trim(strval(input("device_id") ?: input("client_device_id") ?: input("device") ?: ""));
        if ($deviceId === "") {
            $this->json(0, "设备标识不能为空");
        }
        if (strlen($deviceId) > 180 || !preg_match('/^[A-Za-z0-9_\-:\.]+$/', $deviceId)) {
            $this->json(0, "设备标识不合法");
        }
        return true;
    }

    protected function blinNonceGuard($action, $required = true)
    {
        $nonce = trim(strval(input("nonce") ?: input("request_nonce")));
        if ($nonce === "") {
            if ($required) {
                $this->json(0, "nonce不能为空");
            }
            return true;
        }
        if (strlen($nonce) < 8 || strlen($nonce) > 160 || !preg_match('/^[A-Za-z0-9_\-:\.]+$/', $nonce)) {
            $this->json(0, "nonce不合法");
        }
        $token = strval(input("usertoken") ?: "");
        $tokenHash = sha1($token === "" ? get_client_ip() : $token);
        $now = time();
        try {
            Db::name("api_nonce")->insert([
                "appid" => intval($this->appid),
                "nonce" => $nonce,
                "token_hash" => $tokenHash,
                "action" => substr(strval($action), 0, 80),
                "ip" => get_client_ip(),
                "create_time" => $now,
            ]);
            if (mt_rand(1, 100) === 1) {
                Db::name("api_nonce")->where("create_time", "<", $now - 86400)->delete();
            }
        } catch (\Exception $e) {
            $this->json(0, "请求已失效，请重新操作");
        }
        return true;
    }

    protected function blinActionRateLimit($action)
    {
        $action = strtolower(trim(strval($action)));
        $limits = [
            "send_message" => [30, 60],
            "send_im_group_message" => [40, 60],
            "send_im_call_signal" => [180, 60],
            "get_mobile_verification_code" => [5, 300],
            "get_email_verification_code" => [5, 300],
            "login" => [40, 60],
            "register" => [20, 60],
            "upload" => [30, 60],
            "upload_avatar" => [20, 60],
            "upload_background" => [20, 60],
        ];
        $rule = isset($limits[$action]) ? $limits[$action] : [240, 60];
        $limit = intval($rule[0]);
        $ttl = intval($rule[1]);
        if ($limit <= 0 || $ttl <= 0) {
            return true;
        }
        $token = strval(input("usertoken") ?: "");
        $identity = $token === "" ? get_client_ip() : sha1($token);
        $key = "api_action_rate:" . intval($this->appid) . ":" . $action . ":" . $identity;
        $count = Cache::get($key);
        if ($count && intval($count) >= $limit) {
            $this->json(0, "请求频繁,请稍后再试");
        }
        if ($count) {
            Cache::inc($key);
        } else {
            Cache::set($key, 1, $ttl);
        }
        return true;
    }

    protected function blinClientMsgNo($value)
    {
        $value = trim(strval($value));
        if ($value === "" || $value === "null") {
            return "";
        }
        $value = preg_replace('/[^A-Za-z0-9_\-:\.]/', "_", $value);
        return substr($value, 0, 128);
    }
'''


def patch_base():
    original = BASE.read_text()
    source = original
    if "$this->blinRequestGuard();" not in source:
        source = replace_once(
            source,
            '        $this->app_info = $this->getAppInfoByAppid($this->appid);\n        $this->maximum_number();',
            '        $this->app_info = $this->getAppInfoByAppid($this->appid);\n        $this->blinRequestGuard();\n        $this->maximum_number();',
            "base_initialize_guard",
        )
    source = replace_guard_methods(source)
    if '        $skipNonceActions = ["get_image_verification_code"];\n' not in source:
        source = source.replace(
            '        $this->blinActionRateLimit($action);\n',
            '        $this->blinActionRateLimit($action);\n        $skipNonceActions = ["get_image_verification_code"];\n',
            1,
        )
    source = source.replace(
        '            if (input("nonce") !== "" && input("sign") !== "") {',
        '            if (!in_array($action, $skipNonceActions) && input("nonce") !== "" && input("sign") !== "") {',
        1,
    )
    source = source.replace(
        '''        $this->blinNonceGuard($action, true);
        return true;''',
        '''        if (!in_array($action, $skipNonceActions)) {
            $this->blinNonceGuard($action, true);
        }
        return true;''',
        1,
    )
    save(BASE, original, source, "api_replay_guard_base")


def patch_private_send():
    original = API.read_text()
    source = original
    if '$this->blinActionRateLimit("send_message");' not in source:
        source = replace_once(
            source,
            '        $user_all_info = $this->user_info;\n',
            '        $this->blinActionRateLimit("send_message");\n        $user_all_info = $this->user_info;\n',
            "private_rate",
        )
    if 'blin-private-message-idempotency' not in source:
        source = replace_once(
            source,
            '''        if ($client_payload) {
            $decoded_client_no_payload = json_decode($client_payload, true);
            if (is_array($decoded_client_no_payload) && isset($decoded_client_no_payload["client_msg_no"]) && strval($decoded_client_no_payload["client_msg_no"]) !== "") {
                $client_msg_no_from_payload = strval($decoded_client_no_payload["client_msg_no"]);
            }
        }
''',
            '''        if ($client_payload) {
            $decoded_client_no_payload = json_decode($client_payload, true);
            if (is_array($decoded_client_no_payload) && isset($decoded_client_no_payload["client_msg_no"]) && strval($decoded_client_no_payload["client_msg_no"]) !== "") {
                $client_msg_no_from_payload = strval($decoded_client_no_payload["client_msg_no"]);
            }
        }
        $client_msg_no_from_payload = $this->blinClientMsgNo($client_msg_no_from_payload);
        if (strlen(strval($client_payload)) > 262144) {
            $this->json(0, "消息体过大");
        }
        if (strlen(strval(input("content"))) > 10000) {
            $this->json(0, "消息内容过长");
        }
        // blin-private-message-idempotency
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
''',
            "private_idempotency",
        )
    if '''        $add_message = [
            "appid" => intval($this->appid),
            "sender_id" => $user_all_info["id"],
''' not in source:
        source = replace_once(
            source,
            '''        $add_message = [
            "sender_id" => $user_all_info["id"],
''',
            '''        $add_message = [
            "appid" => intval($this->appid),
            "sender_id" => $user_all_info["id"],
''',
            "private_add_appid",
        )
    if '"client_msg_no" => $client_msg_no_from_payload !== "" ? $client_msg_no_from_payload : null,' not in source:
        source = replace_once(
            source,
            '''            "im_payload" => $client_payload,
            "file_path" => $file_path,
''',
            '''            "im_payload" => $client_payload,
            "client_msg_no" => $client_msg_no_from_payload !== "" ? $client_msg_no_from_payload : null,
            "file_path" => $file_path,
''',
            "private_add_client_no",
        )
    if 'blin-private-duplicate-insert-race' not in source:
        source = replace_once(
            source,
            '        $message_id = Db::name("messages")->insertGetId($add_message);\n',
            r'''        try {
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
''',
            "private_insert_guard",
        )
    save(API, original, source, "api_replay_guard_private")


GROUP_IDEMPOTENCY = r'''        $clientNo = isset($payload["client_msg_no"]) ? strval($payload["client_msg_no"]) : ("group_msg_" . $groupId . "_" . time() . "_" . mt_rand(1000,9999));
        $clientNo = $this->blinClientMsgNo($clientNo);
        if ($clientNo === "") {
            $clientNo = "group_msg_" . $groupId . "_" . time() . "_" . mt_rand(1000,9999);
        }
        if (strlen(strval($rawPayload)) > 262144) {
            $this->json(0, "消息体过大");
        }
        if (strlen(strval($content)) > 10000) {
            $this->json(0, "消息内容过长");
        }
        // blin-group-message-idempotency
        $existingGroupMessage = Db::name("im_group_messages")
            ->where("appid", intval($this->appid))
            ->where("group_id", $groupId)
            ->where("sender_id", intval($user["id"]))
            ->where("client_msg_no", $clientNo)
            ->find();
        if ($existingGroupMessage) {
            $existingPayload = isset($existingGroupMessage["payload"]) && $existingGroupMessage["payload"] !== "" ? json_decode($existingGroupMessage["payload"], true) : [];
            if (!is_array($existingPayload)) {
                $existingPayload = [];
            }
            $this->json(1, "发送成功", ["message_id" => intval($existingGroupMessage["id"]), "payload" => $existingPayload, "duplicate" => 1]);
        }
'''


def patch_group_send(path: Path):
    original = path.read_text()
    source = original
    if '$this->blinActionRateLimit("send_im_group_message");' not in source:
        source = replace_once(
            source,
            '        $user = $this->im_group_user();\n',
            '        $this->blinActionRateLimit("send_im_group_message");\n        $user = $this->im_group_user();\n',
            f"group_rate_{path.name}",
        )
    if "blin-group-message-idempotency" not in source:
        double_marker = '        $clientNo = isset($payload["client_msg_no"]) ? strval($payload["client_msg_no"]) : ("group_msg_" . $groupId . "_" . time() . "_" . mt_rand(1000,9999));\n'
        single_marker = "        $clientNo = isset($payload['client_msg_no']) ? strval($payload['client_msg_no']) : ('group_msg_' . $groupId . '_' . time() . '_' . mt_rand(1000,9999));\n"
        if double_marker in source:
            source = source.replace(double_marker, GROUP_IDEMPOTENCY, 1)
        elif single_marker in source:
            source = source.replace(
                single_marker,
                r'''        $clientNo = isset($payload['client_msg_no']) ? strval($payload['client_msg_no']) : ('group_msg_' . $groupId . '_' . time() . '_' . mt_rand(1000,9999));
        $clientNo = $this->blinClientMsgNo($clientNo);
        if ($clientNo === '') {
            $clientNo = 'group_msg_' . $groupId . '_' . time() . '_' . mt_rand(1000,9999);
        }
        if (strlen(strval($payloadRaw)) > 262144) {
            $this->json(0, '消息体过大');
        }
        if (strlen(strval($content)) > 10000) {
            $this->json(0, '消息内容过长');
        }
        // blin-group-message-idempotency
        $existingGroupMessage = Db::name('im_group_messages')
            ->where('appid', intval($this->appid))
            ->where('group_id', $groupId)
            ->where('sender_id', intval($user['id']))
            ->where('client_msg_no', $clientNo)
            ->find();
        if ($existingGroupMessage) {
            $existingPayload = isset($existingGroupMessage['payload']) && $existingGroupMessage['payload'] !== '' ? json_decode($existingGroupMessage['payload'], true) : [];
            if (!is_array($existingPayload)) {
                $existingPayload = [];
            }
            $this->json(1, '发送成功', ['message_id' => intval($existingGroupMessage['id']), 'payload' => $existingPayload, 'im_payload' => $existingPayload, 'duplicate' => 1]);
        }
''',
                1,
            )
        else:
            raise SystemExit(f"group_idempotency_{path.name}_MARKER_NOT_FOUND")
    if "blin-group-duplicate-insert-race" not in source:
        double_marker = '        $messageId = Db::name("im_group_messages")->insertGetId(["appid"=>$this->appid, "group_id"=>$groupId, "sender_id"=>intval($user["id"]), "message_type"=>$messageType, "content"=>$content, "payload"=>"", "client_msg_no"=>$clientNo, "create_time"=>date("Y-m-d H:i:s")]);\n'
        double_new = r'''        try {
            $messageId = Db::name("im_group_messages")->insertGetId(["appid"=>$this->appid, "group_id"=>$groupId, "sender_id"=>intval($user["id"]), "message_type"=>$messageType, "content"=>$content, "payload"=>"", "client_msg_no"=>$clientNo, "create_time"=>date("Y-m-d H:i:s")]);
        } catch (\Exception $e) {
            // blin-group-duplicate-insert-race
            $existingGroupMessage = Db::name("im_group_messages")
                ->where("appid", intval($this->appid))
                ->where("group_id", $groupId)
                ->where("sender_id", intval($user["id"]))
                ->where("client_msg_no", $clientNo)
                ->find();
            if ($existingGroupMessage) {
                $existingPayload = isset($existingGroupMessage["payload"]) && $existingGroupMessage["payload"] !== "" ? json_decode($existingGroupMessage["payload"], true) : [];
                if (!is_array($existingPayload)) {
                    $existingPayload = [];
                }
                $this->json(1, "发送成功", ["message_id" => intval($existingGroupMessage["id"]), "payload" => $existingPayload, "duplicate" => 1]);
            }
            $this->json(0, "消息发送失败，请稍后再试");
        }
'''
        single_marker = "        $messageId = Db::name('im_group_messages')->insertGetId(['appid'=>$this->appid, 'group_id'=>$groupId, 'sender_id'=>intval($user['id']), 'message_type'=>$messageType, 'content'=>$content, 'payload'=>'', 'client_msg_no'=>$clientNo, 'create_time'=>date('Y-m-d H:i:s')]);\n"
        single_new = r'''        try {
            $messageId = Db::name('im_group_messages')->insertGetId(['appid'=>$this->appid, 'group_id'=>$groupId, 'sender_id'=>intval($user['id']), 'message_type'=>$messageType, 'content'=>$content, 'payload'=>'', 'client_msg_no'=>$clientNo, 'create_time'=>date('Y-m-d H:i:s')]);
        } catch (\Exception $e) {
            // blin-group-duplicate-insert-race
            $existingGroupMessage = Db::name('im_group_messages')
                ->where('appid', intval($this->appid))
                ->where('group_id', $groupId)
                ->where('sender_id', intval($user['id']))
                ->where('client_msg_no', $clientNo)
                ->find();
            if ($existingGroupMessage) {
                $existingPayload = isset($existingGroupMessage['payload']) && $existingGroupMessage['payload'] !== '' ? json_decode($existingGroupMessage['payload'], true) : [];
                if (!is_array($existingPayload)) {
                    $existingPayload = [];
                }
                $this->json(1, '发送成功', ['message_id' => intval($existingGroupMessage['id']), 'payload' => $existingPayload, 'im_payload' => $existingPayload, 'duplicate' => 1]);
            }
            $this->json(0, '消息发送失败，请稍后再试');
        }
'''
        if double_marker in source:
            source = source.replace(double_marker, double_new, 1)
        elif single_marker in source:
            source = source.replace(single_marker, single_new, 1)
        else:
            raise SystemExit(f"group_insert_guard_{path.name}_MARKER_NOT_FOUND")
    save(path, original, source, f"api_replay_guard_group_{path.stem.lower()}")


def main():
    patch_database()
    patch_base()
    patch_private_send()
    patch_group_send(API)
    patch_group_send(TRAIT)


if __name__ == "__main__":
    main()
