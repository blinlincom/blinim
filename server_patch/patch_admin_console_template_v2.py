#!/usr/bin/env python3
"""Repair and rebuild the admin console template after the first redesign pass.

The first modern console pass replaced modern-admin.css wholesale, which removed
older feature-specific styles. This V2 patch restores the previous CSS base from
the server backup, then appends a scoped console layer so existing pages keep
their behavior while the shell, mobile layout, tables, and IM visual management
pages get the new product-grade treatment.
"""
from datetime import datetime
from pathlib import Path
import re
import shutil


ROOT = Path("/www/wwwroot/blinlin")
VIEW = ROOT / "app/admin/view"
CSS = ROOT / "public/static/css/modern-admin.css"
INDEX_VIEW = VIEW / "index/index.html"
GROUP_VIEW = VIEW / "im/group_manage.html"
PRIVATE_VIEW = VIEW / "im/private_chat_manage.html"
APP_EDIT_VIEW = VIEW / "app/edit.html"
APPSTORE_CONTROLLER = ROOT / "app/admin/controller/Appstore.php"
RUNTIME_ADMIN = ROOT / "runtime/admin/temp"
RUNTIME_CACHE = ROOT / "runtime/cache"
VERSION = "202606231215"
MARKER = "/* ===== Blin Admin Console V2 scoped rebuild ===== */"


def backup(path, suffix):
    if not path.exists():
        return
    target = path.with_name(
        "%s.bak_%s_%s" % (path.name, suffix, datetime.now().strftime("%Y%m%d%H%M%S"))
    )
    shutil.copy2(str(path), str(target))
    print("BACKUP", target)


def write_if_changed(path, text, suffix):
    old = path.read_text(errors="ignore") if path.exists() else ""
    if old == text:
        return False
    backup(path, suffix)
    path.write_text(text, encoding="utf-8")
    print("UPDATED", path)
    return True


def strip_v2(css):
    return re.sub(re.escape(MARKER) + r".*\Z", "", css, flags=re.S).rstrip() + "\n"


def restore_css_base():
    backups = sorted(CSS.parent.glob("modern-admin.css.bak_modern_console_css_*"))
    if backups:
        base = backups[-1].read_text(errors="ignore")
        print("RESTORE_CSS_BASE", backups[-1])
    else:
        base = CSS.read_text(errors="ignore")
        base = re.sub(r"/\* Blin IM Modern Console Template 2026 \*/.*\Z", "", base, flags=re.S)
    base = strip_v2(base)
    return write_if_changed(CSS, base + "\n" + V2_CSS.strip() + "\n", "console_v2_css")


def bump_css_versions():
    changed = 0
    for path in VIEW.rglob("*.html"):
        text = path.read_text(errors="ignore")
        new = re.sub(
            r"/static/css/modern-admin\.css\?v=\d+",
            "/static/css/modern-admin.css?v=%s" % VERSION,
            text,
        )
        if write_if_changed(path, new, "console_v2_css_version"):
            changed += 1
    return changed


def patch_index():
    text = INDEX_VIEW.read_text(errors="ignore")
    text = text.replace(
        '<body class="lyear-index blin-console-shell">',
        '<body class="lyear-index blin-console-shell blin-console-v2">',
    )
    text = text.replace(
        '<div class="blin-console-title">\n'
        '                            <strong>数据运营台</strong>\n'
        '                            <span>应用 / 用户 / 消息 / 财务 / 系统</span>\n'
        '                        </div>',
        '<div class="blin-console-title">\n'
        '                            <strong>管理控制台</strong>\n'
        '                            <span>应用、用户、消息、财务、系统统一管理</span>\n'
        '                        </div>',
    )
    if 'blin-im-fast-links' not in text:
        text = text.replace(
            '<li>\n'
            '                            <a href="javascript:void(0)" onclick="Clear_All()" class="blin-top-action">\n'
            '                                <i class="mdi mdi-broom"></i>\n'
            '                                <span>清缓存</span>\n'
            '                            </a>\n'
            '                        </li>',
            '<li class="blin-im-fast-links">\n'
            '                            <a class="blin-top-action multitabs" href="{$Request.root}/im/group_manage" data-url="{$Request.root}/im/group_manage"><i class="mdi mdi-account-group-outline"></i><span>群管理</span></a>\n'
            '                            <a class="blin-top-action multitabs" href="{$Request.root}/im/private_chat_manage" data-url="{$Request.root}/im/private_chat_manage"><i class="mdi mdi-message-text-outline"></i><span>私聊</span></a>\n'
            '                        </li>\n'
            '                        <li>\n'
            '                            <a href="javascript:void(0)" onclick="Clear_All()" class="blin-top-action">\n'
            '                                <i class="mdi mdi-broom"></i>\n'
            '                                <span>清缓存</span>\n'
            '                            </a>\n'
            '                        </li>',
        )
    text = text.replace(
        "        function setSidebar(data) {\n"
        "            if (data.length == 0) return false;\n"
        "            var treeObj = getTrees(data, 0, 'id', 'pid', 'children');\n"
        "            $('.sidebar-main').append(createMenu(treeObj, true));\n"
        "        }",
        "        function setSidebar(data) {\n"
        "            if (data.length == 0) return false;\n"
        "            data = normalizeMenu(data);\n"
        "            var treeObj = getTrees(data, 0, 'id', 'pid', 'children');\n"
        "            $('.sidebar-main').append(createMenu(treeObj, true));\n"
        "        }\n"
        "        function normalizeMenu(data) {\n"
        "            var iconMap = {\n"
        "                '首页':'mdi mdi-view-dashboard-outline','权限管理':'mdi mdi-shield-account-outline','系统管理':'mdi mdi-tune-variant','APP管理':'mdi mdi-cellphone-cog','用户管理':'mdi mdi-account-multiple-outline','卡密管理':'mdi mdi-card-bulleted-outline','商城管理':'mdi mdi-storefront-outline','提现管理':'mdi mdi-wallet-outline','笔记管理':'mdi mdi-note-text-outline','论坛管理':'mdi mdi-forum-outline','应用商店':'mdi mdi-emoticon-outline','即时通讯':'mdi mdi-message-text-outline','即时通讯管理':'mdi mdi-message-text-outline'\n"
        "            };\n"
        "            return $.map(data, function(item){\n"
        "                item.icon = item.icon || iconMap[item.name] || '';\n"
        "                if (item.name === '即时通讯管理') item.sort = 2.5;\n"
        "                if (item.name === '群聊运营管理') item.sort = 2.6;\n"
        "                if (item.name === '私聊记录管理') item.sort = 2.7;\n"
        "                return item;\n"
        "            }).sort(function(a,b){ return (parseFloat(a.sort)||0) - (parseFloat(b.sort)||0); });\n"
        "        }",
    )
    text = text.replace(
        "            var menu_body = is_frist ? '<ul class=\"nav-drawer\">' : '<ul class=\"nav nav-subnav\">';",
        "            var menu_body = is_frist ? '<ul class=\"nav-drawer\">' : '<ul class=\"nav nav-subnav\">';",
    )
    text = text.replace(
        "                if (item.name === '即时通讯管理') item.sort = 2.5;\n"
        "                if (item.name === '群聊运营管理') item.sort = 2.6;\n"
        "                if (item.name === '私聊记录管理') item.sort = 2.7;",
        "                if (item.name === '即时通讯管理' || item.name === '即时通讯配置') { item.name = '即时通讯管理'; item.sort = 2.5; }\n"
        "                if (item.name === '群聊运营管理' || item.name === '群运营管理') { item.name = '群聊运营管理'; item.sort = 2.6; }\n"
        "                if (item.name === '私聊记录管理' || item.name === '私聊运营管理') { item.name = '私聊运营管理'; item.sort = 2.7; }",
    )
    text = text.replace(
        "                    var nav_selected = i == 0 ? ' active open' : '';",
        "                    var nav_selected = (i == 0 || data[i].name === '即时通讯管理') ? ' active open' : '';",
    )
    return write_if_changed(INDEX_VIEW, text, "console_v2_shell")


def patch_group_view():
    text = GROUP_VIEW.read_text(errors="ignore")
    text = re.sub(r"<style>.*?</style>\s*", "", text, flags=re.S)
    text = text.replace(
        '<div class="container-fluid p-t-15">',
        '<div class="container-fluid p-t-15 im-visual-page im-group-admin-page">',
        1,
    )
    text = text.replace(
        '<div class="card im-card">\n'
        '    <header class="card-header d-flex justify-content-between align-items-center">\n'
        '      <div><div class="im-title">群聊运营管理</div><div class="im-sub">创建、编辑、解散群聊，管理成员和群消息</div></div>\n'
        '      <button class="btn btn-primary" onclick="openCreateModal()"><i class="mdi mdi-plus"></i> 创建群聊</button>\n'
        '    </header>',
        '<section class="im-visual-hero">\n'
        '    <div><div class="im-title">群聊运营管理</div><div class="im-sub">创建、编辑、解散群聊，管理成员、群资料和群消息</div></div>\n'
        '    <div class="im-hero-actions"><button class="btn btn-primary" onclick="openCreateModal()"><i class="mdi mdi-plus"></i> 创建群聊</button></div>\n'
        '  </section>\n'
        '  <div class="im-stat-grid">\n'
        '    <div><span>群聊总数</span><strong id="group_total">--</strong></div>\n'
        '    <div><span>成员管理</span><strong>角色 / 移出</strong></div>\n'
        '    <div><span>消息管理</span><strong>隐藏 / 删除</strong></div>\n'
        '    <div><span>危险操作</span><strong>解散 / 清空</strong></div>\n'
        '  </div>\n'
        '  <div class="card im-card">\n'
        '    <header class="card-header d-flex justify-content-between align-items-center">\n'
        '      <div><div class="card-title">群聊列表</div><div class="im-sub">按应用、状态和关键词筛选群聊</div></div>\n'
        '    </header>',
    )
    text = text.replace(
        "totalField:'total',queryParams:queryGroups,columns:[",
        "totalField:'total',queryParams:queryGroups,onLoadSuccess:function(res){ $('#group_total').text((res&&res.total)||0); },columns:[",
    )
    text = text.replace("style=\"max-width:220px\"", "")
    text = text.replace("style=\"max-width:150px\"", "")
    text = text.replace("style=\"max-width:280px\"", "")
    return write_if_changed(GROUP_VIEW, text, "console_v2_group_view")


def patch_private_view():
    text = PRIVATE_VIEW.read_text(errors="ignore")
    text = re.sub(r"<style>.*?</style>\s*", "", text, flags=re.S)
    text = text.replace("私聊记录管理", "私聊运营管理")
    text = text.replace(
        '<div class="container-fluid p-t-15">',
        '<div class="container-fluid p-t-15 im-visual-page im-private-admin-page">',
        1,
    )
    text = text.replace(
        '<div class="card im-card">\n'
        '    <header class="card-header">\n'
        '      <div class="im-title">私聊记录管理</div>\n'
        '      <div class="im-sub">按会话查看个人聊天记录，可隐藏消息、删除消息或清空双方会话</div>\n'
        '    </header>',
        '<section class="im-visual-hero">\n'
        '    <div><div class="im-title">私聊记录管理</div><div class="im-sub">按会话查看聊天记录，支持隐藏、删除、标记已读和清空双方记录</div></div>\n'
        '  </section>\n'
        '  <div class="im-stat-grid">\n'
        '    <div><span>会话总数</span><strong id="conversation_total">--</strong></div>\n'
        '    <div><span>消息查看</span><strong>逐条审查</strong></div>\n'
        '    <div><span>记录处理</span><strong>隐藏 / 删除</strong></div>\n'
        '    <div><span>双方会话</span><strong>清空 / 已读</strong></div>\n'
        '  </div>\n'
        '  <div class="card im-card">\n'
        '    <header class="card-header">\n'
        '      <div><div class="card-title">私聊会话</div><div class="im-sub">按应用、用户或消息内容检索</div></div>\n'
        '    </header>',
    )
    text = text.replace(
        "totalField:'total',queryParams:function(p){return {limit:p.limit,page:(p.offset/p.limit)+1,appid:$('#appid').val(),keyword:$('#keyword').val()}},columns:[",
        "totalField:'total',queryParams:function(p){return {limit:p.limit,page:(p.offset/p.limit)+1,appid:$('#appid').val(),keyword:$('#keyword').val()}},onLoadSuccess:function(res){ $('#conversation_total').text((res&&res.total)||0); },columns:[",
    )
    text = text.replace("style=\"max-width:220px\"", "")
    text = text.replace("style=\"max-width:320px\"", "")
    text = text.replace("style=\"max-width:260px\"", "")
    return write_if_changed(PRIVATE_VIEW, text, "console_v2_private_view")


def patch_app_edit_view():
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
    return write_if_changed(APP_EDIT_VIEW, text, "console_v2_app_im_links")


def patch_appstore_controller():
    if not APPSTORE_CONTROLLER.exists():
        return False
    text = APPSTORE_CONTROLLER.read_text(errors="ignore")
    text = text.replace(
        '$this->success("导入成功", null, ["count" => count($savedItems)]);',
        '$this->success("导入成功", "", ["count" => count($savedItems)]);',
    )
    return write_if_changed(APPSTORE_CONTROLLER, text, "console_v2_tp8_success")


def clear_runtime():
    for root in [RUNTIME_ADMIN, RUNTIME_CACHE]:
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if path.is_file():
                try:
                    path.unlink()
                except Exception:
                    pass


V2_CSS = r'''
/* ===== Blin Admin Console V2 scoped rebuild ===== */
:root{
  --blin-primary:#2563EB;
  --blin-primary-deep:#1D4ED8;
  --blin-cyan:#0EA5E9;
  --blin-success:#10B981;
  --blin-warning:#F59E0B;
  --blin-danger:#EF4444;
  --blin-page:#F4F7FB;
  --blin-card:#FFFFFF;
  --blin-ink:#1E293B;
  --blin-text:#475569;
  --blin-muted:#64748B;
  --blin-soft:#F1F5F9;
  --blin-line:#E2E8F0;
  --blin-sidebar:#101827;
  --blin-shadow:0 10px 28px rgba(21,35,63,.08);
}
html body.blin-console-v2,
html body.blin-console-content{background:var(--blin-page)!important;color:var(--blin-ink)!important;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Microsoft YaHei",sans-serif!important;letter-spacing:0!important}
html body.blin-console-content:not(.center-vh){padding:0!important;background:var(--blin-page)!important;background-image:none!important}
body.blin-console-v2 .lyear-layout-sidebar{width:268px!important;background:var(--blin-sidebar)!important;border-right:0!important;box-shadow:18px 0 40px rgba(15,23,42,.18)!important}
body.blin-console-v2 .sidebar-header{height:72px!important;background:var(--blin-sidebar)!important;border-bottom:1px solid rgba(255,255,255,.08)!important}
body.blin-console-v2 #logo a{height:72px!important;line-height:1!important;padding:0 18px!important;color:#fff!important}
body.blin-console-v2 #logo a:before,body.blin-console-v2 #logo a:after{display:none!important;content:none!important}
.blin-console-logo{display:flex!important;align-items:center!important;gap:12px!important}
.blin-console-logo-mark{width:40px;height:40px;border-radius:14px;background:linear-gradient(135deg,var(--blin-cyan),var(--blin-primary));color:#fff!important;display:inline-flex;align-items:center;justify-content:center;font-size:20px;font-weight:800;box-shadow:0 12px 24px rgba(37,99,235,.28)}
.blin-console-logo-copy{display:flex;flex-direction:column;gap:3px}.blin-console-logo-copy strong{font-size:16px;font-weight:800;color:#fff}.blin-console-logo-copy small{font-size:12px;font-weight:600;color:#94A3B8}
.blin-sidebar-search{margin:14px 14px 8px;padding:0 12px;height:42px;display:flex;align-items:center;gap:8px;border-radius:14px;background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.08)}.blin-sidebar-search input{width:100%;border:0;background:transparent;outline:0;color:#fff;font-size:13px}.blin-sidebar-search input::placeholder{color:#94A3B8}.blin-sidebar-search i{color:#94A3B8}
body.blin-console-v2 .lyear-layout-sidebar-info{top:136px!important;padding:0 12px 16px!important;background:var(--blin-sidebar)!important}
body.blin-console-v2 .sidebar-main a,body.blin-console-v2 .nav-drawer>li>a,body.blin-console-v2 .nav-subnav>li>a{min-height:42px!important;margin:3px 0!important;padding:0 12px!important;border-radius:12px!important;display:flex!important;align-items:center!important;gap:10px!important;color:#F8FAFC!important;background:transparent!important;font-size:14px!important;font-weight:750!important;opacity:1!important;text-shadow:none!important}
body.blin-console-v2 .sidebar-main a *,body.blin-console-v2 .nav-drawer>li>a *,body.blin-console-v2 .nav-subnav>li>a *,body.blin-console-v2 .blin-sidebar-menu-text{color:#F8FAFC!important;opacity:1!important;text-shadow:none!important}
body.blin-console-v2 .nav-drawer>li>a i{width:22px;text-align:center;color:#BFDBFE!important;font-size:19px!important}.blin-sub-dot{width:7px;height:7px;border-radius:999px;background:#93C5FD;margin-left:8px}
body.blin-console-v2 .nav-subnav{margin:4px 0 8px 12px!important;padding:4px 0 4px 10px!important;border-left:1px solid rgba(255,255,255,.10)!important;background:transparent!important}
body.blin-console-v2 .nav-item-has-subnav.open>.nav-subnav,body.blin-console-v2 .nav-item-has-subnav.active>.nav-subnav{display:block!important}
body.blin-console-v2 .nav-subnav>li>a{background:rgba(255,255,255,.045)!important}
body.blin-console-v2 .sidebar-main a:hover,body.blin-console-v2 .nav-drawer>li.active>a,body.blin-console-v2 .nav-drawer>li.open>a,body.blin-console-v2 .nav-subnav>li.active>a{background:rgba(37,99,235,.34)!important;color:#fff!important}
body.blin-console-v2 .sidebar-main a:hover *,body.blin-console-v2 .nav-drawer>li.active>a *,body.blin-console-v2 .nav-drawer>li.open>a *,body.blin-console-v2 .nav-subnav>li.active>a *{color:#fff!important}
body.blin-console-v2 .lyear-layout-header{left:268px!important;height:72px!important;background:rgba(248,250,252,.96)!important;border-bottom:1px solid var(--blin-line)!important;box-shadow:none!important}
body.blin-console-v2 .navbar{height:72px!important;padding:0 20px!important;background:transparent!important;box-shadow:none!important}
.blin-console-title strong{display:block;color:var(--blin-ink);font-size:18px;font-weight:800}.blin-console-title span{display:block;color:var(--blin-muted);font-size:12px;font-weight:600;margin-top:3px}
.blin-icon-button,.lyear-aside-toggler{width:42px!important;height:42px!important;border-radius:14px!important;border:1px solid var(--blin-line)!important;background:#fff!important;display:inline-flex!important;flex-direction:column!important;justify-content:center!important;align-items:center!important;gap:4px!important}
.lyear-toggler-bar{width:18px!important;height:2px!important;background:var(--blin-ink)!important;border-radius:999px!important}
.blin-top-action{min-height:40px;display:inline-flex!important;align-items:center!important;justify-content:center;gap:7px;padding:0 12px;border-radius:14px;border:1px solid var(--blin-line);background:#fff;color:var(--blin-text)!important;font-size:13px;font-weight:750}.blin-im-fast-links{display:flex;gap:8px}
body.blin-console-v2 .lyear-layout-content{left:268px!important;top:72px!important;background:var(--blin-page)!important}
body.blin-console-v2 #iframe-content{height:100%!important;background:var(--blin-page)!important}
body.blin-console-v2 .mt-nav-bar{min-height:50px!important;padding:8px 16px!important;background:var(--blin-page)!important;border-bottom:1px solid var(--blin-line)!important}
body.blin-console-v2 .mt-nav-panel .nav-link{border:0!important;border-radius:999px!important;background:transparent!important;color:var(--blin-text)!important;font-size:13px!important;font-weight:700!important}
body.blin-console-v2 .mt-nav-panel .nav-link.active{background:#EEF2FF!important;color:var(--blin-primary)!important}
body.blin-console-v2 .mt-tab-content{padding-top:50px!important;background:var(--blin-page)!important}
body.blin-console-content .container-fluid{width:100%!important;max-width:1540px!important;padding:20px!important}
body.blin-console-content .card{border:1px solid var(--blin-line)!important;border-radius:16px!important;background:#fff!important;box-shadow:none!important}
body.blin-console-content .card-header{min-height:58px!important;padding:16px 18px!important;background:#fff!important;border-bottom:1px solid var(--blin-line)!important}
body.blin-console-content .card-title{font-size:17px!important;font-weight:800!important;color:var(--blin-ink)!important}
body.blin-console-content .card-body{padding:18px!important}
body.blin-console-content .toolbar-btn-action,body.blin-console-content .search-box,body.blin-console-content .im-toolbar{display:flex!important;flex-wrap:wrap!important;align-items:center!important;gap:10px!important;padding:12px!important;margin:0 0 14px!important;border:1px solid var(--blin-line)!important;border-radius:14px!important;background:var(--blin-soft)!important}
body.blin-console-content .form-control,body.blin-console-content .form-select,body.blin-console-content select{min-height:40px!important;border-radius:12px!important;border:1px solid var(--blin-line)!important;background:#fff!important;color:var(--blin-ink)!important}
body.blin-console-content .btn{min-height:40px!important;border-radius:12px!important;display:inline-flex!important;align-items:center!important;justify-content:center!important;gap:6px!important;font-weight:750!important;border:0!important;white-space:nowrap!important;box-shadow:none!important}
body.blin-console-content .btn-primary{background:var(--blin-primary)!important;color:#fff!important}body.blin-console-content .btn-success{background:var(--blin-success)!important;color:#fff!important}body.blin-console-content .btn-warning{background:var(--blin-warning)!important;color:#1E293B!important}body.blin-console-content .btn-danger{background:var(--blin-danger)!important;color:#fff!important}body.blin-console-content .btn-info{background:#06B6D4!important;color:#fff!important}body.blin-console-content .btn-default,body.blin-console-content .btn-secondary{background:#fff!important;color:var(--blin-ink)!important;border:1px solid var(--blin-line)!important}
body.blin-console-content .fixed-table-toolbar{display:flex!important;flex-wrap:wrap!important;align-items:center!important;justify-content:space-between!important;gap:10px!important;margin-bottom:10px!important}
body.blin-console-content .fixed-table-toolbar .bs-bars,body.blin-console-content .fixed-table-toolbar .columns,body.blin-console-content .fixed-table-toolbar .search{margin:0!important}
body.blin-console-content .fixed-table-toolbar .search input{min-height:38px!important;border-radius:12px!important}
body.blin-console-content .bootstrap-table .fixed-table-container{border:1px solid var(--blin-line)!important;border-radius:14px!important;background:#fff!important;overflow:hidden!important}
body.blin-console-content .fixed-table-body{overflow:auto!important}
body.blin-console-content .bootstrap-table table{min-width:900px}
body.blin-console-content .table th,body.blin-console-content .bootstrap-table table thead th{background:#F8FAFC!important;color:var(--blin-text)!important;font-size:12px!important;font-weight:850!important;border-color:var(--blin-line)!important}
body.blin-console-content .table td,body.blin-console-content .table th,body.blin-console-content .bootstrap-table td,body.blin-console-content .bootstrap-table th{vertical-align:middle!important;color:var(--blin-ink)!important;border-color:var(--blin-line)!important}
body.blin-console-content .bootstrap-table tbody tr:hover{background:#F8FAFC!important}
body.blin-console-content .modal-content{border-radius:18px!important;border:1px solid var(--blin-line)!important;box-shadow:var(--blin-shadow)!important}
body.blin-console-content .dropdown-menu{border-radius:14px!important;border:1px solid var(--blin-line)!important;box-shadow:var(--blin-shadow)!important;padding:8px!important}.dropdown-item{border-radius:10px!important;color:var(--blin-ink)!important;font-weight:650!important}.dropdown-item:hover{background:#EEF2FF!important;color:var(--blin-primary)!important}
body.blin-console-content img{max-width:100%;height:auto}
body.blin-console-content .bootstrap-table img,body.blin-console-content table img{width:44px!important;height:44px!important;max-width:44px!important;object-fit:cover!important;border-radius:12px!important;background:#EEF2FF!important;display:inline-block!important}
body.blin-console-content img.template-shot,body.blin-console-content .screenshot-item img{width:100%!important;max-width:100%!important;height:auto!important;object-fit:cover!important}
body.blin-console-content .app-icon-img,body.blin-console-content .im-avatar{width:38px!important;height:38px!important;max-width:38px!important;border-radius:12px!important;object-fit:cover!important;background:#EEF2FF!important;flex:none}
body.blin-console-content table td .btn,body.blin-console-content .bootstrap-table td .btn{width:auto!important;min-height:34px!important;padding:6px 10px!important;margin:2px!important;border-radius:10px!important}
.blin-dashboard{display:flex;flex-direction:column;gap:18px}.blin-page-hero{display:flex;align-items:center;justify-content:space-between;gap:20px;min-height:140px;padding:24px;border:1px solid var(--blin-line);border-radius:18px;background:#fff;box-shadow:var(--blin-shadow)}.blin-eyebrow{display:inline-flex;align-items:center;min-height:24px;padding:3px 9px;border-radius:999px;background:#EFF6FF;color:var(--blin-primary);font-size:12px;font-weight:850}.blin-page-hero h1{margin:10px 0 6px;color:var(--blin-ink);font-size:28px;font-weight:850}.blin-page-hero p{margin:0;color:var(--blin-text);font-size:14px}.blin-metric-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px}.blin-metric-card{position:relative;min-height:132px;padding:18px;border-radius:18px;border:1px solid var(--blin-line);background:#fff;box-shadow:var(--blin-shadow);overflow:hidden}.blin-metric-card:after{content:"";position:absolute;right:-24px;bottom:-24px;width:90px;height:90px;border-radius:999px;background:#EFF6FF}.blin-metric-card i{position:relative;z-index:1;width:42px;height:42px;border-radius:14px;background:#EFF6FF;color:var(--blin-primary);display:inline-flex;align-items:center;justify-content:center;font-size:22px}.blin-metric-card span{display:block;margin-top:14px;color:var(--blin-text);font-size:13px;font-weight:750}.blin-metric-card strong{display:block;margin-top:4px;color:var(--blin-ink);font-size:26px;font-weight:850}.blin-metric-card small{display:block;margin-top:4px;color:var(--blin-muted);font-size:12px;font-weight:650}.blin-metric-card.success i,.blin-metric-card.success:after{background:#ECFDF5;color:var(--blin-success)}.blin-metric-card.warning i,.blin-metric-card.warning:after{background:#FFFBEB;color:var(--blin-warning)}.blin-metric-card.cyan i,.blin-metric-card.cyan:after{background:#ECFEFF;color:var(--blin-cyan)}.blin-chart-card .card-body{height:320px}.blin-chart-card canvas{width:100%!important;height:100%!important}
.blin-setting-row{display:flex!important;align-items:center!important;justify-content:space-between!important;gap:16px!important;padding:14px 16px!important;border:1px solid var(--blin-line)!important;border-radius:14px!important;background:#fff!important;margin-bottom:12px!important}.blin-setting-copy{display:flex!important;flex-direction:column!important;gap:4px!important}.blin-setting-title{color:var(--blin-ink)!important;font-size:14px!important;font-weight:800!important}.blin-setting-desc{color:var(--blin-muted)!important;font-size:12px!important;font-weight:600!important}.blin-segmented-switch{display:inline-flex!important;gap:4px!important;padding:4px!important;border-radius:14px!important;background:#F1F5F9!important;border:1px solid var(--blin-line)!important}.blin-segmented-switch .btn-check{position:absolute!important;opacity:0!important;pointer-events:none!important}.blin-switch-choice{min-width:76px!important;min-height:34px!important;margin:0!important;padding:0 12px!important;border-radius:11px!important;display:inline-flex!important;align-items:center!important;justify-content:center!important;gap:6px!important;color:var(--blin-text)!important;font-size:13px!important;font-weight:800!important;cursor:pointer!important}.blin-segmented-switch .btn-check:checked + .blin-switch-choice-on,.blin-segmented-switch input:checked + .blin-switch-choice-on{background:var(--blin-success)!important;color:#fff!important}.blin-segmented-switch .btn-check:checked + .blin-switch-choice-off,.blin-segmented-switch input:checked + .blin-switch-choice-off{background:var(--blin-danger)!important;color:#fff!important}
.blin-im-admin-links{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px;margin-bottom:16px}.blin-im-admin-link-card{min-height:92px;padding:16px;border:1px solid var(--blin-line);border-radius:16px;background:#F8FAFC;color:var(--blin-ink)!important;display:grid;grid-template-columns:44px 1fr;grid-template-areas:"icon title" "icon desc";column-gap:12px;align-items:center;text-decoration:none!important}.blin-im-admin-link-card:hover{border-color:var(--blin-primary);background:#EFF6FF}.blin-im-admin-link-card i{grid-area:icon;width:44px;height:44px;border-radius:14px;background:linear-gradient(135deg,var(--blin-cyan),var(--blin-primary));color:#fff!important;display:inline-flex;align-items:center;justify-content:center;font-size:22px}.blin-im-admin-link-card span{grid-area:title;color:var(--blin-ink);font-size:15px;font-weight:850}.blin-im-admin-link-card small{grid-area:desc;color:var(--blin-muted);font-size:12px;font-weight:650;line-height:1.45}
.download-admin-page .download-hero,.download-edit-page .download-hero{border-radius:18px!important;border:1px solid var(--blin-line)!important;background:#fff!important;box-shadow:var(--blin-shadow)!important}.download-admin-page .app-icon,.download-edit-page .app-icon{width:58px!important;height:58px!important;border-radius:16px!important;object-fit:cover!important}.download-edit-page .template-grid{display:grid!important;grid-template-columns:repeat(3,minmax(0,1fr))!important;gap:14px!important}.download-edit-page .template-option{border:1px solid var(--blin-line)!important;border-radius:16px!important;background:#fff!important;box-shadow:none!important;overflow:hidden!important}.download-edit-page .template-option.active{border-color:var(--blin-primary)!important;box-shadow:0 0 0 3px rgba(37,99,235,.12)!important}
.im-visual-page{display:flex;flex-direction:column;gap:16px}.im-visual-hero{display:flex;align-items:center;justify-content:space-between;gap:16px;padding:18px;border:1px solid var(--blin-line);border-radius:18px;background:#fff;box-shadow:var(--blin-shadow)}.im-title{font-size:20px;font-weight:850;color:var(--blin-ink)}.im-sub{font-size:12px;font-weight:600;color:var(--blin-muted);margin-top:4px}.im-stat-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px}.im-stat-grid>div{padding:14px;border:1px solid var(--blin-line);border-radius:14px;background:#fff;box-shadow:var(--blin-shadow)}.im-stat-grid span{display:block;font-size:12px;font-weight:750;color:var(--blin-muted)}.im-stat-grid strong{display:block;margin-top:6px;font-size:18px;font-weight:850;color:var(--blin-ink)}.user-pair{display:flex;align-items:center;gap:8px}.user-dot{width:34px;height:34px;border-radius:12px;background:#EFF6FF;color:var(--blin-primary);display:inline-flex;align-items:center;justify-content:center;font-weight:850;flex:none}.text-clip{max-width:320px;white-space:nowrap!important;overflow:hidden;text-overflow:ellipsis}.im-actions{display:flex;gap:6px;flex-wrap:wrap}.im-actions .btn{margin:0!important;width:auto!important}
@media (max-width:1024px){
  body.blin-console-v2 .lyear-layout-sidebar{transform:translateX(-100%);transition:transform .18s ease-out;z-index:1040!important}
  body.blin-console-v2 .lyear-layout-sidebar.lyear-aside-open{transform:translateX(0)}
  body.blin-console-v2 .lyear-layout-header,body.blin-console-v2 .lyear-layout-content{left:0!important}
  body.blin-console-v2 .blin-console-title span,.blin-im-fast-links{display:none}
  .im-stat-grid,.blin-metric-grid{grid-template-columns:repeat(2,minmax(0,1fr))}
  .download-edit-page .template-grid{grid-template-columns:repeat(2,minmax(0,1fr))!important}
}
@media (max-width:640px){
  body.blin-console-v2 .navbar{padding:0 12px!important}
  body.blin-console-content .container-fluid{padding:12px!important}
  body.blin-console-content .card-body{padding:14px!important}
  body.blin-console-content .search-box>*,body.blin-console-content .toolbar-btn-action>*,body.blin-console-content .im-toolbar>*{width:100%!important;max-width:none!important}
  body.blin-console-content .toolbar-btn-action>.btn,body.blin-console-content .search-box>.btn,body.blin-console-content .im-toolbar>.btn,body.blin-console-content .modal-footer>.btn{width:100%!important}
  .blin-page-hero,.im-visual-hero{align-items:stretch;flex-direction:column}.im-hero-actions .btn{width:100%!important}.im-stat-grid,.blin-metric-grid{grid-template-columns:1fr}
  .blin-page-hero h1{font-size:23px}.blin-chart-card .card-body{height:260px}.blin-setting-row{align-items:flex-start!important;flex-direction:column!important}.blin-segmented-switch{width:100%!important}.blin-switch-choice{flex:1!important}
  body.blin-console-content .modal-dialog{max-width:none!important;margin:0!important;height:100%}
  body.blin-console-content .modal-content{min-height:100%;border-radius:0!important}
  body.blin-console-content .bootstrap-table table{min-width:760px}
  body.blin-console-content .fixed-table-toolbar{align-items:stretch!important;flex-direction:column!important}
  .download-edit-page .template-grid{grid-template-columns:1fr!important}
  .blin-im-admin-links{grid-template-columns:1fr}
  .admin-profile-name,.blin-top-action span{display:none}
}
'''


def main():
    changed = 0
    changed += int(restore_css_base())
    changed += int(patch_index())
    changed += int(patch_group_view())
    changed += int(patch_private_view())
    changed += int(patch_app_edit_view())
    changed += int(patch_appstore_controller())
    changed += bump_css_versions()
    clear_runtime()
    print("admin console v2 patch applied, changed=%s" % changed)


if __name__ == "__main__":
    main()
