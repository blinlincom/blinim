# imblinlin 部署与通话配置说明

本文档说明 imblinlin Flutter 客户端、ThinkPHP 后端、悟空 IM、WebRTC 音视频通话的部署和配置方式。

## 1. 当前架构

- Flutter 客户端：`lib/`
- 后端 API：ThinkPHP，当前地址 `http://139.196.166.181/api`
- 实时消息：悟空 IM/WuKongIM，Flutter 客户端使用官方 `wukongimfluttersdk: ^1.7.9`
- 音视频通话：WebRTC 媒体通道 + 悟空 IM 信令
- 通话信令类型：`msg_type=call`
- 通话信令动作：`invite`、`offer`、`accept`、`answer`、`ice`、`ack`、`hangup`、`reject`

通话不是把音视频流走悟空 IM，而是：

1. 客户端用悟空 IM 给对方发送通话信令。
2. 双方通过 WebRTC 建立 P2P 音视频连接。
3. ICE 候选也通过悟空 IM 交换。
4. 如果网络复杂，需要 TURN 服务器中转媒体流。

## 2. 客户端配置位置

主要配置文件：

```dart
lib/core/app_config.dart
```

### 2.1 后端 API 地址

```dart
static const String apiBase = 'http://139.196.166.181/api';
```

如果后端迁移到新服务器，改成：

```dart
static const String apiBase = 'http://新服务器IP或域名/api';
```

如果使用 HTTPS，建议：

```dart
static const String apiBase = 'https://api.your-domain.com/api';
```

### 2.2 接口签名与 AES 配置

```dart
static const String apiAppKey = '...';
static const String apiSignSecretKey = apiAppKey;
static const String apiAesKey = '...';
static const bool verifyResponseSign = true;
```

这些必须和后端现有接口规则一致。迁移服务器时，如果后端代码和数据库配置不变，一般不需要改。

### 2.3 WebRTC STUN/TURN 配置

```dart
static const List<Map<String, dynamic>> rtcIceServers = [
  {'urls': 'stun:stun.l.google.com:19302'},
  {'urls': 'stun:stun.cloudflare.com:3478'},
];
```

当前默认只配了公共 STUN，适合普通网络测试。商用建议部署 TURN，然后加入：

```dart
{
  'urls': [
    'turn:turn.your-domain.com:3478?transport=udp',
    'turn:turn.your-domain.com:3478?transport=tcp',
    'turns:turn.your-domain.com:5349?transport=tcp',
  ],
  'username': 'imblinlin',
  'credential': '你的TURN密码',
}
```

## 3. 客户端权限

Android 权限文件：

```text
android/app/src/main/AndroidManifest.xml
```

已配置：

```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
```

iOS 权限文件：

```text
ios/Runner/Info.plist
```

已配置：

```xml
<key>NSCameraUsageDescription</key>
<string>用于视频通话和拍摄头像内容</string>
<key>NSMicrophoneUsageDescription</key>
<string>用于语音通话和视频通话</string>
```

## 4. 客户端通话代码位置

- 通话页面：`lib/screens/call_screen.dart`
- 聊天页入口：`lib/screens/chat_screen.dart`
- 悟空 IM 信令分发：`lib/services/im_service.dart`
- 通话 ICE 配置：`lib/core/app_config.dart`

WuKongIM Flutter SDK 1.7.9 监听已在 `ImService` 中统一接入连接状态、新消息、入库消息、刷新消息和 CMD。Web 自动化打包时不要使用不存在的 `RTCPeerConnection.remoteDescription` getter，客户端通过本地 `remoteDescriptionSet` 标记判断 ICE 是否可添加。

聊天页顶部好友状态下会显示：

- 语音通话按钮
- 视频通话按钮

非好友发起通话会提示先添加好友。

## 5. 后端部署位置

当前服务器信息：

```text
服务器：139.196.166.181
后端目录：/www/wwwroot/blinlin
API 文件：/www/wwwroot/blinlin/application/api/controller/Api.php
框架：ThinkPHP
接口路由：/api/:action -> api/api/:action
```

当前已经补过的后端能力：

- `send_message` 支持文本、图片、转账、文件、视频
- 非好友只能发送三条文字
- 非好友不能发送图片、视频、文件、转账
- `search_user` 支持 `keyword/search`，支持按 `id/username/nickname` 搜索
- `get_friends`
- `get_friend_list`
- `is_friend`
- `add_friend`
- `apply_friend`

音视频通话当前主要走客户端悟空 IM 信令，不强依赖后端新增接口。

## 6. 数据库要求

好友关系表：

```sql
CREATE TABLE IF NOT EXISTS `im_friends` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `friend_id` BIGINT UNSIGNED NOT NULL,
  `status` TINYINT NOT NULL DEFAULT 1,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_user_friend` (`user_id`, `friend_id`),
  KEY `idx_friend_user` (`friend_id`, `user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `im_friend_requests` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `from_user_id` BIGINT UNSIGNED NOT NULL,
  `to_user_id` BIGINT UNSIGNED NOT NULL,
  `message` VARCHAR(255) NOT NULL DEFAULT '',
  `status` TINYINT NOT NULL DEFAULT 0,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_to_status` (`to_user_id`, `status`),
  KEY `idx_from_to` (`from_user_id`, `to_user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

消息表字段：当前 ThinkPHP 前缀为 `mr_`，代码里的 `Db::name('messages')` 对应真实表 `mr_messages`。

```sql
ALTER TABLE `mr_messages`
  ADD COLUMN `im_payload` TEXT NULL,
  ADD COLUMN `file_path` VARCHAR(500) NOT NULL DEFAULT '',
  ADD COLUMN `file_name` VARCHAR(255) NOT NULL DEFAULT '';
```

如果新服务器数据库没有 `mr_` 前缀，需要按真实表名调整。

## 7. TURN 服务器部署建议

音视频通话可以部署到其他服务器，推荐把 TURN 独立部署到一台公网服务器。

### 7.1 Ubuntu/Debian 安装 coturn

```bash
sudo apt update
sudo apt install -y coturn
```

### 7.2 开启 coturn 服务

编辑：

```bash
sudo nano /etc/default/coturn
```

设置：

```text
TURNSERVER_ENABLED=1
```

### 7.3 配置 coturn

编辑：

```bash
sudo nano /etc/turnserver.conf
```

示例配置：

```text
listening-port=3478
tls-listening-port=5349
fingerprint
lt-cred-mech
realm=turn.your-domain.com
server-name=turn.your-domain.com
user=imblinlin:强密码
no-multicast-peers
no-cli
```

如果先不用 TLS，可以只开 `3478`。如果使用 `turns:5349`，需要继续配置证书：

```text
cert=/etc/letsencrypt/live/turn.your-domain.com/fullchain.pem
pkey=/etc/letsencrypt/live/turn.your-domain.com/privkey.pem
```

### 7.4 防火墙端口

至少开放：

```text
TCP 3478
UDP 3478
TCP 5349
UDP 49152-65535
```

云服务器安全组也要放行这些端口。

### 7.5 启动服务

```bash
sudo systemctl enable coturn
sudo systemctl restart coturn
sudo systemctl status coturn
```

### 7.6 客户端配置 TURN

修改：

```dart
lib/core/app_config.dart
```

加入：

```dart
{
  'urls': [
    'turn:turn.your-domain.com:3478?transport=udp',
    'turn:turn.your-domain.com:3478?transport=tcp',
  ],
  'username': 'imblinlin',
  'credential': '强密码',
}
```

然后重新构建 APK/IPA。

## 8. 是否可以部署到其他服务器

可以，分两种情况：

### 8.1 只部署 TURN 通话中转服务器

最推荐。后端和悟空 IM 不动，只把 WebRTC 中转能力放到新服务器。

需要你提供：

```text
SSH_HOST=
SSH_PORT=22
SSH_USER=
SSH_PASS= 或 SSH_KEY=
TURN_DOMAIN= 可选
```

我可以帮你：

1. SSH 登录新服务器。
2. 安装 coturn。
3. 配置账号密码。
4. 开放/检查端口。
5. 把 TURN 配置写回 `lib/core/app_config.dart`。
6. 一次性提交客户端配置。

### 8.2 整套后端迁移到新服务器

也可以，但步骤更多。需要迁移：

- ThinkPHP 代码目录 `/www/wwwroot/blinlin`
- `.env` 数据库配置
- MySQL 数据库
- Nginx/Apache 站点配置
- PHP 版本和扩展
- 悟空 IM 服务配置
- 上传目录和静态资源
- 域名/证书

需要你提供：

```text
新服务器 SSH_HOST=
SSH_PORT=22
SSH_USER=
SSH_PASS= 或 SSH_KEY=
域名= 可选
是否迁移数据库= 是/否
是否迁移悟空IM= 是/否
```

迁移后客户端至少要改：

```dart
AppConfig.apiBase
AppConfig.rtcIceServers
```

如果悟空 IM 地址由后端接口返回，客户端可能不用直接改 IM 地址；如果后端配置里写死了悟空 IM 地址，则需要同步改后端配置。

## 9. 构建与验证

客户端依赖更新后执行：

```bash
flutter pub get
flutter analyze
flutter build apk --release
```

通话验证建议：

1. 两台真机登录两个账号。
2. 双方先互加好友。
3. A 给 B 发起语音通话。
4. B 收到来电页并接听。
5. 验证麦克风声音。
6. A 给 B 发起视频通话。
7. 验证摄像头画面、挂断、拒接。
8. 分别测试同 Wi-Fi、4G/5G、跨运营商网络。

如果同 Wi-Fi 可用、4G/跨网不可用，基本就是缺 TURN 或 TURN 端口未放行。

## 10. 注意事项

- 悟空 IM 负责通话信令，不负责传输音视频流。
- WebRTC P2P 在复杂 NAT 下不一定直连成功，商用必须配 TURN。
- TURN 密码不要写太简单，建议使用强密码。
- 如果使用 HTTPS 域名，Android/iOS 权限和 ATS 配置也要同步检查。
- 后端覆盖前必须先备份 `Api.php`，不要直接整站覆盖。
- 多文件客户端修改必须一次 commit 推送，避免触发多轮 Actions。
