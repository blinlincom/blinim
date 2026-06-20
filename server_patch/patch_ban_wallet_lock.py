#!/usr/bin/env python3
"""Fix banned-user enforcement and add admin wallet lock actions."""

from datetime import datetime
from pathlib import Path
import os
import shutil


ROOT = Path(os.environ.get("BLIN_ROOT", "/www/wwwroot/blinlin"))
API = ROOT / "application/api/controller/Api.php"
BASE = ROOT / "application/api/controller/BaseController.php"
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


def insert_after(text, marker, block, label):
    if block.strip() in text:
        return text
    pos = text.find(marker)
    if pos < 0:
        raise RuntimeError("missing marker: " + label)
    pos += len(marker)
    return text[:pos] + block + text[pos:]


def replace_once(text, old, new, label):
    if new in text:
        return text
    if old not in text:
        raise RuntimeError("missing anchor: " + label)
    return text.replace(old, new, 1)


def method_slice(text, signature):
    start = text.find(signature)
    if start < 0:
        raise RuntimeError("missing method: " + signature)
    brace = text.find("{", start)
    if brace < 0:
        raise RuntimeError("missing method brace: " + signature)
    depth = 0
    for i in range(brace, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return start, i + 1
    raise RuntimeError("missing method end: " + signature)


def replace_method(text, signature, method_text):
    start, end = method_slice(text, signature)
    if method_text.strip() in text[start:end]:
        return text
    return text[:start] + method_text + text[end:]


BAN_HELPER = r'''
    // blin-ban-guard-start
    protected function blinRejectBannedUser($user_info)
    {
        if (!$user_info || intval(isset($user_info["reasons"]) ? $user_info["reasons"] : 0) != 1) {
            return false;
        }
        $until = intval(isset($user_info["reasons_time"]) ? $user_info["reasons_time"] : 0);
        $reason = trim(strval(isset($user_info["reasons_ban"]) ? $user_info["reasons_ban"] : ""));
        if ($until <= 0 || $until > time()) {
            $message = "你账号已被封禁";
            if ($reason !== "") $message .= "，封禁理由为：" . $reason;
            if ($until > 0) $message .= "，解封时间为" . date("Y-m-d H:i:s", $until);
            $this->json(403, $message);
        }
        Db::name("user")->where("id", intval($user_info["id"]))->update([
            "reasons" => 0,
            "reasons_time" => "",
            "reasons_ban" => "",
        ]);
        return true;
    }
    // blin-ban-guard-end

'''


GET_USER_METHOD = r'''    //更新用户在线记录
    public function getUserLogonInfoByUsertoken($usertoken = '')
    {
        if ($usertoken == "") {
            return false;
        }
        //查询当前用户token是否存在。优先使用按终端保存的会话表，兼容旧的 mr_user.usertoken。
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
        }
        $this->blinRejectBannedUser($user_info);
        $this->user_info = $user_info;
        //增加用户在线记录
        $user_logon = [
            "login_ip" => get_client_ip(),
            "last_activity_time" => time(),
        ];
        Db::name("online_record")->where("userid", $user_info["id"])->update($user_logon);
        $now_time = date("Y-m-d", time());
        $log = Db::name("user_log")->where("type = 1 and userid={$user_info["id"]} and create_time like '{$now_time}%'")->find();
        if (!$log) {
            //加入签到记录
            Db::name('user_log')->insert([
                "userid" => $user_info["id"],
                "type" => 1,
                "appid" => $this->appid,
                "create_time" => date("Y-m-d H:i:s", time())
            ]);
        }
        return $user_logon;
    }'''


API_BAN_OLD = r'''            //判断账号是否被封禁
            if ($user_info["reasons"] == 1) {
                if ($user_info["reasons_time"] > time()) {
                    $this->json(403, "你账号已被封禁，封禁理由为：" . $user_info["reasons_ban"] . ",解封时间为" . date("Y-m-d H:i:s", $user_info["reasons_time"]));
                } else {
                    Db::name("user")->where("id", $user_info["id"])->update([
                        'reasons' => 0,
                        'reasons_time' => '',
                        'reasons_ban' => '',
                    ]);
                }
            }'''


API_BAN_QQ_OLD = r'''            //判断账号是否被封禁
            if ($user_info["reasons"] == 1) {
                if ($user_info["reasons_time"] > time()) {
                    $this->json(403, "你账号已被封禁，封禁理由为：" . $user_info["reasons_ban"] . ",解封时间为" . $user_info["reasons_time"]);
                } else {
                    Db::name("user")->where("id", $user_info["id"])->update([
                        'reasons' => 1,
                        'reasons_time' => 0,
                        'reasons_ban' => ""
                    ]);
                }
            }'''


API_BAN_NEW = r'''            //判断账号是否被封禁
            $this->blinRejectBannedUser($user_info);'''


ADMIN_LOCK_METHOD = r'''
    public function set_wallet_lock()
    {
        if (!Request::isAjax()) return $this->error("请求方式错误");
        $id = intval(input("id"));
        $locked = intval(input("locked")) == 1 ? 1 : 0;
        if ($id <= 0) return $this->error("请选择用户");
        $this->blinEnsurePaymentPasswordAdminColumns();
        $user = Db::name("user")->where("id", $id)->find();
        if (!$user) return $this->error("用户不存在");
        $this->blinRequireApp($user["appid"]);
        Db::name("user")->where("id", $id)->update([
            "wallet_locked" => $locked,
            "wallet_locked_time" => $locked ? time() : 0,
            "pay_password_error_count" => $locked ? intval(isset($user["pay_password_error_count"]) ? $user["pay_password_error_count"] : 0) : 0,
        ]);
        return $this->success($locked ? "钱包已锁定" : "钱包已解锁");
    }
'''


def patch_base():
    before = read(BASE)
    after = before
    after = insert_after(after, "    }\n\n\n    //获取APP信息", "\n" + BAN_HELPER, "base ban helper")
    after = replace_method(after, "public function getUserLogonInfoByUsertoken", GET_USER_METHOD)
    write_if_changed(BASE, before, after, "ban_wallet_base")


def patch_api():
    before = read(API)
    after = before
    after = insert_after(after, "class Api extends BaseController\n{\n", BAN_HELPER, "api ban helper")
    while API_BAN_OLD in after:
        after = after.replace(API_BAN_OLD, API_BAN_NEW, 1)
    after = after.replace(API_BAN_QQ_OLD, API_BAN_NEW, 1)
    write_if_changed(API, before, after, "ban_wallet_api")


def patch_user_controller():
    before = read(USER)
    after = before
    after = after.replace(
        "public $no_need_right = ['obtain_user_action_logs', 'clear_pay_password'];",
        "public $no_need_right = ['obtain_user_action_logs', 'clear_pay_password', 'set_wallet_lock'];",
    )
    after = insert_after(
        after,
        "    public function clear_pay_password()\n    {\n        if (!Request::isAjax()) return $this->error(\"请求方式错误\");\n        $id = intval(input(\"id\"));\n        if ($id <= 0) return $this->error(\"请选择用户\");\n        $this->blinEnsurePaymentPasswordAdminColumns();\n        $user = Db::name(\"user\")->where(\"id\", $id)->find();\n        if (!$user) return $this->error(\"用户不存在\");\n        $this->blinRequireApp($user[\"appid\"]);\n        Db::name(\"user\")->where(\"id\", $id)->update([\n            \"pay_password_hash\" => \"\",\n            \"pay_password_error_count\" => 0,\n            \"wallet_locked\" => 0,\n            \"wallet_locked_time\" => 0,\n            \"pay_password_update_time\" => 0,\n        ]);\n        return $this->success(\"支付密码已清除\");\n    }\n",
        ADMIN_LOCK_METHOD,
        "admin lock method",
    )
    write_if_changed(USER, before, after, "ban_wallet_user")


def patch_user_index():
    before = read(USER_INDEX)
    after = before
    after = replace_once(
        after,
        """                'click .clear-pay-btn': function (event, value, row, index) {
                    clearPayPassword(row.id, row.username);
                }""",
        """                'click .clear-pay-btn': function (event, value, row, index) {
                    clearPayPassword(row.id, row.username);
                },
                'click .wallet-lock-btn': function (event, value, row, index) {
                    setWalletLock(row.id, row.username, row.wallet_locked == 1 ? 0 : 1);
                }""",
        "wallet lock event",
    )
    after = replace_once(
        after,
        """            html += '<a href="#!" class="btn btn-sm btn-warning me-1 clear-pay-btn" title="清除支付密码并解锁钱包" data-bs-toggle="tooltip"><i class="mdi mdi-lock-reset"></i></a>';""",
        """            if (row.wallet_locked == 1) {
                html += '<a href="#!" class="btn btn-sm btn-success me-1 wallet-lock-btn" title="解锁钱包" data-bs-toggle="tooltip"><i class="mdi mdi-lock-open-variant"></i></a>';
            } else {
                html += '<a href="#!" class="btn btn-sm btn-danger me-1 wallet-lock-btn" title="锁定钱包" data-bs-toggle="tooltip"><i class="mdi mdi-lock"></i></a>';
            }
            html += '<a href="#!" class="btn btn-sm btn-warning me-1 clear-pay-btn" title="清除支付密码并解锁钱包" data-bs-toggle="tooltip"><i class="mdi mdi-lock-reset"></i></a>';""",
        "wallet lock button",
    )
    after = insert_after(
        after,
        """    function clearPayPassword(id, username) {
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
""",
        r'''

    function setWalletLock(id, username, locked) {
        layer.confirm("确定" + (locked == 1 ? "锁定" : "解锁") + " " + username + " 的钱包？", {
            title: locked == 1 ? "锁定钱包" : "解锁钱包",
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
                url: '{:url("set_wallet_lock")}',
                data: { id: id, locked: locked },
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
        "wallet lock js",
    )
    write_if_changed(USER_INDEX, before, after, "ban_wallet_user_view")


def main():
    patch_base()
    patch_api()
    patch_user_controller()
    patch_user_index()
    print("PATCHED_BAN_WALLET_LOCK")


if __name__ == "__main__":
    main()
