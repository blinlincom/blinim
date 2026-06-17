#!/usr/bin/env python3
from pathlib import Path

ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"


def backup(path: Path) -> str:
    dst = path.with_name(f"{path.name}.bak_moments_interactions_20260617")
    if not dst.exists():
        dst.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
    return str(dst)


MOMENTS_BLOCK = r'''
    private function blinEnsureMomentsColumn($column, $ddl)
    {
        try {
            $exists = Db::query("SHOW COLUMNS FROM `mr_im_moments` LIKE '" . addslashes($column) . "'");
            if (!$exists) Db::execute("ALTER TABLE `mr_im_moments` ADD COLUMN " . $ddl);
        } catch (\Exception $e) {}
    }

    private function blinEnsureMomentsTables()
    {
        try {
            Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_moments` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `user_id` int(11) NOT NULL DEFAULT 0, `content` text, `images` mediumtext, `video_url` varchar(500) NOT NULL DEFAULT '', `video_thumb` varchar(500) NOT NULL DEFAULT '', `visibility` varchar(16) NOT NULL DEFAULT 'friends', `like_count` int(11) NOT NULL DEFAULT 0, `comment_count` int(11) NOT NULL DEFAULT 0, `status` tinyint(1) NOT NULL DEFAULT 1, `delete_reason` varchar(500) NOT NULL DEFAULT '', `deleted_by` int(11) NOT NULL DEFAULT 0, `delete_time` datetime DEFAULT NULL, `create_time` datetime DEFAULT NULL, `update_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), KEY `idx_app_time` (`appid`,`status`,`create_time`), KEY `idx_user` (`appid`,`user_id`), KEY `idx_visibility` (`appid`,`status`,`visibility`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
            Db::execute("CREATE TABLE IF NOT EXISTS `im_friends` (`id` bigint(20) unsigned NOT NULL AUTO_INCREMENT, `appid` bigint(20) NOT NULL DEFAULT 0, `user_id` bigint(20) unsigned NOT NULL, `friend_id` bigint(20) unsigned NOT NULL, `status` tinyint(4) NOT NULL DEFAULT 1, `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP, `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (`id`), UNIQUE KEY `uniq_friend_pair` (`user_id`,`friend_id`), KEY `idx_app_user` (`appid`,`user_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
            Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_moment_likes` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `moment_id` int(11) NOT NULL DEFAULT 0, `user_id` int(11) NOT NULL DEFAULT 0, `status` tinyint(1) NOT NULL DEFAULT 1, `create_time` datetime DEFAULT NULL, `update_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), UNIQUE KEY `uk_moment_user` (`appid`,`moment_id`,`user_id`), KEY `idx_user` (`appid`,`user_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
            Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_moment_comments` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `moment_id` int(11) NOT NULL DEFAULT 0, `user_id` int(11) NOT NULL DEFAULT 0, `parent_id` int(11) NOT NULL DEFAULT 0, `reply_user_id` int(11) NOT NULL DEFAULT 0, `content` varchar(1000) NOT NULL DEFAULT '', `status` tinyint(1) NOT NULL DEFAULT 1, `create_time` datetime DEFAULT NULL, `update_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), KEY `idx_moment` (`appid`,`moment_id`,`status`,`id`), KEY `idx_user` (`appid`,`user_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
            Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_moment_notifications` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `moment_id` int(11) NOT NULL DEFAULT 0, `comment_id` int(11) NOT NULL DEFAULT 0, `actor_id` int(11) NOT NULL DEFAULT 0, `receiver_id` int(11) NOT NULL DEFAULT 0, `action` varchar(20) NOT NULL DEFAULT '', `content` varchar(1000) NOT NULL DEFAULT '', `is_read` tinyint(1) NOT NULL DEFAULT 0, `create_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), KEY `idx_receiver` (`appid`,`receiver_id`,`is_read`,`id`), KEY `idx_moment` (`appid`,`moment_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
            $this->blinEnsureMomentsColumn("video_url", "`video_url` varchar(500) NOT NULL DEFAULT '' AFTER `images`");
            $this->blinEnsureMomentsColumn("video_thumb", "`video_thumb` varchar(500) NOT NULL DEFAULT '' AFTER `video_url`");
            $this->blinEnsureMomentsColumn("visibility", "`visibility` varchar(16) NOT NULL DEFAULT 'friends' AFTER `video_thumb`");
            $this->blinEnsureMomentsColumn("delete_reason", "`delete_reason` varchar(500) NOT NULL DEFAULT '' AFTER `status`");
            $this->blinEnsureMomentsColumn("deleted_by", "`deleted_by` int(11) NOT NULL DEFAULT 0 AFTER `delete_reason`");
            $this->blinEnsureMomentsColumn("delete_time", "`delete_time` datetime DEFAULT NULL AFTER `deleted_by`");
            try { Db::execute("ALTER TABLE `mr_im_moments` ADD KEY `idx_visibility` (`appid`,`status`,`visibility`)"); } catch (\Exception $e) {}
        } catch (\Exception $e) {}
    }

    private function blinMomentFriendIds($userId)
    {
        $friendIds = [];
        try {
            $friendIds = Db::table("im_friends")
                ->where("appid", intval($this->appid))
                ->where("user_id", intval($userId))
                ->where("status", 1)
                ->column("friend_id");
        } catch (\Exception $e) {
            $friendIds = [];
        }
        if (!is_array($friendIds)) $friendIds = [];
        $friendIds[] = intval($userId);
        return array_values(array_unique(array_map("intval", $friendIds)));
    }

    private function blinMomentCanView($moment, $userId)
    {
        if (!$moment || intval($moment["appid"]) !== intval($this->appid)) return false;
        if (intval($moment["user_id"]) === intval($userId)) return true;
        if ($this->blinMomentsVisibility() === "all") return true;
        try {
            return !!Db::table("im_friends")
                ->where("appid", intval($this->appid))
                ->where("user_id", intval($userId))
                ->where("friend_id", intval($moment["user_id"]))
                ->where("status", 1)
                ->find();
        } catch (\Exception $e) {
            return false;
        }
    }

    private function blinMomentImages($raw)
    {
        $images = [];
        if (is_array($raw)) $items = $raw;
        else {
            $text = trim(strval($raw));
            if ($text === "") return [];
            $decoded = json_decode($text, true);
            $items = is_array($decoded) ? $decoded : preg_split("/[,，\s]+/", $text);
        }
        foreach ($items as $img) {
            $url = trim(strval($img));
            if ($url !== "") $images[] = $url;
            if (count($images) >= 9) break;
        }
        return $images;
    }

    private function blinMomentCommentRow($row)
    {
        return [
            "id" => intval($row["id"]),
            "moment_id" => intval($row["moment_id"]),
            "user_id" => intval($row["user_id"]),
            "nickname" => trim(strval(isset($row["nickname"]) ? $row["nickname"] : "")) !== "" ? $row["nickname"] : (isset($row["username"]) ? $row["username"] : "用户"),
            "username" => isset($row["username"]) ? $row["username"] : "",
            "avatar" => isset($row["usertx"]) ? $row["usertx"] : "",
            "parent_id" => intval(isset($row["parent_id"]) ? $row["parent_id"] : 0),
            "reply_user_id" => intval(isset($row["reply_user_id"]) ? $row["reply_user_id"] : 0),
            "reply_nickname" => isset($row["reply_nickname"]) ? $row["reply_nickname"] : "",
            "content" => isset($row["content"]) ? $row["content"] : "",
            "create_time" => isset($row["create_time"]) ? $row["create_time"] : "",
        ];
    }

    private function blinMomentNotify($moment, $actorId, $action, $commentId = 0, $content = "", $receiverIds = [])
    {
        $now = date("Y-m-d H:i:s");
        $ids = is_array($receiverIds) ? $receiverIds : [$receiverIds];
        if (!$ids) $ids = [intval($moment["user_id"])];
        $ids = array_values(array_unique(array_map("intval", $ids)));
        foreach ($ids as $receiverId) {
            if ($receiverId <= 0 || $receiverId === intval($actorId)) continue;
            try {
                Db::name("im_moment_notifications")->insert([
                    "appid" => intval($this->appid),
                    "moment_id" => intval($moment["id"]),
                    "comment_id" => intval($commentId),
                    "actor_id" => intval($actorId),
                    "receiver_id" => intval($receiverId),
                    "action" => $action,
                    "content" => mb_substr(trim(strval($content)), 0, 500, "UTF-8"),
                    "is_read" => 0,
                    "create_time" => $now,
                ]);
            } catch (\Exception $e) {}
        }
    }

    public function get_moments_list()
    {
        if (!$this->blinMomentsOpen()) $this->json(0, "朋友圈入口已关闭");
        $this->blinEnsureMomentsTables();
        $user = $this->user_info;
        if (!$user || !isset($user["id"])) $this->json(401, "未登录");
        $page = max(1, intval(input("page") ?: 1));
        $limit = min(50, max(1, intval(input("limit") ?: 20)));
        $visibility = $this->blinMomentsVisibility();
        $query = Db::name("im_moments")->alias("m")
            ->join("user u", "u.id=m.user_id")
            ->where("m.appid", $this->appid)
            ->where("u.appid", $this->appid)
            ->where("m.status", 1);
        if ($visibility !== "all") {
            $query = $query->where("m.user_id", "in", $this->blinMomentFriendIds(intval($user["id"])));
        }
        $rows = $query
            ->field("m.id,m.appid,m.user_id,m.content,m.images,m.video_url,m.video_thumb,m.visibility,m.like_count,m.comment_count,m.create_time,u.username,u.nickname,u.usertx")
            ->order("m.id desc")
            ->page($page, $limit)
            ->select();
        $momentIds = [];
        foreach ($rows as $row) $momentIds[] = intval($row["id"]);
        $likedMap = [];
        $likesMap = [];
        $commentsMap = [];
        if ($momentIds) {
            try {
                $liked = Db::name("im_moment_likes")->where("appid", $this->appid)->where("moment_id", "in", $momentIds)->where("user_id", intval($user["id"]))->where("status", 1)->column("moment_id");
                foreach ($liked as $mid) $likedMap[intval($mid)] = true;
            } catch (\Exception $e) {}
            try {
                $likeRows = Db::name("im_moment_likes")->alias("l")->join("user u", "u.id=l.user_id", "LEFT")->where("l.appid", $this->appid)->where("l.moment_id", "in", $momentIds)->where("l.status", 1)->field("l.moment_id,l.user_id,u.nickname,u.username,u.usertx")->order("l.id asc")->select();
                foreach ($likeRows as $lr) {
                    $mid = intval($lr["moment_id"]);
                    if (!isset($likesMap[$mid])) $likesMap[$mid] = [];
                    if (count($likesMap[$mid]) < 12) $likesMap[$mid][] = ["user_id"=>intval($lr["user_id"]), "nickname"=>trim(strval($lr["nickname"])) !== "" ? $lr["nickname"] : $lr["username"], "avatar"=>isset($lr["usertx"]) ? $lr["usertx"] : ""];
                }
            } catch (\Exception $e) {}
            try {
                $commentRows = Db::name("im_moment_comments")->alias("c")->join("user u", "u.id=c.user_id", "LEFT")->join("user ru", "ru.id=c.reply_user_id", "LEFT")->where("c.appid", $this->appid)->where("c.moment_id", "in", $momentIds)->where("c.status", 1)->field("c.id,c.moment_id,c.user_id,c.parent_id,c.reply_user_id,c.content,c.create_time,u.nickname,u.username,u.usertx,ru.nickname as reply_nickname")->order("c.id asc")->select();
                foreach ($commentRows as $cr) {
                    $mid = intval($cr["moment_id"]);
                    if (!isset($commentsMap[$mid])) $commentsMap[$mid] = [];
                    $commentsMap[$mid][] = $this->blinMomentCommentRow($cr);
                }
            } catch (\Exception $e) {}
        }
        foreach ($rows as $k => $row) {
            $mid = intval($row["id"]);
            $images = $this->blinMomentImages(isset($row["images"]) ? $row["images"] : "");
            $rows[$k]["images"] = $images;
            $rows[$k]["video_url"] = isset($row["video_url"]) ? $row["video_url"] : "";
            $rows[$k]["video_thumb"] = isset($row["video_thumb"]) ? $row["video_thumb"] : "";
            $rows[$k]["avatar"] = isset($row["usertx"]) ? $row["usertx"] : "";
            $rows[$k]["nickname"] = trim(strval(isset($row["nickname"]) ? $row["nickname"] : "")) !== "" ? $row["nickname"] : (isset($row["username"]) ? $row["username"] : "用户");
            $rows[$k]["visibility"] = $this->blinNormalizeMomentsVisibility(isset($row["visibility"]) ? $row["visibility"] : $visibility);
            $rows[$k]["visibility_label"] = $rows[$k]["visibility"] === "all" ? "全员可见" : "仅好友可见";
            $rows[$k]["liked_by_me"] = isset($likedMap[$mid]) ? 1 : 0;
            $rows[$k]["like_users"] = isset($likesMap[$mid]) ? $likesMap[$mid] : [];
            $rows[$k]["comments"] = isset($commentsMap[$mid]) ? $commentsMap[$mid] : [];
            unset($rows[$k]["usertx"]);
        }
        $unread = 0;
        try { $unread = Db::name("im_moment_notifications")->where("appid", $this->appid)->where("receiver_id", intval($user["id"]))->where("is_read", 0)->count(); } catch (\Exception $e) {}
        $this->json(1, "success", ["list"=>$rows, "page"=>$page, "limit"=>$limit, "visibility"=>$visibility, "visibility_label"=>$visibility === "all" ? "全员可见" : "仅好友可见", "unread_count"=>intval($unread)]);
    }

    public function create_moment()
    {
        if (!$this->blinMomentsOpen()) $this->json(0, "朋友圈入口已关闭");
        $this->blinEnsureMomentsTables();
        $user = $this->user_info;
        if (!$user || !isset($user["id"])) $this->json(401, "未登录");
        $content = trim(strval(input("content") ?: input("text") ?: ""));
        $images = $this->blinMomentImages(input("images") ?: "");
        $videoUrl = trim(strval(input("video_url") ?: input("video") ?: ""));
        $videoThumb = trim(strval(input("video_thumb") ?: input("thumb") ?: ""));
        if ($content === "" && !$images && $videoUrl === "") $this->json(0, "请输入朋友圈内容");
        if (mb_strlen($content, "UTF-8") > 2000) $this->json(0, "朋友圈内容过长");
        $visibility = $this->blinMomentsVisibility();
        $now = date("Y-m-d H:i:s");
        $id = Db::name("im_moments")->insertGetId(["appid"=>$this->appid, "user_id"=>intval($user["id"]), "content"=>$content, "images"=>json_encode($images, JSON_UNESCAPED_UNICODE), "video_url"=>$videoUrl, "video_thumb"=>$videoThumb, "visibility"=>$visibility, "like_count"=>0, "comment_count"=>0, "status"=>1, "create_time"=>$now, "update_time"=>$now]);
        $this->json(1, "发布成功", ["id"=>intval($id), "user_id"=>intval($user["id"]), "nickname"=>isset($user["nickname"]) ? $user["nickname"] : $user["username"], "username"=>$user["username"], "avatar"=>isset($user["usertx"]) ? $user["usertx"] : "", "content"=>$content, "images"=>$images, "video_url"=>$videoUrl, "video_thumb"=>$videoThumb, "visibility"=>$visibility, "visibility_label"=>$visibility === "all" ? "全员可见" : "仅好友可见", "like_count"=>0, "comment_count"=>0, "liked_by_me"=>0, "like_users"=>[], "comments"=>[], "create_time"=>$now]);
    }

    public function delete_moment()
    {
        $this->blinEnsureMomentsTables();
        $user = $this->user_info;
        if (!$user || !isset($user["id"])) $this->json(401, "未登录");
        $id = intval(input("id") ?: input("moment_id"));
        if ($id <= 0) $this->json(0, "朋友圈不存在");
        $row = Db::name("im_moments")->where("appid", $this->appid)->where("id", $id)->where("status", 1)->find();
        if (!$row) $this->json(0, "朋友圈不存在");
        if (intval($row["user_id"]) !== intval($user["id"])) $this->json(0, "只能删除自己的朋友圈");
        Db::name("im_moments")->where("id", $id)->update(["status"=>0, "update_time"=>date("Y-m-d H:i:s")]);
        $this->json(1, "已删除");
    }

    public function like_moment()
    {
        if (!$this->blinMomentsOpen()) $this->json(0, "朋友圈入口已关闭");
        $this->blinEnsureMomentsTables();
        $user = $this->user_info;
        if (!$user || !isset($user["id"])) $this->json(401, "未登录");
        $id = intval(input("id") ?: input("moment_id"));
        $moment = Db::name("im_moments")->where("appid", $this->appid)->where("id", $id)->where("status", 1)->find();
        if (!$this->blinMomentCanView($moment, intval($user["id"]))) $this->json(0, "朋友圈不存在");
        $now = date("Y-m-d H:i:s");
        $exists = Db::name("im_moment_likes")->where("appid", $this->appid)->where("moment_id", $id)->where("user_id", intval($user["id"]))->find();
        $liked = false;
        if ($exists && intval($exists["status"]) === 1) {
            Db::name("im_moment_likes")->where("id", intval($exists["id"]))->update(["status"=>0, "update_time"=>$now]);
        } else {
            if ($exists) Db::name("im_moment_likes")->where("id", intval($exists["id"]))->update(["status"=>1, "update_time"=>$now]);
            else Db::name("im_moment_likes")->insert(["appid"=>$this->appid, "moment_id"=>$id, "user_id"=>intval($user["id"]), "status"=>1, "create_time"=>$now, "update_time"=>$now]);
            $liked = true;
            $this->blinMomentNotify($moment, intval($user["id"]), "like", 0, "", [intval($moment["user_id"])]);
        }
        $count = Db::name("im_moment_likes")->where("appid", $this->appid)->where("moment_id", $id)->where("status", 1)->count();
        Db::name("im_moments")->where("id", $id)->update(["like_count"=>intval($count), "update_time"=>$now]);
        $this->json(1, "success", ["liked"=>$liked ? 1 : 0, "like_count"=>intval($count)]);
    }

    public function comment_moment()
    {
        if (!$this->blinMomentsOpen()) $this->json(0, "朋友圈入口已关闭");
        $this->blinEnsureMomentsTables();
        $user = $this->user_info;
        if (!$user || !isset($user["id"])) $this->json(401, "未登录");
        $id = intval(input("id") ?: input("moment_id"));
        $moment = Db::name("im_moments")->where("appid", $this->appid)->where("id", $id)->where("status", 1)->find();
        if (!$this->blinMomentCanView($moment, intval($user["id"]))) $this->json(0, "朋友圈不存在");
        $content = trim(strval(input("content") ?: input("text") ?: ""));
        if ($content === "") $this->json(0, "请输入评论内容");
        if (mb_strlen($content, "UTF-8") > 500) $this->json(0, "评论内容过长");
        $parentId = intval(input("parent_id") ?: input("reply_comment_id"));
        $replyUserId = 0;
        if ($parentId > 0) {
            $parent = Db::name("im_moment_comments")->where("appid", $this->appid)->where("moment_id", $id)->where("id", $parentId)->where("status", 1)->find();
            if ($parent) $replyUserId = intval($parent["user_id"]);
            else $parentId = 0;
        }
        $now = date("Y-m-d H:i:s");
        $commentId = Db::name("im_moment_comments")->insertGetId(["appid"=>$this->appid, "moment_id"=>$id, "user_id"=>intval($user["id"]), "parent_id"=>$parentId, "reply_user_id"=>$replyUserId, "content"=>$content, "status"=>1, "create_time"=>$now, "update_time"=>$now]);
        $count = Db::name("im_moment_comments")->where("appid", $this->appid)->where("moment_id", $id)->where("status", 1)->count();
        Db::name("im_moments")->where("id", $id)->update(["comment_count"=>intval($count), "update_time"=>$now]);
        $receivers = [intval($moment["user_id"])];
        if ($replyUserId > 0) $receivers[] = $replyUserId;
        $this->blinMomentNotify($moment, intval($user["id"]), $replyUserId > 0 ? "reply" : "comment", intval($commentId), $content, $receivers);
        $row = ["id"=>$commentId, "moment_id"=>$id, "user_id"=>intval($user["id"]), "parent_id"=>$parentId, "reply_user_id"=>$replyUserId, "content"=>$content, "create_time"=>$now, "nickname"=>isset($user["nickname"]) ? $user["nickname"] : $user["username"], "username"=>$user["username"], "usertx"=>isset($user["usertx"]) ? $user["usertx"] : "", "reply_nickname"=>""];
        $this->json(1, "评论成功", ["comment"=>$this->blinMomentCommentRow($row), "comment_count"=>intval($count)]);
    }

    public function delete_moment_comment()
    {
        $this->blinEnsureMomentsTables();
        $user = $this->user_info;
        if (!$user || !isset($user["id"])) $this->json(401, "未登录");
        $id = intval(input("id") ?: input("comment_id"));
        $comment = Db::name("im_moment_comments")->where("appid", $this->appid)->where("id", $id)->where("status", 1)->find();
        if (!$comment) $this->json(0, "评论不存在");
        $moment = Db::name("im_moments")->where("appid", $this->appid)->where("id", intval($comment["moment_id"]))->find();
        if (intval($comment["user_id"]) !== intval($user["id"]) && intval($moment["user_id"]) !== intval($user["id"])) $this->json(0, "无权删除该评论");
        Db::name("im_moment_comments")->where("id", $id)->update(["status"=>0, "update_time"=>date("Y-m-d H:i:s")]);
        $count = Db::name("im_moment_comments")->where("appid", $this->appid)->where("moment_id", intval($comment["moment_id"]))->where("status", 1)->count();
        Db::name("im_moments")->where("id", intval($comment["moment_id"]))->update(["comment_count"=>intval($count), "update_time"=>date("Y-m-d H:i:s")]);
        $this->json(1, "已删除", ["comment_count"=>intval($count)]);
    }

    public function get_moment_notifications()
    {
        $this->blinEnsureMomentsTables();
        $user = $this->user_info;
        if (!$user || !isset($user["id"])) $this->json(401, "未登录");
        $page = max(1, intval(input("page") ?: 1));
        $limit = min(50, max(1, intval(input("limit") ?: 20)));
        $rows = Db::name("im_moment_notifications")->alias("n")
            ->join("user u", "u.id=n.actor_id", "LEFT")
            ->join("im_moments m", "m.id=n.moment_id", "LEFT")
            ->where("n.appid", $this->appid)
            ->where("n.receiver_id", intval($user["id"]))
            ->field("n.id,n.moment_id,n.comment_id,n.actor_id,n.action,n.content,n.is_read,n.create_time,u.nickname,u.username,u.usertx,m.content as moment_content")
            ->order("n.id desc")
            ->page($page, $limit)
            ->select();
        foreach ($rows as $k => $row) {
            $rows[$k]["actor_nickname"] = trim(strval(isset($row["nickname"]) ? $row["nickname"] : "")) !== "" ? $row["nickname"] : (isset($row["username"]) ? $row["username"] : "用户");
            $rows[$k]["actor_avatar"] = isset($row["usertx"]) ? $row["usertx"] : "";
            unset($rows[$k]["usertx"]);
        }
        $unread = Db::name("im_moment_notifications")->where("appid", $this->appid)->where("receiver_id", intval($user["id"]))->where("is_read", 0)->count();
        $this->json(1, "success", ["list"=>$rows, "unread_count"=>intval($unread)]);
    }

    public function clear_moment_notifications()
    {
        $this->blinEnsureMomentsTables();
        $user = $this->user_info;
        if (!$user || !isset($user["id"])) $this->json(401, "未登录");
        Db::name("im_moment_notifications")->where("appid", $this->appid)->where("receiver_id", intval($user["id"]))->update(["is_read"=>1]);
        $this->json(1, "已读");
    }

    public function get_moment_unread_count()
    {
        $this->blinEnsureMomentsTables();
        $user = $this->user_info;
        if (!$user || !isset($user["id"])) $this->json(401, "未登录");
        $unread = Db::name("im_moment_notifications")->where("appid", $this->appid)->where("receiver_id", intval($user["id"]))->where("is_read", 0)->count();
        $this->json(1, "success", ["unread_count"=>intval($unread)]);
    }

'''


def main() -> None:
    original = API.read_text(encoding="utf-8")
    start = original.find("    private function blinEnsureMomentsColumn(")
    end = original.find("    //搜索用户接口", start)
    if start < 0 or end < 0:
        raise SystemExit("moments_block_not_found")
    source = original[:start] + MOMENTS_BLOCK + original[end:]
    if source == original:
        print("NO_CHANGE")
        return
    print(f"BACKUP {backup(API)}")
    API.write_text(source, encoding="utf-8")
    print(f"PATCHED {API}")


if __name__ == "__main__":
    main()
