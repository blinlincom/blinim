#!/usr/bin/env python3
"""Patch username search, display policy, random register profile and rename API."""

from datetime import datetime
from pathlib import Path
import os
import re
import shutil
import subprocess


ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"
APP = ROOT / "application/admin/controller/App.php"
APP_EDIT = ROOT / "application/admin/view/app/edit.html"


def backup(path: Path, suffix: str) -> None:
    target = path.with_name(
        f"{path.name}.bak_{suffix}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    shutil.copy2(path, target)
    print("BACKUP", target)


def save(path: Path, original: str, source: str, suffix: str) -> bool:
    if source == original:
        print("NO_CHANGE", path)
        return False
    backup(path, suffix)
    path.write_text(source)
    print("PATCHED", path)
    return True


def replace_once(source: str, old: str, new: str, label: str) -> str:
    if old not in source:
        raise SystemExit(f"{label}_MARKER_NOT_FOUND")
    return source.replace(old, new, 1)


def db_config():
    values = {
        "hostname": "127.0.0.1",
        "database": "blinlin",
        "username": "root",
        "password": "",
        "hostport": "3306",
    }
    env_path = ROOT / ".env"
    section = ""
    if not env_path.exists():
        return values
    for raw in env_path.read_text(errors="ignore").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith(";"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip().lower()
            continue
        if section != "database" or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip().lower()
        value = value.strip().strip('"').strip("'")
        if key in values:
            values[key] = value
    return values


def mysql(sql: str, ignore=()):
    config = db_config()
    env = os.environ.copy()
    env["MYSQL_PWD"] = config["password"]
    result = subprocess.run(
        [
            "mysql",
            f"-h{config['hostname']}",
            f"-u{config['username']}",
            f"-P{config.get('hostport') or '3306'}",
            config["database"],
            "-e",
            sql,
        ],
        universal_newlines=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        check=False,
    )
    if result.returncode != 0:
        err = result.stderr.strip()
        if any(item in err for item in ignore):
            print("MYSQL_IGNORE", err)
            return ""
        raise SystemExit(err)
    if result.stdout.strip():
        print(result.stdout.strip())
    return result.stdout


def patch_database():
    mysql(
        "ALTER TABLE `mr_user` ADD COLUMN `username_updated_at` datetime DEFAULT NULL",
        ("Duplicate column name",),
    )
    mysql(
        """UPDATE `mr_app`
SET `userinfo_configuration` = JSON_SET(
  COALESCE(NULLIF(`userinfo_configuration`, ''), '{}'),
  '$.show_user_id_switch',
  COALESCE(JSON_UNQUOTE(JSON_EXTRACT(COALESCE(NULLIF(`userinfo_configuration`, ''), '{}'), '$.show_user_id_switch')), '1'),
  '$.username_change_switch',
  COALESCE(JSON_UNQUOTE(JSON_EXTRACT(COALESCE(NULLIF(`userinfo_configuration`, ''), '{}'), '$.username_change_switch')), '0'),
  '$.username_change_interval_days',
  COALESCE(JSON_UNQUOTE(JSON_EXTRACT(COALESCE(NULLIF(`userinfo_configuration`, ''), '{}'), '$.username_change_interval_days')), '30')
)
WHERE JSON_VALID(COALESCE(NULLIF(`userinfo_configuration`, ''), '{}')) = 1"""
    )


API_HELPERS = r'''
    // blin-username-policy
    private function blinUserInfoConfig($key = null, $default = null)
    {
        $config = isset($this->app_info["userinfo_configuration"]) && is_array($this->app_info["userinfo_configuration"]) ? $this->app_info["userinfo_configuration"] : [];
        $defaults = [
            "show_user_id_switch" => 1,
            "username_change_switch" => 0,
            "username_change_interval_days" => 30,
        ];
        $config = array_merge($defaults, $config);
        if ($key === null) return $config;
        return isset($config[$key]) ? $config[$key] : $default;
    }

    private function blinValidUsername($username)
    {
        return preg_match('/^[A-Za-z0-9]{4,8}$/', strval($username)) === 1;
    }

    private function blinGenerateUsername()
    {
        $letters = "abcdefghijklmnopqrstuvwxyz";
        for ($i = 0; $i < 30; $i++) {
            $prefix = "";
            for ($j = 0; $j < 2; $j++) {
                $prefix .= $letters[mt_rand(0, strlen($letters) - 1)];
            }
            $suffix = "";
            $suffixLength = mt_rand(2, 6);
            for ($j = 0; $j < $suffixLength; $j++) {
                $suffix .= mt_rand(0, 9);
            }
            $username = substr($prefix . $suffix, 0, 8);
            if (!$this->blinValidUsername($username)) {
                continue;
            }
            $exists = Db::name("user")->where("appid", $this->appid)->where("username", $username)->find();
            if (!$exists) {
                return $username;
            }
        }
        do {
            $username = substr("u" . substr(strval(time()), -5) . mt_rand(10, 99), 0, 8);
        } while (Db::name("user")->where("appid", $this->appid)->where("username", $username)->find());
        return $username;
    }

    private function blinRandomNickname()
    {
        $prefix = ["星河", "微光", "初见", "清风", "云端", "晴川", "松果", "南星", "青柠", "白昼"];
        $suffix = ["来信", "旅人", "同学", "朋友", "行者", "小站", "回声", "拾光", "信号", "坐标"];
        return $prefix[array_rand($prefix)] . $suffix[array_rand($suffix)] . mt_rand(10, 99);
    }

    private function blinRandomAvatar()
    {
        $files = ["user.png", "android.png"];
        $file = $files[array_rand($files)];
        $color = substr(md5(uniqid("", true) . mt_rand()), 0, 6);
        if ($file === "user.png") {
            return request()->domain() . "/static/images/initial_photo/user.png?v=" . $color;
        }
        return request()->domain() . "/static/images/initial_photo/android.png?v=" . $color;
    }
'''


def patch_api_controller():
    source = API.read_text(errors="ignore")
    original = source

    if "private function blinUserInfoConfig(" not in source:
        source = replace_once(
            source,
            "    //获取APP信息\n    public function get_app_info()",
            API_HELPERS + "\n    //获取APP信息\n    public function get_app_info()",
            "api_helpers",
        )

    source = source.replace('/^[A-Za-z0-9]{1,8}$/', '/^[A-Za-z0-9]{4,8}$/')
    source = source.replace("1-8位英文或数字", "4-8位英文或数字")
    source = source.replace("最多8位", "4到8位")

    if "private function blinGenerateUsername(" not in source:
        valid_helper = '''    private function blinValidUsername($username)
    {
        return preg_match('/^[A-Za-z0-9]{4,8}$/', strval($username)) === 1;
    }
'''
        generate_helper = '''    private function blinGenerateUsername()
    {
        $letters = "abcdefghijklmnopqrstuvwxyz";
        for ($i = 0; $i < 30; $i++) {
            $prefix = "";
            for ($j = 0; $j < 2; $j++) {
                $prefix .= $letters[mt_rand(0, strlen($letters) - 1)];
            }
            $suffix = "";
            $suffixLength = mt_rand(2, 6);
            for ($j = 0; $j < $suffixLength; $j++) {
                $suffix .= mt_rand(0, 9);
            }
            $username = substr($prefix . $suffix, 0, 8);
            if (!$this->blinValidUsername($username)) {
                continue;
            }
            $exists = Db::name("user")->where("appid", $this->appid)->where("username", $username)->find();
            if (!$exists) {
                return $username;
            }
        }
        do {
            $username = substr("u" . substr(strval(time()), -5) . mt_rand(10, 99), 0, 8);
        } while (Db::name("user")->where("appid", $this->appid)->where("username", $username)->find());
        return $username;
    }
'''
        source = replace_once(
            source,
            valid_helper,
            valid_helper + "\n" + generate_helper,
            "generate_username_helper",
        )

    if '$result["userinfo_configuration"] = $this->app_info["userinfo_configuration"];' not in source:
        source = replace_once(
            source,
            '''        $result["security_configuration"] = $this->app_info["security_configuration"];
        $result["im_configuration"] = $this->app_info["im_configuration"];''',
            '''        $result["security_configuration"] = $this->app_info["security_configuration"];
        $result["userinfo_configuration"] = $this->app_info["userinfo_configuration"];
        $result["im_configuration"] = $this->app_info["im_configuration"];''',
            "app_info_userinfo_config",
        )

    source = source.replace(
        "'username|用户名' => 'require|min:5',\n            'password|密码' => 'require|min:5',",
        "'username|用户名' => 'require',\n            'password|密码' => 'require|min:5',",
    )
    source = source.replace(
        "'username|用户名' => 'require|min:5',",
        "'username|用户名' => 'require',",
    )
    source = source.replace(
        "'username|用户名' => 'require|min:4',\n            'password|密码' => 'require|min:4',",
        "'username|用户名' => 'require',\n            'password|密码' => 'require|min:4',",
        1,
    )
    source, _ = re.subn(
        r"(    //用户注册\n    public function register\(\)\n    \{.*?        \$data = input\(''\);\n        \$rule = \[\n)            'username\|用户名' => 'require',\n(            'password\|密码' => 'require\|min:5',\n        \];)",
        r"\1\2",
        source,
        count=1,
        flags=re.S,
    )
    login_start = source.find("    public function login()")
    login_captcha = source.find("        //判断是否开启图片验证码", login_start)
    if login_start >= 0 and login_captcha > login_start:
        login_validate_segment = source[login_start:login_captcha]
        if "blinValidUsername($username)" not in login_validate_segment:
            source, count = re.subn(
                r"(    public function login\(\)\n    \{.*?        if \(!\$validate->check\(\$data\)\) \{\n            \$this->json\(0, \$validate->getError\(\)\);\n        \}\n)(        //判断是否开启图片验证码)",
                lambda m: m.group(1) + '''        $username = trim(strval($username));
        if (!$this->blinValidUsername($username)) {
            $this->json(0, "用户名只能使用4-8位英文或数字");
        }
''' + m.group(2),
                source,
                count=1,
                flags=re.S,
            )
            if count == 0:
                raise SystemExit("login_username_validate_MARKER_NOT_FOUND")
    else:
        raise SystemExit("login_username_validate_RANGE_NOT_FOUND")
    register_validate = '''        $username = trim(strval($username));
        $useGeneratedUsername = intval($this->app_info["registration_configuration"]["registration_code_switch"]) === 3 && $username === "";
        if ($useGeneratedUsername) {
            $username = $this->blinGenerateUsername();
        } elseif (!$this->blinValidUsername($username)) {
            $this->json(0, "用户名只能使用4-8位英文或数字");
        }
        $add = [];'''
    old_register_validate = '''        $username = trim(strval($username));
        if (!$this->blinValidUsername($username)) {
            $this->json(0, "用户名只能使用4-8位英文或数字");
        }
        $add = [];'''
    if old_register_validate in source:
        source = source.replace(old_register_validate, register_validate, 1)
    elif register_validate not in source:
        source = replace_once(
            source,
            '''        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $add = [];''',
            '''        if (!$result) {
            $this->json(0, $validate->getError());
        }
        $username = trim(strval($username));
        $useGeneratedUsername = intval($this->app_info["registration_configuration"]["registration_code_switch"]) === 3 && $username === "";
        if ($useGeneratedUsername) {
            $username = $this->blinGenerateUsername();
        } elseif (!$this->blinValidUsername($username)) {
            $this->json(0, "用户名只能使用4-8位英文或数字");
        }
        $add = [];''',
            "register_username_validate",
        )

    source = source.replace(
        '$add["usertx"] = $userinfo_configuration[\'usertx\'];',
        '$add["usertx"] = $this->blinRandomAvatar();',
    )
    source = source.replace(
        '$add["nickname"] = $userinfo_configuration[\'nickname\'];',
        '$add["nickname"] = $this->blinRandomNickname();',
    )
    source = source.replace('$add["usertx"] = $Response["figureurl_qq"];', '$add["usertx"] = $this->blinRandomAvatar();')
    source = source.replace('$add["nickname"] = $Response["nickname"];', '$add["nickname"] = $this->blinRandomNickname();')
    source = source.replace('$username = enerate_username();', '$username = $this->blinGenerateUsername();')

    email_retrieve_marker = '''                if (!$result) {
                    throw new \\Exception((string)$validate->getError());
                }
                $email_info = Db::name('user')->where("appid", $this->appid)->where("username='{$username}'")->find();'''
    if email_retrieve_marker in source:
        source = source.replace(
            email_retrieve_marker,
            '''                if (!$result) {
                    throw new \\Exception((string)$validate->getError());
                }
                $username = trim(strval($username));
                if (!$this->blinValidUsername($username)) {
                    throw new \\Exception("用户名只能使用4-8位英文或数字");
                }
                $email_info = Db::name('user')->where("appid", $this->appid)->where("username='{$username}'")->find();''',
            1,
        )

    retrieve_start = source.find("    public function retrieve_password()")
    retrieve_end = source.find("    //上传头像", retrieve_start)
    if retrieve_start >= 0 and retrieve_end > retrieve_start and "blinValidUsername($username)" not in source[retrieve_start:retrieve_end]:
        source, count = re.subn(
            r"(    public function retrieve_password\(\)\n    \{.*?        if \(!\$result\) \{\n            \$this->json\(0, \$validate->getError\(\)\);\n        \}\n)(        \$type = input\(\"type\"\);)",
            lambda m: m.group(1) + '''        $username = trim(strval($username));
        if (!$this->blinValidUsername($username)) {
            $this->json(0, "用户名只能使用4-8位英文或数字");
        }
''' + m.group(2),
            source,
            count=1,
            flags=re.S,
        )
        if count == 0:
            raise SystemExit("retrieve_password_username_validate_marker_not_found")

    if 'public function change_username()' not in source:
        source = replace_once(
            source,
            '''        Db::name("user")->where("id", $user_all_info["id"])->update($update_user_info);
        $this->json(1, "修改成功");
    }

    //修改用户邮箱
    public function modify_user_email()''',
            '''        Db::name("user")->where("id", $user_all_info["id"])->update($update_user_info);
        $this->json(1, "修改成功");
    }

    public function change_username()
    {
        $data = input('');
        $rule = [
            'usertoken|用户token' => 'require',
            'username|用户名' => 'require',
        ];
        $validate = new Validate($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $user = $this->user_info;
        $username = trim(strval($data["username"]));
        if (!$this->blinValidUsername($username)) {
            $this->json(0, "用户名只能使用4-8位英文或数字");
        }
        if (intval($this->blinUserInfoConfig("username_change_switch", 0)) === 1) {
            $this->json(0, "当前应用暂不允许修改用户名");
        }
        if ($username === strval($user["username"])) {
            $this->json(1, "用户名未变化", ["username" => $username]);
        }
        $exists = Db::name("user")->where("appid", $this->appid)->where("username", $username)->where("id", "<>", intval($user["id"]))->find();
        if ($exists) {
            $this->json(0, "用户名已存在");
        }
        $days = max(0, intval($this->blinUserInfoConfig("username_change_interval_days", 30)));
        $lastRaw = isset($user["username_updated_at"]) ? strval($user["username_updated_at"]) : "";
        $last = $lastRaw === "" || $lastRaw === "0000-00-00 00:00:00" ? 0 : strtotime($lastRaw);
        if ($days > 0 && $last > 0) {
            $next = $last + $days * 86400;
            if (time() < $next) {
                $remain = max(1, ceil(($next - time()) / 86400));
                $this->json(0, "用户名还需{$remain}天后才能再次修改");
            }
        }
        $now = date("Y-m-d H:i:s");
        Db::name("user")->where("appid", $this->appid)->where("id", intval($user["id"]))->update([
            "username" => $username,
            "username_updated_at" => $now,
        ]);
        $this->json(1, "用户名修改成功", ["username" => $username, "username_updated_at" => $now]);
    }

    public function update_username(){ return $this->change_username(); }

    //修改用户邮箱
    public function modify_user_email()''',
            "change_username_api",
        )

    new_search = r'''    //搜索用户接口
    public function search_user()
    {
        $username = trim(strval(input("username") ?: input("search") ?: input("keyword")));
        if (!$this->blinValidUsername($username)) {
            $this->json(0, "只能搜索4-8位英文或数字用户名");
        }
        $query = Db::name("user")
            ->where("appid", $this->appid)
            ->where("username", "like", "%" . $username . "%");
        $result = $query
            ->field("id,username,nickname,usertx,title")
            ->limit($this->limit)
            ->page($this->page)
            ->select();
        foreach ($result as $key => $value) {
            $result[$key]["title"] = array_filter(explode(",", $value["title"]));
            $result[$key]["show_user_id"] = intval($this->blinUserInfoConfig("show_user_id_switch", 1)) === 0 ? 1 : 0;
            $result[$key]["badge"] = Db::name("polymorphic")
                ->alias("p")
                ->join("bagge b", "b.id=p.other_id")
                ->where("p.userid", $value["id"])
                ->where("p.type", 5)
                ->where("b.is_view", 0)
                ->where("p.wearing", 0)
                ->order(["b.type" => $this->medal_sorting, "b.sort" => "desc"])
                ->field("b.id,b.name,b.icon,case when p.expiration_time = '9999' then '永久' else p.expiration_time end as expiration_time")
                ->select();
        }
        $pagecount = Db::name("user")
            ->where("appid", $this->appid)
            ->where("username", "like", "%" . $username . "%")
            ->count();
        $data_rs["list"] = $result;
        $data_rs["show_user_id"] = intval($this->blinUserInfoConfig("show_user_id_switch", 1)) === 0 ? 1 : 0;
        $data_rs["pagecount"] = ceil($pagecount / $this->limit) == 0 ? 1 : ceil($pagecount / $this->limit);
        $data_rs["current_number"] = $this->page;
        $this->json(1, "success", $data_rs);
    }
'''
    source, count = re.subn(
        r"    //搜索用户接口\n    public function search_user\(\)\n    \{.*?\n    \}\n\n\n\n\n\n\n    // blin-im-group-api:",
        new_search + "\n\n\n\n\n\n    // blin-im-group-api:",
        source,
        count=1,
        flags=re.S,
    )
    if count == 0:
        raise SystemExit("search_user_block_not_found")

    save(API, original, source, "username_policy")


def patch_app_controller():
    source = APP.read_text(errors="ignore")
    original = source

    source = source.replace(
        '"title_medal_priority":"0"}',
        '"title_medal_priority":"0","show_user_id_switch":"1","username_change_switch":"0","username_change_interval_days":"30"}',
        1,
    )

    if '"show_user_id_switch" => isset($data["show_user_id_switch"])' not in source:
        source = replace_once(
            source,
            '''                "update_userinfo_audit" => isset($data["update_userinfo_audit"]) ? intval($data["update_userinfo_audit"]) : 1,
                "title_medal_priority" => $data["title_medal_priority"],
            ];''',
            '''                "update_userinfo_audit" => isset($data["update_userinfo_audit"]) ? intval($data["update_userinfo_audit"]) : 1,
                "title_medal_priority" => $data["title_medal_priority"],
                "show_user_id_switch" => isset($data["show_user_id_switch"]) ? intval($data["show_user_id_switch"]) : 1,
                "username_change_switch" => isset($data["username_change_switch"]) ? intval($data["username_change_switch"]) : 1,
                "username_change_interval_days" => max(0, intval(isset($data["username_change_interval_days"]) ? $data["username_change_interval_days"] : 30)),
            ];''',
            "userinfo_save_config",
        )

    if '"show_user_id_switch" => 1,' not in source:
        source = replace_once(
            source,
            '''                if (!isset($result["userinfo_configuration"]["title_medal_priority"])) {
                    $result["userinfo_configuration"]["title_medal_priority"] = 0;
                }''',
            '''                $userInfoDefaults = [
                    "show_user_id_switch" => 1,
                    "username_change_switch" => 0,
                    "username_change_interval_days" => 30,
                    "title_medal_priority" => 0,
                ];
                $result["userinfo_configuration"] = array_merge($userInfoDefaults, $result["userinfo_configuration"]);
                if (!isset($result["userinfo_configuration"]["title_medal_priority"])) {
                    $result["userinfo_configuration"]["title_medal_priority"] = 0;
                }''',
            "userinfo_defaults",
        )

    save(APP, original, source, "username_policy")


def patch_app_edit_view():
    source = APP_EDIT.read_text(errors="ignore")
    original = source
    source = source.replace("最多8位", "4到8位")

    if 'name="show_user_id_switch"' not in source:
        source = replace_once(
            source,
            '''                            <div class="col-md-12">
                                <label for="title_medal_priority" class="form-label">称号勋章优先输出配置</label>
                                <select class="form-control" name="title_medal_priority">
                                    <option value="0" {if $data.userinfo_configuration.title_medal_priority==0} selected {/if}>勋章优先输出</option>
                                    <option value="1" {if $data.userinfo_configuration.title_medal_priority==1} selected {/if}>称号优先输出</option>
                                </select>
                            </div>''',
            '''                            <div class="col-md-12">
                                <div class="blin-setting-row blin-user-id-switch-card">
                                    <div class="blin-setting-copy">
                                        <span class="blin-setting-title">显示用户ID</span>
                                        <small class="blin-setting-desc">默认关闭。关闭后客户端只展示用户名，数字ID仅用于内部接口。</small>
                                    </div>
                                    <div class="blin-segmented-switch" role="group" aria-label="显示用户ID">
                                        <input type="radio" id="show_user_id_on" value="0" name="show_user_id_switch" class="btn-check" autocomplete="off" {if $data.userinfo_configuration.show_user_id_switch==0} checked {/if}>
                                        <label class="blin-switch-choice blin-switch-choice-on" for="show_user_id_on"><i class="mdi mdi-check-circle-outline"></i>开启</label>
                                        <input type="radio" id="show_user_id_off" value="1" name="show_user_id_switch" class="btn-check" autocomplete="off" {if $data.userinfo_configuration.show_user_id_switch==1} checked {/if}>
                                        <label class="blin-switch-choice blin-switch-choice-off" for="show_user_id_off"><i class="mdi mdi-close-circle-outline"></i>关闭</label>
                                    </div>
                                </div>
                            </div>
                            <div class="col-md-12">
                                <div class="blin-setting-row blin-username-change-switch-card">
                                    <div class="blin-setting-copy">
                                        <span class="blin-setting-title">允许修改用户名</span>
                                        <small class="blin-setting-desc">开启后用户可在客户端修改用户名。用户名仅支持英文和数字，4到8位。</small>
                                    </div>
                                    <div class="blin-segmented-switch" role="group" aria-label="允许修改用户名">
                                        <input type="radio" id="username_change_on" value="0" name="username_change_switch" class="btn-check" autocomplete="off" {if $data.userinfo_configuration.username_change_switch==0} checked {/if}>
                                        <label class="blin-switch-choice blin-switch-choice-on" for="username_change_on"><i class="mdi mdi-check-circle-outline"></i>开启</label>
                                        <input type="radio" id="username_change_off" value="1" name="username_change_switch" class="btn-check" autocomplete="off" {if $data.userinfo_configuration.username_change_switch==1} checked {/if}>
                                        <label class="blin-switch-choice blin-switch-choice-off" for="username_change_off"><i class="mdi mdi-close-circle-outline"></i>关闭</label>
                                    </div>
                                </div>
                            </div>
                            <div class="col-md-6">
                                <label class="form-label">用户名修改间隔（天）</label>
                                <input type="number" min="0" class="form-control" name="username_change_interval_days" value="{$data.userinfo_configuration.username_change_interval_days}" placeholder="30">
                                <small class="blin-setting-desc">设置 0 表示不限制修改间隔。</small>
                            </div>
                            <div class="col-md-12">
                                <label for="title_medal_priority" class="form-label">称号勋章优先输出配置</label>
                                <select class="form-control" name="title_medal_priority">
                                    <option value="0" {if $data.userinfo_configuration.title_medal_priority==0} selected {/if}>勋章优先输出</option>
                                    <option value="1" {if $data.userinfo_configuration.title_medal_priority==1} selected {/if}>称号优先输出</option>
                                </select>
                            </div>''',
            "userinfo_policy_view",
        )

    save(APP_EDIT, original, source, "username_policy")


def main():
    patch_database()
    patch_api_controller()
    patch_app_controller()
    patch_app_edit_view()


if __name__ == "__main__":
    main()
