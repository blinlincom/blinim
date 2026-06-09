# IM 群聊与音视频联调文档

## 群聊后端接口

本次群聊在现有 ThinkPHP API 与 WuKongIM 上扩展，不引入新服务。

### 数据表

- `mr_im_groups`：群基础信息。
- `mr_im_group_members`：群成员关系。
- `mr_im_group_messages`：群消息历史。

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

## WuKongIM 约定

- 单聊：`channel_type=1`，`channel_id={appid}_{userId}`。
- 群聊：`channel_type=2`，`channel_id=group_{appid}_{groupId}`。
- 群消息 payload：
  - `msg_type=text|image|file|video|transfer`
  - `group_id`、`group_no`
  - `from_user_id`、`from_uid`
  - `content`

## 客户端入口

- 消息页顶部 `群组+` 图标：创建群聊。
- 消息页“我的群聊”：打开群聊。
- 当前版本先支持群文本消息闭环，附件可沿用 `payload` 结构继续扩展。

## 音视频联调检查

- 两端登录不同账号，确保 IM 状态为在线。
- 手机端拨 Web/另一端：被叫端应弹出来电页。
- 被叫点击接听：按钮转圈，状态显示“正在建立媒体连接”。
- 只有 `RTCPeerConnectionStateConnected` 后显示“通话中”。
- 任一端挂断/拒绝：另一端应自动退出通话页。
- 如无画面，检查日志中是否有：`收到远端媒体`、`PeerConnection状态 Connected`。

## 后期对接建议

- 群成员管理后续补：邀请、移除、退群、群主转让。
- 群未读数后续可按 `mr_im_group_messages.id` + 用户已读游标扩展。
- 音视频如跨 NAT 不稳定，优先检查 coturn：3478/5349 UDP/TCP 与 ICE 配置。