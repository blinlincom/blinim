from pathlib import Path


ROOT = Path("/www/wwwroot/blinlin")


def backup(path: Path) -> None:
    bak = path.with_name(path.name + ".bak_moments_audit_20260621")
    if not bak.exists():
        bak.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise RuntimeError(f"missing marker: {label}")
    return text.replace(old, new, 1)


def patch_api() -> None:
    path = ROOT / "application/api/controller/Api.php"
    backup(path)
    text = path.read_text(encoding="utf-8")

    old = '''    private function blinMomentsOpen()
    {
        return intval($this->blinForumConfig("moments_switch", 0)) === 0;
    }


    private function blinEnsureMomentsColumn($column, $ddl)
'''
    new = '''    private function blinMomentsOpen()
    {
        return intval($this->blinForumConfig("moments_switch", 0)) === 0;
    }

    private function blinMomentsAuditEnabled()
    {
        return intval($this->blinForumConfig("moments_audit_switch", 0)) === 1;
    }

    private function blinMomentsAuditConfig()
    {
        return [
            "switch" => $this->blinMomentsAuditEnabled() ? 1 : 0,
            "mode" => trim(strval($this->blinForumConfig("moments_audit_mode", "smart"))) ?: "smart",
            "reject_keywords" => trim(strval($this->blinForumConfig("moments_audit_reject_keywords", ""))),
            "review_keywords" => trim(strval($this->blinForumConfig("moments_audit_review_keywords", ""))),
            "block_links" => intval($this->blinForumConfig("moments_audit_block_links", 0)),
            "review_links" => intval($this->blinForumConfig("moments_audit_review_links", 1)),
            "review_video" => intval($this->blinForumConfig("moments_audit_review_video", 0)),
            "review_long_text" => intval($this->blinForumConfig("moments_audit_review_long_text", 0)),
            "long_text_length" => max(0, intval($this->blinForumConfig("moments_audit_long_text_length", 800))),
        ];
    }

    private function blinMomentAuditText($status)
    {
        $status = intval($status);
        if ($status === 0) return "审核中";
        if ($status === 2) return "未通过";
        return "已通过";
    }

    private function blinMomentKeywordList($raw)
    {
        $items = preg_split("/[\\r\\n,，|]+/u", strval($raw));
        $words = [];
        foreach ($items as $item) {
            $word = trim(strval($item));
            if ($word !== "") $words[] = $word;
            if (count($words) >= 300) break;
        }
        return array_values(array_unique($words));
    }

    private function blinMomentFirstKeywordHit($text, $words)
    {
        $text = mb_strtolower(strval($text), "UTF-8");
        foreach ($words as $word) {
            $word = mb_strtolower(trim(strval($word)), "UTF-8");
            if ($word !== "" && mb_strpos($text, $word, 0, "UTF-8") !== false) return $word;
        }
        return "";
    }

    private function blinMomentAutoAudit($content, $images, $videoUrl)
    {
        if (!$this->blinMomentsAuditEnabled()) {
            return ["status" => 1, "reason" => "审核关闭，自动通过"];
        }
        $config = $this->blinMomentsAuditConfig();
        $mode = strtolower(trim(strval($config["mode"])));
        if ($mode === "manual") {
            return ["status" => 0, "reason" => "等待人工审核"];
        }
        $content = trim(strval($content));
        $mediaText = implode(" ", is_array($images) ? $images : []) . " " . trim(strval($videoUrl));
        $scanText = $content . " " . $mediaText;
        $rejectHit = $this->blinMomentFirstKeywordHit($scanText, $this->blinMomentKeywordList($config["reject_keywords"]));
        if ($rejectHit !== "") {
            return ["status" => 2, "reason" => "内容命中禁止词：" . $rejectHit];
        }
        $hasLink = preg_match("/https?:\\/\\/|www\\.|[a-z0-9\\-]+\\.(com|cn|net|org|top|xyz|io|app)(\\/|\\s|$)/i", $scanText) ? true : false;
        if ($hasLink && intval($config["block_links"]) === 1) {
            return ["status" => 2, "reason" => "内容包含外部链接"];
        }
        $reviewReasons = [];
        $reviewHit = $this->blinMomentFirstKeywordHit($scanText, $this->blinMomentKeywordList($config["review_keywords"]));
        if ($reviewHit !== "") $reviewReasons[] = "命中复核词：" . $reviewHit;
        if ($hasLink && intval($config["review_links"]) === 1) $reviewReasons[] = "包含链接";
        if (trim(strval($videoUrl)) !== "" && intval($config["review_video"]) === 1) $reviewReasons[] = "包含视频";
        if (intval($config["review_long_text"]) === 1 && intval($config["long_text_length"]) > 0 && mb_strlen($content, "UTF-8") > intval($config["long_text_length"])) {
            $reviewReasons[] = "文本较长";
        }
        if ($mode === "strict" && $reviewReasons) {
            return ["status" => 0, "reason" => implode("；", $reviewReasons)];
        }
        if ($mode === "smart" && $reviewReasons) {
            return ["status" => 0, "reason" => implode("；", $reviewReasons)];
        }
        return ["status" => 1, "reason" => "自动审核通过"];
    }


    private function blinEnsureMomentsColumn($column, $ddl)
'''
    text = replace_once(text, old, new, "api audit helpers")

    old = '''            $this->blinEnsureMomentsColumn("delete_reason", "`delete_reason` varchar(500) NOT NULL DEFAULT '' AFTER `status`");
            $this->blinEnsureMomentsColumn("deleted_by", "`deleted_by` int(11) NOT NULL DEFAULT 0 AFTER `delete_reason`");
            $this->blinEnsureMomentsColumn("delete_time", "`delete_time` datetime DEFAULT NULL AFTER `deleted_by`");
            try { Db::execute("ALTER TABLE `mr_im_moments` ADD KEY `idx_visibility` (`appid`,`status`,`visibility`)"); } catch (\\Exception $e) {}
'''
    new = '''            $this->blinEnsureMomentsColumn("audit_status", "`audit_status` tinyint(1) NOT NULL DEFAULT 1 AFTER `status`");
            $this->blinEnsureMomentsColumn("audit_reason", "`audit_reason` varchar(500) NOT NULL DEFAULT '' AFTER `audit_status`");
            $this->blinEnsureMomentsColumn("audit_admin_id", "`audit_admin_id` int(11) NOT NULL DEFAULT 0 AFTER `audit_reason`");
            $this->blinEnsureMomentsColumn("audit_time", "`audit_time` datetime DEFAULT NULL AFTER `audit_admin_id`");
            $this->blinEnsureMomentsColumn("delete_reason", "`delete_reason` varchar(500) NOT NULL DEFAULT '' AFTER `audit_time`");
            $this->blinEnsureMomentsColumn("deleted_by", "`deleted_by` int(11) NOT NULL DEFAULT 0 AFTER `delete_reason`");
            $this->blinEnsureMomentsColumn("delete_time", "`delete_time` datetime DEFAULT NULL AFTER `deleted_by`");
            try { Db::execute("ALTER TABLE `mr_im_moments` ADD KEY `idx_visibility` (`appid`,`status`,`visibility`)"); } catch (\\Exception $e) {}
            try { Db::execute("ALTER TABLE `mr_im_moments` ADD KEY `idx_audit` (`appid`,`status`,`audit_status`,`create_time`)"); } catch (\\Exception $e) {}
'''
    text = replace_once(text, old, new, "api audit columns")

    old = '''        if ($ownerId <= 0 || $viewerId <= 0) return false;
        if ($ownerId === $viewerId) return true;
        $type = $this->blinMomentVisibilityType(isset($moment["visibility_type"]) ? $moment["visibility_type"] : (isset($moment["visibility"]) ? $moment["visibility"] : "friends"));
'''
    new = '''        if ($ownerId <= 0 || $viewerId <= 0) return false;
        if ($ownerId === $viewerId) return true;
        if ($this->blinMomentsAuditEnabled() && intval(isset($moment["audit_status"]) ? $moment["audit_status"] : 1) !== 1) return false;
        $type = $this->blinMomentVisibilityType(isset($moment["visibility_type"]) ? $moment["visibility_type"] : (isset($moment["visibility"]) ? $moment["visibility"] : "friends"));
'''
    text = replace_once(text, old, new, "api can view audit")

    text = replace_once(
        text,
        '''            ->field("m.id,m.appid,m.user_id,m.content,m.images,m.video_url,m.video_thumb,m.visibility,m.visibility_type,m.visible_user_ids,m.hidden_user_ids,m.like_count,m.comment_count,m.create_time,u.username,u.nickname,u.usertx")
''',
        '''            ->field("m.id,m.appid,m.user_id,m.content,m.images,m.video_url,m.video_thumb,m.visibility,m.visibility_type,m.visible_user_ids,m.hidden_user_ids,m.like_count,m.comment_count,m.audit_status,m.audit_reason,m.audit_time,m.create_time,u.username,u.nickname,u.usertx")
''',
        "api list fields",
    )

    old = '''        $rows = $filteredRows;
        foreach ($rows as $k => $row) {
            $mid = intval($row["id"]);
            $images = $this->blinMomentImages(isset($row["images"]) ? $row["images"] : "");
'''
    new = '''        $rows = $filteredRows;
        $auditEnabled = $this->blinMomentsAuditEnabled();
        foreach ($rows as $k => $row) {
            $mid = intval($row["id"]);
            $images = $this->blinMomentImages(isset($row["images"]) ? $row["images"] : "");
'''
    text = replace_once(text, old, new, "api audit enabled local")

    old = '''            $rows[$k]["visibility_label"] = $this->blinMomentVisibilityLabel($rows[$k]["visibility_type"]);
            $rows[$k]["liked_by_me"] = isset($likedMap[$mid]) ? 1 : 0;
'''
    new = '''            $rows[$k]["visibility_label"] = $this->blinMomentVisibilityLabel($rows[$k]["visibility_type"]);
            $auditStatus = intval(isset($row["audit_status"]) ? $row["audit_status"] : 1);
            $isOwner = intval($row["user_id"]) === intval($user["id"]);
            $rows[$k]["audit_enabled"] = $auditEnabled ? 1 : 0;
            $rows[$k]["audit_status"] = $auditStatus;
            $rows[$k]["audit_status_text"] = $this->blinMomentAuditText($auditStatus);
            $rows[$k]["audit_reason"] = $isOwner ? (isset($row["audit_reason"]) ? $row["audit_reason"] : "") : "";
            $rows[$k]["is_pending_audit"] = $auditEnabled && $auditStatus === 0 ? 1 : 0;
            $rows[$k]["is_rejected_audit"] = $auditEnabled && $auditStatus === 2 ? 1 : 0;
            $rows[$k]["liked_by_me"] = isset($likedMap[$mid]) ? 1 : 0;
'''
    text = replace_once(text, old, new, "api list audit output")

    old = '''        $this->json(1, "success", ["list"=>$rows, "page"=>$page, "limit"=>$limit, "visibility"=>$visibility, "visibility_label"=>$visibility === "all" ? "全员可见" : "仅好友可见", "unread_count"=>intval($unread)]);
'''
    new = '''        $this->json(1, "success", ["list"=>$rows, "page"=>$page, "limit"=>$limit, "visibility"=>$visibility, "visibility_label"=>$visibility === "all" ? "全员可见" : "仅好友可见", "audit_enabled"=>$auditEnabled ? 1 : 0, "unread_count"=>intval($unread)]);
'''
    text = replace_once(text, old, new, "api list data audit")

    old = '''        $visibility = $visibilityType === "public" ? "all" : "friends";
        $now = date("Y-m-d H:i:s");
        $id = Db::name("im_moments")->insertGetId(["appid"=>$this->appid, "user_id"=>intval($user["id"]), "content"=>$content, "images"=>json_encode($images, JSON_UNESCAPED_UNICODE), "video_url"=>$videoUrl, "video_thumb"=>$videoThumb, "visibility"=>$visibility, "visibility_type"=>$visibilityType, "visible_user_ids"=>json_encode($visibleUserIds, JSON_UNESCAPED_UNICODE), "hidden_user_ids"=>json_encode($hiddenUserIds, JSON_UNESCAPED_UNICODE), "like_count"=>0, "comment_count"=>0, "status"=>1, "create_time"=>$now, "update_time"=>$now]);
        $this->json(1, "发布成功", ["id"=>intval($id), "user_id"=>intval($user["id"]), "nickname"=>isset($user["nickname"]) ? $user["nickname"] : $user["username"], "username"=>$user["username"], "avatar"=>isset($user["usertx"]) ? $user["usertx"] : "", "content"=>$content, "images"=>$images, "video_url"=>$videoUrl, "video_thumb"=>$videoThumb, "visibility"=>$visibility, "visibility_type"=>$visibilityType, "visible_user_ids"=>$visibleUserIds, "hidden_user_ids"=>$hiddenUserIds, "visibility_label"=>$this->blinMomentVisibilityLabel($visibilityType), "like_count"=>0, "comment_count"=>0, "liked_by_me"=>0, "like_users"=>[], "comments"=>[], "create_time"=>$now]);
'''
    new = '''        $visibility = $visibilityType === "public" ? "all" : "friends";
        $audit = $this->blinMomentAutoAudit($content, $images, $videoUrl);
        $auditStatus = intval($audit["status"]);
        $auditReason = mb_substr(trim(strval($audit["reason"])), 0, 500, "UTF-8");
        $now = date("Y-m-d H:i:s");
        $id = Db::name("im_moments")->insertGetId(["appid"=>$this->appid, "user_id"=>intval($user["id"]), "content"=>$content, "images"=>json_encode($images, JSON_UNESCAPED_UNICODE), "video_url"=>$videoUrl, "video_thumb"=>$videoThumb, "visibility"=>$visibility, "visibility_type"=>$visibilityType, "visible_user_ids"=>json_encode($visibleUserIds, JSON_UNESCAPED_UNICODE), "hidden_user_ids"=>json_encode($hiddenUserIds, JSON_UNESCAPED_UNICODE), "like_count"=>0, "comment_count"=>0, "status"=>1, "audit_status"=>$auditStatus, "audit_reason"=>$auditReason, "audit_time"=>$auditStatus === 1 ? $now : null, "create_time"=>$now, "update_time"=>$now]);
        $message = $auditStatus === 1 ? "发布成功" : ($auditStatus === 2 ? "内容未通过审核，仅自己可见" : "发布成功，审核通过前仅自己可见");
        $this->json(1, $message, ["id"=>intval($id), "user_id"=>intval($user["id"]), "nickname"=>isset($user["nickname"]) ? $user["nickname"] : $user["username"], "username"=>$user["username"], "avatar"=>isset($user["usertx"]) ? $user["usertx"] : "", "content"=>$content, "images"=>$images, "video_url"=>$videoUrl, "video_thumb"=>$videoThumb, "visibility"=>$visibility, "visibility_type"=>$visibilityType, "visible_user_ids"=>$visibleUserIds, "hidden_user_ids"=>$hiddenUserIds, "visibility_label"=>$this->blinMomentVisibilityLabel($visibilityType), "audit_enabled"=>$this->blinMomentsAuditEnabled() ? 1 : 0, "audit_status"=>$auditStatus, "audit_status_text"=>$this->blinMomentAuditText($auditStatus), "audit_reason"=>$auditReason, "is_pending_audit"=>$this->blinMomentsAuditEnabled() && $auditStatus === 0 ? 1 : 0, "is_rejected_audit"=>$this->blinMomentsAuditEnabled() && $auditStatus === 2 ? 1 : 0, "like_count"=>0, "comment_count"=>0, "liked_by_me"=>0, "like_users"=>[], "comments"=>[], "create_time"=>$now]);
'''
    text = replace_once(text, old, new, "api create audit")

    path.write_text(text, encoding="utf-8")


def patch_app() -> None:
    path = ROOT / "application/admin/controller/App.php"
    backup(path)
    text = path.read_text(encoding="utf-8")

    text = replace_once(
        text,
        '''"moments_switch":"0","moments_visibility":"friends"}',
''',
        '''"moments_switch":"0","moments_visibility":"friends","moments_audit_switch":"0","moments_audit_mode":"smart","moments_audit_reject_keywords":"","moments_audit_review_keywords":"","moments_audit_block_links":"0","moments_audit_review_links":"1","moments_audit_review_video":"0","moments_audit_review_long_text":"0","moments_audit_long_text_length":"800"}',
''',
        "app add default config",
    )

    old = '''                "moments_switch" => isset($data["moments_switch"]) ? intval($data["moments_switch"]) : 1,
                "moments_visibility" => $this->blinNormalizeMomentsVisibility(isset($data["moments_visibility"]) ? $data["moments_visibility"] : "friends"),
                "post_switch" => $data["post_switch"],
'''
    new = '''                "moments_switch" => isset($data["moments_switch"]) ? intval($data["moments_switch"]) : 1,
                "moments_visibility" => $this->blinNormalizeMomentsVisibility(isset($data["moments_visibility"]) ? $data["moments_visibility"] : "friends"),
                "moments_audit_switch" => isset($data["moments_audit_switch"]) ? intval($data["moments_audit_switch"]) : 0,
                "moments_audit_mode" => in_array(isset($data["moments_audit_mode"]) ? $data["moments_audit_mode"] : "smart", ["smart", "manual", "strict"]) ? $data["moments_audit_mode"] : "smart",
                "moments_audit_reject_keywords" => isset($data["moments_audit_reject_keywords"]) ? trim($data["moments_audit_reject_keywords"]) : "",
                "moments_audit_review_keywords" => isset($data["moments_audit_review_keywords"]) ? trim($data["moments_audit_review_keywords"]) : "",
                "moments_audit_block_links" => isset($data["moments_audit_block_links"]) ? intval($data["moments_audit_block_links"]) : 0,
                "moments_audit_review_links" => isset($data["moments_audit_review_links"]) ? intval($data["moments_audit_review_links"]) : 1,
                "moments_audit_review_video" => isset($data["moments_audit_review_video"]) ? intval($data["moments_audit_review_video"]) : 0,
                "moments_audit_review_long_text" => isset($data["moments_audit_review_long_text"]) ? intval($data["moments_audit_review_long_text"]) : 0,
                "moments_audit_long_text_length" => max(0, intval(isset($data["moments_audit_long_text_length"]) ? $data["moments_audit_long_text_length"] : 800)),
                "post_switch" => $data["post_switch"],
'''
    text = replace_once(text, old, new, "app save audit config")

    old = '''                if (!isset($result["forum_configuration"]["comment_tipping_time_limit"])) {
                    $result["forum_configuration"]["comment_tipping_time_limit"] = 0;
                }
                $result["userinfo_configuration"] = json_decode($result["userinfo_configuration"], true);
'''
    new = '''                if (!isset($result["forum_configuration"]["comment_tipping_time_limit"])) {
                    $result["forum_configuration"]["comment_tipping_time_limit"] = 0;
                }
                $momentAuditDefaults = [
                    "moments_switch" => 0,
                    "moments_visibility" => "friends",
                    "moments_audit_switch" => 0,
                    "moments_audit_mode" => "smart",
                    "moments_audit_reject_keywords" => "",
                    "moments_audit_review_keywords" => "",
                    "moments_audit_block_links" => 0,
                    "moments_audit_review_links" => 1,
                    "moments_audit_review_video" => 0,
                    "moments_audit_review_long_text" => 0,
                    "moments_audit_long_text_length" => 800,
                ];
                $result["forum_configuration"] = array_merge($momentAuditDefaults, $result["forum_configuration"]);
                $result["userinfo_configuration"] = json_decode($result["userinfo_configuration"], true);
'''
    text = replace_once(text, old, new, "app load defaults")
    path.write_text(text, encoding="utf-8")


def patch_app_view() -> None:
    path = ROOT / "application/admin/view/app/edit.html"
    backup(path)
    text = path.read_text(encoding="utf-8")

    old = '''                        <div class="blin-setting-row blin-moments-visibility-card">
                            <div class="blin-setting-copy">
                                <span class="blin-setting-title">朋友圈可见范围</span>
                                <small class="blin-setting-desc">全员可见会展示当前应用内所有用户的朋友圈；仅好友可见只展示好友和自己的朋友圈。</small>
                            </div>
                            <div class="blin-segmented-switch" role="group" aria-label="朋友圈可见范围">
                                <input type="radio" id="moments_visibility_friends" value="friends" name="moments_visibility" class="btn-check" autocomplete="off" {if $data.forum_configuration.moments_visibility=="friends"} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-on" for="moments_visibility_friends"><i class="mdi mdi-account-multiple-outline"></i>仅好友</label>
                                <input type="radio" id="moments_visibility_all" value="all" name="moments_visibility" class="btn-check" autocomplete="off" {if $data.forum_configuration.moments_visibility=="all"} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-off" for="moments_visibility_all"><i class="mdi mdi-earth"></i>全员</label>
                            </div>
                        </div>
'''
    new = old + '''                        <div class="blin-setting-row blin-moments-audit-card">
                            <div class="blin-setting-copy">
                                <span class="blin-setting-title">朋友圈审核</span>
                                <small class="blin-setting-desc">开启后，用户发布内容会先经过自动规则审核；待审核或未通过内容只对发布者自己可见。</small>
                            </div>
                            <div class="blin-segmented-switch" role="group" aria-label="朋友圈审核">
                                <input type="radio" id="moments_audit_switch_on" value="1" name="moments_audit_switch" class="btn-check" autocomplete="off" {if $data.forum_configuration.moments_audit_switch==1} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-on" for="moments_audit_switch_on"><i class="mdi mdi-shield-check-outline"></i>开启</label>
                                <input type="radio" id="moments_audit_switch_off" value="0" name="moments_audit_switch" class="btn-check" autocomplete="off" {if $data.forum_configuration.moments_audit_switch!=1} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-off" for="moments_audit_switch_off"><i class="mdi mdi-shield-off-outline"></i>关闭</label>
                            </div>
                        </div>
                        <div class="row g-3 blin-moment-audit-options" style="margin-top: 0px;">
                            <div class="col-md-4">
                                <label class="form-label">审核模式</label>
                                <select class="form-control" name="moments_audit_mode">
                                    <option value="smart" {if $data.forum_configuration.moments_audit_mode=="smart"} selected {/if}>智能机审</option>
                                    <option value="strict" {if $data.forum_configuration.moments_audit_mode=="strict"} selected {/if}>严格机审</option>
                                    <option value="manual" {if $data.forum_configuration.moments_audit_mode=="manual"} selected {/if}>全部人工审核</option>
                                </select>
                                <small>智能机审：低风险自动通过，风险内容进入审核或拒绝。</small>
                            </div>
                            <div class="col-md-4">
                                <label class="form-label">链接处理</label>
                                <select class="form-control" name="moments_audit_block_links">
                                    <option value="0" {if $data.forum_configuration.moments_audit_block_links!=1} selected {/if}>链接进入复核</option>
                                    <option value="1" {if $data.forum_configuration.moments_audit_block_links==1} selected {/if}>链接直接拒绝</option>
                                </select>
                            </div>
                            <div class="col-md-4">
                                <label class="form-label">长文阈值</label>
                                <input type="number" class="form-control" name="moments_audit_long_text_length" value="{$data.forum_configuration.moments_audit_long_text_length}" min="0">
                            </div>
                            <div class="col-md-4">
                                <label class="form-label">含链接需复核</label>
                                <select class="form-control" name="moments_audit_review_links">
                                    <option value="1" {if $data.forum_configuration.moments_audit_review_links!=0} selected {/if}>开启</option>
                                    <option value="0" {if $data.forum_configuration.moments_audit_review_links==0} selected {/if}>关闭</option>
                                </select>
                            </div>
                            <div class="col-md-4">
                                <label class="form-label">视频需复核</label>
                                <select class="form-control" name="moments_audit_review_video">
                                    <option value="0" {if $data.forum_configuration.moments_audit_review_video!=1} selected {/if}>关闭</option>
                                    <option value="1" {if $data.forum_configuration.moments_audit_review_video==1} selected {/if}>开启</option>
                                </select>
                            </div>
                            <div class="col-md-4">
                                <label class="form-label">长文需复核</label>
                                <select class="form-control" name="moments_audit_review_long_text">
                                    <option value="0" {if $data.forum_configuration.moments_audit_review_long_text!=1} selected {/if}>关闭</option>
                                    <option value="1" {if $data.forum_configuration.moments_audit_review_long_text==1} selected {/if}>开启</option>
                                </select>
                            </div>
                            <div class="col-md-6">
                                <label class="form-label">禁止词</label>
                                <textarea class="form-control" name="moments_audit_reject_keywords" rows="3" placeholder="命中后直接拒绝，多个词用换行或逗号分隔">{$data.forum_configuration.moments_audit_reject_keywords}</textarea>
                            </div>
                            <div class="col-md-6">
                                <label class="form-label">复核词</label>
                                <textarea class="form-control" name="moments_audit_review_keywords" rows="3" placeholder="命中后进入待审核，多个词用换行或逗号分隔">{$data.forum_configuration.moments_audit_review_keywords}</textarea>
                            </div>
                        </div>
'''
    text = replace_once(text, old, new, "app view audit block")
    path.write_text(text, encoding="utf-8")


def patch_forum() -> None:
    path = ROOT / "application/admin/controller/Forum.php"
    backup(path)
    text = path.read_text(encoding="utf-8")

    text = replace_once(
        text,
        '''    public $no_need_right = ['select_postinfo', 'select_commentinfo'];
''',
        '''    public $no_need_right = ['select_postinfo', 'select_commentinfo', 'audit_moment'];
''',
        "forum audit no need right",
    )

    old = '''            $this->blinEnsureMomentsColumn("delete_reason", "`delete_reason` varchar(500) NOT NULL DEFAULT '' AFTER `status`");
            $this->blinEnsureMomentsColumn("deleted_by", "`deleted_by` int(11) NOT NULL DEFAULT 0 AFTER `delete_reason`");
            $this->blinEnsureMomentsColumn("delete_time", "`delete_time` datetime DEFAULT NULL AFTER `deleted_by`");
            try { Db::execute("ALTER TABLE `mr_im_moments` ADD KEY `idx_visibility` (`appid`,`status`,`visibility`)"); } catch (\\Exception $e) {}
'''
    new = '''            $this->blinEnsureMomentsColumn("audit_status", "`audit_status` tinyint(1) NOT NULL DEFAULT 1 AFTER `status`");
            $this->blinEnsureMomentsColumn("audit_reason", "`audit_reason` varchar(500) NOT NULL DEFAULT '' AFTER `audit_status`");
            $this->blinEnsureMomentsColumn("audit_admin_id", "`audit_admin_id` int(11) NOT NULL DEFAULT 0 AFTER `audit_reason`");
            $this->blinEnsureMomentsColumn("audit_time", "`audit_time` datetime DEFAULT NULL AFTER `audit_admin_id`");
            $this->blinEnsureMomentsColumn("delete_reason", "`delete_reason` varchar(500) NOT NULL DEFAULT '' AFTER `audit_time`");
            $this->blinEnsureMomentsColumn("deleted_by", "`deleted_by` int(11) NOT NULL DEFAULT 0 AFTER `delete_reason`");
            $this->blinEnsureMomentsColumn("delete_time", "`delete_time` datetime DEFAULT NULL AFTER `deleted_by`");
            try { Db::execute("ALTER TABLE `mr_im_moments` ADD KEY `idx_visibility` (`appid`,`status`,`visibility`)"); } catch (\\Exception $e) {}
            try { Db::execute("ALTER TABLE `mr_im_moments` ADD KEY `idx_audit` (`appid`,`status`,`audit_status`,`create_time`)"); } catch (\\Exception $e) {}
'''
    text = replace_once(text, old, new, "forum audit columns")

    text = replace_once(
        text,
        '''            $status = trim(strval(input("status")));
            $build = function () use ($appid, $username, $content, $status) {
''',
        '''            $status = trim(strval(input("status")));
            $auditStatus = trim(strval(input("audit_status")));
            $build = function () use ($appid, $username, $content, $status, $auditStatus) {
''',
        "forum audit filter var",
    )

    old = '''                if ($status !== "") {
                    $q = $q->where("m.status", intval($status));
                }
                return $q;
'''
    new = '''                if ($status !== "") {
                    $q = $q->where("m.status", intval($status));
                }
                if ($auditStatus !== "") {
                    $q = $q->where("m.audit_status", intval($auditStatus));
                }
                return $q;
'''
    text = replace_once(text, old, new, "forum audit filter query")

    text = text.replace(
        '''$allowSort = ["id", "create_time", "update_time", "status", "like_count", "comment_count"];''',
        '''$allowSort = ["id", "create_time", "update_time", "status", "audit_status", "like_count", "comment_count"];''',
        1,
    )

    text = replace_once(
        text,
        '''                $rows[$key]["status_text"] = intval($row["status"]) === 1 ? "正常" : "已删除";
''',
        '''                $rows[$key]["status_text"] = intval($row["status"]) === 1 ? "正常" : "已删除";
                $auditStatusValue = intval(isset($row["audit_status"]) ? $row["audit_status"] : 1);
                $rows[$key]["audit_status_text"] = $auditStatusValue === 0 ? "待审核" : ($auditStatusValue === 2 ? "未通过" : "已通过");
''',
        "forum row audit text",
    )

    text = replace_once(
        text,
        '''                $appid = $.trim($('#search_appid').val()),
''',
        '''                $appid = $.trim($('#search_appid').val()),
''',
        "noop",
    ) if False else text

    text = replace_once(
        text,
        '''            $rows = $build()
                ->field("m.id,m.appid,m.user_id,m.content,m.images,m.video_url,m.video_thumb,m.visibility,m.like_count,m.comment_count,m.status,m.delete_reason,m.deleted_by,m.delete_time,m.create_time,m.update_time,a.appname,u.username,u.nickname,u.usertx")
''',
        '''            $rows = $build()
                ->field("m.id,m.appid,m.user_id,m.content,m.images,m.video_url,m.video_thumb,m.visibility,m.like_count,m.comment_count,m.status,m.audit_status,m.audit_reason,m.audit_admin_id,m.audit_time,m.delete_reason,m.deleted_by,m.delete_time,m.create_time,m.update_time,a.appname,u.username,u.nickname,u.usertx")
''',
        "forum fields audit",
    )

    insert_after = '''        return $this->success("删除成功");
    }

'''
    method = '''        return $this->success("删除成功");
    }

    public function audit_moment()
    {
        $this->blinEnsureMomentsTables();
        $ids = explode(",", strval(input("id")));
        $auditStatus = intval(input("audit_status"));
        $reason = trim(strval(input("reason")));
        if (!in_array($auditStatus, [1, 2], true)) {
            return $this->error("审核状态错误");
        }
        if ($auditStatus === 2 && $reason === "") {
            return $this->error("请输入驳回原因");
        }
        $now = date("Y-m-d H:i:s");
        foreach ($ids as $value) {
            $id = intval($value);
            if ($id <= 0) continue;
            $moment = Db::name("im_moments")->where("id", $id)->find();
            if (!$moment) continue;
            $this->blinRequireApp($moment["appid"]);
            Db::name("im_moments")->where("id", $id)->update([
                "audit_status" => $auditStatus,
                "audit_reason" => $auditStatus === 2 ? $reason : "人工审核通过",
                "audit_admin_id" => isset($this->admin_info["id"]) ? intval($this->admin_info["id"]) : 0,
                "audit_time" => $now,
                "update_time" => $now,
            ]);
            Db::name("im_moment_notifications")->insert([
                "appid" => intval($moment["appid"]),
                "moment_id" => $id,
                "comment_id" => 0,
                "actor_id" => 0,
                "receiver_id" => intval($moment["user_id"]),
                "action" => $auditStatus === 1 ? "audit_pass" : "audit_reject",
                "content" => $auditStatus === 1 ? "你的朋友圈已审核通过" : ("你的朋友圈未通过审核，原因：" . mb_substr($reason, 0, 460, "UTF-8")),
                "is_read" => 0,
                "create_time" => $now,
            ]);
        }
        return $this->success("审核成功");
    }

'''
    text = replace_once(text, insert_after, method, "forum audit method")
    path.write_text(text, encoding="utf-8")


def patch_forum_view() -> None:
    path = ROOT / "application/admin/view/forum/moments.html"
    backup(path)
    text = path.read_text(encoding="utf-8")

    old = '''                        <div class="col-md-2 mb-2">
                            <select class="form-control" id="search_status">
                                <option value="">全部状态</option>
                                <option value="1">正常</option>
                                <option value="0">已删除</option>
                            </select>
                        </div>
                        <div class="col-md-2 mb-2">
                            <select class="form-control" id="search_appid">
'''
    new = '''                        <div class="col-md-2 mb-2">
                            <select class="form-control" id="search_status">
                                <option value="">全部状态</option>
                                <option value="1">正常</option>
                                <option value="0">已删除</option>
                            </select>
                        </div>
                        <div class="col-md-2 mb-2">
                            <select class="form-control" id="search_audit_status">
                                <option value="">全部审核</option>
                                <option value="0">待审核</option>
                                <option value="1">已通过</option>
                                <option value="2">未通过</option>
                            </select>
                        </div>
                        <div class="col-md-2 mb-2">
                            <select class="form-control" id="search_appid">
'''
    text = replace_once(text, old, new, "view audit filter")

    old = '''                    <div id="toolbar" class="toolbar-btn-action">
                        {if checkRight('forum/delete_moment')}
                        <button id="btn_delete" type="button" class="btn btn-label btn-danger">
                            <label><i class="mdi mdi-window-close" aria-hidden="true"></i></label>删除
                        </button>
                        {/if}
                    </div>
'''
    new = '''                    <div id="toolbar" class="toolbar-btn-action">
                        <button id="btn_audit_pass" type="button" class="btn btn-label btn-success">
                            <label><i class="mdi mdi-shield-check-outline" aria-hidden="true"></i></label>通过
                        </button>
                        <button id="btn_audit_reject" type="button" class="btn btn-label btn-warning">
                            <label><i class="mdi mdi-shield-alert-outline" aria-hidden="true"></i></label>驳回
                        </button>
                        {if checkRight('forum/delete_moment')}
                        <button id="btn_delete" type="button" class="btn btn-label btn-danger">
                            <label><i class="mdi mdi-window-close" aria-hidden="true"></i></label>删除
                        </button>
                        {/if}
                    </div>
'''
    text = replace_once(text, old, new, "view toolbar audit")

    old = '''                status: $.trim($('#search_status').val()),
                appid: $.trim($('#search_appid').val()),
'''
    new = '''                status: $.trim($('#search_status').val()),
                audit_status: $.trim($('#search_audit_status').val()),
                appid: $.trim($('#search_appid').val()),
'''
    text = replace_once(text, old, new, "view query audit")

    old = '''        }, {
            field: 'status_text',
            title: '状态',
            formatter: function (value, row) {
                return row.status == 1 ? '<span class="badge bg-success">正常</span>' : '<span class="badge bg-secondary">已删除</span>';
            }
        }, {
            field: 'delete_reason',
'''
    new = '''        }, {
            field: 'status_text',
            title: '状态',
            formatter: function (value, row) {
                return row.status == 1 ? '<span class="badge bg-success">正常</span>' : '<span class="badge bg-secondary">已删除</span>';
            }
        }, {
            field: 'audit_status_text',
            title: '审核',
            sortable: true,
            formatter: function (value, row) {
                if (row.audit_status == 0) return '<span class="badge bg-warning">待审核</span>';
                if (row.audit_status == 2) return '<span class="badge bg-danger">未通过</span>';
                return '<span class="badge bg-success">已通过</span>';
            }
        }, {
            field: 'audit_reason',
            title: '审核原因',
            formatter: function (value) { return htmlEscape(value || '-'); }
        }, {
            field: 'delete_reason',
'''
    text = replace_once(text, old, new, "view audit columns")

    old = '''                var html = '';
                {if checkRight('forum/delete_moment')}
                if (row.status == 1) html += '<a href="#!" class="btn btn-sm btn-default del-btn" title="删除" data-toggle="tooltip"><i class="mdi mdi-window-close"></i></a>';
                {/if}
                return html;
            },
            events: {
                'click .del-btn': function (event, value, row) {
                    deleteMoment(row.id);
                }
            }
'''
    new = '''                var html = '';
                if (row.status == 1 && row.audit_status != 1) html += '<a href="#!" class="btn btn-sm btn-default audit-pass-btn" title="通过" data-toggle="tooltip"><i class="mdi mdi-shield-check-outline"></i></a> ';
                if (row.status == 1 && row.audit_status != 2) html += '<a href="#!" class="btn btn-sm btn-default audit-reject-btn" title="驳回" data-toggle="tooltip"><i class="mdi mdi-shield-alert-outline"></i></a> ';
                {if checkRight('forum/delete_moment')}
                if (row.status == 1) html += '<a href="#!" class="btn btn-sm btn-default del-btn" title="删除" data-toggle="tooltip"><i class="mdi mdi-window-close"></i></a>';
                {/if}
                return html;
            },
            events: {
                'click .audit-pass-btn': function (event, value, row) {
                    auditMoment(row.id, 1, '');
                },
                'click .audit-reject-btn': function (event, value, row) {
                    askAuditReject(row.id);
                },
                'click .del-btn': function (event, value, row) {
                    deleteMoment(row.id);
                }
            }
'''
    text = replace_once(text, old, new, "view operate audit")

    old = '''    function deleteMoment(id) {
        askDeleteReason(id);
    }

    function doDelete(ids, reason) {
'''
    new = '''    function deleteMoment(id) {
        askDeleteReason(id);
    }

    function askAuditReject(ids) {
        if (!ids) return;
        var html = '<div style="padding:16px;">'
            + '<textarea id="moment_audit_reason" class="form-control" rows="4" placeholder="请输入驳回原因"></textarea>'
            + '<small class="text-muted d-block mt-2">驳回后内容仍仅发布者自己可见，并会通知发布用户。</small>'
            + '</div>';
        layer.open({
            type: 1,
            title: '驳回朋友圈',
            area: ['460px', '260px'],
            content: html,
            btn: ['驳回', '取消'],
            yes: function (index) {
                var reason = $.trim($('#moment_audit_reason').val());
                if (!reason) {
                    notify.error('请输入驳回原因');
                    return;
                }
                layer.close(index);
                auditMoment(ids, 2, reason);
            }
        });
    }

    function auditMoment(ids, status, reason) {
        var l = $('body').lyearloading({
            opacity: 0.2,
            spinnerSize: 'lg',
            spinnerText: '后台处理中，请稍后...',
            textColorClass: 'text-info',
            spinnerColorClass: 'text-info'
        });
        $.ajax({
            type: "POST",
            url: "{$Request.root}/forum/audit_moment",
            data: { id: ids, audit_status: status, reason: reason || '' },
            dataType: "json",
            success: function (data) {
                l.destroy();
                if (data.code == 1) {
                    notify.success(data.msg);
                    $('#table').bootstrapTable('refresh');
                } else {
                    notify.error(data.msg || '审核失败');
                }
            },
            error: function () {
                l.destroy();
                notify.error("系统错误");
            }
        });
    }

    function doDelete(ids, reason) {
'''
    text = replace_once(text, old, new, "view audit js")

    old = '''    $("#btn_delete").click(function () {
        var ids = selectedIds();
        if (!ids) return false;
        askDeleteReason(ids);
    });
'''
    new = '''    $("#btn_audit_pass").click(function () {
        var ids = selectedIds();
        if (!ids) return false;
        auditMoment(ids, 1, '');
    });

    $("#btn_audit_reject").click(function () {
        var ids = selectedIds();
        if (!ids) return false;
        askAuditReject(ids);
    });

    $("#btn_delete").click(function () {
        var ids = selectedIds();
        if (!ids) return false;
        askDeleteReason(ids);
    });
'''
    text = replace_once(text, old, new, "view audit buttons")

    path.write_text(text, encoding="utf-8")


def main() -> None:
    patch_api()
    patch_app()
    patch_app_view()
    patch_forum()
    patch_forum_view()
    print("moments audit patch applied")


if __name__ == "__main__":
    main()
