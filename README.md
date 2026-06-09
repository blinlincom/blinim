# imblinlin

现代化社区 + WuKongIM 即时通讯 Flutter 应用。支持 Android、Web、iOS 代码构建。

## 当前 IM SDK

客户端已迁移到官方最新版：

```yaml
wukongimfluttersdk: ^1.7.9
```

接入入口统一为 `WKIM.shared`，核心监听已在 `lib/services/im_service.dart` 接入：

- `connectionManager.addOnConnectionStatus`：连接/同步状态监听
- `messageManager.addOnNewMsgListener`：收到新消息
- `messageManager.addOnMsgInsertedListener`：本地消息入库
- `messageManager.addOnRefreshMsgListener`：消息状态刷新
- `cmdManager.addOnCmdListener`：CMD 命令消息监听

业务 payload 会兼容 `WKTextContent` 外层包裹，优先解出内层 JSON 后再分发到单聊、群聊、通话信令、presence 和好友事件。

## 已接入接口

- `POST /api/login` 登录
- `POST /api/get_im_connect_info` 获取 WuKongIM 最新 SDK 连接信息：`uid`、`token`、`tcp_addr/addr/im_addr`
- `POST /api/get_message_list` 会话列表，客户端已处理后台切回超时/Socket abort 重试与友好降级
- `POST /api/get_chat_log` 历史消息，读取 `message.im_payload`
- `POST /api/send_message` 发送消息，后端推送 WuKongIM 实时消息
- `POST /api/get_im_group_list` 群列表
- `POST /api/send_im_group_message` 群消息落库与群频道推送
- `POST /api/get_im_group_chat_log` 群历史消息

## 当前配置

```dart
AppConfig.apiBase = 'http://139.196.166.181/api';
AppConfig.appId = 1;
```

## 测试账号

- `abcd / 123456`，用户 ID `1`
- `abcc / 123456`，用户 ID `2`

## 构建

```bash
flutter clean
flutter pub get
flutter build apk --release
flutter build web --release
```

GitHub Actions 会自动构建 Android APK 与 Web 静态产物，并上传 artifact。

## 架构

- 社区首页：现代玻璃拟态卡片流
- 消息列表：PHP 历史会话接口 + WuKongIM 实时事件刷新
- 聊天页：历史消息 + WuKongIM Flutter SDK 实时接收
- 群聊：WuKongIM group channel + HTTP 落库 + 客户端未读角标
- 音视频：WebRTC 媒体通道 + WuKongIM 最新 SDK 信令
- 消息统一结构：`UnifiedMessage`，兼容 `im_payload` 与实时 payload

> 注意：当前服务器使用 HTTP，正式上线建议切换 HTTPS；WuKongIM Flutter SDK 1.7.9 的 `getAddr` 应返回 IM TCP 通信地址，不是旧 WebSocket 地址。

## 下载发布页

GitHub Pages 发布页：

```text
https://blinlincom.github.io/imblinlin/
```

页面提供：

- Android APK 下载
- Web 版预览
- APK SHA256 校验信息
- GitHub 源码入口
