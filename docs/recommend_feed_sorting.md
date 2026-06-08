# 推荐流排序接口说明

更新时间：2026-06-08

## 背景

首页「推荐」不能简单等同于全部帖子按发布时间展示。推荐流需要综合后台已有数据，优先展示更有价值的帖子。

本次调整不改数据库结构，不新增字段，不执行 SQL，只调整 `/get_posts_list` 的默认排序策略和客户端请求参数。

---

## 一、涉及接口

```text
POST /api/get_posts_list
```

客户端封装：

```text
lib/services/api_service.dart
getForumPosts()
```

后端文件：

```text
/application/api/controller/Api.php
get_posts_list()
```

---

## 二、推荐排序策略

推荐流默认排序调整为：

```text
sticky desc
featured desc
popular desc
score desc
create_time desc
```

含义：

```text
1. sticky：置顶帖优先
2. featured：精华帖优先
3. popular：热门帖优先
4. score：综合分高的优先
5. create_time：同权重下新帖优先
```

---

## 三、score 综合分来源

当前后端已有 `score` 字段，不新增数据库字段。

后端在帖子详情相关逻辑中会根据互动数据计算并回写：

```text
score = 浏览量 * 0.4 + 点赞量 * 0.3 + 评论量 * 0.3
```

涉及数据：

```text
浏览量
点赞量
评论量
```

说明：

```text
score 是已有字段，本次只使用它参与排序，不改变表结构。
```

---

## 四、客户端请求参数

客户端请求推荐流时传：

```text
sort = sticky,featured,popular,score,create_time
sortOrder = desc,desc,desc,desc,desc
```

代码位置：

```text
lib/services/api_service.dart
getForumPosts()
```

---

## 五、后端默认排序兜底

即使客户端不传 `sort` / `sortOrder`，后端 `/get_posts_list` 默认也会使用：

```text
sticky,featured,popular,score,create_time
```

对应排序：

```text
desc,desc,desc,desc,desc
```

这样可以保证其他客户端或旧版本客户端调用接口时，也能得到推荐排序。

---

## 六、数据库影响

本次调整：

```text
不新增表
不新增字段
不修改字段类型
不执行 SQL
不直接改数据库数据
```

唯一间接影响：

```text
接口返回帖子顺序变化。
```

---

## 七、测试建议

### 测试 1：置顶优先

后台设置一个帖子为置顶。

预期：

```text
该帖子在推荐流靠前展示。
```

### 测试 2：精华优先

后台设置一个帖子为精华。

预期：

```text
在非置顶帖子中，精华帖优先。
```

### 测试 3：热门优先

后台设置热门帖。

预期：

```text
在置顶、精华排序之后，热门帖优先。
```

### 测试 4：综合分优先

增加帖子浏览、点赞、评论数据。

预期：

```text
score 更高的帖子优先。
```

### 测试 5：同权重新帖优先

如果多个帖子以上权重相同。

预期：

```text
create_time 新的帖子优先。
```