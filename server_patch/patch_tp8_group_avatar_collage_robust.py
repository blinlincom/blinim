#!/usr/bin/env python3
from pathlib import Path


ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "app/api/controller/Api.php"
TRAIT = ROOT / "app/api/controller/traits/ImApiTrait.php"
STAMP = "20260623_group_avatar_collage_robust"


def backup(path: Path) -> None:
    bak = path.with_name(f"{path.name}.bak_{STAMP}")
    if not bak.exists():
        bak.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise RuntimeError(f"missing marker: {label}")
    return text.replace(old, new, 1)


def patch_file(path: Path, trait: bool) -> None:
    backup(path)
    text = path.read_text(encoding="utf-8")

    creator = """    private function blinCreatorAvatar($user)
    {
        if (isset($user["usertx"]) && trim(strval($user["usertx"])) !== "") return trim(strval($user["usertx"]));
        if (isset($user["avatar"]) && trim(strval($user["avatar"])) !== "") return trim(strval($user["avatar"]));
        if (isset($user["tx"]) && trim(strval($user["tx"])) !== "") return trim(strval($user["tx"]));
        return "";
    }
"""
    creator_new = """    private function blinCreatorAvatar($user)
    {
        return $this->blinGroupAvatarFromRow(is_array($user) ? $user : []);
    }

    private function blinGroupAvatarFromRow($row)
    {
        if (!is_array($row)) return "";
        foreach (["usertx", "avatar", "user_avatar", "tx", "headimg", "head_img", "head_image", "userpic", "user_pic", "face", "photo", "portrait"] as $key) {
            if (isset($row[$key]) && trim(strval($row[$key])) !== "" && strtolower(trim(strval($row[$key]))) !== "null") {
                return trim(strval($row[$key]));
            }
        }
        return "";
    }
"""
    text = replace_once(text, creator, creator_new, f"{path.name} creator avatar helper")

    system_default_variants = [
        """    private function blinIsSystemDefaultAvatar($avatar)
    {
        $avatar = strtolower(trim(strval($avatar)));
        if ($avatar === "") return true;
        return strpos($avatar, "/static/images/initial_photo/") !== false
            || strpos($avatar, "initial_photo/user.png") !== false
            || strpos($avatar, "initial_photo/android.png") !== false
            || strpos($avatar, "default_avatar") !== false
            || strpos($avatar, "default-user") !== false;
    }
""",
        """    private function blinIsSystemDefaultAvatar($avatar)
    {
        $avatar = strtolower(trim(strval($avatar)));
        if ($avatar === "") return true;
        return strpos($avatar, "/static/images/initial_photo/") !== false
            || strpos($avatar, "initial_photo/user.png") !== false
            || strpos($avatar, "default_avatar") !== false
            || strpos($avatar, "default-user") !== false;
    }
""",
    ]
    system_default_new = """    private function blinIsSystemDefaultAvatar($avatar)
    {
        $avatar = strtolower(trim(strval($avatar)));
        if ($avatar === "" || $avatar === "null" || $avatar === "undefined") return true;
        $path = parse_url($avatar, PHP_URL_PATH);
        $path = $path ? strtolower($path) : $avatar;
        $base = basename($path);
        return strpos($path, "/static/images/initial_photo/") !== false
            || strpos($path, "initial_photo/user.png") !== false
            || strpos($path, "initial_photo/android.png") !== false
            || $base === "user.png"
            || $base === "android.png"
            || strpos($path, "default_avatar") !== false
            || strpos($path, "default-user") !== false
            || strpos($path, "default_user") !== false
            || strpos($path, "/default/") !== false;
    }
"""
    if system_default_new not in text:
        for system_default in system_default_variants:
            if system_default in text:
                text = text.replace(system_default, system_default_new, 1)
                break
        else:
            raise RuntimeError(f"missing marker: {path.name} system default avatar")

    field_old = '            ->field("u.id,u.usertx")\n'
    field_new = '            ->field("u.id,u.usertx,u.nickname,u.username")\n'
    if field_old in text:
        text = text.replace(field_old, field_new, 1)

    signature_old = """            foreach ($rows as $row) {
                $parts[] = intval($row["id"]) . ":" . trim(strval(isset($row["usertx"]) ? $row["usertx"] : ""));
            }
            return md5(implode("|", $parts));
"""
    signature_new = """            foreach ($rows as $row) {
                $parts[] = intval($row["id"]) . ":" . $this->blinGroupAvatarFromRow($row) . ":" . trim(strval(isset($row["nickname"]) ? $row["nickname"] : "")) . ":" . trim(strval(isset($row["username"]) ? $row["username"] : ""));
            }
            return md5(implode("|", $parts));
"""
    text = replace_once(text, signature_old, signature_new, f"{path.name} signature avatar source")

    draw_old = """            $avatar = trim(strval(isset($row["usertx"]) ? $row["usertx"] : ""));
            $img = $this->blinIsSystemDefaultAvatar($avatar) ? null : $this->blinLoadAvatarImage($avatar);
            if ($img) {
                imagecopyresampled($canvas, $img, $x, $y, 0, 0, $cell, $cell, imagesx($img), imagesy($img));
                imagedestroy($img);
            } else {
                $this->blinDrawGroupAvatarTile($canvas, $x, $y, $cell, $row, $index);
            }
"""
    draw_new = """            $avatar = $this->blinGroupAvatarFromRow($row);
            $img = $this->blinIsSystemDefaultAvatar($avatar) ? null : $this->blinLoadAvatarImage($avatar);
            if ($img) {
                $w = imagesx($img);
                $h = imagesy($img);
                if ($w > 0 && $h > 0) {
                    imagecopyresampled($canvas, $img, $x, $y, 0, 0, $cell, $cell, $w, $h);
                } else {
                    $this->blinDrawGroupAvatarTile($canvas, $x, $y, $cell, $row, $index);
                }
                imagedestroy($img);
            } else {
                $this->blinDrawGroupAvatarTile($canvas, $x, $y, $cell, $row, $index);
            }
"""
    text = replace_once(text, draw_old, draw_new, f"{path.name} draw avatar source")

    jpeg_old = """        imagejpeg($canvas, $path, 88);
        imagedestroy($canvas);
        $domain = request()->domain();
        return $domain . "/uploads/im_group_avatar/" . $name;
"""
    jpeg_new = """        $saved = @imagejpeg($canvas, $path, 88);
        imagedestroy($canvas);
        if (!$saved || !is_file($path) || filesize($path) <= 0) {
            @unlink($path);
            return "";
        }
        $domain = request()->domain();
        return $domain . "/uploads/im_group_avatar/" . $name;
"""
    text = replace_once(text, jpeg_old, jpeg_new, f"{path.name} jpeg save guard")

    load_old = """    private function blinLoadAvatarImage($avatar)
    {
        if ($avatar === "") return null;
        $path = $avatar;
        if (strpos($avatar, "http://") === 0 || strpos($avatar, "https://") === 0) {
            $urlPath = parse_url($avatar, PHP_URL_PATH);
            if ($urlPath) {
                $local = \\think\\facade\\Env::get("root_path") . "public" . $urlPath;
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
        if (strpos($path, "/") === 0) $path = \\think\\facade\\Env::get("root_path") . "public" . $path;
        if (!is_file($path)) $path = \\think\\facade\\Env::get("root_path") . "public/" . ltrim($avatar, "/");
        if (!is_file($path)) return null;
        $raw = @file_get_contents($path);
        if (!$raw) return null;
        return @imagecreatefromstring($raw);
    }
"""
    load_new = """    private function blinLoadAvatarImage($avatar)
    {
        $avatar = trim(strval($avatar));
        if ($avatar === "" || $this->blinIsSystemDefaultAvatar($avatar)) return null;
        $path = $avatar;
        if (strpos($avatar, "http://") === 0 || strpos($avatar, "https://") === 0) {
            $urlPath = parse_url($avatar, PHP_URL_PATH);
            if ($urlPath) {
                $local = \\think\\facade\\Env::get("root_path") . "public" . $urlPath;
                if (is_file($local)) {
                    $raw = @file_get_contents($local);
                    $img = $raw ? @imagecreatefromstring($raw) : null;
                    if ($img) return $img;
                }
            }
            $context = stream_context_create(["http"=>["timeout"=>5, "ignore_errors"=>true], "https"=>["timeout"=>5, "ignore_errors"=>true]]);
            $raw = @file_get_contents($avatar, false, $context);
            if (!$raw) return null;
            $img = @imagecreatefromstring($raw);
            return $img ?: null;
        }
        if (strpos($path, "/") === 0) $path = \\think\\facade\\Env::get("root_path") . "public" . $path;
        if (!is_file($path)) $path = \\think\\facade\\Env::get("root_path") . "public/" . ltrim($avatar, "/");
        if (!is_file($path)) return null;
        $raw = @file_get_contents($path);
        if (!$raw) return null;
        $img = @imagecreatefromstring($raw);
        return $img ?: null;
    }
"""
    text = replace_once(text, load_old, load_new, f"{path.name} load avatar guard")

    path.write_text(text, encoding="utf-8")


def main() -> None:
    patch_file(API, trait=False)
    patch_file(TRAIT, trait=True)
    print("patched tp8 group avatar collage robust handling")


if __name__ == "__main__":
    main()
