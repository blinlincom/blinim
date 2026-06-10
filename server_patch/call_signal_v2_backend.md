# Blinlin Call Signal v2 后端接口改造说明

目标：废弃纯 cmd 作为通话业务主协议，所有通话信令统一使用结构化 JSON；后端负责合法化、状态校验、入库、悟空 IM 推送和补偿拉取。

## 1. 统一信令 JSON

后端 `/send_im_call_signal` 接收并输出的标准结构：

```json
{
  "schema": "blinlin.call.signal.v2",
  "msg_type": "call",
  "signal_type": "call_signal",
  "client_msg_no": "call_xxx_1_invite",
  "call_id": "call_xxx",
  "signal_id": "call_xxx_1_invite",
  "action": "invite",
  "type": "call_invite",
  "media": "audio",
  "from_user_id": 1,
  "to_user_id": 2,
  "from_uid": "1_1",
  "to_uid": "1_2",
  "from_device_id": "android_xxx",
  "seq": 1,
  "timestamp": 1781040000000,
  "content": {
    "call_id": "call_xxx",
    "signal_id": "call_xxx_1_invite",
    "action": "invite",
    "type": "call_invite",
    "media": "audio",
    "silent": false,
    "visible": true,
    "nickname": "abcd",
    "avatar": ""
  },
  "create_time": "2026-06-10T07:00:00.000"
}
```

## 2. action 白名单

只允许：

```text
invite
offer
accept
answer
ice
hangup
reject
cancel
timeout
ack
```

兼容输入可以接收旧值，但入库和输出必须归一化：

```text
call_invite => invite
call_offer => offer
call_accept => accept
call_answer => answer
call_ice => ice
call_hangup => hangup
call_reject => reject
call_ack => ack
end/finish => hangup
refuse => reject
```

## 3. /send_im_call_signal 后端必做校验

伪代码：

```php
$user = auth_by_usertoken($_POST['usertoken']);
if (!$user) fail('未登录');

$payload = json_decode($_POST['im_payload'] ?? $_POST['payload'] ?? '{}', true);
if (!$payload) fail('payload非法');

$content = is_array($payload['content'] ?? null) ? $payload['content'] : [];

$callId = trim($content['call_id'] ?? $payload['call_id'] ?? $_POST['call_id'] ?? '');
$signalId = trim($content['signal_id'] ?? $payload['signal_id'] ?? $payload['client_msg_no'] ?? $_POST['client_msg_no'] ?? '');
$action = normalize_call_action($content['action'] ?? $payload['action'] ?? $_POST['action'] ?? $_POST['call_action'] ?? $_POST['signal_action'] ?? '');
$media = normalize_media($content['media'] ?? $payload['media'] ?? $_POST['media'] ?? 'audio');
$toUserId = intval($_POST['to_user_id'] ?? $_POST['receiver_id'] ?? $payload['to_user_id'] ?? 0);

if ($callId === '') fail('call_id不能为空');
if ($signalId === '') fail('signal_id不能为空');
if (!in_array($action, CALL_ACTIONS, true)) fail('action非法');
if (!in_array($media, ['audio','video'], true)) fail('media非法');
if ($toUserId <= 0) fail('to_user_id非法');
if ($toUserId == $user['id']) fail('不能给自己拨打');

// from_user_id 必须以后端 token 为准，不能信任客户端传入。
$fromUserId = intval($user['id']);
$fromUid = appid().'_'.$fromUserId;
$toUid = appid().'_'.$toUserId;

$payload['schema'] = 'blinlin.call.signal.v2';
$payload['msg_type'] = 'call';
$payload['signal_type'] = 'call_signal';
$payload['call_id'] = $callId;
$payload['signal_id'] = $signalId;
$payload['client_msg_no'] = $signalId;
$payload['action'] = $action;
$payload['type'] = 'call_'.$action;
$payload['media'] = $media;
$payload['from_user_id'] = $fromUserId;
$payload['to_user_id'] = $toUserId;
$payload['from_uid'] = $fromUid;
$payload['to_uid'] = $toUid;
$payload['content'] = array_merge($content, [
  'call_id' => $callId,
  'signal_id' => $signalId,
  'action' => $action,
  'type' => 'call_'.$action,
  'media' => $media,
  'silent' => $action !== 'invite',
  'visible' => $action === 'invite',
]);

// 状态机校验：非法状态可返回成功但不执行，避免客户端重复弹。
$stateBefore = get_call_state($callId);
if (!call_state_can_accept($stateBefore, $action, $fromUserId, $toUserId)) {
  // 推荐返回 code=1 + ignored=true，让客户端不因重试制造更多重复信令。
  success(['ignored' => true, 'reason' => 'illegal_state', 'state' => $stateBefore]);
}
$stateAfter = call_state_next($stateBefore, $action);

// signal_id 唯一去重。
try {
  insert mr_im_call_signals(... payload_json=json_encode($payload) ...);
} catch duplicate_signal_id {
  success(['duplicate' => true, 'signal_id' => $signalId]);
}

// 悟空 IM 推送：不要只发 cmd 字符串；cmd 只能作为外层兼容字段，业务内容必须是 payload JSON。
wukong_send_to_user($toUid, json_encode($payload, JSON_UNESCAPED_UNICODE));

success(['id' => $insertId, 'payload' => $payload]);
```

## 4. /get_im_call_signals 返回要求

返回必须是结构化 list，不允许 payload 一会儿字符串一会儿对象。推荐：

```json
{
  "code": 1,
  "data": {
    "list": [
      {
        "id": 1001,
        "call_id": "call_xxx",
        "signal_id": "call_xxx_1_invite",
        "action": "invite",
        "media": "audio",
        "from_user_id": 1,
        "to_user_id": 2,
        "payload": { "schema": "blinlin.call.signal.v2", "msg_type": "call", "signal_type": "call_signal" }
      }
    ]
  }
}
```

筛选条件：

```sql
WHERE to_user_id = 当前登录用户ID
  AND id > since_id
ORDER BY id ASC
LIMIT limit
```

也可以包含自己发出的通话信令用于多端同步，但必须标明 from_user_id/to_user_id。

## 5. 后端状态机建议

状态：

```text
idle
outgoing_calling
incoming_ringing
offer_sent
offer_received
answer_sent
connecting_media
connected
ending
ended
rejected
failed
```

最低限度必须拦截：

- ended/rejected 后的新 invite/offer 不再推送。
- 同一 signal_id 重复提交不再重复写库/推送。
- 同一 call_id 的 invite 重复提交只保留第一条。
- hangup/reject/cancel 到达后，后续补偿接口不能再把旧 invite 当成待来电推给客户端。

## 6. 注意

客户端现在已兼容旧输入，但业务层会统一归一化为 `CallSignal`。后端完成后，客户端可以逐步移除旧 cmd 猜字段逻辑。