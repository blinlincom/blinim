from pathlib import Path
p = Path('/www/wwwroot/blinlin/application/api/controller/Api.php')
s = p.read_text()
backup = p.with_suffix('.php.bak_online_device_sql_20260608')
backup.write_text(s)
old = '''                $exists = Db::name('im_online_status')->where('uid', $uid)->find();
                $save = ['appid'=>$this->appid, 'uid'=>$uid, 'user_id'=>intval($user_all_info["id"]), 'online'=>1, 'last_event'=>'connect_info', 'raw_data'=>$raw, 'update_time'=>$now, 'device'=>$device, 'platform'=>$platform, 'terminal'=>$terminal, 'device_flag'=>$device_flag];
                if ($exists) { Db::name('im_online_status')->where('uid', $uid)->update($save); } else { $save['last_seen'] = null; Db::name('im_online_status')->insert($save); }
            } catch (\\Exception $e) {}
'''
new = '''                $sql = "INSERT INTO `mr_im_online_status` (`appid`,`uid`,`user_id`,`online`,`last_event`,`last_seen`,`raw_data`,`update_time`,`device`,`platform`,`terminal`,`device_flag`) VALUES (:appid,:uid,:user_id,1,'connect_info',NULL,:raw_data,:update_time,:device,:platform,:terminal,:device_flag) ON DUPLICATE KEY UPDATE `online`=1,`last_event`='connect_info',`raw_data`=VALUES(`raw_data`),`update_time`=VALUES(`update_time`),`device`=VALUES(`device`),`platform`=VALUES(`platform`),`terminal`=VALUES(`terminal`),`device_flag`=VALUES(`device_flag`)";
                Db::execute($sql, ['appid'=>$this->appid, 'uid'=>$uid, 'user_id'=>intval($user_all_info["id"]), 'raw_data'=>$raw, 'update_time'=>$now, 'device'=>$device, 'platform'=>$platform, 'terminal'=>$terminal, 'device_flag'=>$device_flag]);
            } catch (\\Exception $e) { $im_online_write_error = $e->getMessage(); }
'''
if old not in s:
    raise SystemExit('connect save block not found')
s = s.replace(old, new, 1)
old2 = '''        try {
                $wkim = new \\app\\common\\tool\\WukongIM();
'''
new2 = '''        $im_online_write_error = "";
        try {
                $wkim = new \\app\\common\\tool\\WukongIM();
'''
s = s.replace(old2, new2, 1)
old3 = '''"terminal"=>$terminal,"route"=>$route,'''
new3 = '''"terminal"=>$terminal,"online_write_error"=>$im_online_write_error,"route"=>$route,'''
if old3 not in s:
    raise SystemExit('connect output marker not found')
s = s.replace(old3, new3, 1)
p.write_text(s)
print('patched', backup)