#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"
BASE = ROOT / "application/api/controller/BaseController.php"
APP = ROOT / "application/admin/controller/App.php"
APP_EDIT = ROOT / "application/admin/view/app/edit.html"
FORUM = ROOT / "application/admin/controller/Forum.php"
MOMENTS_VIEW = ROOT / "application/admin/view/forum/moments.html"


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


MOMENTS_API_BLOCK = r'''
    private function blinForumConfig($key = null, $default = null)
    {
        $config = isset($this->app_info["forum_configuration"]) && is_array($this->app_info["forum_configuration"]) ? $this->app_info["forum_configuration"] : [];
        if ($key === null) return $config;
        return isset($config[$key]) ? $config[$key] : $default;
    }

    private function blinNormalizeMomentsVisibility($visibility)
    {
        $visibility = strtolower(trim(strval($visibility)));
        return in_array($visibility, ["all", "friends"]) ? $visibility : "friends";
    }

    private function blinMomentsVisibility()
    {
        return $this->blinNormalizeMomentsVisibility($this->blinForumConfig("moments_visibility", "friends"));
    }

    private function blinMomentsOpen()
    {
        return intval($this->blinForumConfig("moments_switch", 0)) === 0;
    }

    private function blinEnsureMomentsColumn($column, $ddl)
    {
        try {
            $exists = Db::query("SHOW COLUMNS FROM `mr_im_moments` LIKE '" . addslashes($column) . "'");
            if (!$exists) Db::execute("ALTER TABLE `mr_im_moments` ADD COLUMN " . $ddl);
        } catch (\Exception $e) {}
    }

    private function blinEnsureMomentsTables()
    {
        try {
            Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_moments` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `user_id` int(11) NOT NULL DEFAULT 0, `content` text, `images` mediumtext, `visibility` varchar(16) NOT NULL DEFAULT 'friends', `like_count` int(11) NOT NULL DEFAULT 0, `comment_count` int(11) NOT NULL DEFAULT 0, `status` tinyint(1) NOT NULL DEFAULT 1, `delete_reason` varchar(500) NOT NULL DEFAULT '', `deleted_by` int(11) NOT NULL DEFAULT 0, `delete_time` datetime DEFAULT NULL, `create_time` datetime DEFAULT NULL, `update_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), KEY `idx_app_time` (`appid`,`status`,`create_time`), KEY `idx_user` (`appid`,`user_id`), KEY `idx_visibility` (`appid`,`status`,`visibility`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
            Db::execute("CREATE TABLE IF NOT EXISTS `im_friends` (`id` bigint(20) unsigned NOT NULL AUTO_INCREMENT, `appid` bigint(20) NOT NULL DEFAULT 0, `user_id` bigint(20) unsigned NOT NULL, `friend_id` bigint(20) unsigned NOT NULL, `status` tinyint(4) NOT NULL DEFAULT 1, `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP, `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (`id`), UNIQUE KEY `uniq_friend_pair` (`user_id`,`friend_id`), KEY `idx_app_user` (`appid`,`user_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
            $this->blinEnsureMomentsColumn("visibility", "`visibility` varchar(16) NOT NULL DEFAULT 'friends' AFTER `images`");
            $this->blinEnsureMomentsColumn("delete_reason", "`delete_reason` varchar(500) NOT NULL DEFAULT '' AFTER `status`");
            $this->blinEnsureMomentsColumn("deleted_by", "`deleted_by` int(11) NOT NULL DEFAULT 0 AFTER `delete_reason`");
            $this->blinEnsureMomentsColumn("delete_time", "`delete_time` datetime DEFAULT NULL AFTER `deleted_by`");
            try { Db::execute("ALTER TABLE `mr_im_moments` ADD KEY `idx_visibility` (`appid`,`status`,`visibility`)"); } catch (\Exception $e) {}
        } catch (\Exception $e) {}
    }

    private function blinMomentFriendIds($userId)
    {
        $friendIds = [];
        try {
            $friendIds = Db::table("im_friends")
                ->where("appid", intval($this->appid))
                ->where("user_id", intval($userId))
                ->where("status", 1)
                ->column("friend_id");
        } catch (\Exception $e) {
            $friendIds = [];
        }
        if (!is_array($friendIds)) $friendIds = [];
        $friendIds[] = intval($userId);
        return array_values(array_unique(array_map("intval", $friendIds)));
    }

    public function get_moments_list()
    {
        if (!$this->blinMomentsOpen()) $this->json(0, "朋友圈入口已关闭");
        $this->blinEnsureMomentsTables();
        $user = $this->user_info;
        if (!$user || !isset($user["id"])) $this->json(401, "未登录");
        $page = max(1, intval(input("page") ?: 1));
        $limit = min(50, max(1, intval(input("limit") ?: 20)));
        $visibility = $this->blinMomentsVisibility();
        $query = Db::name("im_moments")->alias("m")
            ->join("user u", "u.id=m.user_id")
            ->where("m.appid", $this->appid)
            ->where("u.appid", $this->appid)
            ->where("m.status", 1);
        if ($visibility !== "all") {
            $query = $query->where("m.user_id", "in", $this->blinMomentFriendIds(intval($user["id"])));
        }
        $rows = $query
            ->field("m.id,m.user_id,m.content,m.images,m.visibility,m.like_count,m.comment_count,m.create_time,u.username,u.nickname,u.usertx")
            ->order("m.id desc")
            ->page($page, $limit)
            ->select();
        foreach ($rows as $k => $row) {
            $images = json_decode(strval(isset($row["images"]) ? $row["images"] : "[]"), true);
            if (!is_array($images)) $images = [];
            $rows[$k]["images"] = $images;
            $rows[$k]["avatar"] = isset($row["usertx"]) ? $row["usertx"] : "";
            $rows[$k]["nickname"] = trim(strval(isset($row["nickname"]) ? $row["nickname"] : "")) !== "" ? $row["nickname"] : (isset($row["username"]) ? $row["username"] : "用户");
            $rows[$k]["visibility"] = $this->blinNormalizeMomentsVisibility(isset($row["visibility"]) ? $row["visibility"] : $visibility);
            $rows[$k]["visibility_label"] = $rows[$k]["visibility"] === "all" ? "全员可见" : "仅好友可见";
            unset($rows[$k]["usertx"]);
        }
        $this->json(1, "success", ["list"=>$rows, "page"=>$page, "limit"=>$limit, "visibility"=>$visibility, "visibility_label"=>$visibility === "all" ? "全员可见" : "仅好友可见"]);
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
        $visibility = $this->blinMomentsVisibility();
        $now = date("Y-m-d H:i:s");
        $id = Db::name("im_moments")->insertGetId(["appid"=>$this->appid, "user_id"=>intval($user["id"]), "content"=>$content, "images"=>json_encode($clean, JSON_UNESCAPED_UNICODE), "visibility"=>$visibility, "status"=>1, "create_time"=>$now, "update_time"=>$now]);
        $this->json(1, "发布成功", ["id"=>intval($id), "content"=>$content, "images"=>$clean, "visibility"=>$visibility, "visibility_label"=>$visibility === "all" ? "全员可见" : "仅好友可见", "create_time"=>$now]);
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


FORUM_METHODS = r'''
    private function blinEnsureMomentsColumn($column, $ddl)
    {
        try {
            $exists = Db::query("SHOW COLUMNS FROM `mr_im_moments` LIKE '" . addslashes($column) . "'");
            if (!$exists) Db::execute("ALTER TABLE `mr_im_moments` ADD COLUMN " . $ddl);
        } catch (\Exception $e) {}
    }

    private function blinEnsureMomentsTables()
    {
        try {
            Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_moments` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `user_id` int(11) NOT NULL DEFAULT 0, `content` text, `images` mediumtext, `visibility` varchar(16) NOT NULL DEFAULT 'friends', `like_count` int(11) NOT NULL DEFAULT 0, `comment_count` int(11) NOT NULL DEFAULT 0, `status` tinyint(1) NOT NULL DEFAULT 1, `delete_reason` varchar(500) NOT NULL DEFAULT '', `deleted_by` int(11) NOT NULL DEFAULT 0, `delete_time` datetime DEFAULT NULL, `create_time` datetime DEFAULT NULL, `update_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), KEY `idx_app_time` (`appid`,`status`,`create_time`), KEY `idx_user` (`appid`,`user_id`), KEY `idx_visibility` (`appid`,`status`,`visibility`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
            $this->blinEnsureMomentsColumn("visibility", "`visibility` varchar(16) NOT NULL DEFAULT 'friends' AFTER `images`");
            $this->blinEnsureMomentsColumn("delete_reason", "`delete_reason` varchar(500) NOT NULL DEFAULT '' AFTER `status`");
            $this->blinEnsureMomentsColumn("deleted_by", "`deleted_by` int(11) NOT NULL DEFAULT 0 AFTER `delete_reason`");
            $this->blinEnsureMomentsColumn("delete_time", "`delete_time` datetime DEFAULT NULL AFTER `deleted_by`");
            try { Db::execute("ALTER TABLE `mr_im_moments` ADD KEY `idx_visibility` (`appid`,`status`,`visibility`)"); } catch (\Exception $e) {}
        } catch (\Exception $e) {}
    }

    public function moments()
    {
        $this->blinEnsureMomentsTables();
        if (request()->isAjax() || input("callback") != "") {
            $limit = input('limit') ? intval(input('limit')) : 10;
            $page = input('page') ? intval(input('page')) : 1;
            $sort = input('?sort') ? input('sort') : 'id';
            $allowSort = ["id", "create_time", "update_time", "status"];
            if (!in_array($sort, $allowSort)) $sort = "id";
            $sortOrder = strtolower(strval(input("?sortOrder") ? input("sortOrder") : "desc")) === "asc" ? "asc" : "desc";
            $appid = intval(input("appid"));
            $username = trim(strval(input("username")));
            $content = trim(strval(input("content")));
            $status = trim(strval(input("status")));
            $build = function () use ($appid, $username, $content, $status) {
                $q = Db::name("im_moments")->alias("m")
                    ->leftJoin("app a", "m.appid = a.appid")
                    ->leftJoin("user u", "m.user_id = u.id");
                $q = $this->blinScopeQuery($q, "m.appid");
                if ($appid > 0) {
                    $this->blinRequireApp($appid);
                    $q = $q->where("m.appid", $appid);
                }
                if ($username !== "") {
                    $q = $q->where("u.username|u.nickname", "like", "%" . $username . "%");
                }
                if ($content !== "") {
                    $q = $q->where("m.content", "like", "%" . $content . "%");
                }
                if ($status !== "") {
                    $q = $q->where("m.status", intval($status));
                }
                return $q;
            };
            $rows = $build()
                ->field("m.id,m.appid,m.user_id,m.content,m.images,m.visibility,m.like_count,m.comment_count,m.status,m.delete_reason,m.deleted_by,m.delete_time,m.create_time,m.update_time,a.appname,u.username,u.nickname,u.usertx")
                ->order("m." . $sort, $sortOrder)
                ->page($page, $limit)
                ->select();
            foreach ($rows as $key => $row) {
                $images = json_decode(strval(isset($row["images"]) ? $row["images"] : "[]"), true);
                if (!is_array($images)) $images = [];
                $rows[$key]["images"] = $images;
                $rows[$key]["images_count"] = count($images);
                $rows[$key]["content_short"] = mb_substr(trim(strval(isset($row["content"]) ? $row["content"] : "")), 0, 80, "UTF-8");
                $visibility = strtolower(trim(strval(isset($row["visibility"]) ? $row["visibility"] : "friends")));
                $rows[$key]["visibility_text"] = $visibility === "all" ? "全员可见" : "仅好友可见";
                $rows[$key]["status_text"] = intval($row["status"]) === 1 ? "正常" : "已删除";
            }
            $result = ["rows" => $rows, "total" => $build()->count()];
            echo input("callback") . '(' . json_encode($result, JSON_UNESCAPED_UNICODE) . ')';
            die();
        }
        $this->assign("app_list", $this->blinScopedAppList());
        return $this->fetch();
    }

    public function delete_moment()
    {
        $this->blinEnsureMomentsTables();
        $ids = explode(",", strval(input("id")));
        $reason = trim(strval(input("reason")));
        $now = date("Y-m-d H:i:s");
        foreach ($ids as $value) {
            $id = intval($value);
            if ($id <= 0) continue;
            $moment = Db::name("im_moments")->where("id", $id)->find();
            if (!$moment) continue;
            $this->blinRequireApp($moment["appid"]);
            Db::name("im_moments")->where("id", $id)->update([
                "status" => 0,
                "delete_reason" => $reason,
                "deleted_by" => isset($this->admin_info["id"]) ? intval($this->admin_info["id"]) : 0,
                "delete_time" => $now,
                "update_time" => $now,
            ]);
            if ($reason !== "") {
                Db::name("message_notification")->insert([
                    "title" => "朋友圈已删除",
                    "content" => "你发布的朋友圈已被管理员删除，原因：" . $reason,
                    "send_to" => 0,
                    "appid" => intval($moment["appid"]),
                    "type" => 0,
                    "time" => $now,
                    "postid" => $id,
                    "user_id" => intval($moment["user_id"]),
                    "status" => 0,
                    "is_admin" => 1,
                ]);
            }
        }
        return $this->success("删除成功");
    }

'''


MOMENTS_VIEW_SOURCE = r'''{extend name="layout" /}
{block name="body"}
<div class="container-fluid">
    <div class="row">
        <div class="col-lg-12">
            <div class="card">
                <header class="card-header">
                    <div class="card-title">朋友圈管理</div>
                </header>
                <div class="card-body">
                    <div class="row search-box">
                        <div class="col-md-3 mb-2">
                            <input class="form-control" type="text" id="search_username" placeholder="用户名或昵称">
                        </div>
                        <div class="col-md-3 mb-2">
                            <input class="form-control" type="text" id="search_content" placeholder="朋友圈内容">
                        </div>
                        <div class="col-md-2 mb-2">
                            <select class="form-control" id="search_status">
                                <option value="">全部状态</option>
                                <option value="1">正常</option>
                                <option value="0">已删除</option>
                            </select>
                        </div>
                        <div class="col-md-2 mb-2">
                            <select class="form-control" id="search_appid">
                                <option value="">全部应用</option>
                                {volist name="app_list" id="vo"}
                                <option value="{$vo.appid}">{$vo.appname}</option>
                                {/volist}
                            </select>
                        </div>
                        <div class="col-md-2 mb-2">
                            <a class="btn btn-default mb-2 mr-2" onclick="javascript:$('#table').bootstrapTable('refresh');" href="#!">
                                <i class="mdi mdi-magnify"></i> 搜索
                            </a>
                        </div>
                    </div>
                    <div id="toolbar" class="toolbar-btn-action">
                        {if checkRight('forum/delete_moment')}
                        <button id="btn_delete" type="button" class="btn btn-label btn-danger">
                            <label><i class="mdi mdi-window-close" aria-hidden="true"></i></label>删除
                        </button>
                        {/if}
                    </div>
                    <table id="table"></table>
                </div>
            </div>
        </div>
    </div>
</div>
{/block}
{block name="js"}
<script>
    window.parent.$("#iframe-content .mt-nav-bar").find('a.active').text("朋友圈管理");
    function htmlEscape(value) {
        return String(value || '').replace(/[&<>"']/g, function (m) {
            return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]);
        });
    }
    function imageFormatter(value, row) {
        var images = row.images || [];
        if (typeof images === 'string') {
            try { images = JSON.parse(images); } catch (e) { images = []; }
        }
        if (!images || images.length === 0) return '-';
        var html = '<div style="display:flex;gap:6px;align-items:center;">';
        for (var i = 0; i < Math.min(images.length, 3); i++) {
            html += '<img src="' + htmlEscape(images[i]) + '" style="width:42px;height:42px;border-radius:8px;object-fit:cover;border:1px solid #e5e7eb;">';
        }
        if (images.length > 3) html += '<span class="badge bg-info">+' + (images.length - 3) + '</span>';
        html += '</div>';
        return html;
    }
    $('#table').bootstrapTable({
        classes: 'table table-bordered table-hover table-striped lyear-table',
        url: "{$Request.root}/forum/moments",
        uniqueId: 'id',
        idField: 'id',
        clickToSelect: true,
        dataType: 'jsonp',
        method: 'get',
        toolbar: '#toolbar',
        pagination: true,
        showColumns: true,
        showRefresh: true,
        showButtonIcons: true,
        showButtonText: false,
        showFullscreen: true,
        showPaginationSwitch: true,
        totalField: 'total',
        undefinedText: '-',
        sortName: 'id',
        sortOrder: "desc",
        iconsPrefix: 'mdi',
        iconSize: 'mini',
        icons: {
            columns: 'mdi-table-column-remove',
            paginationSwitchDown: 'mdi-door-closed',
            paginationSwitchUp: 'mdi-door-open',
            refresh: 'mdi-refresh',
            toggleOff: 'mdi-toggle-switch-off',
            toggleOn: 'mdi-toggle-switch',
            fullscreen: 'mdi-monitor-screenshot',
            detailOpen: 'mdi-plus',
            detailClose: 'mdi-minus',
            export: 'mdi-export',
        },
        sidePagination: "server",
        pageNumber: 1,
        pageSize: 10,
        pageList: [5, 10, 25, 50, 100],
        paginationLoop: true,
        paginationPagesBySide: 2,
        buttonsClass: 'default',
        buttonsPrefix: 'btn',
        showExport: true,
        exportDataType: "selected",
        queryParams: function (params) {
            return {
                limit: params.limit,
                page: (params.offset / params.limit) + 1,
                sort: params.sort,
                sortOrder: params.order,
                username: $.trim($('#search_username').val()),
                content: $.trim($('#search_content').val()),
                status: $.trim($('#search_status').val()),
                appid: $.trim($('#search_appid').val()),
            };
        },
        columns: [{
            field: 'example',
            checkbox: true
        }, {
            field: 'id',
            title: 'ID',
            sortable: true
        }, {
            field: 'appname',
            title: '应用'
        }, {
            field: 'username',
            title: '发布用户',
            formatter: function (value, row) {
                return htmlEscape(row.username || '') + '（' + htmlEscape(row.nickname || '') + '）';
            }
        }, {
            field: 'content_short',
            title: '内容',
            formatter: function (value) { return htmlEscape(value || '[图片]'); }
        }, {
            field: 'images',
            title: '图片',
            formatter: imageFormatter
        }, {
            field: 'visibility_text',
            title: '可见范围',
            formatter: function (value, row) {
                return '<span class="badge bg-info">' + htmlEscape(row.visibility_text || value) + '</span>';
            }
        }, {
            field: 'status_text',
            title: '状态',
            formatter: function (value, row) {
                return row.status == 1 ? '<span class="badge bg-success">正常</span>' : '<span class="badge bg-secondary">已删除</span>';
            }
        }, {
            field: 'delete_reason',
            title: '删除原因',
            formatter: function (value) { return htmlEscape(value || '-'); }
        }, {
            field: 'create_time',
            title: '发布时间',
            sortable: true
        }, {
            field: 'operate',
            title: '操作',
            formatter: function (value, row) {
                var html = '';
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
        }]
    });

    function selectedIds() {
        var rows = $('#table').bootstrapTable('getSelections');
        return $.map(rows, function (row) { return row.id; }).join(',');
    }

    function askDeleteReason(ids) {
        if (!ids) return;
        var html = '<div style="padding:16px;">'
            + '<textarea id="moment_delete_reason" class="form-control" rows="4" placeholder="删除原因，可不填。不填则不会通知发布用户。"></textarea>'
            + '<small class="text-muted d-block mt-2">填写原因后，系统会通知发布朋友圈的用户。</small>'
            + '</div>';
        layer.open({
            type: 1,
            title: '删除朋友圈',
            area: ['460px', '260px'],
            content: html,
            btn: ['删除', '取消'],
            yes: function (index) {
                var reason = $.trim($('#moment_delete_reason').val());
                layer.close(index);
                doDelete(ids, reason);
            }
        });
    }

    function deleteMoment(id) {
        askDeleteReason(id);
    }

    function doDelete(ids, reason) {
        var l = $('body').lyearloading({
            opacity: 0.2,
            spinnerSize: 'lg',
            spinnerText: '后台处理中，请稍后...',
            textColorClass: 'text-info',
            spinnerColorClass: 'text-info'
        });
        $.ajax({
            type: "POST",
            url: "{$Request.root}/forum/delete_moment",
            data: { id: ids, reason: reason },
            dataType: "json",
            success: function (data) {
                l.destroy();
                if (data.code == 1) {
                    notify.success(data.msg);
                    $('#table').bootstrapTable('refresh');
                } else {
                    notify.error(data.msg || '删除失败');
                }
            },
            error: function () {
                l.destroy();
                notify.error("系统错误");
            }
        });
    }

    $("#btn_delete").click(function () {
        var ids = selectedIds();
        if (!ids) return false;
        askDeleteReason(ids);
    });
</script>
{/block}
'''


def patch_app_controller() -> bool:
    original = APP.read_text(encoding="utf-8")
    source = original
    source = source.replace(
        '"moments_switch":"0"}',
        '"moments_switch":"0","moments_visibility":"friends"}',
    )
    if "private function blinNormalizeMomentsVisibility" not in source:
        source = source.replace(
            "    public function edit()\n",
            '''    private function blinNormalizeMomentsVisibility($visibility)
    {
        $visibility = strtolower(trim(strval($visibility)));
        return in_array($visibility, ["all", "friends"]) ? $visibility : "friends";
    }

''' + "    public function edit()\n",
        )
    if '"moments_visibility" => $this->blinNormalizeMomentsVisibility' not in source:
        source = source.replace(
            '                "moments_switch" => isset($data["moments_switch"]) ? intval($data["moments_switch"]) : 1,\n',
            '                "moments_switch" => isset($data["moments_switch"]) ? intval($data["moments_switch"]) : 1,\n'
            '                "moments_visibility" => $this->blinNormalizeMomentsVisibility(isset($data["moments_visibility"]) ? $data["moments_visibility"] : "friends"),\n',
        )
    if '$result["forum_configuration"]["moments_visibility"] = "friends";' not in source:
        source = source.replace(
            '                if (!isset($result["forum_configuration"]["community_switch"])) {\n                    $result["forum_configuration"]["community_switch"] = 0;\n                }\n',
            '                if (!isset($result["forum_configuration"]["community_switch"])) {\n                    $result["forum_configuration"]["community_switch"] = 0;\n                }\n'
            '                if (!isset($result["forum_configuration"]["moments_switch"])) {\n                    $result["forum_configuration"]["moments_switch"] = 0;\n                }\n'
            '                if (!isset($result["forum_configuration"]["moments_visibility"])) {\n                    $result["forum_configuration"]["moments_visibility"] = "friends";\n                }\n',
        )
    return save(APP, original, source, "moments_visibility_app")


def patch_base() -> bool:
    original = BASE.read_text(encoding="utf-8")
    source = original
    if '$forumDefaults = [' not in source:
        source = source.replace(
            '            $result["forum_configuration"] = json_decode($result["forum_configuration"], true);\n            $result["userinfo_configuration"] = json_decode($result["userinfo_configuration"], true);\n',
            '''            $result["forum_configuration"] = json_decode($result["forum_configuration"], true);
            if (!is_array($result["forum_configuration"])) {
                $result["forum_configuration"] = [];
            }
            $forumDefaults = [
                "community_switch" => "0",
                "moments_switch" => "0",
                "moments_visibility" => "friends",
            ];
            $result["forum_configuration"] = array_merge($forumDefaults, $result["forum_configuration"]);
            $result["userinfo_configuration"] = json_decode($result["userinfo_configuration"], true);
''',
        )
    return save(BASE, original, source, "moments_visibility_base")


def patch_app_view() -> bool:
    original = APP_EDIT.read_text(encoding="utf-8")
    source = original
    insert = '''                        <div class="blin-setting-row blin-moments-switch-card">
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
                        <div class="blin-setting-row blin-moments-visibility-card">
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
    if 'name="moments_switch"' not in source:
        source = source.replace(
            '                        <div class="blin-setting-row blin-post-switch-card">\n',
            insert + '                        <div class="blin-setting-row blin-post-switch-card">\n',
        )
    elif 'name="moments_visibility"' not in source:
        source = source.replace(
            '                        <div class="blin-setting-row blin-post-switch-card">\n',
            insert.replace('''                        <div class="blin-setting-row blin-moments-switch-card">
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
''', '') + '                        <div class="blin-setting-row blin-post-switch-card">\n',
        )
    return save(APP_EDIT, original, source, "moments_visibility_view")


def patch_api() -> bool:
    original = API.read_text(encoding="utf-8")
    source = original
    pattern = r'\n    private function blinForumConfig\(.*?\n\n    //搜索用户接口'
    if re.search(pattern, source, flags=re.S):
        source = re.sub(pattern, "\n" + MOMENTS_API_BLOCK + "\n\n    //搜索用户接口", source, count=1, flags=re.S)
    else:
        source = source.replace("\n    //搜索用户接口\n", "\n" + MOMENTS_API_BLOCK + "\n\n    //搜索用户接口\n")
    return save(API, original, source, "moments_visibility_api")


def patch_forum() -> bool:
    original = FORUM.read_text(encoding="utf-8")
    source = original
    source = source.replace(
        "public $no_need_right = ['select_postinfo', 'select_commentinfo'];",
        "public $no_need_right = ['select_postinfo', 'select_commentinfo'];",
    )
    if "public function moments()" not in source:
        source = source.replace("    public function forum_section()\n", FORUM_METHODS + "    public function forum_section()\n")
    return save(FORUM, original, source, "moments_admin_forum")


def patch_moments_view() -> bool:
    if MOMENTS_VIEW.exists():
        original = MOMENTS_VIEW.read_text(encoding="utf-8")
    else:
        original = ""
    if original == MOMENTS_VIEW_SOURCE:
        print(f"NO_CHANGE {MOMENTS_VIEW}")
        return False
    if original:
        print(f"BACKUP {backup(MOMENTS_VIEW, 'moments_admin_view')}")
    MOMENTS_VIEW.write_text(MOMENTS_VIEW_SOURCE, encoding="utf-8")
    print(f"PATCHED {MOMENTS_VIEW}")
    return True


def main():
    changed = False
    changed = patch_app_controller() or changed
    changed = patch_base() or changed
    changed = patch_app_view() or changed
    changed = patch_api() or changed
    changed = patch_forum() or changed
    changed = patch_moments_view() or changed
    print("DONE changed=%s" % changed)
    print("NOTE run these SQL statements once if the menu is not visible:")
    print("INSERT INTO `mr_admin_permission` (`pid`,`name`,`url`,`icon`,`sort`,`is_out`,`is_menu`) SELECT id,'朋友圈管理','forum/moments','',7,2,1 FROM `mr_admin_permission` WHERE `url`='forum' AND NOT EXISTS (SELECT 1 FROM `mr_admin_permission` WHERE `url`='forum/moments') LIMIT 1;")
    print("INSERT INTO `mr_admin_permission` (`pid`,`name`,`url`,`icon`,`sort`,`is_out`,`is_menu`) SELECT id,'删除朋友圈','forum/delete_moment','',1,2,2 FROM `mr_admin_permission` WHERE `url`='forum/moments' AND NOT EXISTS (SELECT 1 FROM `mr_admin_permission` WHERE `url`='forum/delete_moment') LIMIT 1;")


if __name__ == "__main__":
    main()
