# 安卓离线推送方案（不依赖手机厂商推送）

## 结论

严格意义上，普通 Android App 被系统杀进程、限制自启动、断网休眠后，**不使用厂商 Push/FCM 就无法保证 100% 离线实时到达**。这是 Android 后台限制决定的，不是业务代码能完全绕过。

但可以做一个“不依赖厂商、尽量可靠”的自建方案：

1. App 前台/后台存活时：使用 WuKongIM 长连接实时收信令。
2. App 长连接不稳定或刚启动时：使用后端 `get_im_call_signals` 做补偿拉取。
3. App 后台但进程仍存活时：Android 前台服务保活 WebSocket/TCP，并展示常驻通知。
4. App 被杀/首次安装未打开/系统禁止后台运行时：无法被自建服务唤醒，只能等用户打开 App 后从后端补偿未接来电。

## 推荐落地结构

### 1. 后端：通话信令必须持久化

已具备基础：`mr_im_call_signals` 保存 `offer/answer/ice/hangup/reject/cancel` 等信令。

继续加强：

- 给每条信令保留 `call_id`、`signal_id`、`from_user_id`、`to_user_id`、`action`、`payload`。
- `/api/get_im_call_signals` 支持按 `since_id`、`call_id`、`peer_id` 增量拉取。
- 呼叫中如果对方未在线，仍写入数据库，等待客户端上线补偿。
- 增加未接来电状态表或复用信令表终止态：超时后写 `timeout`，避免用户上线后弹出已过期来电。

### 2. 客户端：前台服务保活

Android 端新增 ForegroundService：

- 启动登录后开启服务。
- 服务内维持 IM 连接或定时唤醒 Flutter/原生任务拉取 `/get_im_call_signals`。
- 服务必须显示常驻通知，例如“搭个话正在保持消息连接”。
- 通话邀请到达时发高优先级本地通知，点击进入 `CallScreen`。

Manifest 需要增加：

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
```

Android 14+ 前台服务类型要声明 `dataSync` 或按实际用途拆分。

### 3. 客户端：补偿拉取

当前 Flutter 已在 `HomeScreen` 启动、恢复前台、IM 重连后调用 `_syncCallSignalsFromBackend()`。本次又在 `CallScreen` 内增加了通话中补偿轮询，防止实时信令漏掉 `answer/ice` 后卡在“正在建立媒体连接”。

### 4. 为什么不能只靠离线推送

语音/视频通话的问题本质不是“通知没来”一个点，而是：

- 来电信令是否送达；
- offer/answer 是否都携带 SDP；
- ICE candidate 是否完整到达；
- TURN 是否可用；
- Android 后台是否允许进程存活。

离线推送只能解决“提醒用户打开 App”，不能替代 WebRTC 信令链路。

## 当前建议

短期：先用“后端持久化 + 通话页补偿轮询 + 前台本地通知”修连接中卡死。

中期：做 Android ForegroundService 保持 IM 长连接。

长期：如果要微信级到达率，必须接入厂商推送或 FCM；如果坚持不用厂商，就需要明确接受“被系统杀死时只能打开 App 后补偿”的限制。
