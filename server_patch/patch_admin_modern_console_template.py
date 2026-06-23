#!/usr/bin/env python3
"""Replace the admin console shell with a modern visual management template.

This patch targets the current ThinkPHP upgraded structure:
  /www/wwwroot/blinlin/app/admin/view

It keeps route URLs, permission checks, form names, table IDs, Bootstrap Table
initialization, modal IDs, and existing page JavaScript intact. The replacement
focuses on the console shell, login page, shared layout, dashboard, and global
visual treatment for all existing data tables/forms/cards.
"""
from datetime import datetime
from pathlib import Path
import re
import shutil


ROOT = Path("/www/wwwroot/blinlin")
ADMIN_VIEW = ROOT / "app/admin/view"
INDEX_CONTROLLER = ROOT / "app/admin/controller/Index.php"
MODERN_CSS = ROOT / "public/static/css/modern-admin.css"
INDEX_VIEW = ADMIN_VIEW / "index/index.html"
LAYOUT_VIEW = ADMIN_VIEW / "layout.html"
LOGIN_VIEW = ADMIN_VIEW / "login/index.html"
HOME_VIEW = ADMIN_VIEW / "index/home.html"
RUNTIME_ADMIN = ROOT / "runtime/admin"
RUNTIME_CACHE = ROOT / "runtime/cache"
VERSION = "202606231030"


def backup(path: Path, suffix: str) -> None:
    if not path.exists():
        return
    target = path.with_name(
        f"{path.name}.bak_{suffix}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    shutil.copy2(path, target)
    print(f"BACKUP {target}")


def write_if_changed(path: Path, text: str, suffix: str) -> bool:
    current = path.read_text(errors="ignore") if path.exists() else ""
    if current == text:
        return False
    backup(path, suffix)
    path.write_text(text, encoding="utf-8")
    print(f"UPDATED {path}")
    return True


def replace_function(source: str, name: str, replacement: str) -> str:
    marker = f"    public function {name}("
    start = source.find(marker)
    if start < 0:
        raise RuntimeError(f"{name} not found")
    brace = source.find("{", start)
    if brace < 0:
        raise RuntimeError(f"{name} body not found")
    depth = 0
    for i in range(brace, len(source)):
        ch = source[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return source[:start] + replacement.rstrip() + "\n" + source[i + 1 :]
    raise RuntimeError(f"{name} end not found")


def patch_index_controller() -> bool:
    source = INDEX_CONTROLLER.read_text(errors="ignore")
    updated = replace_function(source, "home", INDEX_HOME_FUNCTION)
    return write_if_changed(INDEX_CONTROLLER, updated, "modern_console_controller")


def patch_views() -> int:
    changed = 0
    changed += int(write_if_changed(INDEX_VIEW, INDEX_TEMPLATE, "modern_console_shell"))
    changed += int(write_if_changed(LAYOUT_VIEW, LAYOUT_TEMPLATE, "modern_console_layout"))
    changed += int(write_if_changed(LOGIN_VIEW, LOGIN_TEMPLATE, "modern_console_login"))
    changed += int(write_if_changed(HOME_VIEW, HOME_TEMPLATE, "modern_console_home"))
    return changed


def patch_css() -> bool:
    return write_if_changed(MODERN_CSS, MODERN_CONSOLE_CSS, "modern_console_css")


def clear_runtime() -> None:
    for root in [RUNTIME_ADMIN / "temp", RUNTIME_CACHE]:
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if path.is_file():
                try:
                    path.unlink()
                except Exception:
                    pass


INDEX_HOME_FUNCTION = r'''    public function home()
    {
        $appid = input("appid");
        $appname = input("appname") ? input("appname") : "全部应用";
        $where = "1=1";
        if ($appid !== "" && $appid !== null) {
            $appid = intval($appid);
            if (method_exists($this, "blinRequireApp")) $this->blinRequireApp($appid);
            $where .= " and appid={$appid}";
        } elseif (method_exists($this, "blinIsSuperAdmin") && !$this->blinIsSuperAdmin()) {
            $ids = $this->blinAdminAppIds();
            $where .= $ids ? " and appid in (" . implode(",", array_map("intval", $ids)) . ")" : " and 1=0";
        }

        $data = [];
        $data["user_total"] = Db::name("user")->where($where)->count();
        $data["app_view_today"] = Db::name("polymorphic")->where("type=0")->where($where)->count();
        $data["km_total"] = Db::name("km")->where($where)->count();
        $data["shop_total"] = Db::name("shop_products")->where($where)->count();
        $data["order_total"] = Db::name("order_records")->where($where)->count();
        $data["withdrawal_total"] = Db::name("withdrawal_record")->where($where)->count();
        $data["notes_total"] = Db::name("notes")->where($where)->count();
        $data["plate_total"] = Db::name("forum_section")->where("pid=0")->where($where)->count();
        $data["posts_total"] = Db::name("forum_posts")->where($where)->count();
        $data["file_total"] = Db::name("file")->count();
        $time = time() - intval(config("system.user_online_time"));
        $data["online_total"] = Db::name("online_record")->where("last_activity_time >= {$time}")->where($where)->count();
        $data["bagge_total"] = Db::name("bagge")->where($where)->count();

        $visual = [
            "apps" => Db::name("app")->count(),
            "private_messages" => $this->blinAdminCountTable("im_private_messages", $where),
            "group_messages" => $this->blinAdminCountTable("im_group_messages", $where),
            "groups" => $this->blinAdminCountTable("im_groups", $where),
            "moments" => $this->blinAdminCountTable("moments", $where),
            "transfers" => $this->blinAdminCountTable("im_transfer_order", $where),
            "red_packets" => $this->blinAdminCountTable("im_red_packet_order", $where),
            "bills" => $this->blinAdminCountTable("money_bill", $where),
            "files" => intval($data["file_total"]),
            "orders" => intval($data["order_total"]),
            "users" => intval($data["user_total"]),
            "online" => intval($data["online_total"]),
        ];

        $this->assign("appid", $appid);
        $this->assign("appname", $appname);
        $this->assign("data", $data);
        $this->assign("visual", $visual);

        $user_register_date = [];
        $user_register_count = [];
        $user_login_date = [];
        $user_login_count = [];
        $user_sign_date = [];
        $user_sign_count = [];
        $order_record_date = [];
        $order_record_count = ["money" => [], "integral" => [], "other" => []];
        $message_trend = ["private" => [], "group" => []];
        for ($i = 7; $i >= 0; $i--) {
            $date = date("Y-m-d", strtotime("-{$i} day"));
            $start = $date . " 00:00:00";
            $end = $date . " 23:59:59";
            $user_register_date[] = $date;
            $user_register_count[] = Db::name("user")->where($where)->whereTime("create_time", "between", [$start, $end])->count();
            $user_login_date[] = $date;
            $user_login_count[] = Db::name("user_log")->where($where)->where("type", "=", 1)->whereTime("create_time", "between", [$start, $end])->count();
            $user_sign_date[] = $date;
            $user_sign_count[] = Db::name("user_log")->where($where)->where("type", "=", 0)->whereTime("create_time", "between", [$start, $end])->count();
            $order_record_date[] = $date;
            $order_record_count["other"][] = Db::name("order_records")->where("payment_method", ">=", 2)->where("status", "=", 1)->where($where)->whereTime("payment_time", "between", [$start, $end])->count();
            $order_record_count["integral"][] = Db::name("order_records")->where("payment_method", "=", 1)->where("status", "=", 1)->where($where)->whereTime("payment_time", "between", [$start, $end])->count();
            $order_record_count["money"][] = Db::name("order_records")->where("payment_method", "=", 0)->where("status", "=", 1)->where($where)->whereTime("payment_time", "between", [$start, $end])->count();
            $message_trend["private"][] = $this->blinAdminCountTableBetween("im_private_messages", $where, "create_time", $start, $end);
            $message_trend["group"][] = $this->blinAdminCountTableBetween("im_group_messages", $where, "create_time", $start, $end);
        }
        $this->assign("user_register", ["date" => $user_register_date, "count" => $user_register_count]);
        $this->assign("user_login", ["date" => $user_login_date, "count" => $user_login_count]);
        $this->assign("user_sign", ["date" => $user_sign_date, "count" => $user_sign_count]);
        $this->assign("order_record", ["date" => $order_record_date, "count" => $order_record_count]);
        $this->assign("message_trend", ["date" => $order_record_date, "count" => $message_trend]);
        return $this->fetch();
    }

    private function blinAdminCountTable($table, $where)
    {
        try {
            return intval(Db::name($table)->where($where)->count());
        } catch (\Exception $e) {
            return 0;
        }
    }

    private function blinAdminCountTableBetween($table, $where, $field, $start, $end)
    {
        try {
            return intval(Db::name($table)->where($where)->whereTime($field, "between", [$start, $end])->count());
        } catch (\Exception $e) {
            return 0;
        }
    }'''


INDEX_TEMPLATE = r'''<!DOCTYPE html>
<html lang="zh">

<head>
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=0, minimal-ui">
    <title>Blin IM 管理后台</title>
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-touch-fullscreen" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="default">
    <link rel="stylesheet" type="text/css" href="/static/css/materialdesignicons.min.css">
    <link rel="stylesheet" type="text/css" href="/static/css/bootstrap.min.css">
    <link rel="stylesheet" type="text/css" href="/static/css/animate.min.css">
    <link rel="stylesheet" type="text/css" href="/static/js/bootstrap-multitabs/multitabs.min.css">
    <link rel="stylesheet" type="text/css" href="/static/js/jquery-confirm/jquery-confirm.min.css">
    <link rel="stylesheet" type="text/css" href="/static/css/style.min.css">
    <link rel="stylesheet" type="text/css" href="/static/css/modern-admin.css?v=202606231030">
</head>

<body class="lyear-index blin-console-shell">
    <div class="lyear-layout-web">
        <div class="lyear-layout-container">
            <aside class="lyear-layout-sidebar">
                <div id="logo" class="sidebar-header">
                    <a href="{$Request.root}" class="blin-console-logo">
                        <span class="blin-console-logo-mark">B</span>
                        <span class="blin-console-logo-copy">
                            <strong>Blin IM</strong>
                            <small>运营管理</small>
                        </span>
                    </a>
                </div>
                <div class="blin-sidebar-search">
                    <i class="mdi mdi-magnify"></i>
                    <input id="blinMenuSearch" type="text" placeholder="搜索功能">
                </div>
                <div class="lyear-layout-sidebar-info lyear-scroll">
                    <nav class="sidebar-main"></nav>
                    <div class="sidebar-footer">
                        <span>Commercial IM Console</span>
                    </div>
                </div>
            </aside>

            <header class="lyear-layout-header">
                <nav class="navbar">
                    <div class="navbar-left">
                        <button type="button" class="lyear-aside-toggler blin-icon-button" aria-label="切换菜单">
                            <span class="lyear-toggler-bar"></span>
                            <span class="lyear-toggler-bar"></span>
                            <span class="lyear-toggler-bar"></span>
                        </button>
                        <div class="blin-console-title">
                            <strong>数据运营台</strong>
                            <span>应用 / 用户 / 消息 / 财务 / 系统</span>
                        </div>
                    </div>
                    <ul class="navbar-right d-flex align-items-center">
                        <li>
                            <a href="javascript:void(0)" onclick="Clear_All()" class="blin-top-action">
                                <i class="mdi mdi-broom"></i>
                                <span>清缓存</span>
                            </a>
                        </li>
                        <li class="dropdown">
                            <a href="javascript:void(0)" data-bs-toggle="dropdown" class="dropdown-toggle admin-profile-toggle">
                                <img class="avatar-md rounded-circle" src="{$admin_info.avatar}" alt="{$admin_info.nickname}" />
                                <span class="admin-profile-name">{$admin_info.nickname}</span>
                            </a>
                            <ul class="dropdown-menu dropdown-menu-end">
                                <li>
                                    <a class="multitabs dropdown-item" data-url="{$Request.root}/admin/edit_profile" href="javascript:void(0)">
                                        <i class="mdi mdi-account-outline"></i>
                                        <span>个人信息</span>
                                    </a>
                                </li>
                                <li>
                                    <a class="dropdown-item" href="javascript:void(0)" onclick="Clear_All()">
                                        <i class="mdi mdi-delete-sweep-outline"></i>
                                        <span>清空缓存</span>
                                    </a>
                                </li>
                                <li class="dropdown-divider"></li>
                                <li>
                                    <a class="dropdown-item text-danger" href="{$Request.root}/login/logout">
                                        <i class="mdi mdi-logout-variant"></i>
                                        <span>退出登录</span>
                                    </a>
                                </li>
                            </ul>
                        </li>
                    </ul>
                </nav>
            </header>

            <main class="lyear-layout-content">
                <div id="iframe-content"></div>
            </main>
        </div>
    </div>

    <script type="text/javascript" src="/static/js/jquery.min.js"></script>
    <script type="text/javascript" src="/static/js/popper.min.js"></script>
    <script type="text/javascript" src="/static/js/bootstrap.min.js"></script>
    <script type="text/javascript" src="/static/js/perfect-scrollbar.min.js"></script>
    <script type="text/javascript" src="/static/js/bootstrap-multitabs/multitabs.min.js"></script>
    <script type="text/javascript" src="/static/js/jquery.cookie.min.js"></script>
    <script type="text/javascript" src="/static/js/jquery-confirm/jquery-confirm.min.js"></script>
    <script type="text/javascript">
        var menu_list = {$permission|raw};
        setSidebar(menu_list);

        function setSidebar(data) {
            if (data.length == 0) return false;
            var treeObj = getTrees(data, 0, 'id', 'pid', 'children');
            $('.sidebar-main').append(createMenu(treeObj, true));
        }
        function createMenu(data, is_frist) {
            var menu_body = is_frist ? '<ul class="nav-drawer">' : '<ul class="nav nav-subnav">';
            for (var i = 0; i < data.length; i++) {
                var iframe_class = data[i].is_out == 1 ? 'target="_blank"' : 'class="multitabs"';
                var icon_div = data[i].pid == 0 ? '<i class="' + data[i].icon + '"></i>' : '<span class="blin-sub-dot"></span>';
                var menuName = '<span class="blin-sidebar-menu-text">' + data[i].name + '</span>';
                var selected = '';
                var homeIdName = '';
                if (data[i].children && data[i].children.length > 0) {
                    var nav_selected = i == 0 ? ' active open' : '';
                    menu_body += '<li class="nav-item nav-item-has-subnav ' + nav_selected + '"><a href="javascript:void(0)">' + icon_div + menuName + '</a>';
                    menu_body += createMenu(data[i].children, false);
                } else {
                    if (searchStrEach(data[i].url, '/') > 2) {
                        if (menu_body.indexOf('default-page') == -1) {
                            selected = 'active';
                            homeIdName = ' id="default-page"';
                        }
                        menu_body += '<li class="nav-item ' + selected + '"><a href="' + data[i].url + '" ' + iframe_class + homeIdName + '>' + icon_div + menuName + '</a>';
                    }
                }
                menu_body += '</li>';
            }
            menu_body += '</ul>';
            return menu_body;
        }
        function getTrees(list, parentId, idName, parentIdName, childrenName) {
            var items = {};
            for (var i = 0; i < list.length; i++) {
                var key = list[i][parentIdName];
                if (items[key]) items[key].push(list[i]);
                else items[key] = [list[i]];
            }
            return formatTree(items, parentId, idName, childrenName);
        }
        function formatTree(items, parentId, idName, childrenName) {
            var result = [];
            if (!items[parentId]) return result;
            for (var t in items[parentId]) {
                items[parentId][t][childrenName] = formatTree(items, items[parentId][t][idName], idName, childrenName);
                result.push(items[parentId][t]);
            }
            return result;
        }
        function searchStrEach(str, target) {
            var sum = 0;
            for (var key of str) if (key == target) sum++;
            return sum;
        }
        $(document).on('input', '#blinMenuSearch', function () {
            var keyword = $.trim($(this).val()).toLowerCase();
            $('.sidebar-main .nav-item').show();
            if (!keyword) return;
            $('.sidebar-main .nav-subnav .nav-item').each(function () {
                var matched = $(this).text().toLowerCase().indexOf(keyword) >= 0;
                $(this).toggle(matched);
                if (matched) $(this).parents('.nav-item-has-subnav').show().addClass('open').children('.nav-subnav').show();
            });
        });
    </script>
    <script type="text/javascript" src="/static/js/index.min.js"></script>
    <script type="text/javascript" src="/static/js/lyear-loading.js"></script>
    <script type="text/javascript" src="/static/js/notify_stand.js"></script>
    <script>
        function Clear_All() {
            sessionStorage.clear();
            var l = $('body').lyearloading({ opacity: 0.2, spinnerSize: 'lg' });
            $.ajax({
                type: 'get',
                url: "{$Request.root}/index/cache",
                data: {},
                dataType: "json",
                success: function (data) {
                    setTimeout(function () {
                        l.destroy();
                        notify.success(data.msg, 1000, function () { window.location.reload(); });
                    }, 600);
                }
            });
        }
    </script>
</body>
</html>
'''


LAYOUT_TEMPLATE = r'''<!DOCTYPE html>
<html lang="zh">

<head>
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=0, minimal-ui">
    <title></title>
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-touch-fullscreen" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="default">
    <link rel="stylesheet" type="text/css" href="/static/css/materialdesignicons.min.css">
    <link rel="stylesheet" type="text/css" href="/static/css/bootstrap.min.css">
    <link rel="stylesheet" type="text/css" href="/static/js/bootstrap-select/bootstrap-select.min.css">
    <link rel="stylesheet" href="/static/js/bootstrap-table/bootstrap-table.min.css">
    <link rel="stylesheet" type="text/css" href="/static/css/style.min.css">
    <link rel="stylesheet" type="text/css" href="/static/css/modern-admin.css?v=202606231030">
</head>

<body class="blin-console-content">
    {block name="body"}{/block}
    <script type="text/javascript" src="/static/js/jquery.min.js"></script>
    <script type="text/javascript" src="/static/js/popper.min.js"></script>
    <script type="text/javascript" src="/static/js/bootstrap.min.js"></script>
    <script type="text/javascript" src="/static/js/lyear-loading.js"></script>
    <script type="text/javascript" src="/static/js/bootstrap-select/bootstrap-select.min.js"></script>
    <script type="text/javascript" src="/static/js/bootstrap-select/i18n/defaults-zh_CN.min.js"></script>
    <script type="text/javascript" src="/static/js/main.min.js"></script>
    <script type="text/javascript" src="/static/js/layer/layer.js"></script>
    <script type="text/javascript" src="/static/js/notify_stand.js"></script>
    <script type="text/javascript" src="/static/js/bootstrap-table/bootstrap-table.js"></script>
    <script type="text/javascript" src="/static/js/bootstrap-table/locale/bootstrap-table-zh-CN.min.js"></script>
    <script type="text/javascript" src="/static/js/bootstrap-table/extensions/export/table-export.min.js"></script>
    <script type="text/javascript" src="/static/js/bootstrap-table/extensions/export/bootstrap-table-export.min.js"></script>
    <script type="text/javascript" src="/static/js/momentjs/moment.min.js"></script>
    <script type="text/javascript" src="/static/js/bootstrap-datetimepicker/bootstrap-datetimepicker.min.js"></script>
    <script type="text/javascript" src="/static/js/momentjs/locale/zh-cn.min.js"></script>
    <script>
        $(document).ready(function () {
            $(document).on('click', '.file-browser', function () {
                var $browser = $(this);
                var file = $browser.closest('.file-group').find('[type="file"]');
                file.on('click', function (e) { e.stopPropagation(); });
                file.trigger('click');
            });

            $(document).on('change', '.file-group [type="file"]', function () {
                var $this = $(this);
                var $input = $(this)[0];
                var formFile = new FormData();
                if ($input.files.length == 0) return false;
                formFile.append("file", $input.files[0]);
                var l = $('body').lyearloading({ opacity: 0.2, spinnerSize: 'lg' });
                $.ajax({
                    url: '{$Request.root}/index/upload',
                    data: formFile,
                    type: "POST",
                    dataType: "json",
                    cache: false,
                    processData: false,
                    contentType: false,
                    success: function (res) {
                        l.destroy();
                        if (res.code === 1) {
                            notify.success("上传成功");
                            $this.closest('.file-group').find('.file-value').val(res.data.filePath);
                        } else {
                            notify.error(res.msg);
                        }
                    },
                    error: function () {
                        l.destroy();
                        notify.error("服务器错误");
                    }
                });
                $(".file-group [type='file']").val('');
            });
        });

        function getSelectedRows(idname = "id") {
            var selRows = $("#table").bootstrapTable("getSelections");
            if (selRows.length == 0) {
                notify.error("请至少选择一行");
                return "";
            }
            var postData = "";
            $.each(selRows, function (i) {
                postData += selRows[i][idname];
                if (i < selRows.length - 1) postData += ",";
            });
            return postData;
        }

        $(document).ready(function () {
            $('.selectpicker').selectpicker();
        });
    </script>
    {block name="js"}{/block}
</body>
</html>
'''


LOGIN_TEMPLATE = r'''<!DOCTYPE html>
<html lang="zh">

<head>
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=0, minimal-ui">
    <title>后台登录</title>
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-touch-fullscreen" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="default">
    <link rel="stylesheet" type="text/css" href="/static/css/materialdesignicons.min.css">
    <link rel="stylesheet" type="text/css" href="/static/css/bootstrap.min.css">
    <link rel="stylesheet" type="text/css" href="/static/css/animate.min.css">
    <link rel="stylesheet" type="text/css" href="/static/css/style.min.css">
    <link rel="stylesheet" type="text/css" href="/static/css/modern-admin.css?v=202606231030">
</head>

<body class="center-vh blin-console-login">
    <main class="blin-login-layout">
        <section class="blin-login-panel">
            <div class="blin-login-brand">
                <div class="blin-login-mark">B</div>
                <div>
                    <h1>Blin IM</h1>
                    <p>商业即时通讯运营后台</p>
                </div>
            </div>
            <form action="{:url('login/index')}" method="post" class="signin-form needs-validation" novalidate>
                <div class="blin-login-field">
                    <i class="mdi mdi-account-outline"></i>
                    <input type="text" class="form-control" name="username" placeholder="用户名" required>
                </div>
                <div class="blin-login-field">
                    <i class="mdi mdi-lock-outline"></i>
                    <input type="password" class="form-control" name="password" id="password" placeholder="密码" required>
                </div>
                {if $captcha_status == 0}
                <div class="row g-2 mb-3">
                    <div class="col-7">
                        <div class="blin-login-field mb-0">
                            <i class="mdi mdi-shield-check-outline"></i>
                            <input type="text" name="captcha" class="form-control" placeholder="验证码" required>
                        </div>
                    </div>
                    <div class="col-5">
                        <img src="{:captcha_src()}" class="blin-login-captcha" id="captcha" onclick="this.src=this.src+'?d='+Math.random();" title="点击刷新" alt="captcha">
                    </div>
                </div>
                {/if}
                <div class="d-flex align-items-center justify-content-between mb-4">
                    <label class="form-check blin-check">
                        <input type="checkbox" class="form-check-input" name="rememberme">
                        <span class="form-check-label">保持登录</span>
                    </label>
                </div>
                <button class="btn btn-primary blin-login-submit" type="submit">进入后台</button>
            </form>
        </section>
        <aside class="blin-login-visual">
            <div class="blin-login-visual-card">
                <span>IM Console</span>
                <strong>消息、用户、财务、系统配置统一可视化</strong>
                <div class="blin-login-bars"><i></i><i></i><i></i><i></i></div>
            </div>
        </aside>
    </main>
    <script type="text/javascript" src="/static/js/jquery.min.js"></script>
    <script type="text/javascript" src="/static/js/popper.min.js"></script>
    <script type="text/javascript" src="/static/js/bootstrap.min.js"></script>
    <script type="text/javascript" src="/static/js/lyear-loading.js"></script>
    <script type="text/javascript" src="/static/js/bootstrap-notify.min.js"></script>
    <script type="text/javascript" src="/static/js/notify_stand.js"></script>
    <script type="text/javascript">
        var loader;
        $(document).ajaxStart(function () {
            $("button:submit").html('登录中...').attr("disabled", true);
            loader = $('button:submit').lyearloading({ opacity: 0.2, spinnerSize: 'nm' });
        }).ajaxStop(function () {
            if (loader) loader.destroy();
            $("button:submit").html('进入后台').attr("disabled", false);
        });
        $('.signin-form').on('submit', function (event) {
            if ($(this)[0].checkValidity() === false) {
                event.preventDefault();
                event.stopPropagation();
                $(this).addClass('was-validated');
                return false;
            }
            $.post($(this).attr('action'), $(this).serialize(), function (res) {
                if (res.code == 1) {
                    notify.success('登录成功，正在跳转...');
                    setTimeout(function () { window.location.reload(); }, 800);
                } else {
                    notify.error(res.msg);
                    $('#password').val('');
                    $("#captcha").click();
                }
            }).fail(function () {
                notify.error('网络错误，请稍候再试');
            });
            return false;
        });
    </script>
</body>
</html>
'''


HOME_TEMPLATE = r'''{extend name="layout" /}
{block name="body"}
<div class="container-fluid blin-dashboard">
    <div class="blin-page-hero">
        <div>
            <span class="blin-eyebrow">Overview</span>
            <h1>运营数据总览</h1>
            <p>把应用、用户、消息、财务、内容和文件数据集中到同一个可视化看板。</p>
        </div>
        <div class="dropdown">
            <button class="btn btn-secondary dropdown-toggle" type="button" id="appSwitch" data-bs-toggle="dropdown" aria-expanded="false">
                {$appname}
            </button>
            <ul class="dropdown-menu dropdown-menu-end" aria-labelledby="appSwitch">
                <li><a class="dropdown-item" href="{$Request.root}/index/home">全部应用</a></li>
                {volist name=":blin_admin_table_all('app')" id="vo"}
                <li><a class="dropdown-item" href="{$Request.root}/index/home?appid={$vo.appid}&appname={$vo.appname}">{$vo.appname} <span>{$vo.appid}</span></a></li>
                {/volist}
            </ul>
        </div>
    </div>

    <div class="blin-metric-grid">
        <div class="blin-metric-card primary"><i class="mdi mdi-account-group-outline"></i><span>用户</span><strong>{$data["user_total"]}</strong><small>当前应用范围</small></div>
        <div class="blin-metric-card success"><i class="mdi mdi-message-text-outline"></i><span>私聊消息</span><strong>{$visual.private_messages}</strong><small>累计发送</small></div>
        <div class="blin-metric-card cyan"><i class="mdi mdi-forum-outline"></i><span>群聊消息</span><strong>{$visual.group_messages}</strong><small>累计发送</small></div>
        <div class="blin-metric-card warning"><i class="mdi mdi-wallet-outline"></i><span>订单</span><strong>{$data["order_total"]}</strong><small>商城交易</small></div>
        <div class="blin-metric-card"><i class="mdi mdi-account-voice"></i><span>在线</span><strong>{$data["online_total"]}</strong><small>实时活跃</small></div>
        <div class="blin-metric-card"><i class="mdi mdi-account-multiple-outline"></i><span>群聊</span><strong>{$visual.groups}</strong><small>群组规模</small></div>
        <div class="blin-metric-card"><i class="mdi mdi-gift-outline"></i><span>红包</span><strong>{$visual.red_packets}</strong><small>红包记录</small></div>
        <div class="blin-metric-card"><i class="mdi mdi-swap-horizontal"></i><span>转账</span><strong>{$visual.transfers}</strong><small>转账记录</small></div>
        <div class="blin-metric-card"><i class="mdi mdi-note-text-outline"></i><span>朋友圈</span><strong>{$visual.moments}</strong><small>动态内容</small></div>
        <div class="blin-metric-card"><i class="mdi mdi-package-variant-closed"></i><span>商品</span><strong>{$data["shop_total"]}</strong><small>商品中心</small></div>
        <div class="blin-metric-card"><i class="mdi mdi-file-cloud-outline"></i><span>文件</span><strong>{$data["file_total"]}</strong><small>上传资源</small></div>
        <div class="blin-metric-card"><i class="mdi mdi-seal-variant"></i><span>称号</span><strong>{$data["bagge_total"]}</strong><small>用户标识</small></div>
    </div>

    <div class="row g-4">
        <div class="col-xl-8">
            <div class="card blin-chart-card">
                <header class="card-header">
                    <div>
                        <span class="blin-eyebrow">Trend</span>
                        <div class="card-title">近 8 天用户增长与活跃</div>
                    </div>
                </header>
                <div class="card-body"><canvas id="chart-user-trend"></canvas></div>
            </div>
        </div>
        <div class="col-xl-4">
            <div class="card blin-chart-card">
                <header class="card-header">
                    <div>
                        <span class="blin-eyebrow">Content</span>
                        <div class="card-title">业务数据占比</div>
                    </div>
                </header>
                <div class="card-body"><canvas id="chart-business-radar"></canvas></div>
            </div>
        </div>
        <div class="col-xl-6">
            <div class="card blin-chart-card">
                <header class="card-header">
                    <div>
                        <span class="blin-eyebrow">Message</span>
                        <div class="card-title">近 8 天消息量</div>
                    </div>
                </header>
                <div class="card-body"><canvas id="chart-message-trend"></canvas></div>
            </div>
        </div>
        <div class="col-xl-6">
            <div class="card blin-chart-card">
                <header class="card-header">
                    <div>
                        <span class="blin-eyebrow">Trade</span>
                        <div class="card-title">近 8 天订单类型</div>
                    </div>
                </header>
                <div class="card-body"><canvas id="chart-order-record"></canvas></div>
            </div>
        </div>
    </div>
</div>
{/block}
{block name="js"}
<script type="text/javascript" src="/static/js/chart.min.js"></script>
<script type="text/javascript">
window.parent.$("#iframe-content .mt-nav-bar").find('a.active').text("运营总览");
Chart.defaults.global.defaultFontFamily = '-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Microsoft YaHei",sans-serif';
Chart.defaults.global.defaultFontColor = '#64748b';
var labels = {$user_register['date']|array_values|json_encode|raw};
var primary = '#6366F1', success = '#10B981', amber = '#F59E0B', cyan = '#06B6D4', danger = '#EF4444';
new Chart($("#chart-user-trend"), {
    type: 'line',
    data: { labels: labels, datasets: [
        { label: "注册", borderColor: primary, backgroundColor: 'rgba(99,102,241,.12)', pointRadius: 3, borderWidth: 3, data: {$user_register['count']|array_values|json_encode|raw} },
        { label: "登录", borderColor: success, backgroundColor: 'rgba(16,185,129,.10)', pointRadius: 3, borderWidth: 3, data: {$user_login['count']|array_values|json_encode|raw} },
        { label: "签到", borderColor: amber, backgroundColor: 'rgba(245,158,11,.12)', pointRadius: 3, borderWidth: 3, data: {$user_sign['count']|array_values|json_encode|raw} }
    ] },
    options: { responsive: true, maintainAspectRatio: false, legend: { labels: { usePointStyle: true } }, scales: { yAxes: [{ ticks: { beginAtZero: true }, gridLines: { color: 'rgba(148,163,184,.18)' } }], xAxes: [{ gridLines: { display: false } }] } }
});
new Chart($("#chart-message-trend"), {
    type: 'bar',
    data: { labels: labels, datasets: [
        { label: "私聊", backgroundColor: primary, data: {$message_trend['count']["private"]|array_values|json_encode|raw} },
        { label: "群聊", backgroundColor: cyan, data: {$message_trend['count']["group"]|array_values|json_encode|raw} }
    ] },
    options: { responsive: true, maintainAspectRatio: false, legend: { labels: { usePointStyle: true } }, scales: { yAxes: [{ ticks: { beginAtZero: true }, gridLines: { color: 'rgba(148,163,184,.18)' } }], xAxes: [{ gridLines: { display: false } }] } }
});
new Chart($("#chart-order-record"), {
    type: 'bar',
    data: { labels: {$order_record['date']|array_values|json_encode|raw}, datasets: [
        { label: "金币", backgroundColor: primary, data: {$order_record['count']["money"]|array_values|json_encode|raw} },
        { label: "积分", backgroundColor: success, data: {$order_record['count']["integral"]|array_values|json_encode|raw} },
        { label: "其他", backgroundColor: amber, data: {$order_record['count']["other"]|array_values|json_encode|raw} }
    ] },
    options: { responsive: true, maintainAspectRatio: false, legend: { labels: { usePointStyle: true } }, scales: { yAxes: [{ ticks: { beginAtZero: true }, gridLines: { color: 'rgba(148,163,184,.18)' } }], xAxes: [{ gridLines: { display: false } }] } }
});
new Chart($("#chart-business-radar"), {
    type: 'doughnut',
    data: { labels: ["用户", "群聊", "商品", "订单", "红包", "转账"], datasets: [{
        backgroundColor: [primary, cyan, amber, success, danger, '#8B5CF6'],
        data: [{$visual.users}, {$visual.groups}, {$data["shop_total"]}, {$visual.orders}, {$visual.red_packets}, {$visual.transfers}]
    }] },
    options: { responsive: true, maintainAspectRatio: false, legend: { position: 'bottom', labels: { usePointStyle: true, boxWidth: 8 } } }
});
</script>
{/block}
'''


MODERN_CONSOLE_CSS = r'''/* Blin IM Modern Console Template 2026 */
:root {
  --blin-primary: #6366F1;
  --blin-primary-dark: #4F46E5;
  --blin-success: #10B981;
  --blin-warning: #F59E0B;
  --blin-danger: #EF4444;
  --blin-cyan: #06B6D4;
  --blin-page: #F8FAFC;
  --blin-card: #FFFFFF;
  --blin-ink: #1E293B;
  --blin-text: #64748B;
  --blin-muted: #94A3B8;
  --blin-line: #E2E8F0;
  --blin-soft: #F1F5F9;
  --blin-shadow: 0 12px 30px rgba(15, 23, 42, .08);
}
* { box-sizing: border-box; }
html, body {
  background: var(--blin-page) !important;
  color: var(--blin-ink) !important;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif !important;
  letter-spacing: 0 !important;
}
a { text-decoration: none !important; color: var(--blin-primary); }
a:hover { color: var(--blin-primary-dark); }
.blin-console-shell .lyear-layout-web,
.blin-console-shell .lyear-layout-container,
.blin-console-shell .lyear-layout-content {
  min-height: 100vh;
  background: var(--blin-page) !important;
}
.blin-console-shell .lyear-layout-sidebar {
  width: 276px !important;
  left: 0 !important;
  top: 0 !important;
  background: #FFFFFF !important;
  border-right: 1px solid var(--blin-line) !important;
  box-shadow: 8px 0 28px rgba(15, 23, 42, .04) !important;
}
.blin-console-shell .sidebar-header {
  height: 76px !important;
  padding: 0 18px !important;
  background: #FFFFFF !important;
  border-bottom: 1px solid var(--blin-line) !important;
}
.blin-console-logo {
  display: flex !important;
  align-items: center !important;
  gap: 12px !important;
  height: 76px !important;
  line-height: 1 !important;
  padding: 0 !important;
  color: var(--blin-ink) !important;
}
.blin-console-logo::before,
.blin-console-logo::after,
#logo a::before,
#logo a::after {
  display: none !important;
  content: none !important;
}
.blin-console-logo-mark {
  width: 42px;
  height: 42px;
  border-radius: 14px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  background: var(--blin-primary);
  color: #fff !important;
  font-size: 20px;
  font-weight: 800;
  box-shadow: 0 12px 24px rgba(99, 102, 241, .28);
}
.blin-console-logo-copy { display: flex; flex-direction: column; gap: 3px; min-width: 0; }
.blin-console-logo-copy strong { color: var(--blin-ink); font-size: 17px; font-weight: 800; }
.blin-console-logo-copy small { color: var(--blin-muted); font-size: 12px; font-weight: 600; }
.blin-sidebar-search {
  margin: 16px 16px 8px;
  height: 42px;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 0 12px;
  background: var(--blin-soft);
  border: 1px solid transparent;
  border-radius: 14px;
}
.blin-sidebar-search i { color: var(--blin-muted); font-size: 18px; }
.blin-sidebar-search input {
  width: 100%;
  border: 0;
  outline: 0;
  background: transparent;
  color: var(--blin-ink);
  font-size: 13px;
}
.blin-console-shell .lyear-layout-sidebar-info {
  top: 142px !important;
  bottom: 0 !important;
  padding: 0 12px 16px !important;
  background: #FFFFFF !important;
}
.blin-console-shell .sidebar-main a,
.blin-console-shell .nav-drawer > li > a,
.blin-console-shell .nav-subnav > li > a {
  min-height: 42px !important;
  margin: 3px 0 !important;
  padding: 0 12px !important;
  border-radius: 14px !important;
  display: flex !important;
  align-items: center !important;
  gap: 10px !important;
  color: var(--blin-text) !important;
  background: transparent !important;
  font-size: 14px !important;
  font-weight: 650 !important;
}
.blin-console-shell .nav-drawer > li > a i {
  width: 22px;
  text-align: center;
  color: var(--blin-muted) !important;
  font-size: 20px !important;
}
.blin-sub-dot {
  width: 7px;
  height: 7px;
  border-radius: 999px;
  background: #CBD5E1;
  margin-left: 8px;
}
.blin-console-shell .nav-subnav {
  margin: 4px 0 8px 10px !important;
  padding: 4px 0 4px 10px !important;
  border-left: 1px solid var(--blin-line);
  background: transparent !important;
}
.blin-console-shell .sidebar-main a:hover,
.blin-console-shell .nav-drawer > li.active > a,
.blin-console-shell .nav-drawer > li.open > a,
.blin-console-shell .nav-subnav > li.active > a,
.blin-console-shell .nav-subnav > li > a.active {
  background: #EEF2FF !important;
  color: var(--blin-primary) !important;
}
.blin-console-shell .sidebar-main a:hover i,
.blin-console-shell .nav-drawer > li.active > a i,
.blin-console-shell .nav-drawer > li.open > a i {
  color: var(--blin-primary) !important;
}
.blin-console-shell .sidebar-footer {
  padding: 18px 10px 4px !important;
  color: var(--blin-muted) !important;
  font-size: 12px;
  border-top: 1px solid var(--blin-line);
  margin-top: 18px;
}
.blin-console-shell .lyear-layout-header {
  left: 276px !important;
  height: 76px !important;
  background: rgba(248, 250, 252, .92) !important;
  backdrop-filter: blur(16px);
  border-bottom: 1px solid var(--blin-line) !important;
  box-shadow: none !important;
}
.blin-console-shell .navbar {
  height: 76px !important;
  padding: 0 24px !important;
  background: transparent !important;
  box-shadow: none !important;
}
.blin-console-shell .navbar-left,
.blin-console-shell .navbar-right {
  display: flex !important;
  align-items: center !important;
  gap: 14px !important;
}
.blin-icon-button,
.lyear-aside-toggler {
  width: 42px !important;
  height: 42px !important;
  border: 1px solid var(--blin-line) !important;
  border-radius: 14px !important;
  background: #fff !important;
  display: inline-flex !important;
  flex-direction: column !important;
  align-items: center !important;
  justify-content: center !important;
  gap: 4px !important;
  box-shadow: 0 8px 18px rgba(15, 23, 42, .05) !important;
}
.lyear-toggler-bar {
  width: 18px !important;
  height: 2px !important;
  background: var(--blin-ink) !important;
  border-radius: 999px !important;
}
.blin-console-title { display: flex; flex-direction: column; gap: 2px; }
.blin-console-title strong { color: var(--blin-ink); font-size: 18px; font-weight: 800; }
.blin-console-title span { color: var(--blin-muted); font-size: 12px; font-weight: 600; }
.blin-top-action {
  height: 40px;
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 0 13px;
  border: 1px solid var(--blin-line);
  border-radius: 14px;
  background: #fff;
  color: var(--blin-text) !important;
  font-weight: 700;
  box-shadow: 0 8px 18px rgba(15, 23, 42, .05);
}
.admin-profile-toggle {
  min-height: 46px !important;
  display: inline-flex !important;
  align-items: center !important;
  gap: 10px !important;
  padding: 4px 12px 4px 4px !important;
  border: 1px solid var(--blin-line);
  border-radius: 999px;
  background: #fff;
  box-shadow: 0 8px 18px rgba(15, 23, 42, .05);
  color: var(--blin-ink) !important;
}
.admin-profile-toggle img {
  width: 38px !important;
  height: 38px !important;
  object-fit: cover !important;
  border: 2px solid #fff;
}
.admin-profile-name { color: var(--blin-ink); font-weight: 750; }
.blin-console-shell .lyear-layout-content {
  left: 276px !important;
  top: 76px !important;
  background: var(--blin-page) !important;
}
#iframe-content { height: 100% !important; padding: 0 !important; }
.mt-wrapper { background: var(--blin-page) !important; }
.mt-nav-bar {
  min-height: 52px !important;
  padding: 8px 18px !important;
  background: var(--blin-page) !important;
  border-bottom: 1px solid var(--blin-line) !important;
}
.mt-nav-panel .nav-link,
.mt-nav-tools-left .nav-link,
.mt-nav-tools-right .nav-link {
  border: 0 !important;
  border-radius: 999px !important;
  color: var(--blin-text) !important;
  font-size: 13px !important;
  font-weight: 700 !important;
  background: transparent !important;
}
.mt-nav-panel .nav-link.active {
  color: var(--blin-primary) !important;
  background: #EEF2FF !important;
}
.mt-tab-content {
  background: var(--blin-page) !important;
  padding-top: 52px !important;
}
.mt-tab-content iframe {
  background: var(--blin-page) !important;
}
body.blin-console-content {
  padding: 0 !important;
  background: var(--blin-page) !important;
}
.container-fluid {
  padding: 22px !important;
}
.card {
  border: 1px solid var(--blin-line) !important;
  border-radius: 20px !important;
  background: var(--blin-card) !important;
  box-shadow: 0 8px 22px rgba(15, 23, 42, .05) !important;
  overflow: hidden;
}
.card-header {
  min-height: 62px !important;
  padding: 18px 20px !important;
  display: flex !important;
  align-items: center !important;
  justify-content: space-between !important;
  background: #fff !important;
  border-bottom: 1px solid var(--blin-line) !important;
}
.card-title {
  margin: 0 !important;
  color: var(--blin-ink) !important;
  font-size: 18px !important;
  font-weight: 800 !important;
}
.card-body { padding: 20px !important; color: var(--blin-text); }
.search-box,
.toolbar-btn-action {
  margin: 0 0 16px !important;
  padding: 14px !important;
  display: flex !important;
  flex-wrap: wrap !important;
  gap: 10px !important;
  align-items: center !important;
  background: var(--blin-soft) !important;
  border: 1px solid var(--blin-line) !important;
  border-radius: 18px !important;
}
.form-control,
.form-select,
.bootstrap-select > .dropdown-toggle,
select {
  min-height: 42px !important;
  border: 1px solid var(--blin-line) !important;
  border-radius: 14px !important;
  background-color: #fff !important;
  color: var(--blin-ink) !important;
  box-shadow: none !important;
}
.form-control:focus,
.form-select:focus {
  border-color: var(--blin-primary) !important;
  box-shadow: 0 0 0 4px rgba(99, 102, 241, .14) !important;
}
label,
.form-label {
  color: var(--blin-ink) !important;
  font-weight: 700 !important;
}
.btn {
  min-height: 40px !important;
  border-radius: 14px !important;
  border: 0 !important;
  display: inline-flex !important;
  align-items: center !important;
  justify-content: center !important;
  gap: 7px !important;
  font-weight: 750 !important;
  box-shadow: none !important;
}
.btn-primary { color: #fff !important; background: var(--blin-primary) !important; }
.btn-success { color: #fff !important; background: var(--blin-success) !important; }
.btn-warning { color: #1E293B !important; background: var(--blin-warning) !important; }
.btn-danger { color: #fff !important; background: var(--blin-danger) !important; }
.btn-info { color: #fff !important; background: var(--blin-cyan) !important; }
.btn-secondary,
.btn-default,
.btn-light {
  color: var(--blin-ink) !important;
  background: #fff !important;
  border: 1px solid var(--blin-line) !important;
}
.btn-label label {
  width: 26px !important;
  height: 26px !important;
  margin: -2px 2px -2px -4px !important;
  border-radius: 10px !important;
  display: inline-flex !important;
  align-items: center !important;
  justify-content: center !important;
  background: rgba(255,255,255,.24) !important;
  color: currentColor !important;
}
.btn i,
.btn .mdi { color: currentColor !important; }
.badge,
[class*="badge-outline"] {
  min-height: 24px;
  display: inline-flex !important;
  align-items: center !important;
  border-radius: 999px !important;
  padding: 4px 9px !important;
  font-weight: 800 !important;
}
.badge-outline-primary { color: #4F46E5 !important; background: #EEF2FF !important; border: 1px solid #C7D2FE !important; }
.badge-outline-success { color: #047857 !important; background: #ECFDF5 !important; border: 1px solid #A7F3D0 !important; }
.badge-outline-warning { color: #92400E !important; background: #FFFBEB !important; border: 1px solid #FDE68A !important; }
.badge-outline-danger { color: #B91C1C !important; background: #FEF2F2 !important; border: 1px solid #FECACA !important; }
.badge-outline-dark,
.badge-outline-info {
  color: var(--blin-text) !important;
  background: var(--blin-soft) !important;
  border: 1px solid var(--blin-line) !important;
}
.bootstrap-table .fixed-table-container {
  border: 1px solid var(--blin-line) !important;
  border-radius: 18px !important;
  background: #fff !important;
  overflow: hidden !important;
}
.table {
  color: var(--blin-ink) !important;
  margin-bottom: 0 !important;
}
.table thead th,
.bootstrap-table table thead th {
  padding: 14px 12px !important;
  background: #F8FAFC !important;
  color: var(--blin-text) !important;
  border-color: var(--blin-line) !important;
  font-size: 12px !important;
  font-weight: 850 !important;
  text-transform: none !important;
}
.table td,
.table th,
.bootstrap-table table td,
.bootstrap-table table th {
  vertical-align: middle !important;
  border-color: rgba(226, 232, 240, .85) !important;
  color: var(--blin-ink) !important;
  word-break: break-word !important;
}
.bootstrap-table table tbody tr { background: #fff !important; }
.bootstrap-table table tbody tr:hover { background: #F8FAFC !important; }
.bootstrap-table .selected,
.bootstrap-table .selected > td {
  background: #EEF2FF !important;
}
.fixed-table-toolbar {
  display: flex !important;
  flex-wrap: wrap !important;
  align-items: center !important;
  justify-content: space-between !important;
  gap: 12px !important;
}
.fixed-table-toolbar .columns,
.fixed-table-toolbar .search,
.fixed-table-toolbar .bs-bars {
  margin: 0 0 12px !important;
}
.fixed-table-toolbar .btn,
.fixed-table-pagination .btn {
  color: var(--blin-ink) !important;
  background: #fff !important;
  border: 1px solid var(--blin-line) !important;
}
.fixed-table-pagination,
.pagination-detail,
.pagination-info,
.page-list {
  color: var(--blin-text) !important;
  font-weight: 650 !important;
}
.pagination .page-link {
  color: var(--blin-text) !important;
  background: #fff !important;
  border-color: var(--blin-line) !important;
}
.pagination .active .page-link {
  color: #fff !important;
  background: var(--blin-primary) !important;
  border-color: var(--blin-primary) !important;
}
.dropdown-menu {
  padding: 8px !important;
  border: 1px solid var(--blin-line) !important;
  border-radius: 16px !important;
  box-shadow: var(--blin-shadow) !important;
}
.dropdown-item {
  border-radius: 12px !important;
  color: var(--blin-ink) !important;
  font-weight: 700 !important;
}
.dropdown-item:hover {
  color: var(--blin-primary) !important;
  background: #EEF2FF !important;
}
.modal-content,
.jconfirm-box,
.layui-layer {
  border: 1px solid var(--blin-line) !important;
  border-radius: 22px !important;
  box-shadow: var(--blin-shadow) !important;
  overflow: hidden !important;
}
.modal-header,
.modal-footer {
  border-color: var(--blin-line) !important;
  background: #fff !important;
}
.alert,
pre,
#result {
  border-radius: 16px !important;
  border: 1px solid var(--blin-line) !important;
}
pre,
#result {
  background: #0F172A !important;
  color: #DBEAFE !important;
  padding: 16px !important;
  white-space: pre-wrap;
  word-break: break-word;
}
.blin-page-hero {
  min-height: 146px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 20px;
  margin-bottom: 22px;
  padding: 24px;
  border-radius: 24px;
  border: 1px solid var(--blin-line);
  background: #fff;
  box-shadow: 0 8px 22px rgba(15, 23, 42, .05);
}
.blin-eyebrow {
  display: inline-flex;
  align-items: center;
  min-height: 24px;
  padding: 3px 9px;
  border-radius: 999px;
  background: #EEF2FF;
  color: var(--blin-primary);
  font-size: 12px;
  font-weight: 850;
}
.blin-page-hero h1 {
  margin: 10px 0 6px;
  color: var(--blin-ink);
  font-size: 28px;
  font-weight: 850;
}
.blin-page-hero p {
  margin: 0;
  color: var(--blin-text);
  font-size: 14px;
}
.blin-metric-grid {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 14px;
  margin-bottom: 22px;
}
.blin-metric-card {
  position: relative;
  min-height: 140px;
  padding: 18px;
  border-radius: 22px;
  border: 1px solid var(--blin-line);
  background: #fff;
  box-shadow: 0 8px 22px rgba(15, 23, 42, .05);
  overflow: hidden;
}
.blin-metric-card::after {
  content: "";
  position: absolute;
  right: -22px;
  bottom: -22px;
  width: 86px;
  height: 86px;
  border-radius: 999px;
  background: #EEF2FF;
}
.blin-metric-card i {
  position: relative;
  z-index: 1;
  width: 42px;
  height: 42px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 14px;
  background: #EEF2FF;
  color: var(--blin-primary);
  font-size: 22px;
}
.blin-metric-card span {
  display: block;
  margin-top: 14px;
  color: var(--blin-text);
  font-size: 13px;
  font-weight: 750;
}
.blin-metric-card strong {
  display: block;
  margin-top: 4px;
  color: var(--blin-ink);
  font-size: 26px;
  font-weight: 850;
}
.blin-metric-card small {
  display: block;
  margin-top: 4px;
  color: var(--blin-muted);
  font-size: 12px;
  font-weight: 650;
}
.blin-metric-card.success i,
.blin-metric-card.success::after { background: #ECFDF5; color: var(--blin-success); }
.blin-metric-card.warning i,
.blin-metric-card.warning::after { background: #FFFBEB; color: var(--blin-warning); }
.blin-metric-card.cyan i,
.blin-metric-card.cyan::after { background: #ECFEFF; color: var(--blin-cyan); }
.blin-chart-card .card-body {
  height: 320px;
}
.blin-chart-card canvas {
  width: 100% !important;
  height: 100% !important;
}
body.blin-console-login {
  min-height: 100vh;
  padding: 0 !important;
  background: radial-gradient(circle at 20% 20%, rgba(99, 102, 241, .12), transparent 26%), var(--blin-page) !important;
}
.blin-login-layout {
  width: min(1040px, calc(100vw - 32px));
  min-height: 620px;
  display: grid;
  grid-template-columns: 420px 1fr;
  border: 1px solid var(--blin-line);
  border-radius: 28px;
  overflow: hidden;
  background: #fff;
  box-shadow: 0 24px 70px rgba(15, 23, 42, .12);
}
.blin-login-panel {
  padding: 46px;
  display: flex;
  flex-direction: column;
  justify-content: center;
}
.blin-login-brand {
  display: flex;
  align-items: center;
  gap: 14px;
  margin-bottom: 34px;
}
.blin-login-mark {
  width: 52px;
  height: 52px;
  border-radius: 18px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  background: var(--blin-primary);
  color: #fff;
  font-size: 24px;
  font-weight: 850;
}
.blin-login-brand h1 {
  margin: 0;
  color: var(--blin-ink);
  font-size: 25px;
  font-weight: 850;
}
.blin-login-brand p {
  margin: 4px 0 0;
  color: var(--blin-text);
  font-size: 13px;
  font-weight: 650;
}
.blin-login-field {
  height: 48px;
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 14px;
  padding: 0 14px;
  border: 1px solid var(--blin-line);
  border-radius: 16px;
  background: #fff;
}
.blin-login-field i {
  color: var(--blin-muted);
  font-size: 20px;
}
.blin-login-field .form-control {
  min-height: 0 !important;
  height: auto !important;
  padding: 0 !important;
  border: 0 !important;
  border-radius: 0 !important;
  box-shadow: none !important;
}
.blin-login-captcha {
  width: 100%;
  height: 48px;
  object-fit: cover;
  border: 1px solid var(--blin-line);
  border-radius: 16px;
  cursor: pointer;
}
.blin-login-submit {
  width: 100%;
  height: 48px;
  border-radius: 16px !important;
}
.blin-check {
  display: flex;
  align-items: center;
  gap: 8px;
  color: var(--blin-text);
  font-weight: 700;
}
.blin-login-visual {
  padding: 32px;
  display: flex;
  align-items: flex-end;
  background: linear-gradient(145deg, #EEF2FF 0%, #ECFEFF 100%);
}
.blin-login-visual-card {
  width: 100%;
  padding: 26px;
  border-radius: 24px;
  background: rgba(255, 255, 255, .72);
  border: 1px solid rgba(255, 255, 255, .7);
  color: var(--blin-ink);
}
.blin-login-visual-card span {
  color: var(--blin-primary);
  font-size: 12px;
  font-weight: 850;
}
.blin-login-visual-card strong {
  display: block;
  margin-top: 8px;
  max-width: 360px;
  font-size: 28px;
  line-height: 1.28;
}
.blin-login-bars {
  display: flex;
  align-items: end;
  gap: 10px;
  height: 110px;
  margin-top: 24px;
}
.blin-login-bars i {
  flex: 1;
  border-radius: 999px 999px 12px 12px;
  background: var(--blin-primary);
}
.blin-login-bars i:nth-child(1) { height: 45%; opacity: .45; }
.blin-login-bars i:nth-child(2) { height: 74%; opacity: .75; }
.blin-login-bars i:nth-child(3) { height: 58%; opacity: .6; }
.blin-login-bars i:nth-child(4) { height: 92%; opacity: .95; }
@media (max-width: 1024px) {
  .blin-console-shell .lyear-layout-sidebar { transform: translateX(-276px); }
  .blin-console-shell .lyear-layout-sidebar.lyear-aside-open { transform: translateX(0); }
  .blin-console-shell .lyear-layout-header,
  .blin-console-shell .lyear-layout-content { left: 0 !important; }
  .blin-metric-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .blin-login-layout { grid-template-columns: 1fr; }
  .blin-login-visual { display: none; }
}
@media (max-width: 640px) {
  .container-fluid { padding: 14px !important; }
  .blin-console-title span { display: none; }
  .admin-profile-name,
  .blin-top-action span { display: none; }
  .blin-metric-grid { grid-template-columns: 1fr; }
  .blin-page-hero { align-items: flex-start; flex-direction: column; }
  .blin-login-panel { padding: 28px; }
}
'''


def main() -> None:
    if not ADMIN_VIEW.exists():
        raise SystemExit(f"admin view path not found: {ADMIN_VIEW}")
    changed = 0
    changed += int(patch_index_controller())
    changed += patch_views()
    changed += int(patch_css())
    for path in ADMIN_VIEW.rglob("*.html"):
        text = path.read_text(errors="ignore")
        new_text = re.sub(
            r"/static/css/modern-admin\.css\?v=\d+",
            f"/static/css/modern-admin.css?v={VERSION}",
            text,
        )
        if new_text != text:
            changed += int(write_if_changed(path, new_text, "modern_console_cache"))
    clear_runtime()
    print(f"modern admin console patch applied, changed={changed}")


if __name__ == "__main__":
    main()
