from pathlib import Path
p = Path('/www/wwwroot/blinlin/application/api/controller/Api.php')
s = p.read_text()
backup = p.with_suffix('.php.bak_online_device_wukong_20260608')
backup.write_text(s)

old = '''        $device_flag = input("device_flag") === "" ? 0 : intval(input("device_flag"));
        try {
                $wkim = new \\app\\common\\tool\\WukongIM();
            $wkim->updateUserToken($uid, $token, $device_flag, 1);
            $route = $wkim->getUserRoute($uid, intval(config('wukongim.route_intranet')));
            $this->json(1, "success", ["uid"=>$uid,"token"=>$token,"device_flag"=>$device_flag,"device_level"=>1,"route"=>$route,"ws_addr"=>isset($route["ws_addr"])?$route["ws_addr"]:config('wukongim.ws_url'),"tcp_addr"=>isset($route["tcp_addr"])?$route["tcp_addr"]:"","wss_addr"=>isset($route["wss_addr"])?$route["wss_addr"]:""]);
        } catch (\\Exception $e) { $this->json(0, "悟空IM连接信息获取失败：" . $e->getMessage()); }
'''
new = '''        $device_flag = input("device_flag") === "" ? 0 : intval(input("device_flag"));
        $platform = trim(strval(input("platform") ?: ""));
        $terminal = trim(strval(input("terminal") ?: input("device_type") ?: ""));
        $device = trim(strval(input("device") ?: $terminal ?: $platform ?: $device_flag));
        try {
                $wkim = new \\app\\common\\tool\\WukongIM();
            $wkim->updateUserToken($uid, $token, $device_flag, 1);
            $route = $wkim->getUserRoute($uid, intval(config('wukongim.route_intranet')));
            try {
                Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_online_status` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `uid` varchar(64) NOT NULL DEFAULT '', `user_id` int(11) NOT NULL DEFAULT 0, `online` tinyint(1) NOT NULL DEFAULT 0, `last_event` varchar(64) NOT NULL DEFAULT '', `last_seen` datetime DEFAULT NULL, `raw_data` text, `update_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), UNIQUE KEY `uk_uid` (`uid`), KEY `idx_user_id` (`user_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8;");
                try { Db::execute("ALTER TABLE `mr_im_online_status` ADD COLUMN `device` varchar(32) NOT NULL DEFAULT ''"); } catch (\\Exception $e) {}
                try { Db::execute("ALTER TABLE `mr_im_online_status` ADD COLUMN `platform` varchar(32) NOT NULL DEFAULT ''"); } catch (\\Exception $e) {}
                try { Db::execute("ALTER TABLE `mr_im_online_status` ADD COLUMN `terminal` varchar(32) NOT NULL DEFAULT ''"); } catch (\\Exception $e) {}
                try { Db::execute("ALTER TABLE `mr_im_online_status` ADD COLUMN `device_flag` int(11) NOT NULL DEFAULT 0"); } catch (\\Exception $e) {}
                $now = date('Y-m-d H:i:s');
                $raw = json_encode(["event"=>"connect_info", "device"=>$device, "platform"=>$platform, "terminal"=>$terminal, "device_flag"=>$device_flag], JSON_UNESCAPED_UNICODE);
                $exists = Db::name('im_online_status')->where('uid', $uid)->find();
                $save = ['appid'=>$this->appid, 'uid'=>$uid, 'user_id'=>intval($user_all_info["id"]), 'online'=>1, 'last_event'=>'connect_info', 'raw_data'=>$raw, 'update_time'=>$now, 'device'=>$device, 'platform'=>$platform, 'terminal'=>$terminal, 'device_flag'=>$device_flag];
                if ($exists) { Db::name('im_online_status')->where('uid', $uid)->update($save); } else { $save['last_seen'] = null; Db::name('im_online_status')->insert($save); }
            } catch (\\Exception $e) {}
            $this->json(1, "success", ["uid"=>$uid,"token"=>$token,"device_flag"=>$device_flag,"device_level"=>1,"device"=>$device,"platform"=>$platform,"terminal"=>$terminal,"route"=>$route,"ws_addr"=>isset($route["ws_addr"])?$route["ws_addr"]:config('wukongim.ws_url'),"tcp_addr"=>isset($route["tcp_addr"])?$route["tcp_addr"]:"","wss_addr"=>isset($route["wss_addr"])?$route["wss_addr"]:""]);
        } catch (\\Exception $e) { $this->json(0, "悟空IM连接信息获取失败：" . $e->getMessage()); }
'''
if old not in s:
    raise SystemExit('connect block not found')
s = s.replace(old, new)

old2 = '''            $rawJson = json_encode($ev, JSON_UNESCAPED_UNICODE);
            try {
                $exists = Db::name('im_online_status')->where('uid', $uid)->find();
                $save = ['appid'=>$appid, 'uid'=>$uid, 'user_id'=>$user_id, 'online'=>$online ? 1 : 0, 'last_event'=>$eventName ?: $statusRaw, 'raw_data'=>$rawJson, 'update_time'=>$now];
'''
new2 = '''            $rawJson = json_encode($ev, JSON_UNESCAPED_UNICODE);
            $device_flag = isset($ev['device_flag']) ? intval($ev['device_flag']) : (isset($ev['deviceFlag']) ? intval($ev['deviceFlag']) : 0);
            $platform = isset($ev['platform']) ? strval($ev['platform']) : '';
            $terminal = isset($ev['terminal']) ? strval($ev['terminal']) : (isset($ev['device_type']) ? strval($ev['device_type']) : '');
            $device = isset($ev['device']) ? strval($ev['device']) : ($terminal ?: ($platform ?: strval($device_flag)));
            try { Db::execute("ALTER TABLE `mr_im_online_status` ADD COLUMN `device` varchar(32) NOT NULL DEFAULT ''"); } catch (\\Exception $e) {}
            try { Db::execute("ALTER TABLE `mr_im_online_status` ADD COLUMN `platform` varchar(32) NOT NULL DEFAULT ''"); } catch (\\Exception $e) {}
            try { Db::execute("ALTER TABLE `mr_im_online_status` ADD COLUMN `terminal` varchar(32) NOT NULL DEFAULT ''"); } catch (\\Exception $e) {}
            try { Db::execute("ALTER TABLE `mr_im_online_status` ADD COLUMN `device_flag` int(11) NOT NULL DEFAULT 0"); } catch (\\Exception $e) {}
            try {
                $exists = Db::name('im_online_status')->where('uid', $uid)->find();
                $save = ['appid'=>$appid, 'uid'=>$uid, 'user_id'=>$user_id, 'online'=>$online ? 1 : 0, 'last_event'=>$eventName ?: $statusRaw, 'raw_data'=>$rawJson, 'update_time'=>$now, 'device'=>$device, 'platform'=>$platform, 'terminal'=>$terminal, 'device_flag'=>$device_flag];
'''
if old2 not in s:
    raise SystemExit('webhook block not found')
s = s.replace(old2, new2)

old3 = '''        $online = false;
        $online_uids = [];
        $source = "none";
        $api_error = "";
'''
new3 = '''        $online = false;
        $online_uids = [];
        $source = "none";
        $api_error = "";
        $device = "";
        $platform = "";
        $terminal = "";
        $device_flag = 0;
'''
s = s.replace(old3, new3, 1)

old4 = '''            if ($rows) {
                foreach ($rows as $r) {
                    if (intval($r['online']) === 1) {
                        $online = true;
                        $source = $source === "wukongim" ? "wukongim+db" : "db";
                        break;
                    }
                }
                if ($source === "none") { $source = "db"; }
            }
'''
new4 = '''            if ($rows) {
                foreach ($rows as $r) {
                    if ($device === "") $device = isset($r['device']) ? strval($r['device']) : "";
                    if ($platform === "") $platform = isset($r['platform']) ? strval($r['platform']) : "";
                    if ($terminal === "") $terminal = isset($r['terminal']) ? strval($r['terminal']) : "";
                    if ($device_flag === 0 && isset($r['device_flag'])) $device_flag = intval($r['device_flag']);
                    if (intval($r['online']) === 1) {
                        $online = true;
                        $device = isset($r['device']) ? strval($r['device']) : $device;
                        $platform = isset($r['platform']) ? strval($r['platform']) : $platform;
                        $terminal = isset($r['terminal']) ? strval($r['terminal']) : $terminal;
                        $device_flag = isset($r['device_flag']) ? intval($r['device_flag']) : $device_flag;
                        $source = $source === "wukongim" ? "wukongim+db" : "db";
                        break;
                    }
                }
                if ($source === "none") { $source = "db"; }
            }
'''
if old4 not in s:
    raise SystemExit('status rows block not found')
s = s.replace(old4, new4)

old5 = '''            "online"=>$online,
            "online_uids"=>$online_uids,
            "source"=>$source,
            "api_error"=>$api_error,
'''
new5 = '''            "online"=>$online,
            "device"=>$device ?: ($terminal ?: ($platform ?: strval($device_flag))),
            "platform"=>$platform,
            "terminal"=>$terminal,
            "device_flag"=>$device_flag,
            "online_uids"=>$online_uids,
            "source"=>$source,
            "api_error"=>$api_error,
'''
if old5 not in s:
    raise SystemExit('status output block not found')
s = s.replace(old5, new5)

p.write_text(s)
print('patched', backup)
