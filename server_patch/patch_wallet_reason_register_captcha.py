#!/usr/bin/env python3
"""Add wallet lock reason and require image captcha before register code send."""

from datetime import datetime
from pathlib import Path
import os
import shutil
import subprocess


ROOT = Path(os.environ.get("BLIN_ROOT", "/www/wwwroot/blinlin"))
API = ROOT / "application/api/controller/Api.php"
USER = ROOT / "application/admin/controller/User.php"
USER_INDEX = ROOT / "application/admin/view/user/index.html"


def backup(path, suffix):
    stamp = datetime.now().strftime("%Y%m%d%H%M%S")
    shutil.copy2(path, path.with_name("%s.bak_%s_%s" % (path.name, suffix, stamp)))


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
        raise RuntimeError("missing anchor: " + label)
    return text.replace(old, new, 1)


def replace_between(text, start, end, new, label):
    if new in text:
        return text
    start_index = text.find(start)
    if start_index < 0:
        raise RuntimeError("missing start anchor: " + label)
    end_index = text.find(end, start_index)
    if end_index < 0:
        raise RuntimeError("missing end anchor: " + label)
    return text[:start_index] + new + text[end_index:]


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
            "-h%s" % (config.get("hostname") or "127.0.0.1"),
            "-u%s" % (config.get("username") or "root"),
            "-P%s" % (config.get("hostport") or "3306"),
            config.get("database") or "blinlin",
            "-Nse",
            sql,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
        env=env,
        check=False,
    )


def patch_database():
    config = db_config()
    prefix = config.get("prefix", "mr_")
    table = "`%suser`" % prefix
    exists = mysql("SHOW COLUMNS FROM %s LIKE 'wallet_locked_reason'" % table)
    if exists.returncode != 0:
        raise RuntimeError(exists.stderr.strip() or "mysql check failed")
    if not exists.stdout.strip():
        added = mysql(
            "ALTER TABLE %s ADD COLUMN `wallet_locked_reason` varchar(255) NOT NULL DEFAULT '' AFTER `wallet_locked_time`"
            % table
        )
        if added.returncode != 0:
            raise RuntimeError(added.stderr.strip() or "mysql alter failed")
        print("DB_ADDED wallet_locked_reason")


def patch_api():
    before = read(API)
    after = before
    after = replace_once(
        after,
        '            $this->blinTransferAddColumnIfMissing("mr_user", "wallet_locked_time", "ALTER TABLE `mr_user` ADD COLUMN `wallet_locked_time` int(11) NOT NULL DEFAULT 0 AFTER `wallet_locked`");\n            $this->blinTransferAddColumnIfMissing("mr_user", "pay_password_update_time", "ALTER TABLE `mr_user` ADD COLUMN `pay_password_update_time` int(11) NOT NULL DEFAULT 0 AFTER `wallet_locked_time`");',
        '            $this->blinTransferAddColumnIfMissing("mr_user", "wallet_locked_time", "ALTER TABLE `mr_user` ADD COLUMN `wallet_locked_time` int(11) NOT NULL DEFAULT 0 AFTER `wallet_locked`");\n            $this->blinTransferAddColumnIfMissing("mr_user", "wallet_locked_reason", "ALTER TABLE `mr_user` ADD COLUMN `wallet_locked_reason` varchar(255) NOT NULL DEFAULT \'\' AFTER `wallet_locked_time`");\n            $this->blinTransferAddColumnIfMissing("mr_user", "pay_password_update_time", "ALTER TABLE `mr_user` ADD COLUMN `pay_password_update_time` int(11) NOT NULL DEFAULT 0 AFTER `wallet_locked_time`");',
        "api ensure wallet reason",
    )
    after = replace_once(
        after,
        '            "wallet_locked" => intval(isset($user["wallet_locked"]) ? $user["wallet_locked"] : 0),\n            "failed_attempts" => intval(isset($user["pay_password_error_count"]) ? $user["pay_password_error_count"] : 0),',
        '            "wallet_locked" => intval(isset($user["wallet_locked"]) ? $user["wallet_locked"] : 0),\n            "wallet_locked_reason" => trim(strval(isset($user["wallet_locked_reason"]) ? $user["wallet_locked_reason"] : "")),\n            "failed_attempts" => intval(isset($user["pay_password_error_count"]) ? $user["pay_password_error_count"] : 0),',
        "api status wallet reason",
    )
    after = replace_once(
        after,
        '        if (intval(isset($fresh["wallet_locked"]) ? $fresh["wallet_locked"] : 0) === 1) {\n            $this->json(0, "钱包已锁定，请找回支付密码后再支付");\n        }',
        '        if (intval(isset($fresh["wallet_locked"]) ? $fresh["wallet_locked"] : 0) === 1) {\n            $reason = trim(strval(isset($fresh["wallet_locked_reason"]) ? $fresh["wallet_locked_reason"] : ""));\n            $this->json(0, $reason === "" ? "钱包已锁定，无法使用钱包" : "钱包已锁定，无法使用钱包。原因：" . $reason);\n        }',
        "api wallet locked message",
    )
    after = replace_once(
        after,
        '            Db::name("user")->where("id", $userId)->update(["pay_password_error_count" => 0, "wallet_locked" => 0, "wallet_locked_time" => 0]);',
        '            Db::name("user")->where("id", $userId)->update(["pay_password_error_count" => 0, "wallet_locked" => 0, "wallet_locked_time" => 0, "wallet_locked_reason" => ""]);',
        "api clear reason on verify",
    )
    after = replace_once(
        after,
        '                $update["wallet_locked"] = 1;\n                $update["wallet_locked_time"] = time();',
        '                $update["wallet_locked"] = 1;\n                $update["wallet_locked_time"] = time();\n                $update["wallet_locked_reason"] = "支付密码错误次数过多";',
        "api set auto lock reason",
    )
    after = replace_once(
        after,
        '            "wallet_locked_time" => 0,\n            "pay_password_update_time" => time(),',
        '            "wallet_locked_time" => 0,\n            "wallet_locked_reason" => "",\n            "pay_password_update_time" => time(),',
        "api clear reason on set",
    )
    after = replace_once(
        after,
        '                $validate = new Validate($rule);\n                $result = $validate->check($data);\n                if (!$result) {\n                    throw new \\Exception((string)$validate->getError());\n                }\n                $mobile_code_cache = Cache::get($this->appid . "mobile_register" . $mobile);',
        '                $validate = new Validate($rule);\n                $result = $validate->check($data);\n                if (!$result) {\n                    throw new \\Exception((string)$validate->getError());\n                }\n                if (!$this->blinCheckImageCaptcha("register", input("captcha"))) {\n                    throw new \\Exception("图片验证码错误");\n                }\n                $mobile_code_cache = Cache::get($this->appid . "mobile_register" . $mobile);',
        "mobile register image captcha",
    )
    after = replace_once(
        after,
        '                $validate = new Validate($rule);\n                $result = $validate->check($data);\n                if (!$result) {\n                    throw new \\Exception((string)$validate->getError());\n                }\n                $email_register_code_cache = Cache::get($this->appid . "email_register" . $email);',
        '                $validate = new Validate($rule);\n                $result = $validate->check($data);\n                if (!$result) {\n                    throw new \\Exception((string)$validate->getError());\n                }\n                if (!$this->blinCheckImageCaptcha("register", input("captcha"))) {\n                    throw new \\Exception("图片验证码错误");\n                }\n                $email_register_code_cache = Cache::get($this->appid . "email_register" . $email);',
        "email register image captcha",
    )
    write_if_changed(API, before, after, "wallet_reason_register_captcha_api")


def patch_user_controller():
    before = read(USER)
    after = before
    after = replace_once(
        after,
        '        try { Db::execute("ALTER TABLE `mr_user` ADD COLUMN `wallet_locked_time` int(11) NOT NULL DEFAULT 0 AFTER `wallet_locked`"); } catch (\\Exception $e) {}\n        try { Db::execute("ALTER TABLE `mr_user` ADD COLUMN `pay_password_update_time` int(11) NOT NULL DEFAULT 0 AFTER `wallet_locked_time`"); } catch (\\Exception $e) {}',
        '        try { Db::execute("ALTER TABLE `mr_user` ADD COLUMN `wallet_locked_time` int(11) NOT NULL DEFAULT 0 AFTER `wallet_locked`"); } catch (\\Exception $e) {}\n        try { Db::execute("ALTER TABLE `mr_user` ADD COLUMN `wallet_locked_reason` varchar(255) NOT NULL DEFAULT \'\' AFTER `wallet_locked_time`"); } catch (\\Exception $e) {}\n        try { Db::execute("ALTER TABLE `mr_user` ADD COLUMN `pay_password_update_time` int(11) NOT NULL DEFAULT 0 AFTER `wallet_locked_time`"); } catch (\\Exception $e) {}',
        "admin ensure reason",
    )
    after = replace_once(
        after,
        '            "wallet_locked_time" => 0,\n            "pay_password_update_time" => 0,',
        '            "wallet_locked_time" => 0,\n            "wallet_locked_reason" => "",\n            "pay_password_update_time" => 0,',
        "admin clear reason",
    )
    after = replace_once(
        after,
        '        $locked = intval(input("locked")) == 1 ? 1 : 0;\n        if ($id <= 0) return $this->error("请选择用户");',
        '        $locked = intval(input("locked")) == 1 ? 1 : 0;\n        $reason = trim(strval(input("reason")));\n        if (function_exists("mb_substr")) $reason = mb_substr($reason, 0, 120, "UTF-8"); else $reason = substr($reason, 0, 240);\n        if ($id <= 0) return $this->error("请选择用户");',
        "admin read reason",
    )
    after = replace_once(
        after,
        '            "wallet_locked_time" => $locked ? time() : 0,\n            "pay_password_error_count" => $locked ? intval(isset($user["pay_password_error_count"]) ? $user["pay_password_error_count"] : 0) : 0,',
        '            "wallet_locked_time" => $locked ? time() : 0,\n            "wallet_locked_reason" => $locked ? $reason : "",\n            "pay_password_error_count" => $locked ? intval(isset($user["pay_password_error_count"]) ? $user["pay_password_error_count"] : 0) : 0,',
        "admin save reason",
    )
    write_if_changed(USER, before, after, "wallet_reason_register_captcha_user")


def patch_user_index():
    before = read(USER_INDEX)
    functions_block = """    function clearPayPassword(id, username) {
        layer.confirm("确定清除 " + username + " 的支付密码？", {
            title: "清除支付密码",
            btn: ['确定', '关闭']
        }, function () {
            var l = $('body').lyearloading({
                opacity: 0.2,
                spinnerSize: 'nm'
            });
            $.ajax({
                type: "post",
                url: '{:url("clear_pay_password")}',
                data: { id: id },
                success: function (res) {
                    l.destroy();
                    if (res.code == 1) {
                        layer.msg(res.msg || "操作成功", {time: 1500}, function () {
                            location.reload();
                        });
                    } else {
                        layer.msg(res.msg || "操作失败");
                    }
                },
                error: function () {
                    l.destroy();
                    layer.msg("网络异常，请稍后再试");
                }
            });
        }, function () {});
    }

    function setWalletLock(id, username, locked) {
        var doSubmit = function(reason) {
            var l = $('body').lyearloading({
                opacity: 0.2,
                spinnerSize: 'nm'
            });
            $.ajax({
                type: "post",
                url: '{:url("set_wallet_lock")}',
                data: { id: id, locked: locked, reason: reason || "" },
                success: function (res) {
                    l.destroy();
                    if (res.code == 1) {
                        layer.msg(res.msg || "操作成功", {time: 1500}, function () {
                            location.reload();
                        });
                    } else {
                        layer.msg(res.msg || "操作失败");
                    }
                },
                error: function () {
                    l.destroy();
                    layer.msg("网络异常，请稍后再试");
                }
            });
        };
        if (locked == 1) {
            layer.prompt({
                title: "请输入钱包锁定原因（可不填）",
                formType: 2,
                value: ""
            }, function(value, index) {
                layer.close(index);
                doSubmit(value);
            });
        } else {
            layer.confirm("确定解锁 " + username + " 的钱包？", {
                title: "解锁钱包",
                btn: ['确定', '关闭']
            }, function () { doSubmit(""); }, function () {});
        }
    }

"""
    after = replace_between(
        before,
        "    function clearPayPassword(id, username) {",
        "    $(\"#btn_delete\").click(function () {",
        functions_block,
        "wallet admin js functions",
    )
    write_if_changed(USER_INDEX, before, after, "wallet_reason_register_captcha_user_view")


def main():
    patch_database()
    patch_api()
    patch_user_controller()
    patch_user_index()
    print("PATCHED_WALLET_REASON_REGISTER_CAPTCHA")


if __name__ == "__main__":
    main()
