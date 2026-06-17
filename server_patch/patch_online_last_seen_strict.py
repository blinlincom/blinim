#!/usr/bin/env python3
from pathlib import Path

ROOT = Path("/www/wwwroot/blinlin")
CANDIDATES = [
    ROOT / "application/api/controller/traits/ImApiTrait.php",
    ROOT / "application/api/controller/Api.php",
]


def backup(path: Path) -> str:
    dst = path.with_name(f"{path.name}.bak_online_last_seen_strict_20260617")
    if not dst.exists():
        dst.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
    return str(dst)


def patch(path: Path) -> bool:
    if not path.exists():
        return False
    original = path.read_text(encoding="utf-8")
    if "public function get_im_online_status()" not in original:
        return False
    source = original

    source = source.replace(
        '        $last_update_time = "";\n',
        '        $last_update_time = "";\n        $last_seen = "";\n',
        1,
    )

    old_loop = '''                    if ($last_update_time === "" && isset($r['update_time'])) $last_update_time = strval($r['update_time']);
                    $fresh = isset($r['update_time']) && strtotime($r['update_time']) >= time() - $ttl_seconds;
                    if (intval($r['online']) === 1 && $fresh) {
                        $online = true;
                        $device = isset($r['device']) ? strval($r['device']) : $device;
                        $platform = isset($r['platform']) ? strval($r['platform']) : $platform;
                        $terminal = isset($r['terminal']) ? strval($r['terminal']) : $terminal;
                        $device_flag = isset($r['device_flag']) ? intval($r['device_flag']) : $device_flag;
                        $last_update_time = isset($r['update_time']) ? strval($r['update_time']) : $last_update_time;
                        $source = $source === "wukongim" ? "wukongim+db_heartbeat" : "db_heartbeat";
                        break;
                    }
'''
    new_loop = '''                    if ($last_update_time === "" && isset($r['update_time'])) $last_update_time = strval($r['update_time']);
                    if ($last_seen === "" && isset($r['last_seen']) && trim(strval($r['last_seen'])) !== "" && strval($r['last_seen']) !== "0000-00-00 00:00:00") {
                        $last_seen = strval($r['last_seen']);
                    }
                    $row_update_time = isset($r['update_time']) ? strval($r['update_time']) : "";
                    $fresh = $row_update_time !== "" && strtotime($row_update_time) >= time() - $ttl_seconds;
                    if (intval($r['online']) === 1 && $fresh) {
                        $online = true;
                        $device = isset($r['device']) ? strval($r['device']) : $device;
                        $platform = isset($r['platform']) ? strval($r['platform']) : $platform;
                        $terminal = isset($r['terminal']) ? strval($r['terminal']) : $terminal;
                        $device_flag = isset($r['device_flag']) ? intval($r['device_flag']) : $device_flag;
                        $last_update_time = $row_update_time !== "" ? $row_update_time : $last_update_time;
                        $source = $source === "wukongim" ? "wukongim+db_heartbeat" : "db_heartbeat";
                        break;
                    }
                    if (intval($r['online']) === 1 && !$fresh && $row_update_time !== "") {
                        try {
                            Db::name('im_online_status')->where("id", intval($r["id"]))->update(["online"=>0, "last_event"=>"timeout", "last_seen"=>$row_update_time, "update_time"=>$row_update_time]);
                        } catch (\\Exception $e) {}
                        if ($last_seen === "") $last_seen = $row_update_time;
                    }
'''
    if old_loop in source:
        source = source.replace(old_loop, new_loop, 1)

    old_seen = '''        $last_seen = $last_update_time;
        if (!$online) {
            try {
                $seenRow = Db::name("im_online_status")->where("uid", $uid)->order("update_time desc")->find();
                if ($seenRow) $last_seen = isset($seenRow["last_seen"]) && $seenRow["last_seen"] ? strval($seenRow["last_seen"]) : (isset($seenRow["update_time"]) ? strval($seenRow["update_time"]) : $last_update_time);
            } catch (\\Exception $e) {}
        }

'''
    new_seen = '''        if (!$online && $last_seen === "") {
            try {
                $seenRows = Db::name("im_online_status")->where("uid", $uid)->order("update_time desc")->select();
                foreach ($seenRows as $seenRow) {
                    if (isset($seenRow["last_seen"]) && trim(strval($seenRow["last_seen"])) !== "" && strval($seenRow["last_seen"]) !== "0000-00-00 00:00:00") {
                        $last_seen = strval($seenRow["last_seen"]);
                        break;
                    }
                }
            } catch (\\Exception $e) {}
        }

'''
    if old_seen in source:
        source = source.replace(old_seen, new_seen, 1)

    if source == original:
        print(f"NO_CHANGE {path}")
        return False
    print(f"BACKUP {backup(path)}")
    path.write_text(source, encoding="utf-8")
    print(f"PATCHED {path}")
    return True


def main() -> None:
    changed = False
    for candidate in CANDIDATES:
        changed = patch(candidate) or changed
    print("DONE" if changed else "NO_CHANGES")


if __name__ == "__main__":
    main()
