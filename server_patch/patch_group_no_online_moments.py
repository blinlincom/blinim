#!/usr/bin/env python3
from pathlib import Path

ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"
TRAIT = ROOT / "application/api/controller/traits/ImApiTrait.php"
ADMIN = ROOT / "application/admin/controller/App.php"
EDIT = ROOT / "application/admin/view/app/edit.html"
BASE = ROOT / "application/api/controller/BaseController.php"
ROUTE = ROOT / "route/route.php"


def backup(path: Path, tag: str) -> str:
    dst = path.with_name(f"{path.name}.bak_{tag}_20260617")
    if not dst.exists():
        dst.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
    return str(dst)


def save(path: Path, original: str, source: str, tag: str) -> bool:
    if source == original:
        print(f"NO_CHANGE {path}")
        return False
    print(f"BACKUP {backup(path, tag)}")
    path.write_text(source, encoding="utf-8")
    print(f"PATCHED {path}")
    return True


def patch_admin() -> bool:
    original = ADMIN.read_text(encoding="utf-8")
    source = original
    source = source.replace(
        '"group_avatar_collage_switch":"0"}',
        '"group_avatar_collage_switch":"0","group_no_rule":"alnum"}',
    )
    source = source.replace(
        '"comment_tipping_time_limit":"0"}',
        '"comment_tipping_time_limit":"0","moments_switch":"0"}',
    )
    if '"moments_switch" => isset($data["moments_switch"])' not in source:
        source = source.replace(
            '                "community_switch" => isset($data["community_switch"]) ? intval($data["community_switch"]) : 1,\n',
            '                "community_switch" => isset($data["community_switch"]) ? intval($data["community_switch"]) : 1,\n'
            '                "moments_switch" => isset($data["moments_switch"]) ? intval($data["moments_switch"]) : 1,\n',
        )
    if '"group_no_rule" => $this->blinNormalizeGroupNoRule' not in source:
        source = source.replace(
            '                    "group_no_change_amount" => isset($data["group_no_change_amount"]) ? floatval($data["group_no_change_amount"]) : 0,\n',
            '                    "group_no_change_amount" => isset($data["group_no_change_amount"]) ? floatval($data["group_no_change_amount"]) : 0,\n'
            '                    "group_no_rule" => $this->blinNormalizeGroupNoRule(isset($data["group_no_rule"]) ? $data["group_no_rule"] : "alnum"),\n',
        )
    if '"group_no_rule" => "alnum"' not in source:
        source = source.replace(
            '                    "group_no_change_amount" => 0,\n',
            '                    "group_no_change_amount" => 0,\n'
            '                    "group_no_rule" => "alnum",\n',
        )
    if "private function blinNormalizeGroupNoRule" not in source:
        marker = "    public function edit()\n"
        helper = '''    private function blinNormalizeGroupNoRule($rule)
    {
        $rule = strtolower(trim(strval($rule)));
        $allow = ["alnum", "number", "letters", "alnum_underscore"];
        return in_array($rule, $allow) ? $rule : "alnum";
    }

'''
        source = source.replace(marker, helper + marker)
    return save(ADMIN, original, source, "group_no_online_moments_admin")


def patch_base() -> bool:
    original = BASE.read_text(encoding="utf-8")
    source = original
    if '"group_no_rule"' not in source:
        source = source.replace(
            '                "group_no_change_amount" => "0",\n',
            '                "group_no_change_amount" => "0",\n'
            '                "group_no_rule" => "alnum",\n',
        )
    if '"moments_switch"' not in source:
        source = source.replace(
            '                "community_switch" => "0",\n',
            '                "community_switch" => "0",\n'
            '                "moments_switch" => "0",\n',
        )
    return save(BASE, original, source, "group_no_online_moments_base")


def patch_route() -> bool:
    original = ROUTE.read_text(encoding="utf-8")
    source = original
    if "get_moments_list" not in source:
        source = source.replace(
            "$imStatusActions = ['get_im_connect_info','wukongim_webhook','get_im_online_status','im_online_heartbeat','batch_get_im_user_info','im_debug_log_count'];\n",
            "$imStatusActions = ['get_im_connect_info','wukongim_webhook','get_im_online_status','im_online_heartbeat','batch_get_im_user_info','im_debug_log_count'];\n"
            "$imMomentsActions = ['get_moments_list','create_moment','delete_moment'];\n"
            "foreach ($imMomentsActions as $action) { Route::rule('api/' . $action, 'api/api/' . $action); }\n",
        )
    return save(ROUTE, original, source, "group_no_online_moments_route")


def patch_edit() -> bool:
    original = EDIT.read_text(encoding="utf-8")
    source = original
    if "name=\"group_no_rule\"" not in source:
        insert = '''                            <div class="col-md-4">
                                <label class="form-label">群号格式规则</label>
                                <select class="form-control" name="group_no_rule">
                                    <option value="alnum" {if $data.im_configuration.group_no_rule=="alnum"} selected {/if}>英文或数字</option>
                                    <option value="number" {if $data.im_configuration.group_no_rule=="number"} selected {/if}>纯数字</option>
                                    <option value="letters" {if $data.im_configuration.group_no_rule=="letters"} selected {/if}>纯英文</option>
                                    <option value="alnum_underscore" {if $data.im_configuration.group_no_rule=="alnum_underscore"} selected {/if}>英文数字下划线</option>
                                </select>
                                <small>群号长度固定为 4-32 位，客户端和服务端都会按此规则校验。</small>
                            </div>
'''
        source = source.replace(
            '                            <div class="col-md-4">\n                                <label class="form-label">群号修改金额</label>\n                                <input type="number" step="0.01" min="0" class="form-control" name="group_no_change_amount" value="{$data.im_configuration.group_no_change_amount}" placeholder="0">\n                            </div>\n',
            '                            <div class="col-md-4">\n                                <label class="form-label">群号修改金额</label>\n                                <input type="number" step="0.01" min="0" class="form-control" name="group_no_change_amount" value="{$data.im_configuration.group_no_change_amount}" placeholder="0">\n                            </div>\n' + insert,
        )
    if "name=\"moments_switch\"" not in source:
        moments = '''                        <div class="blin-setting-row blin-moments-switch-card">
                            <div class="blin-setting-copy">
                                <span class="blin-setting-title">朋友圈入口</span>
                                <small class="blin-setting-desc">开启后，客户端通讯录显示朋友圈入口；关闭后客户端隐藏入口并禁止发布。</small>
                            </div>
                            <div class="blin-segmented-switch" role="group" aria-label="朋友圈入口">
                                <input type="radio" id="moments_switch_on" value="0" name="moments_switch" class="btn-check" autocomplete="off" {if $data.forum_configuration.moments_switch==0} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-on" for="moments_switch_on"><i class="mdi mdi-check-circle-outline"></i>开启</label>
                                <input type="radio" id="moments_switch_off" value="1" name="moments_switch" class="btn-check" autocomplete="off" {if $data.forum_configuration.moments_switch==1} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-off" for="moments_switch_off"><i class="mdi mdi-close-circle-outline"></i>关闭</label>
                            </div>
                        </div>
'''
        source = source.replace(
            '                        <div class="row g-3">\n                            <div class="col-md-6">\n                                <label for="post_money">发帖奖励金币</label>',
            moments + '                        <div class="row g-3">\n                            <div class="col-md-6">\n                                <label for="post_money">发帖奖励金币</label>',
        )
    source = source.replace(
        '<input type="number" class="form-control" name="transfer_handling_fee" value="{$data.forum_configuration.transfer_handling_fee}">',
        '<input type="number" step="0.01" class="form-control" name="transfer_handling_fee" value="{$data.forum_configuration.transfer_handling_fee}">',
    )
    source = source.replace(
        '因为这里涉及到金币及积分都是整数，所以只会取整数扣除，小于1则直接不扣除',
        '金币余额支持两位小数，手续费会按两位小数计算',
    )
    return save(EDIT, original, source, "group_no_online_moments_view")


GROUP_HELPERS = r'''
    private function blinNormalizeGroupNoRule($rule)
    {
        $rule = strtolower(trim(strval($rule)));
        $allow = ["alnum", "number", "letters", "alnum_underscore"];
        return in_array($rule, $allow) ? $rule : "alnum";
    }

    private function blinGroupNoRuleMeta($rule)
    {
        $rule = $this->blinNormalizeGroupNoRule($rule);
        if ($rule === "number") return ["rule"=>"number", "pattern"=>"/^[0-9]{4,32}$/", "message"=>"群号只能是4-32位纯数字", "label"=>"纯数字"];
        if ($rule === "letters") return ["rule"=>"letters", "pattern"=>"/^[A-Za-z]{4,32}$/", "message"=>"群号只能是4-32位纯英文", "label"=>"纯英文"];
        if ($rule === "alnum_underscore") return ["rule"=>"alnum_underscore", "pattern"=>"/^[A-Za-z0-9_]{4,32}$/", "message"=>"群号只能是4-32位英文数字或下划线", "label"=>"英文数字下划线"];
        return ["rule"=>"alnum", "pattern"=>"/^[A-Za-z0-9]{4,32}$/", "message"=>"群号只能是4-32位英文或数字", "label"=>"英文或数字"];
    }
'''


MOMENTS_METHODS = r'''

    private function blinForumConfig($key = null, $default = null)
    {
        $config = isset($this->app_info["forum_configuration"]) && is_array($this->app_info["forum_configuration"]) ? $this->app_info["forum_configuration"] : [];
        if ($key === null) return $config;
        return isset($config[$key]) ? $config[$key] : $default;
    }

    private function blinMomentsOpen()
    {
        return intval($this->blinForumConfig("moments_switch", 0)) === 0;
    }

    private function blinEnsureMomentsTables()
    {
        Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_moments` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `user_id` int(11) NOT NULL DEFAULT 0, `content` text, `images` mediumtext, `like_count` int(11) NOT NULL DEFAULT 0, `comment_count` int(11) NOT NULL DEFAULT 0, `status` tinyint(1) NOT NULL DEFAULT 1, `create_time` datetime DEFAULT NULL, `update_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), KEY `idx_app_time` (`appid`,`status`,`create_time`), KEY `idx_user` (`appid`,`user_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
    }

    public function get_moments_list()
    {
        if (!$this->blinMomentsOpen()) $this->json(0, "朋友圈入口已关闭");
        $this->blinEnsureMomentsTables();
        $user = $this->user_info;
        if (!$user || !isset($user["id"])) $this->json(401, "未登录");
        $page = max(1, intval(input("page") ?: 1));
        $limit = min(50, max(1, intval(input("limit") ?: 20)));
        $friendIds = Db::table("im_friends")->where("user_id", intval($user["id"]))->where("status", 1)->column("friend_id");
        if (!is_array($friendIds)) $friendIds = [];
        $friendIds[] = intval($user["id"]);
        $friendIds = array_values(array_unique(array_map("intval", $friendIds)));
        $rows = Db::name("im_moments")->alias("m")
            ->join("user u", "u.id=m.user_id")
            ->where("m.appid", $this->appid)
            ->where("m.user_id", "in", $friendIds)
            ->where("m.status", 1)
            ->field("m.id,m.user_id,m.content,m.images,m.like_count,m.comment_count,m.create_time,u.username,u.nickname,u.usertx")
            ->order("m.id desc")
            ->page($page, $limit)
            ->select();
        foreach ($rows as $k => $row) {
            $images = json_decode(strval(isset($row["images"]) ? $row["images"] : "[]"), true);
            if (!is_array($images)) $images = [];
            $rows[$k]["images"] = $images;
            $rows[$k]["avatar"] = isset($row["usertx"]) ? $row["usertx"] : "";
            $rows[$k]["nickname"] = trim(strval(isset($row["nickname"]) ? $row["nickname"] : "")) !== "" ? $row["nickname"] : (isset($row["username"]) ? $row["username"] : "用户");
            unset($rows[$k]["usertx"]);
        }
        $this->json(1, "success", ["list"=>$rows, "page"=>$page, "limit"=>$limit]);
    }

    public function create_moment()
    {
        if (!$this->blinMomentsOpen()) $this->json(0, "朋友圈入口已关闭");
        $this->blinEnsureMomentsTables();
        $user = $this->user_info;
        if (!$user || !isset($user["id"])) $this->json(401, "未登录");
        $content = trim(strval(input("content") ?: input("text") ?: ""));
        $imagesRaw = input("images") ?: "";
        $images = [];
        if (is_array($imagesRaw)) $images = $imagesRaw;
        elseif (trim(strval($imagesRaw)) !== "") {
            $decoded = json_decode(strval($imagesRaw), true);
            if (is_array($decoded)) $images = $decoded;
            else $images = preg_split("/[,，\s]+/", trim(strval($imagesRaw)));
        }
        $clean = [];
        foreach ($images as $img) {
            $url = trim(strval($img));
            if ($url !== "") $clean[] = $url;
            if (count($clean) >= 9) break;
        }
        if ($content === "" && !$clean) $this->json(0, "请输入朋友圈内容");
        if (mb_strlen($content, "UTF-8") > 2000) $this->json(0, "朋友圈内容过长");
        $now = date("Y-m-d H:i:s");
        $id = Db::name("im_moments")->insertGetId(["appid"=>$this->appid, "user_id"=>intval($user["id"]), "content"=>$content, "images"=>json_encode($clean, JSON_UNESCAPED_UNICODE), "status"=>1, "create_time"=>$now, "update_time"=>$now]);
        $this->json(1, "发布成功", ["id"=>intval($id), "content"=>$content, "images"=>$clean, "create_time"=>$now]);
    }

    public function delete_moment()
    {
        $this->blinEnsureMomentsTables();
        $user = $this->user_info;
        if (!$user || !isset($user["id"])) $this->json(401, "未登录");
        $id = intval(input("id") ?: input("moment_id"));
        if ($id <= 0) $this->json(0, "朋友圈不存在");
        $row = Db::name("im_moments")->where("appid", $this->appid)->where("id", $id)->where("status", 1)->find();
        if (!$row) $this->json(0, "朋友圈不存在");
        if (intval($row["user_id"]) !== intval($user["id"])) $this->json(0, "只能删除自己的朋友圈");
        Db::name("im_moments")->where("id", $id)->update(["status"=>0, "update_time"=>date("Y-m-d H:i:s")]);
        $this->json(1, "已删除");
    }
'''


def patch_api_like(path: Path, tag: str) -> bool:
    original = path.read_text(encoding="utf-8")
    source = original
    if "blinGroupNoRuleMeta" not in source:
        source = source.replace("    private function blinGroupNoChangeConfig()\n", GROUP_HELPERS + "\n    private function blinGroupNoChangeConfig()\n")
    source = source.replace(
        '"group_no_change_amount" => isset($config["group_no_change_amount"]) ? floatval($config["group_no_change_amount"]) : 0,\n        ];',
        '"group_no_change_amount" => isset($config["group_no_change_amount"]) ? floatval($config["group_no_change_amount"]) : 0,\n'
        '            "group_no_rule" => $this->blinNormalizeGroupNoRule(isset($config["group_no_rule"]) ? $config["group_no_rule"] : "alnum"),\n'
        '        ];',
    )
    old = '            if (!preg_match("/^[A-Za-z0-9_]{4,32}$/", $groupNo)) $this->json(0, "群号只能是4-32位英文数字或下划线");'
    new = '            $groupNoRule = $this->blinGroupNoRuleMeta(isset($groupNoConfig["group_no_rule"]) ? $groupNoConfig["group_no_rule"] : "alnum");\n            if (!preg_match($groupNoRule["pattern"], $groupNo)) $this->json(0, $groupNoRule["message"]);'
    source = source.replace(old, new)
    if "public function get_moments_list()" not in source:
        source = source.replace("\n    //搜索用户接口\n", MOMENTS_METHODS + "\n\n    //搜索用户接口\n")
    if '"last_seen"=>$last_seen' not in source:
        source = source.replace(
            '        $this->json(1, "success", [\n            "uid"=>$uid,',
            '        $last_seen = $last_update_time;\n        if (!$online) {\n            try {\n                $seenRow = Db::name("im_online_status")->where("uid", $uid)->order("update_time desc")->find();\n                if ($seenRow) $last_seen = isset($seenRow["last_seen"]) && $seenRow["last_seen"] ? strval($seenRow["last_seen"]) : (isset($seenRow["update_time"]) ? strval($seenRow["update_time"]) : $last_update_time);\n            } catch (\\Exception $e) {}\n        }\n\n        $this->json(1, "success", [\n            "uid"=>$uid,',
        )
        source = source.replace(
            '            "last_update_time"=>$last_update_time,\n',
            '            "last_update_time"=>$last_update_time,\n            "last_seen"=>$last_seen,\n',
        )
    source = source.replace(
        '            "content" => $content,\n            "create_time" => date("Y-m-d H:i:s", time()),',
        '            "content" => $sql_message_type == 2 ? number_format(floatval($content), 2, ".", "") : $content,\n            "create_time" => date("Y-m-d H:i:s", time()),',
    )
    source = source.replace(
        '$content = $data["money"];',
        '$content = number_format(floatval($data["money"]), 2, ".", "");',
    )
    return save(path, original, source, tag)


def main():
    changed = False
    changed = patch_admin() or changed
    changed = patch_base() or changed
    changed = patch_route() or changed
    changed = patch_edit() or changed
    changed = patch_api_like(API, "group_no_online_moments_api") or changed
    changed = patch_api_like(TRAIT, "group_no_online_moments_trait") or changed
    print("DONE changed=%s" % changed)


if __name__ == "__main__":
    main()
