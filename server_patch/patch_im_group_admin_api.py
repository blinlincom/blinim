#!/usr/bin/env python3
"""Patch ThinkPHP Api.php with IM group avatar/admin/member management APIs.
Run on server after database migration:
  python3 /tmp/patch_im_group_admin_api.py
"""
from pathlib import Path

p = Path('/www/wwwroot/blinlin/application/api/controller/Api.php')
s = p.read_text(errors='ignore')
backup = p.with_suffix('.php.bak_im_group_admin_20260609')
backup.write_text(s)

if 'public function get_im_group_members()' in s and 'public function set_im_group_admin()' in s:
    print('GROUP_ADMIN_API_ALREADY_EXISTS')
    raise SystemExit(0)

marker = '\n    //获取悟空IM连接信息\n'
if marker not in s:
    marker = '\n    public function get_im_connect_info()'
if marker not in s:
    raise SystemExit('MARKER_NOT_FOUND')

code = r'''
    private function ensure_im_group_admin_tables()
    {
        if (method_exists($this, 'ensure_im_group_tables')) { $this->ensure_im_group_tables(); }
        Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_groups` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `group_no` varchar(64) NOT NULL DEFAULT '', `name` varchar(100) NOT NULL DEFAULT '', `avatar` varchar(500) NOT NULL DEFAULT '', `notice` varchar(1000) NOT NULL DEFAULT '', `owner_id` int(11) NOT NULL DEFAULT 0, `member_count` int(11) NOT NULL DEFAULT 0, `mute_all` tinyint(1) NOT NULL DEFAULT 0, `status` tinyint(1) NOT NULL DEFAULT 1, `create_time` datetime DEFAULT NULL, `update_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), UNIQUE KEY `uk_group_no` (`group_no`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
        Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_group_members` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `group_id` int(11) NOT NULL DEFAULT 0, `user_id` int(11) NOT NULL DEFAULT 0, `role` tinyint(1) NOT NULL DEFAULT 0, `nickname` varchar(100) NOT NULL DEFAULT '', `mute_until` datetime DEFAULT NULL, `status` tinyint(1) NOT NULL DEFAULT 1, `create_time` datetime DEFAULT NULL, `update_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), UNIQUE KEY `uk_group_user` (`group_id`,`user_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
        Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_group_messages` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `group_id` int(11) NOT NULL DEFAULT 0, `sender_id` int(11) NOT NULL DEFAULT 0, `message_type` int(11) NOT NULL DEFAULT 0, `content` text, `payload` mediumtext, `client_msg_no` varchar(128) NOT NULL DEFAULT '', `create_time` datetime DEFAULT NULL, PRIMARY KEY (`id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
        $this->im_group_add_column('mr_im_groups', 'avatar', "ALTER TABLE `mr_im_groups` ADD COLUMN `avatar` varchar(500) NOT NULL DEFAULT '' AFTER `name`");
        $this->im_group_add_column('mr_im_groups', 'notice', "ALTER TABLE `mr_im_groups` ADD COLUMN `notice` varchar(1000) NOT NULL DEFAULT '' AFTER `avatar`");
        $this->im_group_add_column('mr_im_groups', 'owner_id', "ALTER TABLE `mr_im_groups` ADD COLUMN `owner_id` int(11) NOT NULL DEFAULT 0 AFTER `notice`");
        $this->im_group_add_column('mr_im_groups', 'mute_all', "ALTER TABLE `mr_im_groups` ADD COLUMN `mute_all` tinyint(1) NOT NULL DEFAULT 0 AFTER `member_count`");
        $this->im_group_add_column('mr_im_groups', 'update_time', "ALTER TABLE `mr_im_groups` ADD COLUMN `update_time` datetime DEFAULT NULL");
        $this->im_group_add_column('mr_im_group_members', 'role', "ALTER TABLE `mr_im_group_members` ADD COLUMN `role` tinyint(1) NOT NULL DEFAULT 0 AFTER `user_id`");
        $this->im_group_add_column('mr_im_group_members', 'nickname', "ALTER TABLE `mr_im_group_members` ADD COLUMN `nickname` varchar(100) NOT NULL DEFAULT '' AFTER `role`");
        $this->im_group_add_column('mr_im_group_members', 'mute_until', "ALTER TABLE `mr_im_group_members` ADD COLUMN `mute_until` datetime DEFAULT NULL AFTER `nickname`");
        $this->im_group_add_column('mr_im_group_members', 'update_time', "ALTER TABLE `mr_im_group_members` ADD COLUMN `update_time` datetime DEFAULT NULL");
        $this->im_group_add_column('mr_im_group_messages', 'payload', "ALTER TABLE `mr_im_group_messages` ADD COLUMN `payload` mediumtext NULL AFTER `content`");
        $this->im_group_add_column('mr_im_group_messages', 'client_msg_no', "ALTER TABLE `mr_im_group_messages` ADD COLUMN `client_msg_no` varchar(128) NOT NULL DEFAULT '' AFTER `payload`");
    }

    private function im_group_add_column($table, $column, $sql)
    {
        try {
            $exists = Db::query("SHOW COLUMNS FROM `".$table."` LIKE '".$column."'");
            if (!$exists) { Db::execute($sql); }
        } catch (\Exception $e) {}
    }

    private function im_group_user()
    {
        $user_all_info = $this->user_info;
        if (!$user_all_info || !isset($user_all_info['id'])) { $this->json(0, '用户信息异常'); }
        return $user_all_info;
    }

    private function im_group_role_name($role)
    {
        $r = intval($role);
        if ($r >= 2) return 'owner';
        if ($r == 1) return 'admin';
        return 'member';
    }

    private function im_group_member($groupId, $userId)
    {
        return Db::name('im_group_members')->where('appid', $this->appid)->where('group_id', intval($groupId))->where('user_id', intval($userId))->where('status', 1)->find();
    }

    private function im_group_can_manage($groupId, $userId)
    {
        $m = $this->im_group_member($groupId, $userId);
        return $m && intval($m['role']) >= 1;
    }

    private function im_group_is_owner($groupId, $userId)
    {
        $m = $this->im_group_member($groupId, $userId);
        return $m && intval($m['role']) >= 2;
    }

    public function get_im_group_info()
    {
        $data = input();
        $rule = ['usertoken|用户token' => 'require', 'group_id|群ID' => 'require|number'];
        $validate = new Validate($rule);
        if (!$validate->check($data)) { $this->json(0, $validate->getError()); }
        $user = $this->im_group_user();
        $this->ensure_im_group_admin_tables();
        $groupId = intval($data['group_id']);
        $member = $this->im_group_member($groupId, intval($user['id']));
        if (!$member) { $this->json(0, '你不在该群聊中'); }
        $group = Db::name('im_groups')->where('appid', $this->appid)->where('id', $groupId)->where('status', 1)->find();
        if (!$group) { $this->json(0, '群聊不存在'); }
        $group['group_id'] = intval($group['id']);
        $group['my_role'] = $this->im_group_role_name($member['role']);
        $this->json(1, 'success', $group);
    }

    public function get_im_group_members()
    {
        $data = input();
        $rule = ['usertoken|用户token' => 'require', 'group_id|群ID' => 'require|number'];
        $validate = new Validate($rule);
        if (!$validate->check($data)) { $this->json(0, $validate->getError()); }
        $user = $this->im_group_user();
        $this->ensure_im_group_admin_tables();
        $groupId = intval($data['group_id']);
        if (!$this->im_group_member($groupId, intval($user['id']))) { $this->json(0, '你不在该群聊中'); }
        $rows = Db::name('im_group_members')->alias('m')->join('user u', 'u.id=m.user_id', 'LEFT')->where('m.appid', $this->appid)->where('m.group_id', $groupId)->where('m.status', 1)->field('m.user_id,m.role,m.nickname,u.username,u.nickname as user_nickname,u.usertx')->order('m.role desc,m.id asc')->select();
        $list = [];
        foreach (($rows ?: []) as $r) {
            $uid = intval($r['user_id']);
            $nick = isset($r['nickname']) && $r['nickname'] !== '' ? $r['nickname'] : (isset($r['user_nickname']) && $r['user_nickname'] !== '' ? $r['user_nickname'] : (isset($r['username']) ? $r['username'] : ('用户'.$uid)));
            $list[] = ['user_id'=>$uid, 'nickname'=>$nick, 'avatar'=>isset($r['usertx']) ? $r['usertx'] : '', 'role'=>$this->im_group_role_name($r['role'])];
        }
        $this->json(1, 'success', $list);
    }

    public function update_im_group()
    {
        $data = input();
        $rule = ['usertoken|用户token' => 'require', 'group_id|群ID' => 'require|number'];
        $validate = new Validate($rule);
        if (!$validate->check($data)) { $this->json(0, $validate->getError()); }
        $user = $this->im_group_user();
        $this->ensure_im_group_admin_tables();
        $groupId = intval($data['group_id']);
        if (!$this->im_group_can_manage($groupId, intval($user['id']))) { $this->json(0, '没有群管理权限'); }
        $update = ['update_time'=>date('Y-m-d H:i:s')];
        if (isset($data['name']) || isset($data['group_name'])) { $update['name'] = trim(strval(isset($data['name']) ? $data['name'] : $data['group_name'])); }
        if (isset($data['avatar']) || isset($data['group_avatar'])) { $update['avatar'] = trim(strval(isset($data['avatar']) ? $data['avatar'] : $data['group_avatar'])); }
        if (count($update) <= 1) { $this->json(0, '没有可更新内容'); }
        Db::name('im_groups')->where('appid', $this->appid)->where('id', $groupId)->update($update);
        $group = Db::name('im_groups')->where('appid', $this->appid)->where('id', $groupId)->find();
        $this->json(1, '更新成功', $group ?: []);
    }

    public function add_im_group_members()
    {
        $data = input();
        $rule = ['usertoken|用户token' => 'require', 'group_id|群ID' => 'require|number'];
        $validate = new Validate($rule);
        if (!$validate->check($data)) { $this->json(0, $validate->getError()); }
        $user = $this->im_group_user();
        $this->ensure_im_group_admin_tables();
        $groupId = intval($data['group_id']);
        if (!$this->im_group_can_manage($groupId, intval($user['id']))) { $this->json(0, '没有群管理权限'); }
        $raw = isset($data['user_ids']) ? $data['user_ids'] : (isset($data['member_ids']) ? $data['member_ids'] : '');
        $ids = [];
        foreach (explode(',', strval($raw)) as $id) { $v = intval(trim($id)); if ($v > 0) $ids[$v] = $v; }
        if (!$ids) { $this->json(0, '请选择成员'); }
        $now = date('Y-m-d H:i:s');
        $added = 0;
        foreach ($ids as $uid) {
            $exists = Db::name('im_group_members')->where('group_id', $groupId)->where('user_id', $uid)->find();
            if ($exists) { Db::name('im_group_members')->where('id', $exists['id'])->update(['status'=>1, 'update_time'=>$now]); }
            else { Db::name('im_group_members')->insert(['appid'=>$this->appid, 'group_id'=>$groupId, 'user_id'=>$uid, 'role'=>0, 'status'=>1, 'create_time'=>$now, 'update_time'=>$now]); }
            $added++;
        }
        $count = Db::name('im_group_members')->where('group_id', $groupId)->where('status', 1)->count();
        Db::name('im_groups')->where('id', $groupId)->update(['member_count'=>$count, 'update_time'=>$now]);
        $this->json(1, '添加成功', ['added'=>$added, 'member_count'=>$count]);
    }

    public function remove_im_group_member()
    {
        $data = input();
        $rule = ['usertoken|用户token' => 'require', 'group_id|群ID' => 'require|number'];
        $validate = new Validate($rule);
        if (!$validate->check($data)) { $this->json(0, $validate->getError()); }
        $user = $this->im_group_user();
        $this->ensure_im_group_admin_tables();
        $groupId = intval($data['group_id']);
        $uid = intval(isset($data['user_id']) ? $data['user_id'] : (isset($data['member_id']) ? $data['member_id'] : 0));
        if ($uid <= 0) { $this->json(0, '成员ID错误'); }
        if (!$this->im_group_can_manage($groupId, intval($user['id']))) { $this->json(0, '没有群管理权限'); }
        $target = $this->im_group_member($groupId, $uid);
        if (!$target) { $this->json(0, '成员不存在'); }
        if (intval($target['role']) >= 2) { $this->json(0, '不能移除群主'); }
        Db::name('im_group_members')->where('group_id', $groupId)->where('user_id', $uid)->update(['status'=>0, 'update_time'=>date('Y-m-d H:i:s')]);
        $count = Db::name('im_group_members')->where('group_id', $groupId)->where('status', 1)->count();
        Db::name('im_groups')->where('id', $groupId)->update(['member_count'=>$count, 'update_time'=>date('Y-m-d H:i:s')]);
        $this->json(1, '移除成功', ['member_count'=>$count]);
    }

    public function set_im_group_admin()
    {
        $data = input();
        $rule = ['usertoken|用户token' => 'require', 'group_id|群ID' => 'require|number'];
        $validate = new Validate($rule);
        if (!$validate->check($data)) { $this->json(0, $validate->getError()); }
        $user = $this->im_group_user();
        $this->ensure_im_group_admin_tables();
        $groupId = intval($data['group_id']);
        if (!$this->im_group_is_owner($groupId, intval($user['id']))) { $this->json(0, '只有群主可以设置管理员'); }
        $uid = intval(isset($data['user_id']) ? $data['user_id'] : (isset($data['member_id']) ? $data['member_id'] : 0));
        $admin = (isset($data['admin']) && intval($data['admin']) == 1) || (isset($data['role']) && strval($data['role']) == 'admin');
        $target = $this->im_group_member($groupId, $uid);
        if (!$target || intval($target['role']) >= 2) { $this->json(0, '成员不存在或不能修改群主'); }
        Db::name('im_group_members')->where('group_id', $groupId)->where('user_id', $uid)->update(['role'=>$admin ? 1 : 0, 'update_time'=>date('Y-m-d H:i:s')]);
        $this->json(1, $admin ? '已设为管理员' : '已取消管理员');
    }

    public function transfer_im_group()
    {
        $data = input();
        $rule = ['usertoken|用户token' => 'require', 'group_id|群ID' => 'require|number'];
        $validate = new Validate($rule);
        if (!$validate->check($data)) { $this->json(0, $validate->getError()); }
        $user = $this->im_group_user();
        $this->ensure_im_group_admin_tables();
        $groupId = intval($data['group_id']);
        if (!$this->im_group_is_owner($groupId, intval($user['id']))) { $this->json(0, '只有群主可以转让'); }
        $uid = intval(isset($data['new_owner_id']) ? $data['new_owner_id'] : (isset($data['user_id']) ? $data['user_id'] : 0));
        if (!$this->im_group_member($groupId, $uid)) { $this->json(0, '新群主不在群内'); }
        Db::name('im_group_members')->where('group_id', $groupId)->where('user_id', intval($user['id']))->update(['role'=>1, 'update_time'=>date('Y-m-d H:i:s')]);
        Db::name('im_group_members')->where('group_id', $groupId)->where('user_id', $uid)->update(['role'=>2, 'update_time'=>date('Y-m-d H:i:s')]);
        Db::name('im_groups')->where('id', $groupId)->update(['owner_id'=>$uid, 'update_time'=>date('Y-m-d H:i:s')]);
        $this->json(1, '转让成功');
    }

    public function leave_im_group()
    {
        $data = input();
        $rule = ['usertoken|用户token' => 'require', 'group_id|群ID' => 'require|number'];
        $validate = new Validate($rule);
        if (!$validate->check($data)) { $this->json(0, $validate->getError()); }
        $user = $this->im_group_user();
        $this->ensure_im_group_admin_tables();
        $groupId = intval($data['group_id']);
        if ($this->im_group_is_owner($groupId, intval($user['id']))) { $this->json(0, '群主请先转让或解散群'); }
        Db::name('im_group_members')->where('group_id', $groupId)->where('user_id', intval($user['id']))->update(['status'=>0, 'update_time'=>date('Y-m-d H:i:s')]);
        $count = Db::name('im_group_members')->where('group_id', $groupId)->where('status', 1)->count();
        Db::name('im_groups')->where('id', $groupId)->update(['member_count'=>$count, 'update_time'=>date('Y-m-d H:i:s')]);
        $this->json(1, '已退出群聊');
    }

    public function dismiss_im_group()
    {
        $data = input();
        $rule = ['usertoken|用户token' => 'require', 'group_id|群ID' => 'require|number'];
        $validate = new Validate($rule);
        if (!$validate->check($data)) { $this->json(0, $validate->getError()); }
        $user = $this->im_group_user();
        $this->ensure_im_group_admin_tables();
        $groupId = intval($data['group_id']);
        if (!$this->im_group_is_owner($groupId, intval($user['id']))) { $this->json(0, '只有群主可以解散群'); }
        Db::name('im_groups')->where('id', $groupId)->update(['status'=>0, 'update_time'=>date('Y-m-d H:i:s')]);
        Db::name('im_group_members')->where('group_id', $groupId)->update(['status'=>0, 'update_time'=>date('Y-m-d H:i:s')]);
        $this->json(1, '已解散群聊');
    }

'''

p.write_text(s.replace(marker, '\n' + code + marker, 1))
print('PATCH_OK', backup)
