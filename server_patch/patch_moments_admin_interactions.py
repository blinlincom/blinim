#!/usr/bin/env python3
from pathlib import Path

ROOT = Path("/www/wwwroot/blinlin")
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
            Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_moments` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `user_id` int(11) NOT NULL DEFAULT 0, `content` text, `images` mediumtext, `video_url` varchar(500) NOT NULL DEFAULT '', `video_thumb` varchar(500) NOT NULL DEFAULT '', `visibility` varchar(16) NOT NULL DEFAULT 'friends', `like_count` int(11) NOT NULL DEFAULT 0, `comment_count` int(11) NOT NULL DEFAULT 0, `status` tinyint(1) NOT NULL DEFAULT 1, `delete_reason` varchar(500) NOT NULL DEFAULT '', `deleted_by` int(11) NOT NULL DEFAULT 0, `delete_time` datetime DEFAULT NULL, `create_time` datetime DEFAULT NULL, `update_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), KEY `idx_app_time` (`appid`,`status`,`create_time`), KEY `idx_user` (`appid`,`user_id`), KEY `idx_visibility` (`appid`,`status`,`visibility`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
            Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_moment_notifications` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `moment_id` int(11) NOT NULL DEFAULT 0, `comment_id` int(11) NOT NULL DEFAULT 0, `actor_id` int(11) NOT NULL DEFAULT 0, `receiver_id` int(11) NOT NULL DEFAULT 0, `action` varchar(20) NOT NULL DEFAULT '', `content` varchar(1000) NOT NULL DEFAULT '', `is_read` tinyint(1) NOT NULL DEFAULT 0, `create_time` datetime DEFAULT NULL, PRIMARY KEY (`id`), KEY `idx_receiver` (`appid`,`receiver_id`,`is_read`,`id`), KEY `idx_moment` (`appid`,`moment_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
            $this->blinEnsureMomentsColumn("video_url", "`video_url` varchar(500) NOT NULL DEFAULT '' AFTER `images`");
            $this->blinEnsureMomentsColumn("video_thumb", "`video_thumb` varchar(500) NOT NULL DEFAULT '' AFTER `video_url`");
            $this->blinEnsureMomentsColumn("visibility", "`visibility` varchar(16) NOT NULL DEFAULT 'friends' AFTER `video_thumb`");
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
            $allowSort = ["id", "create_time", "update_time", "status", "like_count", "comment_count"];
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
                ->field("m.id,m.appid,m.user_id,m.content,m.images,m.video_url,m.video_thumb,m.visibility,m.like_count,m.comment_count,m.status,m.delete_reason,m.deleted_by,m.delete_time,m.create_time,m.update_time,a.appname,u.username,u.nickname,u.usertx")
                ->order("m." . $sort, $sortOrder)
                ->page($page, $limit)
                ->select();
            foreach ($rows as $key => $row) {
                $images = json_decode(strval(isset($row["images"]) ? $row["images"] : "[]"), true);
                if (!is_array($images)) $images = [];
                $rows[$key]["images"] = array_slice($images, 0, 9);
                $rows[$key]["images_count"] = count($rows[$key]["images"]);
                $rows[$key]["has_video"] = trim(strval(isset($row["video_url"]) ? $row["video_url"] : "")) !== "" ? 1 : 0;
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
                Db::name("im_moment_notifications")->insert([
                    "appid" => intval($moment["appid"]),
                    "moment_id" => $id,
                    "comment_id" => 0,
                    "actor_id" => 0,
                    "receiver_id" => intval($moment["user_id"]),
                    "action" => "admin_delete",
                    "content" => "你的朋友圈已被管理员删除，原因：" . mb_substr($reason, 0, 460, "UTF-8"),
                    "is_read" => 0,
                    "create_time" => $now,
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
        var html = '<div style="display:flex;gap:6px;align-items:center;flex-wrap:wrap;">';
        if (row.has_video == 1 || row.video_url) {
            html += '<span class="badge bg-warning"><i class="mdi mdi-play-circle-outline"></i> 视频</span>';
        }
        if (images && images.length > 0) {
            for (var i = 0; i < Math.min(images.length, 3); i++) {
                html += '<img src="' + htmlEscape(images[i]) + '" style="width:42px;height:42px;border-radius:8px;object-fit:cover;border:1px solid #e5e7eb;">';
            }
            if (images.length > 3) html += '<span class="badge bg-info">+' + (images.length - 3) + '</span>';
        }
        html += '</div>';
        return html === '<div style="display:flex;gap:6px;align-items:center;flex-wrap:wrap;"></div>' ? '-' : html;
    }
    function statsFormatter(value, row) {
        return '<span class="badge bg-success">赞 ' + (row.like_count || 0) + '</span> '
            + '<span class="badge bg-info">评 ' + (row.comment_count || 0) + '</span>';
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
            formatter: function (value, row) { return htmlEscape(value || (row.has_video == 1 ? '[视频]' : '[图片]')); }
        }, {
            field: 'images',
            title: '媒体',
            formatter: imageFormatter
        }, {
            field: 'like_count',
            title: '互动',
            sortable: true,
            formatter: statsFormatter
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
            + '<small class="text-muted d-block mt-2">填写原因后，系统会通过朋友圈消息通知发布用户。</small>'
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


def patch_forum() -> bool:
    original = FORUM.read_text(encoding="utf-8")
    start = original.find("    private function blinEnsureMomentsColumn(")
    end = original.find("    public function forum_section()", start)
    if start < 0 or end < 0:
        raise SystemExit("forum_moments_block_not_found")
    source = original[:start] + FORUM_METHODS + original[end:]
    return save(FORUM, original, source, "moments_admin_interactions")


def patch_view() -> bool:
    original = MOMENTS_VIEW.read_text(encoding="utf-8") if MOMENTS_VIEW.exists() else ""
    return save(MOMENTS_VIEW, original, MOMENTS_VIEW_SOURCE, "moments_admin_interactions_view")


def main() -> None:
    changed = False
    changed = patch_forum() or changed
    changed = patch_view() or changed
    print("DONE changed=%s" % changed)


if __name__ == "__main__":
    main()
