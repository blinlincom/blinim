from pathlib import Path
from datetime import datetime

ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"
TRAIT = ROOT / "application/api/controller/traits/ImApiTrait.php"


def backup(path: Path):
    stamp = datetime.now().strftime("%Y%m%d%H%M%S")
    bak = path.with_name(f"{path.name}.bak_group_avatar_{stamp}")
    bak.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")


def replace_between(source: str, start: str, end: str, replacement: str) -> str:
    a = source.find(start)
    if a < 0:
        raise RuntimeError(f"start not found: {start}")
    b = source.find(end, a)
    if b < 0:
        raise RuntimeError(f"end not found: {end}")
    return source[:a] + replacement.rstrip() + "\n\n" + source[b:]


def ensure_common_methods(source: str) -> str:
    update_marker = "\n    public function update_im_group()"
    helper_marker = "\n    private function blinEnsureGroupFeatureColumns()"
    h = source.find(helper_marker)
    u = source.find(update_marker)
    if u < 0:
        raise RuntimeError("update_im_group marker not found")
    if h >= 0 and h < u:
        return source[:h] + "\n" + COMMON_METHODS.rstrip() + "\n" + source[u:]
    return source[:u] + "\n" + COMMON_METHODS.rstrip() + "\n" + source[u:]


COMMON_METHODS = r'''
    private function blinEnsureGroupFeatureColumns()
    {
        $this->blinAddColumnIfMissing('mr_im_groups', 'qr_enabled', "ALTER TABLE `mr_im_groups` ADD COLUMN `qr_enabled` tinyint(1) NOT NULL DEFAULT 1 AFTER `default_group`");
        $this->blinAddColumnIfMissing('mr_im_groups', 'admin_notice_enabled', "ALTER TABLE `mr_im_groups` ADD COLUMN `admin_notice_enabled` tinyint(1) NOT NULL DEFAULT 1 AFTER `qr_enabled`");
        $this->blinAddColumnIfMissing('mr_im_groups', 'notice_pinned', "ALTER TABLE `mr_im_groups` ADD COLUMN `notice_pinned` tinyint(1) NOT NULL DEFAULT 1 AFTER `admin_notice_enabled`");
        $this->blinAddColumnIfMissing('mr_im_groups', 'screenshot_notify_enabled', "ALTER TABLE `mr_im_groups` ADD COLUMN `screenshot_notify_enabled` tinyint(1) NOT NULL DEFAULT 0 AFTER `notice_pinned`");
    }

    private function blinAddColumnIfMissing($table, $column, $sql)
    {
        try {
            $row = Db::query("SHOW COLUMNS FROM `" . $table . "` LIKE '" . $column . "'");
            if (!$row) Db::execute($sql);
        } catch (\Exception $e) {}
    }

    private function blinGroupUpdateValue($data, $keys)
    {
        foreach ($keys as $key) {
            if (isset($data[$key])) return trim(strval($data[$key]));
        }
        return null;
    }

    private function blinGroupBoolValue($data, $keys)
    {
        foreach ($keys as $key) {
            if (isset($data[$key])) return intval($data[$key]) == 1 ? 1 : 0;
        }
        return null;
    }

    private function blinBuildGroupAvatar($groupId)
    {
        $rows = Db::name("im_group_members")->alias("m")
            ->join("user u", "u.id=m.user_id")
            ->where("m.appid", $this->appid)
            ->where("m.group_id", $groupId)
            ->where("m.status", 1)
            ->where("u.appid", $this->appid)
            ->field("u.id,u.usertx,u.nickname,u.username")
            ->order("m.role desc,m.id asc")
            ->limit(9)
            ->select();
        if (!$rows) return "";
        $size = 240;
        $canvas = imagecreatetruecolor($size, $size);
        $bg = imagecolorallocate($canvas, 241, 245, 249);
        imagefill($canvas, 0, 0, $bg);
        $count = count($rows);
        $cols = $count <= 1 ? 1 : ($count <= 4 ? 2 : 3);
        $gap = 8;
        $cell = intval(($size - ($cols + 1) * $gap) / $cols);
        $rowsCount = intval(ceil($count / $cols));
        $startY = intval(($size - ($rowsCount * $cell + ($rowsCount - 1) * $gap)) / 2);
        foreach ($rows as $index => $row) {
            $col = $index % $cols;
            $line = intval(floor($index / $cols));
            $itemsInLine = min($cols, $count - $line * $cols);
            $startX = intval(($size - ($itemsInLine * $cell + ($itemsInLine - 1) * $gap)) / 2);
            $x = $startX + ($index % $cols) * ($cell + $gap);
            $y = $startY + $line * ($cell + $gap);
            $avatar = trim(strval(isset($row["usertx"]) ? $row["usertx"] : ""));
            $img = $this->blinLoadAvatarImage($avatar);
            if ($img) {
                imagecopyresampled($canvas, $img, $x, $y, 0, 0, $cell, $cell, imagesx($img), imagesy($img));
                imagedestroy($img);
            } else {
                $r = 99 + ($index * 23) % 80;
                $g = 102 + ($index * 31) % 80;
                $b = 241 - ($index * 17) % 70;
                $fill = imagecolorallocate($canvas, $r, $g, $b);
                imagefilledrectangle($canvas, $x, $y, $x + $cell, $y + $cell, $fill);
            }
        }
        $dir = ROOT_PATH . "public/uploads/im_group_avatar";
        if (!is_dir($dir)) @mkdir($dir, 0755, true);
        $name = "group_" . intval($this->appid) . "_" . intval($groupId) . "_" . time() . "_" . mt_rand(1000, 9999) . ".jpg";
        $path = $dir . "/" . $name;
        imagejpeg($canvas, $path, 88);
        imagedestroy($canvas);
        $domain = request()->domain();
        return $domain . "/uploads/im_group_avatar/" . $name;
    }

    private function blinLoadAvatarImage($avatar)
    {
        if ($avatar === "") return null;
        $path = $avatar;
        if (strpos($avatar, "http://") === 0 || strpos($avatar, "https://") === 0) {
            $context = stream_context_create(["http"=>["timeout"=>3], "https"=>["timeout"=>3]]);
            $raw = @file_get_contents($avatar, false, $context);
            if (!$raw) return null;
            return @imagecreatefromstring($raw);
        }
        if (strpos($path, "/") === 0) $path = ROOT_PATH . "public" . $path;
        if (!is_file($path)) $path = ROOT_PATH . "public/" . ltrim($avatar, "/");
        if (!is_file($path)) return null;
        $raw = @file_get_contents($path);
        if (!$raw) return null;
        return @imagecreatefromstring($raw);
    }
'''


API_UPDATE = r'''
    public function update_im_group()
    {
        $rule = ["usertoken|用户token" => "require", "group_id|群ID" => "require|number"];
        $data = input();
        $validate = new Validate($rule);
        if (!$validate->check($data)) $this->json(0, $validate->getError());
        $user = $this->im_group_user();
        $this->ensure_im_group_tables();
        $this->blinEnsureGroupFeatureColumns();
        $groupId = intval($data["group_id"]);
        $group = Db::name("im_groups")->where("appid", $this->appid)->where("id", $groupId)->where("status", 1)->find();
        if (!$group) $this->json(0, "群聊不存在");
        $member = $this->im_group_member($groupId, intval($user["id"]));
        if (!$member) $this->json(0, "不是群成员");
        $isOwner = intval($member["role"]) >= 2 || intval($group["owner_id"]) === intval($user["id"]);
        $canManage = $isOwner || intval($member["role"]) >= 1;
        $update = ["update_time"=>date("Y-m-d H:i:s")];
        $name = $this->blinGroupUpdateValue($data, ["name", "group_name"]);
        if ($name !== null) {
            if (!$canManage) $this->json(0, "没有群管理权限");
            $update["name"] = $name;
        }
        $avatar = $this->blinGroupUpdateValue($data, ["avatar", "group_avatar"]);
        if ($avatar !== null) {
            if (!$canManage) $this->json(0, "没有群管理权限");
            $update["avatar"] = $avatar;
        }
        $notice = $this->blinGroupUpdateValue($data, ["notice", "announcement", "group_notice"]);
        if ($notice !== null) {
            if (!$isOwner && !(intval(isset($group["admin_notice_enabled"]) ? $group["admin_notice_enabled"] : 1) === 1 && $canManage)) $this->json(0, "没有公告编辑权限");
            $update["notice"] = $notice;
        }
        $groupNo = $this->blinGroupUpdateValue($data, ["group_no", "groupNo"]);
        if ($groupNo !== null) {
            if (!$isOwner) $this->json(0, "只有群主可以修改群号");
            if (!preg_match("/^[A-Za-z0-9_]{4,32}$/", $groupNo)) $this->json(0, "群号只能是4-32位英文数字或下划线");
            $exists = Db::name("im_groups")->where("appid", $this->appid)->where("group_no", $groupNo)->where("id", "<>", $groupId)->find();
            if ($exists) $this->json(0, "群号已存在");
            $update["group_no"] = $groupNo;
        }
        $qr = $this->blinGroupBoolValue($data, ["qr_enabled", "qrcode_enabled"]);
        if ($qr !== null) {
            if (!$isOwner) $this->json(0, "只有群主可以设置群二维码");
            $update["qr_enabled"] = $qr;
        }
        $adminNotice = $this->blinGroupBoolValue($data, ["admin_notice_enabled"]);
        if ($adminNotice !== null) {
            if (!$isOwner) $this->json(0, "只有群主可以设置公告权限");
            $update["admin_notice_enabled"] = $adminNotice;
        }
        $screenshotNotify = $this->blinGroupBoolValue($data, ["screenshot_notify_enabled", "screenshot_notice_enabled"]);
        if ($screenshotNotify !== null) {
            if (!$isOwner) $this->json(0, "只有群主可以设置截屏提醒");
            $update["screenshot_notify_enabled"] = $screenshotNotify;
        }
        $noticePinned = $this->blinGroupBoolValue($data, ["notice_pinned"]);
        if ($noticePinned !== null) {
            if (!$isOwner) $this->json(0, "只有群主可以设置公告置顶");
            $update["notice_pinned"] = $noticePinned;
        }
        if (count($update) <= 1) $this->json(0, "没有可更新内容");
        Db::name("im_groups")->where("appid", $this->appid)->where("id", $groupId)->update($update);
        $group = Db::name("im_groups")->where("appid", $this->appid)->where("id", $groupId)->find();
        $this->json(1, "更新成功", $group ?: []);
    }

    public function generate_im_group_avatar()
    {
        $rule = ["usertoken|用户token" => "require", "group_id|群ID" => "require|number"];
        $data = input();
        $validate = new Validate($rule);
        if (!$validate->check($data)) $this->json(0, $validate->getError());
        if (!extension_loaded("gd")) $this->json(0, "服务器未安装GD图片库");
        $user = $this->im_group_user();
        $this->ensure_im_group_tables();
        $this->blinEnsureGroupFeatureColumns();
        $groupId = intval($data["group_id"]);
        if (!$this->im_group_can_manage($groupId, intval($user["id"]))) $this->json(0, "没有群管理权限");
        $group = Db::name("im_groups")->where("appid", $this->appid)->where("id", $groupId)->where("status", 1)->find();
        if (!$group) $this->json(0, "群聊不存在");
        $url = $this->blinBuildGroupAvatar($groupId);
        if ($url === "") $this->json(0, "没有可用于拼接的群成员头像");
        Db::name("im_groups")->where("appid", $this->appid)->where("id", $groupId)->update(["avatar"=>$url, "update_time"=>date("Y-m-d H:i:s")]);
        $group = Db::name("im_groups")->where("appid", $this->appid)->where("id", $groupId)->find();
        $this->json(1, "群头像已生成", $group ?: ["avatar"=>$url]);
    }
'''


TRAIT_UPDATE = API_UPDATE


def patch_api():
    source = API.read_text(encoding="utf-8")
    source = ensure_common_methods(source)
    source = replace_between(
        source,
        "    public function update_im_group()",
        "    public function add_im_group_members()",
        API_UPDATE,
    )
    API.write_text(source, encoding="utf-8")


def patch_trait():
    source = TRAIT.read_text(encoding="utf-8")
    source = ensure_common_methods(source)
    source = replace_between(
        source,
        "    public function update_im_group()",
        "    public function add_im_group_members()",
        TRAIT_UPDATE,
    )
    TRAIT.write_text(source, encoding="utf-8")


def main():
    backup(API)
    backup(TRAIT)
    patch_api()
    patch_trait()
    print("patched group avatar management")


if __name__ == "__main__":
    main()
