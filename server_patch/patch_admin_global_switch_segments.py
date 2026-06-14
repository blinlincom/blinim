#!/usr/bin/env python3
"""Unify remaining admin binary controls with the segmented switch UI."""
from datetime import datetime
from pathlib import Path
import re


ROOT = Path("/www/wwwroot/blinlin")
ADMIN_INDEX = ROOT / "application/admin/view/admin/index.html"
PERMISSION_INDEX = ROOT / "application/admin/view/permission/index.html"
FORUM_SECTION = ROOT / "application/admin/view/forum/forum_section.html"
USER_EDIT = ROOT / "application/admin/view/user/edit.html"
USER_BAGGE = ROOT / "application/admin/view/user/bagge.html"
USER_CONTROLLER = ROOT / "application/admin/controller/User.php"
APP_DOWNLOAD = ROOT / "application/admin/view/app/edit_download_page.html"
SYSTEM_PAGE = ROOT / "application/admin/view/system/system.html"
LAYOUT = ROOT / "application/admin/view/layout.html"
MODERN_CSS = ROOT / "public/static/css/modern-admin.css"


def backup(path: Path, suffix: str) -> str:
    target = path.with_name(
        f"{path.name}.bak_{suffix}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    target.write_text(path.read_text(errors="ignore"))
    return str(target)


def replace_block(source: str, old: str, new: str, marker: str):
    if old in source:
        return source.replace(old, new, 1), True
    if marker in source:
        return source, False
    raise SystemExit(f"BLOCK_NOT_FOUND:{marker}")


def save_if_changed(path: Path, original: str, source: str, suffix: str) -> bool:
    if source == original:
        return False
    print(f"PATCH_{path.name}_BACKUP", backup(path, suffix))
    path.write_text(source)
    return True


def segmented(
    *,
    name: str,
    on_id: str,
    off_id: str,
    on_value: str,
    off_value: str,
    on_checked: str,
    off_checked: str,
    on_label: str = "开启",
    off_label: str = "关闭",
    aria: str = "",
    small: bool = False,
    table: bool = False,
    onchange: str = "",
) -> str:
    classes = ["blin-segmented-switch"]
    if small:
        classes.append("blin-segmented-switch-sm")
    if table:
        classes.append("blin-table-switch")
    change = f' onchange="{onchange}"' if onchange else ""
    group_label = aria or name
    return (
        f'<div class="{" ".join(classes)}" role="group" aria-label="{group_label}">'
        f'\n                                <input type="radio" id="{on_id}" value="{on_value}" name="{name}" class="btn-check" autocomplete="off"{on_checked}{change}>'
        f'\n                                <label class="blin-switch-choice blin-switch-choice-on" for="{on_id}"><i class="mdi mdi-check-circle-outline"></i>{on_label}</label>'
        f'\n                                <input type="radio" id="{off_id}" value="{off_value}" name="{name}" class="btn-check" autocomplete="off"{off_checked}{change}>'
        f'\n                                <label class="blin-switch-choice blin-switch-choice-off" for="{off_id}"><i class="mdi mdi-close-circle-outline"></i>{off_label}</label>'
        f'\n                            </div>'
    )


def setting_row(title: str, desc: str, switch_html: str) -> str:
    return (
        '<div class="blin-setting-row blin-setting-row-modal">'
        '\n                            <div class="blin-setting-copy">'
        f'\n                                <span class="blin-setting-title">{title}</span>'
        f'\n                                <small class="blin-setting-desc">{desc}</small>'
        '\n                            </div>'
        f'\n                            {switch_html}'
        '\n                        </div>'
    )


def patch_admin_index() -> bool:
    path = ADMIN_INDEX
    source = path.read_text(errors="ignore")
    original = source
    old = '''                    <div class="mb-3">
                        <label for="is_out" class="form-label">禁用</label>
                        <div class="form-check form-switch">
                            <input class="form-check-input form-check-green" value="2" name="status" type="checkbox">
                        </div>
                    </div>'''
    switch_html = segmented(
        name="status",
        on_id="admin_status_on",
        off_id="admin_status_off",
        on_value="1",
        off_value="2",
        on_checked=" checked",
        off_checked="",
        on_label="启用",
        off_label="禁用",
        aria="管理员状态",
    )
    new = '''                    <div class="mb-3">
                        ''' + setting_row(
        "管理员状态",
        "启用后可正常登录后台，禁用后不可登录。",
        switch_html,
    ) + '''
                    </div>'''
    source, _ = replace_block(source, old, new, "管理员状态")
    return save_if_changed(path, original, source, "global_switch_segments")


def patch_permission_index() -> bool:
    path = PERMISSION_INDEX
    source = path.read_text(errors="ignore")
    original = source

    old_menu = '''                                    <td>
                                        {if $vo.is_menu == 1}
                                        <div class="form-check form-switch">
                                            <input class="form-check-input" type="checkbox" value="2" checked onchange="setIsMenu('{$vo.id}',this.value)">
                                        </div>
                                        {else /}
                                        <div class="form-check form-switch">
                                            <input class="form-check-input" type="checkbox" value="1" onchange="setIsMenu('{$vo.id}',this.value)">
                                        </div>
                                        {/if}
                                    </td>'''
    new_menu = '''                                    <td>
                                        <div class="blin-segmented-switch blin-segmented-switch-sm blin-table-switch" role="group" aria-label="是否菜单">
                                            <input type="radio" id="is_menu_{$vo.id}_on" value="1" name="is_menu_{$vo.id}" class="btn-check" autocomplete="off" {if $vo.is_menu == 1} checked {/if} onchange="setIsMenu('{$vo.id}',this.value)">
                                            <label class="blin-switch-choice blin-switch-choice-on" for="is_menu_{$vo.id}_on"><i class="mdi mdi-check-circle-outline"></i>菜单</label>
                                            <input type="radio" id="is_menu_{$vo.id}_off" value="2" name="is_menu_{$vo.id}" class="btn-check" autocomplete="off" {if $vo.is_menu != 1} checked {/if} onchange="setIsMenu('{$vo.id}',this.value)">
                                            <label class="blin-switch-choice blin-switch-choice-off" for="is_menu_{$vo.id}_off"><i class="mdi mdi-close-circle-outline"></i>隐藏</label>
                                        </div>
                                    </td>'''
    source, _ = replace_block(source, old_menu, new_menu, 'is_menu_{$vo.id}_on')

    old_out = '''                                    <td>
                                        {if $vo.is_out == 1}
                                        <div class="form-check form-switch">
                                            <input class="form-check-input form-check-yellow" value="2" type="checkbox" checked onchange="setIsOut('{$vo.id}',this.value)">
                                        </div>
                                        {else /}
                                        <div class="form-check form-switch">
                                            <input class="form-check-input form-check-yellow" value="1" type="checkbox" onchange="setIsOut('{$vo.id}',this.value)">
                                        </div>
                                        {/if}
                                    </td>'''
    new_out = '''                                    <td>
                                        <div class="blin-segmented-switch blin-segmented-switch-sm blin-table-switch" role="group" aria-label="是否外链">
                                            <input type="radio" id="is_out_{$vo.id}_on" value="1" name="is_out_{$vo.id}" class="btn-check" autocomplete="off" {if $vo.is_out == 1} checked {/if} onchange="setIsOut('{$vo.id}',this.value)">
                                            <label class="blin-switch-choice blin-switch-choice-on" for="is_out_{$vo.id}_on"><i class="mdi mdi-check-circle-outline"></i>外链</label>
                                            <input type="radio" id="is_out_{$vo.id}_off" value="2" name="is_out_{$vo.id}" class="btn-check" autocomplete="off" {if $vo.is_out != 1} checked {/if} onchange="setIsOut('{$vo.id}',this.value)">
                                            <label class="blin-switch-choice blin-switch-choice-off" for="is_out_{$vo.id}_off"><i class="mdi mdi-close-circle-outline"></i>内页</label>
                                        </div>
                                    </td>'''
    source, _ = replace_block(source, old_out, new_out, 'is_out_{$vo.id}_on')

    old_modal_out = '''                    <div class="mb-3">
                        <label for="is_out" class="form-label">是否是外链</label>
                        <div class="form-check form-switch">
                            <input class="form-check-input form-check-yellow" value="1" name="is_out" type="checkbox">
                        </div>
                        <small>当是菜单的时候才生效</small>
                    </div>'''
    modal_out_switch = segmented(
        name="is_out",
        on_id="permission_is_out_on",
        off_id="permission_is_out_off",
        on_value="1",
        off_value="2",
        on_checked="",
        off_checked=" checked",
        on_label="外链",
        off_label="内页",
        aria="是否是外链",
    )
    new_modal_out = '''                    <div class="mb-3">
                        ''' + setting_row(
        "是否是外链",
        "当该项是菜单时生效，开启后会在新窗口打开。",
        modal_out_switch,
    ) + '''
                    </div>'''
    source, _ = replace_block(source, old_modal_out, new_modal_out, "permission_is_out_on")

    old_modal_menu = '''                    <div class="mb-3">
                        <label for="is_menu" class="form-label">是否是菜单</label>
                        <div class="form-check form-switch">
                            <input class="form-check-input" value="1" name="is_menu" type="checkbox">
                        </div>
                    </div>'''
    modal_menu_switch = segmented(
        name="is_menu",
        on_id="permission_is_menu_on",
        off_id="permission_is_menu_off",
        on_value="1",
        off_value="2",
        on_checked="",
        off_checked=" checked",
        on_label="菜单",
        off_label="隐藏",
        aria="是否是菜单",
    )
    new_modal_menu = '''                    <div class="mb-3">
                        ''' + setting_row(
        "是否是菜单",
        "开启后在后台菜单中展示，关闭后仅作为权限节点。",
        modal_menu_switch,
    ) + '''
                    </div>'''
    source, _ = replace_block(source, old_modal_menu, new_modal_menu, "permission_is_menu_on")
    return save_if_changed(path, original, source, "global_switch_segments")


def patch_forum_section() -> bool:
    path = FORUM_SECTION
    source = path.read_text(errors="ignore")
    original = source
    old = '''                                    <td>
                                        <div class="form-check form-switch">
                                            <input class="form-check-input" type="checkbox" role="switch" id="plate_status" {if $vo.status==1}checked{/if} onchange="edit_status(this)">
                                        </div>
                                    </td>'''
    new = '''                                    <td>
                                        <div class="blin-segmented-switch blin-segmented-switch-sm blin-table-switch" role="group" aria-label="板块状态">
                                            <input type="radio" id="plate_status_{$vo.id}_on" value="1" name="plate_status_{$vo.id}" class="btn-check" autocomplete="off" {if $vo.status==1} checked {/if} onchange="edit_status(this)">
                                            <label class="blin-switch-choice blin-switch-choice-on" for="plate_status_{$vo.id}_on"><i class="mdi mdi-check-circle-outline"></i>启用</label>
                                            <input type="radio" id="plate_status_{$vo.id}_off" value="0" name="plate_status_{$vo.id}" class="btn-check" autocomplete="off" {if $vo.status!=1} checked {/if} onchange="edit_status(this)">
                                            <label class="blin-switch-choice blin-switch-choice-off" for="plate_status_{$vo.id}_off"><i class="mdi mdi-close-circle-outline"></i>停用</label>
                                        </div>
                                    </td>'''
    source, _ = replace_block(source, old, new, 'plate_status_{$vo.id}_on')
    source = source.replace(
        "        var status = $(obj).prop('checked') == true ? 1 : 0;",
        "        var status = $(obj).val();",
    )
    return save_if_changed(path, original, source, "global_switch_segments")


def patch_user_edit() -> bool:
    path = USER_EDIT
    source = path.read_text(errors="ignore")
    original = source
    old = '''                        <div class="mb-3">
                            <label class="form-label" for="reasons">是否封禁</label>
                            <div class="form-check form-switch">
                                <input class="form-check-input" type="checkbox" role="switch" value="{$user.reasons}" id="reasons" name="reasons" onchange="changenone(this.value)" {if $user.reasons==1} checked {/if}>
                                <label class="form-check-label" for="reasons"></label>
                            </div>
                        </div>'''
    switch_html = '''<div class="blin-segmented-switch" role="group" aria-label="用户状态">
                                <input type="radio" id="reasons_normal" value="0" name="reasons" class="btn-check" autocomplete="off" {if $user.reasons==0} checked {/if} onchange="changenone(this.value)">
                                <label class="blin-switch-choice blin-switch-choice-on" for="reasons_normal"><i class="mdi mdi-check-circle-outline"></i>正常</label>
                                <input type="radio" id="reasons_banned" value="1" name="reasons" class="btn-check" autocomplete="off" {if $user.reasons==1} checked {/if} onchange="changenone(this.value)">
                                <label class="blin-switch-choice blin-switch-choice-off" for="reasons_banned"><i class="mdi mdi-close-circle-outline"></i>封禁</label>
                            </div>'''
    new = '''                        <div class="mb-3">
                            ''' + setting_row(
        "用户状态",
        "正常用户可使用应用，封禁后需填写封禁理由和到期时间。",
        switch_html,
    ) + '''
                        </div>'''
    source, _ = replace_block(source, old, new, "reasons_normal")
    source = source.replace(
        '''    function changenone(value) {
        if (value == 1) {
            $("#reasons").val(0);
            $("#select_else").hide();
        } else {
            $("#reasons").val(1);
            $("#select_else").show();
        }
    }''',
        '''    function changenone(value) {
        if (value == 1) {
            $("#select_else").show();
        } else {
            $("#select_else").hide();
        }
    }''',
    )
    return save_if_changed(path, original, source, "global_switch_segments")


def patch_user_controller() -> bool:
    path = USER_CONTROLLER
    source = path.read_text(errors="ignore")
    original = source
    old = '''            if (!isset($data["reasons"])) {
                $data["reasons"] = 0;
                $data["reasons_ban"] = "";
                $data["reasons_time"] = "";
            } else {
                $data["reasons"] = 1;
                $data["reasons_time"] = strtotime($data["reasons_time"]);
            }'''
    new = '''            if (!isset($data["reasons"]) || intval($data["reasons"]) != 1) {
                $data["reasons"] = 0;
                $data["reasons_ban"] = "";
                $data["reasons_time"] = "";
            } else {
                $data["reasons"] = 1;
                $data["reasons_time"] = strtotime($data["reasons_time"]);
            }'''
    source, _ = replace_block(source, old, new, 'intval($data["reasons"]) != 1')
    return save_if_changed(path, original, source, "global_switch_segments")


def patch_user_bagge() -> bool:
    path = USER_BAGGE
    source = path.read_text(errors="ignore")
    original = source
    old = '''                if (value == 1) {
                    is_checked = '';
                } else if (value == 0) {
                    is_checked = 'checked="checked"';
                }
                {if checkRight('user/update_bagge_status') }
                    result = '<div class="form-check form-switch"><input class="form-check-input" type="checkbox" role="switch" ' + is_checked + ' onClick="updateStatus(' + row.id + ', ' + value + ')"></div>';
                {else /}'''
    new = '''                var normal_checked = value == 0 ? ' checked' : '';
                var disabled_checked = value == 1 ? ' checked' : '';
                {if checkRight('user/update_bagge_status') }
                    result = '<div class="blin-segmented-switch blin-segmented-switch-sm blin-table-switch" role="group" aria-label="徽章状态">' +
                        '<input type="radio" id="bagge_status_' + row.id + '_on" name="bagge_status_' + row.id + '" value="0" class="btn-check" autocomplete="off"' + normal_checked + ' onchange="updateStatus(' + row.id + ', 0)">' +
                        '<label class="blin-switch-choice blin-switch-choice-on" for="bagge_status_' + row.id + '_on"><i class="mdi mdi-check-circle-outline"></i>正常</label>' +
                        '<input type="radio" id="bagge_status_' + row.id + '_off" name="bagge_status_' + row.id + '" value="1" class="btn-check" autocomplete="off"' + disabled_checked + ' onchange="updateStatus(' + row.id + ', 1)">' +
                        '<label class="blin-switch-choice blin-switch-choice-off" for="bagge_status_' + row.id + '_off"><i class="mdi mdi-close-circle-outline"></i>禁用</label>' +
                    '</div>';
                {else /}'''
    source, _ = replace_block(source, old, new, "bagge_status_")
    source = source.replace(
        '''    function updateStatus(id, state) {
        var newstate = (state == 1) ? 0 : 1; // 发送参数值跟当前参数值相反
        $.ajax({
            type: "post",
            url: "{$Request.root}/user/update_bagge_status",
            data: { id: id, status: newstate },''',
        '''    function updateStatus(id, state) {
        $.ajax({
            type: "post",
            url: "{$Request.root}/user/update_bagge_status",
            data: { id: id, status: state },''',
    )
    return save_if_changed(path, original, source, "global_switch_segments")


def patch_app_download() -> bool:
    path = APP_DOWNLOAD
    source = path.read_text(errors="ignore")
    original = source
    old = '''                        <div class="mb-3">
                            <label for="video_url" class="form-label">首页显示（只能开启一个）</label><br>
                            <div class="form-check">
                                <input class="form-check-input" type="checkbox" value="" name="default_official_website" id="default_official_website" {if $data.default_official_website==0} checked {/if}>
                                <label class="form-check-label" for="default_official_website">
                                    默认的复选框
                                </label>
                            </div>
                        </div>'''
    switch_html = '''<div class="blin-segmented-switch" role="group" aria-label="首页显示">
                                <input type="radio" id="default_official_website_on" value="0" name="default_official_website" class="btn-check" autocomplete="off" {if $data.default_official_website==0} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-on" for="default_official_website_on"><i class="mdi mdi-check-circle-outline"></i>开启</label>
                                <input type="radio" id="default_official_website_off" value="1" name="default_official_website" class="btn-check" autocomplete="off" {if $data.default_official_website!=0} checked {/if}>
                                <label class="blin-switch-choice blin-switch-choice-off" for="default_official_website_off"><i class="mdi mdi-close-circle-outline"></i>关闭</label>
                            </div>'''
    new = '''                        <div class="mb-3">
                            ''' + setting_row(
        "首页显示",
        "开启后作为当前下载页首页展示，同一时间只允许开启一个。",
        switch_html,
    ) + '''
                        </div>'''
    source, _ = replace_block(source, old, new, "default_official_website_on")
    source = source.replace(
        '''        if ($("#default_official_website").is(":checked")) {
            var default_official_website = 0;
        } else {
            var default_official_website = 1;
        }''',
        '''        var default_official_website = $('input[name="default_official_website"]:checked').val();''',
    )
    return save_if_changed(path, original, source, "global_switch_segments")


def patch_system_page() -> bool:
    path = SYSTEM_PAGE
    source = path.read_text(errors="ignore")
    original = source
    replacements = [
        (
            '''                            <div class="col-md-12">
                                <label for="debug" class="form-label">debug模式</label>
                                <select class="form-select" name="debug">
                                    <option value="true" {if $env.debug} selected {/if}>开启</option>
                                    <option value="false" {if !$env.debug} selected {/if}>关闭</option>
                                </select>
                            </div>''',
            '''                            <div class="col-md-12">
                                ''' + setting_row(
                "debug模式",
                "仅排查问题时开启，正式环境建议关闭。",
                segmented(
                    name="debug",
                    on_id="system_debug_on",
                    off_id="system_debug_off",
                    on_value="true",
                    off_value="false",
                    on_checked=" {if $env.debug} checked {/if}",
                    off_checked=" {if !$env.debug} checked {/if}",
                    aria="debug模式",
                ),
            ) + '''
                            </div>''',
            "system_debug_on",
        ),
        (
            '''                            <div class="col-md-12">
                                <label for="trace" class="form-label">trace模式</label>
                                <select class="form-select" name="trace">
                                    <option value="true" {if $env.trace} selected {/if}>开启</option>
                                    <option value="false" {if !$env.trace} selected {/if}>关闭</option>
                                </select>
                            </div>''',
            '''                            <div class="col-md-12">
                                ''' + setting_row(
                "trace模式",
                "用于开发调试链路追踪，正式环境建议关闭。",
                segmented(
                    name="trace",
                    on_id="system_trace_on",
                    off_id="system_trace_off",
                    on_value="true",
                    off_value="false",
                    on_checked=" {if $env.trace} checked {/if}",
                    off_checked=" {if !$env.trace} checked {/if}",
                    aria="trace模式",
                ),
            ) + '''
                            </div>''',
            "system_trace_on",
        ),
        (
            '''                            <div class="col-md-12">
                                <label for="captcha_status" class="form-label">后台验证码</label>
                                <select class="form-select" name="captcha_status">
                                    <option value="0" {if $system_info.captcha_status==0 } selected {/if}>开启</option>
                                    <option value="1" {if $system_info.captcha_status==1 } selected {/if}>关闭</option>
                                </select>
                            </div>''',
            '''                            <div class="col-md-12">
                                ''' + setting_row(
                "后台验证码",
                "开启后后台登录需要验证码验证。",
                segmented(
                    name="captcha_status",
                    on_id="system_captcha_on",
                    off_id="system_captcha_off",
                    on_value="0",
                    off_value="1",
                    on_checked=" {if $system_info.captcha_status==0 } checked {/if}",
                    off_checked=" {if $system_info.captcha_status==1 } checked {/if}",
                    aria="后台验证码",
                ),
            ) + '''
                            </div>''',
            "system_captcha_on",
        ),
        (
            '''                            <div class="col-md-12">
                                <label class="form-label">管理员日志</label>
                                <div class="controls-box clearfix">
                                    <div class="form-check form-check-inline">
                                        <input class="form-check-input" id="administrator_log1" type="radio" name="administrator_log" {if $system_info.administrator_log=='0' } checked {/if} value="0">
                                        <label class="form-check-label" for="administrator_log1">开启</label>
                                    </div>
                                    <div class="form-check form-check-inline">
                                        <input class="form-check-input" id="administrator_log2" type="radio" name="administrator_log" {if $system_info.administrator_log=='1' } checked {/if} value="1">
                                        <label class="form-check-label" for="administrator_log2">关闭</label>
                                    </div>
                                </div>
                            </div>''',
            '''                            <div class="col-md-12">
                                ''' + setting_row(
                "管理员日志",
                "开启后记录后台管理员操作日志。",
                segmented(
                    name="administrator_log",
                    on_id="administrator_log1",
                    off_id="administrator_log2",
                    on_value="0",
                    off_value="1",
                    on_checked=" {if $system_info.administrator_log=='0' } checked {/if}",
                    off_checked=" {if $system_info.administrator_log=='1' } checked {/if}",
                    aria="管理员日志",
                ),
            ) + '''
                            </div>''',
            "administrator_log1",
        ),
    ]
    for old, new, marker in replacements:
        source, _ = replace_block(source, old, new, marker)
    return save_if_changed(path, original, source, "global_switch_segments")


def patch_layout_version() -> bool:
    path = LAYOUT
    source = path.read_text(errors="ignore")
    original = source
    source = re.sub(
        r"modern-admin\.css\?v=\d+",
        "modern-admin.css?v=202606140845",
        source,
    )
    return save_if_changed(path, original, source, "global_switch_segments")


def patch_css() -> bool:
    path = MODERN_CSS
    source = path.read_text(errors="ignore")
    original = source
    marker = "/* ===== Admin global segmented switch polish ===== */"
    if marker not in source:
        source += '''

/* ===== Admin global segmented switch polish ===== */
.blin-setting-row-modal{
  margin-bottom:0!important;
  min-height:auto!important;
}
.blin-setting-row-modal .blin-segmented-switch{
  min-width:190px!important;
}
.blin-segmented-switch-sm{
  padding:3px!important;
  gap:3px!important;
  box-shadow:none!important;
}
.blin-segmented-switch-sm .blin-switch-choice{
  min-width:56px!important;
  padding:6px 10px!important;
  font-size:12px!important;
  gap:4px!important;
}
.blin-segmented-switch-sm .blin-switch-choice i{
  font-size:14px!important;
}
.blin-table-switch{
  margin:0 auto!important;
}
.table .blin-table-switch{
  white-space:nowrap!important;
}
.modal .blin-setting-row{
  border-radius:16px!important;
}
@media(max-width:768px){
  .blin-setting-row-modal .blin-segmented-switch{
    min-width:0!important;
    width:100%!important;
  }
}
'''
    return save_if_changed(path, original, source, "global_switch_segments")


def main() -> None:
    changed = False
    for patcher in (
        patch_admin_index,
        patch_permission_index,
        patch_forum_section,
        patch_user_edit,
        patch_user_controller,
        patch_user_bagge,
        patch_app_download,
        patch_system_page,
        patch_layout_version,
        patch_css,
    ):
        changed = patcher() or changed
    if changed:
        print("PATCHED_ADMIN_GLOBAL_SWITCH_SEGMENTS")
    else:
        print("ADMIN_GLOBAL_SWITCH_SEGMENTS_ALREADY_UP_TO_DATE")


if __name__ == "__main__":
    main()
