#!/usr/bin/env python3
"""Patch backend login sessions to allow cross-terminal concurrent login.

Behavior:
  - Same app + same user + same terminal keeps one active token.
  - Different terminals (web/android/ios/desktop) can stay logged in together.
  - App login configuration gets same_terminal_login_policy:
      kick_previous (default) or single_all.
"""
from datetime import datetime
from pathlib import Path


ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"
BASE = ROOT / "application/api/controller/BaseController.php"
ADMIN = ROOT / "application/admin/controller/App.php"
EDIT = ROOT / "application/admin/view/app/edit.html"


def backup(path: Path, suffix: str) -> str:
    target = path.with_name(
        f"{path.name}.bak_{suffix}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    target.write_text(path.read_text(errors="ignore"))
    return str(target)


def replace_once(text: str, old: str, new: str) -> str:
    if old not in text:
        raise SystemExit(f"MARKER_NOT_FOUND:\n{old[:200]}")
    return text.replace(old, new, 1)


def patch_api() -> bool:
    source = API.read_text(errors="ignore")
    original = source

    if "private function blinTerminalKey(" not in source:
        marker = "\n    //获取APP信息\n"
        helper = r'''
    private function blinTerminalKey($data = null)
    {
        if ($data === null) {
            $data = input('');
        }
        $terminal = strtolower(trim(strval(isset($data["terminal"]) ? $data["terminal"] : input("terminal"))));
        $platform = strtolower(trim(strval(isset($data["platform"]) ? $data["platform"] : input("platform"))));
        $device = strtolower(trim(strval(isset($data["device"]) ? $data["device"] : input("device"))));
        $deviceType = strtolower(trim(strval(isset($data["device_type"]) ? $data["device_type"] : input("device_type"))));
        $flag = intval(isset($data["device_flag"]) ? $data["device_flag"] : input("device_flag"));
        $raw = $terminal ?: ($platform ?: ($deviceType ?: $device));
        if ($raw === "web" || $flag === 1) {
            return "web";
        }
        if ($raw === "ios" || $raw === "iphone" || $raw === "ipad" || $flag === 4) {
            return "ios";
        }
        if ($raw === "android" || $raw === "mobile" || $flag === 2) {
            return "android";
        }
        if ($raw === "windows" || $raw === "macos" || $raw === "linux" || $raw === "desktop" || $flag === 3) {
            return "desktop";
        }
        return $raw === "" ? "unknown" : $raw;
    }

    private function blinSaveLoginSession($userId, $token, $terminal, $data = [])
    {
        try {
            Db::execute("CREATE TABLE IF NOT EXISTS `mr_user_login_session` (`id` bigint(20) NOT NULL AUTO_INCREMENT, `appid` bigint(20) NOT NULL DEFAULT 0, `user_id` bigint(20) NOT NULL DEFAULT 0, `terminal` varchar(32) NOT NULL DEFAULT '', `token` varchar(255) NOT NULL DEFAULT '', `platform` varchar(32) NOT NULL DEFAULT '', `device` varchar(64) NOT NULL DEFAULT '', `device_flag` int(11) NOT NULL DEFAULT 0, `login_ip` varchar(45) NOT NULL DEFAULT '', `login_time` int(11) NOT NULL DEFAULT 0, `last_activity_time` int(11) NOT NULL DEFAULT 0, PRIMARY KEY (`id`), UNIQUE KEY `uk_app_user_terminal` (`appid`,`user_id`,`terminal`), UNIQUE KEY `uk_token` (`token`), KEY `idx_user` (`appid`,`user_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8;");
        } catch (\Exception $e) {}
        $policy = isset($this->app_info["login_configuration"]["same_terminal_login_policy"]) ? $this->app_info["login_configuration"]["same_terminal_login_policy"] : "kick_previous";
        $row = [
            "appid" => intval($this->appid),
            "user_id" => intval($userId),
            "terminal" => $terminal,
            "token" => $token,
            "platform" => strtolower(trim(strval(isset($data["platform"]) ? $data["platform"] : input("platform")))),
            "device" => strtolower(trim(strval(isset($data["device"]) ? $data["device"] : input("device")))),
            "device_flag" => intval(isset($data["device_flag"]) ? $data["device_flag"] : input("device_flag")),
            "login_ip" => get_client_ip(),
            "login_time" => time(),
            "last_activity_time" => time(),
        ];
        if ($policy === "single_all") {
            Db::name("user_login_session")->where("appid", $this->appid)->where("user_id", intval($userId))->delete();
        }
        $exists = Db::name("user_login_session")->where("appid", $this->appid)->where("user_id", intval($userId))->where("terminal", $terminal)->find();
        if ($exists) {
            Db::name("user_login_session")->where("id", $exists["id"])->update($row);
        } else {
            Db::name("user_login_session")->insert($row);
        }
    }

'''
        source = source.replace(marker, "\n" + helper + marker, 1)

    session_data = (
        '                $terminal_data = input(\'\');\n'
        '                $terminal_key = $this->blinTerminalKey($terminal_data);\n'
    )
    session_data_12 = (
        '            $terminal_data = input(\'\');\n'
        '            $terminal_key = $this->blinTerminalKey($terminal_data);\n'
    )
    replacements = [
        (
            '                $update_user_info["usertoken"] = $usertoken;\n'
            '                Db::name("user")->where("id", $user_info["id"])->update($update_user_info);',
            '                $update_user_info["usertoken"] = $usertoken;\n'
            + session_data
            + '                $this->blinSaveLoginSession($user_info["id"], $usertoken, $terminal_key, $terminal_data);\n'
            '                Db::name("user")->where("id", $user_info["id"])->update($update_user_info);',
        ),
        (
            '                $update_user_info["usertoken"] = $usertoken;\n'
            '                Db::name("user")->where("id", $user_id)->update($update_user_info);',
            '                $update_user_info["usertoken"] = $usertoken;\n'
            + session_data
            + '                $this->blinSaveLoginSession($user_id, $usertoken, $terminal_key, $terminal_data);\n'
            '                Db::name("user")->where("id", $user_id)->update($update_user_info);',
        ),
        (
            '        $update_user_info["usertoken"] = $usertoken;\n'
            '        Db::name("user")->where("id", $user_id)->update($update_user_info);',
            '        $update_user_info["usertoken"] = $usertoken;\n'
            '        $terminal_data = input(\'\');\n'
            '        $terminal_key = $this->blinTerminalKey($terminal_data);\n'
            '        $this->blinSaveLoginSession($user_id, $usertoken, $terminal_key, $terminal_data);\n'
            '        Db::name("user")->where("id", $user_id)->update($update_user_info);',
        ),
        (
            '            $update_user_info["usertoken"] = $usertoken;\n'
            '            Db::name("user")->where("id", $user_info["id"])->update($update_user_info);',
            '            $update_user_info["usertoken"] = $usertoken;\n'
            + session_data_12
            + '            $this->blinSaveLoginSession($user_info["id"], $usertoken, $terminal_key, $terminal_data);\n'
            '            Db::name("user")->where("id", $user_info["id"])->update($update_user_info);',
        ),
        (
            '            $update_user_info["usertoken"] = $usertoken;\n'
            '            Db::name("user")->where("id", $user_id)->update($update_user_info);',
            '            $update_user_info["usertoken"] = $usertoken;\n'
            + session_data_12
            + '            $this->blinSaveLoginSession($user_id, $usertoken, $terminal_key, $terminal_data);\n'
            '            Db::name("user")->where("id", $user_id)->update($update_user_info);',
        ),
    ]
    for old, new in replacements:
        source = source.replace(old, new)

    logout_marker = '        Db::name("online_record")->where("token", $usertoken)->update([\'token\' => ""]);\n'
    if logout_marker in source and "user_login_session" not in source[source.find(logout_marker):source.find(logout_marker) + 300]:
        source = source.replace(
            logout_marker,
            logout_marker
            + '        try {\n'
            + '            Db::name("user_login_session")->where("appid", $this->appid)->where("token", $usertoken)->delete();\n'
            + '        } catch (\\Exception $e) {}\n',
            1,
        )

    if source == original:
        return False
    print("PATCH_API_BACKUP", backup(API, "terminal_login_api"))
    API.write_text(source)
    return True


def patch_base() -> bool:
    source = BASE.read_text(errors="ignore")
    original = source

    if "private function blinTerminalKey(" not in source:
        marker = "\n    //获取APP信息\n"
        helper = r'''
    private function blinTerminalKey()
    {
        $terminal = strtolower(trim(strval(input("terminal") ?: "")));
        $platform = strtolower(trim(strval(input("platform") ?: "")));
        $device = strtolower(trim(strval(input("device") ?: "")));
        $deviceType = strtolower(trim(strval(input("device_type") ?: "")));
        $flag = intval(input("device_flag"));
        $raw = $terminal ?: ($platform ?: ($deviceType ?: $device));
        if ($raw === "web" || $flag === 1) return "web";
        if ($raw === "ios" || $raw === "iphone" || $raw === "ipad" || $flag === 4) return "ios";
        if ($raw === "android" || $raw === "mobile" || $flag === 2) return "android";
        if ($raw === "windows" || $raw === "macos" || $raw === "linux" || $raw === "desktop" || $flag === 3) return "desktop";
        return $raw === "" ? "unknown" : $raw;
    }

'''
        source = source.replace(marker, "\n" + helper + marker, 1)

    old = r'''        //查询当前用户token是否存在
        $user_info = Db::name('user')->where("appid", $this->appid)->where("usertoken='{$usertoken}'")->find();
        if (!$user_info) {
            $this->json(401, "未登录");
        }'''
    new = r'''        //查询当前用户token是否存在。优先使用按终端保存的会话表，兼容旧的 mr_user.usertoken。
        $terminal = $this->blinTerminalKey();
        $session = null;
        try {
            $session = Db::name("user_login_session")->where("appid", $this->appid)->where("token", $usertoken)->find();
        } catch (\Exception $e) {
            $session = null;
        }
        if ($session) {
            if ($terminal !== "unknown" && isset($session["terminal"]) && $session["terminal"] !== "" && $session["terminal"] !== $terminal) {
                $this->json(401, "登录已在其他同端设备上失效，请重新登录");
            }
            $user_info = Db::name('user')->where("appid", $this->appid)->where("id", intval($session["user_id"]))->find();
            if (!$user_info) {
                $this->json(401, "未登录");
            }
            try {
                Db::name("user_login_session")->where("id", $session["id"])->update(["last_activity_time" => time()]);
            } catch (\Exception $e) {}
        } else {
            $user_info = Db::name('user')->where("appid", $this->appid)->where("usertoken='{$usertoken}'")->find();
            if (!$user_info) {
                $this->json(401, "登录已失效，请重新登录");
            }
        }'''
    if old in source:
        source = source.replace(old, new, 1)

    if source == original:
        return False
    print("PATCH_BASE_BACKUP", backup(BASE, "terminal_login_base"))
    BASE.write_text(source)
    return True


def patch_admin() -> bool:
    changed = False
    source = ADMIN.read_text(errors="ignore")
    original = source
    source = source.replace(
        '"login_configuration" => \'{"login_switch":"0","login_closing_prompt":"","login_code_switch":"0","new_device_login_switch":"0","remote_login":"1"}\',',
        '"login_configuration" => \'{"login_switch":"0","login_closing_prompt":"","login_code_switch":"0","new_device_login_switch":"0","remote_login":"1","same_terminal_login_policy":"kick_previous"}\',',
    )
    old = '                "remote_login" => $data["remote_login"]\n'
    if old in source and 'same_terminal_login_policy' not in source[source.find(old) - 300 : source.find(old) + 300]:
        source = source.replace(
            old,
            old.rstrip()
            + ',\n'
            + '                "same_terminal_login_policy" => isset($data["same_terminal_login_policy"]) ? $data["same_terminal_login_policy"] : "kick_previous"\n',
            1,
        )
    decode_marker = '                $result["login_configuration"] = json_decode($result["login_configuration"], true);\n'
    if decode_marker in source and 'same_terminal_login_policy"] = "kick_previous"' not in source:
        source = source.replace(
            decode_marker,
            decode_marker
            + '                if (!isset($result["login_configuration"]["same_terminal_login_policy"])) {\n'
            + '                    $result["login_configuration"]["same_terminal_login_policy"] = "kick_previous";\n'
            + '                }\n',
            1,
        )
    if source != original:
        print("PATCH_ADMIN_BACKUP", backup(ADMIN, "terminal_login_admin"))
        ADMIN.write_text(source)
        changed = True

    view = EDIT.read_text(errors="ignore")
    original_view = view
    if "same_terminal_login_policy" not in view:
        marker = '''                                    <div class="col-md-4">
                                        <label for="remote_login" class="form-label">异地登录发送邮件</label>
                                        <select class="form-control" name="remote_login">
                                            <option value="0" {if $data.login_configuration.remote_login==0} selected {/if}>开启</option>
                                            <option value="1" {if $data.login_configuration.remote_login==1} selected {/if}>关闭</option>
                                        </select>
                                    </div>'''
        addition = marker + r'''
                                    <div class="col-md-4">
                                        <label for="same_terminal_login_policy" class="form-label">同端登录策略</label>
                                        <select class="form-control" name="same_terminal_login_policy">
                                            <option value="kick_previous" {if $data.login_configuration.same_terminal_login_policy=='kick_previous'} selected {/if}>跨端共存，同端互踢</option>
                                            <option value="single_all" {if $data.login_configuration.same_terminal_login_policy=='single_all'} selected {/if}>全端单登</option>
                                        </select>
                                        <small>默认 Web、安卓、iOS 可同时在线；同一端再次登录会踢掉旧设备。</small>
                                    </div>'''
        view = replace_once(view, marker, addition)
    if view != original_view:
        print("PATCH_EDIT_BACKUP", backup(EDIT, "terminal_login_view"))
        EDIT.write_text(view)
        changed = True
    return changed


changed_api = patch_api()
changed_base = patch_base()
changed_admin = patch_admin()
changed_any = changed_api or changed_base or changed_admin
print("PATCHED_TERMINAL_LOGIN" if changed_any else "TERMINAL_LOGIN_ALREADY_UP_TO_DATE")
