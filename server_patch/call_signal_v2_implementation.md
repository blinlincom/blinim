# Call Signal v2 实施记录

## 已执行时间

2026-06-10

## 客户端已改内容

涉及文件：

```text
lib/models/call_signal.dart
lib/screens/call_screen.dart
lib/screens/home_screen.dart
lib/services/im_service.dart
lib/services/api_service.dart
```

### 1. 新增结构化通话信令模型

新增 `lib/models/call_signal.dart`：

- `CallSignal`：统一解析和输出结构化 JSON 信令。
- `CallStateMachine`：客户端通话状态机。
- 兼容旧输入：`call_invite`、`call_action`、`signal_action`、`payload` 字符串、base64 payload、cmd-like 数据。
- 业务层统一使用结构化 payload。

标准信令：

```text
schema = blinlin.call.signal.v2
msg_type = call
signal_type = call_signal
action = invite/offer/accept/answer/ice/hangup/reject/cancel/timeout/ack
```

### 2. CallScreen 状态机化

`lib/screens/call_screen.dart` 已接入：

- 初始化 `CallStateMachine`。
- 发送信令前检查 `canSend(action)`。
- 接收信令先 `CallSignal.tryParse()`，再检查 `canReceive(action)`。
- 重复信令仍 ACK，但不重复执行。
- 非法状态信令写入日志并忽略。
- 所有发出的信令统一使用 `CallSignal.toPayload()`。

### 3. IM 层结构化归一化

`lib/services/im_service.dart` 已接入：

- `WKCMD` 只作为旧输入兼容，不再作为业务主协议。
- 收到 call/call_signal 后统一转成 `CallSignal`。
- 分发给业务层的是标准结构化 payload。

### 4. 后端补偿合法化解析

`lib/services/api_service.dart` 已接入：

- `sendImCallSignal()` 发送 schema/signal_type/action/signal_id 等结构化字段。
- `getImCallSignals()` 对后端返回进行统一归一化，payload 字符串/旧字段会被解析成标准结构。

### 5. HomeScreen 来电恢复增强

`lib/screens/home_screen.dart` 已接入：

- `im.calls` 收到信令后先统一解析 `CallSignal`。
- `_recoverIncomingCallsFromConversations()` 使用结构化解析，不再只认 Map。
- `_syncCallSignalsFromBackend()` 使用结构化解析，不再只认 `payload is Map`。
- IM connected 后立刻补拉通话信令。
- App 启动后增加 1s/3s/6s/10s 多次补偿同步，解决刚登录/新装/IM 连接慢窗口期。

## 后端已改内容

已通过 SSH 修改：

```text
/www/wwwroot/blinlin/application/api/controller/Api.php
```

自动备份：

```text
/www/wwwroot/blinlin/application/api/controller/Api.php.bak_call_v2_20260610080621
```

已执行检查：

```text
php -l /www/wwwroot/blinlin/application/api/controller/Api.php
```

结果：

```text
No syntax errors detected
```

### 后端接口变更

已覆盖这段逻辑：

```text
ensure_im_call_signal_tables()
normalize_im_call_action()
send_im_call_signal()
get_im_call_signals()
```

新增/增强：

- `signal_id` 强校验。
- `call_id` 强校验，不再由后端随便生成空 call_id。
- `action` 白名单。
- `media` 归一化为 audio/video。
- `from_user_id` 以后端 token 用户为准，不信任客户端。
- `to_user_id` 校验存在且不能等于自己。
- payload 统一输出 `schema=blinlin.call.signal.v2`。
- 同一 `signal_id` 重复请求返回 duplicate，不重复写库/推送。
- 同一 `call_id` 已终止后，后续 invite/offer/answer/ice 忽略。
- 同一 `call_id` 重复 invite 忽略，避免重复来电。
- 悟空 IM 推送内容为完整 JSON payload，不只发纯 cmd。

## 数据库 SQL 文件

已生成：

```text
server_patch/call_signal_v2_database.sql
```

说明：

- 这是给你手动执行/核对的数据库增强 SQL。
- 后端代码本身也会在接口调用时保守执行 ALTER 补字段。
- SQL 不会在客户端本地执行。

## 后端接口改造说明文件

已生成：

```text
server_patch/call_signal_v2_backend.md
```

## 当前未做

- 没有本地跑 Android/Gradle/Flutter 编译。
- 没有执行数据库破坏性操作。
- 没有删除旧数据。
- 没有直接清空通话信令表。

## 测试建议

两台手机测试：

1. A 打 B，B 前台，应只弹一个来电页。
2. B 退后台，A 打 B，应弹一个通知。
3. B 刚登录 1-10 秒内，A 打 B，应靠启动多次补偿拉到来电。
4. A 快速拨打后挂断，B 不应继续弹旧来电。
5. 同一通电话 invite/offer/hangup 的 call_id 必须一致。
6. 重复点击拨打或网络重试，不应多次弹同一 call_id。

如果仍有问题，优先抓后端 `mr_im_call_signals`：

```sql
SELECT id, call_id, signal_id, client_msg_no, action, media, from_user_id, to_user_id, create_time
FROM mr_im_call_signals
ORDER BY id DESC
LIMIT 50;
```

重点看：

- 同一通话 call_id 是否一致。
- signal_id 是否唯一。
- B 是否有收到 to_user_id=B 的 invite。
- hangup/reject 后是否还有新的 invite/offer 被写入。