from pathlib import Path


ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"


def backup(path: Path) -> None:
    bak = path.with_name(path.name + ".bak_group_avatar_collage_default_20260621")
    if not bak.exists():
        bak.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise RuntimeError(f"missing marker: {label}")
    return text.replace(old, new, 1)


def main() -> None:
    backup(API)
    text = API.read_text(encoding="utf-8")

    text = replace_once(
        text,
        '''        } else {
            Db::name("im_groups")->where("id", $group["id"])->update(["name"=>$name, "avatar"=>$avatar, "notice"=>$notice, "owner_id"=>$ownerId, "default_group"=>1, "status"=>1, "update_time"=>$now]);
            $group = Db::name("im_groups")->where("id", $group["id"])->find();
        }
''',
        '''        } else {
            $defaultGroupUpdate = ["name"=>$name, "notice"=>$notice, "owner_id"=>$ownerId, "default_group"=>1, "status"=>1, "update_time"=>$now];
            $currentAvatar = trim(strval(isset($group["avatar"]) ? $group["avatar"] : ""));
            if ($avatar !== "" && ($currentAvatar === "" || !$this->blinIsGeneratedGroupAvatar($currentAvatar))) {
                $defaultGroupUpdate["avatar"] = $avatar;
            }
            Db::name("im_groups")->where("id", $group["id"])->update($defaultGroupUpdate);
            $group = Db::name("im_groups")->where("id", $group["id"])->find();
        }
''',
        "default_group_keep_generated_avatar",
    )

    text = replace_once(
        text,
        '''    private function blinCreatorAvatar($user)
    {
        if (isset($user["usertx"]) && trim(strval($user["usertx"])) !== "") return trim(strval($user["usertx"]));
        if (isset($user["avatar"]) && trim(strval($user["avatar"])) !== "") return trim(strval($user["avatar"]));
        if (isset($user["tx"]) && trim(strval($user["tx"])) !== "") return trim(strval($user["tx"]));
        return "";
    }

    private function blinApplyDefaultGroupAvatar($groupId, $requestAvatar, $creatorAvatar)
''',
        '''    private function blinCreatorAvatar($user)
    {
        if (isset($user["usertx"]) && trim(strval($user["usertx"])) !== "") return trim(strval($user["usertx"]));
        if (isset($user["avatar"]) && trim(strval($user["avatar"])) !== "") return trim(strval($user["avatar"]));
        if (isset($user["tx"]) && trim(strval($user["tx"])) !== "") return trim(strval($user["tx"]));
        return "";
    }

    private function blinIsGeneratedGroupAvatar($avatar)
    {
        $avatar = strtolower(trim(strval($avatar)));
        return $avatar !== "" && strpos($avatar, "/uploads/im_group_avatar/") !== false;
    }

    private function blinIsSystemDefaultAvatar($avatar)
    {
        $avatar = strtolower(trim(strval($avatar)));
        if ($avatar === "") return true;
        return strpos($avatar, "/static/images/initial_photo/") !== false
            || strpos($avatar, "initial_photo/user.png") !== false
            || strpos($avatar, "default_avatar") !== false
            || strpos($avatar, "default-user") !== false;
    }

    private function blinGroupAvatarLabel($row)
    {
        $source = "";
        if (isset($row["username"]) && trim(strval($row["username"])) !== "") $source = trim(strval($row["username"]));
        if ($source === "" && isset($row["nickname"]) && trim(strval($row["nickname"])) !== "") $source = trim(strval($row["nickname"]));
        $source = strtoupper(preg_replace("/[^A-Za-z0-9]/", "", $source));
        if ($source === "") $source = "U" . intval(isset($row["id"]) ? $row["id"] : 0);
        return substr($source, 0, 2);
    }

    private function blinDrawGroupAvatarTile($canvas, $x, $y, $cell, $row, $index)
    {
        $palette = [
            [99, 102, 241], [16, 185, 129], [245, 158, 11],
            [14, 165, 233], [236, 72, 153], [168, 85, 247],
            [20, 184, 166], [239, 68, 68], [34, 197, 94],
        ];
        $seed = intval(isset($row["id"]) ? $row["id"] : 0) + intval($index);
        $rgb = $palette[abs($seed) % count($palette)];
        $fill = imagecolorallocate($canvas, $rgb[0], $rgb[1], $rgb[2]);
        imagefilledrectangle($canvas, $x, $y, $x + $cell - 1, $y + $cell - 1, $fill);
        $label = $this->blinGroupAvatarLabel($row);
        $font = $cell >= 72 ? 5 : 4;
        $textColor = imagecolorallocate($canvas, 255, 255, 255);
        $tw = imagefontwidth($font) * strlen($label);
        $th = imagefontheight($font);
        imagestring($canvas, $font, intval($x + ($cell - $tw) / 2), intval($y + ($cell - $th) / 2), $label, $textColor);
    }

    private function blinApplyDefaultGroupAvatar($groupId, $requestAvatar, $creatorAvatar)
''',
        "avatar_helper_methods",
    )

    text = replace_once(
        text,
        '''            $avatar = trim(strval(isset($row["usertx"]) ? $row["usertx"] : ""));
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
''',
        '''            $avatar = trim(strval(isset($row["usertx"]) ? $row["usertx"] : ""));
            $img = $this->blinIsSystemDefaultAvatar($avatar) ? null : $this->blinLoadAvatarImage($avatar);
            if ($img) {
                imagecopyresampled($canvas, $img, $x, $y, 0, 0, $cell, $cell, imagesx($img), imagesy($img));
                imagedestroy($img);
            } else {
                $this->blinDrawGroupAvatarTile($canvas, $x, $y, $cell, $row, $index);
            }
''',
        "draw_member_avatar_tile",
    )

    text = replace_once(
        text,
        '''        if (strpos($avatar, "http://") === 0 || strpos($avatar, "https://") === 0) {
            $context = stream_context_create(["http"=>["timeout"=>3], "https"=>["timeout"=>3]]);
            $raw = @file_get_contents($avatar, false, $context);
            if (!$raw) return null;
            return @imagecreatefromstring($raw);
        }
''',
        r'''        if (strpos($avatar, "http://") === 0 || strpos($avatar, "https://") === 0) {
            $urlPath = parse_url($avatar, PHP_URL_PATH);
            if ($urlPath) {
                $local = \think\facade\Env::get("root_path") . "public" . $urlPath;
                if (is_file($local)) {
                    $raw = @file_get_contents($local);
                    if ($raw) return @imagecreatefromstring($raw);
                }
            }
            $context = stream_context_create(["http"=>["timeout"=>3], "https"=>["timeout"=>3]]);
            $raw = @file_get_contents($avatar, false, $context);
            if (!$raw) return null;
            return @imagecreatefromstring($raw);
        }
''',
        "load_avatar_local_url_first",
    )

    API.write_text(text, encoding="utf-8")
    print("patched group avatar collage default handling")


if __name__ == "__main__":
    main()
