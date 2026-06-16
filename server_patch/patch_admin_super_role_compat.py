#!/usr/bin/env python3
"""Keep legacy admin accounts visible after app-scope isolation."""

from datetime import datetime
from pathlib import Path
import os
import shutil
import subprocess


ROOT = Path("/www/wwwroot/blinlin")
BACKEND = ROOT / "application/admin/controller/Backend.php"


def backup(path):
    target = path.with_name(
        "%s.bak_super_role_compat_%s" % (path.name, datetime.now().strftime("%Y%m%d%H%M%S"))
    )
    shutil.copy2(path, target)
    print("PATCH_BACKUP", target)


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


def mysql(sql):
    config = db_config()
    env = os.environ.copy()
    env["MYSQL_PWD"] = config["password"]
    result = subprocess.run(
        [
            "mysql",
            "-h%s" % config["hostname"],
            "-u%s" % config["username"],
            "-P%s" % (config.get("hostport") or "3306"),
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
        raise SystemExit(result.stderr)
    if result.stdout.strip():
        print(result.stdout.strip())


def main():
    source = BACKEND.read_text()
    old = '''    protected function blinIsSuperAdmin()
    {
        $admin = $this->blinCurrentAdminFull();
        return isset($admin["role_id"]) && intval($admin["role_id"]) === 0;
    }
'''
    new = '''    protected function blinIsSuperAdmin()
    {
        $admin = $this->blinCurrentAdminFull();
        if (!$admin) return false;
        if (isset($admin["id"]) && intval($admin["id"]) === 1) return true;
        if (!isset($admin["role_id"]) || $admin["role_id"] === null || $admin["role_id"] === "") return true;
        return intval($admin["role_id"]) === 0;
    }
'''
    if new not in source:
        if old not in source:
            raise SystemExit("SUPER_ADMIN_BLOCK_NOT_FOUND")
        backup(BACKEND)
        BACKEND.write_text(source.replace(old, new, 1))
        print("PATCHED", BACKEND)
    else:
        print("NO_CHANGE", BACKEND)
    mysql("UPDATE `mr_admin` SET `role_id`=0 WHERE `id`=1 AND (`role_id` IS NULL OR `role_id`=''); SELECT id,username,role_id,managed_appids FROM `mr_admin` ORDER BY id;")


if __name__ == "__main__":
    main()
