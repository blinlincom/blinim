#!/usr/bin/env python3
from pathlib import Path

ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"


def backup(path: Path) -> str:
    dst = path.with_name(f"{path.name}.bak_moments_friend_appid_compat_20260617")
    if not dst.exists():
        dst.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
    return str(dst)


def main() -> None:
    original = API.read_text(encoding="utf-8")
    source = original
    source = source.replace(
        '''Db::table("im_friends")
                ->where("appid", intval($this->appid))
                ->where("user_id", intval($userId))
                ->where("status", 1)
                ->column("friend_id")''',
        '''Db::table("im_friends")
                ->where("appid", "in", [intval($this->appid), 0])
                ->where("user_id", intval($userId))
                ->where("status", 1)
                ->column("friend_id")''',
    )
    source = source.replace(
        '''Db::table("im_friends")
                ->where("appid", intval($this->appid))
                ->where("user_id", intval($userId))
                ->where("friend_id", intval($moment["user_id"]))
                ->where("status", 1)
                ->find()''',
        '''Db::table("im_friends")
                ->where("appid", "in", [intval($this->appid), 0])
                ->where("user_id", intval($userId))
                ->where("friend_id", intval($moment["user_id"]))
                ->where("status", 1)
                ->find()''',
    )
    if source == original:
        print("NO_CHANGE")
        return
    print(f"BACKUP {backup(API)}")
    API.write_text(source, encoding="utf-8")
    print(f"PATCHED {API}")


if __name__ == "__main__":
    main()
