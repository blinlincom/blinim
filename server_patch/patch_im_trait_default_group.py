#!/usr/bin/env python3
"""Patch live ImApiTrait group APIs for app-scoped default groups."""

from datetime import datetime
from pathlib import Path
import shutil


ROOT = Path("/www/wwwroot/blinlin")
TRAIT = ROOT / "application/api/controller/traits/ImApiTrait.php"


def backup(path):
    target = path.with_name(
        "%s.bak_trait_default_group_%s" % (path.name, datetime.now().strftime("%Y%m%d%H%M%S"))
    )
    shutil.copy2(path, target)
    print("PATCH_BACKUP", target)


def find_method(source, signature):
    start = source.find(signature)
    if start == -1:
        raise SystemExit("METHOD_NOT_FOUND:%s" % signature)
    brace = source.find("{", start)
    if brace == -1:
        raise SystemExit("METHOD_BRACE_NOT_FOUND:%s" % signature)
    depth = 0
    in_single = False
    in_double = False
    escape = False
    i = brace
    while i < len(source):
        ch = source[i]
        if escape:
            escape = False
            i += 1
            continue
        if ch == "\\" and (in_single or in_double):
            escape = True
            i += 1
            continue
        if ch == "'" and not in_double:
            in_single = not in_single
            i += 1
            continue
        if ch == '"' and not in_single:
            in_double = not in_double
            i += 1
            continue
        if not in_single and not in_double:
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    end = i + 1
                    if end < len(source) and source[end] == "\r":
                        end += 1
                    if end < len(source) and source[end] == "\n":
                        end += 1
                    return start, end
        i += 1
    raise SystemExit("METHOD_END_NOT_FOUND:%s" % signature)


def replace_method(source, signature, body):
    start, end = find_method(source, signature)
    current = source[start:end]
    if current.strip() == body.strip():
        return source
    return source[:start] + body.rstrip() + "\n" + source[end:]


def insert_after_method(source, signature, block, marker):
    if marker in source:
        return source
    start, end = find_method(source, signature)
    return source[:end] + "\n" + block.rstrip() + "\n" + source[end:]


ENSURE_TABLES = r'''    private function ensure_im_group_tables()
    {
        Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_groups` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `group_no` varchar(64) NOT NULL DEFAULT '', `name` varchar(100) NOT NULL DEFAULT '', `avatar` varchar(500) NOT NULL DEFAULT '', `notice` varchar(1000) NOT NULL DEFAULT '', `owner_id` int(11) NOT NULL DEFAULT 0, `member_count` int(11) NOT NULL DEFAULT 0, `mute_all` tinyint(1) NOT NULL DEFAULT 0, `status` tinyint(1) NOT NULL DEFAULT 1, `default_group` tinyint(1) NOT NULL DEFAULT 0, `create_time` datetime DEFAULT NULL, `update_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), UNIQUE KEY `uk_group_no` (`group_no`), KEY `idx_app_default` (`appid`,`default_group`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
        Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_group_members` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `group_id` int(11) NOT NULL DEFAULT 0, `user_id` int(11) NOT NULL DEFAULT 0, `role` tinyint(1) NOT NULL DEFAULT 0, `nickname` varchar(100) NOT NULL DEFAULT '', `mute_until` datetime DEFAULT NULL, `status` tinyint(1) NOT NULL DEFAULT 1, `create_time` datetime DEFAULT NULL, `update_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), UNIQUE KEY `uk_group_user` (`group_id`,`user_id`), KEY `idx_app_user` (`appid`,`user_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
        Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_group_messages` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `group_id` int(11) NOT NULL DEFAULT 0, `sender_id` int(11) NOT NULL DEFAULT 0, `message_type` int(11) NOT NULL DEFAULT 0, `content` text, `payload` mediumtext, `client_msg_no` varchar(128) NOT NULL DEFAULT '', `create_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), KEY `idx_group_id` (`group_id`), KEY `idx_create_time` (`create_time`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
        $this->im_group_add_column('mr_im_groups', 'avatar', "ALTER TABLE `mr_im_groups` ADD COLUMN `avatar` varchar(500) NOT NULL DEFAULT '' AFTER `name`");
        $this->im_group_add_column('mr_im_groups', 'notice', "ALTER TABLE `mr_im_groups` ADD COLUMN `notice` varchar(1000) NOT NULL DEFAULT '' AFTER `avatar`");
        $this->im_group_add_column('mr_im_groups', 'owner_id', "ALTER TABLE `mr_im_groups` ADD COLUMN `owner_id` int(11) NOT NULL DEFAULT 0 AFTER `notice`");
        $this->im_group_add_column('mr_im_groups', 'member_count', "ALTER TABLE `mr_im_groups` ADD COLUMN `member_count` int(11) NOT NULL DEFAULT 0 AFTER `owner_id`");
        $this->im_group_add_column('mr_im_groups', 'mute_all', "ALTER TABLE `mr_im_groups` ADD COLUMN `mute_all` tinyint(1) NOT NULL DEFAULT 0 AFTER `member_count`");
        $this->im_group_add_column('mr_im_groups', 'default_group', "ALTER TABLE `mr_im_groups` ADD COLUMN `default_group` tinyint(1) NOT NULL DEFAULT 0 AFTER `status`");
        $this->im_group_add_column('mr_im_groups', 'update_time', "ALTER TABLE `mr_im_groups` ADD COLUMN `update_time` datetime DEFAULT NULL");
        $this->im_group_add_column('mr_im_group_members', 'role', "ALTER TABLE `mr_im_group_members` ADD COLUMN `role` tinyint(1) NOT NULL DEFAULT 0 AFTER `user_id`");
        $this->im_group_add_column('mr_im_group_members', 'nickname', "ALTER TABLE `mr_im_group_members` ADD COLUMN `nickname` varchar(100) NOT NULL DEFAULT '' AFTER `role`");
        $this->im_group_add_column('mr_im_group_members', 'mute_until', "ALTER TABLE `mr_im_group_members` ADD COLUMN `mute_until` datetime DEFAULT NULL AFTER `nickname`");
        $this->im_group_add_column('mr_im_group_members', 'update_time', "ALTER TABLE `mr_im_group_members` ADD COLUMN `update_time` datetime DEFAULT NULL");
        $this->im_group_add_column('mr_im_group_messages', 'payload', "ALTER TABLE `mr_im_group_messages` ADD COLUMN `payload` mediumtext NULL AFTER `content`");
        $this->im_group_add_column('mr_im_group_messages', 'client_msg_no', "ALTER TABLE `mr_im_group_messages` ADD COLUMN `client_msg_no` varchar(128) NOT NULL DEFAULT '' AFTER `payload`");
    }'''


HELPERS = r'''    // blin-im-trait-default-group
    private function blinTraitImConfig($key = null, $default = null)
    {
        $config = [];
        if (isset($this->app_info['im_configuration']) && is_array($this->app_info['im_configuration'])) {
            $config = $this->app_info['im_configuration'];
        } elseif (isset($this->app_info['im_configuration']) && $this->app_info['im_configuration']) {
            $decoded = json_decode($this->app_info['im_configuration'], true);
            if (is_array($decoded)) $config = $decoded;
        }
        $defaults = [
            'voice_message_switch' => '0',
            'admin_app_message_switch' => '0',
            'default_group_switch' => '0',
            'default_group_join_switch' => '0',
            'default_group_id' => '0',
            'default_group_name' => '',
            'default_group_avatar' => '',
            'default_group_notice' => '',
            'default_group_owner_id' => '0',
        ];
        $config = array_merge($defaults, $config);
        if ($key === null) return $config;
        return isset($config[$key]) ? $config[$key] : $default;
    }

    private function blinTraitFeatureOpen($key)
    {
        return intval($this->blinTraitImConfig($key, 1)) === 0;
    }

    private function blinTraitSyncChannel($group, $uids = [], $create = false)
    {
        if (!$group || !isset($group['group_no']) || trim(strval($group['group_no'])) === '') return;
        if (!config('wukongim.enable')) return;
        $subscribers = [];
        foreach ($uids as $uid) {
            $uid = intval($uid);
            if ($uid > 0) $subscribers[] = $this->appid . '_' . $uid;
        }
        $subscribers = array_values(array_unique($subscribers));
        try {
            $wkim = new \app\common\tool\WukongIM();
            if ($create) {
                $wkim->createChannel($group['group_no'], 2, $subscribers, [
                    'large' => 0,
                    'ban' => intval(isset($group['status']) && intval($group['status']) == 1 ? 0 : 1),
                    'disband' => 0,
                ]);
            } elseif ($subscribers) {
                $wkim->addChannelSubscribers($group['group_no'], 2, $subscribers);
            }
        } catch (\Exception $e) {}
    }

    private function blinTraitMessageType($payload, $content)
    {
        $raw = '';
        if (is_array($payload)) {
            if (isset($payload['msg_type'])) $raw = strval($payload['msg_type']);
            elseif (isset($payload['type'])) $raw = strval($payload['type']);
            elseif (isset($payload['message_type'])) $raw = strval($payload['message_type']);
        }
        $raw = strtolower(trim($raw));
        if ($raw === 'image' || $raw === 'photo' || $raw === 'pic') return 1;
        if ($raw === 'voice' || $raw === 'audio') return 5;
        if ($raw === 'video') return 3;
        if ($raw === 'file') return 4;
        if ($raw === 'call' || $raw === 'call_signal' || $raw === 'group_call') return 6;
        if ($raw === 'system' || $raw === 'notice') return 9;
        return 0;
    }

    private function blinTraitDefaultGroup()
    {
        if (!$this->blinTraitFeatureOpen('default_group_switch')) return null;
        $this->ensure_im_group_tables();
        $config = $this->blinTraitImConfig();
        $now = date('Y-m-d H:i:s');
        $groupId = intval($config['default_group_id']);
        $group = null;
        if ($groupId > 0) {
            $group = Db::name('im_groups')->where('appid', $this->appid)->where('id', $groupId)->where('status', 1)->find();
        }
        if (!$group) {
            $group = Db::name('im_groups')->where('appid', $this->appid)->where('default_group', 1)->where('status', 1)->order('id asc')->find();
        }
        $appName = isset($this->app_info['appname']) && trim(strval($this->app_info['appname'])) !== '' ? trim(strval($this->app_info['appname'])) : '官方';
        $name = trim(strval($config['default_group_name']));
        if ($name === '') $name = $appName . '官方群';
        $avatar = trim(strval($config['default_group_avatar']));
        if ($avatar === '' && isset($this->app_info['appicon'])) $avatar = trim(strval($this->app_info['appicon']));
        $notice = trim(strval($config['default_group_notice']));
        $ownerId = intval($config['default_group_owner_id']);
        if ($ownerId > 0) {
            $owner = Db::name('user')->where('appid', $this->appid)->where('id', $ownerId)->find();
            if (!$owner) $ownerId = 0;
        }
        $update = [
            'name' => $name,
            'avatar' => $avatar,
            'notice' => $notice,
            'owner_id' => $ownerId,
            'default_group' => 1,
            'status' => 1,
            'update_time' => $now,
        ];
        if ($group) {
            Db::name('im_groups')->where('appid', $this->appid)->where('id', intval($group['id']))->update($update);
            $group = Db::name('im_groups')->where('appid', $this->appid)->where('id', intval($group['id']))->find();
        } else {
            $groupNo = 'default_group_' . $this->appid . '_' . time() . '_' . mt_rand(1000, 9999);
            $update['appid'] = $this->appid;
            $update['group_no'] = $groupNo;
            $update['member_count'] = 0;
            $update['mute_all'] = 0;
            $update['create_time'] = $now;
            $groupId = Db::name('im_groups')->insertGetId($update);
            $group = Db::name('im_groups')->where('appid', $this->appid)->where('id', $groupId)->find();
            $this->blinTraitSyncChannel($group, $ownerId > 0 ? [$ownerId] : [], true);
        }
        if ($ownerId > 0) $this->blinTraitAddUserToGroup($group, $ownerId, 2);
        return $group;
    }

    private function blinTraitAddUserToGroup($group, $userId, $role = 0)
    {
        if (!$group || intval($userId) <= 0) return false;
        $userId = intval($userId);
        $role = intval($role);
        $groupId = intval($group['id']);
        $user = Db::name('user')->where('appid', $this->appid)->where('id', $userId)->find();
        if (!$user) return false;
        $now = date('Y-m-d H:i:s');
        $exists = Db::name('im_group_members')->where('appid', $this->appid)->where('group_id', $groupId)->where('user_id', $userId)->find();
        if ($exists) {
            $newRole = max(intval($exists['role']), $role);
            Db::name('im_group_members')->where('id', intval($exists['id']))->update(['role'=>$newRole, 'status'=>1, 'update_time'=>$now]);
        } else {
            Db::name('im_group_members')->insert(['appid'=>$this->appid, 'group_id'=>$groupId, 'user_id'=>$userId, 'role'=>$role, 'status'=>1, 'create_time'=>$now, 'update_time'=>$now]);
        }
        $count = Db::name('im_group_members')->where('appid', $this->appid)->where('group_id', $groupId)->where('status', 1)->count();
        Db::name('im_groups')->where('appid', $this->appid)->where('id', $groupId)->update(['member_count'=>$count, 'update_time'=>$now]);
        $this->blinTraitSyncChannel($group, [$userId], false);
        return true;
    }

    private function blinTraitAutoJoinDefaultGroup($userId)
    {
        if (!$this->blinTraitFeatureOpen('default_group_switch') || !$this->blinTraitFeatureOpen('default_group_join_switch')) return;
        try {
            $group = $this->blinTraitDefaultGroup();
            if ($group) $this->blinTraitAddUserToGroup($group, intval($userId), 0);
        } catch (\Exception $e) {}
    }'''


CREATE_GROUP = r'''    public function create_im_group()
    {
        $data = input();
        $rule = ['usertoken|用户token' => 'require', 'name|群名称' => 'require'];
        $validate = new Validate($rule);
        if (!$validate->check($data)) { $this->json(0, $validate->getError()); }
        $user = $this->current_group_user();
        $this->ensure_im_group_tables();
        $idsRaw = isset($data['member_ids']) ? strval($data['member_ids']) : '';
        $memberIds = [];
        foreach (explode(',', $idsRaw) as $id) { $v = intval(trim($id)); if ($v > 0 && $v != intval($user['id'])) $memberIds[$v] = $v; }
        if (empty($memberIds)) { $this->json(0, '请选择群成员'); }
        $validUsers = Db::name('user')->where('appid', $this->appid)->where('id', 'in', array_values($memberIds))->column('id');
        if (empty($validUsers)) { $this->json(0, '群成员不存在'); }
        $now = date('Y-m-d H:i:s');
        $groupNo = 'group_' . $this->appid . '_' . time() . '_' . mt_rand(1000,9999);
        $name = trim(strval($data['name']));
        $avatar = isset($data['avatar']) ? trim(strval($data['avatar'])) : (isset($data['group_avatar']) ? trim(strval($data['group_avatar'])) : '');
        $notice = isset($data['notice']) ? trim(strval($data['notice'])) : '';
        $groupId = Db::name('im_groups')->insertGetId(['appid'=>$this->appid, 'group_no'=>$groupNo, 'name'=>$name, 'avatar'=>$avatar, 'notice'=>$notice, 'owner_id'=>intval($user['id']), 'member_count'=>0, 'mute_all'=>0, 'default_group'=>0, 'status'=>1, 'create_time'=>$now, 'update_time'=>$now]);
        $group = Db::name('im_groups')->where('appid', $this->appid)->where('id', $groupId)->find();
        $this->blinTraitSyncChannel($group, array_merge([intval($user['id'])], array_values($validUsers)), true);
        $this->blinTraitAddUserToGroup($group, intval($user['id']), 2);
        foreach ($validUsers as $uid) { $this->blinTraitAddUserToGroup($group, intval($uid), 0); }
        $group = Db::name('im_groups')->where('appid', $this->appid)->where('id', $groupId)->find();
        $this->json(1, '创建成功', ['id'=>$groupId, 'group_id'=>$groupId, 'group_no'=>$groupNo, 'name'=>$name, 'avatar'=>$avatar, 'notice'=>$notice, 'member_count'=>intval($group ? $group['member_count'] : (count($validUsers)+1))]);
    }'''


GROUP_LIST = r'''    public function get_im_group_list()
    {
        $data = input();
        $rule = ['usertoken|用户token' => 'require'];
        $validate = new Validate($rule);
        if (!$validate->check($data)) { $this->json(0, $validate->getError()); }
        $user = $this->current_group_user();
        $this->ensure_im_group_tables();
        $this->blinTraitAutoJoinDefaultGroup(intval($user['id']));
        $rows = Db::name('im_group_members')->alias('m')
            ->join('im_groups g', 'g.id=m.group_id')
            ->where('m.appid', $this->appid)
            ->where('m.user_id', intval($user['id']))
            ->where('m.status', 1)
            ->where('g.appid', $this->appid)
            ->where('g.status', 1)
            ->field('g.id,g.id as group_id,g.group_no,g.name,g.avatar,g.notice,g.owner_id,g.member_count,g.default_group,g.update_time,m.role')
            ->order('g.default_group desc,g.update_time desc,g.id desc')
            ->select();
        $list = [];
        foreach (($rows ?: []) as $row) {
            $row['group_id'] = intval($row['id']);
            $row['member_count'] = intval($row['member_count']);
            $row['default_group'] = intval(isset($row['default_group']) ? $row['default_group'] : 0);
            $row['my_role'] = $this->im_group_role_name($row['role']);
            $list[] = $row;
        }
        $this->json(1, 'success', $list);
    }'''


SEND_GROUP_MESSAGE = r'''    public function send_im_group_message()
    {
        $data = input();
        $rule = ['usertoken|用户token' => 'require', 'group_id|群ID' => 'require|number'];
        $validate = new Validate($rule);
        if (!$validate->check($data)) { $this->json(0, $validate->getError()); }
        $user = $this->current_group_user();
        $this->ensure_im_group_tables();
        $groupId = intval($data['group_id']);
        $member = Db::name('im_group_members')->where('appid', $this->appid)->where('group_id', $groupId)->where('user_id', intval($user['id']))->where('status', 1)->find();
        if (!$member) { $this->json(0, '你不在该群聊中'); }
        $group = Db::name('im_groups')->where('appid', $this->appid)->where('id', $groupId)->where('status', 1)->find();
        if (!$group) { $this->json(0, '群聊不存在'); }
        $content = isset($data['content']) ? strval($data['content']) : '';
        $payloadRaw = isset($data['im_payload']) ? strval($data['im_payload']) : (isset($data['payload']) ? strval($data['payload']) : '');
        $payload = $payloadRaw ? json_decode($payloadRaw, true) : null;
        if (!is_array($payload)) {
            $payload = ['msg_type'=>'text', 'content'=>['text'=>$content]];
        }
        if ($content === '' && isset($payload['content']) && is_array($payload['content']) && isset($payload['content']['text'])) {
            $content = strval($payload['content']['text']);
        }
        $payload['group_id'] = $groupId;
        $payload['group_no'] = $group['group_no'];
        $payload['from_user_id'] = intval($user['id']);
        $payload['from_uid'] = $this->appid . '_' . intval($user['id']);
        $payload['to_uid'] = $group['group_no'];
        $payload['create_time'] = date('Y-m-d H:i:s');
        $clientNo = isset($payload['client_msg_no']) ? strval($payload['client_msg_no']) : ('group_msg_' . $groupId . '_' . time() . '_' . mt_rand(1000,9999));
        $payload['client_msg_no'] = $clientNo;
        $messageType = $this->blinTraitMessageType($payload, $content);
        $messageId = Db::name('im_group_messages')->insertGetId(['appid'=>$this->appid, 'group_id'=>$groupId, 'sender_id'=>intval($user['id']), 'message_type'=>$messageType, 'content'=>$content, 'payload'=>'', 'client_msg_no'=>$clientNo, 'create_time'=>date('Y-m-d H:i:s')]);
        $payload['message_id'] = intval($messageId);
        Db::name('im_group_messages')->where('appid', $this->appid)->where('id', $messageId)->update(['payload'=>json_encode($payload, JSON_UNESCAPED_UNICODE)]);
        Db::name('im_groups')->where('appid', $this->appid)->where('id', $groupId)->update(['update_time'=>date('Y-m-d H:i:s')]);
        try { if (config('wukongim.enable')) { $wkim = new \app\common\tool\WukongIM(); $wkim->sendMessage($this->appid . '_' . intval($user['id']), $group['group_no'], 2, $payload, $clientNo, ['no_persist'=>0,'red_dot'=>1,'sync_once'=>0]); } } catch (\Exception $e) {}
        $this->json(1, '发送成功', ['message_id'=>$messageId, 'client_msg_no'=>$clientNo, 'message_type'=>$messageType, 'im_payload'=>$payload]);
    }'''


CHAT_LOG = r'''    public function get_im_group_chat_log()
    {
        $data = input();
        $rule = ['usertoken|用户token' => 'require', 'group_id|群ID' => 'require|number'];
        $validate = new Validate($rule);
        if (!$validate->check($data)) { $this->json(0, $validate->getError()); }
        $user = $this->current_group_user();
        $this->ensure_im_group_tables();
        $groupId = intval($data['group_id']);
        $group = Db::name('im_groups')->where('appid', $this->appid)->where('id', $groupId)->where('status', 1)->find();
        if (!$group) { $this->json(0, '群聊不存在'); }
        $member = Db::name('im_group_members')->where('appid', $this->appid)->where('group_id', $groupId)->where('user_id', intval($user['id']))->where('status', 1)->find();
        if (!$member) { $this->json(0, '你不在该群聊中'); }
        $page = max(1, intval(isset($data['page']) ? $data['page'] : 1));
        $limit = max(1, min(100, intval(isset($data['limit']) ? $data['limit'] : 30)));
        $offset = ($page - 1) * $limit;
        $rows = Db::name('im_group_messages')->where('appid', $this->appid)->where('group_id', $groupId)->order('id desc')->limit($offset, $limit)->select();
        $list = [];
        foreach (($rows ?: []) as $r) {
            $payload = isset($r['payload']) ? strval($r['payload']) : '';
            if ($payload !== '') {
                $decoded = json_decode($payload, true);
                if (is_array($decoded) && !isset($decoded['message_id'])) {
                    $decoded['message_id'] = intval($r['id']);
                    $payload = json_encode($decoded, JSON_UNESCAPED_UNICODE);
                }
            }
            $list[] = ['message'=>['id'=>intval($r['id']), 'message_id'=>intval($r['id']), 'sender_id'=>intval($r['sender_id']), 'receiver_id'=>$groupId, 'group_id'=>$groupId, 'message_type'=>intval($r['message_type']), 'content'=>$r['content'], 'im_payload'=>$payload, 'client_msg_no'=>isset($r['client_msg_no']) ? $r['client_msg_no'] : '', 'create_time'=>$r['create_time']]];
        }
        $this->json(1, 'success', ['list'=>$list]);
    }'''


ADD_MEMBERS = r'''    public function add_im_group_members()
    {
        $data = input();
        $rule = ['usertoken|用户token' => 'require', 'group_id|群ID' => 'require|number'];
        $validate = new Validate($rule);
        if (!$validate->check($data)) { $this->json(0, $validate->getError()); }
        $user = $this->im_group_user();
        $this->ensure_im_group_admin_tables();
        $groupId = intval($data['group_id']);
        if (!$this->im_group_can_manage($groupId, intval($user['id']))) { $this->json(0, '没有群管理权限'); }
        $group = Db::name('im_groups')->where('appid', $this->appid)->where('id', $groupId)->where('status', 1)->find();
        if (!$group) { $this->json(0, '群聊不存在'); }
        $raw = isset($data['user_ids']) ? $data['user_ids'] : (isset($data['member_ids']) ? $data['member_ids'] : '');
        $ids = [];
        foreach (explode(',', strval($raw)) as $id) { $v = intval(trim($id)); if ($v > 0) $ids[$v] = $v; }
        if (!$ids) { $this->json(0, '请选择成员'); }
        $validUsers = Db::name('user')->where('appid', $this->appid)->where('id', 'in', array_values($ids))->column('id');
        if (!$validUsers) { $this->json(0, '成员不属于当前应用'); }
        $added = 0;
        foreach ($validUsers as $uid) {
            if ($this->blinTraitAddUserToGroup($group, intval($uid), 0)) $added++;
        }
        $count = Db::name('im_group_members')->where('appid', $this->appid)->where('group_id', $groupId)->where('status', 1)->count();
        $this->json(1, '添加成功', ['added'=>$added, 'member_count'=>$count]);
    }'''


def main():
    source = TRAIT.read_text()
    original = source
    source = replace_method(source, "    private function ensure_im_group_tables()", ENSURE_TABLES)
    source = insert_after_method(source, "    private function current_group_user()", HELPERS, "blin-im-trait-default-group")
    source = replace_method(source, "    public function create_im_group()", CREATE_GROUP)
    source = replace_method(source, "    public function get_im_group_list()", GROUP_LIST)
    source = replace_method(source, "    public function send_im_group_message()", SEND_GROUP_MESSAGE)
    source = replace_method(source, "    public function get_im_group_chat_log()", CHAT_LOG)
    source = replace_method(source, "    public function add_im_group_members()", ADD_MEMBERS)
    if source == original:
        print("NO_CHANGE", TRAIT)
        return
    backup(TRAIT)
    TRAIT.write_text(source)
    print("PATCHED", TRAIT)


if __name__ == "__main__":
    main()
