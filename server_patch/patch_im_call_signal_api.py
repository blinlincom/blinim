#!/usr/bin/env python3
"""Patch ThinkPHP Api.php with backend-routed WuKongIM call signaling APIs.

Adds:
  POST /send_im_call_signal
  POST /get_im_call_signals

Client -> backend -> DB + WuKongIM server push. Client must not send business
signals directly through WuKongIM SDK.
"""
from pathlib import Path
from datetime import datetime

p = Path('/www/wwwroot/blinlin/application/api/controller/Api.php')
s = p.read_text(errors='ignore')
backup = p.with_name('Api.php.bak_im_call_signal_' + datetime.now().strftime('%Y%m%d%H%M%S'))
backup.write_text(s)

if 'public function send_im_call_signal()' in s and 'public function get_im_call_signals()' in s:
    print('IM_CALL_SIGNAL_API_ALREADY_EXISTS')
    raise SystemExit(0)

marker = '\n    //获取悟空IM连接信息\n'
if marker not in s:
    marker = '\n    public function get_im_connect_info()'
if marker not in s:
    raise SystemExit('MARKER_NOT_FOUND')

code = r'''
    private function ensure_im_call_signal_tables()
    {
        Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_call_signals` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `call_id` varchar(128) NOT NULL DEFAULT '', `client_msg_no` varchar(128) NOT NULL DEFAULT '', `from_user_id` int(11) NOT NULL DEFAULT 0, `to_user_id` int(11) NOT NULL DEFAULT 0, `action` varchar(32) NOT NULL DEFAULT '', `media` varchar(16) NOT NULL DEFAULT '', `payload` mediumtext, `status` tinyint(1) NOT NULL DEFAULT 1, `create_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), UNIQUE KEY `uk_client_msg_no` (`client_msg_no`), KEY `idx_to_id` (`to_user_id`,`id`), KEY `idx_call_id` (`call_id`), KEY `idx_from_to` (`from_user_id`,`to_user_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
    }

    private function im_call_user()
    {
        $user_all_info = $this->user_info;
        if (!$user_all_info || !isset($user_all_info['id'])) { $this->json(0, '用户信息异常'); }
        return $user_all_info;
    }

    private function normalize_im_call_action($raw)
    {
        $raw = strval($raw);
        if ($raw == 'call_invite') return 'invite';
        if ($raw == 'call_offer') return 'offer';
        if ($raw == 'call_accept') return 'accept';
        if ($raw == 'call_answer') return 'answer';
        if ($raw == 'call_ice') return 'ice';
        if ($raw == 'call_hangup') return 'hangup';
        if ($raw == 'call_reject') return 'reject';
        if ($raw == 'call_ack') return 'ack';
        if (strpos($raw, 'call_') === 0) return substr($raw, 5);
        return $raw;
    }

    public function send_im_call_signal()
    {
        $data = input();
        $rule = ['usertoken|用户token' => 'require', 'to_user_id|接收用户' => 'require|number'];
        $validate = new Validate($rule);
        if (!$validate->check($data)) { $this->json(0, $validate->getError()); }
        $user = $this->im_call_user();
        $this->ensure_im_call_signal_tables();

        $fromId = intval($user['id']);
        $toId = intval(isset($data['to_user_id']) ? $data['to_user_id'] : (isset($data['receiver_id']) ? $data['receiver_id'] : 0));
        if ($toId <= 0 || $toId == $fromId) { $this->json(0, '接收用户错误'); }
        $target = Db::name('user')->where('appid', $this->appid)->where('id', $toId)->find();
        if (!$target) { $this->json(0, '接收用户不存在'); }

        $payloadRaw = isset($data['im_payload']) ? strval($data['im_payload']) : (isset($data['payload']) ? strval($data['payload']) : '');
        $payload = $payloadRaw ? json_decode($payloadRaw, true) : null;
        if (!is_array($payload)) { $payload = []; }
        $content = isset($payload['content']) && is_array($payload['content']) ? $payload['content'] : [];

        $action = $this->normalize_im_call_action(isset($data['action']) ? $data['action'] : (isset($content['action']) ? $content['action'] : (isset($content['type']) ? $content['type'] : '')));
        if ($action === '') { $this->json(0, '通话动作不能为空'); }
        $callId = isset($data['call_id']) ? strval($data['call_id']) : (isset($content['call_id']) ? strval($content['call_id']) : '');
        if ($callId === '') { $callId = 'call_' . $this->appid . '_' . $fromId . '_' . $toId . '_' . time() . '_' . mt_rand(1000,9999); }
        $media = isset($data['media']) ? strval($data['media']) : (isset($content['media']) ? strval($content['media']) : 'audio');
        $clientNo = isset($data['client_msg_no']) ? strval($data['client_msg_no']) : (isset($payload['client_msg_no']) ? strval($payload['client_msg_no']) : ($callId . '_' . microtime(true) . '_' . $action));
        $now = date('Y-m-d H:i:s');

        $payload['msg_type'] = 'call';
        $payload['client_msg_no'] = $clientNo;
        $payload['from_user_id'] = $fromId;
        $payload['to_user_id'] = $toId;
        $payload['from_uid'] = $this->appid . '_' . $fromId;
        $payload['to_uid'] = $this->appid . '_' . $toId;
        $payload['create_time'] = $now;
        $payload['content'] = array_merge($content, [
            'call_id' => $callId,
            'signal_id' => isset($content['signal_id']) ? $content['signal_id'] : $clientNo,
            'action' => $action,
            'type' => 'call_' . $action,
            'media' => $media,
        ]);

        $encoded = json_encode($payload, JSON_UNESCAPED_UNICODE);
        $exists = Db::name('im_call_signals')->where('appid', $this->appid)->where('client_msg_no', $clientNo)->find();
        if ($exists) {
            $signalId = intval($exists['id']);
        } else {
            $signalId = Db::name('im_call_signals')->insertGetId([
                'appid'=>$this->appid,
                'call_id'=>$callId,
                'client_msg_no'=>$clientNo,
                'from_user_id'=>$fromId,
                'to_user_id'=>$toId,
                'action'=>$action,
                'media'=>$media,
                'payload'=>$encoded,
                'status'=>1,
                'create_time'=>$now,
            ]);
        }

        try {
            if (config('wukongim.enable')) {
                $wkim = new \app\common\tool\WukongIM();
                $wkim->sendMessage($this->appid . '_' . $fromId, $this->appid . '_' . $toId, 1, $payload, $clientNo, ['no_persist'=>0,'red_dot'=>($action == 'invite' ? 1 : 0),'sync_once'=>0]);
            }
        } catch (\Exception $e) {}

        $this->json(1, '发送成功', ['id'=>$signalId, 'call_id'=>$callId, 'client_msg_no'=>$clientNo]);
    }

    public function get_im_call_signals()
    {
        $data = input();
        $rule = ['usertoken|用户token' => 'require'];
        $validate = new Validate($rule);
        if (!$validate->check($data)) { $this->json(0, $validate->getError()); }
        $user = $this->im_call_user();
        $this->ensure_im_call_signal_tables();
        $uid = intval($user['id']);
        $sinceId = max(0, intval(isset($data['since_id']) ? $data['since_id'] : 0));
        $limit = max(1, min(100, intval(isset($data['limit']) ? $data['limit'] : 50)));
        $callId = isset($data['call_id']) ? trim(strval($data['call_id'])) : '';
        $peerId = intval(isset($data['peer_id']) ? $data['peer_id'] : 0);

        $q = Db::name('im_call_signals')->where('appid', $this->appid)->where('id', '>', $sinceId)->where(function($query) use ($uid) { $query->where('to_user_id', $uid)->whereOr('from_user_id', $uid); });
        if ($callId !== '') { $q = $q->where('call_id', $callId); }
        if ($peerId > 0) { $q = $q->where(function($query) use ($uid, $peerId) { $query->where(['from_user_id'=>$uid,'to_user_id'=>$peerId])->whereOr(['from_user_id'=>$peerId,'to_user_id'=>$uid]); }); }
        $rows = $q->order('id asc')->limit($limit)->select();
        $list = [];
        foreach (($rows ?: []) as $r) {
            $payload = json_decode(isset($r['payload']) ? $r['payload'] : '', true);
            if (!is_array($payload)) { $payload = []; }
            $list[] = ['id'=>intval($r['id']), 'call_id'=>$r['call_id'], 'action'=>$r['action'], 'from_user_id'=>intval($r['from_user_id']), 'to_user_id'=>intval($r['to_user_id']), 'payload'=>$payload, 'create_time'=>$r['create_time']];
        }
        $this->json(1, 'success', ['list'=>$list]);
    }

'''

p.write_text(s.replace(marker, '\n' + code + marker, 1))
print('PATCH_OK', backup)
