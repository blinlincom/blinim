#!/usr/bin/env python3
"""Apply a restrained 2026 admin UI layer without changing backend behavior.

The patch is intentionally CSS-first. It keeps existing ThinkPHP templates,
form names, element ids, JavaScript callbacks, routes, and permission checks.
Only cache-busting links and visual overrides are changed.
"""
from datetime import datetime
from pathlib import Path
import re


ROOT = Path("/www/wwwroot/blinlin")
ADMIN_VIEW = ROOT / "application/admin/view"
MODERN_CSS = ROOT / "public/static/css/modern-admin.css"
LOGIN_VIEW = ADMIN_VIEW / "login/index.html"
INDEX_VIEW = ADMIN_VIEW / "index/index.html"
LAYOUT_VIEW = ADMIN_VIEW / "layout.html"
HOME_VIEW = ADMIN_VIEW / "index/home.html"
VERSION = "202606182530"
MARKER = "/* ===== Blin Admin 2026 product redesign ===== */"


def backup(path: Path, suffix: str) -> None:
    if not path.exists():
        return
    target = path.with_name(
        f"{path.name}.bak_{suffix}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    target.write_text(path.read_text(errors="ignore"), encoding="utf-8")
    print(f"BACKUP {target}")


def write_if_changed(path: Path, text: str, suffix: str) -> bool:
    current = path.read_text(errors="ignore")
    if current == text:
        return False
    backup(path, suffix)
    path.write_text(text, encoding="utf-8")
    print(f"UPDATED {path}")
    return True


def bump_css_versions() -> int:
    changed = 0
    pattern = re.compile(r"/static/css/modern-admin\.css\?v=\d+")
    for path in ADMIN_VIEW.rglob("*.html"):
        text = path.read_text(errors="ignore")
        next_text = pattern.sub(f"/static/css/modern-admin.css?v={VERSION}", text)
        if write_if_changed(path, next_text, "admin_ui_2026_cache"):
            changed += 1
    return changed


def patch_css() -> bool:
    source = MODERN_CSS.read_text(errors="ignore")
    source = re.sub(
        re.escape(MARKER) + r".*\Z",
        "",
        source,
        flags=re.S,
    ).rstrip()
    source += "\n\n" + ADMIN_2026_CSS.strip() + "\n"
    return write_if_changed(MODERN_CSS, source, "admin_ui_2026_css")


def patch_templates() -> int:
    changed = 0

    if LOGIN_VIEW.exists():
        text = LOGIN_VIEW.read_text(errors="ignore")
        next_text = text.replace(
            '<body class="center-vh" style="background-image: url(/static/images/login-bg-2.jpg); background-size: cover;">',
            '<body class="center-vh blin-admin-login">',
        )
        next_text = next_text.replace(
            """        <div class="text-center mb-3">
            <h2>后 台 登 录</h2>
        </div>""",
            """        <div class="text-center mb-4 blin-login-brand">
            <div class="blin-login-mark">IM</div>
            <h2>后台登录</h2>
        </div>""",
        )
        next_text = next_text.replace(
            "            <p>IM 运营管理控制台</p>\n",
            "",
        )
        if write_if_changed(LOGIN_VIEW, next_text, "admin_ui_2026_shell"):
            changed += 1

    if INDEX_VIEW.exists():
        text = INDEX_VIEW.read_text(errors="ignore")
        next_text = text.replace(
            '<body class="lyear-index">',
            '<body class="lyear-index blin-admin-shell">',
        )
        next_text = next_text.replace(
            "                menuName = data[i].pid == 0 ? '<span>' + data[i].name + '</span>' : data[i].name;",
            "                menuName = '<span class=\"blin-sidebar-menu-text\">' + data[i].name + '</span>';",
        )
        next_text = next_text.replace(
            '<a href="{$Request.root}">后台管理系统</a>',
            '<a href="{$Request.root}" class="blin-admin-logo"><span class="blin-admin-logo-mark">IM</span><span class="blin-admin-logo-text">管理后台</span></a>',
        )
        next_text = re.sub(
            r"\n\s*<div class=\"blin-admin-top-title\">.*?</div>\s*(?=\n\s*</div>\n\s*<ul class=\"navbar-right d-flex align-items-center\">)",
            "\n",
            next_text,
            flags=re.S,
        )
        next_text = re.sub(
            r"\n\s*<!--切换主题配色-->.*?(?=\n\s*<!--个人头像内容-->)",
            "\n",
            next_text,
            flags=re.S,
        )
        if write_if_changed(INDEX_VIEW, next_text, "admin_ui_2026_shell"):
            changed += 1

    if LAYOUT_VIEW.exists():
        text = LAYOUT_VIEW.read_text(errors="ignore")
        next_text = text.replace("<body>", '<body class="blin-admin-content">', 1)
        if write_if_changed(LAYOUT_VIEW, next_text, "admin_ui_2026_shell"):
            changed += 1

    if HOME_VIEW.exists():
        text = HOME_VIEW.read_text(errors="ignore")
        next_text = re.sub(
            r'\n<link rel="stylesheet" type="text/css" href="/static/js/jquery-confirm/jquery-confirm\.min\.css">\s*'
            r'<script type="text/javascript" src="/static/js/jquery-confirm/jquery-confirm\.min\.js"></script>',
            "",
            text,
            flags=re.S,
        )
        next_text = re.sub(
            r'\n<script>\s*var version = \$\("#version"\)\.html\(\);.*?</script>\s*(?=\{/block\})',
            "\n",
            next_text,
            flags=re.S,
        )
        if write_if_changed(HOME_VIEW, next_text, "admin_ui_2026_home"):
            changed += 1

    return changed


ADMIN_2026_CSS = r"""
/* ===== Blin Admin 2026 product redesign ===== */
:root {
  --blin-primary: #6366f1;
  --blin-primary-strong: #4f46e5;
  --blin-primary-soft: #eef2ff;
  --blin-success: #10b981;
  --blin-warning: #f59e0b;
  --blin-danger: #ef4444;
  --blin-page: #f8fafc;
  --blin-surface: #ffffff;
  --blin-surface-2: #f1f5f9;
  --blin-ink: #1e293b;
  --blin-body: #475569;
  --blin-muted: #64748b;
  --blin-subtle: #94a3b8;
  --blin-line: #e2e8f0;
  --blin-sidebar: #111827;
  --blin-sidebar-2: #0f172a;
  --blin-radius: 14px;
  --blin-radius-sm: 10px;
  --blin-shadow: 0 2px 8px rgba(15, 23, 42, .06);
  --blin-focus: 0 0 0 4px rgba(99, 102, 241, .16);
}

html,
body {
  color: var(--blin-ink) !important;
  background: var(--blin-page) !important;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC",
    "Microsoft YaHei", sans-serif !important;
  letter-spacing: 0 !important;
}

body:not(.center-vh) {
  padding: 0 !important;
  background: var(--blin-page) !important;
}

a {
  color: var(--blin-primary) !important;
  text-decoration: none !important;
}

a:hover {
  color: var(--blin-primary-strong) !important;
}

/* App shell */
body.lyear-index {
  background: var(--blin-page) !important;
}

.lyear-layout-web,
.lyear-layout-container,
.lyear-layout-content {
  background: var(--blin-page) !important;
}

body:not(.center-vh) .lyear-layout-web,
body:not(.center-vh) .lyear-layout-container {
  min-height: 100vh !important;
  padding: 0 !important;
}

.lyear-layout-sidebar {
  width: 250px !important;
  margin: 0 !important;
  background: var(--blin-sidebar) !important;
  border-right: 1px solid rgba(255, 255, 255, .08) !important;
  box-shadow: none !important;
}

body.lyear-index .lyear-layout-sidebar {
  left: 0 !important;
  top: 0 !important;
}

.sidebar-header {
  height: 68px !important;
  width: 100% !important;
  padding: 0 !important;
  background: var(--blin-sidebar) !important;
  border-bottom: 1px solid rgba(255, 255, 255, .08) !important;
}

#logo a {
  width: 100% !important;
  display: flex !important;
  align-items: center !important;
  gap: 10px !important;
  height: 68px !important;
  padding: 0 18px !important;
  color: #fff !important;
  font-size: 17px !important;
  font-weight: 700 !important;
  letter-spacing: 0 !important;
  line-height: 1 !important;
}

#logo a::before {
  display: none !important;
  content: none !important;
}

#logo a::after {
  display: none !important;
  content: none !important;
}

.lyear-layout-sidebar-info {
  padding: 12px !important;
}

.nav-drawer > li > a,
.nav-subnav > li > a {
  min-height: 42px !important;
  margin: 2px 0 !important;
  padding: 10px 12px !important;
  border: 0 !important;
  border-radius: 10px !important;
  color: #cbd5e1 !important;
  background: transparent !important;
  box-shadow: none !important;
  font-size: 14px !important;
  font-weight: 600 !important;
  letter-spacing: 0 !important;
  transform: none !important;
}

.nav-drawer > li > a i,
.nav-drawer > li > a .mdi {
  color: #94a3b8 !important;
  width: 20px !important;
  min-width: 20px !important;
  margin-right: 10px !important;
}

.nav-drawer > li > a:hover,
.nav-subnav > li > a:hover {
  color: #fff !important;
  background: rgba(255, 255, 255, .08) !important;
  transform: none !important;
}

.nav-drawer > li.active > a,
.nav-drawer > li.open > a,
.nav-drawer > li > a.active,
.nav-subnav > li.active > a,
.nav-subnav > li > a.active {
  color: #fff !important;
  background: var(--blin-primary) !important;
  border: 0 !important;
  box-shadow: none !important;
}

.nav-drawer > li.active > a i,
.nav-drawer > li.open > a i,
.nav-drawer > li > a.active i {
  color: #fff !important;
}

.nav-subnav {
  margin: 4px 0 8px !important;
  padding: 6px !important;
  border: 1px solid rgba(255, 255, 255, .07) !important;
  border-radius: 12px !important;
  background: rgba(15, 23, 42, .72) !important;
}

.nav-subnav > li > a {
  min-height: 36px !important;
  padding: 8px 12px 8px 34px !important;
  color: #cbd5e1 !important;
  font-size: 13px !important;
}

.sidebar-footer {
  border-top: 1px solid rgba(255, 255, 255, .08) !important;
  color: #94a3b8 !important;
}

.lyear-layout-header {
  background: var(--blin-surface) !important;
  border-bottom: 1px solid var(--blin-line) !important;
  box-shadow: none !important;
  backdrop-filter: none !important;
  -webkit-backdrop-filter: none !important;
}

.lyear-layout-header .navbar {
  min-height: 64px !important;
  padding: 0 20px !important;
}

.lyear-aside-toggler,
.icon-item,
.admin-profile-toggle {
  width: 38px !important;
  height: 38px !important;
  border: 1px solid var(--blin-line) !important;
  border-radius: 12px !important;
  color: var(--blin-body) !important;
  background: var(--blin-surface) !important;
  box-shadow: none !important;
}

.admin-profile-toggle {
  width: auto !important;
  gap: 8px !important;
  padding: 4px 12px 4px 4px !important;
}

.lyear-layout-content {
  padding: 14px !important;
}

#iframe-content,
.lyear-iframe {
  border: 1px solid var(--blin-line) !important;
  border-radius: 16px !important;
  background: var(--blin-page) !important;
  box-shadow: none !important;
}

.lyear-tabs,
.multitabs .nav-tabs,
.lyear-tabs .nav-tabs {
  background: var(--blin-surface) !important;
  border-bottom: 1px solid var(--blin-line) !important;
}

.multitabs .nav-tabs .nav-link,
.lyear-tabs .nav-tabs .nav-link {
  border: 1px solid var(--blin-line) !important;
  border-radius: 10px !important;
  background: var(--blin-surface) !important;
  color: var(--blin-muted) !important;
  box-shadow: none !important;
}

.multitabs .nav-tabs .nav-link.active,
.lyear-tabs .nav-tabs .nav-link.active {
  color: var(--blin-primary) !important;
  background: var(--blin-primary-soft) !important;
  border-color: rgba(99, 102, 241, .28) !important;
}

/* Surfaces */
.container-fluid {
  max-width: 1520px !important;
}

.card,
.modal-content,
.jconfirm-box,
.dropdown-menu {
  color: var(--blin-ink) !important;
  background: var(--blin-surface) !important;
  border: 1px solid var(--blin-line) !important;
  border-radius: var(--blin-radius) !important;
  box-shadow: var(--blin-shadow) !important;
  overflow: hidden !important;
}

.card {
  margin-bottom: 18px !important;
}

.card-header {
  min-height: 54px !important;
  padding: 15px 18px !important;
  background: var(--blin-surface) !important;
  border-bottom: 1px solid var(--blin-line) !important;
}

.card-title,
.card-header .card-title {
  margin: 0 !important;
  color: var(--blin-ink) !important;
  font-size: 16px !important;
  font-weight: 700 !important;
  letter-spacing: 0 !important;
}

.card-title::before,
.admin-app-edit .card-title::before {
  display: none !important;
}

.card-body {
  padding: 18px !important;
}

.bg-primary,
.bg-danger,
.bg-success,
.bg-purple,
.bg-info,
.bg-warning {
  color: #fff !important;
  border: 0 !important;
  background-image: none !important;
}

.bg-primary { background-color: var(--blin-primary) !important; }
.bg-success { background-color: var(--blin-success) !important; }
.bg-danger { background-color: var(--blin-danger) !important; }
.bg-warning { background-color: var(--blin-warning) !important; }
.bg-info { background-color: #0ea5e9 !important; }
.bg-purple { background-color: #8b5cf6 !important; }
.bg-primary::after,
.bg-danger::after,
.bg-success::after,
.bg-purple::after,
.bg-info::after,
.bg-warning::after {
  display: none !important;
}

/* Forms */
label,
.form-label {
  margin-bottom: 7px !important;
  color: var(--blin-ink) !important;
  font-size: 13px !important;
  font-weight: 700 !important;
}

.form-control,
.form-select,
.bootstrap-select > .dropdown-toggle,
input[type="text"],
input[type="number"],
input[type="password"],
input[type="email"],
input[type="search"],
input[type="url"],
input[type="tel"],
input[type="date"],
input[type="datetime-local"],
input[type="time"],
select,
textarea {
  min-height: 40px !important;
  color: var(--blin-ink) !important;
  background: var(--blin-surface) !important;
  border: 1px solid var(--blin-line) !important;
  border-radius: 10px !important;
  box-shadow: none !important;
}

textarea.form-control,
textarea {
  min-height: 96px !important;
}

.form-control:focus,
.form-select:focus,
.bootstrap-select > .dropdown-toggle:focus,
input[type="text"]:focus,
input[type="number"]:focus,
input[type="password"]:focus,
input[type="email"]:focus,
input[type="search"]:focus,
input[type="url"]:focus,
input[type="tel"]:focus,
input[type="date"]:focus,
input[type="datetime-local"]:focus,
input[type="time"]:focus,
select:focus,
textarea:focus {
  border-color: var(--blin-primary) !important;
  box-shadow: var(--blin-focus) !important;
  outline: none !important;
}

.form-control::placeholder,
input[type="text"]::placeholder,
input[type="number"]::placeholder,
input[type="password"]::placeholder,
input[type="email"]::placeholder,
input[type="search"]::placeholder,
input[type="url"]::placeholder,
input[type="tel"]::placeholder,
textarea::placeholder {
  color: #6b7280 !important;
  opacity: 1 !important;
}

small,
.form-text,
.text-muted {
  color: var(--blin-muted) !important;
  line-height: 1.55 !important;
}

.input-group-text,
.input-group-addon,
.input-group-append .btn,
.input-group-btn .btn {
  min-height: 40px !important;
  border-color: var(--blin-line) !important;
  background: var(--blin-surface-2) !important;
  color: var(--blin-body) !important;
  box-shadow: none !important;
}

/* Buttons */
.btn {
  min-height: 38px !important;
  display: inline-flex !important;
  align-items: center !important;
  justify-content: center !important;
  gap: 6px !important;
  border-radius: 10px !important;
  border: 1px solid transparent !important;
  box-shadow: none !important;
  font-size: 13px !important;
  font-weight: 700 !important;
  letter-spacing: 0 !important;
  transform: none !important;
  transition: background-color .16s ease, border-color .16s ease, color .16s ease !important;
}

.btn:hover,
.btn:focus {
  transform: none !important;
  box-shadow: none !important;
}

.btn-primary,
body:not(.center-vh) .btn-primary {
  color: #fff !important;
  background: var(--blin-primary) !important;
  border-color: var(--blin-primary) !important;
}

.btn-primary:hover {
  background: var(--blin-primary-strong) !important;
}

.btn-success,
body:not(.center-vh) .btn-success {
  color: #fff !important;
  background: var(--blin-success) !important;
  border-color: var(--blin-success) !important;
}

.btn-danger,
body:not(.center-vh) .btn-danger {
  color: #fff !important;
  background: var(--blin-danger) !important;
  border-color: var(--blin-danger) !important;
}

.btn-info,
body:not(.center-vh) .btn-info {
  color: #fff !important;
  background: #0ea5e9 !important;
  border-color: #0ea5e9 !important;
}

.btn-warning,
body:not(.center-vh) .btn-warning {
  color: #78350f !important;
  background: #fef3c7 !important;
  border-color: #fde68a !important;
}

.btn-secondary,
.btn-default,
.btn-light,
body:not(.center-vh) .btn-secondary:not(.dropdown-toggle),
body:not(.center-vh) .btn-default,
body:not(.center-vh) .btn-light {
  color: var(--blin-body) !important;
  background: var(--blin-surface) !important;
  border-color: var(--blin-line) !important;
}

.btn-label label {
  width: 24px !important;
  height: 24px !important;
  margin: -2px 0 -2px -4px !important;
  color: currentColor !important;
  background: rgba(255, 255, 255, .18) !important;
  border-radius: 8px !important;
}

.toolbar-btn-action {
  display: flex !important;
  flex-wrap: wrap !important;
  gap: 8px !important;
  align-items: center !important;
  padding: 12px !important;
  margin-bottom: 14px !important;
  background: var(--blin-surface-2) !important;
  border: 1px solid var(--blin-line) !important;
  border-radius: 12px !important;
}

/* Tables */
.bootstrap-table .fixed-table-container,
.table-responsive {
  border: 1px solid var(--blin-line) !important;
  border-radius: 12px !important;
  overflow: hidden !important;
  background: var(--blin-surface) !important;
}

.table,
.bootstrap-table table {
  margin-bottom: 0 !important;
  color: var(--blin-ink) !important;
}

.table thead th,
.bootstrap-table table thead th {
  color: var(--blin-body) !important;
  background: #f8fafc !important;
  border-bottom: 1px solid var(--blin-line) !important;
  font-size: 12px !important;
  font-weight: 700 !important;
}

.table td,
.table th,
.bootstrap-table table td,
.bootstrap-table table th {
  border-color: var(--blin-line) !important;
  vertical-align: middle !important;
}

.bootstrap-table table tbody tr,
.table tbody tr {
  background: var(--blin-surface) !important;
}

.bootstrap-table table tbody tr:hover,
.table tbody tr:hover {
  background: #f8fafc !important;
}

.bootstrap-table table td {
  max-width: 440px;
  white-space: normal !important;
  word-break: break-word !important;
}

.fixed-table-toolbar {
  margin-bottom: 12px !important;
}

.fixed-table-toolbar .search input {
  border-radius: 10px !important;
}

.fixed-table-toolbar .btn,
.bootstrap-table .btn,
.fixed-table-toolbar .dropdown-toggle {
  min-height: 36px !important;
}

.fixed-table-pagination,
.pagination-detail,
.pagination-info,
.page-list {
  color: var(--blin-muted) !important;
}

.pagination .page-link {
  color: var(--blin-body) !important;
  background: var(--blin-surface) !important;
  border-color: var(--blin-line) !important;
}

.pagination .active .page-link {
  color: #fff !important;
  background: var(--blin-primary) !important;
  border-color: var(--blin-primary) !important;
}

/* Badges and states */
.badge {
  border-radius: 999px !important;
  font-weight: 700 !important;
  letter-spacing: 0 !important;
}

.badge-outline-primary {
  color: #3730a3 !important;
  background: #eef2ff !important;
  border: 1px solid #c7d2fe !important;
}

.badge-outline-success {
  color: #047857 !important;
  background: #ecfdf5 !important;
  border: 1px solid #a7f3d0 !important;
}

.badge-outline-info {
  color: #0369a1 !important;
  background: #f0f9ff !important;
  border: 1px solid #bae6fd !important;
}

.badge-outline-warning {
  color: #92400e !important;
  background: #fffbeb !important;
  border: 1px solid #fde68a !important;
}

.badge-outline-dark,
.bg-light.text-dark {
  color: var(--blin-body) !important;
  background: var(--blin-surface-2) !important;
  border: 1px solid var(--blin-line) !important;
}

/* Segmented switches */
.blin-setting-row {
  display: flex !important;
  align-items: center !important;
  justify-content: space-between !important;
  gap: 16px !important;
  padding: 14px !important;
  margin-bottom: 14px !important;
  color: var(--blin-ink) !important;
  background: var(--blin-surface-2) !important;
  border: 1px solid var(--blin-line) !important;
  border-radius: 12px !important;
}

.blin-setting-copy {
  min-width: 0 !important;
}

.blin-setting-title {
  color: var(--blin-ink) !important;
  font-size: 14px !important;
  font-weight: 700 !important;
}

.blin-setting-desc {
  color: var(--blin-muted) !important;
  font-size: 12px !important;
}

.blin-segmented-switch {
  display: inline-flex !important;
  flex: 0 0 auto !important;
  align-items: center !important;
  gap: 3px !important;
  padding: 3px !important;
  background: var(--blin-surface) !important;
  border: 1px solid var(--blin-line) !important;
  border-radius: 999px !important;
  box-shadow: none !important;
}

.blin-segmented-switch .btn-check {
  position: absolute !important;
  clip: rect(0, 0, 0, 0) !important;
  pointer-events: none !important;
}

.blin-switch-choice {
  min-width: 70px !important;
  min-height: 32px !important;
  display: inline-flex !important;
  align-items: center !important;
  justify-content: center !important;
  gap: 5px !important;
  padding: 0 12px !important;
  border-radius: 999px !important;
  color: var(--blin-muted) !important;
  background: transparent !important;
  font-size: 13px !important;
  font-weight: 700 !important;
  cursor: pointer !important;
}

.blin-segmented-switch .btn-check:checked + .blin-switch-choice-on {
  color: #fff !important;
  background: var(--blin-primary) !important;
}

.blin-segmented-switch .btn-check:checked + .blin-switch-choice-off {
  color: #fff !important;
  background: var(--blin-body) !important;
}

/* Login */
body.center-vh {
  min-height: 100vh !important;
  display: flex !important;
  align-items: center !important;
  justify-content: center !important;
  background: #0f172a !important;
  background-image: none !important;
  overflow: auto !important;
}

body.center-vh::before {
  content: "" !important;
  position: fixed !important;
  inset: 0 !important;
  background:
    linear-gradient(90deg, rgba(255, 255, 255, .04) 1px, transparent 1px),
    linear-gradient(rgba(255, 255, 255, .04) 1px, transparent 1px) !important;
  background-size: 40px 40px !important;
  mask-image: none !important;
  pointer-events: none !important;
}

body.center-vh .card {
  width: min(420px, calc(100vw - 32px)) !important;
  padding: 30px !important;
  background: var(--blin-surface) !important;
  border: 1px solid rgba(255, 255, 255, .14) !important;
  border-radius: 16px !important;
  box-shadow: 0 24px 60px rgba(0, 0, 0, .28) !important;
  backdrop-filter: none !important;
}

body.center-vh h2 {
  color: var(--blin-ink) !important;
  margin-bottom: 18px !important;
  font-size: 22px !important;
  font-weight: 800 !important;
  letter-spacing: 0 !important;
}

body.center-vh h2::before {
  content: "" !important;
  width: 46px !important;
  height: 46px !important;
  display: block !important;
  margin: 0 auto 14px !important;
  border-radius: 14px !important;
  background: var(--blin-primary) !important;
  box-shadow: none !important;
}

.signin-form .has-feedback .mdi {
  width: 42px !important;
  height: 42px !important;
  line-height: 42px !important;
  color: var(--blin-muted) !important;
}

.signin-form .has-feedback .form-control {
  min-height: 42px !important;
  padding-left: 42px !important;
}

body.center-vh .btn-primary {
  width: 100% !important;
  min-height: 44px !important;
}

/* Modals and dropdowns */
.modal-header,
.modal-footer {
  border-color: var(--blin-line) !important;
}

.modal-title {
  color: var(--blin-ink) !important;
  font-weight: 700 !important;
}

.dropdown-menu {
  padding: 8px !important;
}

.dropdown-item {
  border-radius: 8px !important;
  color: var(--blin-body) !important;
  font-weight: 600 !important;
}

.dropdown-item:hover {
  color: var(--blin-primary) !important;
  background: var(--blin-primary-soft) !important;
}

/* Admin profile cards */
.admin-user-summary,
.user-summary,
.d-flex[style*="align-items: center"] {
  gap: 16px !important;
  align-items: center !important;
}

.rounded-circle {
  object-fit: cover !important;
  border: 1px solid var(--blin-line) !important;
}

/* Responsive */
@media (max-width: 992px) {
  body:not(.center-vh) {
    padding: 10px !important;
  }

  .lyear-layout-content {
    padding: 10px !important;
  }

  .card-body {
    padding: 14px !important;
  }

  .toolbar-btn-action {
    padding: 10px !important;
  }

  .blin-setting-row {
    align-items: flex-start !important;
    flex-direction: column !important;
  }

  .blin-segmented-switch {
    width: 100% !important;
  }

  .blin-switch-choice {
    flex: 1 1 0 !important;
  }
}

@media (prefers-reduced-motion: reduce) {
  *,
  *::before,
  *::after {
    transition-duration: .01ms !important;
    animation-duration: .01ms !important;
    animation-iteration-count: 1 !important;
    scroll-behavior: auto !important;
  }
}

/* ===== Blin Admin 2026 complete rebuild hardening ===== */
:root {
  --admin-bg: #f5f7fb;
  --admin-shell: #101827;
  --admin-shell-2: #172033;
  --admin-surface: #ffffff;
  --admin-panel: #f8fafc;
  --admin-line: #d8e0ec;
  --admin-line-strong: #c5d0df;
  --admin-ink: #0f172a;
  --admin-text: #1f2937;
  --admin-muted: #334155;
  --admin-subtle: #475569;
  --admin-primary: #4f46e5;
  --admin-primary-hover: #4338ca;
  --admin-primary-soft: #eef2ff;
  --admin-success: #059669;
  --admin-success-soft: #d1fae5;
  --admin-warning: #b45309;
  --admin-warning-soft: #fef3c7;
  --admin-danger: #dc2626;
  --admin-danger-soft: #fee2e2;
  --admin-info: #0369a1;
  --admin-info-soft: #e0f2fe;
  --admin-radius: 12px;
  --admin-radius-lg: 16px;
  --admin-shadow: 0 10px 28px rgba(15, 23, 42, .08);
  --admin-shadow-soft: 0 2px 8px rgba(15, 23, 42, .06);
}

html,
body {
  color-scheme: light !important;
  text-rendering: optimizeLegibility !important;
}

body:not(.center-vh) {
  min-height: 100vh !important;
  background: var(--admin-bg) !important;
  background-image: none !important;
  color: var(--admin-text) !important;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif !important;
  letter-spacing: 0 !important;
}

body:not(.center-vh),
body:not(.center-vh) p,
body:not(.center-vh) li,
body:not(.center-vh) td,
body:not(.center-vh) th,
body:not(.center-vh) label,
body:not(.center-vh) .control-label,
body:not(.center-vh) .form-check-label,
body:not(.center-vh) .checkbox label,
body:not(.center-vh) .radio label,
body:not(.center-vh) .help-block,
body:not(.center-vh) .form-text,
body:not(.center-vh) .bootstrap-table,
body:not(.center-vh) .fixed-table-container,
body:not(.center-vh) .fixed-table-body,
body:not(.center-vh) .treeview,
body:not(.center-vh) .jstree,
body:not(.center-vh) .dd-handle {
  color: var(--admin-text) !important;
}

body:not(.center-vh) .text-muted,
body:not(.center-vh) .text-secondary,
body:not(.center-vh) .small,
body:not(.center-vh) small,
body:not(.center-vh) .help-block,
body:not(.center-vh) .form-text,
body:not(.center-vh) .description,
body:not(.center-vh) .desc,
body:not(.center-vh) .hint,
body:not(.center-vh) .layui-layer-content small {
  color: var(--admin-muted) !important;
}

body:not(.center-vh) a:not(.btn):not(.nav-link):not(.dropdown-item):not(.page-link) {
  color: #3730a3 !important;
  text-decoration: none !important;
}

body:not(.center-vh) a:not(.btn):not(.nav-link):not(.dropdown-item):not(.page-link):hover {
  color: var(--admin-primary) !important;
}

body:not(.center-vh) h1,
body:not(.center-vh) h2,
body:not(.center-vh) h3,
body:not(.center-vh) h4,
body:not(.center-vh) h5,
body:not(.center-vh) h6,
body:not(.center-vh) .card-title,
body:not(.center-vh) .modal-title,
body:not(.center-vh) .page-title,
body:not(.center-vh) .content-title {
  color: var(--admin-ink) !important;
  font-weight: 800 !important;
  letter-spacing: 0 !important;
}

body:not(.center-vh) .lyear-layout-web,
body:not(.center-vh) .lyear-layout-content,
body:not(.center-vh) .container-fluid,
body:not(.center-vh) .content {
  background: var(--admin-bg) !important;
  color: var(--admin-text) !important;
}

body:not(.center-vh) .lyear-layout-sidebar,
body:not(.center-vh) .sidebar-main,
body:not(.center-vh) .lyear-sidebar,
body:not(.center-vh) .sidebar-header {
  background: var(--admin-shell) !important;
  background-image: none !important;
  color: #e5e7eb !important;
  border-color: rgba(255, 255, 255, .08) !important;
  box-shadow: none !important;
}

body:not(.center-vh) .lyear-layout-header,
body:not(.center-vh) .topbar,
body:not(.center-vh) .navbar,
body:not(.center-vh) .header {
  background: var(--admin-surface) !important;
  background-image: none !important;
  color: var(--admin-ink) !important;
  border-color: var(--admin-line) !important;
  box-shadow: 0 1px 0 rgba(15, 23, 42, .08) !important;
}

body:not(.center-vh) .lyear-layout-header a,
body:not(.center-vh) .topbar a,
body:not(.center-vh) .navbar a {
  color: var(--admin-text) !important;
}

body:not(.center-vh) .nav-item > a,
body:not(.center-vh) .sidebar-main a,
body:not(.center-vh) .lyear-sidebar a,
body:not(.center-vh) .nav-drawer a {
  color: #cbd5e1 !important;
  font-weight: 650 !important;
}

body:not(.center-vh) .sidebar-main a:hover,
body:not(.center-vh) .lyear-sidebar a:hover,
body:not(.center-vh) .nav-drawer a:hover,
body:not(.center-vh) .nav-drawer .active > a,
body:not(.center-vh) .nav-drawer li.active > a {
  background: rgba(99, 102, 241, .16) !important;
  color: #ffffff !important;
}

body:not(.center-vh) .nav-drawer i,
body:not(.center-vh) .sidebar-main i,
body:not(.center-vh) .lyear-sidebar i {
  color: #a5b4fc !important;
}

body:not(.center-vh) .card,
body:not(.center-vh) .panel,
body:not(.center-vh) .box,
body:not(.center-vh) .modal-content,
body:not(.center-vh) .jconfirm-box,
body:not(.center-vh) .layui-layer,
body:not(.center-vh) .dropdown-menu,
body:not(.center-vh) .popover,
body:not(.center-vh) .bootstrap-select .dropdown-menu,
body:not(.center-vh) .fixed-table-container {
  background: var(--admin-surface) !important;
  background-image: none !important;
  color: var(--admin-text) !important;
  border: 1px solid var(--admin-line) !important;
  border-radius: var(--admin-radius) !important;
  box-shadow: var(--admin-shadow-soft) !important;
  backdrop-filter: none !important;
}

body:not(.center-vh) .card-header,
body:not(.center-vh) .panel-heading,
body:not(.center-vh) .modal-header,
body:not(.center-vh) .modal-footer,
body:not(.center-vh) .layui-layer-title {
  background: var(--admin-panel) !important;
  background-image: none !important;
  color: var(--admin-ink) !important;
  border-color: var(--admin-line) !important;
}

body:not(.center-vh) .card-body,
body:not(.center-vh) .panel-body,
body:not(.center-vh) .modal-body,
body:not(.center-vh) .layui-layer-content,
body:not(.center-vh) .jconfirm-content,
body:not(.center-vh) .jconfirm-title {
  color: var(--admin-text) !important;
}

body:not(.center-vh) .table,
body:not(.center-vh) table,
body:not(.center-vh) .table td,
body:not(.center-vh) .table th,
body:not(.center-vh) .bootstrap-table td,
body:not(.center-vh) .bootstrap-table th {
  color: var(--admin-text) !important;
  border-color: var(--admin-line) !important;
}

body:not(.center-vh) .table thead th,
body:not(.center-vh) .bootstrap-table thead th,
body:not(.center-vh) .fixed-table-header th {
  background: #eef2ff !important;
  background-image: none !important;
  color: var(--admin-ink) !important;
  border-bottom: 1px solid var(--admin-line-strong) !important;
  font-size: 13px !important;
  font-weight: 800 !important;
}

body:not(.center-vh) .table tbody tr,
body:not(.center-vh) .bootstrap-table tbody tr {
  background: var(--admin-surface) !important;
}

body:not(.center-vh) .table-hover tbody tr:hover,
body:not(.center-vh) .bootstrap-table tbody tr:hover,
body:not(.center-vh) .table-striped tbody tr:nth-of-type(odd):hover {
  background: #f1f5ff !important;
}

body:not(.center-vh) .table-striped tbody tr:nth-of-type(odd),
body:not(.center-vh) .bootstrap-table .table-striped tbody tr:nth-of-type(odd) {
  background: #fbfcff !important;
}

body:not(.center-vh) .table span:not(.badge):not(.label):not(.mdi):not([class*="switch"]),
body:not(.center-vh) .bootstrap-table span:not(.badge):not(.label):not(.mdi):not([class*="switch"]) {
  color: var(--admin-text) !important;
}

body:not(.center-vh) .fixed-table-pagination,
body:not(.center-vh) .fixed-table-toolbar,
body:not(.center-vh) .pagination-detail,
body:not(.center-vh) .page-list,
body:not(.center-vh) .columns,
body:not(.center-vh) .search {
  color: var(--admin-text) !important;
}

body:not(.center-vh) .form-control,
body:not(.center-vh) .form-select,
body:not(.center-vh) select,
body:not(.center-vh) textarea,
body:not(.center-vh) input[type="text"],
body:not(.center-vh) input[type="number"],
body:not(.center-vh) input[type="password"],
body:not(.center-vh) input[type="email"],
body:not(.center-vh) input[type="search"],
body:not(.center-vh) input[type="url"],
body:not(.center-vh) .bootstrap-select > .dropdown-toggle,
body:not(.center-vh) .select2-selection,
body:not(.center-vh) .chosen-container-single .chosen-single {
  background: #ffffff !important;
  background-image: none !important;
  color: var(--admin-ink) !important;
  border: 1px solid var(--admin-line-strong) !important;
  border-radius: 10px !important;
  box-shadow: none !important;
}

body:not(.center-vh) .form-control:focus,
body:not(.center-vh) .form-select:focus,
body:not(.center-vh) select:focus,
body:not(.center-vh) textarea:focus,
body:not(.center-vh) input:focus,
body:not(.center-vh) .bootstrap-select > .dropdown-toggle:focus {
  border-color: var(--admin-primary) !important;
  box-shadow: 0 0 0 3px rgba(79, 70, 229, .14) !important;
  outline: none !important;
}

body:not(.center-vh) ::placeholder {
  color: var(--admin-subtle) !important;
  opacity: 1 !important;
}

body:not(.center-vh) .input-group-text,
body:not(.center-vh) .input-group-addon {
  background: var(--admin-panel) !important;
  color: var(--admin-muted) !important;
  border-color: var(--admin-line-strong) !important;
  font-weight: 700 !important;
}

body:not(.center-vh) .dropdown-menu,
body:not(.center-vh) .dropdown-menu *,
body:not(.center-vh) .bootstrap-select .dropdown-menu,
body:not(.center-vh) .bootstrap-select .dropdown-menu *,
body:not(.center-vh) .select2-dropdown,
body:not(.center-vh) .select2-results__option {
  color: var(--admin-text) !important;
}

body:not(.center-vh) .dropdown-item,
body:not(.center-vh) .dropdown-menu > li > a,
body:not(.center-vh) .bootstrap-select .dropdown-menu li a,
body:not(.center-vh) .select2-results__option {
  background: transparent !important;
  color: var(--admin-text) !important;
  border-radius: 8px !important;
  font-weight: 650 !important;
}

body:not(.center-vh) .dropdown-item:hover,
body:not(.center-vh) .dropdown-menu > li > a:hover,
body:not(.center-vh) .bootstrap-select .dropdown-menu li a:hover,
body:not(.center-vh) .select2-results__option--highlighted {
  background: var(--admin-primary-soft) !important;
  color: #312e81 !important;
}

body:not(.center-vh) .btn {
  min-height: 34px !important;
  border-radius: 10px !important;
  border: 1px solid transparent !important;
  box-shadow: none !important;
  font-weight: 750 !important;
  letter-spacing: 0 !important;
  text-shadow: none !important;
}

body:not(.center-vh) .btn-primary,
body:not(.center-vh) .btn-purple,
body:not(.center-vh) .btn-indigo {
  background: var(--admin-primary) !important;
  background-image: none !important;
  border-color: var(--admin-primary) !important;
  color: #ffffff !important;
}

body:not(.center-vh) .btn-primary:hover,
body:not(.center-vh) .btn-purple:hover,
body:not(.center-vh) .btn-indigo:hover {
  background: var(--admin-primary-hover) !important;
  border-color: var(--admin-primary-hover) !important;
  color: #ffffff !important;
}

body:not(.center-vh) .btn-default,
body:not(.center-vh) .btn-light,
body:not(.center-vh) .btn-secondary,
body:not(.center-vh) .btn-outline-secondary,
body:not(.center-vh) .btn-outline-default {
  background: #ffffff !important;
  background-image: none !important;
  color: var(--admin-text) !important;
  border-color: var(--admin-line-strong) !important;
}

body:not(.center-vh) .btn-default:hover,
body:not(.center-vh) .btn-light:hover,
body:not(.center-vh) .btn-secondary:hover,
body:not(.center-vh) .btn-outline-secondary:hover,
body:not(.center-vh) .btn-outline-default:hover {
  background: var(--admin-panel) !important;
  color: var(--admin-ink) !important;
}

body:not(.center-vh) .btn-success {
  background: var(--admin-success) !important;
  border-color: var(--admin-success) !important;
  color: #ffffff !important;
}

body:not(.center-vh) .btn-warning {
  background: #f59e0b !important;
  border-color: #f59e0b !important;
  color: #111827 !important;
}

body:not(.center-vh) .btn-danger {
  background: var(--admin-danger) !important;
  border-color: var(--admin-danger) !important;
  color: #ffffff !important;
}

body:not(.center-vh) .btn-info {
  background: var(--admin-info) !important;
  border-color: var(--admin-info) !important;
  color: #ffffff !important;
}

body:not(.center-vh) .btn-link {
  color: #3730a3 !important;
  background: transparent !important;
  border-color: transparent !important;
}

body:not(.center-vh) .badge,
body:not(.center-vh) .label {
  border-radius: 999px !important;
  border: 1px solid transparent !important;
  font-weight: 800 !important;
  letter-spacing: 0 !important;
  text-shadow: none !important;
}

body:not(.center-vh) .badge-primary,
body:not(.center-vh) .label-primary,
body:not(.center-vh) .bg-primary {
  background: var(--admin-primary-soft) !important;
  color: #312e81 !important;
  border-color: #c7d2fe !important;
}

body:not(.center-vh) .badge-success,
body:not(.center-vh) .label-success,
body:not(.center-vh) .bg-success {
  background: var(--admin-success-soft) !important;
  color: #065f46 !important;
  border-color: #a7f3d0 !important;
}

body:not(.center-vh) .badge-warning,
body:not(.center-vh) .label-warning,
body:not(.center-vh) .bg-warning {
  background: var(--admin-warning-soft) !important;
  color: #78350f !important;
  border-color: #fde68a !important;
}

body:not(.center-vh) .badge-danger,
body:not(.center-vh) .label-danger,
body:not(.center-vh) .bg-danger {
  background: var(--admin-danger-soft) !important;
  color: #991b1b !important;
  border-color: #fecaca !important;
}

body:not(.center-vh) .badge-info,
body:not(.center-vh) .label-info,
body:not(.center-vh) .bg-info {
  background: var(--admin-info-soft) !important;
  color: #075985 !important;
  border-color: #bae6fd !important;
}

body:not(.center-vh) .badge-light,
body:not(.center-vh) .label-light,
body:not(.center-vh) .bg-light,
body:not(.center-vh) .bg-white {
  background: #ffffff !important;
  color: var(--admin-text) !important;
  border-color: var(--admin-line-strong) !important;
}

body:not(.center-vh) .alert {
  border-radius: var(--admin-radius) !important;
  border: 1px solid var(--admin-line) !important;
  color: var(--admin-text) !important;
  background-image: none !important;
}

body:not(.center-vh) .alert-info {
  background: var(--admin-info-soft) !important;
  color: #075985 !important;
  border-color: #bae6fd !important;
}

body:not(.center-vh) .alert-success {
  background: var(--admin-success-soft) !important;
  color: #065f46 !important;
  border-color: #a7f3d0 !important;
}

body:not(.center-vh) .alert-warning {
  background: var(--admin-warning-soft) !important;
  color: #78350f !important;
  border-color: #fde68a !important;
}

body:not(.center-vh) .alert-danger {
  background: var(--admin-danger-soft) !important;
  color: #991b1b !important;
  border-color: #fecaca !important;
}

body:not(.center-vh) .page-link,
body:not(.center-vh) .pagination > li > a,
body:not(.center-vh) .pagination > li > span {
  background: #ffffff !important;
  color: var(--admin-text) !important;
  border-color: var(--admin-line-strong) !important;
}

body:not(.center-vh) .page-item.active .page-link,
body:not(.center-vh) .pagination > .active > a,
body:not(.center-vh) .pagination > .active > span {
  background: var(--admin-primary) !important;
  color: #ffffff !important;
  border-color: var(--admin-primary) !important;
}

body:not(.center-vh) .nav-tabs,
body:not(.center-vh) .nav-pills {
  border-color: var(--admin-line) !important;
}

body:not(.center-vh) .nav-tabs .nav-link,
body:not(.center-vh) .nav-pills .nav-link,
body:not(.center-vh) .nav-tabs > li > a,
body:not(.center-vh) .nav-pills > li > a {
  color: var(--admin-muted) !important;
  border-radius: 10px !important;
  font-weight: 750 !important;
}

body:not(.center-vh) .nav-tabs .nav-link.active,
body:not(.center-vh) .nav-pills .nav-link.active,
body:not(.center-vh) .nav-tabs > li.active > a,
body:not(.center-vh) .nav-pills > li.active > a {
  background: var(--admin-primary-soft) !important;
  color: #312e81 !important;
  border-color: #c7d2fe !important;
}

body:not(.center-vh) .lyear-skin-title,
body:not(.center-vh) .lyear-skin-title p,
body:not(.center-vh) .lyear-skin-li,
body:not(.center-vh) .lyear-skin-li label,
body:not(.center-vh) .form-material .form-control,
body:not(.center-vh) .material-control,
body:not(.center-vh) .list-group-item,
body:not(.center-vh) .timeline,
body:not(.center-vh) .timeline *:not(.badge):not(.btn):not(i) {
  color: var(--admin-text) !important;
}

body:not(.center-vh) .switch,
body:not(.center-vh) .switch *,
body:not(.center-vh) .custom-control,
body:not(.center-vh) .custom-control-label,
body:not(.center-vh) .form-check,
body:not(.center-vh) .form-check * {
  color: var(--admin-text) !important;
}

body:not(.center-vh) .progress {
  background: #e2e8f0 !important;
  border-radius: 999px !important;
}

body:not(.center-vh) .progress-bar {
  background: var(--admin-primary) !important;
  color: #ffffff !important;
}

body:not(.center-vh) .bg-primary.text-white,
body:not(.center-vh) .bg-success.text-white,
body:not(.center-vh) .bg-danger.text-white,
body:not(.center-vh) .bg-info.text-white,
body:not(.center-vh) .btn-primary *,
body:not(.center-vh) .btn-success *,
body:not(.center-vh) .btn-danger *,
body:not(.center-vh) .btn-info * {
  color: inherit !important;
}

body.center-vh {
  background: #f5f7fb !important;
  background-image: none !important;
  color: var(--admin-text) !important;
}

body.center-vh::before {
  display: none !important;
}

body.center-vh .card {
  background: #ffffff !important;
  color: var(--admin-text) !important;
  border: 1px solid var(--admin-line) !important;
  box-shadow: 0 24px 60px rgba(15, 23, 42, .14) !important;
}

body.center-vh h1,
body.center-vh h2,
body.center-vh h3,
body.center-vh p,
body.center-vh label,
body.center-vh small,
body.center-vh .form-check-label,
body.center-vh .help-block {
  color: var(--admin-text) !important;
}

body.center-vh .form-control,
body.center-vh input {
  background: #ffffff !important;
  color: var(--admin-ink) !important;
  border: 1px solid var(--admin-line-strong) !important;
  border-radius: 10px !important;
}

body.center-vh ::placeholder {
  color: var(--admin-subtle) !important;
  opacity: 1 !important;
}

body.center-vh .btn-primary {
  background: var(--admin-primary) !important;
  border-color: var(--admin-primary) !important;
  color: #ffffff !important;
}

/* Shell and login templates rebuilt on top of the existing backend routes. */
body.blin-admin-shell .lyear-layout-web,
body.blin-admin-shell .lyear-layout-container {
  background: var(--admin-bg) !important;
}

body.blin-admin-shell .sidebar-header {
  min-height: 72px !important;
  padding: 0 18px !important;
  display: flex !important;
  align-items: center !important;
  background: var(--admin-shell) !important;
  border-bottom: 1px solid rgba(255, 255, 255, .08) !important;
}

body.blin-admin-shell #logo a.blin-admin-logo {
  width: 100% !important;
  height: auto !important;
  margin: 0 !important;
  display: inline-flex !important;
  align-items: center !important;
  gap: 10px !important;
  color: #ffffff !important;
  font-size: 16px !important;
  line-height: 1 !important;
  letter-spacing: 0 !important;
  overflow: visible !important;
  text-decoration: none !important;
}

body.blin-admin-shell #logo a.blin-admin-logo::before,
body.blin-admin-shell #logo a.blin-admin-logo::after,
body.blin-admin-login .blin-login-mark::before,
body.blin-admin-login .blin-login-mark::after {
  display: none !important;
  content: none !important;
}

.blin-admin-logo-mark,
.blin-login-mark {
  width: 38px !important;
  height: 38px !important;
  display: inline-flex !important;
  align-items: center !important;
  justify-content: center !important;
  flex: 0 0 auto !important;
  border-radius: 12px !important;
  background: var(--admin-primary) !important;
  color: #ffffff !important;
  font-size: 14px !important;
  font-weight: 900 !important;
  letter-spacing: 0 !important;
  box-shadow: none !important;
}

.blin-admin-logo-text {
  color: #ffffff !important;
  font-size: 16px !important;
  font-weight: 850 !important;
  line-height: 1 !important;
}

body.blin-admin-shell .lyear-layout-sidebar-close .lyear-layout-sidebar:hover #logo a.blin-admin-logo,
body.blin-admin-shell .lyear-layout-sidebar.lyear-aside-open #logo a.blin-admin-logo {
  width: 100% !important;
  height: auto !important;
  margin: 0 !important;
  letter-spacing: 0 !important;
}

body.blin-admin-shell .navbar {
  min-height: 64px !important;
  padding: 0 22px !important;
}

body.blin-admin-shell .navbar-right .dropdown-skin {
  display: none !important;
}

.blin-admin-top-title {
  margin-left: 18px !important;
  display: flex !important;
  flex-direction: column !important;
  justify-content: center !important;
  gap: 4px !important;
}

.blin-admin-top-title strong {
  color: var(--admin-ink) !important;
  font-size: 16px !important;
  font-weight: 850 !important;
  line-height: 1 !important;
}

.blin-admin-top-title span {
  color: var(--admin-muted) !important;
  font-size: 12px !important;
  font-weight: 650 !important;
  line-height: 1 !important;
}

body.blin-admin-shell .lyear-toggler-bar {
  background: var(--admin-ink) !important;
}

body.blin-admin-shell .icon-item {
  width: 38px !important;
  height: 38px !important;
  display: inline-flex !important;
  align-items: center !important;
  justify-content: center !important;
  border-radius: 10px !important;
  background: var(--admin-panel) !important;
  border: 1px solid var(--admin-line) !important;
  color: var(--admin-text) !important;
}

body.blin-admin-shell .sidebar-footer {
  color: #94a3b8 !important;
  border-top: 1px solid rgba(255, 255, 255, .08) !important;
}

body.blin-admin-shell .sidebar-footer a,
body.blin-admin-shell .sidebar-footer span,
body.blin-admin-shell .copyright {
  color: #94a3b8 !important;
}

body.blin-admin-content > .card:first-child,
body.blin-admin-content > .container-fluid > .card:first-child,
body.blin-admin-content .card {
  margin-bottom: 18px !important;
}

body.blin-admin-login .card {
  padding: 34px !important;
  border-radius: 18px !important;
}

body.blin-admin-login h2::before,
body.blin-admin-login h2::after,
body.blin-admin-login .blin-login-brand h2::before,
body.blin-admin-login .blin-login-brand h2::after,
body.center-vh.blin-admin-login h2::before,
body.center-vh.blin-admin-login h2::after {
  display: none !important;
  content: none !important;
  width: 0 !important;
  height: 0 !important;
  margin: 0 !important;
  padding: 0 !important;
  background: transparent !important;
  box-shadow: none !important;
}

.blin-login-brand {
  display: flex !important;
  flex-direction: column !important;
  align-items: center !important;
  gap: 12px !important;
}

.blin-login-brand h2 {
  margin: 0 !important;
  font-size: 24px !important;
  font-weight: 900 !important;
  color: var(--admin-ink) !important;
  letter-spacing: 0 !important;
}

.blin-login-brand h2::before {
  display: none !important;
}

.blin-login-brand p {
  margin: 0 !important;
  color: var(--admin-muted) !important;
  font-size: 13px !important;
  font-weight: 650 !important;
}

body.blin-admin-login #captcha {
  height: 42px !important;
  max-width: 100% !important;
  border-radius: 10px !important;
  border: 1px solid var(--admin-line-strong) !important;
  object-fit: cover !important;
}

/* Final sidebar contrast lock: one color scheme, readable on every menu level. */
html body.blin-admin-shell,
html body.blin-admin-shell.mx-sidebar-light,
html body.blin-admin-shell.mx-sidebar-dark,
html body.blin-admin-shell[data-sidebarbg],
html body.blin-admin-shell[data-logobg],
html body.blin-admin-shell[data-headerbg] {
  --admin-shell: #0f172a !important;
  --admin-shell-2: #111827 !important;
}

html body.blin-admin-shell .lyear-layout-sidebar,
html body.blin-admin-shell.mx-sidebar-light .lyear-layout-sidebar,
html body.blin-admin-shell.mx-sidebar-dark .lyear-layout-sidebar {
  background: #0f172a !important;
  background-image: none !important;
  border-right: 1px solid rgba(255, 255, 255, .12) !important;
  box-shadow: none !important;
}

html body.blin-admin-shell .sidebar-header,
html body.blin-admin-shell.mx-sidebar-light .sidebar-header,
html body.blin-admin-shell.mx-sidebar-dark .sidebar-header {
  background: #0f172a !important;
  background-image: none !important;
  border-bottom: 1px solid rgba(255, 255, 255, .12) !important;
}

html body.blin-admin-shell .lyear-layout-sidebar-info,
html body.blin-admin-shell .sidebar-main,
html body.blin-admin-shell .sidebar-footer,
html body.blin-admin-shell.mx-sidebar-light .lyear-layout-sidebar-info,
html body.blin-admin-shell.mx-sidebar-light .sidebar-main,
html body.blin-admin-shell.mx-sidebar-light .sidebar-footer,
html body.blin-admin-shell.mx-sidebar-dark .lyear-layout-sidebar-info,
html body.blin-admin-shell.mx-sidebar-dark .sidebar-main,
html body.blin-admin-shell.mx-sidebar-dark .sidebar-footer {
  background: #0f172a !important;
  background-image: none !important;
}

html body.blin-admin-shell #logo a,
html body.blin-admin-shell #logo a span,
html body.blin-admin-shell.mx-sidebar-light #logo a,
html body.blin-admin-shell.mx-sidebar-light #logo a span {
  color: #ffffff !important;
}

html body.blin-admin-shell .sidebar-main a,
html body.blin-admin-shell .nav-drawer > li > a,
html body.blin-admin-shell .nav-subnav > li > a,
html body.blin-admin-shell.mx-sidebar-light .sidebar-main a,
html body.blin-admin-shell.mx-sidebar-light .nav-drawer > li > a,
html body.blin-admin-shell.mx-sidebar-light .nav-subnav > li > a,
html body.blin-admin-shell.mx-sidebar-dark .sidebar-main a,
html body.blin-admin-shell.mx-sidebar-dark .nav-drawer > li > a,
html body.blin-admin-shell.mx-sidebar-dark .nav-subnav > li > a {
  color: #e5e7eb !important;
  background: transparent !important;
  text-shadow: none !important;
  opacity: 1 !important;
}

html body.blin-admin-shell .sidebar-main a span,
html body.blin-admin-shell .nav-drawer > li > a span,
html body.blin-admin-shell .nav-subnav > li > a span {
  color: #e5e7eb !important;
  opacity: 1 !important;
}

html body.blin-admin-shell .sidebar-main a i,
html body.blin-admin-shell .sidebar-main a .mdi,
html body.blin-admin-shell .nav-drawer > li > a i,
html body.blin-admin-shell .nav-drawer > li > a .mdi,
html body.blin-admin-shell .nav-subnav > li > a i,
html body.blin-admin-shell .nav-subnav > li > a .mdi,
html body.blin-admin-shell.mx-sidebar-light .nav-drawer > li > a i,
html body.blin-admin-shell.mx-sidebar-light .nav-drawer > li > a .mdi {
  color: #c7d2fe !important;
  opacity: 1 !important;
}

html body.blin-admin-shell .nav-subnav {
  background: transparent !important;
  border: 0 !important;
  box-shadow: none !important;
  margin: 2px 0 10px 0 !important;
  padding: 4px 0 4px 8px !important;
}

html body.blin-admin-shell .sidebar-main a:hover,
html body.blin-admin-shell .nav-drawer > li > a:hover,
html body.blin-admin-shell .nav-subnav > li > a:hover {
  background: rgba(99, 102, 241, .22) !important;
  color: #ffffff !important;
}

html body.blin-admin-shell .sidebar-main a:hover span,
html body.blin-admin-shell .nav-drawer > li > a:hover span,
html body.blin-admin-shell .nav-subnav > li > a:hover span,
html body.blin-admin-shell .sidebar-main a:hover i,
html body.blin-admin-shell .nav-drawer > li > a:hover i,
html body.blin-admin-shell .nav-subnav > li > a:hover i,
html body.blin-admin-shell .sidebar-main a:hover .mdi,
html body.blin-admin-shell .nav-drawer > li > a:hover .mdi,
html body.blin-admin-shell .nav-subnav > li > a:hover .mdi {
  color: #ffffff !important;
}

html body.blin-admin-shell .nav-drawer > li.active > a,
html body.blin-admin-shell .nav-drawer > li.open > a,
html body.blin-admin-shell .nav-drawer > li > a.active,
html body.blin-admin-shell .nav-subnav > li.active > a,
html body.blin-admin-shell .nav-subnav > li > a.active,
html body.blin-admin-shell.mx-sidebar-light .nav-drawer > li.active > a,
html body.blin-admin-shell.mx-sidebar-light .nav-drawer > li.open > a,
html body.blin-admin-shell.mx-sidebar-light .nav-subnav > li.active > a {
  background: #4f46e5 !important;
  background-image: none !important;
  color: #ffffff !important;
  border-color: rgba(255, 255, 255, .18) !important;
  box-shadow: none !important;
}

html body.blin-admin-shell .nav-drawer > li.active > a span,
html body.blin-admin-shell .nav-drawer > li.open > a span,
html body.blin-admin-shell .nav-drawer > li > a.active span,
html body.blin-admin-shell .nav-subnav > li.active > a span,
html body.blin-admin-shell .nav-subnav > li > a.active span,
html body.blin-admin-shell .nav-drawer > li.active > a i,
html body.blin-admin-shell .nav-drawer > li.open > a i,
html body.blin-admin-shell .nav-drawer > li > a.active i,
html body.blin-admin-shell .nav-subnav > li.active > a i,
html body.blin-admin-shell .nav-subnav > li > a.active i,
html body.blin-admin-shell .nav-drawer > li.active > a .mdi,
html body.blin-admin-shell .nav-drawer > li.open > a .mdi,
html body.blin-admin-shell .nav-drawer > li > a.active .mdi,
html body.blin-admin-shell .nav-subnav > li.active > a .mdi,
html body.blin-admin-shell .nav-subnav > li > a.active .mdi {
  color: #ffffff !important;
}

html body.blin-admin-shell .sidebar-footer,
html body.blin-admin-shell .sidebar-footer a,
html body.blin-admin-shell .sidebar-footer span,
html body.blin-admin-shell .copyright {
  color: #cbd5e1 !important;
}

html body.blin-admin-shell .nav-subnav > li > a {
  background: transparent !important;
  color: #e5e7eb !important;
  border: 0 !important;
  box-shadow: none !important;
  padding-left: 38px !important;
}

html body.blin-admin-shell .nav-subnav > li > a:hover {
  background: rgba(255, 255, 255, .06) !important;
}

html body.blin-admin-shell .nav-subnav > li.active > a,
html body.blin-admin-shell .nav-subnav > li > a.active {
  background: rgba(79, 70, 229, .32) !important;
  color: #ffffff !important;
}

/* Final selected-state contrast lock for admin controls. */
html body.blin-admin-shell .nav-item-has-subnav.open > a,
html body.blin-admin-shell .nav-item-has-subnav.open > a span,
html body.blin-admin-shell .nav-item-has-subnav.open > a i,
html body.blin-admin-shell .nav-item-has-subnav.open > a .mdi,
html body.blin-admin-shell .nav-item-has-subnav.active > a,
html body.blin-admin-shell .nav-item-has-subnav.active > a span,
html body.blin-admin-shell .nav-item-has-subnav.active > a i,
html body.blin-admin-shell .nav-item-has-subnav.active > a .mdi {
  color: #ffffff !important;
  opacity: 1 !important;
}

html body.blin-admin-shell .nav-item-has-subnav.open > .nav-subnav,
html body.blin-admin-shell .nav-item-has-subnav.active > .nav-subnav {
  display: block !important;
  height: auto !important;
  overflow: visible !important;
  background: transparent !important;
  background-image: none !important;
  border: 0 !important;
  box-shadow: none !important;
}

html body.blin-admin-shell .nav-item-has-subnav.open > .nav-subnav a,
html body.blin-admin-shell .nav-item-has-subnav.active > .nav-subnav a,
html body.blin-admin-shell .nav-item-has-subnav.open > .nav-subnav a span,
html body.blin-admin-shell .nav-item-has-subnav.active > .nav-subnav a span {
  color: #ffffff !important;
  opacity: 1 !important;
}

html body.blin-admin-shell .nav-item-has-subnav.open > .nav-subnav a:not(.active),
html body.blin-admin-shell .nav-item-has-subnav.active > .nav-subnav a:not(.active) {
  background: transparent !important;
  background-image: none !important;
}

body:not(.center-vh) .btn-check + .blin-switch-choice,
body:not(.center-vh) .btn-check + label,
body:not(.center-vh) .btn-group .btn,
body:not(.center-vh) .btn-group label,
body:not(.center-vh) .btn-group-toggle .btn,
body:not(.center-vh) .btn-group-toggle label {
  background: #ffffff !important;
  background-image: none !important;
  color: #1f2937 !important;
  border-color: #cbd5e1 !important;
  text-shadow: none !important;
  opacity: 1 !important;
}

body:not(.center-vh) .btn-check + .blin-switch-choice *,
body:not(.center-vh) .btn-check + label *,
body:not(.center-vh) .btn-group .btn *,
body:not(.center-vh) .btn-group label * {
  color: inherit !important;
  opacity: 1 !important;
}

body:not(.center-vh) .btn-check:checked + .blin-switch-choice,
body:not(.center-vh) .btn-check:checked + label,
body:not(.center-vh) .btn-check:active + .blin-switch-choice,
body:not(.center-vh) .btn-check:active + label,
body:not(.center-vh) .btn-check:focus + .blin-switch-choice,
body:not(.center-vh) .btn-check:focus + label,
body:not(.center-vh) input[type="radio"]:checked + .blin-switch-choice,
body:not(.center-vh) input[type="checkbox"]:checked + .blin-switch-choice {
  background: #4f46e5 !important;
  background-image: none !important;
  color: #ffffff !important;
  border-color: #4f46e5 !important;
  box-shadow: 0 0 0 3px rgba(79, 70, 229, .18) !important;
  opacity: 1 !important;
}

body:not(.center-vh) .btn-check:checked + .blin-switch-choice *,
body:not(.center-vh) .btn-check:checked + label *,
body:not(.center-vh) .btn-check:active + .blin-switch-choice *,
body:not(.center-vh) .btn-check:active + label *,
body:not(.center-vh) .btn-check:focus + .blin-switch-choice *,
body:not(.center-vh) .btn-check:focus + label *,
body:not(.center-vh) input[type="radio"]:checked + .blin-switch-choice *,
body:not(.center-vh) input[type="checkbox"]:checked + .blin-switch-choice * {
  color: #ffffff !important;
  opacity: 1 !important;
}

body:not(.center-vh) .form-check-input,
body:not(.center-vh) input[type="checkbox"],
body:not(.center-vh) input[type="radio"] {
  width: 16px !important;
  height: 16px !important;
  min-width: 16px !important;
  min-height: 16px !important;
  max-width: 16px !important;
  max-height: 16px !important;
  padding: 0 !important;
  margin-top: .2em !important;
  border: 1px solid #94a3b8 !important;
  background-color: #ffffff !important;
  box-shadow: none !important;
  vertical-align: middle !important;
  appearance: auto !important;
  -webkit-appearance: auto !important;
}

body:not(.center-vh) input[type="checkbox"],
body:not(.center-vh) .form-check-input[type="checkbox"] {
  border-radius: 4px !important;
}

body:not(.center-vh) input[type="radio"],
body:not(.center-vh) .form-check-input[type="radio"] {
  border-radius: 50% !important;
}

body:not(.center-vh) .btn-check {
  position: absolute !important;
  width: 1px !important;
  height: 1px !important;
  min-width: 1px !important;
  min-height: 1px !important;
  padding: 0 !important;
  margin: -1px !important;
  overflow: hidden !important;
  clip: rect(0, 0, 0, 0) !important;
  white-space: nowrap !important;
  border: 0 !important;
  appearance: none !important;
  -webkit-appearance: none !important;
}

body:not(.center-vh) .form-check-input:checked,
body:not(.center-vh) input[type="checkbox"]:checked,
body:not(.center-vh) input[type="radio"]:checked {
  background-color: #4f46e5 !important;
  border-color: #4f46e5 !important;
  color: #ffffff !important;
}

body:not(.center-vh) .form-check-input:focus,
body:not(.center-vh) input[type="checkbox"]:focus,
body:not(.center-vh) input[type="radio"]:focus {
  border-color: #4f46e5 !important;
  box-shadow: 0 0 0 3px rgba(79, 70, 229, .18) !important;
}

body:not(.center-vh) .form-check-label,
body:not(.center-vh) .custom-control-label,
body:not(.center-vh) .checkbox label,
body:not(.center-vh) .radio label {
  color: #1f2937 !important;
  opacity: 1 !important;
}

body:not(.center-vh) .bootstrap-select .dropdown-menu li.selected > a,
body:not(.center-vh) .bootstrap-select .dropdown-menu li.active > a,
body:not(.center-vh) .bootstrap-select .dropdown-menu li a.active,
body:not(.center-vh) .dropdown-menu .active > a,
body:not(.center-vh) .dropdown-menu .selected > a,
body:not(.center-vh) .dropdown-item.active,
body:not(.center-vh) .dropdown-item:active,
body:not(.center-vh) .select2-results__option--selected,
body:not(.center-vh) .select2-results__option[aria-selected="true"],
body:not(.center-vh) .select2-results__option--highlighted,
body:not(.center-vh) .chosen-container .chosen-results li.highlighted,
body:not(.center-vh) .chosen-container .chosen-results li.result-selected {
  background: #4f46e5 !important;
  background-image: none !important;
  color: #ffffff !important;
  opacity: 1 !important;
}

body:not(.center-vh) .bootstrap-select .dropdown-menu li.selected > a *,
body:not(.center-vh) .bootstrap-select .dropdown-menu li.active > a *,
body:not(.center-vh) .bootstrap-select .dropdown-menu li a.active *,
body:not(.center-vh) .dropdown-menu .active > a *,
body:not(.center-vh) .dropdown-menu .selected > a *,
body:not(.center-vh) .dropdown-item.active *,
body:not(.center-vh) .dropdown-item:active *,
body:not(.center-vh) .select2-results__option--selected *,
body:not(.center-vh) .select2-results__option[aria-selected="true"] *,
body:not(.center-vh) .select2-results__option--highlighted *,
body:not(.center-vh) .chosen-container .chosen-results li.highlighted *,
body:not(.center-vh) .chosen-container .chosen-results li.result-selected * {
  color: #ffffff !important;
  opacity: 1 !important;
}

body:not(.center-vh) .bootstrap-select .filter-option-inner-inner,
body:not(.center-vh) .bootstrap-select > .dropdown-toggle .filter-option,
body:not(.center-vh) .bootstrap-select > .dropdown-toggle .filter-option *,
body:not(.center-vh) .select2-selection__rendered,
body:not(.center-vh) .chosen-single span {
  color: #0f172a !important;
  opacity: 1 !important;
}

body:not(.center-vh) .table-active,
body:not(.center-vh) .table-active > th,
body:not(.center-vh) .table-active > td,
body:not(.center-vh) tr.selected,
body:not(.center-vh) tr.selected > th,
body:not(.center-vh) tr.selected > td,
body:not(.center-vh) .bootstrap-table .selected,
body:not(.center-vh) .bootstrap-table .selected > th,
body:not(.center-vh) .bootstrap-table .selected > td {
  background: #eef2ff !important;
  color: #0f172a !important;
}

body:not(.center-vh) tr.selected *,
body:not(.center-vh) .bootstrap-table .selected * {
  color: #0f172a !important;
  opacity: 1 !important;
}

body:not(.center-vh) .jstree-clicked,
body:not(.center-vh) .jstree-hovered,
body:not(.center-vh) .list-group-item.active,
body:not(.center-vh) .list-group-item.active *,
body:not(.center-vh) .nav-tabs .nav-link.active,
body:not(.center-vh) .nav-pills .nav-link.active {
  background: #4f46e5 !important;
  background-image: none !important;
  color: #ffffff !important;
  border-color: #4f46e5 !important;
}

body:not(.center-vh) .jstree-clicked *,
body:not(.center-vh) .jstree-hovered *,
body:not(.center-vh) .nav-tabs .nav-link.active *,
body:not(.center-vh) .nav-pills .nav-link.active * {
  color: #ffffff !important;
  opacity: 1 !important;
}

/* Absolute final sidebar surface lock. Keep one background and readable text. */
html body.blin-admin-shell .lyear-layout-sidebar,
html body.blin-admin-shell .lyear-layout-sidebar *,
html body.blin-admin-shell.mx-sidebar-light .lyear-layout-sidebar,
html body.blin-admin-shell.mx-sidebar-light .lyear-layout-sidebar *,
html body.blin-admin-shell.mx-sidebar-dark .lyear-layout-sidebar,
html body.blin-admin-shell.mx-sidebar-dark .lyear-layout-sidebar * {
  text-shadow: none !important;
}

html body.blin-admin-shell .lyear-layout-sidebar,
html body.blin-admin-shell .sidebar-header,
html body.blin-admin-shell #logo,
html body.blin-admin-shell .lyear-layout-sidebar-info,
html body.blin-admin-shell .lyear-scroll,
html body.blin-admin-shell .sidebar-main,
html body.blin-admin-shell .nav-drawer,
html body.blin-admin-shell .nav-subnav,
html body.blin-admin-shell .nav-item-has-subnav,
html body.blin-admin-shell .nav-item-has-subnav.open,
html body.blin-admin-shell .nav-item-has-subnav.active,
html body.blin-admin-shell .nav-subnav li,
html body.blin-admin-shell .sidebar-footer,
html body.blin-admin-shell.mx-sidebar-light .lyear-layout-sidebar,
html body.blin-admin-shell.mx-sidebar-light .sidebar-header,
html body.blin-admin-shell.mx-sidebar-light .lyear-layout-sidebar-info,
html body.blin-admin-shell.mx-sidebar-light .sidebar-main,
html body.blin-admin-shell.mx-sidebar-light .nav-drawer,
html body.blin-admin-shell.mx-sidebar-light .nav-subnav,
html body.blin-admin-shell.mx-sidebar-light .sidebar-footer {
  background: #0f172a !important;
  background-color: #0f172a !important;
  background-image: none !important;
  box-shadow: none !important;
}

html body.blin-admin-shell .lyear-layout-sidebar a,
html body.blin-admin-shell .lyear-layout-sidebar a span,
html body.blin-admin-shell .lyear-layout-sidebar a i,
html body.blin-admin-shell .lyear-layout-sidebar a .mdi,
html body.blin-admin-shell .lyear-layout-sidebar .nav-subnav a,
html body.blin-admin-shell .lyear-layout-sidebar .nav-subnav a span,
html body.blin-admin-shell .lyear-layout-sidebar .nav-subnav a i,
html body.blin-admin-shell .lyear-layout-sidebar .nav-subnav a .mdi {
  color: #f8fafc !important;
  opacity: 1 !important;
}

html body.blin-admin-shell .lyear-layout-sidebar .nav-drawer > li > a,
html body.blin-admin-shell .lyear-layout-sidebar .nav-subnav > li > a {
  border: 0 !important;
  box-shadow: none !important;
  background: transparent !important;
  background-image: none !important;
  transform: none !important;
}

html body.blin-admin-shell .lyear-layout-sidebar .nav-drawer > li > a:hover,
html body.blin-admin-shell .lyear-layout-sidebar .nav-subnav > li > a:hover {
  background: #1f2937 !important;
  background-image: none !important;
  color: #ffffff !important;
}

html body.blin-admin-shell .lyear-layout-sidebar .nav-drawer > li.open > a,
html body.blin-admin-shell .lyear-layout-sidebar .nav-drawer > li.active > a,
html body.blin-admin-shell .lyear-layout-sidebar .nav-drawer > li > a.active,
html body.blin-admin-shell .lyear-layout-sidebar .nav-subnav > li.active > a,
html body.blin-admin-shell .lyear-layout-sidebar .nav-subnav > li > a.active {
  background: #4f46e5 !important;
  background-image: none !important;
  color: #ffffff !important;
}

html body.blin-admin-shell .lyear-layout-sidebar .nav-drawer > li.open > a *,
html body.blin-admin-shell .lyear-layout-sidebar .nav-drawer > li.active > a *,
html body.blin-admin-shell .lyear-layout-sidebar .nav-drawer > li > a.active *,
html body.blin-admin-shell .lyear-layout-sidebar .nav-subnav > li.active > a *,
html body.blin-admin-shell .lyear-layout-sidebar .nav-subnav > li > a.active * {
  color: #ffffff !important;
  opacity: 1 !important;
}

/* Sidebar expanded child menu titles must always be white. */
html body.blin-admin-shell .lyear-layout-sidebar .nav-subnav,
html body.blin-admin-shell .lyear-layout-sidebar .nav-subnav li,
html body.blin-admin-shell .lyear-layout-sidebar .nav-subnav li a,
html body.blin-admin-shell .lyear-layout-sidebar .nav-subnav li a:link,
html body.blin-admin-shell .lyear-layout-sidebar .nav-subnav li a:visited,
html body.blin-admin-shell .lyear-layout-sidebar .nav-subnav li a:hover,
html body.blin-admin-shell .lyear-layout-sidebar .nav-subnav li a:focus,
html body.blin-admin-shell .lyear-layout-sidebar .nav-subnav li a:active,
html body.blin-admin-shell .lyear-layout-sidebar .nav-subnav li a *,
html body.blin-admin-shell .lyear-layout-sidebar .nav-subnav li a span,
html body.blin-admin-shell .lyear-layout-sidebar .nav-subnav li a cite,
html body.blin-admin-shell .lyear-layout-sidebar .nav-subnav li a em,
html body.blin-admin-shell .lyear-layout-sidebar .nav-subnav li a small,
html body.blin-admin-shell .lyear-layout-sidebar .nav-subnav li a i,
html body.blin-admin-shell .lyear-layout-sidebar .nav-subnav li a .mdi {
  color: #ffffff !important;
  opacity: 1 !important;
  text-shadow: none !important;
}

html body.blin-admin-shell .blin-sidebar-menu-text,
html body.blin-admin-shell .blin-sidebar-menu-text *,
html body.blin-admin-shell .nav-subnav .blin-sidebar-menu-text,
html body.blin-admin-shell .nav-subnav .blin-sidebar-menu-text *,
html body.blin-admin-shell .nav-drawer .blin-sidebar-menu-text,
html body.blin-admin-shell .nav-drawer .blin-sidebar-menu-text * {
  color: #ffffff !important;
  opacity: 1 !important;
  text-shadow: none !important;
}

@media (max-width: 768px) {
  body:not(.center-vh) .card,
  body:not(.center-vh) .panel,
  body:not(.center-vh) .fixed-table-container {
    border-radius: 10px !important;
  }

  body:not(.center-vh) .btn {
    min-height: 38px !important;
  }
}
"""


def main() -> None:
    if not ROOT.exists():
        raise SystemExit(f"ROOT_NOT_FOUND:{ROOT}")
    changed = 0
    if patch_css():
        changed += 1
    changed += patch_templates()
    changed += bump_css_versions()
    print(f"PATCH_OK admin_backend_ui_2026 changed={changed}")


if __name__ == "__main__":
    main()
