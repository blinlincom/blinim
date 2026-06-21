from pathlib import Path

p = Path('/www/wwwroot/blinlin/application/api/controller/traits/ImApiTrait.php')
s = p.read_text()
backup = p.with_suffix('.php.bak_stable_im_connect_token_20260622')
backup.write_text(s)

old = '''        $uid = $this->appid . "_" . $user_all_info["id"];
        $token = md5($uid . "_" . input("usertoken") . "_" . time());
        $device_flag = input("device_flag") === "" ? 0 : intval(input("device_flag"));
'''
new = '''        $uid = $this->appid . "_" . $user_all_info["id"];
        $device_flag = input("device_flag") === "" ? 0 : intval(input("device_flag"));
        $token = md5($uid . "_" . md5(strval(input("usertoken"))) . "_" . $device_flag);
'''
if old not in s:
    raise SystemExit('get_im_connect_info token block not found')

p.write_text(s.replace(old, new, 1))
print('patched stable IM token:', backup)
