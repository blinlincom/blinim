#!/usr/bin/env python3
"""Add wallet payment password protection and admin reset action."""

from datetime import datetime
from pathlib import Path
import os
import re
import shutil
import subprocess


ROOT = Path(os.environ.get("BLIN_ROOT", "/www/wwwroot/blinlin"))
API = ROOT / "application/api/controller/Api.php"
USER = ROOT / "application/admin/controller/User.php"
USER_INDEX = ROOT / "application/admin/view/user/index.html"


def backup(path, suffix):
    stamp = datetime.now().strftime("%Y%m%d%H%M%S")
    shutil.copy2(path, path.with_name(f"{path.name}.bak_{suffix}_{stamp}"))


def read(path):
    return path.read_text(encoding="utf-8", errors="ignore")


def write_if_changed(path, before, after, suffix):
    if before == after:
        return False
    backup(path, suffix)
    path.write_text(after, encoding="utf-8")
    print("PATCHED", path)
    return True


def replace_once(text, old, new, label):
    if new in text:
        return text
    if old not in text:
        raise RuntimeError(f"missing anchor: {label}")
    return text.replace(old, new, 1)


def insert_before(text, marker, block, label):
    if block.strip() in text:
        return text
    pos = text.find(marker)
    if pos < 0:
        raise RuntimeError(f"missing marker: {label}")
    return text[:pos] + block + text[pos:]


def insert_before_last_class_brace(text, block, label):
    if block.strip() in text:
        return text
    pos = text.rfind("\n}")
    if pos < 0:
        raise RuntimeError(f"missing class end: {label}")
    return text[:pos] + "\n" + block + text[pos:]


def method_slice(text, signature):
    start = text.find(signature)
    if start < 0:
        raise RuntimeError(f"missing method: {signature}")
    brace = text.find("{", start)
    if brace < 0:
        raise RuntimeError(f"missing method brace: {signature}")
    depth = 0
    for i in range(brace, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return start, i + 1
    raise RuntimeError(f"missing method end: {signature}")


def replace_in_method(text, signature, old, new, label):
    start, end = method_slice(text, signature)
    body = text[start:end]
    if new in body:
        return text
    if old not in body:
        raise RuntimeError(f"missing method anchor: {label}")
    body = body.replace(old, new, 1)
    return text[:start] + body + text[end:]


def db_config():
    values = {
        "hostname": "127.0.0.1",
        "database": "blinlin",
        "username": "root",
        "password": "",
        "hostport": "3306",
        "prefix": "mr_",
    }
    env_path = ROOT / ".env"
    if not env_path.exists():
        return values
    section = ""
    for raw in env_path.read_text(encoding="utf-8", errors="ignore").splitlines():
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


def mysql(sql):
    config = db_config()
    env = os.environ.copy()
    env["MYSQL_PWD"] = config["password"]
    return subprocess.run(
        [
            "mysql",
            f"-h{config.get('hostname') or '127.0.0.1'}",
            f"-u{config.get('username') or 'root'}",
            f"-P{config.get('hostport') or '3306'}",
            config.get("database") or "blinlin",
            "-Nse",
            sql,
        ],
        universal_newlines=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        check=False,
    )


def patch_database():
    config = db_config()
    prefix = config.get("prefix", "mr_")
    if not re.fullmatch(r"[A-Za-z0-9_]*", prefix):
        raise RuntimeError("unsafe db prefix")
    table = f"`{prefix}user`"
    columns = {
        "pay_password_hash": f"ALTER TABLE {table} ADD COLUMN `pay_password_hash` varchar(255) NOT NULL DEFAULT '' AFTER `password`",
        "pay_password_error_count": f"ALTER TABLE {table} ADD COLUMN `pay_password_error_count` int(11) NOT NULL DEFAULT 0 AFTER `pay_password_hash`",
        "wallet_locked": f"ALTER TABLE {table} ADD COLUMN `wallet_locked` tinyint(1) NOT NULL DEFAULT 0 AFTER `pay_password_error_count`",
        "wallet_locked_time": f"ALTER TABLE {table} ADD COLUMN `wallet_locked_time` int(11) NOT NULL DEFAULT 0 AFTER `wallet_locked`",
        "pay_password_update_time": f"ALTER TABLE {table} ADD COLUMN `pay_password_update_time` int(11) NOT NULL DEFAULT 0 AFTER `wallet_locked_time`",
    }
    for column, sql in columns.items():
        exists = mysql(f"SHOW COLUMNS FROM {table} LIKE '{column}'")
        if exists.returncode != 0:
            raise RuntimeError(exists.stderr.strip() or f"mysql check failed: {column}")
        if exists.stdout.strip():
            continue
        added = mysql(sql)
        if added.returncode != 0:
            raise RuntimeError(added.stderr.strip() or f"mysql alter failed: {column}")
        print("DB_ADDED", column)


API_PAYMENT_BLOCK = r'''
    // blin-payment-password-start
    private function blinEnsurePaymentPasswordColumns()
    {
        try {
            $this->blinTransferAddColumnIfMissing("mr_user", "pay_password_hash", "ALTER TABLE `mr_user` ADD COLUMN `pay_password_hash` varchar(255) NOT NULL DEFAULT '' AFTER `password`");
            $this->blinTransferAddColumnIfMissing("mr_user", "pay_password_error_count", "ALTER TABLE `mr_user` ADD COLUMN `pay_password_error_count` int(11) NOT NULL DEFAULT 0 AFTER `pay_password_hash`");
            $this->blinTransferAddColumnIfMissing("mr_user", "wallet_locked", "ALTER TABLE `mr_user` ADD COLUMN `wallet_locked` tinyint(1) NOT NULL DEFAULT 0 AFTER `pay_password_error_count`");
            $this->blinTransferAddColumnIfMissing("mr_user", "wallet_locked_time", "ALTER TABLE `mr_user` ADD COLUMN `wallet_locked_time` int(11) NOT NULL DEFAULT 0 AFTER `wallet_locked`");
            $this->blinTransferAddColumnIfMissing("mr_user", "pay_password_update_time", "ALTER TABLE `mr_user` ADD COLUMN `pay_password_update_time` int(11) NOT NULL DEFAULT 0 AFTER `wallet_locked_time`");
        } catch (\Exception $e) {}
    }

    private function blinPaymentUser()
    {
        $this->blinEnsurePaymentPasswordColumns();
        $id = isset($this->user_info["id"]) ? intval($this->user_info["id"]) : 0;
        if ($id <= 0) $this->json(0, "请先登录");
        $user = Db::name("user")->where("appid", intval($this->appid))->where("id", $id)->find();
        if (!$user) $this->json(0, "用户不存在");
        return $user;
    }

    private function blinPaymentPasswordFromInput($data = null)
    {
        if (!is_array($data)) $data = input();
        foreach (["payment_password", "pay_password", "trade_password", "wallet_password"] as $key) {
            if (isset($data[$key]) && trim(strval($data[$key])) !== "") return trim(strval($data[$key]));
        }
        return "";
    }

    private function blinPaymentPasswordValid($password)
    {
        return preg_match('/^\d{6}$/', strval($password)) === 1;
    }

    private function blinPaymentPasswordStatusData($user)
    {
        $mobile = strval(isset($user["mobile"]) ? $user["mobile"] : "");
        $email = strval(isset($user["email"]) ? $user["email"] : "");
        return [
            "has_password" => trim(strval(isset($user["pay_password_hash"]) ? $user["pay_password_hash"] : "")) !== "" ? 1 : 0,
            "wallet_locked" => intval(isset($user["wallet_locked"]) ? $user["wallet_locked"] : 0),
            "failed_attempts" => intval(isset($user["pay_password_error_count"]) ? $user["pay_password_error_count"] : 0),
            "remaining_attempts" => max(0, 3 - intval(isset($user["pay_password_error_count"]) ? $user["pay_password_error_count"] : 0)),
            "mobile_bound" => trim($mobile) !== "" ? 1 : 0,
            "email_bound" => trim($email) !== "" ? 1 : 0,
            "masked_mobile" => $this->blinMaskMobile($mobile),
            "masked_email" => $this->blinMaskEmail($email),
        ];
    }

    private function blinMaskMobile($mobile)
    {
        $mobile = trim(strval($mobile));
        if (strlen($mobile) < 7) return $mobile;
        return substr($mobile, 0, 3) . "****" . substr($mobile, -4);
    }

    private function blinMaskEmail($email)
    {
        $email = trim(strval($email));
        if ($email === "" || strpos($email, "@") === false) return $email;
        list($name, $domain) = explode("@", $email, 2);
        $prefix = mb_substr($name, 0, 1, "UTF-8");
        return $prefix . "***@" . $domain;
    }

    private function blinPaymentPasswordCheck($user, $password, $countFailure = true)
    {
        $this->blinEnsurePaymentPasswordColumns();
        $userId = intval($user["id"]);
        $fresh = Db::name("user")->where("appid", intval($this->appid))->where("id", $userId)->find();
        if (!$fresh) $this->json(0, "用户不存在");
        if (trim(strval(isset($fresh["pay_password_hash"]) ? $fresh["pay_password_hash"] : "")) === "") {
            $this->json(0, "请先设置支付密码");
        }
        if (intval(isset($fresh["wallet_locked"]) ? $fresh["wallet_locked"] : 0) === 1) {
            $this->json(0, "钱包已锁定，请找回支付密码后再支付");
        }
        if (!$this->blinPaymentPasswordValid($password)) {
            $this->json(0, "支付密码必须是6位数字");
        }
        if (password_verify(strval($password), strval($fresh["pay_password_hash"]))) {
            Db::name("user")->where("id", $userId)->update(["pay_password_error_count" => 0, "wallet_locked" => 0, "wallet_locked_time" => 0]);
            return true;
        }
        if ($countFailure) {
            $next = intval(isset($fresh["pay_password_error_count"]) ? $fresh["pay_password_error_count"] : 0) + 1;
            $update = ["pay_password_error_count" => $next];
            if ($next >= 3) {
                $update["wallet_locked"] = 1;
                $update["wallet_locked_time"] = time();
            }
            Db::name("user")->where("id", $userId)->update($update);
            if ($next >= 3) {
                $this->json(0, "支付密码错误次数过多，钱包已锁定");
            }
            $this->json(0, "支付密码错误，还可输入" . max(0, 3 - $next) . "次");
        }
        return false;
    }

    private function blinRequirePaymentPassword($user, $data = null)
    {
        $password = $this->blinPaymentPasswordFromInput($data);
        if ($password === "") $this->json(0, "请输入支付密码");
        $this->blinPaymentPasswordCheck($user, $password, true);
    }

    private function blinPaymentPasswordCodeCacheKey($user, $method)
    {
        return intval($this->appid) . "pay_password_" . $method . "_" . intval($user["id"]);
    }

    private function blinVerifyPaymentPasswordCode($user, $method, $code, $clear = false)
    {
        $method = strtolower(trim(strval($method)));
        $code = trim(strval($code));
        if (!in_array($method, ["mobile", "email"])) $this->json(0, "请选择验证方式");
        if ($code === "") $this->json(0, "请输入验证码");
        $key = $this->blinPaymentPasswordCodeCacheKey($user, $method);
        $cache = Cache::get($key);
        if (!$cache || trim(strval(isset($cache["code"]) ? $cache["code"] : "")) !== $code) {
            $this->json(0, "验证码错误或已过期");
        }
        if ($clear) Cache::rm($key);
        return true;
    }

    public function get_payment_password_status()
    {
        $data = input();
        $validate = new Validate(["usertoken|用户token" => "require"]);
        if (!$validate->check($data)) $this->json(0, $validate->getError());
        $user = $this->blinPaymentUser();
        $this->json(1, "读取成功", $this->blinPaymentPasswordStatusData($user));
    }

    public function verify_payment_password()
    {
        $data = input();
        $validate = new Validate(["usertoken|用户token" => "require"]);
        if (!$validate->check($data)) $this->json(0, $validate->getError());
        $user = $this->blinPaymentUser();
        $this->blinPaymentPasswordCheck($user, $this->blinPaymentPasswordFromInput($data), true);
        $fresh = Db::name("user")->where("id", intval($user["id"]))->find();
        $this->json(1, "验证成功", $this->blinPaymentPasswordStatusData($fresh ?: $user));
    }

    public function send_payment_password_verification_code()
    {
        $data = input();
        $validate = new Validate(["usertoken|用户token" => "require"]);
        if (!$validate->check($data)) $this->json(0, $validate->getError());
        $user = $this->blinPaymentUser();
        $method = strtolower(trim(strval(isset($data["method"]) ? $data["method"] : input("verification_method"))));
        if (!in_array($method, ["mobile", "email"])) $this->json(0, "请选择验证方式");
        $ttl = intval($this->blinAppSystemValue($method === "mobile" ? "phone_code_time" : "email_code_time", 300));
        $interval = intval($this->blinAppSystemValue($method === "mobile" ? "phone_code_interval_time" : "email_code_interval_time", 60));
        $cacheKey = $this->blinPaymentPasswordCodeCacheKey($user, $method);
        $cached = Cache::get($cacheKey);
        if ($cached && time() - intval($cached["time"]) < $interval) {
            $this->json(0, max(1, intval($interval / 60)) . "分钟内只能发送一次验证码");
        }
        $code = rand(100000, 999999);
        if ($method === "mobile") {
            $mobile = trim(strval(isset($user["mobile"]) ? $user["mobile"] : ""));
            if ($mobile === "") $this->json(0, "当前账号未绑定手机号");
            $sms = new AlibabaSample($this->appid);
            $sms->setCode($code);
            $result = $sms->send($mobile);
            if ($result != 1) $this->json(0, strval($result));
            Cache::set($cacheKey, ["code"=>$code, "method"=>$method, "mobile"=>$mobile, "time"=>time()], $ttl);
            $this->json(1, "验证码已发送");
        }
        $email = trim(strval(isset($user["email"]) ? $user["email"] : ""));
        if ($email === "") $this->json(0, "当前账号未绑定邮箱");
        $mail = new Email($email);
        $appName = isset($this->app_info["appname"]) ? strval($this->app_info["appname"]) : "应用";
        $minutes = max(1, intval($ttl / 60));
        $mail->setSubject($appName . "支付密码验证");
        $mail->setFrom($appName);
        $mail->setBody("<p>你的支付密码验证码为：<b>" . $code . "</b></p><p>验证码" . $minutes . "分钟内有效。如非本人操作，请忽略。</p>");
        $result = $mail->send();
        if ($result != 1) $this->json(0, strval($result));
        Cache::set($cacheKey, ["code"=>$code, "method"=>$method, "email"=>$email, "time"=>time()], $ttl);
        $this->json(1, "验证码已发送");
    }

    public function set_payment_password()
    {
        $data = input();
        $validate = new Validate(["usertoken|用户token" => "require"]);
        if (!$validate->check($data)) $this->json(0, $validate->getError());
        $user = $this->blinPaymentUser();
        $password = trim(strval(isset($data["payment_password"]) ? $data["payment_password"] : (isset($data["pay_password"]) ? $data["pay_password"] : input("new_password"))));
        $confirm = trim(strval(isset($data["confirm_password"]) ? $data["confirm_password"] : input("confirm_payment_password")));
        if (!$this->blinPaymentPasswordValid($password)) $this->json(0, "支付密码必须是6位数字");
        if ($confirm !== "" && $confirm !== $password) $this->json(0, "两次输入的支付密码不一致");
        $hasPassword = trim(strval(isset($user["pay_password_hash"]) ? $user["pay_password_hash"] : "")) !== "";
        $method = strtolower(trim(strval(isset($data["verification_method"]) ? $data["verification_method"] : input("method"))));
        $code = trim(strval(isset($data["verification_code"]) ? $data["verification_code"] : input("code")));
        if ($method !== "" || $code !== "") {
            $this->blinVerifyPaymentPasswordCode($user, $method, $code, true);
        } elseif ($hasPassword) {
            $old = trim(strval(isset($data["old_payment_password"]) ? $data["old_payment_password"] : input("old_pay_password")));
            if ($old === "") $this->json(0, "请输入原支付密码");
            $this->blinPaymentPasswordCheck($user, $old, true);
        }
        Db::name("user")->where("appid", intval($this->appid))->where("id", intval($user["id"]))->update([
            "pay_password_hash" => password_hash($password, PASSWORD_DEFAULT),
            "pay_password_error_count" => 0,
            "wallet_locked" => 0,
            "wallet_locked_time" => 0,
            "pay_password_update_time" => time(),
        ]);
        $fresh = Db::name("user")->where("id", intval($user["id"]))->find();
        $this->json(1, "支付密码已更新", $this->blinPaymentPasswordStatusData($fresh ?: $user));
    }

    public function get_pay_password_status(){ return $this->get_payment_password_status(); }
    public function verify_pay_password(){ return $this->verify_payment_password(); }
    public function send_pay_password_code(){ return $this->send_payment_password_verification_code(); }
    public function set_pay_password(){ return $this->set_payment_password(); }
    // blin-payment-password-end

'''


def patch_api():
    before = read(API)
    text = before
    text = insert_before(text, "    //用户注册\n", API_PAYMENT_BLOCK, "payment api block")

    text = replace_in_method(
        text,
        "    public function send_im_red_packet()",
        '''        if ($existing) $this->json(1, "发送成功", $this->blinRedPacketDuplicateData($existing, intval($sender["id"])));
        Db::startTrans();
''',
        '''        if ($existing) $this->json(1, "发送成功", $this->blinRedPacketDuplicateData($existing, intval($sender["id"])));
        $this->blinRequirePaymentPassword($sender, $data);
        Db::startTrans();
''',
        "private red packet pay password",
    )
    text = replace_in_method(
        text,
        "    public function send_im_group_red_packet()",
        '''        if ($existing) $this->json(1, "发送成功", $this->blinRedPacketDuplicateData($existing, intval($sender["id"])));
        Db::startTrans();
''',
        '''        if ($existing) $this->json(1, "发送成功", $this->blinRedPacketDuplicateData($existing, intval($sender["id"])));
        $this->blinRequirePaymentPassword($sender, $data);
        Db::startTrans();
''',
        "group red packet pay password",
    )
    text = replace_in_method(
        text,
        "    public function send_im_group_transfer()",
        '''        if ($existing) $this->json(1, "发送成功", $this->blinGroupTransferDuplicateData($existing, intval($sender["id"])));
        Db::startTrans();
''',
        '''        if ($existing) $this->json(1, "发送成功", $this->blinGroupTransferDuplicateData($existing, intval($sender["id"])));
        $this->blinRequirePaymentPassword($sender, $data);
        Db::startTrans();
''',
        "group transfer pay password",
    )
    text = replace_in_method(
        text,
        "    public function send_message()",
        '''            if (intval($data["receiver_id"]) == intval($user_all_info["id"])) {
                $this->json(0, "不能给自己转账");
            }
            $transfer_rate = $this->blinTransferFeeRate(isset($this->app_info["forum_configuration"]["transfer_handling_fee"]) ? $this->app_info["forum_configuration"]["transfer_handling_fee"] : 0);
''',
        '''            if (intval($data["receiver_id"]) == intval($user_all_info["id"])) {
                $this->json(0, "不能给自己转账");
            }
            $this->blinRequirePaymentPassword($user_all_info, $data);
            $transfer_rate = $this->blinTransferFeeRate(isset($this->app_info["forum_configuration"]["transfer_handling_fee"]) ? $this->app_info["forum_configuration"]["transfer_handling_fee"] : 0);
''',
        "private transfer pay password",
    )
    write_if_changed(API, before, text, "payment_password_api")


USER_ADMIN_BLOCK = r'''
    // blin-payment-password-admin-start
    private function blinEnsurePaymentPasswordAdminColumns()
    {
        try { Db::execute("ALTER TABLE `mr_user` ADD COLUMN `pay_password_hash` varchar(255) NOT NULL DEFAULT '' AFTER `password`"); } catch (\Exception $e) {}
        try { Db::execute("ALTER TABLE `mr_user` ADD COLUMN `pay_password_error_count` int(11) NOT NULL DEFAULT 0 AFTER `pay_password_hash`"); } catch (\Exception $e) {}
        try { Db::execute("ALTER TABLE `mr_user` ADD COLUMN `wallet_locked` tinyint(1) NOT NULL DEFAULT 0 AFTER `pay_password_error_count`"); } catch (\Exception $e) {}
        try { Db::execute("ALTER TABLE `mr_user` ADD COLUMN `wallet_locked_time` int(11) NOT NULL DEFAULT 0 AFTER `wallet_locked`"); } catch (\Exception $e) {}
        try { Db::execute("ALTER TABLE `mr_user` ADD COLUMN `pay_password_update_time` int(11) NOT NULL DEFAULT 0 AFTER `wallet_locked_time`"); } catch (\Exception $e) {}
    }

    public function clear_pay_password()
    {
        if (!Request::isAjax()) return $this->error("请求方式错误");
        $id = intval(input("id"));
        if ($id <= 0) return $this->error("请选择用户");
        $this->blinEnsurePaymentPasswordAdminColumns();
        $user = Db::name("user")->where("id", $id)->find();
        if (!$user) return $this->error("用户不存在");
        $this->blinRequireApp($user["appid"]);
        Db::name("user")->where("id", $id)->update([
            "pay_password_hash" => "",
            "pay_password_error_count" => 0,
            "wallet_locked" => 0,
            "wallet_locked_time" => 0,
            "pay_password_update_time" => 0,
        ]);
        return $this->success("支付密码已清除");
    }
    // blin-payment-password-admin-end
'''


def patch_user_controller():
    before = read(USER)
    text = before
    text = text.replace(
        "public $no_need_right = ['obtain_user_action_logs'];",
        "public $no_need_right = ['obtain_user_action_logs', 'clear_pay_password'];",
        1,
    )
    text = replace_once(
        text,
        '''                $rows_list[$key]["reasons"] = $value["reasons"];
''',
        '''                $rows_list[$key]["reasons"] = $value["reasons"];
                $rows_list[$key]["wallet_locked"] = intval(isset($value["wallet_locked"]) ? $value["wallet_locked"] : 0);
                $rows_list[$key]["pay_password_status"] = trim(strval(isset($value["pay_password_hash"]) ? $value["pay_password_hash"] : "")) === "" ? "未设置" : ($rows_list[$key]["wallet_locked"] == 1 ? "已锁定" : "已设置");
''',
        "user list payment fields",
    )
    text = insert_before_last_class_brace(text, USER_ADMIN_BLOCK, "admin payment block")
    write_if_changed(USER, before, text, "payment_password_admin")


def patch_user_index():
    before = read(USER_INDEX)
    text = before
    text = replace_once(
        text,
        '''        }, {
            field: 'reasons',
            title: '状态',
            formatter: function (value, row, index) {
                var value = "";
                if (row.reasons == 1) {
                    value = '<span class="badge bg-danger">封禁中</span>';
                } else {
                    value = '<span class="badge bg-success">正常</span>';
                }
                return value;
            }
        }, {
            field: 'operate',
''',
        '''        }, {
            field: 'reasons',
            title: '状态',
            formatter: function (value, row, index) {
                var value = "";
                if (row.reasons == 1) {
                    value = '<span class="badge bg-danger">封禁中</span>';
                } else {
                    value = '<span class="badge bg-success">正常</span>';
                }
                return value;
            }
        }, {
            field: 'pay_password_status',
            title: '支付密码',
            formatter: function (value, row, index) {
                if (value == '已锁定') return '<span class="badge bg-danger">已锁定</span>';
                if (value == '已设置') return '<span class="badge bg-success">已设置</span>';
                return '<span class="badge bg-secondary">未设置</span>';
            }
        }, {
            field: 'operate',
''',
        "payment status column",
    )
    text = replace_once(
        text,
        '''                'click .del-btn': function (event, value, row, index) {
                    deleteuser(row.id, row.username);
                }
''',
        '''                'click .del-btn': function (event, value, row, index) {
                    deleteuser(row.id, row.username);
                },
                'click .clear-pay-btn': function (event, value, row, index) {
                    clearPayPassword(row.id, row.username);
                }
''',
        "clear pay event",
    )
    text = replace_once(
        text,
        '''    function btnGroup() {
        var html = '';
        {if checkRight('user/edit') }
            html += '<a href="#!" class="btn btn-sm btn-default me-1 edit-btn" title="编辑" data-bs-toggle="tooltip"><i class="mdi mdi-pencil"></i></a>';
        {/if}
        {if checkRight('user/del') }
            html += '<a href="#!" class="btn btn-sm btn-default del-btn" title="删除" data-bs-toggle="tooltip"><i class="mdi mdi-window-close"></i></a>';
        {/if}
        return html;
    }
''',
        '''    function btnGroup(value, row, index) {
        var html = '';
        {if checkRight('user/edit') }
            html += '<a href="#!" class="btn btn-sm btn-default me-1 edit-btn" title="编辑" data-bs-toggle="tooltip"><i class="mdi mdi-pencil"></i></a>';
            html += '<a href="#!" class="btn btn-sm btn-warning me-1 clear-pay-btn" title="清除支付密码并解锁钱包" data-bs-toggle="tooltip"><i class="mdi mdi-lock-reset"></i></a>';
        {/if}
        {if checkRight('user/del') }
            html += '<a href="#!" class="btn btn-sm btn-default del-btn" title="删除" data-bs-toggle="tooltip"><i class="mdi mdi-window-close"></i></a>';
        {/if}
        return html;
    }
''',
        "clear pay button",
    )
    text = replace_once(
        text,
        '''    function deleteuser(id, username) {
        layer.confirm("确定删除" + username + "用户？(此删除将会删除与此用户相关联的所有数据)", {
            title: "删除确认",
            btn: ['确定', '关闭'] //按钮
        }, function () {
            del(id);
        }, function () {
        });
    }
''',
        '''    function deleteuser(id, username) {
        layer.confirm("确定删除" + username + "用户？(此删除将会删除与此用户相关联的所有数据)", {
            title: "删除确认",
            btn: ['确定', '关闭'] //按钮
        }, function () {
            del(id);
        }, function () {
        });
    }

    function clearPayPassword(id, username) {
        layer.confirm("确定清除 " + username + " 的支付密码并解锁钱包？", {
            title: "清除支付密码",
            btn: ['确定', '关闭']
        }, function () {
            var l = $('body').lyearloading({
                opacity: 0.2,
                spinnerSize: 'lg',
                spinnerText: '后台处理中，请稍后...',
                textColorClass: 'text-info',
                spinnerColorClass: 'text-info'
            });
            $.ajax({
                type: "POST",
                url: '{:url("clear_pay_password")}',
                data: { id: id },
                dataType: "json",
                success: function (data) {
                    l.destroy();
                    layer.closeAll();
                    if (data.code == 1) {
                        notify.success(data.msg);
                        $('#table').bootstrapTable('refresh');
                    } else {
                        notify.error(data.msg);
                    }
                },
                error: function () {
                    l.destroy();
                    notify.error("服务器错误");
                }
            });
        }, function () {});
    }
''',
        "clear pay function",
    )
    write_if_changed(USER_INDEX, before, text, "payment_password_user_view")


def main():
    patch_database()
    patch_api()
    patch_user_controller()
    patch_user_index()
    print("PATCHED_PAYMENT_PASSWORD")


if __name__ == "__main__":
    main()
