# 搭个话客户端 UI 设计系统说明

> 本文档只约束 Flutter 客户端 UI / 视觉框架，不改变业务功能、接口、WebRTC、IM、状态机和数据模型。

## 1. 设计定位

搭个话是年轻社区 + IM + 动态流应用。界面目标不是做重装饰，而是：

- 信息流清晰；
- 消息/通话入口稳定可信；
- 业务功能密集但不显得杂乱；
- 支持明暗主题，但不破坏现有业务组件可读性。

## 2. 当前品牌核心

主品牌色保留绿色到青蓝的渐变：

```dart
BlinStyle.brandGradient = [green, cyan, blue]
```

语义：

- green：在线、连接、年轻感；
- cyan：消息、流动、即时通讯；
- blue：稳定、技术感、信任。

## 3. 全局 UI 原则

### 3.1 不动业务逻辑

UI 改造只允许修改：

- 颜色；
- 字体层级；
- 边距；
- 圆角；
- 阴影；
- 组件视觉状态；
- 页面背景与导航外壳。

禁止在 UI 优化中顺手修改：

- API 参数；
- 登录、IM、通话、WebRTC、信令状态机；
- 数据模型字段；
- 页面跳转业务条件；
- 定时器、监听器、ACK/去重逻辑。

### 3.2 产品 UI 优先清晰

本项目业务页面较多，许多旧组件使用 `const TextStyle(color: BlinStyle.ink)`。
因此当前策略是：

- 页面背景可以跟随明暗主题；
- 导航、输入框、按钮支持明暗主题；
- 业务卡片默认保持浅色，以保证旧文本可读；
- 如需完整暗色卡片，需要逐页专项适配文字颜色，不能直接全局切黑。

## 4. 核心文件

### `lib/widgets/blin_style.dart`

统一维护：

- 品牌色；
- 页面背景；
- 通用表面色；
- 边线；
- 阴影；
- `SoftCard`；
- `GradientIcon`；
- `PageBackdrop`。

后续新增 UI 组件优先引用这里，不要在业务页面散落大量硬编码颜色。

### `lib/main.dart`

统一维护 `ThemeData`：

- `TextTheme`；
- `AppBarTheme`；
- `InputDecorationTheme`；
- `NavigationBarThemeData`；
- `FilledButtonThemeData`；
- `OutlinedButtonThemeData`；
- `ChipThemeData`；
- `SnackBarThemeData`；
- `DialogThemeData`；
- `DividerThemeData`。

### `lib/widgets/post_card.dart`

动态流卡片应保持：

- 浅色卡片；
- 信息层级明确；
- 图片/视频圆角统一；
- 操作区弱化；
- 暗色模式下仍保持内容可读。

## 5. 当前已完成的 UI 框架改造

- 调整品牌色为更收敛的 green/cyan/blue；
- 降低卡片阴影强度，避免“AI 感”重阴影；
- 将默认卡片圆角从过大的 24/30+ 收敛到 18/20；
- 统一输入框、按钮、导航、SnackBar、Dialog 视觉；
- 优化 `PageBackdrop` 背景光晕，降低装饰噪声；
- 优化登录页 hero 卡片；
- 优化启动页暗色可读性；
- 给底部导航增加稳定顶部发丝线与背景层；
- 保留业务卡片浅色策略，避免现有 `BlinStyle.ink` 文本在暗色模式不可读。

## 6. 后续建议

如果要继续做完整 UI 升级，建议按页面分阶段：

1. 首页信息流：优化 `_FeedHero`、板块筛选、发布入口；
2. 消息列表：统一会话单元、未读徽标、在线状态；
3. 聊天页：优化气泡、输入区、通话按钮状态；
4. 我的页面：资产卡、功能网格、设置项统一；
5. 通话页：只优化控制按钮和布局，不改 WebRTC 逻辑。

每阶段都应先声明“只改 UI”，再做局部静态 diff，避免误伤业务链路。
