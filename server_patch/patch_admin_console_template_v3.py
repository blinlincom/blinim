#!/usr/bin/env python3
"""Rebuild the admin console shell and shared template as a product UI.

This patch is intentionally applied at the shared template layer:
index shell, content layout, home dashboard, login page, and the common
admin stylesheet. Business views, form field names, table initialization,
upload handling, permissions and endpoints stay intact.
"""
from datetime import datetime
from pathlib import Path
import re
import shutil


ROOT = Path("/www/wwwroot/blinlin")
VIEW = ROOT / "app/admin/view"
CSS = ROOT / "public/static/css/modern-admin.css"
INDEX_VIEW = VIEW / "index/index.html"
LAYOUT_VIEW = VIEW / "layout.html"
HOME_VIEW = VIEW / "index/home.html"
LOGIN_VIEW = VIEW / "login/index.html"
GROUP_VIEW = VIEW / "im/group_manage.html"
PRIVATE_VIEW = VIEW / "im/private_chat_manage.html"
APP_EDIT_VIEW = VIEW / "app/edit.html"
APPSTORE_CONTROLLER = ROOT / "app/admin/controller/Appstore.php"
RUNTIME_ADMIN = ROOT / "runtime/admin/temp"
RUNTIME_CACHE = ROOT / "runtime/cache"
VERSION = "202606231225"


def backup(path: Path, suffix: str) -> None:
    if not path.exists():
        return
    target = path.with_name(
        "%s.bak_%s_%s" % (path.name, suffix, datetime.now().strftime("%Y%m%d%H%M%S"))
    )
    shutil.copy2(str(path), str(target))
    print("BACKUP", target)


def write_if_changed(path: Path, text: str, suffix: str) -> bool:
    old = path.read_text(errors="ignore") if path.exists() else ""
    if old == text:
        return False
    backup(path, suffix)
    path.write_text(text, encoding="utf-8")
    print("UPDATED", path)
    return True


def patch_index() -> bool:
    return write_if_changed(INDEX_VIEW, INDEX_TEMPLATE, "admin_console_v3_shell")


def patch_layout() -> bool:
    return write_if_changed(LAYOUT_VIEW, LAYOUT_TEMPLATE, "admin_console_v3_layout")


def patch_home() -> bool:
    return write_if_changed(HOME_VIEW, HOME_TEMPLATE, "admin_console_v3_home")


def patch_login() -> bool:
    return write_if_changed(LOGIN_VIEW, LOGIN_TEMPLATE, "admin_console_v3_login")


def patch_css() -> bool:
    return write_if_changed(CSS, V3_CSS.strip() + "\n", "admin_console_v3_css")


def patch_app_edit_links() -> bool:
    if not APP_EDIT_VIEW.exists():
        return False
    text = APP_EDIT_VIEW.read_text(errors="ignore")
    if "blin-im-admin-links" not in text:
        marker = (
            '                        <div class="card-title">即时通讯配置</div>\n'
            '                    </div>\n'
            '                    <div class="card-body">\n'
        )
        links = (
            '                        <div class="card-title">即时通讯配置</div>\n'
            '                    </div>\n'
            '                    <div class="card-body">\n'
            '                        <div class="blin-im-admin-links">\n'
            '                            <a class="blin-im-admin-link-card" href="{$Request.root}/im/group_manage">\n'
            '                                <i class="mdi mdi-account-group-outline"></i>\n'
            '                                <span>群聊运营管理</span>\n'
            '                                <small>创建群聊、管理成员、群资料和群消息</small>\n'
            '                            </a>\n'
            '                            <a class="blin-im-admin-link-card" href="{$Request.root}/im/private_chat_manage">\n'
            '                                <i class="mdi mdi-message-text-outline"></i>\n'
            '                                <span>私聊运营管理</span>\n'
            '                                <small>查看私聊会话、隐藏删除消息、清空双方记录</small>\n'
            '                            </a>\n'
            '                        </div>\n'
        )
        text = text.replace(marker, links, 1)
    text = re.sub(
        r"/static/css/modern-admin\.css\?v=\d+",
        "/static/css/modern-admin.css?v=%s" % VERSION,
        text,
    )
    return write_if_changed(APP_EDIT_VIEW, text, "admin_console_v3_app_edit")


def patch_im_titles() -> int:
    changed = 0
    if GROUP_VIEW.exists():
        text = GROUP_VIEW.read_text(errors="ignore")
        text = text.replace(
            '<section class="im-visual-hero">\n'
            '    <div><div class="im-title">群聊运营管理</div><div class="im-sub">创建、编辑、解散群聊，管理成员、群资料和群消息</div></div>\n'
            '    <div class="im-hero-actions"><button class="btn btn-primary" onclick="openCreateModal()"><i class="mdi mdi-plus"></i> 创建群聊</button></div>\n'
            '  </section>',
            '<section class="im-visual-hero">\n'
            '    <div><div class="im-title">群聊运营</div><div class="im-sub">群资料、成员、消息和解散操作集中处理</div></div>\n'
            '    <div class="im-hero-actions"><button class="btn btn-primary" onclick="openCreateModal()"><i class="mdi mdi-plus"></i> 创建群聊</button></div>\n'
            '  </section>',
        )
        text = re.sub(
            r"/static/css/modern-admin\.css\?v=\d+",
            "/static/css/modern-admin.css?v=%s" % VERSION,
            text,
        )
        changed += int(write_if_changed(GROUP_VIEW, text, "admin_console_v3_group"))
    if PRIVATE_VIEW.exists():
        text = PRIVATE_VIEW.read_text(errors="ignore")
        text = text.replace(
            '<section class="im-visual-hero">\n'
            '    <div><div class="im-title">私聊运营管理</div><div class="im-sub">按会话查看聊天记录，支持隐藏、删除、标记已读和清空双方记录</div></div>\n'
            '  </section>',
            '<section class="im-visual-hero">\n'
            '    <div><div class="im-title">私聊运营</div><div class="im-sub">会话检索、消息审查、隐藏删除和双方清空</div></div>\n'
            '  </section>',
        )
        text = re.sub(
            r"/static/css/modern-admin\.css\?v=\d+",
            "/static/css/modern-admin.css?v=%s" % VERSION,
            text,
        )
        changed += int(write_if_changed(PRIVATE_VIEW, text, "admin_console_v3_private"))
    return changed


def patch_appstore_controller() -> bool:
    if not APPSTORE_CONTROLLER.exists():
        return False
    text = APPSTORE_CONTROLLER.read_text(errors="ignore")
    text = text.replace(
        '$this->success("导入成功", null, ["count" => count($savedItems)]);',
        '$this->success("导入成功", "", ["count" => count($savedItems)]);',
    )
    return write_if_changed(APPSTORE_CONTROLLER, text, "admin_console_v3_appstore_success")


def bump_css_versions() -> int:
    changed = 0
    for path in VIEW.rglob("*.html"):
        text = path.read_text(errors="ignore")
        new = re.sub(
            r"/static/css/modern-admin\.css\?v=\d+",
            "/static/css/modern-admin.css?v=%s" % VERSION,
            text,
        )
        if write_if_changed(path, new, "admin_console_v3_css_version"):
            changed += 1
    return changed


def clear_runtime() -> None:
    for root in [RUNTIME_ADMIN, RUNTIME_CACHE]:
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if path.is_file():
                try:
                    path.unlink()
                except Exception:
                    pass


INDEX_TEMPLATE = r'''<!DOCTYPE html>
<html lang="zh">

<head>
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
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
    <link rel="stylesheet" type="text/css" href="/static/css/modern-admin.css?v=202606231225">
</head>

<body class="lyear-index blin-console-shell blin-admin-v3">
    <div class="lyear-layout-web">
        <div class="lyear-layout-container">
            <aside class="lyear-layout-sidebar">
                <div id="logo" class="sidebar-header">
                    <a href="{$Request.root}" class="blin-console-logo">
                        <span class="blin-console-logo-mark">B</span>
                        <span class="blin-console-logo-copy">
                            <strong>Blin</strong>
                            <small>运营后台</small>
                        </span>
                    </a>
                </div>
                <div class="blin-sidebar-search">
                    <i class="mdi mdi-magnify"></i>
                    <input id="blinMenuSearch" type="text" placeholder="搜索菜单">
                </div>
                <div class="lyear-layout-sidebar-info lyear-scroll">
                    <nav class="sidebar-main" aria-label="后台菜单"></nav>
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
                    </div>
                    <ul class="navbar-right d-flex align-items-center">
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
        (function () {
            var shellVersion = '202606231225';
            if (sessionStorage.getItem('blin_admin_shell_version') !== shellVersion) {
                sessionStorage.clear();
                sessionStorage.setItem('blin_admin_shell_version', shellVersion);
            }
        })();
        var menu_list = {$permission|raw};
        setSidebar(menu_list);

        function setSidebar(data) {
            if (!data || data.length == 0) return false;
            data = normalizeMenu(data);
            var treeObj = getTrees(data, 0, 'id', 'pid', 'children');
            $('.sidebar-main').empty().append(createMenu(treeObj, true));
        }

        function normalizeMenu(data) {
            var iconMap = {
                '首页':'mdi mdi-view-dashboard-outline',
                '权限管理':'mdi mdi-shield-account-outline',
                '系统管理':'mdi mdi-tune-variant',
                'APP管理':'mdi mdi-cellphone-cog',
                '用户管理':'mdi mdi-account-multiple-outline',
                '卡密管理':'mdi mdi-card-bulleted-outline',
                '商城管理':'mdi mdi-storefront-outline',
                '提现管理':'mdi mdi-wallet-outline',
                '笔记管理':'mdi mdi-note-text-outline',
                '论坛管理':'mdi mdi-forum-outline',
                '表情商店':'mdi mdi-emoticon-outline',
                '应用商店':'mdi mdi-emoticon-outline',
                '即时通讯':'mdi mdi-message-text-outline',
                '即时通讯管理':'mdi mdi-message-text-outline',
                '群聊运营管理':'mdi mdi-account-group-outline',
                '私聊运营管理':'mdi mdi-forum-outline'
            };
            return $.map(data, function(item){
                item.icon = item.icon || iconMap[item.name] || 'mdi mdi-circle-medium';
                if (item.name === '应用商店') item.name = '表情商店';
                if (item.name === '即时通讯配置') item.name = '即时通讯管理';
                if (item.name === '群运营管理') item.name = '群聊运营管理';
                if (item.name === '私聊记录管理') item.name = '私聊运营管理';
                if (item.name === '即时通讯管理') item.sort = 2.5;
                if (item.name === '群聊运营管理') item.sort = 2.6;
                if (item.name === '私聊运营管理') item.sort = 2.7;
                return item;
            }).sort(function(a,b){ return (parseFloat(a.sort)||0) - (parseFloat(b.sort)||0); });
        }

        function createMenu(data, is_frist) {
            var menu_body = is_frist ? '<ul class="nav-drawer">' : '<ul class="nav nav-subnav">';
            for (var i = 0; i < data.length; i++) {
                var iframe_class = data[i].is_out == 1 ? 'target="_blank"' : 'class="multitabs"';
                var icon_div = '';
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
            if (!keyword) {
                $('.sidebar-main .nav-subnav').removeAttr('style');
                return;
            }
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
        $(function () {
            $(document).off('click', '.nav-item-has-subnav > a');
            $(document).on('click', '.nav-item-has-subnav > a', function (event) {
                event.preventDefault();
                var $item = $(this).parent('.nav-item-has-subnav');
                var $subnav = $item.children('.nav-subnav').first();
                var willOpen = !$item.hasClass('open');
                $item.siblings('.nav-item-has-subnav.open')
                    .removeClass('open active')
                    .children('.nav-subnav')
                    .stop(true, true)
                    .slideUp(140);
                $item.toggleClass('open', willOpen);
                $subnav.stop(true, true)[willOpen ? 'slideDown' : 'slideUp'](140);
            });
        });
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
    <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
    <title></title>
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-touch-fullscreen" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="default">
    <link rel="stylesheet" type="text/css" href="/static/css/materialdesignicons.min.css">
    <link rel="stylesheet" type="text/css" href="/static/css/bootstrap.min.css">
    <link rel="stylesheet" type="text/css" href="/static/js/bootstrap-select/bootstrap-select.min.css">
    <link rel="stylesheet" href="/static/js/bootstrap-table/bootstrap-table.min.css">
    <link rel="stylesheet" type="text/css" href="/static/css/style.min.css">
    <link rel="stylesheet" type="text/css" href="/static/css/modern-admin.css?v=202606231225">
</head>

<body class="blin-console-content blin-admin-v3-content">
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


HOME_TEMPLATE = r'''{extend name="layout" /}
{block name="body"}
<div class="container-fluid blin-dashboard">
    <div class="blin-overview-bar">
        <div class="blin-overview-copy">
            <strong>运营总览</strong>
            <span>应用、用户、消息、财务和内容数据</span>
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

    <div class="row g-3">
        <div class="col-xl-8">
            <div class="card blin-chart-card">
                <header class="card-header">
                    <div class="card-title">用户增长与活跃</div>
                </header>
                <div class="card-body"><canvas id="chart-user-trend"></canvas></div>
            </div>
        </div>
        <div class="col-xl-4">
            <div class="card blin-chart-card">
                <header class="card-header">
                    <div class="card-title">业务占比</div>
                </header>
                <div class="card-body"><canvas id="chart-business-radar"></canvas></div>
            </div>
        </div>
        <div class="col-xl-6">
            <div class="card blin-chart-card">
                <header class="card-header">
                    <div class="card-title">消息量</div>
                </header>
                <div class="card-body"><canvas id="chart-message-trend"></canvas></div>
            </div>
        </div>
        <div class="col-xl-6">
            <div class="card blin-chart-card">
                <header class="card-header">
                    <div class="card-title">订单类型</div>
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
var primary = '#2563EB', success = '#10B981', amber = '#F59E0B', cyan = '#06B6D4', danger = '#EF4444';
new Chart($("#chart-user-trend"), {
    type: 'line',
    data: { labels: labels, datasets: [
        { label: "注册", borderColor: primary, backgroundColor: 'rgba(37,99,235,.10)', pointRadius: 3, borderWidth: 3, data: {$user_register['count']|array_values|json_encode|raw} },
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


LOGIN_TEMPLATE = r'''<!DOCTYPE html>
<html lang="zh">

<head>
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
    <title>后台登录</title>
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-touch-fullscreen" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="default">
    <link rel="stylesheet" type="text/css" href="/static/css/materialdesignicons.min.css">
    <link rel="stylesheet" type="text/css" href="/static/css/bootstrap.min.css">
    <link rel="stylesheet" type="text/css" href="/static/css/animate.min.css">
    <link rel="stylesheet" type="text/css" href="/static/css/style.min.css">
    <link rel="stylesheet" type="text/css" href="/static/css/modern-admin.css?v=202606231225">
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


V3_CSS = r'''
/* ===== Blin Admin Console V3 base rebuild ===== */
:root{
  --blin-primary:#2563EB;
  --blin-primary-strong:#1D4ED8;
  --blin-primary-soft:#EFF6FF;
  --blin-accent:#06B6D4;
  --blin-success:#10B981;
  --blin-warning:#F59E0B;
  --blin-danger:#EF4444;
  --blin-page:#F6F8FC;
  --blin-surface:#FFFFFF;
  --blin-surface-2:#F8FAFC;
  --blin-ink:#172033;
  --blin-text:#475569;
  --blin-muted:#64748B;
  --blin-faint:#94A3B8;
  --blin-line:#E2E8F0;
  --blin-line-strong:#CBD5E1;
  --blin-shadow:0 8px 20px rgba(15,23,42,.06);
  --blin-radius:14px;
}
html,body{min-height:100%;background:var(--blin-page)!important;color:var(--blin-ink)!important;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Microsoft YaHei",Arial,sans-serif!important;letter-spacing:0!important}
body.blin-admin-v3,body.blin-admin-v3-content{background:var(--blin-page)!important;background-image:none!important}
a{color:var(--blin-primary);text-decoration:none}a:hover{color:var(--blin-primary-strong);text-decoration:none}
*{outline-color:rgba(37,99,235,.42)}

/* Shell */
body.blin-admin-v3 .lyear-layout-sidebar{width:256px!important;background:linear-gradient(180deg,#101827 0%,#0b1120 100%)!important;border-right:1px solid rgba(255,255,255,.08)!important;box-shadow:18px 0 38px rgba(15,23,42,.18)!important;z-index:1035!important}
body.blin-admin-v3 .sidebar-header{height:62px!important;background:linear-gradient(135deg,rgba(37,99,235,.24),rgba(14,165,233,.06))!important;border-bottom:1px solid rgba(255,255,255,.08)!important}
body.blin-admin-v3 #logo a{height:62px!important;padding:0 16px!important;color:#fff!important;display:flex!important;align-items:center!important}
body.blin-admin-v3 #logo a:before,body.blin-admin-v3 #logo a:after,.sidebar-footer{display:none!important;content:none!important}
.blin-console-logo{display:grid!important;grid-template-columns:36px minmax(0,1fr)!important;align-items:center!important;gap:10px!important;width:100%!important;min-width:0!important}
.blin-console-logo-mark{width:36px;height:36px;border-radius:12px;background:linear-gradient(135deg,#38bdf8,#2563eb 58%,#7c3aed);color:#fff;display:inline-flex;align-items:center;justify-content:center;font-size:18px;font-weight:850;line-height:1;flex:none;box-shadow:0 10px 25px rgba(37,99,235,.35)}
.blin-console-logo-copy{display:flex;flex-direction:column;gap:1px;min-width:0;overflow:hidden}.blin-console-logo-copy strong{font-size:15px;font-weight:850;color:#fff;line-height:1.2;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.blin-console-logo-copy small{font-size:12px;font-weight:650;color:rgba(203,213,225,.86);line-height:1.2;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.blin-sidebar-search{margin:10px 12px 6px;padding:0 12px;height:38px;display:flex;align-items:center;gap:8px;border-radius:12px;background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.09)}
.blin-sidebar-search i{color:rgba(191,219,254,.9);font-size:18px}.blin-sidebar-search input{width:100%;border:0;background:transparent!important;outline:0;color:#fff;font-size:13px;font-weight:600}.blin-sidebar-search input::placeholder{color:rgba(203,213,225,.78);opacity:1}
body.blin-admin-v3 .lyear-layout-sidebar-info{position:absolute!important;top:116px!important;right:0!important;bottom:0!important;left:0!important;height:auto!important;padding:0 10px 14px!important;background:transparent!important}
body.blin-admin-v3 .sidebar-main{padding-bottom:20px}
body.blin-admin-v3 .nav-drawer,body.blin-admin-v3 .nav-subnav{padding:0!important;margin:0!important;list-style:none!important}
body.blin-admin-v3 .nav-drawer>li{margin:3px 0!important}
body.blin-admin-v3 .sidebar-main a,body.blin-admin-v3 .nav-drawer>li>a,body.blin-admin-v3 .nav-subnav>li>a{min-height:40px!important;padding:0 14px!important;border-radius:12px!important;display:flex!important;align-items:center!important;gap:0!important;color:rgba(226,232,240,.9)!important;background:transparent!important;font-size:14px!important;font-weight:750!important;text-shadow:none!important;line-height:1.2!important}
body.blin-admin-v3 .sidebar-main a *,body.blin-admin-v3 .blin-sidebar-menu-text{color:inherit!important;text-shadow:none!important}
body.blin-admin-v3 .nav-drawer>li>a i,body.blin-admin-v3 .nav-drawer>li>a .mdi,body.blin-admin-v3 .sidebar-main .blin-sub-dot{display:none!important;width:0!important;min-width:0!important;margin:0!important;padding:0!important}
.blin-sub-dot{display:none!important}
body.blin-admin-v3 .nav-subnav{display:none;margin:2px 0 8px 18px!important;padding:3px 0 3px 8px!important;border-left:1px solid rgba(255,255,255,.10)!important}
body.blin-admin-v3 .nav-item-has-subnav.open>.nav-subnav{display:block}
body.blin-admin-v3 .nav-subnav>li>a{min-height:36px!important;font-size:13px!important;font-weight:700!important;color:rgba(203,213,225,.84)!important}
body.blin-admin-v3 .sidebar-main a:hover,body.blin-admin-v3 .nav-drawer>li.active>a,body.blin-admin-v3 .nav-drawer>li.open>a,body.blin-admin-v3 .nav-subnav>li.active>a{background:rgba(37,99,235,.30)!important;color:#fff!important}
body.blin-admin-v3 .nav-drawer>li.active>a i,body.blin-admin-v3 .nav-drawer>li.open>a i,body.blin-admin-v3 .sidebar-main a:hover i{display:none!important}
body.blin-admin-v3 .nav-subnav>li.active>a .blin-sub-dot,body.blin-admin-v3 .nav-subnav>li>a:hover .blin-sub-dot{display:none!important}

body.blin-admin-v3 .lyear-layout-header{left:256px!important;height:56px!important;background:rgba(255,255,255,.96)!important;border-bottom:1px solid var(--blin-line)!important;box-shadow:none!important;z-index:1020!important}
body.blin-admin-v3 .navbar{height:56px!important;padding:0 16px!important;background:transparent!important;box-shadow:none!important;display:flex!important;align-items:center!important;justify-content:space-between!important}
body.blin-admin-v3 .navbar-left{display:flex!important;align-items:center!important;gap:10px!important}
body.blin-admin-v3 .navbar-right{gap:8px!important;margin:0!important}
.blin-icon-button,.lyear-aside-toggler{width:40px!important;height:40px!important;padding:0!important;border-radius:12px!important;border:1px solid var(--blin-line)!important;background:var(--blin-surface)!important;display:inline-flex!important;flex-direction:column!important;justify-content:center!important;align-items:center!important;gap:4px!important;box-shadow:none!important}
.lyear-toggler-bar{width:17px!important;height:2px!important;background:var(--blin-ink)!important;border-radius:999px!important}
.blin-top-action{min-height:38px;display:inline-flex!important;align-items:center!important;justify-content:center;gap:7px;padding:0 11px;border-radius:12px;border:1px solid var(--blin-line);background:var(--blin-surface);color:var(--blin-text)!important;font-size:13px;font-weight:750;white-space:nowrap;box-shadow:none}
.blin-top-action:hover{border-color:var(--blin-primary);background:var(--blin-primary-soft);color:var(--blin-primary-strong)!important}
.admin-profile-toggle{height:40px;padding:0 8px;border-radius:12px;display:inline-flex!important;align-items:center;gap:8px;color:var(--blin-text)!important;background:transparent;border:1px solid transparent}
.admin-profile-toggle:hover{background:var(--blin-surface-2);border-color:var(--blin-line)}.admin-profile-toggle img{width:30px!important;height:30px!important;object-fit:cover;background:var(--blin-primary-soft)}.admin-profile-name{max-width:110px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:13px;font-weight:750;color:var(--blin-text)}
body.blin-admin-v3 .lyear-layout-content{left:256px!important;top:56px!important;padding-top:0!important;padding-left:0!important;background:var(--blin-page)!important}
body.blin-admin-v3 #iframe-content{height:100%!important;background:var(--blin-page)!important}
body.blin-admin-v3 .mt-wrapper{height:100%!important;background:var(--blin-page)!important}
body.blin-admin-v3 .mt-nav-bar{height:38px!important;min-height:38px!important;padding:4px 12px!important;top:0!important;left:0!important;right:0!important;background:var(--blin-page)!important;border-bottom:1px solid var(--blin-line)!important}
body.blin-admin-v3 .mt-nav-bar .mt-nav .nav-tabs{border:0!important;margin:0!important}
body.blin-admin-v3 .mt-nav-panel .nav-link{min-height:29px!important;border:0!important;border-radius:999px!important;background:transparent!important;color:var(--blin-muted)!important;font-size:13px!important;font-weight:750!important;padding:5px 11px!important}
body.blin-admin-v3 .mt-nav-panel .nav-link.active{background:var(--blin-surface)!important;color:var(--blin-ink)!important;box-shadow:0 0 0 1px var(--blin-line)!important}
body.blin-admin-v3 .mt-tab-content{height:100%!important;padding-top:38px!important;background:var(--blin-page)!important;overflow:hidden!important}

/* Content */
body.blin-admin-v3-content:not(.center-vh){background:var(--blin-page)!important;padding:0!important}
body.blin-admin-v3-content .container-fluid{width:100%!important;max-width:1560px!important;padding:18px!important}
body.blin-admin-v3-content .container-fluid.p-t-15{padding-top:18px!important}
body.blin-admin-v3-content .row{row-gap:16px}
body.blin-admin-v3-content .card{border:1px solid var(--blin-line)!important;border-radius:var(--blin-radius)!important;background:var(--blin-surface)!important;box-shadow:none!important;overflow:hidden!important;margin-bottom:0!important}
body.blin-admin-v3-content .card-header{min-height:52px!important;padding:14px 16px!important;background:var(--blin-surface)!important;border-bottom:1px solid var(--blin-line)!important;display:flex;align-items:center;justify-content:space-between;gap:12px}
body.blin-admin-v3-content .card-title{font-size:16px!important;font-weight:850!important;color:var(--blin-ink)!important;line-height:1.35!important;margin:0!important}
body.blin-admin-v3-content .card-body{padding:16px!important}
body.blin-admin-v3-content .card-body>form>.row,body.blin-admin-v3-content form .row.g-3{row-gap:14px}
body.blin-admin-v3-content .form-label,body.blin-admin-v3-content label{font-size:13px;font-weight:750;color:var(--blin-text);margin-bottom:6px}
body.blin-admin-v3-content small,body.blin-admin-v3-content .text-muted{color:var(--blin-muted)!important;font-size:12px!important;font-weight:600!important;line-height:1.45}
body.blin-admin-v3-content code{padding:2px 5px;border-radius:6px;background:var(--blin-primary-soft);color:var(--blin-primary-strong);font-size:12px}
body.blin-admin-v3-content .form-control,body.blin-admin-v3-content .form-select,body.blin-admin-v3-content select,body.blin-admin-v3-content textarea{min-height:40px!important;border-radius:11px!important;border:1px solid var(--blin-line)!important;background:var(--blin-surface)!important;color:var(--blin-ink)!important;font-size:14px!important;box-shadow:none!important}
body.blin-admin-v3-content textarea.form-control{min-height:96px!important}
body.blin-admin-v3-content .form-control:focus,body.blin-admin-v3-content .form-select:focus,body.blin-admin-v3-content select:focus,body.blin-admin-v3-content textarea:focus{border-color:var(--blin-primary)!important;box-shadow:0 0 0 3px rgba(37,99,235,.12)!important}
body.blin-admin-v3-content .input-group .form-control{border-radius:11px 0 0 11px!important}.input-group-append .btn,.input-group .btn:last-child{border-radius:0 11px 11px 0!important}

body.blin-admin-v3-content .btn,.btn{min-height:38px!important;border-radius:11px!important;display:inline-flex!important;align-items:center!important;justify-content:center!important;gap:6px!important;font-weight:750!important;font-size:13px!important;border:0!important;white-space:nowrap!important;box-shadow:none!important;padding:7px 12px!important;line-height:1.2!important}
body.blin-admin-v3-content .btn i,.btn i{font-size:17px;line-height:1}
body.blin-admin-v3-content .btn-primary,.btn-primary{background:var(--blin-primary)!important;color:#fff!important}
body.blin-admin-v3-content .btn-primary:hover,.btn-primary:hover{background:var(--blin-primary-strong)!important;color:#fff!important}
body.blin-admin-v3-content .btn-success,.btn-success{background:var(--blin-success)!important;color:#fff!important}
body.blin-admin-v3-content .btn-warning,.btn-warning{background:var(--blin-warning)!important;color:#1E293B!important}
body.blin-admin-v3-content .btn-danger,.btn-danger{background:var(--blin-danger)!important;color:#fff!important}
body.blin-admin-v3-content .btn-info,.btn-info{background:var(--blin-accent)!important;color:#fff!important}
body.blin-admin-v3-content .btn-default,body.blin-admin-v3-content .btn-secondary,.btn-default,.btn-secondary{background:var(--blin-surface)!important;color:var(--blin-ink)!important;border:1px solid var(--blin-line)!important}
body.blin-admin-v3-content .btn-label label{margin:0 3px 0 0!important;display:inline-flex!important;align-items:center!important;color:inherit!important}

body.blin-admin-v3-content .toolbar-btn-action,body.blin-admin-v3-content .search-box,body.blin-admin-v3-content .im-toolbar{display:flex!important;flex-wrap:wrap!important;align-items:center!important;gap:10px!important;padding:12px!important;margin:0 0 14px!important;border:1px solid var(--blin-line)!important;border-radius:var(--blin-radius)!important;background:var(--blin-surface-2)!important}
body.blin-admin-v3-content .search-box>[class*="col-"],body.blin-admin-v3-content .toolbar-btn-action>[class*="col-"],body.blin-admin-v3-content .im-toolbar>[class*="col-"]{width:auto!important;max-width:none!important;flex:0 1 260px!important;padding:0!important;margin:0!important}
body.blin-admin-v3-content .search-box .form-control,body.blin-admin-v3-content .search-box .form-select,body.blin-admin-v3-content .im-toolbar .form-control,body.blin-admin-v3-content .im-toolbar .form-select{min-width:190px}

body.blin-admin-v3-content .fixed-table-toolbar{display:flex!important;flex-wrap:wrap!important;align-items:center!important;justify-content:space-between!important;gap:10px!important;margin:0 0 10px!important}
body.blin-admin-v3-content .fixed-table-toolbar .bs-bars,body.blin-admin-v3-content .fixed-table-toolbar .columns,body.blin-admin-v3-content .fixed-table-toolbar .search{margin:0!important}
body.blin-admin-v3-content .fixed-table-toolbar .search input{min-height:38px!important;border-radius:11px!important}
body.blin-admin-v3-content .bootstrap-table .fixed-table-container{border:1px solid var(--blin-line)!important;border-radius:var(--blin-radius)!important;background:var(--blin-surface)!important;overflow:hidden!important}
body.blin-admin-v3-content .fixed-table-body{overflow:auto!important}
body.blin-admin-v3-content .bootstrap-table table{min-width:920px;margin:0!important}
body.blin-admin-v3-content .table{color:var(--blin-ink)!important;margin-bottom:0!important}
body.blin-admin-v3-content .table th,body.blin-admin-v3-content .bootstrap-table table thead th{height:42px;background:#F8FAFC!important;color:var(--blin-text)!important;font-size:12px!important;font-weight:850!important;border-color:var(--blin-line)!important;vertical-align:middle!important}
body.blin-admin-v3-content .table td,body.blin-admin-v3-content .table th,body.blin-admin-v3-content .bootstrap-table td,body.blin-admin-v3-content .bootstrap-table th{vertical-align:middle!important;color:var(--blin-ink)!important;border-color:var(--blin-line)!important}
body.blin-admin-v3-content .bootstrap-table tbody tr:hover{background:#F8FAFC!important}
body.blin-admin-v3-content .pagination .page-link{border-color:var(--blin-line)!important;color:var(--blin-text)!important;border-radius:9px!important;margin:0 2px!important}
body.blin-admin-v3-content .pagination .page-item.active .page-link{background:var(--blin-primary)!important;border-color:var(--blin-primary)!important;color:#fff!important}
body.blin-admin-v3-content table td .btn,body.blin-admin-v3-content .bootstrap-table td .btn{width:auto!important;min-height:32px!important;padding:6px 9px!important;margin:2px!important;border-radius:9px!important}
body.blin-admin-v3-content .bootstrap-table img,body.blin-admin-v3-content table img{width:42px!important;height:42px!important;max-width:42px!important;object-fit:cover!important;border-radius:11px!important;background:var(--blin-primary-soft)!important;display:inline-block!important}
body.blin-admin-v3-content img.template-shot,body.blin-admin-v3-content .screenshot-item img{width:100%!important;max-width:100%!important;height:auto!important;object-fit:cover!important}
body.blin-admin-v3-content .app-icon-img,body.blin-admin-v3-content .im-avatar{width:38px!important;height:38px!important;max-width:38px!important;border-radius:11px!important;object-fit:cover!important;background:var(--blin-primary-soft)!important;flex:none}

.badge,.label{border-radius:999px!important;padding:4px 8px!important;font-size:12px!important;font-weight:750!important;line-height:1!important}
.badge-outline-primary{color:var(--blin-primary-strong)!important;background:var(--blin-primary-soft)!important;border:1px solid #BFDBFE!important}
.badge-outline-success{color:#047857!important;background:#ECFDF5!important;border:1px solid #A7F3D0!important}
.badge-outline-warning{color:#92400E!important;background:#FFFBEB!important;border:1px solid #FDE68A!important}
.badge-outline-danger{color:#B91C1C!important;background:#FEF2F2!important;border:1px solid #FECACA!important}
.badge-outline-dark{color:var(--blin-ink)!important;background:#F1F5F9!important;border:1px solid var(--blin-line)!important}

body.blin-admin-v3-content .modal-content,.jconfirm .jconfirm-box{border-radius:16px!important;border:1px solid var(--blin-line)!important;box-shadow:var(--blin-shadow)!important;overflow:hidden!important}
body.blin-admin-v3-content .modal-header,.jconfirm .jconfirm-box div.jconfirm-title-c{border-bottom:1px solid var(--blin-line)!important;background:var(--blin-surface)!important;padding:14px 16px!important}
body.blin-admin-v3-content .modal-title{font-size:16px!important;font-weight:850!important;color:var(--blin-ink)!important}
body.blin-admin-v3-content .modal-body{padding:16px!important}
body.blin-admin-v3-content .modal-footer{border-top:1px solid var(--blin-line)!important;padding:12px 16px!important;background:var(--blin-surface-2)!important}
.dropdown-menu{border-radius:13px!important;border:1px solid var(--blin-line)!important;box-shadow:var(--blin-shadow)!important;padding:7px!important;background:var(--blin-surface)!important}
.dropdown-item{border-radius:9px!important;color:var(--blin-ink)!important;font-weight:700!important;min-height:34px;display:flex!important;align-items:center;gap:8px}.dropdown-item:hover{background:var(--blin-primary-soft)!important;color:var(--blin-primary-strong)!important}

/* Login */
body.center-vh.blin-console-login{min-height:100vh!important;display:flex!important;align-items:center!important;justify-content:center!important;padding:24px!important;background:#0f172a!important;background-image:none!important;overflow:auto!important}
body.center-vh.blin-console-login:before{content:""!important;position:fixed!important;inset:0!important;background:linear-gradient(90deg,rgba(255,255,255,.04) 1px,transparent 1px),linear-gradient(rgba(255,255,255,.04) 1px,transparent 1px)!important;background-size:40px 40px!important;pointer-events:none!important}
.blin-login-layout{width:min(860px,calc(100vw - 32px));display:grid;grid-template-columns:minmax(0,420px) minmax(0,1fr);gap:16px;position:relative;z-index:1}
.blin-login-panel{padding:28px;border:1px solid rgba(255,255,255,.14);border-radius:18px;background:var(--blin-surface);box-shadow:0 24px 60px rgba(0,0,0,.28)}
.blin-login-brand{display:flex;align-items:center;gap:12px;margin-bottom:24px}
.blin-login-mark{width:44px;height:44px;border-radius:14px;background:linear-gradient(135deg,#38bdf8,#2563eb 58%,#7c3aed);color:#fff;display:inline-flex;align-items:center;justify-content:center;font-size:20px;font-weight:850;box-shadow:0 16px 34px rgba(37,99,235,.34)}
.blin-login-brand h1{margin:0;color:var(--blin-ink);font-size:22px;font-weight:850;line-height:1.2}
.blin-login-brand p{margin:2px 0 0;color:var(--blin-muted);font-size:13px;font-weight:650}
.blin-login-field{min-height:46px;padding:0 12px;border:1px solid var(--blin-line);border-radius:13px;background:var(--blin-surface-2);display:flex!important;align-items:center;gap:8px;margin-bottom:12px}
.blin-login-field i{color:var(--blin-muted);font-size:19px}.blin-login-field .form-control{height:44px;border:0!important;background:transparent!important;padding:0!important;color:var(--blin-ink)!important;box-shadow:none!important}
.blin-login-captcha-row{display:grid;grid-template-columns:1fr 120px;gap:10px;margin-bottom:14px}.blin-login-captcha{width:120px;height:46px;border-radius:13px;border:1px solid var(--blin-line);object-fit:cover;cursor:pointer;background:#fff}
.blin-check{display:flex;align-items:center;gap:7px;margin:6px 0 18px}.blin-check .form-check-input{margin:0}.blin-login-submit{width:100%;height:46px!important;border-radius:13px!important;font-size:14px!important}
.blin-login-visual{display:flex;min-height:100%;border:1px solid rgba(255,255,255,.12);border-radius:18px;background:linear-gradient(135deg,rgba(37,99,235,.24),rgba(14,165,233,.08));padding:22px;align-items:flex-end;overflow:hidden}
.blin-login-visual-card{width:100%;padding:18px;border-radius:16px;background:rgba(15,23,42,.66);border:1px solid rgba(255,255,255,.12)}
.blin-login-visual-card span{display:block;color:#93c5fd;font-size:12px;font-weight:800;margin-bottom:8px}.blin-login-visual-card strong{display:block;color:#fff;font-size:18px;font-weight:850;line-height:1.4}.blin-login-bars{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin-top:18px}.blin-login-bars i{height:46px;border-radius:10px;background:rgba(96,165,250,.28)}.blin-login-bars i:nth-child(2){height:62px}.blin-login-bars i:nth-child(3){height:36px}.blin-login-bars i:nth-child(4){height:54px}

/* Dashboard */
.blin-dashboard{display:flex;flex-direction:column;gap:16px}
.blin-overview-bar{display:flex;align-items:center;justify-content:space-between;gap:14px;padding:14px 16px;border:1px solid var(--blin-line);border-radius:var(--blin-radius);background:var(--blin-surface)}
.blin-overview-copy{display:flex;align-items:baseline;gap:10px;min-width:0}.blin-overview-copy strong{font-size:18px;font-weight:850;color:var(--blin-ink)}.blin-overview-copy span{font-size:13px;font-weight:650;color:var(--blin-muted)}
.blin-metric-grid{display:grid;grid-template-columns:repeat(6,minmax(0,1fr));gap:12px}
.blin-metric-card{min-height:104px;padding:14px;border-radius:var(--blin-radius);border:1px solid var(--blin-line);background:var(--blin-surface);display:grid;grid-template-columns:38px 1fr;grid-template-areas:"icon label" "icon value" "icon note";column-gap:11px;align-items:center}
.blin-metric-card i{grid-area:icon;width:38px;height:38px;border-radius:12px;background:var(--blin-primary-soft);color:var(--blin-primary);display:inline-flex;align-items:center;justify-content:center;font-size:20px}.blin-metric-card span{grid-area:label;color:var(--blin-muted);font-size:12px;font-weight:750}.blin-metric-card strong{grid-area:value;color:var(--blin-ink);font-size:22px;font-weight:850;line-height:1.1}.blin-metric-card small{grid-area:note;color:var(--blin-faint);font-size:12px;font-weight:650}
.blin-metric-card.success i{background:#ECFDF5;color:var(--blin-success)}.blin-metric-card.warning i{background:#FFFBEB;color:var(--blin-warning)}.blin-metric-card.cyan i{background:#ECFEFF;color:var(--blin-accent)}
.blin-chart-card .card-body{height:310px}.blin-chart-card canvas{width:100%!important;height:100%!important}

/* Settings and IM operation helpers */
.blin-setting-row{display:flex!important;align-items:center!important;justify-content:space-between!important;gap:16px!important;padding:13px 14px!important;border:1px solid var(--blin-line)!important;border-radius:var(--blin-radius)!important;background:var(--blin-surface-2)!important;margin-bottom:12px!important}
.blin-setting-copy{display:flex!important;flex-direction:column!important;gap:3px!important;min-width:0}.blin-setting-title{color:var(--blin-ink)!important;font-size:14px!important;font-weight:850!important}.blin-setting-desc{color:var(--blin-muted)!important;font-size:12px!important;font-weight:600!important}
.blin-segmented-switch{display:inline-flex!important;gap:4px!important;padding:4px!important;border-radius:13px!important;background:#EEF2F7!important;border:1px solid var(--blin-line)!important;flex:none}.blin-segmented-switch .btn-check{position:absolute!important;opacity:0!important;pointer-events:none!important}
.blin-switch-choice{min-width:74px!important;min-height:32px!important;margin:0!important;padding:0 11px!important;border-radius:10px!important;display:inline-flex!important;align-items:center!important;justify-content:center!important;gap:5px!important;color:var(--blin-text)!important;font-size:13px!important;font-weight:800!important;cursor:pointer!important}
.blin-segmented-switch .btn-check:checked + .blin-switch-choice-on,.blin-segmented-switch input:checked + .blin-switch-choice-on{background:var(--blin-success)!important;color:#fff!important}
.blin-segmented-switch .btn-check:checked + .blin-switch-choice-off,.blin-segmented-switch input:checked + .blin-switch-choice-off{background:var(--blin-danger)!important;color:#fff!important}
.blin-im-admin-links{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px;margin-bottom:16px}.blin-im-admin-link-card{min-height:84px;padding:14px;border:1px solid var(--blin-line);border-radius:var(--blin-radius);background:var(--blin-surface-2);color:var(--blin-ink)!important;display:grid;grid-template-columns:40px 1fr;grid-template-areas:"icon title" "icon desc";column-gap:11px;align-items:center;text-decoration:none!important}.blin-im-admin-link-card:hover{border-color:var(--blin-primary);background:var(--blin-primary-soft)}.blin-im-admin-link-card i{grid-area:icon;width:40px;height:40px;border-radius:12px;background:var(--blin-primary);color:#fff!important;display:inline-flex;align-items:center;justify-content:center;font-size:21px}.blin-im-admin-link-card span{grid-area:title;color:var(--blin-ink);font-size:15px;font-weight:850}.blin-im-admin-link-card small{grid-area:desc;color:var(--blin-muted);font-size:12px;font-weight:650;line-height:1.45}
.im-visual-page{display:flex;flex-direction:column;gap:14px}.im-visual-hero{display:flex;align-items:center;justify-content:space-between;gap:14px;padding:14px 16px;border:1px solid var(--blin-line);border-radius:var(--blin-radius);background:var(--blin-surface)}.im-title{font-size:18px;font-weight:850;color:var(--blin-ink);line-height:1.25}.im-sub{font-size:12px;font-weight:650;color:var(--blin-muted);margin-top:3px}.im-stat-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px}.im-stat-grid>div{padding:13px;border:1px solid var(--blin-line);border-radius:var(--blin-radius);background:var(--blin-surface)}.im-stat-grid span{display:block;font-size:12px;font-weight:750;color:var(--blin-muted)}.im-stat-grid strong{display:block;margin-top:5px;font-size:17px;font-weight:850;color:var(--blin-ink)}
.user-pair{display:flex;align-items:center;gap:8px}.user-dot{width:34px;height:34px;border-radius:11px;background:var(--blin-primary-soft);color:var(--blin-primary);display:inline-flex;align-items:center;justify-content:center;font-weight:850;flex:none}.text-clip{max-width:320px;white-space:nowrap!important;overflow:hidden;text-overflow:ellipsis}.im-actions{display:flex;gap:6px;flex-wrap:wrap}.im-actions .btn{margin:0!important;width:auto!important}

/* Download pages keep their business layout but inherit the same vocabulary. */
.download-admin-page .download-hero,.download-edit-page .download-hero{border-radius:var(--blin-radius)!important;border:1px solid var(--blin-line)!important;background:var(--blin-surface)!important;box-shadow:none!important}.download-admin-page .app-icon,.download-edit-page .app-icon{width:56px!important;height:56px!important;border-radius:14px!important;object-fit:cover!important}.download-edit-page .template-grid{display:grid!important;grid-template-columns:repeat(3,minmax(0,1fr))!important;gap:12px!important}.download-edit-page .template-option{border:1px solid var(--blin-line)!important;border-radius:var(--blin-radius)!important;background:var(--blin-surface)!important;box-shadow:none!important;overflow:hidden!important}.download-edit-page .template-option.active{border-color:var(--blin-primary)!important;box-shadow:0 0 0 3px rgba(37,99,235,.12)!important}

@media (max-width:1280px){.blin-metric-grid{grid-template-columns:repeat(4,minmax(0,1fr))}}
@media (max-width:1024px){
  body.blin-admin-v3 .lyear-layout-sidebar{transform:translateX(-100%);transition:transform .18s ease-out;width:268px!important;box-shadow:18px 0 38px rgba(15,23,42,.12)!important}
  body.blin-admin-v3 .lyear-layout-sidebar.lyear-aside-open{transform:translateX(0)}
  body.blin-admin-v3 .lyear-layout-header,body.blin-admin-v3 .lyear-layout-content{left:0!important}
  .im-stat-grid,.blin-metric-grid{grid-template-columns:repeat(2,minmax(0,1fr))}
  .download-edit-page .template-grid{grid-template-columns:repeat(2,minmax(0,1fr))!important}
}
@media (max-width:640px){
  body.blin-admin-v3 .navbar{padding:0 12px!important}
  .admin-profile-name,.blin-top-action span{display:none!important}
  body.blin-admin-v3-content .container-fluid{padding:12px!important}
  body.blin-admin-v3-content .card-body{padding:14px!important}
  body.blin-admin-v3-content .search-box,body.blin-admin-v3-content .toolbar-btn-action,body.blin-admin-v3-content .im-toolbar{align-items:stretch!important}
  body.blin-admin-v3-content .search-box>*,body.blin-admin-v3-content .toolbar-btn-action>*,body.blin-admin-v3-content .im-toolbar>*{width:100%!important;max-width:none!important;min-width:0!important;flex:1 1 100%!important}
  body.blin-admin-v3-content .toolbar-btn-action>.btn,body.blin-admin-v3-content .search-box>.btn,body.blin-admin-v3-content .im-toolbar>.btn,body.blin-admin-v3-content .modal-footer>.btn{width:100%!important}
  .blin-overview-bar,.im-visual-hero{align-items:stretch;flex-direction:column}.blin-overview-copy{align-items:flex-start;flex-direction:column;gap:2px}.im-hero-actions .btn{width:100%!important}.im-stat-grid,.blin-metric-grid{grid-template-columns:1fr}
  .blin-chart-card .card-body{height:260px}.blin-setting-row{align-items:flex-start!important;flex-direction:column!important}.blin-segmented-switch{width:100%!important}.blin-switch-choice{flex:1!important}
  body.blin-admin-v3-content .modal-dialog{max-width:none!important;margin:0!important;height:100%}
  body.blin-admin-v3-content .modal-content{min-height:100%;border-radius:0!important}
  body.blin-admin-v3-content .bootstrap-table table{min-width:760px}
  body.blin-admin-v3-content .fixed-table-toolbar{align-items:stretch!important;flex-direction:column!important}
  .download-edit-page .template-grid,.blin-im-admin-links{grid-template-columns:1fr!important}
  .blin-login-layout{grid-template-columns:1fr}.blin-login-visual{display:none}.blin-login-panel{padding:22px}.blin-login-captcha-row{grid-template-columns:1fr}.blin-login-captcha{width:100%}
}
@media (prefers-reduced-motion: reduce){*,*:before,*:after{transition:none!important;animation:none!important;scroll-behavior:auto!important}}
'''


def main() -> None:
    changed = 0
    changed += int(patch_css())
    changed += int(patch_index())
    changed += int(patch_layout())
    changed += int(patch_home())
    changed += int(patch_login())
    changed += int(patch_app_edit_links())
    changed += patch_im_titles()
    changed += int(patch_appstore_controller())
    changed += bump_css_versions()
    clear_runtime()
    print("admin console v3 patch applied, changed=%s" % changed)


if __name__ == "__main__":
    main()
