#!/usr/bin/env python3
"""Improve admin clarity and button contrast for app management pages."""
from datetime import datetime
from pathlib import Path
import re


ROOT = Path("/www/wwwroot/blinlin")
ADMIN = ROOT / "application/admin/controller/App.php"
APP_INDEX = ROOT / "application/admin/view/app/index.html"
APP_EDIT = ROOT / "application/admin/view/app/edit.html"
LAYOUT = ROOT / "application/admin/view/layout.html"
MODERN_CSS = ROOT / "public/static/css/modern-admin.css"


def backup(path: Path, suffix: str) -> str:
    target = path.with_name(
        f"{path.name}.bak_{suffix}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    target.write_text(path.read_text(errors="ignore"))
    return str(target)


def patch_admin_controller() -> bool:
    source = ADMIN.read_text(errors="ignore")
    original = source
    source = source.replace(
        '"community_switch" => isset($data["community_switch"]) ? 0 : 1,',
        '"community_switch" => isset($data["community_switch"]) ? intval($data["community_switch"]) : 1,',
    )
    if source != original:
        print("PATCH_ADMIN_CONTROLLER_BACKUP", backup(ADMIN, "admin_ui_community_switch"))
        ADMIN.write_text(source)
        return True
    return False


def patch_app_index() -> bool:
    source = APP_INDEX.read_text(errors="ignore")
    original = source
    source = source.replace(
        '<div class="container-fluid">',
        '<div class="container-fluid admin-app-list">',
        1,
    )
    source = source.replace(
        '            title: "操作",\n            formatter: btnGroup,',
        '            title: "操作",\n            width: 260,\n            formatter: btnGroup,',
        1,
    )
    replacements = {
        """            html += '<a href="#!" class="btn btn-sm btn-default me-1 edit-btn" title="编辑" data-bs-toggle="tooltip"><i class="mdi mdi-pencil"></i></a>';
            html += '<a href="#!" class="btn btn-sm btn-default me-1 login-policy-btn" title="登录策略" data-bs-toggle="tooltip"><i class="mdi mdi-key-variant"></i> 登录策略</a>';""":
        """            html += '<a href="#!" class="btn btn-sm btn-admin-action btn-admin-edit me-1 edit-btn" title="编辑" data-bs-toggle="tooltip"><i class="mdi mdi-pencil"></i><span>编辑</span></a>';
            html += '<a href="#!" class="btn btn-sm btn-admin-action btn-admin-policy me-1 login-policy-btn" title="登录策略" data-bs-toggle="tooltip"><i class="mdi mdi-key-variant"></i><span>登录策略</span></a>';""",
        """            html += '<a href="#!" class="btn btn-sm btn-default me-1 edit-btn" title="编辑" data-bs-toggle="tooltip"><i class="mdi mdi-pencil"></i></a>';""":
        """            html += '<a href="#!" class="btn btn-sm btn-admin-action btn-admin-edit me-1 edit-btn" title="编辑" data-bs-toggle="tooltip"><i class="mdi mdi-pencil"></i><span>编辑</span></a>';""",
        """            html += '<a href="#!" class="btn btn-sm btn-default del-btn" title="删除" data-bs-toggle="tooltip"><i class="mdi mdi-window-close"></i></a>';""":
        """            html += '<a href="#!" class="btn btn-sm btn-admin-action btn-admin-delete del-btn" title="删除" data-bs-toggle="tooltip"><i class="mdi mdi-window-close"></i><span>删除</span></a>';""",
    }
    for old, new in replacements.items():
        source = source.replace(old, new)
    if source != original:
        print("PATCH_APP_INDEX_BACKUP", backup(APP_INDEX, "admin_ui_index"))
        APP_INDEX.write_text(source)
        return True
    return False


def patch_app_edit() -> bool:
    source = APP_EDIT.read_text(errors="ignore")
    original = source
    source = source.replace(
        '<div class="container-fluid p-t-15">',
        '<div class="container-fluid p-t-15 admin-app-edit">',
        1,
    )
    old = '''                        <div>
                            <span>社区模块</span>
                            <div class="form-check form-check-inline">
                                <input type="checkbox" id="community_switch" value="{$data.forum_configuration.community_switch}" name="community_switch" class="form-check-input" {if $data.forum_configuration.community_switch==0} checked {/if}>
                                <label class="form-check-label" for="community_switch">客户端显示社区入口</label>
                            </div>
                            <small>关闭后客户端隐藏社区首页和帖子相关入口，底部导航显示消息、发现、我的。</small>
                        </div>'''
    new = '''                        <div class="blin-setting-row blin-community-switch-card">
                            <div class="blin-setting-copy">
                                <span class="blin-setting-title">社区模块</span>
                                <small class="blin-setting-desc">控制客户端是否显示社区首页和帖子相关入口。关闭后底部导航显示消息、发现、我的。</small>
                            </div>
                            <div class="blin-segmented-switch" role="group" aria-label="社区模块开关">
                                <input type="radio" id="community_switch_on" value="0" name="community_switch" class="btn-check" autocomplete="off" {if $data.forum_configuration.community_switch==0} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-on" for="community_switch_on"><i class="mdi mdi-check-circle-outline"></i>开启</label>
                                <input type="radio" id="community_switch_off" value="1" name="community_switch" class="btn-check" autocomplete="off" {if $data.forum_configuration.community_switch==1} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-off" for="community_switch_off"><i class="mdi mdi-close-circle-outline"></i>关闭</label>
                            </div>
                        </div>'''
    if old in source:
        source = source.replace(old, new, 1)
    elif "blin-community-switch-card" not in source:
        raise SystemExit("COMMUNITY_SWITCH_BLOCK_NOT_FOUND")
    if source != original:
        print("PATCH_APP_EDIT_BACKUP", backup(APP_EDIT, "admin_ui_edit"))
        APP_EDIT.write_text(source)
        return True
    return False


def patch_layout() -> bool:
    source = LAYOUT.read_text(errors="ignore")
    original = source
    source = re.sub(
        r"/static/css/modern-admin\.css\?v=\d+",
        "/static/css/modern-admin.css?v=202606132245",
        source,
        count=1,
    )
    if source != original:
        print("PATCH_LAYOUT_BACKUP", backup(LAYOUT, "admin_ui_css_version"))
        LAYOUT.write_text(source)
        return True
    return False


def patch_css() -> bool:
    source = MODERN_CSS.read_text(errors="ignore")
    original = source
    marker = "/* ===== Admin clarity and action contrast fixes ===== */"
    if marker not in source:
        source += r'''

/* ===== Admin clarity and action contrast fixes ===== */
body:not(.center-vh) .toolbar-btn-action{
  display:flex!important;
  flex-wrap:wrap!important;
  align-items:center!important;
  gap:10px!important;
  padding:14px!important;
  margin-bottom:16px!important;
  background:#f8fafc!important;
  border:1px solid rgba(23,32,51,.08)!important;
  border-radius:16px!important;
}
body:not(.center-vh) .toolbar-btn-action .btn{
  min-height:40px!important;
  display:inline-flex!important;
  align-items:center!important;
  justify-content:center!important;
  gap:8px!important;
  padding:.5rem .9rem!important;
  border:0!important;
  letter-spacing:0!important;
}
body:not(.center-vh) .btn-label label{
  display:inline-flex!important;
  align-items:center!important;
  justify-content:center!important;
  width:26px!important;
  height:26px!important;
  margin:-2px 2px -2px -4px!important;
  border-radius:9px!important;
  color:currentColor!important;
  background:rgba(255,255,255,.24)!important;
}
body:not(.center-vh) .btn-label label i,
body:not(.center-vh) .btn-label label span,
body:not(.center-vh) .btn .mdi,
body:not(.center-vh) .btn i{
  color:currentColor!important;
  opacity:1!important;
}
body:not(.center-vh) .btn-primary{color:#fff!important;background:linear-gradient(135deg,#2563eb,#0ea5e9)!important}
body:not(.center-vh) .btn-success{color:#fff!important;background:linear-gradient(135deg,#10b981,#14b8a6)!important}
body:not(.center-vh) .btn-danger{color:#fff!important;background:linear-gradient(135deg,#ef4444,#f97316)!important}
body:not(.center-vh) .btn-info{color:#fff!important;background:linear-gradient(135deg,#0ea5e9,#2563eb)!important}
body:not(.center-vh) .btn-warning{color:#1e293b!important;background:linear-gradient(135deg,#fbbf24,#f59e0b)!important}
body:not(.center-vh) .btn-secondary:not(.dropdown-toggle),
body:not(.center-vh) .btn-default,
body:not(.center-vh) .btn-light{
  color:#334155!important;
  background:#fff!important;
  border:1px solid rgba(23,32,51,.12)!important;
}
body:not(.center-vh) .badge-outline-primary{color:#1d4ed8!important;background:#eff6ff!important;border:1px solid #bfdbfe!important}
body:not(.center-vh) .badge-outline-success{color:#047857!important;background:#ecfdf5!important;border:1px solid #a7f3d0!important}
body:not(.center-vh) .badge-outline-info{color:#0369a1!important;background:#f0f9ff!important;border:1px solid #bae6fd!important}
body:not(.center-vh) .badge-outline-warning{color:#92400e!important;background:#fffbeb!important;border:1px solid #fde68a!important}
body:not(.center-vh) .badge-outline-dark{color:#1e293b!important;background:#f1f5f9!important;border:1px solid #cbd5e1!important}
.admin-app-list .bootstrap-table .fixed-table-container{
  border-radius:18px!important;
  border:1px solid rgba(23,32,51,.10)!important;
}
.admin-app-list .bootstrap-table table thead th{
  background:#eef2ff!important;
  color:#1e293b!important;
}
.admin-app-list .bootstrap-table table tbody tr:hover{
  background:#f8fafc!important;
}
body:not(.center-vh) table td .btn-admin-action,
body:not(.center-vh) .bootstrap-table td .btn-admin-action{
  display:inline-flex!important;
  align-items:center!important;
  justify-content:center!important;
  gap:5px!important;
  min-height:32px!important;
  padding:.35rem .65rem!important;
  border:0!important;
  color:#fff!important;
  box-shadow:0 8px 18px rgba(21,35,63,.10)!important;
}
body:not(.center-vh) table td .btn-admin-edit{background:#2563eb!important}
body:not(.center-vh) table td .btn-admin-policy{background:#475569!important}
body:not(.center-vh) table td .btn-admin-delete{background:#ef4444!important}
body:not(.center-vh) table td .btn-admin-action i,
body:not(.center-vh) table td .btn-admin-action span{color:#fff!important}
.admin-app-edit .card-header{
  display:flex!important;
  align-items:center!important;
  min-height:58px!important;
}
.admin-app-edit .card-title:before{
  content:"";
  display:inline-block;
  width:8px;
  height:18px;
  margin-right:10px;
  border-radius:999px;
  background:#6366f1;
  vertical-align:-3px;
}
.admin-app-edit small{
  color:#64748b!important;
  line-height:1.55!important;
}
.blin-setting-row{
  display:flex!important;
  align-items:center!important;
  justify-content:space-between!important;
  gap:18px!important;
  padding:16px!important;
  margin-bottom:18px!important;
  background:#f8fafc!important;
  border:1px solid rgba(23,32,51,.08)!important;
  border-radius:16px!important;
}
.blin-setting-copy{
  display:flex!important;
  flex-direction:column!important;
  gap:5px!important;
  min-width:0!important;
}
.blin-setting-title{
  color:#1e293b!important;
  font-size:15px!important;
  font-weight:800!important;
}
.blin-setting-desc{
  color:#64748b!important;
  font-size:12px!important;
}
.blin-segmented-switch{
  display:inline-flex!important;
  align-items:center!important;
  gap:4px!important;
  padding:4px!important;
  background:#fff!important;
  border:1px solid rgba(23,32,51,.10)!important;
  border-radius:999px!important;
  box-shadow:0 8px 18px rgba(21,35,63,.06)!important;
  flex-shrink:0!important;
}
.blin-segmented-switch .btn-check{
  position:absolute!important;
  clip:rect(0,0,0,0)!important;
  pointer-events:none!important;
}
.blin-switch-choice{
  display:inline-flex!important;
  align-items:center!important;
  gap:6px!important;
  min-width:78px!important;
  justify-content:center!important;
  padding:8px 14px!important;
  margin:0!important;
  border-radius:999px!important;
  color:#475569!important;
  font-size:13px!important;
  font-weight:800!important;
  cursor:pointer!important;
  transition:all .16s ease!important;
}
.blin-switch-choice i{color:currentColor!important}
.btn-check:checked + .blin-switch-choice-on{
  color:#fff!important;
  background:#10b981!important;
  box-shadow:0 10px 20px rgba(16,185,129,.22)!important;
}
.btn-check:checked + .blin-switch-choice-off{
  color:#fff!important;
  background:#ef4444!important;
  box-shadow:0 10px 20px rgba(239,68,68,.20)!important;
}
@media(max-width:768px){
  .blin-setting-row{align-items:flex-start!important;flex-direction:column!important}
  .blin-segmented-switch{width:100%!important}
  .blin-switch-choice{flex:1!important}
}
'''
    if source != original:
        print("PATCH_CSS_BACKUP", backup(MODERN_CSS, "admin_ui_clarity"))
        MODERN_CSS.write_text(source)
        return True
    return False


def main() -> None:
    changed = False
    for fn in [
        patch_admin_controller,
        patch_app_index,
        patch_app_edit,
        patch_layout,
        patch_css,
    ]:
        changed = fn() or changed
    print("PATCHED_ADMIN_UI_CLARITY" if changed else "ADMIN_UI_CLARITY_ALREADY_UP_TO_DATE")


if __name__ == "__main__":
    main()
