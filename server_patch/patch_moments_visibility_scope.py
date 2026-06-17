#!/usr/bin/env python3
"""Add per-moment WeChat-style visibility scopes."""

from datetime import datetime
from pathlib import Path
import shutil


ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"


def backup(path: Path) -> None:
    target = path.with_name(
        f"{path.name}.bak_moments_visibility_scope_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    shutil.copy2(path, target)
    print("BACKUP", target)


def replace_once(source: str, old: str, new: str, marker: str) -> str:
    if new in source:
        return source
    if old not in source:
        raise SystemExit(f"{marker}_NOT_FOUND")
    return source.replace(old, new, 1)


def main() -> None:
    source = API.read_text(encoding="utf-8", errors="ignore")
    original = source

    source = replace_once(
        source,
        '''        return in_array($visibility, ["all", "friends"]) ? $visibility : "friends";
    }

    private function blinMomentsVisibility()
''',
        '''        return in_array($visibility, ["all", "friends"]) ? $visibility : "friends";
    }

    private function blinMomentVisibilityType($type)
    {
        $type = strtolower(trim(strval($type)));
        if ($type === "all") return "public";
        if ($type === "self") return "private";
        return in_array($type, ["public", "friends", "include", "exclude", "private"]) ? $type : "friends";
    }

    private function blinMomentIdList($raw)
    {
        $ids = [];
        if (is_array($raw)) $items = $raw;
        else {
            $text = trim(strval($raw));
            if ($text === "") return [];
            $decoded = json_decode($text, true);
            $items = is_array($decoded) ? $decoded : preg_split("/[,，\\s]+/", $text);
        }
        foreach ($items as $item) {
            $id = intval($item);
            if ($id > 0) $ids[] = $id;
            if (count($ids) >= 500) break;
        }
        return array_values(array_unique($ids));
    }

    private function blinMomentScopeAllows($moment, $viewerId)
    {
        $ownerId = intval(isset($moment["user_id"]) ? $moment["user_id"] : 0);
        $viewerId = intval($viewerId);
        if ($ownerId <= 0 || $viewerId <= 0) return false;
        if ($ownerId === $viewerId) return true;
        $type = $this->blinMomentVisibilityType(isset($moment["visibility_type"]) ? $moment["visibility_type"] : (isset($moment["visibility"]) ? $moment["visibility"] : "friends"));
        if ($type === "private") return false;
        if ($type === "include") {
            return in_array($viewerId, $this->blinMomentIdList(isset($moment["visible_user_ids"]) ? $moment["visible_user_ids"] : ""), true);
        }
        if ($type === "exclude") {
            return !in_array($viewerId, $this->blinMomentIdList(isset($moment["hidden_user_ids"]) ? $moment["hidden_user_ids"] : ""), true);
        }
        if ($type === "public") return true;
        return true;
    }

    private function blinMomentVisibilityLabel($type)
    {
        $type = $this->blinMomentVisibilityType($type);
        if ($type === "public") return "公开";
        if ($type === "include") return "部分可见";
        if ($type === "exclude") return "部分不可见";
        if ($type === "private") return "仅自己可见";
        return "仅好友可见";
    }

    private function blinMomentsVisibility()
''',
        "MOMENT_VISIBILITY_HELPERS",
    )

    source = replace_once(
        source,
        '''            $this->blinEnsureMomentsColumn("visibility", "`visibility` varchar(16) NOT NULL DEFAULT 'friends' AFTER `video_thumb`");
            $this->blinEnsureMomentsColumn("delete_reason", "`delete_reason` varchar(500) NOT NULL DEFAULT '' AFTER `status`");
''',
        '''            $this->blinEnsureMomentsColumn("visibility", "`visibility` varchar(16) NOT NULL DEFAULT 'friends' AFTER `video_thumb`");
            $this->blinEnsureMomentsColumn("visibility_type", "`visibility_type` varchar(16) NOT NULL DEFAULT 'friends' AFTER `visibility`");
            $this->blinEnsureMomentsColumn("visible_user_ids", "`visible_user_ids` mediumtext AFTER `visibility_type`");
            $this->blinEnsureMomentsColumn("hidden_user_ids", "`hidden_user_ids` mediumtext AFTER `visible_user_ids`");
            $this->blinEnsureMomentsColumn("delete_reason", "`delete_reason` varchar(500) NOT NULL DEFAULT '' AFTER `status`");
''',
        "MOMENT_TABLE_COLUMNS",
    )

    source = replace_once(
        source,
        '''        if ($this->blinMomentsVisibility() === "all") return true;
        try {
            return !!Db::table("im_friends")
''',
        '''        if (!$this->blinMomentScopeAllows($moment, $userId)) return false;
        if ($this->blinMomentsVisibility() === "all") return true;
        $type = $this->blinMomentVisibilityType(isset($moment["visibility_type"]) ? $moment["visibility_type"] : (isset($moment["visibility"]) ? $moment["visibility"] : "friends"));
        if ($type === "public" || $type === "exclude" || $type === "include") return true;
        try {
            return !!Db::table("im_friends")
''',
        "MOMENT_CAN_VIEW_SCOPE",
    )

    source = replace_once(
        source,
        '''            ->field("m.id,m.appid,m.user_id,m.content,m.images,m.video_url,m.video_thumb,m.visibility,m.like_count,m.comment_count,m.create_time,u.username,u.nickname,u.usertx")
''',
        '''            ->field("m.id,m.appid,m.user_id,m.content,m.images,m.video_url,m.video_thumb,m.visibility,m.visibility_type,m.visible_user_ids,m.hidden_user_ids,m.like_count,m.comment_count,m.create_time,u.username,u.nickname,u.usertx")
''',
        "MOMENT_LIST_FIELDS",
    )

    source = replace_once(
        source,
        '''        foreach ($rows as $k => $row) {
            $mid = intval($row["id"]);
            $images = $this->blinMomentImages(isset($row["images"]) ? $row["images"] : "");
            $rows[$k]["images"] = $images;
''',
        '''        $filteredRows = [];
        foreach ($rows as $row) {
            if ($this->blinMomentCanView($row, intval($user["id"]))) $filteredRows[] = $row;
        }
        $rows = $filteredRows;
        foreach ($rows as $k => $row) {
            $mid = intval($row["id"]);
            $images = $this->blinMomentImages(isset($row["images"]) ? $row["images"] : "");
            $rows[$k]["images"] = $images;
''',
        "MOMENT_LIST_FILTER",
    )

    source = replace_once(
        source,
        '''            $rows[$k]["visibility"] = $this->blinNormalizeMomentsVisibility(isset($row["visibility"]) ? $row["visibility"] : $visibility);
            $rows[$k]["visibility_label"] = $rows[$k]["visibility"] === "all" ? "全员可见" : "仅好友可见";
''',
        '''            $rows[$k]["visibility"] = $this->blinNormalizeMomentsVisibility(isset($row["visibility"]) ? $row["visibility"] : $visibility);
            $rows[$k]["visibility_type"] = $this->blinMomentVisibilityType(isset($row["visibility_type"]) ? $row["visibility_type"] : $rows[$k]["visibility"]);
            $rows[$k]["visible_user_ids"] = $this->blinMomentIdList(isset($row["visible_user_ids"]) ? $row["visible_user_ids"] : "");
            $rows[$k]["hidden_user_ids"] = $this->blinMomentIdList(isset($row["hidden_user_ids"]) ? $row["hidden_user_ids"] : "");
            $rows[$k]["visibility_label"] = $this->blinMomentVisibilityLabel($rows[$k]["visibility_type"]);
''',
        "MOMENT_LIST_VISIBILITY_FIELDS",
    )

    source = replace_once(
        source,
        '''        $visibility = $this->blinMomentsVisibility();
        $now = date("Y-m-d H:i:s");
        $id = Db::name("im_moments")->insertGetId(["appid"=>$this->appid, "user_id"=>intval($user["id"]), "content"=>$content, "images"=>json_encode($images, JSON_UNESCAPED_UNICODE), "video_url"=>$videoUrl, "video_thumb"=>$videoThumb, "visibility"=>$visibility, "like_count"=>0, "comment_count"=>0, "status"=>1, "create_time"=>$now, "update_time"=>$now]);
        $this->json(1, "发布成功", ["id"=>intval($id), "user_id"=>intval($user["id"]), "nickname"=>isset($user["nickname"]) ? $user["nickname"] : $user["username"], "username"=>$user["username"], "avatar"=>isset($user["usertx"]) ? $user["usertx"] : "", "content"=>$content, "images"=>$images, "video_url"=>$videoUrl, "video_thumb"=>$videoThumb, "visibility"=>$visibility, "visibility_label"=>$visibility === "all" ? "全员可见" : "仅好友可见", "like_count"=>0, "comment_count"=>0, "liked_by_me"=>0, "like_users"=>[], "comments"=>[], "create_time"=>$now]);
''',
        '''        $globalVisibility = $this->blinMomentsVisibility();
        $visibilityType = $this->blinMomentVisibilityType(input("visibility_type") ?: input("moment_visibility") ?: $globalVisibility);
        $visibleUserIds = $this->blinMomentIdList(input("visible_user_ids") ?: input("allow_user_ids") ?: "");
        $hiddenUserIds = $this->blinMomentIdList(input("hidden_user_ids") ?: input("deny_user_ids") ?: "");
        if ($globalVisibility !== "all" && $visibilityType === "public") $visibilityType = "friends";
        if ($visibilityType === "include" && !$visibleUserIds) $this->json(0, "请选择可见好友");
        if ($visibilityType === "exclude" && !$hiddenUserIds) $this->json(0, "请选择不可见好友");
        $visibility = $visibilityType === "public" ? "all" : "friends";
        $now = date("Y-m-d H:i:s");
        $id = Db::name("im_moments")->insertGetId(["appid"=>$this->appid, "user_id"=>intval($user["id"]), "content"=>$content, "images"=>json_encode($images, JSON_UNESCAPED_UNICODE), "video_url"=>$videoUrl, "video_thumb"=>$videoThumb, "visibility"=>$visibility, "visibility_type"=>$visibilityType, "visible_user_ids"=>json_encode($visibleUserIds, JSON_UNESCAPED_UNICODE), "hidden_user_ids"=>json_encode($hiddenUserIds, JSON_UNESCAPED_UNICODE), "like_count"=>0, "comment_count"=>0, "status"=>1, "create_time"=>$now, "update_time"=>$now]);
        $this->json(1, "发布成功", ["id"=>intval($id), "user_id"=>intval($user["id"]), "nickname"=>isset($user["nickname"]) ? $user["nickname"] : $user["username"], "username"=>$user["username"], "avatar"=>isset($user["usertx"]) ? $user["usertx"] : "", "content"=>$content, "images"=>$images, "video_url"=>$videoUrl, "video_thumb"=>$videoThumb, "visibility"=>$visibility, "visibility_type"=>$visibilityType, "visible_user_ids"=>$visibleUserIds, "hidden_user_ids"=>$hiddenUserIds, "visibility_label"=>$this->blinMomentVisibilityLabel($visibilityType), "like_count"=>0, "comment_count"=>0, "liked_by_me"=>0, "like_users"=>[], "comments"=>[], "create_time"=>$now]);
''',
        "MOMENT_CREATE_SCOPE",
    )

    if source == original:
        print("NO_CHANGE", API)
        return
    backup(API)
    API.write_text(source, encoding="utf-8")
    print("PATCHED", API)


if __name__ == "__main__":
    main()
