#!/usr/bin/env python3
"""Add per-admin app scope, frontend user binding, and IM system-user sync."""

from datetime import datetime
from pathlib import Path
import os
import re
import subprocess


ROOT = Path("/www/wwwroot/blinlin")
BACKEND = ROOT / "application/admin/controller/Backend.php"
LOGIN = ROOT / "application/admin/controller/Login.php"
ADMIN = ROOT / "application/admin/controller/Admin.php"
APP = ROOT / "application/admin/controller/App.php"
USER = ROOT / "application/admin/controller/User.php"
IM = ROOT / "application/admin/controller/Im.php"
ADMIN_INDEX = ROOT / "application/admin/view/admin/index.html"


def backup(path, suffix):
    target = path.with_name(
        f"{path.name}.bak_{suffix}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    target.write_text(path.read_text(errors="ignore"))
    return target


def save_if_changed(path, original, source, suffix):
    if source == original:
        return False
    print("PATCH_BACKUP", backup(path, suffix))
    path.write_text(source)
    print("PATCHED", path)
    return True


def replace_once(source, old, new, label):
    if new in source:
        return source
    if old not in source:
        raise SystemExit(f"MARKER_NOT_FOUND:{label}")
    return source.replace(old, new, 1)


def insert_before_last_class_brace(source, block, marker):
    if marker in source:
        return source
    pos = source.rfind("\n}")
    if pos == -1:
        raise SystemExit(f"CLASS_END_NOT_FOUND:{marker}")
    return source[:pos] + "\n" + block + source[pos:]


def db_config():
    values = {
        "hostname": "127.0.0.1",
        "database": "blinlin",
        "username": "root",
        "password": "",
        "hostport": "3306",
    }
    env = ROOT / ".env"
    section = ""
    for raw in env.read_text(errors="ignore").splitlines():
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
        if key == "hostname":
            values["hostname"] = value
        elif key == "database":
            values["database"] = value
        elif key == "username":
            values["username"] = value
        elif key == "password":
            values["password"] = value
        elif key == "hostport":
            values["hostport"] = value
    return values


def mysql(args, env=None):
    config = db_config()
    run_env = os.environ.copy()
    run_env["MYSQL_PWD"] = config["password"]
    if env:
        run_env.update(env)
    cmd = [
        "mysql",
        f"-h{config['hostname']}",
        f"-u{config['username']}",
        f"-P{config.get('hostport') or '3306'}",
        config["database"],
        *args,
    ]
    return subprocess.run(
        cmd,
        universal_newlines=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=run_env,
        check=False,
    )


def patch_database():
    columns = {
        "managed_appids": "ALTER TABLE `mr_admin` ADD COLUMN `managed_appids` text NULL AFTER `role_id`",
        "front_appid": "ALTER TABLE `mr_admin` ADD COLUMN `front_appid` bigint(20) NOT NULL DEFAULT 0 AFTER `managed_appids`",
        "front_user_id": "ALTER TABLE `mr_admin` ADD COLUMN `front_user_id` bigint(20) NOT NULL DEFAULT 0 AFTER `front_appid`",
        "im_system_user": "ALTER TABLE `mr_admin` ADD COLUMN `im_system_user` tinyint(1) NOT NULL DEFAULT 0 AFTER `front_user_id`",
    }
    for column, sql in columns.items():
        check = mysql(["-Nse", f"SHOW COLUMNS FROM `mr_admin` LIKE '{column}'"])
        if check.returncode != 0:
            raise SystemExit(check.stderr.strip() or f"MYSQL_CHECK_FAILED:{column}")
        if check.stdout.strip():
            continue
        run = mysql(["-e", sql])
        if run.returncode != 0:
            raise SystemExit(run.stderr.strip() or f"MYSQL_ALTER_FAILED:{column}")
        print("DB_ADDED", column)


BACKEND_HELPERS = r'''
    // blin-admin-app-scope: per-admin application data isolation.
    protected function blinCurrentAdminFull()
    {
        $id = isset($this->admin_info["id"]) ? intval($this->admin_info["id"]) : 0;
        if ($id <= 0) return [];
        $admin = Db::name("admin")->where("id", $id)->find();
        return $admin ? $admin : [];
    }

    protected function blinIsSuperAdmin()
    {
        $admin = $this->blinCurrentAdminFull();
        if (!$admin) return false;
        if (isset($admin["id"]) && intval($admin["id"]) === 1) return true;
        if (!isset($admin["role_id"]) || $admin["role_id"] === null || $admin["role_id"] === "") return true;
        return intval($admin["role_id"]) === 0;
    }

    protected function blinManagedAppIdsFromRaw($raw)
    {
        if (is_array($raw)) {
            $items = $raw;
        } else {
            $items = preg_split("/[,，\s]+/", strval($raw));
        }
        $ids = [];
        foreach ($items as $item) {
            $id = intval($item);
            if ($id > 0) $ids[] = $id;
        }
        return array_values(array_unique($ids));
    }

    protected function blinAdminAppIds()
    {
        if ($this->blinIsSuperAdmin()) return [];
        $admin = $this->blinCurrentAdminFull();
        $ids = $this->blinManagedAppIdsFromRaw(isset($admin["managed_appids"]) ? $admin["managed_appids"] : "");
        $frontAppid = isset($admin["front_appid"]) ? intval($admin["front_appid"]) : 0;
        if ($frontAppid > 0) $ids[] = $frontAppid;
        return array_values(array_unique($ids));
    }

    protected function blinAppScopeSql($alias = "")
    {
        if ($this->blinIsSuperAdmin()) return "";
        $ids = $this->blinAdminAppIds();
        if (!$ids) return " and 1=0";
        $field = ($alias !== "" ? $alias . "." : "") . "appid";
        return " and " . $field . " in (" . implode(",", $ids) . ")";
    }

    protected function blinScopeQuery($query, $field = "appid")
    {
        if ($this->blinIsSuperAdmin()) return $query;
        $ids = $this->blinAdminAppIds();
        if (!$ids) return $query->where("1=0");
        return $query->whereIn($field, $ids);
    }

    protected function blinAppAllowed($appid)
    {
        $appid = intval($appid);
        if ($appid <= 0) return false;
        if ($this->blinIsSuperAdmin()) return true;
        return in_array($appid, $this->blinAdminAppIds());
    }

    protected function blinRequireApp($appid)
    {
        $appid = intval($appid);
        if (!$this->blinAppAllowed($appid)) {
            if ($this->request->isAjax()) $this->error("无权管理该应用");
            abort(403, "无权管理该应用");
        }
        return $appid;
    }

    protected function blinScopedAppList()
    {
        $query = Db::name("app")->field("appid,appname,appicon");
        $this->blinScopeQuery($query, "appid");
        return $query->order("appid", "asc")->select();
    }

    protected function blinAppendAdminAppId($adminId, $appid)
    {
        $adminId = intval($adminId);
        $appid = intval($appid);
        if ($adminId <= 0 || $appid <= 0) return;
        $admin = Db::name("admin")->where("id", $adminId)->find();
        if (!$admin || intval($admin["role_id"]) === 0) return;
        $ids = $this->blinManagedAppIdsFromRaw(isset($admin["managed_appids"]) ? $admin["managed_appids"] : "");
        if (!in_array($appid, $ids)) $ids[] = $appid;
        Db::name("admin")->where("id", $adminId)->update(["managed_appids" => implode(",", $ids)]);
    }

    protected function blinUidAppid($uid)
    {
        $uid = trim(strval($uid));
        if ($uid === "") return 0;
        if (strpos($uid, "_") !== false) {
            $parts = explode("_", $uid);
            return intval($parts[0]);
        }
        return 0;
    }

    protected function blinUidAllowed($uid)
    {
        if ($this->blinIsSuperAdmin()) return true;
        $appid = $this->blinUidAppid($uid);
        return $appid > 0 && in_array($appid, $this->blinAdminAppIds());
    }

    protected function blinRequireUid($uid)
    {
        if (!$this->blinUidAllowed($uid)) {
            if ($this->request->isAjax()) $this->error("无权管理该IM用户");
            abort(403, "无权管理该IM用户");
        }
        return $uid;
    }

    protected function blinFilterUids($uids)
    {
        if ($this->blinIsSuperAdmin()) return $uids;
        $result = [];
        foreach ($uids as $uid) {
            if ($this->blinUidAllowed($uid)) $result[] = $uid;
        }
        return $result;
    }
'''


ADMIN_HELPERS = r'''
    // blin-admin-front-user: bind backend admin to a frontend IM user.
    protected function blinAdminPostAppids()
    {
        $raw = input("post.managed_appids/a", []);
        if (!$raw) $raw = input("post.managed_appids", "");
        $ids = $this->blinManagedAppIdsFromRaw($raw);
        foreach ($ids as $appid) {
            $this->blinRequireApp($appid);
        }
        return implode(",", $ids);
    }

    protected function blinSyncAdminFrontUser($adminId, $plainPassword = "", $oldAdmin = null)
    {
        $admin = Db::name("admin")->where("id", intval($adminId))->find();
        if (!$admin) return 0;
        $frontAppid = intval(isset($admin["front_appid"]) ? $admin["front_appid"] : 0);
        if ($frontAppid <= 0) return 0;
        $this->blinRequireApp($frontAppid);
        $appInfo = Db::name("app")->where("appid", $frontAppid)->find();
        if (!$appInfo) $this->error("前端应用不存在");

        $frontUserId = intval(isset($admin["front_user_id"]) ? $admin["front_user_id"] : 0);
        $user = $frontUserId > 0 ? Db::name("user")->where("id", $frontUserId)->where("appid", $frontAppid)->find() : null;
        if (!$user) {
            $user = Db::name("user")->where("appid", $frontAppid)->where("username", $admin["username"])->find();
        }

        $avatar = isset($admin["avatar"]) && $admin["avatar"] !== "" ? $admin["avatar"] : "/static/images/initial_photo/user.png";
        $update = [
            "nickname" => $admin["nickname"],
            "usertx" => $avatar,
            "reasons" => 0,
        ];
        if ($plainPassword !== "") {
            $salt = getRandChar(6);
            $update["salt"] = $salt;
            $update["password"] = md5($plainPassword . $salt);
        }

        if ($user) {
            Db::name("user")->where("id", $user["id"])->update($update);
            $frontUserId = intval($user["id"]);
        } else {
            if ($plainPassword === "") $this->error("创建前端用户需要填写管理员密码");
            $userinfo = json_decode($appInfo["userinfo_configuration"], true);
            if (!is_array($userinfo)) $userinfo = [];
            $registration = json_decode($appInfo["registration_configuration"], true);
            if (!is_array($registration)) $registration = [];
            $frontUser = array_merge($update, [
                "appid" => $frontAppid,
                "username" => $admin["username"],
                "money" => intval(isset($registration["money"]) ? $registration["money"] : 0),
                "integral" => intval(isset($registration["integral"]) ? $registration["integral"] : 0),
                "viptime" => time() + intval(isset($registration["vip"]) ? $registration["vip"] : 0),
                "userbg" => isset($userinfo["userbg"]) ? $userinfo["userbg"] : "",
                "signature" => isset($userinfo["signature"]) ? $userinfo["signature"] : "",
                "create_time" => date("Y-m-d H:i:s", time()),
                "register_ip" => get_client_ip(),
                "invitecode" => function_exists("enerate_invitation_code") ? enerate_invitation_code() : getRandChar(8),
            ]);
            $frontUserId = Db::name("user")->insertGetId($frontUser);
        }

        Db::name("admin")->where("id", intval($adminId))->update(["front_user_id" => $frontUserId]);
        $uid = $frontAppid . "_" . $frontUserId;
        $isSystemUser = intval(isset($admin["im_system_user"]) ? $admin["im_system_user"] : 0) === 1;
        if (config("wukongim.enable")) {
            try {
                $wkim = new \app\common\tool\WukongIM();
                if (is_array($oldAdmin)) {
                    $oldAppid = intval(isset($oldAdmin["front_appid"]) ? $oldAdmin["front_appid"] : 0);
                    $oldUserId = intval(isset($oldAdmin["front_user_id"]) ? $oldAdmin["front_user_id"] : 0);
                    if ($oldAppid > 0 && $oldUserId > 0) {
                        $oldUid = $oldAppid . "_" . $oldUserId;
                        if (!$isSystemUser || $oldUid !== $uid) $wkim->removeSystemUids([$oldUid]);
                    }
                }
                if ($isSystemUser) $wkim->addSystemUids([$uid]);
            } catch (\Exception $e) {
                // 系统UID写入失败不阻断后台账号保存，IM管理页可再次同步。
            }
        }
        return $frontUserId;
    }
'''


def patch_backend():
    source = BACKEND.read_text(errors="ignore")
    original = source
    source = insert_before_last_class_brace(source, BACKEND_HELPERS, "blin-admin-app-scope")
    source = source.replace(
        "session('admin', $admin);",
        "session('admin', $admin);\n                $this->admin_info = $admin;",
    )
    save_if_changed(BACKEND, original, source, "admin_app_scope_backend")


def patch_login():
    source = LOGIN.read_text(errors="ignore")
    original = source
    source = replace_once(
        source,
        """                'token' => $token,
            ];""",
        """                'token' => $token,
                'role_id' => $admin['role_id'],
                'managed_appids' => isset($admin['managed_appids']) ? $admin['managed_appids'] : '',
                'front_appid' => isset($admin['front_appid']) ? $admin['front_appid'] : 0,
                'front_user_id' => isset($admin['front_user_id']) ? $admin['front_user_id'] : 0,
                'im_system_user' => isset($admin['im_system_user']) ? $admin['im_system_user'] : 0,
            ];""",
        "login_session_admin_scope",
    )
    source = source.replace("Cookie::set('token', $admin['token'], $time);", "Cookie::set('token', $token, $time);")
    save_if_changed(LOGIN, original, source, "admin_app_scope_login")


def patch_admin_controller():
    source = ADMIN.read_text(errors="ignore")
    original = source
    source = insert_before_last_class_brace(source, ADMIN_HELPERS, "blin-admin-front-user")
    source = replace_once(
        source,
        "->field('ad.id,ad.username,ad.avatar,ad.nickname,ad.status,ad.create_time,ad.update_time,ad.role_id,ar.role_name')",
        "->field('ad.id,ad.username,ad.avatar,ad.nickname,ad.status,ad.create_time,ad.update_time,ad.role_id,ad.managed_appids,ad.front_appid,ad.front_user_id,ad.im_system_user,ar.role_name')",
        "admin_index_field_scope",
    )
    source = replace_once(
        source,
        "$this->assign('role_list', $role_list);\n        return $this->fetch();",
        "$this->assign('role_list', $role_list);\n        $this->assign('app_list', $this->blinScopedAppList());\n        return $this->fetch();",
        "admin_index_app_list",
    )
    source = replace_once(
        source,
        """            $data['avatar'] = '/static/images/initial_photo/user.png';
            $data['password'] = md5($data['password']);
            $data['token'] = md5($data['username'] . $data['password'] . time());
            $data['create_time'] = date('Y-m-d H:i:s', time());
            $data['update_time'] = date('Y-m-d H:i:s', time());
            Db::name('admin')->insert($data);
            return $this->success('添加成功');""",
        """            $plainPassword = $data['password'];
            $data['managed_appids'] = $this->blinAdminPostAppids();
            $data['front_appid'] = intval(isset($data['front_appid']) ? $data['front_appid'] : 0);
            if ($data['front_appid'] > 0) $this->blinRequireApp($data['front_appid']);
            $data['front_user_id'] = intval(isset($data['front_user_id']) ? $data['front_user_id'] : 0);
            $data['im_system_user'] = isset($data['im_system_user']) ? intval($data['im_system_user']) : 0;
            $data['avatar'] = '/static/images/initial_photo/user.png';
            $salt = getRandChar(6);
            $data['salt'] = $salt;
            $data['password'] = md5($plainPassword . $salt);
            $data['token'] = md5($data['username'] . $data['password'] . time());
            $data['create_time'] = date('Y-m-d H:i:s', time());
            $data['update_time'] = date('Y-m-d H:i:s', time());
            $adminId = Db::name('admin')->insertGetId($data);
            $this->blinSyncAdminFrontUser($adminId, $plainPassword);
            return $this->success('添加成功');""",
        "admin_add_front_user",
    )
    source = replace_once(
        source,
        """            $data['update_time'] = date('Y-m-d H:i:s', time());
            //如果密码为空则不修改
            if ($data["password"] == "") {""",
        """            $plainPassword = $data['password'];
            $data['managed_appids'] = $this->blinAdminPostAppids();
            $data['front_appid'] = intval(isset($data['front_appid']) ? $data['front_appid'] : 0);
            if ($data['front_appid'] > 0) $this->blinRequireApp($data['front_appid']);
            $data['front_user_id'] = intval(isset($data['front_user_id']) ? $data['front_user_id'] : 0);
            $data['im_system_user'] = isset($data['im_system_user']) ? intval($data['im_system_user']) : 0;
            $data['update_time'] = date('Y-m-d H:i:s', time());
            //如果密码为空则不修改
            if ($data["password"] == "") {""",
        "admin_edit_scope_fields",
    )
    source = source.replace(
        """            if ($id == $this->admin_info["id"]) {
                $data["token"] = md5($data['username'] . $data['password'] . time());
            }
            //修改
            Db::name('admin')->where("id", $id)->update($data);
            $this->getPermission(1, $id);
            return $this->success('编辑成功');""",
        """            if ($id == $this->admin_info["id"] && isset($data['password'])) {
                $data["token"] = md5($data['username'] . $data['password'] . time());
            }
            $beforeAdmin = Db::name('admin')->where("id", $id)->find();
            //修改
            Db::name('admin')->where("id", $id)->update($data);
            $this->blinSyncAdminFrontUser($id, $plainPassword, $beforeAdmin);
            $this->getPermission(1, $id);
            return $this->success('编辑成功');""",
    )
    save_if_changed(ADMIN, original, source, "admin_app_scope_admin")


def patch_admin_view():
    source = ADMIN_INDEX.read_text(errors="ignore")
    original = source
    source = replace_once(
        source,
        """                                    <th>所属组别</th>
                                    <th>状态</th>""",
        """                                    <th>所属组别</th>
                                    <th>管理应用</th>
                                    <th>前端IM用户</th>
                                    <th>状态</th>""",
        "admin_view_table_head",
    )
    source = replace_once(
        source,
        """                                    <td>{$vo.role_name == null ? "超级管理员" : $vo.role_name}</td>
                                    <td>""",
        """                                    <td>{$vo.role_name == null ? "超级管理员" : $vo.role_name}</td>
                                    <td>{$vo.managed_appids ? $vo.managed_appids : '全部'}</td>
                                    <td>{if $vo.front_appid > 0}{$vo.front_appid}_{$vo.front_user_id}{if $vo.im_system_user == 1}<span class="badge bg-primary ms-1">系统</span>{/if}{else /}-{/if}</td>
                                    <td>""",
        "admin_view_table_cells",
    )
    source = replace_once(
        source,
        """                    <div class="mb-3">
                        <label for="name" class="form-label">昵称</label>
                        <input type="text" class="form-control" id="nickname" name="nickname" placeholder="请输入昵称">
                    </div>
                    <div class="mb-3">""",
        """                    <div class="mb-3">
                        <label for="name" class="form-label">昵称</label>
                        <input type="text" class="form-control" id="nickname" name="nickname" placeholder="请输入昵称">
                    </div>
                    <div class="mb-3">
                        <label class="form-label">可管理应用</label>
                        <select class="form-select" id="managed_appids" name="managed_appids[]" multiple size="4">
                            {volist name="app_list" id="app"}
                            <option value="{$app.appid}">{$app.appname}（{$app.appid}）</option>
                            {/volist}
                        </select>
                        <small class="text-muted">超级管理员不受限制；普通管理员只能管理选中的应用。</small>
                    </div>
                    <div class="mb-3">
                        <label class="form-label">前端登录应用</label>
                        <select class="form-select" id="front_appid" name="front_appid">
                            <option value="0">不绑定前端用户</option>
                            {volist name="app_list" id="app"}
                            <option value="{$app.appid}">{$app.appname}（{$app.appid}）</option>
                            {/volist}
                        </select>
                    </div>
                    <div class="mb-3">
                        <label class="form-label">前端用户ID</label>
                        <input type="number" class="form-control" id="front_user_id" name="front_user_id" value="0" placeholder="留空自动按管理员账号创建/绑定">
                    </div>
                    <div class="mb-3">
                        <div class="blin-setting-row blin-setting-row-modal">
                            <div class="blin-setting-copy">
                                <span class="blin-setting-title">IM系统用户</span>
                                <small class="blin-setting-desc">开启后会把前端UID加入悟空IM系统用户列表。</small>
                            </div>
                            <div class="blin-segmented-switch" role="group" aria-label="IM系统用户">
                                <input type="radio" id="im_system_user_on" value="1" name="im_system_user" class="btn-check" autocomplete="off">
                                <label class="blin-switch-choice blin-switch-choice-on" for="im_system_user_on"><i class="mdi mdi-check-circle-outline"></i>开启</label>
                                <input type="radio" id="im_system_user_off" value="0" name="im_system_user" class="btn-check" autocomplete="off" checked>
                                <label class="blin-switch-choice blin-switch-choice-off" for="im_system_user_off"><i class="mdi mdi-close-circle-outline"></i>关闭</label>
                            </div>
                        </div>
                    </div>
                    <div class="mb-3">""",
        "admin_view_modal_app_scope",
    )
    source = replace_once(
        source,
        """            thisForm.setForm(data);
            $("#password").attr('placeholder', '不修改密码请留空');""",
        """            thisForm.setForm(data);
            var appids = data.managed_appids ? String(data.managed_appids).split(',') : [];
            $("#managed_appids").val(appids);
            $("#front_appid").val(data.front_appid || 0);
            $("#front_user_id").val(data.front_user_id || 0);
            $("input[name=im_system_user][value='" + (data.im_system_user || 0) + "']").prop("checked", true);
            $("#password").attr('placeholder', '不修改密码请留空');""",
        "admin_view_js_edit_scope",
    )
    source = replace_once(
        source,
        """            $("#password").attr('placeholder', '请输入密码');
            $('#add_edit .modal-title').html('新增');""",
        """            $("#managed_appids").val([]);
            $("#front_appid").val(0);
            $("#front_user_id").val(0);
            $("input[name=im_system_user][value='0']").prop("checked", true);
            $("#password").attr('placeholder', '请输入密码');
            $('#add_edit .modal-title').html('新增');""",
        "admin_view_js_add_scope",
    )
    save_if_changed(ADMIN_INDEX, original, source, "admin_app_scope_admin_view")


def patch_app_controller():
    source = APP.read_text(errors="ignore")
    original = source
    source = replace_once(source, '$where = " 1 ";', '$where = " 1 ";' + "\n            $where .= $this->blinAppScopeSql();", "app_index_scope")
    source = replace_once(
        source,
        """            if ($appid) {
                //在更新表插入一条""",
        """            if ($appid) {
                if (!$this->blinIsSuperAdmin()) $this->blinAppendAdminAppId($this->admin_info["id"], $appid);
                //在更新表插入一条""",
        "app_add_assign_scope",
    )
    source = replace_once(
        source,
        """        foreach ($appid_array as $key => $value) {
            Db::name("app")->where(["appid" => $value])->update(["app_switch" => $app_switch]);""",
        """        foreach ($appid_array as $key => $value) {
            $this->blinRequireApp($value);
            Db::name("app")->where(["appid" => $value])->update(["app_switch" => $app_switch]);""",
        "app_switch_require",
    )
    source = replace_once(
        source,
        """        foreach ($appid_array as $key => $value) {
            $database = Env::get('database.DATABASE', 'root');""",
        """        foreach ($appid_array as $key => $value) {
            $this->blinRequireApp($value);
            $database = Env::get('database.DATABASE', 'root');""",
        "app_delete_require",
    )
    source = replace_once(
        source,
        """            // echo json_encode($update_data);die();
            Db::name("app")->where("appid=" . $data["appid"])->update($update_data);""",
        """            // echo json_encode($update_data);die();
            $this->blinRequireApp($data["appid"]);
            Db::name("app")->where("appid=" . $data["appid"])->update($update_data);""",
        "app_edit_post_require",
    )
    source = replace_once(
        source,
        """            if ($appid == "") {
                return $this->error("服务器错误！");
            }
            $result = Db::name("app")->where("appid={$appid}")->find();""",
        """            if ($appid == "") {
                return $this->error("服务器错误！");
            }
            $this->blinRequireApp($appid);
            $result = Db::name("app")->where("appid={$appid}")->find();""",
        "app_edit_get_require",
    )
    source = replace_once(source, '$where = " m.type = 0 ";', '$where = " m.type = 0 ";' + "\n        $where .= $this->blinAppScopeSql('m');", "app_messages_scope")
    source = replace_once(
        source,
        """        if ($data["title"] == "" || $data["content"] == "" || $data["appid"] == "") {
            return $this->error("请填写完整");
        }""",
        """        if ($data["title"] == "" || $data["content"] == "" || $data["appid"] == "") {
            return $this->error("请填写完整");
        }
        $this->blinRequireApp($data["appid"]);""",
        "app_add_message_require",
    )
    source = replace_once(
        source,
        """        foreach ($id as $key => $value) {
            Db::name("message_notification")->where("id", "=", $value)->delete();""",
        """        foreach ($id as $key => $value) {
            $row = Db::name("message_notification")->where("id", "=", $value)->find();
            if ($row) $this->blinRequireApp($row["appid"]);
            Db::name("message_notification")->where("id", "=", $value)->delete();""",
        "app_delete_message_require",
    )
    source = replace_once(source, '$where = " 1 ";' + "\n            if ($name) {", '$where = " 1 ";' + "\n            $where .= $this->blinAppScopeSql('m');\n            if ($name) {", "app_exten_scope")
    source = replace_once(
        source,
        """            if ($data["name"] == "" || $data["data"] == "" || $data["note"] == "" || $data["appid"] == "") {
                return $this->error("请填写完整");
            }""",
        """            if ($data["name"] == "" || $data["data"] == "" || $data["note"] == "" || $data["appid"] == "") {
                return $this->error("请填写完整");
            }
            $this->blinRequireApp($data["appid"]);""",
        "app_exten_add_require",
    )
    save_if_changed(APP, original, source, "admin_app_scope_app")


def patch_user_controller():
    source = USER.read_text(errors="ignore")
    original = source
    source = replace_once(source, '$where = " 1 ";', '$where = " 1 ";' + "\n            $where .= $this->blinAppScopeSql('u');", "user_index_scope")
    source = replace_once(
        source,
        """            if ($data["username"] == "" || $data["password"] == "" || $data["appid"] == "") {
                return $this->error("请输入完整！");
            }""",
        """            if ($data["username"] == "" || $data["password"] == "" || $data["appid"] == "") {
                return $this->error("请输入完整！");
            }
            $this->blinRequireApp($data["appid"]);""",
        "user_add_require",
    )
    source = replace_once(
        source,
        """        foreach ($id as $key => $value) {
            $updateData["reasons"] = $userstate;""",
        """        foreach ($id as $key => $value) {
            $user = Db::name("user")->where("id", "=", $value)->find();
            if ($user) $this->blinRequireApp($user["appid"]);
            $updateData["reasons"] = $userstate;""",
        "user_status_require",
    )
    source = replace_once(
        source,
        """            foreach ($id as $key => $value) {
                //删除用户其他信息
                Db::name("user")->where("id", "=", $value)->delete();""",
        """            foreach ($id as $key => $value) {
                $user = Db::name("user")->where("id", "=", $value)->find();
                if ($user) $this->blinRequireApp($user["appid"]);
                //删除用户其他信息
                Db::name("user")->where("id", "=", $value)->delete();""",
        "user_delete_require",
    )
    source = replace_once(
        source,
        """            if (!$is_user_info) {
                return $this->error("系统错误！");
            }""",
        """            if (!$is_user_info) {
                return $this->error("系统错误！");
            }
            $this->blinRequireApp($is_user_info["appid"]);""",
        "user_edit_post_require",
    )
    source = replace_once(
        source,
        """            if ($result == null) {
                $this->error("服务器错误");
            }""",
        """            if ($result == null) {
                $this->error("服务器错误");
            }
            $this->blinRequireApp($result["appid"]);""",
        "user_edit_get_require",
    )
    source = replace_once(source, '$where = " 1 ";' + "\n            if (input(\"audit_status\")", '$where = " 1 ";' + "\n            $where .= $this->blinAppScopeSql('a');\n            if (input(\"audit_status\")", "user_audit_scope")
    source = replace_once(
        source,
        """        $user_all_info = Db::name('user')->where("id", $audit_info['userid'])->find();
        $data = [""",
        """        $user_all_info = Db::name('user')->where("id", $audit_info['userid'])->find();
        if ($user_all_info) $this->blinRequireApp($user_all_info["appid"]);
        $data = [""",
        "user_audit_action_require",
    )
    save_if_changed(USER, original, source, "admin_app_scope_user")


def patch_im_controller():
    source = IM.read_text(errors="ignore")
    original = source
    source = replace_once(
        source,
        """            $query = Db::name('im_message_log');
            $appid = input('appid');
            if ($appid !== '') $query->where('appid', intval($appid));""",
        """            $query = Db::name('im_message_log');
            $appid = input('appid');
            if ($appid !== '') {
                $this->blinRequireApp($appid);
                $query->where('appid', intval($appid));
            } else {
                $this->blinScopeQuery($query, 'appid');
            }""",
        "im_message_log_scope",
    )
    source = replace_once(
        source,
        """                    $appid = intval(input('appid') ?: 1);
                    $userId = intval(input('user_id'));""",
        """                    $appid = intval(input('appid') ?: 1);
                    $this->blinRequireApp($appid);
                    $userId = intval(input('user_id'));""",
        "im_user_info_app_scope",
    )
    source = replace_once(
        source,
        """                    $uids = $this->arr(input('uids'));
                    if (!$uids) return $this->imFail('请输入UID');
                    return $this->imOk('查询成功','',$wkim->getOnlineStatus($uids));""",
        """                    $uids = $this->blinFilterUids($this->arr(input('uids')));
                    if (!$uids) return $this->imFail('请输入有权限的UID');
                    return $this->imOk('查询成功','',$wkim->getOnlineStatus($uids));""",
        "im_online_uid_scope",
    )
    source = replace_once(
        source,
        """                    $uid = trim(input('uid'));
                    if ($uid === '') return $this->imFail('请输入UID');""",
        """                    $uid = trim(input('uid'));
                    if ($uid === '') return $this->imFail('请输入UID');
                    $this->blinRequireUid($uid);""",
        "im_kick_uid_scope",
    )
    source = source.replace(
        """                    $uid = trim(input('uid')); $token = trim(input('token'));
                    if ($uid === '' || $token === '') return $this->imFail('请输入UID和Token');""",
        """                    $uid = trim(input('uid')); $token = trim(input('token'));
                    if ($uid === '' || $token === '') return $this->imFail('请输入UID和Token');
                    $this->blinRequireUid($uid);""",
    )
    source = source.replace(
        """                if ($op === 'system_uids') return $this->imOk('查询成功','',$wkim->getSystemUids());
                if ($op === 'system_uids_add' || $op === 'system_uids_remove') {
                    $uids = $this->arr(input('uids'));
                    if (!$uids) return $this->imFail('请输入UID');
                    $rs = $op === 'system_uids_add' ? $wkim->addSystemUids($uids) : $wkim->removeSystemUids($uids);""",
        """                if ($op === 'system_uids') {
                    $rows = $wkim->getSystemUids();
                    if (!$this->blinIsSuperAdmin() && is_array($rows)) $rows = $this->blinFilterUids($rows);
                    return $this->imOk('查询成功','',$rows);
                }
                if ($op === 'system_uids_add' || $op === 'system_uids_remove') {
                    $uids = $this->blinFilterUids($this->arr(input('uids')));
                    if (!$uids) return $this->imFail('请输入有权限的UID');
                    $rs = $op === 'system_uids_add' ? $wkim->addSystemUids($uids) : $wkim->removeSystemUids($uids);""",
    )
    source = replace_once(
        source,
        """                    Db::name('im_message_log')->where('id',$id)->update(['status'=>3,'update_time'=>date('Y-m-d H:i:s')]);""",
        """                    $row = Db::name('im_message_log')->where('id',$id)->find();
                    if ($row) $this->blinRequireApp($row['appid']);
                    Db::name('im_message_log')->where('id',$id)->update(['status'=>3,'update_time'=>date('Y-m-d H:i:s')]);""",
        "im_delete_local_require",
    )
    source = replace_once(
        source,
        """        Db::name('im_message_log')->where('id',$id)->update(['status'=>intval(input('status')),'update_time'=>date('Y-m-d H:i:s')]);""",
        """        $row = Db::name('im_message_log')->where('id',$id)->find();
        if ($row) $this->blinRequireApp($row['appid']);
        Db::name('im_message_log')->where('id',$id)->update(['status'=>intval(input('status')),'update_time'=>date('Y-m-d H:i:s')]);""",
        "im_update_status_require",
    )
    source = replace_once(
        source,
        """            $total = Db::name($table)->count();
            $rows = Db::name($table)->order($order,'desc')->page($page,$limit)->select();""",
        """            $countQuery = Db::name($table);
            $rowQuery = Db::name($table);
            if (in_array($table, ['im_online_status','im_offline_message','im_message_log'])) {
                $this->blinScopeQuery($countQuery, 'appid');
                $this->blinScopeQuery($rowQuery, 'appid');
            }
            $total = $countQuery->count();
            $rows = $rowQuery->order($order,'desc')->page($page,$limit)->select();""",
        "im_simple_scope",
    )
    save_if_changed(IM, original, source, "admin_app_scope_im")


def main():
    patch_database()
    patch_backend()
    patch_login()
    patch_admin_controller()
    patch_admin_view()
    patch_app_controller()
    patch_user_controller()
    patch_im_controller()


if __name__ == "__main__":
    main()
