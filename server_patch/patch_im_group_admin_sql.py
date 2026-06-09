#!/usr/bin/env python3
"""Idempotent MySQL migration for IM group avatar/admin features.
Run on server: python3 patch_im_group_admin_sql.py
It reads ThinkPHP config if possible; otherwise uses mysql CLI defaults.
"""
import os
import re
import subprocess
from pathlib import Path

ROOT = Path('/www/wwwroot/blinlin')
DB = os.environ.get('DB_NAME', '')
USER = os.environ.get('DB_USER', '')
PWD = os.environ.get('DB_PASS', '')

for cfg in [ROOT / 'config' / 'database.php', ROOT / 'application' / 'database.php', ROOT / '.env']:
    if not cfg.exists():
        continue
    text = cfg.read_text(errors='ignore')
    def pick(keys):
        for k in keys:
            m = re.search(rf"['\"]{k}['\"]\s*=>\s*['\"]([^'\"]+)", text) or re.search(rf"{k}\s*=\s*([^\n]+)", text)
            if m:
                return m.group(1).strip().strip('"\'')
        return ''
    DB = DB or pick(['database', 'DB_DATABASE'])
    USER = USER or pick(['username', 'DB_USERNAME'])
    PWD = PWD or pick(['password', 'DB_PASSWORD'])

if not DB:
    DB = 'blinlin'
if not USER:
    USER = 'root'

MYSQL = ['mysql', f'-u{USER}', DB]
if PWD:
    MYSQL.insert(2, f'-p{PWD}')

def run(sql):
    p = subprocess.run(MYSQL, input=sql, text=True, capture_output=True)
    if p.returncode != 0:
        print('SQL_FAIL:', sql, p.stderr.strip())
    else:
        print('SQL_OK:', sql.split('\n')[0][:120])

def column_exists(table, column):
    sql = f"SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='{table}' AND COLUMN_NAME='{column}';"
    p = subprocess.run(MYSQL + ['-N', '-e', sql], text=True, capture_output=True)
    return p.stdout.strip() == '1'

def index_exists(table, index):
    sql = f"SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='{table}' AND INDEX_NAME='{index}';"
    p = subprocess.run(MYSQL + ['-N', '-e', sql], text=True, capture_output=True)
    return p.stdout.strip() not in ('', '0')

def add_col(table, col, ddl):
    if column_exists(table, col):
        print('SKIP_COL', table, col)
    else:
        run(f"ALTER TABLE `{table}` ADD COLUMN {ddl};")

def add_idx(table, idx, ddl):
    if index_exists(table, idx):
        print('SKIP_IDX', table, idx)
    else:
        run(f"CREATE INDEX `{idx}` ON `{table}` {ddl};")

run("CREATE TABLE IF NOT EXISTS `mr_im_groups` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `group_no` varchar(64) NOT NULL DEFAULT '', `name` varchar(100) NOT NULL DEFAULT '', `avatar` varchar(500) NOT NULL DEFAULT '', `notice` varchar(1000) NOT NULL DEFAULT '', `owner_id` int(11) NOT NULL DEFAULT 0, `member_count` int(11) NOT NULL DEFAULT 0, `mute_all` tinyint(1) NOT NULL DEFAULT 0, `status` tinyint(1) NOT NULL DEFAULT 1, `create_time` datetime DEFAULT NULL, `update_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), UNIQUE KEY `uk_group_no` (`group_no`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;")
run("CREATE TABLE IF NOT EXISTS `mr_im_group_members` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `group_id` int(11) NOT NULL DEFAULT 0, `user_id` int(11) NOT NULL DEFAULT 0, `role` tinyint(1) NOT NULL DEFAULT 0, `nickname` varchar(100) NOT NULL DEFAULT '', `mute_until` datetime DEFAULT NULL, `status` tinyint(1) NOT NULL DEFAULT 1, `create_time` datetime DEFAULT NULL, `update_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), UNIQUE KEY `uk_group_user` (`group_id`,`user_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;")
run("CREATE TABLE IF NOT EXISTS `mr_im_group_messages` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `group_id` int(11) NOT NULL DEFAULT 0, `sender_id` int(11) NOT NULL DEFAULT 0, `message_type` int(11) NOT NULL DEFAULT 0, `content` text, `payload` mediumtext, `client_msg_no` varchar(128) NOT NULL DEFAULT '', `create_time` datetime DEFAULT NULL, PRIMARY KEY (`id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;")

for col, ddl in {
    'avatar': "`avatar` varchar(500) NOT NULL DEFAULT '' AFTER `name`",
    'notice': "`notice` varchar(1000) NOT NULL DEFAULT '' AFTER `avatar`",
    'owner_id': "`owner_id` int(11) NOT NULL DEFAULT 0 AFTER `notice`",
    'mute_all': "`mute_all` tinyint(1) NOT NULL DEFAULT 0 AFTER `member_count`",
    'status': "`status` tinyint(1) NOT NULL DEFAULT 1 AFTER `mute_all`",
    'update_time': "`update_time` datetime DEFAULT NULL AFTER `create_time`",
}.items(): add_col('mr_im_groups', col, ddl)

for col, ddl in {
    'role': "`role` tinyint(1) NOT NULL DEFAULT 0 COMMENT '0成员 1管理员 2群主' AFTER `user_id`",
    'nickname': "`nickname` varchar(100) NOT NULL DEFAULT '' AFTER `role`",
    'mute_until': "`mute_until` datetime DEFAULT NULL AFTER `nickname`",
    'status': "`status` tinyint(1) NOT NULL DEFAULT 1 AFTER `mute_until`",
    'update_time': "`update_time` datetime DEFAULT NULL AFTER `create_time`",
}.items(): add_col('mr_im_group_members', col, ddl)

for col, ddl in {
    'payload': "`payload` mediumtext NULL AFTER `content`",
    'client_msg_no': "`client_msg_no` varchar(128) NOT NULL DEFAULT '' AFTER `payload`",
}.items(): add_col('mr_im_group_messages', col, ddl)

add_idx('mr_im_groups', 'idx_im_groups_owner', '(`owner_id`)')
add_idx('mr_im_group_members', 'idx_im_group_members_role', '(`group_id`,`role`)')
add_idx('mr_im_group_members', 'idx_im_group_members_status', '(`group_id`,`status`)')
add_idx('mr_im_group_messages', 'idx_im_group_messages_client', '(`client_msg_no`)')
print('PATCH_OK im group admin db schema')
