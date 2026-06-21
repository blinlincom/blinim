#!/usr/bin/env python3
from pathlib import Path


API = Path("/www/wwwroot/blinlin/application/api/controller/Api.php")
TRAIT = Path("/www/wwwroot/blinlin/application/api/controller/traits/ImApiTrait.php")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"missing marker: {label}")
    return text.replace(old, new, 1)


def ensure_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    return replace_once(text, old, new, label)


def patch_api() -> None:
    path = API
    text = path.read_text(encoding="utf-8")
    if "blinRefreshGroupAvatarIfNeeded" in text:
        text = ensure_once(
            text,
            "        $this->ensure_im_group_tables();\n        if ($this->blinDefaultGroupNeeded()) {\n",
            "        $this->ensure_im_group_tables();\n        $this->blinEnsureGroupFeatureColumns();\n        if ($this->blinDefaultGroupNeeded()) {\n",
            "api group list ensure feature columns",
        )
        path.write_text(text, encoding="utf-8")
        return

    text = ensure_once(
        text,
        "        $this->ensure_im_group_tables();\n        if ($this->blinDefaultGroupNeeded()) {\n",
        "        $this->ensure_im_group_tables();\n        $this->blinEnsureGroupFeatureColumns();\n        if ($this->blinDefaultGroupNeeded()) {\n",
        "api group list ensure feature columns",
    )

    text = replace_once(
        text,
        "        $this->blinAddColumnIfMissing('mr_im_groups', 'screenshot_notify_enabled', \"ALTER TABLE `mr_im_groups` ADD COLUMN `screenshot_notify_enabled` tinyint(1) NOT NULL DEFAULT 0 AFTER `notice_pinned`\");\n",
        "        $this->blinAddColumnIfMissing('mr_im_groups', 'screenshot_notify_enabled', \"ALTER TABLE `mr_im_groups` ADD COLUMN `screenshot_notify_enabled` tinyint(1) NOT NULL DEFAULT 0 AFTER `notice_pinned`\");\n"
        "        $this->blinAddColumnIfMissing('mr_im_groups', 'avatar_signature', \"ALTER TABLE `mr_im_groups` ADD COLUMN `avatar_signature` varchar(64) NOT NULL DEFAULT '' AFTER `avatar`\");\n",
        "api feature column",
    )

    text = replace_once(
        text,
        '->field("g.id,g.id as group_id,g.group_no,g.name,g.avatar,g.notice,g.owner_id,g.member_count,g.default_group,g.update_time,m.role")',
        '->field("g.id,g.id as group_id,g.group_no,g.name,g.avatar,g.avatar_signature,g.notice,g.owner_id,g.member_count,g.default_group,g.update_time,m.role")',
        "api group list field",
    )
    text = replace_once(
        text,
        '        foreach ($rows as $k=>$v) {\n            $rows[$k]["my_role"] = $this->im_group_role_name($v["role"]);\n',
        '        foreach ($rows as $k=>$v) {\n'
        '            $rows[$k]["avatar"] = $this->blinRefreshGroupAvatarIfNeeded($v);\n'
        '            if (isset($rows[$k]["avatar_signature"])) unset($rows[$k]["avatar_signature"]);\n'
        '            $rows[$k]["my_role"] = $this->im_group_role_name($v["role"]);\n',
        "api group list refresh",
    )
    text = replace_once(
        text,
        '        $group["group_id"] = intval($group["id"]);\n        $group["my_role"] = $this->im_group_role_name($member["role"]);\n',
        '        $group["avatar"] = $this->blinRefreshGroupAvatarIfNeeded($group);\n'
        '        if (isset($group["avatar_signature"])) unset($group["avatar_signature"]);\n'
        '        $group["group_id"] = intval($group["id"]);\n'
        '        $group["my_role"] = $this->im_group_role_name($member["role"]);\n',
        "api group info refresh",
    )

    api_helpers = '''

    private function blinEnsureGroupAvatarSignatureColumn()
    {
        $this->blinAddColumnIfMissing('mr_im_groups', 'avatar_signature', "ALTER TABLE `mr_im_groups` ADD COLUMN `avatar_signature` varchar(64) NOT NULL DEFAULT '' AFTER `avatar`");
    }

    private function blinGroupAvatarMemberSignature($groupId)
    {
        try {
            $rows = Db::name("im_group_members")->alias("m")
                ->join("user u", "u.id=m.user_id")
                ->where("m.appid", $this->appid)
                ->where("m.group_id", intval($groupId))
                ->where("m.status", 1)
                ->where("u.appid", $this->appid)
                ->field("u.id,u.usertx")
                ->order("m.role desc,m.id asc")
                ->limit(9)
                ->select();
            if (!$rows) return "";
            $parts = [];
            foreach ($rows as $row) {
                $parts[] = intval($row["id"]) . ":" . trim(strval(isset($row["usertx"]) ? $row["usertx"] : ""));
            }
            return md5(implode("|", $parts));
        } catch (\\Exception $e) {
            return "";
        }
    }

    private function blinRefreshGroupAvatarIfNeeded($group)
    {
        if (!$group || !isset($group["id"])) return "";
        $avatar = trim(strval(isset($group["avatar"]) ? $group["avatar"] : ""));
        if (!$this->blinGroupAvatarCollageEnabled()) return $avatar;
        if (!$this->blinIsGeneratedGroupAvatar($avatar) && !$this->blinIsSystemDefaultAvatar($avatar)) return $avatar;
        if (!function_exists("imagecreatetruecolor") || !function_exists("imagejpeg")) return $avatar;
        $groupId = intval($group["id"]);
        $signature = $this->blinGroupAvatarMemberSignature($groupId);
        if ($signature === "") return $avatar;
        $oldSignature = isset($group["avatar_signature"]) ? trim(strval($group["avatar_signature"])) : "";
        if ($avatar !== "" && $this->blinIsGeneratedGroupAvatar($avatar) && $oldSignature === $signature) return $avatar;
        try {
            $this->blinEnsureGroupAvatarSignatureColumn();
            $url = $this->blinBuildGroupAvatar($groupId);
            if ($url !== "") {
                Db::name("im_groups")->where("appid", $this->appid)->where("id", $groupId)->update(["avatar"=>$url, "avatar_signature"=>$signature, "update_time"=>date("Y-m-d H:i:s")]);
                return $url;
            }
        } catch (\\Exception $e) {}
        return $avatar;
    }
'''
    text = replace_once(
        text,
        '    private function blinGroupAvatarLabel($row)\n',
        api_helpers + "\n    private function blinGroupAvatarLabel($row)\n",
        "api avatar helper insert",
    )
    text = replace_once(
        text,
        '            if ($url !== "") {\n                Db::name("im_groups")->where("appid", $this->appid)->where("id", intval($groupId))->update(["avatar"=>$url, "update_time"=>date("Y-m-d H:i:s")]);\n                return $url;\n            }\n',
        '            if ($url !== "") {\n'
        '                $this->blinEnsureGroupAvatarSignatureColumn();\n'
        '                $signature = $this->blinGroupAvatarMemberSignature(intval($groupId));\n'
        '                $update = ["avatar"=>$url, "update_time"=>date("Y-m-d H:i:s")];\n'
        '                if ($signature !== "") $update["avatar_signature"] = $signature;\n'
        '                Db::name("im_groups")->where("appid", $this->appid)->where("id", intval($groupId))->update($update);\n'
        '                return $url;\n'
        '            }\n',
        "api apply avatar signature",
    )
    text = replace_once(
        text,
        '        Db::name("im_groups")->where("appid", $this->appid)->where("id", $groupId)->update(["avatar"=>$url, "update_time"=>date("Y-m-d H:i:s")]);\n',
        '        $this->blinEnsureGroupAvatarSignatureColumn();\n'
        '        $signature = $this->blinGroupAvatarMemberSignature($groupId);\n'
        '        $update = ["avatar"=>$url, "update_time"=>date("Y-m-d H:i:s")];\n'
        '        if ($signature !== "") $update["avatar_signature"] = $signature;\n'
        '        Db::name("im_groups")->where("appid", $this->appid)->where("id", $groupId)->update($update);\n',
        "api manual generate signature",
    )
    path.write_text(text, encoding="utf-8")


def patch_trait() -> None:
    path = TRAIT
    text = path.read_text(encoding="utf-8")
    if "blinTraitRefreshGroupAvatarIfNeeded" in text:
        text = ensure_once(
            text,
            "        $this->ensure_im_group_tables();\n        $this->blinTraitEnsureGroupReadClearTables();\n",
            "        $this->ensure_im_group_tables();\n        $this->blinEnsureGroupFeatureColumns();\n        $this->blinTraitEnsureGroupReadClearTables();\n",
            "trait group list ensure feature columns",
        )
        path.write_text(text, encoding="utf-8")
        return

    text = ensure_once(
        text,
        "        $this->ensure_im_group_tables();\n        $this->blinTraitEnsureGroupReadClearTables();\n",
        "        $this->ensure_im_group_tables();\n        $this->blinEnsureGroupFeatureColumns();\n        $this->blinTraitEnsureGroupReadClearTables();\n",
        "trait group list ensure feature columns",
    )

    text = replace_once(
        text,
        "        $this->blinAddColumnIfMissing('mr_im_groups', 'notice_pinned', \"ALTER TABLE `mr_im_groups` ADD COLUMN `notice_pinned` tinyint(1) NOT NULL DEFAULT 1 AFTER `admin_notice_enabled`\");\n",
        "        $this->blinAddColumnIfMissing('mr_im_groups', 'notice_pinned', \"ALTER TABLE `mr_im_groups` ADD COLUMN `notice_pinned` tinyint(1) NOT NULL DEFAULT 1 AFTER `admin_notice_enabled`\");\n"
        "        $this->blinAddColumnIfMissing('mr_im_groups', 'avatar_signature', \"ALTER TABLE `mr_im_groups` ADD COLUMN `avatar_signature` varchar(64) NOT NULL DEFAULT '' AFTER `avatar`\");\n",
        "trait feature column",
    )
    text = replace_once(
        text,
        "->field('g.id,g.id as group_id,g.group_no,g.name,g.avatar,g.notice,g.owner_id,g.member_count,g.default_group,g.update_time,m.role')",
        "->field('g.id,g.id as group_id,g.group_no,g.name,g.avatar,g.avatar_signature,g.notice,g.owner_id,g.member_count,g.default_group,g.update_time,m.role')",
        "trait group list field",
    )
    text = replace_once(
        text,
        "        foreach (($rows ?: []) as $row) {\n            $row['group_id'] = intval($row['id']);\n",
        "        foreach (($rows ?: []) as $row) {\n"
        "            $row['avatar'] = $this->blinTraitRefreshGroupAvatarIfNeeded($row);\n"
        "            if (isset($row['avatar_signature'])) unset($row['avatar_signature']);\n"
        "            $row['group_id'] = intval($row['id']);\n",
        "trait group list refresh",
    )
    text = replace_once(
        text,
        "        $group['group_id'] = intval($group['id']);\n        $group['my_role'] = $this->im_group_role_name($member['role']);\n",
        "        $group['avatar'] = $this->blinTraitRefreshGroupAvatarIfNeeded($group);\n"
        "        if (isset($group['avatar_signature'])) unset($group['avatar_signature']);\n"
        "        $group['group_id'] = intval($group['id']);\n"
        "        $group['my_role'] = $this->im_group_role_name($member['role']);\n",
        "trait group info refresh",
    )

    trait_helpers = '''

    private function blinTraitEnsureGroupAvatarSignatureColumn()
    {
        $this->blinAddColumnIfMissing('mr_im_groups', 'avatar_signature', "ALTER TABLE `mr_im_groups` ADD COLUMN `avatar_signature` varchar(64) NOT NULL DEFAULT '' AFTER `avatar`");
    }

    private function blinTraitGroupAvatarMemberSignature($groupId)
    {
        try {
            $rows = Db::name("im_group_members")->alias("m")
                ->join("user u", "u.id=m.user_id")
                ->where("m.appid", $this->appid)
                ->where("m.group_id", intval($groupId))
                ->where("m.status", 1)
                ->where("u.appid", $this->appid)
                ->field("u.id,u.usertx")
                ->order("m.role desc,m.id asc")
                ->limit(9)
                ->select();
            if (!$rows) return "";
            $parts = [];
            foreach ($rows as $row) {
                $parts[] = intval($row["id"]) . ":" . trim(strval(isset($row["usertx"]) ? $row["usertx"] : ""));
            }
            return md5(implode("|", $parts));
        } catch (\\Exception $e) {
            return "";
        }
    }

    private function blinTraitRefreshGroupAvatarIfNeeded($group)
    {
        if (!$group || !isset($group["id"])) return "";
        $avatar = trim(strval(isset($group["avatar"]) ? $group["avatar"] : ""));
        if (!$this->blinGroupAvatarCollageEnabled()) return $avatar;
        if (!$this->blinTraitGeneratedGroupAvatar($avatar) && !$this->blinIsSystemDefaultAvatar($avatar)) return $avatar;
        if (!function_exists("imagecreatetruecolor") || !function_exists("imagejpeg")) return $avatar;
        $groupId = intval($group["id"]);
        $signature = $this->blinTraitGroupAvatarMemberSignature($groupId);
        if ($signature === "") return $avatar;
        $oldSignature = isset($group["avatar_signature"]) ? trim(strval($group["avatar_signature"])) : "";
        if ($avatar !== "" && $this->blinTraitGeneratedGroupAvatar($avatar) && $oldSignature === $signature) return $avatar;
        try {
            $this->blinTraitEnsureGroupAvatarSignatureColumn();
            $url = $this->blinBuildGroupAvatar($groupId);
            if ($url !== "") {
                Db::name("im_groups")->where("appid", $this->appid)->where("id", $groupId)->update(["avatar"=>$url, "avatar_signature"=>$signature, "update_time"=>date("Y-m-d H:i:s")]);
                return $url;
            }
        } catch (\\Exception $e) {}
        return $avatar;
    }
'''
    text = replace_once(
        text,
        '    private function blinGroupAvatarLabel($row)\n',
        trait_helpers + "\n    private function blinGroupAvatarLabel($row)\n",
        "trait avatar helper insert",
    )
    text = replace_once(
        text,
        '            if ($url !== "") {\n                Db::name("im_groups")->where("appid", $this->appid)->where("id", intval($groupId))->update(["avatar"=>$url, "update_time"=>date("Y-m-d H:i:s")]);\n                return $url;\n            }\n',
        '            if ($url !== "") {\n'
        '                $this->blinTraitEnsureGroupAvatarSignatureColumn();\n'
        '                $signature = $this->blinTraitGroupAvatarMemberSignature(intval($groupId));\n'
        '                $update = ["avatar"=>$url, "update_time"=>date("Y-m-d H:i:s")];\n'
        '                if ($signature !== "") $update["avatar_signature"] = $signature;\n'
        '                Db::name("im_groups")->where("appid", $this->appid)->where("id", intval($groupId))->update($update);\n'
        '                return $url;\n'
        '            }\n',
        "trait apply avatar signature",
    )
    if "Db::name('im_groups')->where('appid', $this->appid)->where('id', $groupId)->update(['avatar'=>$url, 'update_time'=>date('Y-m-d H:i:s')]);" in text:
        text = replace_once(
            text,
            "        Db::name('im_groups')->where('appid', $this->appid)->where('id', $groupId)->update(['avatar'=>$url, 'update_time'=>date('Y-m-d H:i:s')]);\n",
            "        $this->blinTraitEnsureGroupAvatarSignatureColumn();\n"
            "        $signature = $this->blinTraitGroupAvatarMemberSignature($groupId);\n"
            "        $update = ['avatar'=>$url, 'update_time'=>date('Y-m-d H:i:s')];\n"
            "        if ($signature !== '') $update['avatar_signature'] = $signature;\n"
            "        Db::name('im_groups')->where('appid', $this->appid)->where('id', $groupId)->update($update);\n",
            "trait manual generate signature single quote",
        )
    else:
        text = replace_once(
            text,
            '        Db::name("im_groups")->where("appid", $this->appid)->where("id", $groupId)->update(["avatar"=>$url, "update_time"=>date("Y-m-d H:i:s")]);\n',
            '        $this->blinTraitEnsureGroupAvatarSignatureColumn();\n'
            '        $signature = $this->blinTraitGroupAvatarMemberSignature($groupId);\n'
            '        $update = ["avatar"=>$url, "update_time"=>date("Y-m-d H:i:s")];\n'
            '        if ($signature !== "") $update["avatar_signature"] = $signature;\n'
            '        Db::name("im_groups")->where("appid", $this->appid)->where("id", $groupId)->update($update);\n',
            "trait manual generate signature double quote",
        )
    path.write_text(text, encoding="utf-8")


def main() -> None:
    patch_api()
    patch_trait()
    print("patched group avatar realtime refresh")


if __name__ == "__main__":
    main()
