#!/usr/bin/env python3
"""Use collage avatars by default for newly created IM groups."""

from datetime import datetime
from pathlib import Path
import os
import re
import shutil
import subprocess


ROOT = Path("/www/wwwroot/blinlin")
APP = ROOT / "application/admin/controller/App.php"
BASE = ROOT / "application/api/controller/BaseController.php"
API = ROOT / "application/api/controller/Api.php"
TRAIT = ROOT / "application/api/controller/traits/ImApiTrait.php"
APP_EDIT = ROOT / "application/admin/view/app/edit.html"


def backup(path: Path, suffix: str) -> Path:
    target = path.with_name(f"{path.name}.bak_{suffix}_{datetime.now().strftime('%Y%m%d%H%M%S')}")
    shutil.copy2(path, target)
    return target


def save(path: Path, original: str, source: str, suffix: str) -> bool:
    if source == original:
        return False
    print("PATCH_BACKUP", backup(path, suffix))
    path.write_text(source)
    print("PATCHED", path)
    return True


def db_config() -> dict:
    values = {
        "hostname": "127.0.0.1",
        "database": "blinlin",
        "username": "root",
        "password": "",
        "hostport": "3306",
    }
    env_path = ROOT / ".env"
    section = ""
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


def mysql(sql: str) -> subprocess.CompletedProcess:
    config = db_config()
    env = os.environ.copy()
    env["MYSQL_PWD"] = config["password"]
    return subprocess.run(
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


def patch_database() -> None:
    run = mysql(
        """UPDATE `mr_app`
SET `im_configuration` = JSON_SET(
    CASE
        WHEN JSON_VALID(COALESCE(NULLIF(`im_configuration`, ''), '{}')) = 1
        THEN COALESCE(NULLIF(`im_configuration`, ''), '{}')
        ELSE '{}'
    END,
    '$.group_avatar_collage_switch',
    COALESCE(JSON_UNQUOTE(JSON_EXTRACT(
        CASE WHEN JSON_VALID(COALESCE(NULLIF(`im_configuration`, ''), '{}')) = 1
             THEN COALESCE(NULLIF(`im_configuration`, ''), '{}') ELSE '{}' END,
        '$.group_avatar_collage_switch'
    )), '0')
)"""
    )
    if run.returncode != 0:
        raise SystemExit(run.stderr.strip() or "PATCH_GROUP_AVATAR_COLLAGE_DB_FAILED")


def add_json_literal_default(source: str) -> str:
    if "group_avatar_collage_switch" in source:
        return source
    return re.sub(
        r"(\"im_configuration\"\s*=>\s*'\{)([^']*)(\}'\s*,)",
        lambda m: f'{m.group(1)}{m.group(2)},"group_avatar_collage_switch":"0"{m.group(3)}',
        source,
        count=1,
    )


def patch_app_controller() -> bool:
    source = APP.read_text(errors="ignore")
    original = source
    source = add_json_literal_default(source)
    if '"group_avatar_collage_switch" => isset($data["group_avatar_collage_switch"])' not in source:
        source = re.sub(
            r'("admin_app_message_switch"\s*=>\s*isset\(\$data\["admin_app_message_switch"\]\)\s*\?\s*intval\(\$data\["admin_app_message_switch"\]\)\s*:\s*1,\n)',
            r'\1                    "group_avatar_collage_switch" => isset($data["group_avatar_collage_switch"]) ? intval($data["group_avatar_collage_switch"]) : 0,\n',
            source,
            count=1,
        )
    if '"group_avatar_collage_switch" => 0' not in source:
        source = re.sub(
            r'("admin_app_message_switch"\s*=>\s*0,\n)',
            r'\1                    "group_avatar_collage_switch" => 0,\n',
            source,
            count=1,
        )
    return save(APP, original, source, "group_create_avatar_app")


def patch_base_controller() -> bool:
    source = BASE.read_text(errors="ignore")
    original = source
    if "group_avatar_collage_switch" not in source:
        source = re.sub(
            r'("admin_app_message_switch"\s*=>\s*["\']0["\'],\n)',
            r'\1                "group_avatar_collage_switch" => "0",\n',
            source,
            count=1,
        )
    return save(BASE, original, source, "group_create_avatar_base")


def patch_app_edit() -> bool:
    source = APP_EDIT.read_text(errors="ignore")
    original = source
    if "group_avatar_collage_switch" in source:
        return False
    block = '''                        <div class="blin-setting-row blin-group-avatar-collage-switch-card">
                            <div class="blin-setting-copy">
                                <span class="blin-setting-title">新群默认拼接头像</span>
                                <small class="blin-setting-desc">开启后，新建群未手动设置头像时自动使用群成员头像拼接；关闭后使用创建者头像作为群头像。</small>
                            </div>
                            <div class="blin-segmented-switch" role="group" aria-label="新群默认拼接头像">
                                <input type="radio" id="group_avatar_collage_switch_on" value="0" name="group_avatar_collage_switch" class="btn-check" autocomplete="off" {if $data.im_configuration.group_avatar_collage_switch==0} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-on" for="group_avatar_collage_switch_on"><i class="mdi mdi-check-circle-outline"></i>开启</label>
                                <input type="radio" id="group_avatar_collage_switch_off" value="1" name="group_avatar_collage_switch" class="btn-check" autocomplete="off" {if $data.im_configuration.group_avatar_collage_switch==1} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-off" for="group_avatar_collage_switch_off"><i class="mdi mdi-close-circle-outline"></i>关闭</label>
                            </div>
                        </div>
'''
    marker = '                        <div class="blin-setting-row blin-group-no-change-switch-card">'
    if marker in source:
        source = source.replace(marker, block + marker, 1)
    else:
        marker = '                        <div class="blin-setting-row blin-default-group-switch-card">'
        if marker not in source:
            raise SystemExit("APP_EDIT_GROUP_AVATAR_INSERT_MARKER_NOT_FOUND")
        source = source.replace(marker, block + marker, 1)
    return save(APP_EDIT, original, source, "group_create_avatar_view")


def find_method(source: str, signature: str):
    start = source.find(signature)
    if start < 0:
        raise SystemExit(f"METHOD_NOT_FOUND:{signature}")
    brace = source.find("{", start)
    if brace < 0:
        raise SystemExit(f"METHOD_BRACE_NOT_FOUND:{signature}")
    depth = 0
    in_single = False
    in_double = False
    escape = False
    i = brace
    while i < len(source):
        ch = source[i]
        if escape:
            escape = False
            i += 1
            continue
        if ch == "\\" and (in_single or in_double):
            escape = True
            i += 1
            continue
        if ch == "'" and not in_double:
            in_single = not in_single
            i += 1
            continue
        if ch == '"' and not in_single:
            in_double = not in_double
            i += 1
            continue
        if not in_single and not in_double:
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    end = i + 1
                    if end < len(source) and source[end] == "\r":
                        end += 1
                    if end < len(source) and source[end] == "\n":
                        end += 1
                    return start, end
        i += 1
    raise SystemExit(f"METHOD_END_NOT_FOUND:{signature}")


def replace_method(source: str, signature: str, body: str) -> str:
    start, end = find_method(source, signature)
    current = source[start:end]
    if current.strip() == body.strip():
        return source
    return source[:start] + body.rstrip() + "\n" + source[end:]


AVATAR_HELPERS = r'''
    private function blinGroupAvatarCollageEnabled()
    {
        $config = [];
        if (isset($this->app_info["im_configuration"]) && is_array($this->app_info["im_configuration"])) {
            $config = $this->app_info["im_configuration"];
        } elseif (isset($this->app_info["im_configuration"]) && $this->app_info["im_configuration"]) {
            $decoded = json_decode($this->app_info["im_configuration"], true);
            if (is_array($decoded)) $config = $decoded;
        }
        return intval(isset($config["group_avatar_collage_switch"]) ? $config["group_avatar_collage_switch"] : 0) === 0;
    }

    private function blinCreatorAvatar($user)
    {
        if (isset($user["usertx"]) && trim(strval($user["usertx"])) !== "") return trim(strval($user["usertx"]));
        if (isset($user["avatar"]) && trim(strval($user["avatar"])) !== "") return trim(strval($user["avatar"]));
        if (isset($user["tx"]) && trim(strval($user["tx"])) !== "") return trim(strval($user["tx"]));
        return "";
    }

    private function blinApplyDefaultGroupAvatar($groupId, $requestAvatar, $creatorAvatar)
    {
        if (trim(strval($requestAvatar)) !== "") return trim(strval($requestAvatar));
        $fallback = trim(strval($creatorAvatar));
        if (!$this->blinGroupAvatarCollageEnabled()) return $fallback;
        if (!function_exists("imagecreatetruecolor") || !function_exists("imagejpeg")) return $fallback;
        try {
            $url = $this->blinBuildGroupAvatar(intval($groupId));
            if ($url !== "") {
                Db::name("im_groups")->where("appid", $this->appid)->where("id", intval($groupId))->update(["avatar"=>$url, "update_time"=>date("Y-m-d H:i:s")]);
                return $url;
            }
        } catch (\Exception $e) {}
        return $fallback;
    }
'''


API_CREATE = r'''    public function create_im_group()
    {
        $rule = ["usertoken|用户token" => "require", "name|群名称" => "require"];
        $data = input();
        $validate = new Validate($rule);
        if (!$validate->check($data)) $this->json(0, $validate->getError());
        $this->blinActionRateLimit("send_im_group_message");
        $user = $this->im_group_user();
        $this->ensure_im_group_tables();
        $memberIds = $this->blinGroupMemberIds(isset($data["member_ids"]) ? $data["member_ids"] : input("user_ids"));
        $validUsers = [];
        if ($memberIds) {
            $validUsers = Db::name("user")->where("appid", $this->appid)->whereIn("id", $memberIds)->column("id");
        }
        $now = date("Y-m-d H:i:s");
        $groupNo = "group_" . $this->appid . "_" . time() . "_" . mt_rand(1000, 9999);
        $requestAvatar = isset($data["avatar"]) ? trim(strval($data["avatar"])) : (isset($data["group_avatar"]) ? trim(strval($data["group_avatar"])) : "");
        $creatorAvatar = $this->blinCreatorAvatar($user);
        $avatar = $requestAvatar !== "" ? $requestAvatar : $creatorAvatar;
        $groupId = Db::name("im_groups")->insertGetId(["appid"=>$this->appid, "group_no"=>$groupNo, "name"=>trim(strval($data["name"])), "avatar"=>$avatar, "notice"=>trim(strval(isset($data["notice"]) ? $data["notice"] : "")), "owner_id"=>intval($user["id"]), "member_count"=>0, "status"=>1, "default_group"=>0, "create_time"=>$now, "update_time"=>$now]);
        $group = Db::name("im_groups")->where("id", $groupId)->find();
        $this->blinAddUserToGroup($group, intval($user["id"]), 2);
        foreach ($validUsers as $uid) $this->blinAddUserToGroup($group, intval($uid), 0);
        $avatar = $this->blinApplyDefaultGroupAvatar($groupId, $requestAvatar, $creatorAvatar);
        $group = Db::name("im_groups")->where("id", $groupId)->find();
        if ($group && $avatar !== "") $group["avatar"] = $avatar;
        $group["group_id"] = intval($group["id"]);
        $group["my_role"] = "owner";
        $this->json(1, "创建成功", $group);
    }'''


TRAIT_CREATE = r'''    public function create_im_group()
    {
        $data = input();
        $rule = ['usertoken|用户token' => 'require', 'name|群名称' => 'require'];
        $validate = new Validate($rule);
        if (!$validate->check($data)) { $this->json(0, $validate->getError()); }
        $user = $this->current_group_user();
        $this->ensure_im_group_tables();
        $idsRaw = isset($data['member_ids']) ? strval($data['member_ids']) : '';
        $memberIds = [];
        foreach (explode(',', $idsRaw) as $id) { $v = intval(trim($id)); if ($v > 0 && $v != intval($user['id'])) $memberIds[$v] = $v; }
        if (empty($memberIds)) { $this->json(0, '请选择群成员'); }
        $validUsers = Db::name('user')->where('appid', $this->appid)->where('id', 'in', array_values($memberIds))->column('id');
        if (empty($validUsers)) { $this->json(0, '群成员不存在'); }
        $now = date('Y-m-d H:i:s');
        $groupNo = 'group_' . $this->appid . '_' . time() . '_' . mt_rand(1000,9999);
        $name = trim(strval($data['name']));
        $requestAvatar = isset($data['avatar']) ? trim(strval($data['avatar'])) : (isset($data['group_avatar']) ? trim(strval($data['group_avatar'])) : '');
        $creatorAvatar = $this->blinCreatorAvatar($user);
        $avatar = $requestAvatar !== '' ? $requestAvatar : $creatorAvatar;
        $notice = isset($data['notice']) ? trim(strval($data['notice'])) : '';
        $groupId = Db::name('im_groups')->insertGetId(['appid'=>$this->appid, 'group_no'=>$groupNo, 'name'=>$name, 'avatar'=>$avatar, 'notice'=>$notice, 'owner_id'=>intval($user['id']), 'member_count'=>0, 'mute_all'=>0, 'default_group'=>0, 'status'=>1, 'create_time'=>$now, 'update_time'=>$now]);
        $group = Db::name('im_groups')->where('appid', $this->appid)->where('id', $groupId)->find();
        $this->blinTraitSyncChannel($group, array_merge([intval($user['id'])], array_values($validUsers)), true);
        $this->blinTraitAddUserToGroup($group, intval($user['id']), 2);
        foreach ($validUsers as $uid) { $this->blinTraitAddUserToGroup($group, intval($uid), 0); }
        $avatar = $this->blinApplyDefaultGroupAvatar($groupId, $requestAvatar, $creatorAvatar);
        $group = Db::name('im_groups')->where('appid', $this->appid)->where('id', $groupId)->find();
        if ($group && isset($group['avatar']) && trim(strval($group['avatar'])) !== '') $avatar = trim(strval($group['avatar']));
        $this->json(1, '创建成功', ['id'=>$groupId, 'group_id'=>$groupId, 'group_no'=>$groupNo, 'name'=>$name, 'avatar'=>$avatar, 'notice'=>$notice, 'member_count'=>intval($group ? $group['member_count'] : (count($validUsers)+1))]);
    }'''


def ensure_avatar_helpers(source: str) -> str:
    if "blinGroupAvatarCollageEnabled" in source:
        return source
    marker = "\n    private function blinBuildGroupAvatar($groupId)"
    if marker not in source:
        marker = "\n    public function update_im_group()"
    if marker not in source:
        raise SystemExit("AVATAR_HELPER_MARKER_NOT_FOUND")
    return source.replace(marker, "\n" + AVATAR_HELPERS.rstrip() + "\n" + marker, 1)


def guard_build_group_avatar(source: str) -> str:
    needle = "    private function blinBuildGroupAvatar($groupId)\n    {\n"
    guard = '        if (!function_exists("imagecreatetruecolor") || !function_exists("imagejpeg")) return "";\n'
    if needle not in source or guard in source:
        return source
    return source.replace(needle, needle + guard, 1)


def patch_trait_defaults(source: str) -> str:
    if "'group_avatar_collage_switch' => '0'" in source or '"group_avatar_collage_switch" => "0"' in source:
        return source
    return re.sub(
        r"('admin_app_message_switch'\s*=>\s*'0',\n)",
        r"\1            'group_avatar_collage_switch' => '0',\n",
        source,
        count=1,
    )


def patch_api_file(path: Path, create_body: str, suffix: str, trait_defaults: bool = False) -> bool:
    source = path.read_text(errors="ignore")
    original = source
    if trait_defaults:
        source = patch_trait_defaults(source)
    source = ensure_avatar_helpers(source)
    source = guard_build_group_avatar(source)
    source = replace_method(source, "    public function create_im_group()", create_body)
    return save(path, original, source, suffix)


def main() -> None:
    patch_database()
    changed = patch_app_controller()
    changed = patch_base_controller() or changed
    changed = patch_app_edit() or changed
    changed = patch_api_file(API, API_CREATE, "group_create_avatar_api") or changed
    changed = patch_api_file(TRAIT, TRAIT_CREATE, "group_create_avatar_trait", True) or changed
    print("PATCHED_GROUP_CREATE_DEFAULT_AVATAR" if changed else "GROUP_CREATE_DEFAULT_AVATAR_ALREADY_UP_TO_DATE")


if __name__ == "__main__":
    main()
