# 音视频功能推翻重来说明

## 1. 本次处理结论

旧版 Flutter 端音视频实现已从前端移除。

本次不是继续修旧 WebRTC 链路，而是清空旧的前端音视频接入，为后续按 `flutter-webrtc` 官方示例重新设计做准备。

## 2. 已删除/禁用的前端音视频内容

旧 `lib/screens/call_screen.dart` 中以下能力已移除：

- `flutter_webrtc` 导入
- `RTCVideoRenderer`
- `RTCVideoView`
- `RTCPeerConnection`
- `MediaStream`
- `getUserMedia`
- 本地摄像头/麦克风采集
- 本地/远端视频渲染
- offer/answer 创建与设置
- ICE candidate 添加与发送
- WebRTC 状态监听
- 旧的远端流聚合逻辑
- 旧的 renderer 布局/重绑/探测逻辑
- 静音、摄像头开关、切换摄像头等旧通话控制逻辑

`pubspec.yaml` 中已移除：

```yaml
flutter_webrtc: ^1.4.1
```

因此当前客户端不会再请求相机/麦克风，也不会建立 WebRTC 连接。

## 3. 保留的后端接口与模型

后端音视频信令接口保留，不删除：

- `lib/models/call_signal.dart`
  - `CallSignal`
  - `CallFlowState`
  - `CallStateMachine`
- `lib/services/api_service.dart`
  - `sendImCallSignal()`
  - `getImCallSignals()`
- `lib/services/im_service.dart`
  - IM 通话信令监听与分发相关逻辑
- `lib/screens/home_screen.dart`
  - 来电信令缓存、补偿轮询、通知、打开通话页的现有逻辑
- `lib/screens/chat_screen.dart`
  - 发起通话入口仍可编译，但会进入占位页

保留这些内容的原因：后续重构仍然复用现有后端通话信令通道，不重新设计后端接口。

## 4. 当前 CallScreen 状态

`lib/screens/call_screen.dart` 现在是占位页，只做三件事：

1. 保留 `CallScreen` 构造参数，避免 Home/Chat 现有导航调用编译失败。
2. 保留 `CallRouteGuard`，避免 HomeScreen 依赖断裂。
3. 展示“音视频已移除，待重构”的说明页面。

它不会做：

- 摄像头采集
- 麦克风采集
- WebRTC PeerConnection
- SDP 信令发送
- ICE 发送/接收
- 视频渲染
- 音频播放

## 5. 后续从零重建原则

后续音视频重新接入时，必须遵循以下原则：

### 5.1 以官方 flutter-webrtc 示例为准

参考项目：

```text
https://github.com/flutter-webrtc/flutter-webrtc
```

重点参考：

```text
example/lib/src/loopback_sample_unified_tracks.dart
example/lib/src/get_user_media_sample.dart
```

重新实现时应优先复刻官方顺序：

1. 初始化 `RTCVideoRenderer`
2. `getUserMedia`
3. `localRenderer.srcObject = localStream` 并在 `setState` 中刷新
4. `createPeerConnection(configuration, constraints)`
5. 添加本地 tracks
6. 设置 `onTrack`
7. 设置 `onIceCandidate`
8. 创建 offer/answer
9. setLocalDescription
10. 通过现有后端接口发送 SDP
11. setRemoteDescription
12. addCandidate
13. `remoteRenderer.srcObject = event.streams[0]` 并在 `setState` 中刷新

### 5.2 前后端边界

后端只负责信令传输：

- invite
- offer
- answer
- ice
- hangup
- reject
- busy
- cancel
- ack

前端负责：

- WebRTC 状态机
- 本地媒体采集
- PeerConnection 生命周期
- Renderer 生命周期
- UI 展示
- 权限申请

### 5.3 禁止带入旧补丁

重构时不要直接恢复旧代码里的以下内容：

- 手动聚合 remote stream
- 以 `videoWidth/videoHeight` 作为是否显示画面的前置条件
- renderer 反复重建兜底
- 手工码率 SDP munging
- 主叫/被叫强制改写
- 多套入口同时处理同一 callId

### 5.4 建议新模块拆分

建议后续新建模块，而不是把所有逻辑堆回 `CallScreen`：

```text
lib/calls/
  call_session.dart          # 单次通话状态与生命周期
  call_signaling_adapter.dart # 适配现有 sendImCallSignal/getImCallSignals/im.calls
  call_media_engine.dart      # flutter-webrtc 采集/PeerConnection/Renderer
  call_models.dart            # 前端内部状态模型
  call_screen.dart            # UI 层
```

也可以先保留现有路径 `lib/screens/call_screen.dart`，但内部应拆出 engine 和 signaling adapter。

## 6. 重构验收标准

第一阶段只做官方 demo 级别最小闭环：

- A 能看到自己本地画面
- B 能看到自己本地画面
- A 呼叫 B，双方都能看到对方画面
- B 呼叫 A，双方都能看到对方画面
- 挂断能释放摄像头/麦克风
- 重新拨打不会复用旧 PeerConnection/Renderer

第二阶段再加：

- 通话通知
- 后台来电
- 忙线
- 取消
- 拒绝
- 超时
- 静音
- 摄像头开关
- 切换摄像头
- 蓝牙/扬声器

## 7. 当前注意事项

当前版本音视频功能不可用，这是刻意行为。

聊天、图片、普通 IM、后端通话信令模型仍然保留。

下一次重建时，应从官方最小 demo 接入开始，不要直接恢复旧版复杂通话页。
