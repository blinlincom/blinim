#!/usr/bin/env python3
"""Add group notice enable switch and rich-text payload support."""

from datetime import datetime
from pathlib import Path
import shutil


ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"
TRAIT = ROOT / "application/api/controller/traits/ImApiTrait.php"


def backup(path, suffix):
    target = path.with_name(
        "%s.bak_%s_%s" % (path.name, suffix, datetime.now().strftime("%Y%m%d%H%M%S"))
    )
    shutil.copy2(path, target)
    print("PATCH_BACKUP", target)


def save(path, original, source, suffix):
    if source == original:
        return False
    backup(path, suffix)
    path.write_text(source)
    print("PATCHED", path)
    return True


def patch_file(path, suffix):
    source = path.read_text(errors="ignore")
    original = source

    if "ADD COLUMN `notice_enabled`" not in source:
        source = source.replace(
            "$this->blinAddColumnIfMissing('mr_im_groups', 'admin_notice_enabled', \"ALTER TABLE `mr_im_groups` ADD COLUMN `admin_notice_enabled` tinyint(1) NOT NULL DEFAULT 1 AFTER `qr_enabled`\");",
            "$this->blinAddColumnIfMissing('mr_im_groups', 'notice_enabled', \"ALTER TABLE `mr_im_groups` ADD COLUMN `notice_enabled` tinyint(1) NOT NULL DEFAULT 1 AFTER `notice`\");\n        $this->blinAddColumnIfMissing('mr_im_groups', 'notice_rich_text', \"ALTER TABLE `mr_im_groups` ADD COLUMN `notice_rich_text` mediumtext NULL AFTER `notice_enabled`\");\n        $this->blinAddColumnIfMissing('mr_im_groups', 'admin_notice_enabled', \"ALTER TABLE `mr_im_groups` ADD COLUMN `admin_notice_enabled` tinyint(1) NOT NULL DEFAULT 1 AFTER `qr_enabled`\");",
            1,
        )

    if "$noticeRich = $this->blinGroupUpdateValue" not in source:
        source = source.replace(
            '''        $notice = $this->blinGroupUpdateValue($data, ["notice", "announcement", "group_notice"]);
        if ($notice !== null) {
            if (!$isOwner && !(intval(isset($group["admin_notice_enabled"]) ? $group["admin_notice_enabled"] : 1) === 1 && $canManage)) $this->json(0, "没有公告编辑权限");
            $update["notice"] = $notice;
        }''',
            '''        $notice = $this->blinGroupUpdateValue($data, ["notice", "announcement", "group_notice"]);
        if ($notice !== null) {
            if (!$isOwner && !(intval(isset($group["admin_notice_enabled"]) ? $group["admin_notice_enabled"] : 1) === 1 && $canManage)) $this->json(0, "没有公告编辑权限");
            if (mb_strlen($notice, "UTF-8") > 5000) $this->json(0, "群公告内容过长");
            $update["notice"] = $notice;
        }
        $noticeRich = $this->blinGroupUpdateValue($data, ["notice_rich_text", "notice_rich", "notice_html", "notice_delta"]);
        if ($noticeRich !== null) {
            if (!$isOwner && !(intval(isset($group["admin_notice_enabled"]) ? $group["admin_notice_enabled"] : 1) === 1 && $canManage)) $this->json(0, "没有公告编辑权限");
            if (strlen($noticeRich) > 65535) $this->json(0, "群公告富文本内容过长");
            $update["notice_rich_text"] = $noticeRich;
        }
        $noticeEnabled = $this->blinGroupBoolValue($data, ["notice_enabled", "group_notice_enabled", "announcement_enabled"]);
        if ($noticeEnabled !== null) {
            if (!$isOwner) $this->json(0, "只有群主可以设置群公告开关");
            $update["notice_enabled"] = $noticeEnabled;
        }''',
            1,
        )

    if "$group = Db::name(\"im_groups\")->where(\"appid\", $this->appid)->where(\"id\", $groupId)->find();" in source:
        source = source.replace(
            "$group = Db::name(\"im_groups\")->where(\"appid\", $this->appid)->where(\"id\", $groupId)->find();\n        $this->json(1, \"更新成功\", $group ?: []);",
            "$group = Db::name(\"im_groups\")->where(\"appid\", $this->appid)->where(\"id\", $groupId)->find();\n        if ($group) $group[\"group_id\"] = intval($group[\"id\"]);\n        $this->json(1, \"更新成功\", $group ?: []);",
            1,
        )

    if "$group = Db::name('im_groups')->where('appid', $this->appid)->where('id', $groupId)->find();" in source:
        source = source.replace(
            "$group = Db::name('im_groups')->where('appid', $this->appid)->where('id', $groupId)->find();\n        $this->json(1, \"更新成功\", $group ?: []);",
            "$group = Db::name('im_groups')->where('appid', $this->appid)->where('id', $groupId)->find();\n        if ($group) $group[\"group_id\"] = intval($group[\"id\"]);\n        $this->json(1, \"更新成功\", $group ?: []);",
            1,
        )

    return save(path, original, source, suffix)


def main():
    changed = patch_file(API, "group_notice_rich_api")
    changed = patch_file(TRAIT, "group_notice_rich_trait") or changed
    print("PATCHED_GROUP_NOTICE_RICH_TEXT" if changed else "GROUP_NOTICE_RICH_TEXT_ALREADY_UP_TO_DATE")


if __name__ == "__main__":
    main()
