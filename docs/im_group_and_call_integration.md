# IM 群聊与音视频联调文档

## 架构原则

- 客户端所有业务发送、同步、未读刷新、通话信令同步都调用后端 API。
- 后端 API 统一负责数据库读写、业务去重、调用 WuKongIM 服务端实时推送。
- 客户端 WuKongIM SDK 只负责连接、监听和接收后端经 WuKongIM 推来的结果，不直接发送业务消息。
- 后台恢复、断网恢复、历史同步、未读数刷新均为“客户端请求后端，后端统一处理数据库/WuKongIM 相关记录”。

## 群聊后端接口

本次群聊在现有 ThinkPHP API 与 WuKongIM 上扩展，不引入新服务。

### 数据表

- `mr_im_groups`：群基础信息。
  - `id`、`appid`、`group_no`、`name`
  - `avatar`：群头像
  - `notice`：群公告/预留
  - `owner_id`：群主用户 ID
  - `member_count`：成员数量
  - `mute_all`：全员禁言预留
  - `status`：1 正常，0/其他为无效或解散
  - `create_time`、`update_time`
- `mr_im_group_members`：群成员关系。
  - `group_id`、`user_id`
  - `role`：0 成员，1 管理员，2 群主
  - `nickname`：群昵称/预留
  - `mute_until`：成员禁言到期时间/预留
  - `status`：1 正常
  - `create_time`、`update_time`
- `mr_im_group_messages`：群消息历史。
  - `group_id`、`sender_id`、`message_type`、`content`
  - `payload`：IM 业务 payload JSON
  - `client_msg_no`：客户端消息去重号
  - `create_time`

数据库迁移脚本：

```text
server_patch/im_group_admin_patch.sql
server_patch/patch_im_group_admin_sql.py
```

推荐在线上执行幂等脚本 `patch_im_group_admin_sql.py`，它会自动跳过已存在字段/索引。

### 接口

- `POST /create_im_group`
  - 参数：`usertoken`、`name`、`member_ids`（逗号分隔用户 ID）
  - 行为：创建群、写入群主与成员、返回群信息。

- `POST /get_im_group_list`
  - 参数：`usertoken`
  - 行为：返回当前用户加入的群列表。

- `POST /send_im_group_message`
  - 参数：`usertoken`、`group_id`、`content`、可选 `payload/im_payload/msg_type`
  - 行为：落库 `mr_im_group_messages`，同时通过 WuKongIM group channel 推送。

- `POST /get_im_group_chat_log`
  - 参数：`usertoken`、`group_id`、`page`、`limit`
  - 行为：分页返回群消息历史。

- `POST /get_im_group_info`
  - 参数：`usertoken`、`group_id`
  - 行为：返回群资料、头像、群主、当前用户角色。

- `POST /get_im_group_members`
  - 参数：`usertoken`、`group_id`
  - 行为：返回群成员列表和角色。

- `POST /update_im_group`
  - 参数：`usertoken`、`group_id`、可选 `name/group_name`、`avatar/group_avatar`
  - 行为：群主/管理员修改群名和头像。

- `POST /add_im_group_members`
  - 参数：`usertoken`、`group_id`、`user_ids/member_ids`
  - 行为：群主/管理员邀请成员。

- `POST /remove_im_group_member`
  - 参数：`usertoken`、`group_id`、`user_id/member_id`
  - 行为：群主/管理员移出成员。

- `POST /set_im_group_admin`
  - 参数：`usertoken`、`group_id`、`user_id/member_id`、`admin` 或 `role`
  - 行为：群主设置/取消管理员。

- `POST /transfer_im_group`
  - 参数：`usertoken`、`group_id`、`user_id/new_owner_id`
  - 行为：群主转让。

- `POST /leave_im_group`
  - 参数：`usertoken`、`group_id`
  - 行为：普通成员退出群。

- `POST /dismiss_im_group`
  - 参数：`usertoken`、`group_id`
  - 行为：群主解散群。

- `POST /send_im_call_signal`
  - 参数：`usertoken`、`to_user_id/receiver_id`、`call_id`、`action`、`media`、`client_msg_no`、`payload/im_payload`
  - 行为：后端写入 `mr_im_call_signals`，再通过 WuKongIM personal channel 推送通话信令。客户端不直接调用 WuKongIM 发送通话信令。

- `POST /get_im_call_signals`
  - 参数：`usertoken`、可选 `since_id`、`call_id`、`peer_id`、`limit`
  - 行为：从后端同步通话信令，用于 App 后台/离线后恢复来电或终止状态；后端统一对接 WuKongIM 与数据库。

## WuKongIM 约定

客户端使用官方 `wukongimfluttersdk: ^1.7.9`，不再使用旧 SDK。

- SDK 入口：`WKIM.shared`。
- 初始化：`Options.newDefault(uid, token)` + `WKIM.shared.setup(options)`。
- 地址：`options.getAddr` 返回后端最新 API 给出的 TCP 通信地址，如 `tcp_addr/addr/im_addr`。
- 单聊：`WKChannelType.personal`，`channel_id={appid}_{userId}`。
- 群聊：`WKChannelType.group`，`channel_id=group_{appid}_{groupId}`。
- 发送：`messageManager.sendMessage(WKTextContent(jsonEncode(payload)), WKChannel(...))`。
- 监听：
  - `connectionManager.addOnConnectionStatus`
  - `messageManager.addOnNewMsgListener`
  - `messageManager.addOnMsgInsertedListener`
  - `messageManager.addOnRefreshMsgListener`
  - `cmdManager.addOnCmdListener`
- 因 `WKTextContent` 会包一层文本 content，客户端接收时会优先解出内层业务 JSON。

群消息 payload：
  - `msg_type=text|image|file|video|voice|transfer`
  - `group_id`、`group_no`
  - `from_user_id`、`from_uid`
  - `content`
  - 语音消息 `content` 包含 `url/file_url/name/duration/size/mime`，历史展示和消息列表预览使用 `duration`。

## 客户端入口

- 消息页顶部 `群组+` 图标：创建群聊。
- 消息页“我的群聊”：打开群聊。
- 群聊列表支持本地实时未读角标，收到群消息时对应群未读 `+1`，打开群聊后清零。
- 当前版本先支持群文本消息闭环，附件可沿用 `payload` 结构继续扩展。

## 音视频联调检查

### 2026-06-09 后端链路自动化测试

测试账号：`abcd/123456`（ID=1）与 `abcc/123456`（ID=2）。

已通过：

- 登录：两账号均返回 `code=1`。
- IM 连接信息：`uid=1_1/1_2`，`tcp_addr=139.196.166.181:5100`。
- 单聊发送：`/send_message` 返回发送成功且 `im_log_error` 为空，说明后端调用 WuKongIM 未报错。
- 接收方会话同步：`/get_message_list` 返回成功。
- 通话信令发送：`/send_im_call_signal` 可发送 `invite` 与 `hangup`。
- 通话信令同步：`/get_im_call_signals` 可按 `call_id` 拉到 `invite,hangup`，动作与 payload 类型正确。

仍需真机双端验证：

- 两端同时在线时，B 端 WKIM 监听是否实时收到 A 经后端发送的文字/图片/表情/文件。
- 音视频前端已移除，后续按 `docs/audio_video_rebuild_plan.md` 从零重建；当前只保留 `/send_im_call_signal` 与 `/get_im_call_signals` 后端信令接口。

### 真机双端联调步骤

- 两端登录不同账号，确保 IM 状态为在线。
- 文字、图片、表情、文件消息按现有聊天链路验证。
- 通话入口当前只会进入“音视频已移除，待重构”的占位页。
- 后续音视频重建完成后，再补充新的真机通话联调步骤。

## 后期对接建议

- 群成员管理客户端入口、API 封装与数据库迁移脚本已补：邀请、移除、退群、解散、管理员、群主转让、群头像/群名。
- 后端需要执行 `server_patch/patch_im_group_admin_sql.py` 并实现/合并上述群管理接口。
- 群未读数后续可按 `mr_im_group_messages.id` + 用户已读游标进一步服务端化；当前客户端已有本地实时未读角标。
- 音视频后续按 `docs/audio_video_rebuild_plan.md` 重新设计，不直接恢复旧 WebRTC 前端实现。
