#!/usr/bin/env python3
"""Harden red-packet spoof guards and backfill app switch defaults."""
from datetime import datetime
from pathlib import Path
import json
import os
import re
import subprocess


ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"


def backup(path: Path, suffix: str) -> str:
    target = path.with_name(
        f"{path.name}.bak_{suffix}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    target.write_text(path.read_text(errors="ignore"))
    return str(target)


PRIVATE_GUARD = '''        if (trim(strval(input("msg_type"))) === "red_packet" || preg_match('/"msg_type"\\\\s*:\\\\s*"red_packet"/', strval($client_payload))) {
            $this->json(0, "普通消息接口不能发送红包，请使用红包接口");
        }
'''

GROUP_GUARD = '''        if (trim(strval(input("msg_type"))) === "red_packet" || preg_match('/"msg_type"\\\\s*:\\\\s*"red_packet"/', strval($rawPayload))) {
            $this->json(0, "群普通消息接口不能发送红包，请使用群红包接口");
        }
'''


def patch_api() -> bool:
    source = API.read_text(errors="ignore")
    original = source
    if "trim(strval(input(\"msg_type\"))) === \"red_packet\"" not in source:
        marker = '''        if ($client_payload) {
            $decoded_client_no_payload = json_decode($client_payload, true);
'''
        if marker not in source:
            raise SystemExit("PRIVATE_GUARD_MARKER_NOT_FOUND")
        source = source.replace(marker, PRIVATE_GUARD + marker, 1)
        marker = '''        if ($rawPayload) {
            $decoded = json_decode(strval($rawPayload), true);
'''
        if marker not in source:
            raise SystemExit("GROUP_GUARD_MARKER_NOT_FOUND")
        source = source.replace(marker, GROUP_GUARD + marker, 1)
    if source == original:
        return False
    print("PATCH_Api.php_BACKUP", backup(API, "red_packet_guard_defaults"))
    API.write_text(source)
    return True


def db_config() -> dict:
    values = {
        "hostname": "127.0.0.1",
        "database": "blinlin",
        "username": "root",
        "password": "",
        "hostport": "3306",
        "prefix": "mr_",
    }
    env_path = ROOT / ".env"
    section = ""
    if not env_path.exists():
        return values
    for raw in env_path.read_text(errors="ignore").splitlines():
        line = raw.strip()
        if not line or line.startswith(";") or line.startswith("#"):
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


def mysql(config: dict, sql: str) -> subprocess.CompletedProcess:
    env = os.environ.copy()
    env["MYSQL_PWD"] = config.get("password", "")
    return subprocess.run(
        [
            "mysql",
            f"-h{config.get('hostname') or '127.0.0.1'}",
            f"-u{config.get('username') or 'root'}",
            f"-P{config.get('hostport') or '3306'}",
            config.get("database") or "blinlin",
            "-Nse",
            sql,
        ],
        universal_newlines=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        check=False,
    )


def sql_quote(value: str) -> str:
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"


def backfill_defaults() -> None:
    config = db_config()
    prefix = config.get("prefix", "mr_")
    if not re.fullmatch(r"[A-Za-z0-9_]*", prefix):
        raise SystemExit("UNSAFE_DB_PREFIX")
    table = f"`{prefix}app`"
    rows = mysql(config, f"SELECT appid, forum_configuration FROM {table}")
    if rows.returncode != 0:
        raise SystemExit(rows.stderr.strip() or "MYSQL_SELECT_FAILED")
    changed = 0
    for line in rows.stdout.splitlines():
        if "\t" not in line:
            continue
        appid, raw = line.split("\t", 1)
        try:
            data = json.loads(raw) if raw.strip() else {}
        except json.JSONDecodeError:
            data = {}
        if not isinstance(data, dict):
            data = {}
        before = dict(data)
        data.setdefault("transfer_switch", "0")
        data.setdefault("red_packet_switch", "0")
        if data == before:
            continue
        encoded = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
        update = mysql(
            config,
            f"UPDATE {table} SET forum_configuration={sql_quote(encoded)} WHERE appid={int(appid)}",
        )
        if update.returncode != 0:
            raise SystemExit(update.stderr.strip() or "MYSQL_UPDATE_FAILED")
        changed += 1
    print(f"BACKFILLED_RED_PACKET_SWITCH_DEFAULTS {changed}")


def main() -> None:
    changed = patch_api()
    backfill_defaults()
    print("PATCHED_RED_PACKET_GUARD_AND_DEFAULTS" if changed else "RED_PACKET_GUARD_ALREADY_HARDENED")


if __name__ == "__main__":
    main()
