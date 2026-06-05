# imblinlin

现代化社区 + WuKongIM 即时通讯 Flutter 应用。支持 Android、Web、iOS 代码构建。

## 已接入接口

- `POST /api/login` 登录
- `POST /api/get_im_connect_info` 获取 WuKongIM `uid/token/ws_addr`
- `POST /api/get_message_list` 会话列表
- `POST /api/get_chat_log` 历史消息，读取 `message.im_payload`
- `POST /api/send_message` 发送消息，后端推送 WuKongIM 实时消息

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
flutter pub get
flutter build apk --release
flutter build web --release
```

GitHub Actions 会自动构建 Android APK 与 Web 静态产物，并上传 artifact。

## 架构

- 社区首页：现代玻璃拟态卡片流
- 消息列表：PHP 历史会话接口
- 聊天页：历史消息 + WuKongIM Flutter SDK 实时接收
- 消息统一结构：`UnifiedMessage`，兼容 `im_payload` 与实时 payload

> 注意：当前服务器使用 HTTP/WS，正式上线建议切换 HTTPS/WSS。


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
