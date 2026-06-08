# 社区板块与发帖接口变更记录

更新时间：2026-06-08

## 背景

社区板块分为一级板块和二级板块。之前存在几个问题：

1. 后台创建一级板块时会自动生成“默认版块/默认二级板块”。
2. 客户端和后台发帖逻辑混乱：有时只能选子板块，有时又直接传一级板块。
3. 首页板块展示和发帖目标选择规则不统一。

本次调整后，板块和发帖逻辑统一为以下规则。

---

## 一、板块创建规则

### 后台新增一级板块

修改文件：

```text
/application/admin/controller/Forum.php
```

调整内容：

```text
新增一级板块时，不再自动创建“默认版块/默认二级板块”。
```

现在后台可以：

```text
1. 只创建一级板块，不创建二级板块。
2. 在一级板块下面手动添加二级板块。
```

---

## 二、发帖目标规则

### 规则 1：没有二级板块的一级板块

允许直接发帖到一级板块。

客户端/API 参数：

```text
sectionid = 一级板块ID
不传 subsectionid
```

数据库落库逻辑：

```text
section_id = 一级板块ID
sub_section_id = 一级板块ID
```

说明：

因为原数据表仍然有 `sub_section_id` 字段，为兼容旧查询和旧 join，直接发布到一级板块时，`sub_section_id` 也写一级板块 ID。

---

### 规则 2：有二级板块的一级板块

不允许直接发帖到一级板块，必须选择具体二级板块。

客户端/API 参数：

```text
sectionid = 父级一级板块ID
subsectionid = 二级板块ID
```

数据库落库逻辑：

```text
section_id = 父级一级板块ID
sub_section_id = 二级板块ID
```

如果只传 `sectionid`，且该一级板块存在二级板块，后端会拒绝发布。

错误提示：

```text
该一级板块包含二级板块，请选择具体二级板块发帖
```

---

## 三、客户端接口调用变更

修改文件：

```text
lib/services/api_service.dart
```

### 发帖接口

接口：

```text
POST /post
```

方法：

```dart
Future<String> publishPost(
  String token, {
  required String sectionId,
  String subsectionId = '',
  required String title,
  required String content,
  String video = '',
  String videoCover = '',
})
```

请求参数：

```text
usertoken: 用户 token
sectionid: 一级板块 ID
subsectionid: 二级板块 ID，可选
title: 标题
content: 内容
paid_reading: 0
file_download_method: 0
video: 视频链接，可选
video_img: 视频封面链接，可选
```

调用规则：

```text
没有二级板块的一级板块：
  sectionid = 一级板块ID
  subsectionid 不传

二级板块：
  sectionid = 父级一级板块ID
  subsectionid = 二级板块ID
```

---

## 四、客户端发布页选择规则

修改文件：

```text
lib/screens/home_screen.dart
```

发布页展示的是“可发帖目标列表”，不是原始一级板块列表。

规则：

```text
1. 如果一级板块没有 sub_section：
   展示该一级板块，可直接发帖。

2. 如果一级板块存在 sub_section：
   不展示该一级板块为可发帖项；
   展示它下面的每个二级板块。
```

客户端选择二级板块时，会自动保存：

```text
sectionId = 父级一级板块ID
subsectionId = 二级板块ID
```

---

## 五、首页板块展示规则

修改文件：

```text
lib/screens/home_screen.dart
```

首页频道展示规则：

```text
推荐 + 没有二级板块的一级板块
```

也就是：

```text
带 sub_section 的一级板块不在首页频道展示。
```

原因：

当前产品规则下，带二级板块的一级板块只是一个分组容器，不作为首页直接筛选频道展示。

---

## 六、后端接口/API 规则变更

修改文件：

```text
/application/api/controller/Api.php
```

接口：

```text
/post
```

新增规则：

```text
如果传入的 sectionid 是一级板块，且该一级板块存在二级板块，同时没有传 subsectionid，则拒绝发帖。
```

拒绝提示：

```text
该一级板块包含二级板块，请选择具体二级板块发帖
```

兼容规则：

```text
1. 传 subsectionid：
   认为用户选择的是二级板块。
   后端自动把 section_id 写为其父级一级板块 ID。

2. 不传 subsectionid：
   认为用户选择的是一级板块。
   如果该一级板块没有二级板块，则允许发布。
   如果该一级板块有二级板块，则拒绝发布。
```

---

## 七、后台新增帖子规则变更

修改文件：

```text
/application/admin/controller/Forum.php
/application/admin/view/forum/edit_section_post.html
```

后台新增帖子页面中：

```text
子版块改为可选。
```

文案：

```text
请选择子版块（可选，不选则直接发布到一级版块）
```

但是后台控制器会继续校验：

```text
如果一级板块存在二级板块，则必须选择具体二级板块。
如果一级板块不存在二级板块，则可以不选子板块。
```

---

## 八、当前相关提交

客户端相关提交：

```text
da5772bea1073fce4bdc018e8545a55ed917b41e
```

该提交包含：

```text
lib/screens/home_screen.dart
lib/services/api_service.dart
```

---

## 九、测试建议

### 测试 1：一级板块无二级板块

步骤：

```text
1. 后台创建一级板块 A，不添加二级板块。
2. 客户端发布页选择 A。
3. 发布帖子。
```

预期：

```text
发布成功。
帖子 section_id = A
帖子 sub_section_id = A
首页频道显示 A。
```

---

### 测试 2：一级板块有二级板块

步骤：

```text
1. 后台创建一级板块 B。
2. 在 B 下创建二级板块 B1。
3. 客户端发布页选择 B1。
4. 发布帖子。
```

预期：

```text
发布成功。
帖子 section_id = B
帖子 sub_section_id = B1
首页频道不直接显示 B。
```

---

### 测试 3：错误发布场景

步骤：

```text
直接调用 /post，只传有二级板块的一级板块 B：
sectionid = B
不传 subsectionid
```

预期：

```text
发布失败。
返回：该一级板块包含二级板块，请选择具体二级板块发帖
```
