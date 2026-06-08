from pathlib import Path
p = Path('/www/wwwroot/blinlin/application/api/controller/Api.php')
s = p.read_text()
backup = p.with_suffix('.php.bak_online_heartbeat_ttl_20260609')
backup.write_text(s)
insert_before = '    //批量获取IM用户资料\n'
heartbeat = r'''    // IM在线心跳：客户端前台定时上报，退出后超时自动判离线
    public function im_online_heartbeat()
    {
        $data = input();
        $rule = ['usertoken|用户token' => 'require'];
        $validate = new Validate($rule);
        if (!$validate->check($data)) { $this->json(0, $validate->getError()); }
        $user_all_info = $this->user_info;
        if (!$user_all_info || !isset($user_all_info["id"])) { $this->json(0, "用户信息异常"); }
        $uid = $this->appid . "_" . intval($user_all_info["id"]);
        $device_flag = input("device_flag") === "" ? 0 : intval(input("device_flag"));
        $platform = trim(strval(input("platform") ?: ""));
        $terminal = trim(strval(input("terminal") ?: input("device_type") ?: ""));
        $device = trim(strval(input("device") ?: $terminal ?: $platform ?: $device_flag));
        $onlineRaw = strtolower(strval(input("online") === "" ? "1" : input("online")));
        $online = !($onlineRaw === "0" || $onlineRaw === "false" || $onlineRaw === "offline");
        $now = date('Y-m-d H:i:s');
        try {
            Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_online_status` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `uid` varchar(64) NOT NULL DEFAULT '', `user_id` int(11) NOT NULL DEFAULT 0, `online` tinyint(1) NOT NULL DEFAULT 0, `last_event` varchar(64) NOT NULL DEFAULT '', `last_seen` datetime DEFAULT NULL, `raw_data` text, `update_time` datetime DEFAULT NULL, `device` varchar(32) NOT NULL DEFAULT '', `platform` varchar(32) NOT NULL DEFAULT '', `terminal` varchar(32) NOT NULL DEFAULT '', `device_flag` int(11) NOT NULL DEFAULT 0, PRIMARY KEY (`id`), UNIQUE KEY `uk_uid` (`uid`), KEY `idx_user_id` (`user_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8;");
            foreach (["last_event varchar(64) NOT NULL DEFAULT ''", "last_seen datetime DEFAULT NULL", "raw_data text", "update_time datetime DEFAULT NULL", "device varchar(32) NOT NULL DEFAULT ''", "platform varchar(32) NOT NULL DEFAULT ''", "terminal varchar(32) NOT NULL DEFAULT ''", "device_flag int(11) NOT NULL DEFAULT 0"] as $col) {
                $name = explode(' ', $col)[0];
                try { Db::execute("ALTER TABLE `mr_im_online_status` ADD COLUMN `".$name."` ".$col); } catch (\Exception $e) {}
            }
            $raw = json_encode(["event"=>$online ? "heartbeat" : "offline", "device"=>$device, "platform"=>$platform, "terminal"=>$terminal, "device_flag"=>$device_flag], JSON_UNESCAPED_UNICODE);
            $sql = "INSERT INTO `mr_im_online_status` (`appid`,`uid`,`user_id`,`online`,`last_event`,`last_seen`,`raw_data`,`update_time`,`device`,`platform`,`terminal`,`device_flag`) VALUES (:appid,:uid,:user_id,:online,:last_event,:last_seen,:raw_data,:update_time,:device,:platform,:terminal,:device_flag) ON DUPLICATE KEY UPDATE `online`=VALUES(`online`),`last_event`=VALUES(`last_event`),`last_seen`=VALUES(`last_seen`),`raw_data`=VALUES(`raw_data`),`update_time`=VALUES(`update_time`),`device`=VALUES(`device`),`platform`=VALUES(`platform`),`terminal`=VALUES(`terminal`),`device_flag`=VALUES(`device_flag`)";
            Db::execute($sql, ['appid'=>$this->appid, 'uid'=>$uid, 'user_id'=>intval($user_all_info["id"]), 'online'=>$online ? 1 : 0, 'last_event'=>$online ? 'heartbeat' : 'offline', 'last_seen'=>$online ? null : $now, 'raw_data'=>$raw, 'update_time'=>$now, 'device'=>$device, 'platform'=>$platform, 'terminal'=>$terminal, 'device_flag'=>$device_flag]);
            $this->json(1, "success", ["uid"=>$uid, "online"=>$online, "device"=>$device, "platform"=>$platform, "terminal"=>$terminal, "device_flag"=>$device_flag, "update_time"=>$now]);
        } catch (\Exception $e) {
            $this->json(0, "在线心跳失败：" . $e->getMessage());
        }
    }

'''
if 'public function im_online_heartbeat()' not in s:
    if insert_before not in s:
        raise SystemExit('insert marker not found')
    s = s.replace(insert_before, heartbeat + insert_before, 1)

old = '''        $online = false;
        $online_uids = [];
        $source = "none";
        $api_error = "";
        $device = "";
        $platform = "";
        $terminal = "";
        $device_flag = 0;
'''
new = '''        $online = false;
        $online_uids = [];
        $source = "none";
        $api_error = "";
        $device = "";
        $platform = "";
        $terminal = "";
        $device_flag = 0;
        $ttl_seconds = 45;
        $last_update_time = "";
'''
s = s.replace(old, new, 1)

old2 = '''                    if ($device === "") $device = isset($r['device']) ? strval($r['device']) : "";
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
'''
new2 = '''                    if ($device === "") $device = isset($r['device']) ? strval($r['device']) : "";
                    if ($platform === "") $platform = isset($r['platform']) ? strval($r['platform']) : "";
                    if ($terminal === "") $terminal = isset($r['terminal']) ? strval($r['terminal']) : "";
                    if ($device_flag === 0 && isset($r['device_flag'])) $device_flag = intval($r['device_flag']);
                    if ($last_update_time === "" && isset($r['update_time'])) $last_update_time = strval($r['update_time']);
                    $fresh = isset($r['update_time']) && strtotime($r['update_time']) >= time() - $ttl_seconds;
                    if (intval($r['online']) === 1 && $fresh) {
                        $online = true;
                        $device = isset($r['device']) ? strval($r['device']) : $device;
                        $platform = isset($r['platform']) ? strval($r['platform']) : $platform;
                        $terminal = isset($r['terminal']) ? strval($r['terminal']) : $terminal;
                        $device_flag = isset($r['device_flag']) ? intval($r['device_flag']) : $device_flag;
                        $last_update_time = isset($r['update_time']) ? strval($r['update_time']) : $last_update_time;
                        $source = $source === "wukongim" ? "wukongim+db_heartbeat" : "db_heartbeat";
                        break;
                    }
'''
if old2 not in s:
    raise SystemExit('ttl rows block not found')
s = s.replace(old2, new2, 1)

old3 = '''            "device_flag"=>$device_flag,
            "online_uids"=>$online_uids,
'''
new3 = '''            "device_flag"=>$device_flag,
            "last_update_time"=>$last_update_time,
            "ttl_seconds"=>$ttl_seconds,
            "online_uids"=>$online_uids,
'''
s = s.replace(old3, new3, 1)

p.write_text(s)
print('patched', backup)