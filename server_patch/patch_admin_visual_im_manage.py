from pathlib import Path


ROOT = Path("/www/wwwroot/blinlin")
CONTROLLER = ROOT / "application/admin/controller/Im.php"
VIEW_DIR = ROOT / "application/admin/view/im"


PHP_SNIPPET = r'''

    // blin-visual-im-admin-start
    public function group_manage()
    {
        if (Request::isAjax() || input('callback') != '' || Request::isPost()) {
            $op = trim(strval(input('op')));
            if (Request::isPost() && $op !== '') {
                if ($op === 'create') return $this->blinAdminImGroupCreate();
                if ($op === 'update') return $this->blinAdminImGroupUpdate();
                if ($op === 'dismiss') return $this->blinAdminImGroupDismiss();
                if ($op === 'member_add') return $this->blinAdminImGroupMemberAdd();
                if ($op === 'member_remove') return $this->blinAdminImGroupMemberRemove();
                if ($op === 'member_role') return $this->blinAdminImGroupMemberRole();
                if ($op === 'clear_messages') return $this->blinAdminImGroupClearMessages();
                if ($op === 'hide_message') return $this->blinAdminImGroupHideMessage();
                if ($op === 'delete_message') return $this->blinAdminImGroupDeleteMessage();
            }
            if ($op === 'members') return $this->blinAdminImGroupMembers();
            if ($op === 'messages') return $this->blinAdminImGroupMessages();
            return $this->blinAdminImGroupList();
        }
        $this->assign('apps', $this->blinScopedAppList());
        $this->assign('is_super_admin', $this->blinIsSuperAdmin() ? 1 : 0);
        return $this->fetch();
    }

    public function private_chat_manage()
    {
        if (Request::isAjax() || input('callback') != '' || Request::isPost()) {
            $op = trim(strval(input('op')));
            if (Request::isPost() && $op !== '') {
                if ($op === 'hide_message') return $this->blinAdminImPrivateHideMessage();
                if ($op === 'delete_message') return $this->blinAdminImPrivateDeleteMessage();
                if ($op === 'clear_pair') return $this->blinAdminImPrivateClearPair();
                if ($op === 'mark_read') return $this->blinAdminImPrivateMarkRead();
            }
            if ($op === 'messages') return $this->blinAdminImPrivateMessages();
            return $this->blinAdminImPrivateConversations();
        }
        $this->assign('apps', $this->blinScopedAppList());
        $this->assign('is_super_admin', $this->blinIsSuperAdmin() ? 1 : 0);
        return $this->fetch();
    }

    private function blinAdminImPage()
    {
        return max(1, intval(input('page') ?: 1));
    }

    private function blinAdminImLimit($default = 10, $max = 100)
    {
        $limit = intval(input('limit') ?: $default);
        if ($limit <= 0) $limit = $default;
        if ($limit > $max) $limit = $max;
        return $limit;
    }

    private function blinAdminImText($value, $max = 80)
    {
        $text = trim(strval($value));
        if ($text === '') return '';
        return mb_substr($text, 0, $max, 'UTF-8');
    }

    private function blinAdminImLike($text)
    {
        return str_replace(['\\', "'", '%', '_'], ['\\\\', "\\'", '\\%', '\\_'], strval($text));
    }

    private function blinAdminImAppIds($appid = 0)
    {
        $appid = intval($appid);
        if ($appid > 0) {
            $this->blinRequireApp($appid);
            return [$appid];
        }
        if ($this->blinIsSuperAdmin()) return [];
        $ids = $this->blinAdminAppIds();
        return $ids ?: [-1];
    }

    private function blinAdminImApplyAppScope($query, $field = 'appid')
    {
        $appid = intval(input('appid'));
        if ($appid > 0) {
            $this->blinRequireApp($appid);
            return $query->where($field, $appid);
        }
        return $this->blinScopeQuery($query, $field);
    }

    private function blinAdminImAppSql($alias = 'm', $appid = 0)
    {
        $ids = $this->blinAdminImAppIds($appid);
        if (!$ids) return '';
        $field = ($alias !== '' ? $alias . '.' : '') . 'appid';
        return ' AND ' . $field . ' IN (' . implode(',', array_map('intval', $ids)) . ')';
    }

    private function blinAdminImParseIds($raw)
    {
        if (is_array($raw)) $items = $raw;
        else $items = preg_split('/[,，\s]+/', trim(strval($raw)));
        $ids = [];
        foreach (($items ?: []) as $item) {
            $id = intval($item);
            if ($id > 0) $ids[] = $id;
        }
        return array_values(array_unique($ids));
    }

    private function blinAdminImUser($appid, $userId)
    {
        $userId = intval($userId);
        if ($userId <= 0) return null;
        return Db::name('user')->where('appid', intval($appid))->where('id', $userId)->find();
    }

    private function blinAdminImUserName($user)
    {
        if (!$user) return '';
        $nickname = isset($user['nickname']) ? trim(strval($user['nickname'])) : '';
        if ($nickname !== '') return $nickname;
        $username = isset($user['username']) ? trim(strval($user['username'])) : '';
        if ($username !== '') return $username;
        return '用户' . intval(isset($user['id']) ? $user['id'] : 0);
    }

    private function blinAdminImEnsureGroupMember($appid, $groupId, $userId, $role = 0)
    {
        $appid = intval($appid);
        $groupId = intval($groupId);
        $userId = intval($userId);
        if ($appid <= 0 || $groupId <= 0 || $userId <= 0) return false;
        $user = $this->blinAdminImUser($appid, $userId);
        if (!$user) return false;
        $now = date('Y-m-d H:i:s');
        $row = Db::name('im_group_members')->where('appid', $appid)->where('group_id', $groupId)->where('user_id', $userId)->find();
        $data = [
            'appid'=>$appid,
            'group_id'=>$groupId,
            'user_id'=>$userId,
            'role'=>intval($role),
            'nickname'=>$this->blinAdminImUserName($user),
            'status'=>1,
            'update_time'=>$now,
        ];
        if ($row) {
            Db::name('im_group_members')->where('id', intval($row['id']))->update($data);
        } else {
            $data['create_time'] = $now;
            Db::name('im_group_members')->insert($data);
        }
        return true;
    }

    private function blinAdminImRefreshGroupCount($appid, $groupId)
    {
        $count = intval(Db::name('im_group_members')->where('appid', intval($appid))->where('group_id', intval($groupId))->where('status', 1)->count());
        Db::name('im_groups')->where('appid', intval($appid))->where('id', intval($groupId))->update(['member_count'=>$count, 'update_time'=>date('Y-m-d H:i:s')]);
        return $count;
    }

    private function blinAdminImSyncGroupChannel($group, $mode = 'sync', $userIds = [])
    {
        if (!$group || !config('wukongim.enable')) return;
        $groupNo = trim(strval(isset($group['group_no']) ? $group['group_no'] : ''));
        if ($groupNo === '') return;
        try {
            $wkim = new \app\common\tool\WukongIM();
            if ($mode === 'delete') {
                try { $wkim->deleteChannel($groupNo, 2); } catch (\Exception $e) {}
                return;
            }
            $subs = [];
            if ($userIds) {
                foreach ($userIds as $uid) {
                    $uid = intval($uid);
                    if ($uid > 0) $subs[] = intval($group['appid']) . '_' . $uid;
                }
            } else {
                $ids = Db::name('im_group_members')->where('appid', intval($group['appid']))->where('group_id', intval($group['id']))->where('status', 1)->column('user_id');
                foreach (($ids ?: []) as $uid) $subs[] = intval($group['appid']) . '_' . intval($uid);
            }
            $subs = array_values(array_unique($subs));
            try { $wkim->createChannel($groupNo, 2, $subs, ['name'=>isset($group['name']) ? strval($group['name']) : '']); } catch (\Exception $e) {}
            if ($subs) {
                if ($mode === 'remove') $wkim->removeChannelSubscribers($groupNo, 2, $subs);
                else $wkim->addChannelSubscribers($groupNo, 2, $subs);
            }
        } catch (\Exception $e) {}
    }

    private function blinAdminImGroupById($id)
    {
        $group = Db::name('im_groups')->where('id', intval($id))->find();
        if (!$group) return null;
        $this->blinRequireApp($group['appid']);
        return $group;
    }

    private function blinAdminImGroupList()
    {
        $limit = $this->blinAdminImLimit(10, 100);
        $page = $this->blinAdminImPage();
        $query = Db::name('im_groups')->alias('g')
            ->leftJoin('app a', 'a.appid=g.appid')
            ->leftJoin('user u', 'u.id=g.owner_id AND u.appid=g.appid');
        $countQuery = Db::name('im_groups')->alias('g');
        $this->blinAdminImApplyAppScope($query, 'g.appid');
        $this->blinAdminImApplyAppScope($countQuery, 'g.appid');
        $status = trim(strval(input('status', '')));
        if ($status !== '') {
            $query->where('g.status', intval($status));
            $countQuery->where('g.status', intval($status));
        }
        $keyword = trim(strval(input('keyword')));
        if ($keyword !== '') {
            $query->where(function($q) use ($keyword) {
                $q->where('g.name', 'like', '%' . $keyword . '%')
                  ->whereOr('g.group_no', 'like', '%' . $keyword . '%')
                  ->whereOr('g.id', 'like', '%' . $keyword . '%')
                  ->whereOr('u.username', 'like', '%' . $keyword . '%')
                  ->whereOr('u.nickname', 'like', '%' . $keyword . '%');
            });
            $countQuery->where(function($q) use ($keyword) {
                $q->where('g.name', 'like', '%' . $keyword . '%')
                  ->whereOr('g.group_no', 'like', '%' . $keyword . '%')
                  ->whereOr('g.id', 'like', '%' . $keyword . '%');
            });
        }
        $total = $countQuery->count();
        $rows = $query->field('g.*,a.appname,u.username owner_username,u.nickname owner_nickname,u.usertx owner_avatar')
            ->order('g.update_time desc,g.id desc')->page($page, $limit)->select();
        foreach (($rows ?: []) as $k=>$v) {
            $rows[$k]['owner_name'] = trim(strval($v['owner_nickname'])) !== '' ? $v['owner_nickname'] : $v['owner_username'];
            $rows[$k]['status_text'] = intval($v['status']) === 1 ? '正常' : '已解散';
            $rows[$k]['mute_text'] = intval($v['mute_all']) === 1 ? '全员禁言' : '正常发言';
            $rows[$k]['message_count'] = intval(Db::name('im_group_messages')->where('appid', intval($v['appid']))->where('group_id', intval($v['id']))->count());
            $rows[$k]['active_member_count'] = intval(Db::name('im_group_members')->where('appid', intval($v['appid']))->where('group_id', intval($v['id']))->where('status', 1)->count());
            $rows[$k]['notice_short'] = $this->blinAdminImText(isset($v['notice']) ? $v['notice'] : '', 60);
        }
        return $this->jsonp(['rows'=>$rows, 'total'=>$total]);
    }

    private function blinAdminImGroupCreate()
    {
        $appid = intval(input('appid'));
        if ($appid <= 0) return $this->imFail('请选择应用');
        $this->blinRequireApp($appid);
        $name = $this->blinAdminImText(input('name'), 100);
        if ($name === '') return $this->imFail('请输入群名称');
        $ownerId = intval(input('owner_id'));
        $owner = $this->blinAdminImUser($appid, $ownerId);
        if (!$owner) return $this->imFail('群主不存在');
        $groupNo = trim(strval(input('group_no')));
        if ($groupNo === '') $groupNo = 'group_' . $appid . '_' . time() . '_' . mt_rand(1000, 9999);
        if (Db::name('im_groups')->where('group_no', $groupNo)->find()) return $this->imFail('群号已存在');
        $now = date('Y-m-d H:i:s');
        $avatar = trim(strval(input('avatar')));
        if ($avatar === '') $avatar = isset($owner['usertx']) ? strval($owner['usertx']) : '';
        $groupId = Db::name('im_groups')->insertGetId([
            'appid'=>$appid,
            'group_no'=>$groupNo,
            'name'=>$name,
            'avatar'=>$avatar,
            'notice'=>trim(strval(input('notice'))),
            'owner_id'=>$ownerId,
            'member_count'=>0,
            'mute_all'=>intval(input('mute_all')) ? 1 : 0,
            'status'=>1,
            'default_group'=>intval(input('default_group')) ? 1 : 0,
            'qr_enabled'=>input('qr_enabled') === '' ? 1 : intval(input('qr_enabled')),
            'admin_notice_enabled'=>input('admin_notice_enabled') === '' ? 1 : intval(input('admin_notice_enabled')),
            'notice_pinned'=>input('notice_pinned') === '' ? 1 : intval(input('notice_pinned')),
            'notice_enabled'=>input('notice_enabled') === '' ? 1 : intval(input('notice_enabled')),
            'create_time'=>$now,
            'update_time'=>$now,
        ]);
        $memberIds = $this->blinAdminImParseIds(input('member_ids'));
        $memberIds[] = $ownerId;
        $memberIds = array_values(array_unique($memberIds));
        foreach ($memberIds as $uid) {
            $this->blinAdminImEnsureGroupMember($appid, $groupId, $uid, $uid == $ownerId ? 2 : 0);
        }
        $this->blinAdminImRefreshGroupCount($appid, $groupId);
        $group = Db::name('im_groups')->where('id', $groupId)->find();
        $this->blinAdminImSyncGroupChannel($group);
        return $this->imOk('群聊已创建', '', ['group_id'=>$groupId]);
    }

    private function blinAdminImGroupUpdate()
    {
        $group = $this->blinAdminImGroupById(input('id'));
        if (!$group) return $this->imFail('群聊不存在');
        if (intval($group['status']) !== 1) return $this->imFail('群聊已解散，不能修改');
        $update = ['update_time'=>date('Y-m-d H:i:s')];
        foreach (['name','avatar','notice','notice_rich_text'] as $field) {
            if (input($field) !== null) $update[$field] = strval(input($field));
        }
        foreach (['mute_all','qr_enabled','admin_notice_enabled','notice_pinned','notice_enabled','default_group','screenshot_notify_enabled'] as $field) {
            if (input($field) !== null && input($field) !== '') $update[$field] = intval(input($field)) ? 1 : 0;
        }
        $ownerId = intval(input('owner_id'));
        if ($ownerId > 0 && $ownerId != intval($group['owner_id'])) {
            $owner = $this->blinAdminImUser($group['appid'], $ownerId);
            if (!$owner) return $this->imFail('新群主不存在');
            $update['owner_id'] = $ownerId;
            $this->blinAdminImEnsureGroupMember($group['appid'], $group['id'], $ownerId, 2);
            Db::name('im_group_members')->where('appid', intval($group['appid']))->where('group_id', intval($group['id']))->where('user_id', '<>', $ownerId)->where('role', 2)->update(['role'=>1, 'update_time'=>date('Y-m-d H:i:s')]);
        }
        $newGroupNo = trim(strval(input('group_no')));
        if ($newGroupNo !== '' && $newGroupNo !== strval($group['group_no'])) {
            $exists = Db::name('im_groups')->where('group_no', $newGroupNo)->where('id', '<>', intval($group['id']))->find();
            if ($exists) return $this->imFail('群号已存在');
            $oldGroupNo = strval($group['group_no']);
            $update['group_no'] = $newGroupNo;
        }
        Db::name('im_groups')->where('id', intval($group['id']))->update($update);
        $next = Db::name('im_groups')->where('id', intval($group['id']))->find();
        if (isset($oldGroupNo) && $oldGroupNo !== '') {
            try { if (config('wukongim.enable')) (new \app\common\tool\WukongIM())->deleteChannel($oldGroupNo, 2); } catch (\Exception $e) {}
        }
        $this->blinAdminImRefreshGroupCount($next['appid'], $next['id']);
        $this->blinAdminImSyncGroupChannel($next);
        return $this->imOk('群资料已更新');
    }

    private function blinAdminImGroupDismiss()
    {
        $group = $this->blinAdminImGroupById(input('id'));
        if (!$group) return $this->imFail('群聊不存在');
        if (intval($group['status']) !== 1) return $this->imOk('群聊已解散');
        Db::name('im_groups')->where('id', intval($group['id']))->update(['status'=>0, 'update_time'=>date('Y-m-d H:i:s')]);
        Db::name('im_group_members')->where('appid', intval($group['appid']))->where('group_id', intval($group['id']))->update(['status'=>0, 'update_time'=>date('Y-m-d H:i:s')]);
        $this->blinAdminImSyncGroupChannel($group, 'delete');
        return $this->imOk('群聊已解散');
    }

    private function blinAdminImGroupMembers()
    {
        $group = $this->blinAdminImGroupById(input('group_id'));
        if (!$group) return $this->jsonp(['rows'=>[], 'total'=>0]);
        $limit = $this->blinAdminImLimit(10, 100);
        $page = $this->blinAdminImPage();
        $query = Db::name('im_group_members')->alias('m')->leftJoin('user u', 'u.id=m.user_id AND u.appid=m.appid')
            ->where('m.appid', intval($group['appid']))->where('m.group_id', intval($group['id']));
        $countQuery = Db::name('im_group_members')->where('appid', intval($group['appid']))->where('group_id', intval($group['id']));
        $status = trim(strval(input('member_status', '1')));
        if ($status !== '') {
            $query->where('m.status', intval($status));
            $countQuery->where('status', intval($status));
        }
        $keyword = trim(strval(input('keyword')));
        if ($keyword !== '') {
            $query->where(function($q) use ($keyword) {
                $q->where('u.username', 'like', '%' . $keyword . '%')->whereOr('u.nickname', 'like', '%' . $keyword . '%')->whereOr('m.user_id', 'like', '%' . $keyword . '%');
            });
        }
        $rows = $query->field('m.*,u.username,u.nickname,u.usertx')->order('m.role desc,m.id asc')->page($page, $limit)->select();
        foreach (($rows ?: []) as $k=>$v) {
            $rows[$k]['display_name'] = trim(strval($v['nickname'])) !== '' ? $v['nickname'] : $v['username'];
            $rows[$k]['role_text'] = intval($v['role']) === 2 ? '群主' : (intval($v['role']) === 1 ? '管理员' : '成员');
            $rows[$k]['status_text'] = intval($v['status']) === 1 ? '正常' : '已移出';
        }
        return $this->jsonp(['rows'=>$rows, 'total'=>$countQuery->count()]);
    }

    private function blinAdminImGroupMemberAdd()
    {
        $group = $this->blinAdminImGroupById(input('group_id'));
        if (!$group) return $this->imFail('群聊不存在');
        if (intval($group['status']) !== 1) return $this->imFail('群聊已解散');
        $ids = $this->blinAdminImParseIds(input('user_ids'));
        if (!$ids) return $this->imFail('请输入用户ID');
        $added = [];
        foreach ($ids as $uid) {
            if ($this->blinAdminImEnsureGroupMember($group['appid'], $group['id'], $uid, 0)) $added[] = $uid;
        }
        $this->blinAdminImRefreshGroupCount($group['appid'], $group['id']);
        $this->blinAdminImSyncGroupChannel($group, 'add', $added);
        return $this->imOk('成员已添加', '', ['added'=>$added]);
    }

    private function blinAdminImGroupMemberRemove()
    {
        $group = $this->blinAdminImGroupById(input('group_id'));
        if (!$group) return $this->imFail('群聊不存在');
        $ids = $this->blinAdminImParseIds(input('user_ids'));
        if (!$ids) return $this->imFail('请输入用户ID');
        Db::name('im_group_members')->where('appid', intval($group['appid']))->where('group_id', intval($group['id']))->whereIn('user_id', $ids)->update(['status'=>0, 'update_time'=>date('Y-m-d H:i:s')]);
        $this->blinAdminImRefreshGroupCount($group['appid'], $group['id']);
        $this->blinAdminImSyncGroupChannel($group, 'remove', $ids);
        return $this->imOk('成员已移出');
    }

    private function blinAdminImGroupMemberRole()
    {
        $group = $this->blinAdminImGroupById(input('group_id'));
        if (!$group) return $this->imFail('群聊不存在');
        $userId = intval(input('user_id'));
        $role = intval(input('role'));
        if (!in_array($role, [0,1,2], true)) return $this->imFail('角色不合法');
        if ($role === 2) {
            Db::name('im_groups')->where('id', intval($group['id']))->update(['owner_id'=>$userId, 'update_time'=>date('Y-m-d H:i:s')]);
            Db::name('im_group_members')->where('appid', intval($group['appid']))->where('group_id', intval($group['id']))->where('role', 2)->update(['role'=>1, 'update_time'=>date('Y-m-d H:i:s')]);
        }
        $this->blinAdminImEnsureGroupMember($group['appid'], $group['id'], $userId, $role);
        return $this->imOk('成员角色已更新');
    }

    private function blinAdminImGroupMessages()
    {
        $group = $this->blinAdminImGroupById(input('group_id'));
        if (!$group) return $this->jsonp(['rows'=>[], 'total'=>0]);
        $limit = $this->blinAdminImLimit(10, 100);
        $page = $this->blinAdminImPage();
        $query = Db::name('im_group_messages')->alias('m')->leftJoin('user u', 'u.id=m.sender_id AND u.appid=m.appid')
            ->where('m.appid', intval($group['appid']))->where('m.group_id', intval($group['id']));
        $countQuery = Db::name('im_group_messages')->where('appid', intval($group['appid']))->where('group_id', intval($group['id']));
        $keyword = trim(strval(input('keyword')));
        if ($keyword !== '') {
            $query->where(function($q) use ($keyword) {
                $q->where('m.content', 'like', '%' . $keyword . '%')->whereOr('m.client_msg_no', 'like', '%' . $keyword . '%')->whereOr('u.username', 'like', '%' . $keyword . '%')->whereOr('u.nickname', 'like', '%' . $keyword . '%');
            });
            $countQuery->where('content', 'like', '%' . $keyword . '%');
        }
        $rows = $query->field('m.*,u.username,u.nickname,u.usertx')->order('m.id desc')->page($page, $limit)->select();
        foreach (($rows ?: []) as $k=>$v) {
            $rows[$k]['sender_name'] = trim(strval($v['nickname'])) !== '' ? $v['nickname'] : $v['username'];
            $rows[$k]['content_short'] = $this->blinAdminImText($v['content'], 90);
            $rows[$k]['status_text'] = intval(isset($v['is_recalled']) ? $v['is_recalled'] : 0) === 1 ? '已隐藏' : '正常';
        }
        return $this->jsonp(['rows'=>$rows, 'total'=>$countQuery->count()]);
    }

    private function blinAdminImGroupHideMessage()
    {
        $id = intval(input('id'));
        $row = Db::name('im_group_messages')->where('id', $id)->find();
        if (!$row) return $this->imFail('消息不存在');
        $this->blinRequireApp($row['appid']);
        Db::name('im_group_messages')->where('id', $id)->update(['is_recalled'=>1, 'recall_time'=>date('Y-m-d H:i:s'), 'recall_user_id'=>0, 'content'=>'[后台已隐藏]']);
        return $this->imOk('消息已隐藏');
    }

    private function blinAdminImGroupDeleteMessage()
    {
        $id = intval(input('id'));
        $row = Db::name('im_group_messages')->where('id', $id)->find();
        if (!$row) return $this->imFail('消息不存在');
        $this->blinRequireApp($row['appid']);
        Db::name('im_group_messages')->where('id', $id)->delete();
        Db::name('im_message_log')->where('appid', intval($row['appid']))->where(function($q) use ($id) {
            $q->where('message_id', 'local_' . $id)->whereOr('message_id', strval($id));
        })->update(['status'=>3, 'update_time'=>date('Y-m-d H:i:s')]);
        return $this->imOk('消息已删除');
    }

    private function blinAdminImGroupClearMessages()
    {
        $group = $this->blinAdminImGroupById(input('group_id') ?: input('id'));
        if (!$group) return $this->imFail('群聊不存在');
        $count = intval(Db::name('im_group_messages')->where('appid', intval($group['appid']))->where('group_id', intval($group['id']))->count());
        Db::name('im_group_messages')->where('appid', intval($group['appid']))->where('group_id', intval($group['id']))->delete();
        Db::name('im_group_read_state')->where('appid', intval($group['appid']))->where('group_id', intval($group['id']))->delete();
        Db::name('im_group_clear_state')->where('appid', intval($group['appid']))->where('group_id', intval($group['id']))->delete();
        Db::name('im_groups')->where('id', intval($group['id']))->update(['update_time'=>date('Y-m-d H:i:s')]);
        return $this->imOk('群聊天记录已清空', '', ['deleted'=>$count]);
    }

    private function blinAdminImPrivateConversations()
    {
        $limit = $this->blinAdminImLimit(10, 100);
        $page = $this->blinAdminImPage();
        $offset = ($page - 1) * $limit;
        $appid = intval(input('appid'));
        $where = 'm.is_deleted=0' . $this->blinAdminImAppSql('m', $appid);
        $keyword = trim(strval(input('keyword')));
        if ($keyword !== '') {
            $kw = $this->blinAdminImLike($keyword);
            $where .= " AND (m.content LIKE '%{$kw}%' OR m.sender_id LIKE '%{$kw}%' OR m.receiver_id LIKE '%{$kw}%' OR EXISTS (SELECT 1 FROM mr_user u WHERE u.appid=m.appid AND (u.id=m.sender_id OR u.id=m.receiver_id) AND (u.username LIKE '%{$kw}%' OR u.nickname LIKE '%{$kw}%')))";
        }
        $base = "SELECT m.appid, LEAST(m.sender_id,m.receiver_id) AS user_a, GREATEST(m.sender_id,m.receiver_id) AS user_b, MAX(m.id) AS latest_id, COUNT(*) AS message_count, SUM(CASE WHEN m.is_read=0 THEN 1 ELSE 0 END) AS unread_count, MAX(m.create_time) AS latest_time FROM mr_messages m WHERE {$where} GROUP BY m.appid,user_a,user_b";
        $totalRow = Db::query("SELECT COUNT(*) AS count FROM ({$base}) t");
        $total = intval($totalRow ? $totalRow[0]['count'] : 0);
        $rows = Db::query($base . " ORDER BY latest_time DESC,latest_id DESC LIMIT {$offset},{$limit}");
        foreach (($rows ?: []) as $k=>$v) {
            $latest = Db::name('messages')->where('id', intval($v['latest_id']))->find();
            $u1 = $this->blinAdminImUser($v['appid'], $v['user_a']);
            $u2 = $this->blinAdminImUser($v['appid'], $v['user_b']);
            $app = Db::name('app')->where('appid', intval($v['appid']))->field('appname')->find();
            $rows[$k]['appname'] = $app ? $app['appname'] : '';
            $rows[$k]['user_a_name'] = $this->blinAdminImUserName($u1);
            $rows[$k]['user_b_name'] = $this->blinAdminImUserName($u2);
            $rows[$k]['user_a_avatar'] = $u1 && isset($u1['usertx']) ? $u1['usertx'] : '';
            $rows[$k]['user_b_avatar'] = $u2 && isset($u2['usertx']) ? $u2['usertx'] : '';
            $rows[$k]['latest_content'] = $latest ? $this->blinAdminImText($latest['content'], 80) : '';
            $rows[$k]['latest_type'] = $latest ? intval($latest['message_type']) : 0;
            $rows[$k]['latest_time'] = $latest ? $latest['create_time'] : $v['latest_time'];
        }
        return $this->jsonp(['rows'=>$rows, 'total'=>$total]);
    }

    private function blinAdminImPrivateMessages()
    {
        $appid = intval(input('appid'));
        if ($appid <= 0) return $this->jsonp(['rows'=>[], 'total'=>0]);
        $this->blinRequireApp($appid);
        $userA = intval(input('user_a'));
        $userB = intval(input('user_b'));
        if ($userA <= 0 || $userB <= 0) return $this->jsonp(['rows'=>[], 'total'=>0]);
        $limit = $this->blinAdminImLimit(10, 100);
        $page = $this->blinAdminImPage();
        $query = Db::name('messages')->alias('m')
            ->leftJoin('user su', 'su.id=m.sender_id AND su.appid=m.appid')
            ->leftJoin('user ru', 'ru.id=m.receiver_id AND ru.appid=m.appid')
            ->where('m.appid', $appid)
            ->where(function($q) use ($userA, $userB) {
                $q->whereOr(function($q2) use ($userA, $userB) {
                    $q2->where('m.sender_id', $userA)->where('m.receiver_id', $userB);
                })->whereOr(function($q3) use ($userA, $userB) {
                    $q3->where('m.sender_id', $userB)->where('m.receiver_id', $userA);
                });
            });
        $countQuery = Db::name('messages')->where('appid', $appid)->where(function($q) use ($userA, $userB) {
            $q->whereOr(function($q2) use ($userA, $userB) {
                $q2->where('sender_id', $userA)->where('receiver_id', $userB);
            })->whereOr(function($q3) use ($userA, $userB) {
                $q3->where('sender_id', $userB)->where('receiver_id', $userA);
            });
        });
        $includeDeleted = intval(input('include_deleted')) === 1;
        if (!$includeDeleted) {
            $query->where('m.is_deleted', 0);
            $countQuery->where('is_deleted', 0);
        }
        $keyword = trim(strval(input('keyword')));
        if ($keyword !== '') {
            $query->where('m.content', 'like', '%' . $keyword . '%');
            $countQuery->where('content', 'like', '%' . $keyword . '%');
        }
        $rows = $query->field('m.*,su.username sender_username,su.nickname sender_nickname,ru.username receiver_username,ru.nickname receiver_nickname')
            ->order('m.id desc')->page($page, $limit)->select();
        foreach (($rows ?: []) as $k=>$v) {
            $rows[$k]['sender_name'] = trim(strval($v['sender_nickname'])) !== '' ? $v['sender_nickname'] : $v['sender_username'];
            $rows[$k]['receiver_name'] = trim(strval($v['receiver_nickname'])) !== '' ? $v['receiver_nickname'] : $v['receiver_username'];
            $rows[$k]['content_short'] = $this->blinAdminImText($v['content'], 100);
            $rows[$k]['status_text'] = intval($v['is_deleted']) === 1 ? '已删除' : (intval(isset($v['is_recalled']) ? $v['is_recalled'] : 0) === 1 ? '已隐藏' : '正常');
            $rows[$k]['read_text'] = intval($v['is_read']) === 1 ? '已读' : '未读';
        }
        return $this->jsonp(['rows'=>$rows, 'total'=>$countQuery->count()]);
    }

    private function blinAdminImPrivateMessageRow($id)
    {
        $row = Db::name('messages')->where('id', intval($id))->find();
        if (!$row) return null;
        $this->blinRequireApp($row['appid']);
        return $row;
    }

    private function blinAdminImPrivateHideMessage()
    {
        $row = $this->blinAdminImPrivateMessageRow(input('id'));
        if (!$row) return $this->imFail('消息不存在');
        Db::name('messages')->where('id', intval($row['id']))->update(['is_recalled'=>1, 'recall_time'=>date('Y-m-d H:i:s'), 'recall_user_id'=>0, 'content'=>'[后台已隐藏]']);
        Db::name('im_message_log')->where('appid', intval($row['appid']))->where(function($q) use ($row) {
            $q->where('message_id', 'local_' . intval($row['id']))->whereOr('message_id', strval($row['id']));
        })->update(['status'=>1, 'update_time'=>date('Y-m-d H:i:s')]);
        return $this->imOk('消息已隐藏');
    }

    private function blinAdminImPrivateDeleteMessage()
    {
        $row = $this->blinAdminImPrivateMessageRow(input('id'));
        if (!$row) return $this->imFail('消息不存在');
        Db::name('messages')->where('id', intval($row['id']))->update(['is_deleted'=>1]);
        Db::name('im_message_log')->where('appid', intval($row['appid']))->where(function($q) use ($row) {
            $q->where('message_id', 'local_' . intval($row['id']))->whereOr('message_id', strval($row['id']));
        })->update(['status'=>3, 'update_time'=>date('Y-m-d H:i:s')]);
        return $this->imOk('消息已删除');
    }

    private function blinAdminImPrivateClearPair()
    {
        $appid = intval(input('appid'));
        $userA = intval(input('user_a'));
        $userB = intval(input('user_b'));
        if ($appid <= 0 || $userA <= 0 || $userB <= 0) return $this->imFail('参数错误');
        $this->blinRequireApp($appid);
        $count = intval(Db::name('messages')->where('appid', $appid)->where(function($q) use ($userA, $userB) {
            $q->whereOr(function($q2) use ($userA, $userB) {
                $q2->where('sender_id', $userA)->where('receiver_id', $userB);
            })->whereOr(function($q3) use ($userA, $userB) {
                $q3->where('sender_id', $userB)->where('receiver_id', $userA);
            });
        })->where('is_deleted', 0)->count());
        Db::name('messages')->where('appid', $appid)->where(function($q) use ($userA, $userB) {
            $q->whereOr(function($q2) use ($userA, $userB) {
                $q2->where('sender_id', $userA)->where('receiver_id', $userB);
            })->whereOr(function($q3) use ($userA, $userB) {
                $q3->where('sender_id', $userB)->where('receiver_id', $userA);
            });
        })->update(['is_deleted'=>1]);
        Db::name('im_message_log')->where('appid', $appid)->where(function($q) use ($userA, $userB) {
            $q->whereOr(function($q2) use ($userA, $userB) {
                $q2->where('from_user_id', $userA)->where('channel_user_id', $userB);
            })->whereOr(function($q3) use ($userA, $userB) {
                $q3->where('from_user_id', $userB)->where('channel_user_id', $userA);
            });
        })->update(['status'=>3, 'update_time'=>date('Y-m-d H:i:s')]);
        return $this->imOk('双方聊天记录已删除', '', ['deleted'=>$count]);
    }

    private function blinAdminImPrivateMarkRead()
    {
        $appid = intval(input('appid'));
        $userA = intval(input('user_a'));
        $userB = intval(input('user_b'));
        if ($appid <= 0 || $userA <= 0 || $userB <= 0) return $this->imFail('参数错误');
        $this->blinRequireApp($appid);
        Db::name('messages')->where('appid', $appid)->where(function($q) use ($userA, $userB) {
            $q->whereOr(function($q2) use ($userA, $userB) {
                $q2->where('sender_id', $userA)->where('receiver_id', $userB);
            })->whereOr(function($q3) use ($userA, $userB) {
                $q3->where('sender_id', $userB)->where('receiver_id', $userA);
            });
        })->update(['is_read'=>1]);
        return $this->imOk('已标记为已读');
    }
    // blin-visual-im-admin-end
'''


GROUP_VIEW = r'''{extend name="layout" /}
{block name="body"}
<style>
.im-toolbar{display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin-bottom:14px}.im-toolbar .form-control{height:38px}.im-card{border:0;border-radius:18px;box-shadow:0 8px 22px rgba(15,23,42,.06)}.im-card .card-header{background:#fff;border-bottom:1px solid #eef2f7;border-radius:18px 18px 0 0}.im-title{font-size:18px;font-weight:700;color:#1e293b}.im-sub{font-size:12px;color:#64748b}.im-avatar{width:34px;height:34px;border-radius:12px;object-fit:cover;background:#eef2ff}.im-actions .btn{margin:2px}.modal .form-label{font-weight:600;color:#334155}.text-clip{max-width:240px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
</style>
<div class="container-fluid p-t-15">
  <div class="card im-card">
    <header class="card-header d-flex justify-content-between align-items-center">
      <div><div class="im-title">群聊运营管理</div><div class="im-sub">创建、编辑、解散群聊，管理成员和群消息</div></div>
      <button class="btn btn-primary" onclick="openCreateModal()"><i class="mdi mdi-plus"></i> 创建群聊</button>
    </header>
    <div class="card-body">
      <div class="im-toolbar">
        <select class="form-control" id="appid" style="max-width:220px">
          <option value="">全部应用</option>
          {foreach $apps as $app}<option value="{$app.appid}">{$app.appname}（{$app.appid}）</option>{/foreach}
        </select>
        <select class="form-control" id="status" style="max-width:150px"><option value="1">正常群聊</option><option value="0">已解散</option><option value="">全部状态</option></select>
        <input class="form-control" id="keyword" placeholder="搜索群名、群号、群主" style="max-width:280px">
        <button class="btn btn-default" onclick="refreshGroups()"><i class="mdi mdi-magnify"></i> 搜索</button>
      </div>
      <table id="groupTable"></table>
    </div>
  </div>
</div>

<div class="modal fade" id="groupModal" tabindex="-1"><div class="modal-dialog modal-lg"><div class="modal-content">
  <div class="modal-header"><h6 class="modal-title" id="groupModalTitle">群聊资料</h6><button type="button" class="close" data-dismiss="modal" onclick="$('#groupModal').modal('hide')">&times;</button></div>
  <div class="modal-body">
    <input type="hidden" id="group_id">
    <div class="row">
      <div class="col-md-4 mb-3"><label class="form-label">应用</label><select class="form-control" id="form_appid">{foreach $apps as $app}<option value="{$app.appid}">{$app.appname}（{$app.appid}）</option>{/foreach}</select></div>
      <div class="col-md-4 mb-3"><label class="form-label">群名称</label><input class="form-control" id="form_name" maxlength="100"></div>
      <div class="col-md-4 mb-3"><label class="form-label">群主用户ID</label><input class="form-control" id="form_owner_id" placeholder="必填"></div>
      <div class="col-md-6 mb-3"><label class="form-label">群号</label><input class="form-control" id="form_group_no" placeholder="留空自动生成"></div>
      <div class="col-md-6 mb-3"><label class="form-label">群头像URL</label><input class="form-control" id="form_avatar" placeholder="可留空"></div>
      <div class="col-md-12 mb-3"><label class="form-label">群公告</label><textarea class="form-control" id="form_notice" rows="3"></textarea></div>
      <div class="col-md-12 mb-3" id="memberIdsWrap"><label class="form-label">初始成员用户ID</label><input class="form-control" id="form_member_ids" placeholder="多个ID用逗号分隔，群主会自动加入"></div>
      <div class="col-md-3 mb-2"><label><input type="checkbox" id="form_mute_all"> 全员禁言</label></div>
      <div class="col-md-3 mb-2"><label><input type="checkbox" id="form_notice_enabled" checked> 显示群公告</label></div>
      <div class="col-md-3 mb-2"><label><input type="checkbox" id="form_qr_enabled" checked> 允许群二维码</label></div>
      <div class="col-md-3 mb-2"><label><input type="checkbox" id="form_notice_pinned" checked> 公告置顶</label></div>
    </div>
  </div>
  <div class="modal-footer"><button class="btn btn-default" onclick="$('#groupModal').modal('hide')">取消</button><button class="btn btn-primary" onclick="saveGroup()">保存</button></div>
</div></div></div>

<div class="modal fade" id="membersModal" tabindex="-1"><div class="modal-dialog modal-xl"><div class="modal-content">
  <div class="modal-header"><h6 class="modal-title">成员管理</h6><button type="button" class="close" data-dismiss="modal" onclick="$('#membersModal').modal('hide')">&times;</button></div>
  <div class="modal-body">
    <input type="hidden" id="member_group_id">
    <div class="im-toolbar">
      <input class="form-control" id="member_keyword" placeholder="搜索成员" style="max-width:240px">
      <input class="form-control" id="add_user_ids" placeholder="添加用户ID，逗号分隔" style="max-width:280px">
      <button class="btn btn-primary" onclick="addMembers()">添加成员</button>
      <button class="btn btn-default" onclick="refreshMembers()">刷新</button>
    </div>
    <table id="memberTable"></table>
  </div>
</div></div></div>

<div class="modal fade" id="messagesModal" tabindex="-1"><div class="modal-dialog modal-xl"><div class="modal-content">
  <div class="modal-header"><h6 class="modal-title">群消息管理</h6><button type="button" class="close" data-dismiss="modal" onclick="$('#messagesModal').modal('hide')">&times;</button></div>
  <div class="modal-body">
    <input type="hidden" id="message_group_id">
    <div class="im-toolbar">
      <input class="form-control" id="message_keyword" placeholder="搜索消息内容/发送者" style="max-width:280px">
      <button class="btn btn-default" onclick="refreshGroupMessages()">搜索</button>
      <button class="btn btn-danger" onclick="clearGroupMessages()">清空该群聊天记录</button>
    </div>
    <table id="groupMessageTable"></table>
  </div>
</div></div></div>
{/block}
{block name="js"}
<script>
window.parent.$("#iframe-content .mt-nav-bar").find('a.active').text("群聊运营管理");
function ok(res){return res && (res.code==1 || res.status==1)}
function toast(res){ if(ok(res)){notify.success(res.msg||'操作成功')}else{notify.error((res&&res.msg)||'操作失败')} }
function refreshGroups(){ $('#groupTable').bootstrapTable('refresh'); }
function queryGroups(p){return {limit:p.limit,page:(p.offset/p.limit)+1,appid:$('#appid').val(),status:$('#status').val(),keyword:$('#keyword').val()}}
$('#groupTable').bootstrapTable({classes:'table table-bordered table-hover lyear-table',url:'{:url("group_manage")}',method:'get',dataType:'json',pagination:true,sidePagination:'server',pageSize:10,pageList:[10,25,50,100],showRefresh:true,showColumns:true,totalField:'total',queryParams:queryGroups,columns:[
 {field:'id',title:'ID'},
 {field:'appname',title:'应用'},
 {field:'name',title:'群聊',formatter:function(v,row){var img=row.avatar?'<img class="im-avatar mr-2" src="'+row.avatar+'">':'';return '<div class="d-flex align-items-center">'+img+'<div><b>'+escapeHtml(v||'')+'</b><div class="im-sub">'+escapeHtml(row.group_no||'')+'</div></div></div>';}},
 {field:'owner_name',title:'群主'},
 {field:'active_member_count',title:'成员'},
 {field:'message_count',title:'消息'},
 {field:'mute_text',title:'发言'},
 {field:'status_text',title:'状态'},
 {field:'update_time',title:'更新时间'},
 {field:'operate',title:'操作',formatter:function(v,row){var html='<div class="im-actions"><button class="btn btn-sm btn-primary edit-btn">编辑</button><button class="btn btn-sm btn-info member-btn">成员</button><button class="btn btn-sm btn-default msg-btn">消息</button>'; if(row.status==1){html+=' <button class="btn btn-sm btn-danger dismiss-btn">解散</button>';} return html+'</div>';},events:{'click .edit-btn':function(e,v,row){openEditModal(row)},'click .member-btn':function(e,v,row){openMembers(row)},'click .msg-btn':function(e,v,row){openMessages(row)},'click .dismiss-btn':function(e,v,row){dismissGroup(row)}}}
]});
function escapeHtml(s){return String(s||'').replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]})}
function openCreateModal(){ $('#groupModalTitle').text('创建群聊'); $('#group_id').val(''); $('#memberIdsWrap').show(); $('#form_appid').prop('disabled',false); $('#form_name,#form_owner_id,#form_group_no,#form_avatar,#form_notice,#form_member_ids').val(''); $('#form_mute_all').prop('checked',false); $('#form_notice_enabled,#form_qr_enabled,#form_notice_pinned').prop('checked',true); $('#groupModal').modal('show'); }
function openEditModal(row){ $('#groupModalTitle').text('编辑群聊'); $('#group_id').val(row.id); $('#memberIdsWrap').hide(); $('#form_appid').val(row.appid).prop('disabled',true); $('#form_name').val(row.name||''); $('#form_owner_id').val(row.owner_id||''); $('#form_group_no').val(row.group_no||''); $('#form_avatar').val(row.avatar||''); $('#form_notice').val(row.notice||''); $('#form_mute_all').prop('checked',row.mute_all==1); $('#form_notice_enabled').prop('checked',row.notice_enabled!=0); $('#form_qr_enabled').prop('checked',row.qr_enabled!=0); $('#form_notice_pinned').prop('checked',row.notice_pinned!=0); $('#groupModal').modal('show'); }
function groupPayload(op){return {op:op,id:$('#group_id').val(),appid:$('#form_appid').val(),name:$('#form_name').val(),owner_id:$('#form_owner_id').val(),group_no:$('#form_group_no').val(),avatar:$('#form_avatar').val(),notice:$('#form_notice').val(),member_ids:$('#form_member_ids').val(),mute_all:$('#form_mute_all').is(':checked')?1:0,notice_enabled:$('#form_notice_enabled').is(':checked')?1:0,qr_enabled:$('#form_qr_enabled').is(':checked')?1:0,notice_pinned:$('#form_notice_pinned').is(':checked')?1:0}}
function saveGroup(){var op=$('#group_id').val()?'update':'create'; $.post('{:url("group_manage")}',groupPayload(op),function(res){toast(res); if(ok(res)){ $('#groupModal').modal('hide'); refreshGroups();}},'json')}
function dismissGroup(row){ if(!confirm('确认解散群聊“'+row.name+'”？解散后成员将无法继续进入该群。'))return; $.post('{:url("group_manage")}',{op:'dismiss',id:row.id},function(res){toast(res); if(ok(res))refreshGroups();},'json') }
function openMembers(row){ $('#member_group_id').val(row.id); $('#member_keyword').val(''); $('#membersModal').modal('show'); setTimeout(function(){ if(!$('#memberTable').data('bootstrap.table')) initMembers(); else refreshMembers(); },150); }
function initMembers(){ $('#memberTable').bootstrapTable({classes:'table table-bordered table-hover lyear-table',url:'{:url("group_manage")}',method:'get',dataType:'json',pagination:true,sidePagination:'server',pageSize:10,totalField:'total',queryParams:function(p){return {op:'members',limit:p.limit,page:(p.offset/p.limit)+1,group_id:$('#member_group_id').val(),keyword:$('#member_keyword').val(),member_status:1}},columns:[{field:'user_id',title:'用户ID'},{field:'display_name',title:'昵称'},{field:'username',title:'账号'},{field:'role_text',title:'角色'},{field:'status_text',title:'状态'},{field:'operate',title:'操作',formatter:function(v,row){return '<button class="btn btn-sm btn-info role-admin">设管理员</button> <button class="btn btn-sm btn-secondary role-member">设成员</button> <button class="btn btn-sm btn-warning role-owner">设群主</button> <button class="btn btn-sm btn-danger remove-member">移出</button>';},events:{'click .role-admin':function(e,v,row){setMemberRole(row,1)},'click .role-member':function(e,v,row){setMemberRole(row,0)},'click .role-owner':function(e,v,row){setMemberRole(row,2)},'click .remove-member':function(e,v,row){removeMember(row)}}}]}); }
function refreshMembers(){ $('#memberTable').bootstrapTable('refresh'); }
function addMembers(){ $.post('{:url("group_manage")}',{op:'member_add',group_id:$('#member_group_id').val(),user_ids:$('#add_user_ids').val()},function(res){toast(res); if(ok(res)){ $('#add_user_ids').val(''); refreshMembers(); refreshGroups();}},'json') }
function removeMember(row){ if(!confirm('确认移出 '+row.display_name+'？'))return; $.post('{:url("group_manage")}',{op:'member_remove',group_id:$('#member_group_id').val(),user_ids:row.user_id},function(res){toast(res); if(ok(res)){refreshMembers();refreshGroups();}},'json') }
function setMemberRole(row,role){ $.post('{:url("group_manage")}',{op:'member_role',group_id:$('#member_group_id').val(),user_id:row.user_id,role:role},function(res){toast(res); if(ok(res)){refreshMembers();refreshGroups();}},'json') }
function openMessages(row){ $('#message_group_id').val(row.id); $('#message_keyword').val(''); $('#messagesModal').modal('show'); setTimeout(function(){ if(!$('#groupMessageTable').data('bootstrap.table')) initGroupMessages(); else refreshGroupMessages(); },150); }
function initGroupMessages(){ $('#groupMessageTable').bootstrapTable({classes:'table table-bordered table-hover lyear-table',url:'{:url("group_manage")}',method:'get',dataType:'json',pagination:true,sidePagination:'server',pageSize:10,totalField:'total',queryParams:function(p){return {op:'messages',limit:p.limit,page:(p.offset/p.limit)+1,group_id:$('#message_group_id').val(),keyword:$('#message_keyword').val()}},columns:[{field:'id',title:'ID'},{field:'sender_name',title:'发送人'},{field:'message_type',title:'类型'},{field:'content_short',title:'内容',class:'text-clip'},{field:'status_text',title:'状态'},{field:'create_time',title:'时间'},{field:'operate',title:'操作',formatter:function(){return '<button class="btn btn-sm btn-warning hide-msg">隐藏</button> <button class="btn btn-sm btn-danger del-msg">删除</button>';},events:{'click .hide-msg':function(e,v,row){hideGroupMessage(row)},'click .del-msg':function(e,v,row){deleteGroupMessage(row)}}}]}); }
function refreshGroupMessages(){ $('#groupMessageTable').bootstrapTable('refresh'); }
function hideGroupMessage(row){ $.post('{:url("group_manage")}',{op:'hide_message',id:row.id},function(res){toast(res); if(ok(res))refreshGroupMessages();},'json') }
function deleteGroupMessage(row){ if(!confirm('确认删除这条群消息？'))return; $.post('{:url("group_manage")}',{op:'delete_message',id:row.id},function(res){toast(res); if(ok(res)){refreshGroupMessages();refreshGroups();}},'json') }
function clearGroupMessages(){ if(!confirm('确认清空该群所有聊天记录？该操作不可恢复。'))return; $.post('{:url("group_manage")}',{op:'clear_messages',group_id:$('#message_group_id').val()},function(res){toast(res); if(ok(res)){refreshGroupMessages();refreshGroups();}},'json') }
</script>
{/block}
'''


PRIVATE_VIEW = r'''{extend name="layout" /}
{block name="body"}
<style>
.im-toolbar{display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin-bottom:14px}.im-toolbar .form-control{height:38px}.im-card{border:0;border-radius:18px;box-shadow:0 8px 22px rgba(15,23,42,.06)}.im-card .card-header{background:#fff;border-bottom:1px solid #eef2f7;border-radius:18px 18px 0 0}.im-title{font-size:18px;font-weight:700;color:#1e293b}.im-sub{font-size:12px;color:#64748b}.user-pair{display:flex;align-items:center;gap:8px}.user-dot{width:30px;height:30px;border-radius:11px;background:#eef2ff;display:inline-flex;align-items:center;justify-content:center;color:#6366f1;font-weight:700}.text-clip{max-width:320px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.im-actions .btn{margin:2px}
</style>
<div class="container-fluid p-t-15">
  <div class="card im-card">
    <header class="card-header">
      <div class="im-title">私聊记录管理</div>
      <div class="im-sub">按会话查看个人聊天记录，可隐藏消息、删除消息或清空双方会话</div>
    </header>
    <div class="card-body">
      <div class="im-toolbar">
        <select class="form-control" id="appid" style="max-width:220px"><option value="">全部应用</option>{foreach $apps as $app}<option value="{$app.appid}">{$app.appname}（{$app.appid}）</option>{/foreach}</select>
        <input class="form-control" id="keyword" placeholder="搜索用户、用户ID、消息内容" style="max-width:320px">
        <button class="btn btn-default" onclick="refreshConversations()"><i class="mdi mdi-magnify"></i> 搜索</button>
      </div>
      <table id="conversationTable"></table>
    </div>
  </div>
</div>

<div class="modal fade" id="messagesModal" tabindex="-1"><div class="modal-dialog modal-xl"><div class="modal-content">
  <div class="modal-header"><h6 class="modal-title" id="messageTitle">私聊消息</h6><button type="button" class="close" data-dismiss="modal" onclick="$('#messagesModal').modal('hide')">&times;</button></div>
  <div class="modal-body">
    <input type="hidden" id="msg_appid"><input type="hidden" id="msg_user_a"><input type="hidden" id="msg_user_b">
    <div class="im-toolbar">
      <input class="form-control" id="message_keyword" placeholder="搜索消息内容" style="max-width:260px">
      <label class="mb-0"><input type="checkbox" id="include_deleted"> 包含已删除</label>
      <button class="btn btn-default" onclick="refreshMessages()">搜索</button>
      <button class="btn btn-info" onclick="markRead()">标记已读</button>
      <button class="btn btn-danger" onclick="clearPair()">清空双方记录</button>
    </div>
    <table id="messageTable"></table>
  </div>
</div></div></div>
{/block}
{block name="js"}
<script>
window.parent.$("#iframe-content .mt-nav-bar").find('a.active').text("私聊记录管理");
function ok(res){return res && (res.code==1 || res.status==1)}
function toast(res){ if(ok(res)){notify.success(res.msg||'操作成功')}else{notify.error((res&&res.msg)||'操作失败')} }
function escapeHtml(s){return String(s||'').replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]})}
function refreshConversations(){ $('#conversationTable').bootstrapTable('refresh'); }
$('#conversationTable').bootstrapTable({classes:'table table-bordered table-hover lyear-table',url:'{:url("private_chat_manage")}',method:'get',dataType:'json',pagination:true,sidePagination:'server',pageSize:10,pageList:[10,25,50,100],showRefresh:true,showColumns:true,totalField:'total',queryParams:function(p){return {limit:p.limit,page:(p.offset/p.limit)+1,appid:$('#appid').val(),keyword:$('#keyword').val()}},columns:[
 {field:'appid',title:'APPID'},
 {field:'appname',title:'应用'},
 {field:'user_a_name',title:'会话用户',formatter:function(v,row){return '<div class="user-pair"><span class="user-dot">'+escapeHtml((row.user_a_name||'?').substring(0,1))+'</span><div><b>'+escapeHtml(row.user_a_name)+'</b><div class="im-sub">ID '+row.user_a+'</div></div></div>';}},
 {field:'user_b_name',title:'对方用户',formatter:function(v,row){return '<div class="user-pair"><span class="user-dot">'+escapeHtml((row.user_b_name||'?').substring(0,1))+'</span><div><b>'+escapeHtml(row.user_b_name)+'</b><div class="im-sub">ID '+row.user_b+'</div></div></div>';}},
 {field:'latest_content',title:'最后消息',class:'text-clip'},
 {field:'message_count',title:'消息数'},
 {field:'unread_count',title:'未读'},
 {field:'latest_time',title:'最后时间'},
 {field:'operate',title:'操作',formatter:function(){return '<div class="im-actions"><button class="btn btn-sm btn-primary view-btn">查看</button> <button class="btn btn-sm btn-info read-btn">标已读</button> <button class="btn btn-sm btn-danger clear-btn">清空双方</button></div>';},events:{'click .view-btn':function(e,v,row){openMessages(row)},'click .read-btn':function(e,v,row){markReadRow(row)},'click .clear-btn':function(e,v,row){clearPairRow(row)}}}
]});
function openMessages(row){ $('#msg_appid').val(row.appid); $('#msg_user_a').val(row.user_a); $('#msg_user_b').val(row.user_b); $('#message_keyword').val(''); $('#include_deleted').prop('checked',false); $('#messageTitle').text(row.user_a_name+' 与 '+row.user_b_name+' 的聊天记录'); $('#messagesModal').modal('show'); setTimeout(function(){ if(!$('#messageTable').data('bootstrap.table')) initMessages(); else refreshMessages(); },150); }
function initMessages(){ $('#messageTable').bootstrapTable({classes:'table table-bordered table-hover lyear-table',url:'{:url("private_chat_manage")}',method:'get',dataType:'json',pagination:true,sidePagination:'server',pageSize:10,pageList:[10,25,50,100],totalField:'total',queryParams:function(p){return {op:'messages',limit:p.limit,page:(p.offset/p.limit)+1,appid:$('#msg_appid').val(),user_a:$('#msg_user_a').val(),user_b:$('#msg_user_b').val(),keyword:$('#message_keyword').val(),include_deleted:$('#include_deleted').is(':checked')?1:0}},columns:[{field:'id',title:'ID'},{field:'sender_name',title:'发送人'},{field:'receiver_name',title:'接收人'},{field:'message_type',title:'类型'},{field:'content_short',title:'内容',class:'text-clip'},{field:'read_text',title:'已读'},{field:'status_text',title:'状态'},{field:'create_time',title:'时间'},{field:'operate',title:'操作',formatter:function(v,row){var disabled=row.is_deleted==1?' disabled':'';return '<button class="btn btn-sm btn-warning hide-msg"'+disabled+'>隐藏</button> <button class="btn btn-sm btn-danger del-msg"'+disabled+'>删除</button>';},events:{'click .hide-msg':function(e,v,row){hideMessage(row)},'click .del-msg':function(e,v,row){deleteMessage(row)}}}]}); }
function refreshMessages(){ $('#messageTable').bootstrapTable('refresh'); }
function hideMessage(row){ $.post('{:url("private_chat_manage")}',{op:'hide_message',id:row.id},function(res){toast(res); if(ok(res)){refreshMessages();refreshConversations();}},'json') }
function deleteMessage(row){ if(!confirm('确认删除这条消息？删除后客户端聊天记录不再显示。'))return; $.post('{:url("private_chat_manage")}',{op:'delete_message',id:row.id},function(res){toast(res); if(ok(res)){refreshMessages();refreshConversations();}},'json') }
function clearPair(){ clearPairRow({appid:$('#msg_appid').val(),user_a:$('#msg_user_a').val(),user_b:$('#msg_user_b').val(),user_a_name:$('#msg_user_a').val(),user_b_name:$('#msg_user_b').val()}); }
function clearPairRow(row){ if(!confirm('确认清空双方聊天记录？该操作会让双方都看不到这些私聊记录。'))return; $.post('{:url("private_chat_manage")}',{op:'clear_pair',appid:row.appid,user_a:row.user_a,user_b:row.user_b},function(res){toast(res); if(ok(res)){refreshMessages();refreshConversations();}},'json') }
function markRead(){ markReadRow({appid:$('#msg_appid').val(),user_a:$('#msg_user_a').val(),user_b:$('#msg_user_b').val()}); }
function markReadRow(row){ $.post('{:url("private_chat_manage")}',{op:'mark_read',appid:row.appid,user_a:row.user_a,user_b:row.user_b},function(res){toast(res); if(ok(res)){refreshMessages();refreshConversations();}},'json') }
</script>
{/block}
'''


def patch_controller() -> None:
    text = CONTROLLER.read_text()
    if "blin-visual-im-admin-start" in text:
        print("controller already patched")
        return
    marker = "    public function update_message_status()\n"
    if marker not in text:
        raise RuntimeError("update_message_status marker not found")
    CONTROLLER.write_text(text.replace(marker, PHP_SNIPPET + "\n" + marker, 1))
    print("controller patched")


def write_views() -> None:
    VIEW_DIR.mkdir(parents=True, exist_ok=True)
    (VIEW_DIR / "group_manage.html").write_text(GROUP_VIEW)
    (VIEW_DIR / "private_chat_manage.html").write_text(PRIVATE_VIEW)
    print("views written")


def ensure_permissions() -> None:
    # The project uses ThinkPHP Db at runtime; menu rows are safer to add with
    # the local mysql client because this patch script runs outside the app.
    import os
    import subprocess

    db_password = os.environ.get("BLINLIN_DB_PASSWORD")
    if not db_password:
        raise RuntimeError("BLINLIN_DB_PASSWORD is required")

    sql = r"""
SET @pid := (SELECT id FROM mr_admin_permission WHERE url='im' ORDER BY id DESC LIMIT 1);
INSERT INTO mr_admin_permission (pid,name,url,icon,sort,is_out,is_menu)
SELECT @pid,'群聊运营管理','im/group_manage','mdi-account-group-outline',13,2,1
WHERE @pid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM mr_admin_permission WHERE url='im/group_manage');
INSERT INTO mr_admin_permission (pid,name,url,icon,sort,is_out,is_menu)
SELECT @pid,'私聊记录管理','im/private_chat_manage','mdi-message-text-outline',14,2,1
WHERE @pid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM mr_admin_permission WHERE url='im/private_chat_manage');
"""
    subprocess.run(
        [
            "mysql",
            "-h127.0.0.1",
            "-ublinlin",
            "-p" + db_password,
            "blinlin",
        ],
        input=sql.encode(),
        check=True,
    )
    print("permissions ensured")


patch_controller()
write_views()
ensure_permissions()
