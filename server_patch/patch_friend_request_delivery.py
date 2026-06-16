#!/usr/bin/env python3
"""Fix IM friend request delivery across app-scoped request records."""

from datetime import datetime
from pathlib import Path
import os
import shutil
import subprocess


ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"


def backup(path: Path, suffix: str) -> None:
    target = path.with_name(
        f"{path.name}.bak_{suffix}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    shutil.copy2(path, target)
    print("BACKUP", target)


def db_config():
    values = {
        "hostname": "127.0.0.1",
        "database": "blinlin",
        "username": "root",
        "password": "",
        "hostport": "3306",
    }
    env_path = ROOT / ".env"
    section = ""
    if not env_path.exists():
        return values
    for raw in env_path.read_text(errors="ignore").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith(";"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip().lower()
            continue
        if section != "database" or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip().lower()
        value = value.strip().strip('"').strip("'")
        if key in values:
            values[key] = value
    return values


def mysql(sql: str):
    config = db_config()
    env = os.environ.copy()
    env["MYSQL_PWD"] = config["password"]
    result = subprocess.run(
        [
            "mysql",
            f"-h{config['hostname']}",
            f"-u{config['username']}",
            f"-P{config.get('hostport') or '3306'}",
            config["database"],
            "-e",
            sql,
        ],
        universal_newlines=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(result.stderr.strip())
    if result.stdout.strip():
        print(result.stdout.strip())


def main() -> None:
    mysql(
        """UPDATE `im_friend_requests` r
JOIN `mr_user` u ON u.id = r.from_user_id
SET r.appid = u.appid
WHERE r.appid = 0 AND u.appid > 0"""
    )

    original = API.read_text(errors="ignore")
    source = original

    old = (
        '        Db::execute("INSERT INTO `im_friend_requests` '
        '(`appid`,`from_user_id`,`to_user_id`,`message`,`status`,`created_at`,`updated_at`) '
        'VALUES (:appid,:from_id,:to_id,:message,0,:created,:updated) '
        'ON DUPLICATE KEY UPDATE `appid`=VALUES(`appid`),`message`=VALUES(`message`),'
        '`status`=0,`updated_at`=VALUES(`updated_at`)", ["appid"=>intval($this->appid), '
        '"from_id"=>intval($user["id"]), "to_id"=>$friendId, "message"=>$message, '
        '"created"=>$now, "updated"=>$now]);'
    )
    new = (
        '        Db::execute("INSERT INTO `im_friend_requests` '
        '(`appid`,`from_user_id`,`to_user_id`,`message`,`status`,`created_at`,`updated_at`) '
        'VALUES (:appid,:from_id,:to_id,:message,0,:created,:updated) '
        'ON DUPLICATE KEY UPDATE `appid`=:appid_update,`message`=:message_update,'
        '`status`=0,`updated_at`=:updated_update", ["appid"=>intval($this->appid), '
        '"from_id"=>intval($user["id"]), "to_id"=>$friendId, "message"=>$message, '
        '"created"=>$now, "updated"=>$now, "appid_update"=>intval($this->appid), '
        '"message_update"=>$message, "updated_update"=>$now]);'
    )
    if old in source:
        source = source.replace(old, new, 1)

    source = source.replace(
        '            ->where("r.appid", $this->appid);',
        '            ->where("r.appid", "in", [intval($this->appid), 0]);',
        1,
    )
    source = source.replace(
        '$request = Db::table("im_friend_requests")->where("appid", $this->appid)->where("from_user_id", $fromId)->where("to_user_id", intval($user["id"]))->find();',
        '$request = Db::table("im_friend_requests")->where("appid", "in", [intval($this->appid), 0])->where("from_user_id", $fromId)->where("to_user_id", intval($user["id"]))->find();',
        1,
    )

    if "public function delete_friend_request()" not in source:
        marker = "    public function friend_request_handle(){ return $this->handle_friend_request(); }\n"
        insert = r'''
    public function delete_friend_request()
    {
        $this->blinEnsureFriendTables();
        $user = $this->user_info;
        $uid = intval($user["id"]);
        $fromId = intval(input("from_user_id") ?: input("friend_id") ?: input("user_id"));
        $requestId = intval(input("request_id") ?: input("id"));
        $query = Db::table("im_friend_requests")->where("appid", "in", [intval($this->appid), 0]);
        if ($requestId > 0) {
            $query->where("id", $requestId)->where("(from_user_id={$uid} OR to_user_id={$uid})");
        } else {
            if ($fromId <= 0 || $fromId == $uid) $this->json(0, "好友申请不存在");
            $query->where("(from_user_id={$fromId} AND to_user_id={$uid}) OR (from_user_id={$uid} AND to_user_id={$fromId})");
        }
        $request = $query->find();
        if (!$request) $this->json(0, "好友申请不存在");
        Db::table("im_friend_requests")->where("id", intval($request["id"]))->delete();
        Db::name("message_notification")
            ->where("appid", $this->appid)
            ->where("type", 20)
            ->where("user_id", $uid)
            ->where("postid", intval($request["from_user_id"] == $uid ? $request["to_user_id"] : $request["from_user_id"]))
            ->delete();
        $this->json(1, "已删除好友申请");
    }

    public function remove_friend_request(){ return $this->delete_friend_request(); }
    public function friend_request_delete(){ return $this->delete_friend_request(); }
'''
        if marker not in source:
            raise SystemExit("friend_request_handle_marker_not_found")
        source = source.replace(marker, marker + insert, 1)

    if source == original:
        print("NO_CHANGE", API)
        return
    backup(API, "friend_request_delivery")
    API.write_text(source)
    print("PATCHED", API)


if __name__ == "__main__":
    main()
