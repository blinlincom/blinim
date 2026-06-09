from pathlib import Path

p = Path('/www/wwwroot/blinlin/application/api/controller/Api.php')
s = p.read_text()
backup = p.with_suffix('.php.bak_im_group_20260609')
backup.write_text(s)

marker = '\n    //获取悟空IM连接信息\n'
if 'public function create_im_group()' in s:
    print('group api already exists')
    raise SystemExit(0)

code = r'''
    private function ensure_im_group_tables()
    {
        Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_groups` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `group_no` varchar(64) NOT NULL DEFAULT '', `name` varchar(100) NOT NULL DEFAULT '', `avatar` varchar(255) NOT NULL DEFAULT '', `owner_id` int(11) NOT NULL DEFAULT 0, `member_count` int(11) NOT NULL DEFAULT 0, `status` tinyint(1) NOT NULL DEFAULT 1, `create_time` datetime DEFAULT NULL, `update_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), UNIQUE KEY `uk_group_no` (`group_no`), KEY `idx_appid` (`appid`)) ENGINE=InnoDB DEFAULT CHARSET=utf8;");
        Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_group_members` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `group_id` int(11) NOT NULL DEFAULT 0, `user_id` int(11) NOT NULL DEFAULT 0, `role` tinyint(1) NOT NULL DEFAULT 0, `status` tinyint(1) NOT NULL DEFAULT 1, `create_time` datetime DEFAULT NULL, `update_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), UNIQUE KEY `uk_group_user` (`group_id`,`user_id`), KEY `idx_user` (`user_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8;");
        Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_group_messages` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `group_id` int(11) NOT NULL DEFAULT 0, `sender_id` int(11) NOT NULL DEFAULT 0, `message_type` int(11) NOT NULL DEFAULT 0, `content` text, `payload` text, `client_msg_no` varchar(128) NOT NULL DEFAULT '', `create_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), KEY `idx_group_id` (`group_id`), KEY `idx_create_time` (`create_time`)) ENGINE=InnoDB DEFAULT CHARSET=utf8;");
    }

    private function current_group_user()
    {
        $user_all_info = $this->user_info;
        if (!$user_all_info || !isset($user_all_info["id"])) { $this->json(0, "用户信息异常"); }
        return $user_all_info;
    }

    public function create_im_group()
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
        $groupId = Db::name('im_groups')->insertGetId(['appid'=>$this->appid, 'group_no'=>$groupNo, 'name'=>trim(strval($data['name'])), 'owner_id'=>intval($user['id']), 'member_count'=>count($validUsers)+1, 'status'=>1, 'create_time'=>$now, 'update_time'=>$now]);
        Db::name('im_group_members')->insert(['appid'=>$this->appid, 'group_id'=>$groupId, 'user_id'=>intval($user['id']), 'role'=>2, 'status'=>1, 'create_time'=>$now, 'update_time'=>$now]);
        foreach ($validUsers as $uid) { Db::name('im_group_members')->insert(['appid'=>$this->appid, 'group_id'=>$groupId, 'user_id'=>intval($uid), 'role'=>0, 'status'=>1, 'create_time'=>$now, 'update_time'=>$now], true); }
        $this->json(1, '创建成功', ['id'=>$groupId, 'group_id'=>$groupId, 'group_no'=>$groupNo, 'name'=>trim(strval($data['name'])), 'member_count'=>count($validUsers)+1]);
    }

    public function get_im_group_list()
    {
        $data = input();
        $rule = ['usertoken|用户token' => 'require'];
        $validate = new Validate($rule);
        if (!$validate->check($data)) { $this->json(0, $validate->getError()); }
        $user = $this->current_group_user();
        $this->ensure_im_group_tables();
        $rows = Db::name('im_group_members')->alias('m')->join('im_groups g', 'g.id=m.group_id')->where('m.user_id', intval($user['id']))->where('m.status', 1)->where('g.status', 1)->field('g.id,g.group_no,g.name,g.avatar,g.member_count,g.update_time')->order('g.update_time desc')->select();
        $this->json(1, 'success', $rows ?: []);
    }

    public function send_im_group_message()
    {
        $data = input();
        $rule = ['usertoken|用户token' => 'require', 'group_id|群ID' => 'require|number'];
        $validate = new Validate($rule);
        if (!$validate->check($data)) { $this->json(0, $validate->getError()); }
        $user = $this->current_group_user();
        $this->ensure_im_group_tables();
        $groupId = intval($data['group_id']);
        $member = Db::name('im_group_members')->where('group_id', $groupId)->where('user_id', intval($user['id']))->where('status', 1)->find();
        if (!$member) { $this->json(0, '你不在该群聊中'); }
        $group = Db::name('im_groups')->where('id', $groupId)->where('status', 1)->find();
        if (!$group) { $this->json(0, '群聊不存在'); }
        $content = isset($data['content']) ? strval($data['content']) : '';
        $payloadRaw = isset($data['im_payload']) ? strval($data['im_payload']) : (isset($data['payload']) ? strval($data['payload']) : '');
        $payload = $payloadRaw ? json_decode($payloadRaw, true) : null;
        if (!is_array($payload)) {
            $payload = ['msg_type'=>'text', 'content'=>['text'=>$content]];
        }
        $payload['group_id'] = $groupId;
        $payload['group_no'] = $group['group_no'];
        $payload['from_user_id'] = intval($user['id']);
        $payload['from_uid'] = $this->appid . '_' . intval($user['id']);
        $payload['to_uid'] = $group['group_no'];
        $payload['create_time'] = date('Y-m-d H:i:s');
        $clientNo = isset($payload['client_msg_no']) ? strval($payload['client_msg_no']) : ('group_msg_' . $groupId . '_' . time() . '_' . mt_rand(1000,9999));
        $messageId = Db::name('im_group_messages')->insertGetId(['appid'=>$this->appid, 'group_id'=>$groupId, 'sender_id'=>intval($user['id']), 'message_type'=>0, 'content'=>$content, 'payload'=>json_encode($payload, JSON_UNESCAPED_UNICODE), 'client_msg_no'=>$clientNo, 'create_time'=>date('Y-m-d H:i:s')]);
        Db::name('im_groups')->where('id', $groupId)->update(['update_time'=>date('Y-m-d H:i:s')]);
        try { if (config('wukongim.enable')) { $wkim = new \app\common\tool\WukongIM(); $wkim->sendMessage($this->appid . '_' . intval($user['id']), $group['group_no'], 2, $payload, $clientNo, ['no_persist'=>0,'red_dot'=>1,'sync_once'=>0]); } } catch (\Exception $e) {}
        $this->json(1, '发送成功', ['message_id'=>$messageId]);
    }

    public function get_im_group_chat_log()
    {
        $data = input();
        $rule = ['usertoken|用户token' => 'require', 'group_id|群ID' => 'require|number'];
        $validate = new Validate($rule);
        if (!$validate->check($data)) { $this->json(0, $validate->getError()); }
        $user = $this->current_group_user();
        $this->ensure_im_group_tables();
        $groupId = intval($data['group_id']);
        $member = Db::name('im_group_members')->where('group_id', $groupId)->where('user_id', intval($user['id']))->where('status', 1)->find();
        if (!$member) { $this->json(0, '你不在该群聊中'); }
        $page = max(1, intval(isset($data['page']) ? $data['page'] : 1));
        $limit = max(1, min(100, intval(isset($data['limit']) ? $data['limit'] : 30)));
        $offset = ($page - 1) * $limit;
        $rows = Db::name('im_group_messages')->where('group_id', $groupId)->order('id desc')->limit($offset, $limit)->select();
        $list = [];
        foreach ($rows as $r) { $list[] = ['message'=>['id'=>$r['id'], 'sender_id'=>$r['sender_id'], 'receiver_id'=>$groupId, 'message_type'=>$r['message_type'], 'content'=>$r['content'], 'im_payload'=>$r['payload'], 'create_time'=>$r['create_time']]]; }
        $this->json(1, 'success', ['list'=>$list]);
    }

'''
if marker not in s:
    raise SystemExit('marker not found')
p.write_text(s.replace(marker, '\n' + code + marker, 1))
print('patched', backup)
