# 音视频通话服务小白部署教程

这份教程用于部署 imblinlin 的语音通话、视频通话网络中转服务。

## 一、先理解这两个服务是什么

imblinlin 的通话由两部分组成：

1. **悟空 IM 信令服务**
   - 负责告诉对方：我要打电话、我接听了、我挂断了。
   - 当前项目已经接好了，不需要在新服务器额外部署。

2. **TURN/STUN 中转服务**
   - 负责帮助两台手机建立 WebRTC 音视频连接。
   - 同 Wi-Fi 下可能不用它也能通。
   - 4G/5G、跨运营商、复杂网络下必须靠它提高成功率。

这次部署到新服务器的是：

```text
coturn = STUN + TURN 服务
服务器 IP = 103.39.221.135
端口 = 3478
账号 = imblinlin
密码 = <TURN_PASSWORD>
```

## 二、已经部署好的服务器信息

```text
服务器：103.39.221.135
系统：Ubuntu 22.04
服务：coturn
配置文件：/etc/turnserver.conf
服务名：coturn
STUN 地址：stun:103.39.221.135:3478
TURN UDP：turn:103.39.221.135:3478?transport=udp
TURN TCP：turn:103.39.221.135:3478?transport=tcp
TURN 用户名：imblinlin
TURN 密码：<TURN_PASSWORD>
```

## 三、客户端已经怎么配置

配置文件：

```text
lib/core/app_config.dart
```

当前已写入：

```dart
static const List<Map<String, dynamic>> rtcIceServers = [
  {'urls': 'stun:103.39.221.135:3478'},
  {
    'urls': [
      'turn:103.39.221.135:3478?transport=udp',
      'turn:103.39.221.135:3478?transport=tcp',
    ],
    'username': 'imblinlin',
    'credential': '<TURN_PASSWORD>',
  },
  {'urls': 'stun:stun.cloudflare.com:3478'},
];
```

也就是说，App 发起语音/视频通话时会优先用 `103.39.221.135` 这台服务器做连接辅助和中转。

## 四、如果你自己从零部署

### 1. 准备服务器

需要一台公网 Linux 服务器，推荐：

```text
Ubuntu 20.04 / 22.04
1 核 1G 以上
有公网 IPv4
能开放端口
```

### 2. SSH 登录服务器

```bash
ssh root@你的服务器IP
```

### 3. 安装 coturn

```bash
apt update -y
apt install -y coturn
```

### 4. 开启 coturn

```bash
cat > /etc/default/coturn <<'EOF'
TURNSERVER_ENABLED=1
EOF
```

### 5. 写入配置

把下面的 `你的服务器IP`、`你的密码` 换成自己的：

```bash
cat > /etc/turnserver.conf <<'EOF'
listening-port=3478
tls-listening-port=5349
listening-ip=0.0.0.0
relay-ip=你的服务器IP
external-ip=你的服务器IP
fingerprint
lt-cred-mech
realm=你的服务器IP
server-name=imblinlin-turn
user=imblinlin:你的密码
min-port=49152
max-port=65535
no-multicast-peers
no-cli
no-tlsv1
no-tlsv1_1
log-file=/var/log/turnserver/turnserver.log
simple-log
EOF
```

### 6. 创建日志目录

```bash
mkdir -p /var/log/turnserver
chown turnserver:turnserver /var/log/turnserver
```

### 7. 开放防火墙

如果服务器用了 `ufw`：

```bash
ufw allow 3478/tcp
ufw allow 3478/udp
ufw allow 5349/tcp
ufw allow 49152:65535/udp
```

如果是云服务器，还要去控制台安全组放行：

```text
TCP 3478
UDP 3478
TCP 5349
UDP 49152-65535
```

最重要的是：`UDP 3478` 和 `UDP 49152-65535`。

### 8. 启动服务

```bash
systemctl enable coturn
systemctl restart coturn
systemctl status coturn
```

看到 `active (running)` 就说明启动成功。

### 9. 检查端口

```bash
ss -lntup | grep 3478
```

能看到 `turnserver` 监听 `3478` 就可以。

## 五、部署到其他服务器可以吗

可以。

如果只是部署音视频通话中转服务，只需要给我：

```text
服务器IP
SSH端口
SSH账号
SSH密码
```

我会做这些事：

1. 登录服务器。
2. 安装 `coturn`。
3. 配置 STUN/TURN。
4. 启动并检查服务。
5. 把新的 TURN 地址写进 `lib/core/app_config.dart`。
6. 一次性提交客户端配置，不浪费 Actions。

如果你还要迁移后端 API、数据库、悟空 IM，那是另一套完整迁移，需要额外确认数据库、域名、证书、后端目录。

## 六、修改客户端到新服务器

如果以后换了 TURN 服务器，只改这个文件：

```text
lib/core/app_config.dart
```

把：

```dart
stun:103.39.221.135:3478
turn:103.39.221.135:3478?transport=udp
turn:103.39.221.135:3478?transport=tcp
```

改成新服务器 IP 或域名即可。

比如：

```dart
static const List<Map<String, dynamic>> rtcIceServers = [
  {'urls': 'stun:新服务器IP:3478'},
  {
    'urls': [
      'turn:新服务器IP:3478?transport=udp',
      'turn:新服务器IP:3478?transport=tcp',
    ],
    'username': 'imblinlin',
    'credential': '你的TURN密码',
  },
];
```

改完后重新构建 APK。

## 七、测试方法

准备两台手机、两个账号：

1. 两个账号互相加好友。
2. A 打开 B 的聊天窗口。
3. 点顶部电话按钮，测试语音通话。
4. B 接听，确认双方能听到声音。
5. 再点视频按钮，测试视频通话。
6. 分别测试：
   - 同一个 Wi-Fi
   - 一个 Wi-Fi，一个 4G/5G
   - 两边都 4G/5G

如果同 Wi-Fi 能通，4G/5G 不稳定，优先检查：

- 云服务器安全组 UDP 端口是否放行。
- `coturn` 是否运行。
- 客户端 `rtcIceServers` 是否写对。

## 八、常用维护命令

查看服务状态：

```bash
systemctl status coturn
```

重启服务：

```bash
systemctl restart coturn
```

查看监听端口：

```bash
ss -lntup | grep turnserver
```

查看日志：

```bash
tail -f /var/log/turnserver/turnserver.log
```

查看配置：

```bash
cat /etc/turnserver.conf
```

## 九、注意事项

- TURN 密码不要太简单，防止别人盗用流量。
- 如果通话人数多，TURN 会消耗服务器带宽。
- `turns:5349` 是 TLS 版本，需要域名和证书；当前先用 `turn:3478`。
- 如果服务器提供商有安全组，Linux 内部放行还不够，安全组也必须放行。
- 悟空 IM 是信令，coturn 是媒体中转，不是同一个东西。
