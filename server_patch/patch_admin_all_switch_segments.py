#!/usr/bin/env python3
"""Convert app admin switches to the segmented on/off UI."""
from datetime import datetime
from pathlib import Path
import re


ROOT = Path("/www/wwwroot/blinlin")
ADMIN = ROOT / "application/admin/controller/App.php"
APP_EDIT = ROOT / "application/admin/view/app/edit.html"
LAYOUT = ROOT / "application/admin/view/layout.html"
MODERN_CSS = ROOT / "public/static/css/modern-admin.css"


def backup(path: Path, suffix: str) -> str:
    target = path.with_name(
        f"{path.name}.bak_{suffix}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    target.write_text(path.read_text(errors="ignore"))
    return str(target)


def segment(
    name: str,
    expr: str,
    *,
    on_value: str = "0",
    off_value: str = "1",
    on_label: str = "开启",
    off_label: str = "关闭",
    onchange: str = "",
    aria: str = "",
) -> str:
    change = f' onchange="{onchange}(this.value)"' if onchange else ""
    label = aria or name
    return (
        f'<div class="blin-segmented-switch" role="group" aria-label="{label}">'
        f'\n                                <input type="radio" id="{name}_on" value="{on_value}" name="{name}" class="btn-check" autocomplete="off"{change} {{if {expr}=={on_value}}} checked {{/if}}>'
        f'\n                                <label class="blin-switch-choice blin-switch-choice-on" for="{name}_on"><i class="mdi mdi-check-circle-outline"></i>{on_label}</label>'
        f'\n                                <input type="radio" id="{name}_off" value="{off_value}" name="{name}" class="btn-check" autocomplete="off"{change} {{if {expr}=={off_value}}} checked {{/if}}>'
        f'\n                                <label class="blin-switch-choice blin-switch-choice-off" for="{name}_off"><i class="mdi mdi-close-circle-outline"></i>{off_label}</label>'
        f'\n                            </div>'
    )


def setting_row(
    title: str,
    desc: str,
    name: str,
    expr: str,
    *,
    on_value: str = "0",
    off_value: str = "1",
    on_label: str = "开启",
    off_label: str = "关闭",
    onchange: str = "",
    desc_id: str = "",
    extra_class: str = "",
) -> str:
    desc_attr = f' id="{desc_id}"' if desc_id else ""
    classes = f"blin-setting-row {extra_class}".strip()
    return (
        f'<div class="{classes}">'
        f'\n                            <div class="blin-setting-copy">'
        f'\n                                <span class="blin-setting-title">{title}</span>'
        f'\n                                <small class="blin-setting-desc"{desc_attr}>{desc}</small>'
        f'\n                            </div>'
        f'\n                            {segment(name, expr, on_value=on_value, off_value=off_value, on_label=on_label, off_label=off_label, onchange=onchange, aria=title)}'
        f'\n                        </div>'
    )


def compact_switch(
    title: str,
    desc: str,
    name: str,
    expr: str,
    *,
    on_value: str = "0",
    off_value: str = "1",
    onchange: str = "",
) -> str:
    return (
        '<div class="blin-setting-row blin-setting-row-compact">'
        f'\n                                            <div class="blin-setting-copy">'
        f'\n                                                <span class="blin-setting-title">{title}</span>'
        f'\n                                                <small class="blin-setting-desc">{desc}</small>'
        f'\n                                            </div>'
        f'\n                                            {segment(name, expr, on_value=on_value, off_value=off_value, onchange=onchange, aria=title)}'
        f'\n                                        </div>'
    )


def patch_controller() -> bool:
    source = ADMIN.read_text(errors="ignore")
    original = source
    replacements = {
        '"registration_switch" => isset($data["registration_switch"]) ? 0 : 1,':
            '"registration_switch" => isset($data["registration_switch"]) ? intval($data["registration_switch"]) : 1,',
        '"sign_switch" => isset($data["sign_switch"]) ? 0 : 1,':
            '"sign_switch" => isset($data["sign_switch"]) ? intval($data["sign_switch"]) : 1,',
        '"invitation_switch" => isset($data["invitation_switch"]) ? 0 : 1,':
            '"invitation_switch" => isset($data["invitation_switch"]) ? intval($data["invitation_switch"]) : 1,',
        '"login_switch" => isset($data["login_switch"]) ? 0 : 1,':
            '"login_switch" => isset($data["login_switch"]) ? intval($data["login_switch"]) : 1,',
        '"security_switch" => isset($data["security_switch"]) ? 0 : 1,':
            '"security_switch" => isset($data["security_switch"]) ? intval($data["security_switch"]) : 1,',
        '"update_userinfo_audit" => isset($data["update_userinfo_audit"]) ? 0 : 1,':
            '"update_userinfo_audit" => isset($data["update_userinfo_audit"]) ? intval($data["update_userinfo_audit"]) : 1,',
        '"app_switch" => isset($data["app_switch"]) ? 0 : 1,':
            '"app_switch" => isset($data["app_switch"]) ? intval($data["app_switch"]) : 1,',
        '"increase_decrease" => isset($data["increase_decrease"]) ? 1 : 0,':
            '"increase_decrease" => isset($data["increase_decrease"]) ? intval($data["increase_decrease"]) : 0,',
    }
    for old, new in replacements.items():
        source = source.replace(old, new)
    if source != original:
        print("PATCH_CONTROLLER_BACKUP", backup(ADMIN, "all_switch_segments"))
        ADMIN.write_text(source)
        return True
    return False


def replace_block(source: str, old: str, new: str, label: str) -> str:
    if old in source:
        return source.replace(old, new, 1)
    if label in source:
        return source
    raise SystemExit(f"BLOCK_NOT_FOUND:{label}")


def patch_edit() -> bool:
    source = APP_EDIT.read_text(errors="ignore")
    original = source

    source = replace_block(
        source,
        '''                            <div class="col-md-12">
                                <div class="form-check form-switch">
                                    <input type="checkbox" id="app_switch" value="{$data.app_switch}" name="app_switch" class="form-check-input" onclick="change_app_switch(this.value)" {if $data.app_switch==0} checked {/if}>
                                </div>
                                {if $data.app_switch == 1}
                                <small id="app_switch_words" style="margin-bottom: 0;">关闭应用控制后，该应用下的用户 <code>不允许任何操作</code></small>
                                {else /}
                                <small id="app_switch_words" style="margin-bottom: 0;">开启应用控制后，该应用下的用户可以 <code>可正常使用</code></small>
                                {/if}
                            </div>''',
        '''                            <div class="col-md-12">
                                ''' + setting_row(
            "应用状态",
            '{if $data.app_switch == 0}开启后，该应用下的用户可以 <code>正常使用</code>{else /}关闭后，该应用下的用户 <code>不允许任何操作</code>{/if}',
            "app_switch",
            "$data.app_switch",
            on_label="启用",
            off_label="停用",
            onchange="change_app_switch",
            desc_id="app_switch_words",
            extra_class="blin-switch-card",
        ) + '''
                            </div>''',
        "blin-switch-card",
    )

    source = replace_block(
        source,
        '''                            <div class="col-md-12">
                                <div class="form-check form-switch">
                                    <input type="checkbox" id="increase_decrease" value="{$data.increase_decrease}" name="increase_decrease" class="form-check-input" onclick="change_increase_decrease(this.value)" {if $data.increase_decrease==1} checked {/if}>
                                </div>
                                <small style="margin-bottom: 0;">利用appkey值增减用户金币、积分和会员时间</small>
                            </div>''',
        '''                            <div class="col-md-12">
                                ''' + setting_row(
            "接口资产调整",
            "允许通过 appkey 增减用户金币、积分和会员时间。",
            "increase_decrease",
            "$data.increase_decrease",
            on_value="1",
            off_value="0",
            onchange="change_increase_decrease",
            extra_class="blin-increase-switch-card",
        ) + '''
                            </div>''',
        "blin-increase-switch-card",
    )

    source = replace_block(
        source,
        '''                            <div class="col-md-12">
                                <div class="form-check form-switch">
                                    <input type="checkbox" id="registration_switch" value="{$data.registration_configuration.registration_switch}" name="registration_switch" class="form-check-input" onclick="change_registration_switch(this.value)" {if $data.registration_configuration.registration_switch==0} checked {/if}>
                                </div>
                                {if $data.registration_configuration.registration_switch == 0}
                                <small id="registration_switch_words">开启注册后，该应用可以 <code>正常注册</code></small>
                                {else /}
                                <small id="registration_switch_words">关闭注册后，该应用 <code>禁止所有用户注册</code></small>
                                {/if}
                            </div>''',
        '''                            <div class="col-md-12">
                                ''' + setting_row(
            "注册入口",
            '{if $data.registration_configuration.registration_switch == 0}开启后，该应用可以 <code>正常注册</code>{else /}关闭后，该应用 <code>禁止所有用户注册</code>{/if}',
            "registration_switch",
            "$data.registration_configuration.registration_switch",
            onchange="change_registration_switch",
            desc_id="registration_switch_words",
            extra_class="blin-registration-switch-card",
        ) + '''
                            </div>''',
        "blin-registration-switch-card",
    )

    source = replace_block(
        source,
        '''                            <div class="col-md-12">
                                <div class="form-check form-switch">
                                    <input type="checkbox" id="update_userinfo_audit" value="{$data.userinfo_configuration.update_userinfo_audit}" name="update_userinfo_audit" class="form-check-input" onclick="change_update_userinfo_audit(this.value)" {if $data.userinfo_configuration.update_userinfo_audit==0} checked {/if}>
                                </div>
                                <small>开启后当用户提交了昵称、个性签名、头像、背景的修改才会审核</small>
                            </div>''',
        '''                            <div class="col-md-12">
                                ''' + setting_row(
            "资料审核",
            "开启后，用户提交昵称、签名、头像、背景修改时需要后台审核。",
            "update_userinfo_audit",
            "$data.userinfo_configuration.update_userinfo_audit",
            onchange="change_update_userinfo_audit",
            extra_class="blin-userinfo-audit-card",
        ) + '''
                            </div>''',
        "blin-userinfo-audit-card",
    )

    source = replace_block(
        source,
        '''                            <div class="col-md-12">
                                <div class="form-check form-switch">
                                    <input type="checkbox" id="sign_switch" value="{$data.sign_configuration.sign_switch}" name="sign_switch" class="form-check-input" onclick="change_sign_switch(this.value)" {if $data.sign_configuration.sign_switch==0} checked {/if}>
                                </div>
                                {if $data.sign_configuration.sign_switch == 0}
                                <small id="sign_switch_words">开启签到后，签到接口 <code>可正常使用</code></small>
                                {else /}
                                <small id="sign_switch_words">关闭签到后，签到接口 <code>则将关闭</code></small>
                                {/if}
                            </div>''',
        '''                            <div class="col-md-12">
                                ''' + setting_row(
            "签到功能",
            '{if $data.sign_configuration.sign_switch == 0}开启后，签到接口 <code>可正常使用</code>{else /}关闭后，签到接口 <code>不可使用</code>{/if}',
            "sign_switch",
            "$data.sign_configuration.sign_switch",
            onchange="change_sign_switch",
            desc_id="sign_switch_words",
            extra_class="blin-sign-switch-card",
        ) + '''
                            </div>''',
        "blin-sign-switch-card",
    )

    source = replace_block(
        source,
        '''                            <div class="col-md-12">
                                <div class="form-check form-switch">
                                    <input type="checkbox" id="invitation_switch" value="{$data.invitation_configuration.invitation_switch}" name="invitation_switch" class="form-check-input" onclick="change_invitation_switch(this.value)" {if $data.invitation_configuration.invitation_switch==0} checked {/if}>
                                </div>
                                {if $data.invitation_configuration.invitation_switch == 0}
                                <small id="invitation_switch_words">开启邀请后，填写邀请码接口 <code>可正常使用</code> (以及注册的时候可填写邀请码，不必填选项)</small>
                                {else /}
                                <small id="invitation_switch_words">关闭邀请后，填写邀请码接口 <code>则将关闭</code> (注册填写邀请码则无效)</small>
                                {/if}
                            </div>''',
        '''                            <div class="col-md-12">
                                ''' + setting_row(
            "邀请功能",
            '{if $data.invitation_configuration.invitation_switch == 0}开启后，邀请码接口和注册邀请码入口 <code>可正常使用</code>{else /}关闭后，邀请码接口 <code>不可使用</code>{/if}',
            "invitation_switch",
            "$data.invitation_configuration.invitation_switch",
            onchange="change_invitation_switch",
            desc_id="invitation_switch_words",
            extra_class="blin-invitation-switch-card",
        ) + '''
                            </div>''',
        "blin-invitation-switch-card",
    )

    source = replace_block(
        source,
        '''                            <div class="col-md-12">
                                <div class="form-check form-switch">
                                    <input type="checkbox" id="login_switch" value="{$data.login_configuration.login_switch}" name="login_switch" class="form-check-input" onclick="change_login_switch(this.value)" {if $data.login_configuration.login_switch==0} checked {/if}>
                                </div>
                                {if $data.login_configuration.login_switch == 0}
                                <small id="login_switch_words">关闭登录后 <code>所有用户</code> 都无法登录该应用了</small>
                                {else /}
                                <small id="login_switch_words">开启登录后，该应用下的用户可以 <code> 使用软件（被禁封的用户除外）</code></small>
                                {/if}
                            </div>''',
        '''                            <div class="col-md-12">
                                ''' + setting_row(
            "登录入口",
            '{if $data.login_configuration.login_switch == 0}开启后，该应用下的用户可以 <code>正常登录</code>{else /}关闭后，<code>所有用户</code> 都无法登录该应用{/if}',
            "login_switch",
            "$data.login_configuration.login_switch",
            onchange="change_login_switch",
            desc_id="login_switch_words",
            extra_class="blin-login-switch-card",
        ) + '''
                            </div>''',
        "blin-login-switch-card",
    )

    source = replace_block(
        source,
        '''                            <div class="col-md-12">
                                <div class="form-check form-switch">
                                    <input type="checkbox" id="security_switch" value="{$data.security_configuration.security_switch}" name="security_switch" class="form-check-input" onclick="change_security_switch(this.value)" {if $data.security_configuration.security_switch==0} checked {/if}>
                                </div>
                                {if $data.security_configuration.security_switch == 0}
                                <small id="security_switch_words">开启安全配置后，可对应用 <code>数据</code> 进行加密, 防止数据泄露</small>
                                {else /}
                                <small id="security_switch_words">关闭安全配置后，该应用 <code> 数据 </code>将以明文传输，不使用任何安全配置</small>
                                {/if}
                            </div>''',
        '''                            <div class="col-md-12">
                                ''' + setting_row(
            "安全配置",
            '{if $data.security_configuration.security_switch == 0}开启后，可对应用 <code>数据</code> 进行加密和签名保护{else /}关闭后，应用数据将以明文传输，不使用安全配置{/if}',
            "security_switch",
            "$data.security_configuration.security_switch",
            onchange="change_security_switch",
            desc_id="security_switch_words",
            extra_class="blin-security-switch-card",
        ) + '''
                            </div>''',
        "blin-security-switch-card",
    )

    select_blocks = {
        '''                                    <div class="col-md-4">
                                        <label for="login_code_switch" class="form-label">图片验证码</label>
                                        <select class="form-control" name="login_code_switch">
                                            <option value="0" {if $data.login_configuration.login_code_switch==0} selected {/if}>关闭</option>
                                            <option value="1" {if $data.login_configuration.login_code_switch==1} selected {/if}>开启</option>
                                        </select>
                                    </div>''':
        '''                                    <div class="col-md-4">
                                        ''' + compact_switch(
            "图片验证码",
            "登录时是否启用图片验证码。",
            "login_code_switch",
            "$data.login_configuration.login_code_switch",
            on_value="1",
            off_value="0",
        ) + '''
                                    </div>''',
        '''                                    <div class="col-md-4">
                                        <label for="new_device_login_switch" class="form-label">新设备登录</label>
                                        <select class="form-control" name="new_device_login_switch">
                                            <option value="0" {if $data.login_configuration.new_device_login_switch==0} selected {/if}>开启</option>
                                            <option value="1" {if $data.login_configuration.new_device_login_switch==1} selected {/if}>关闭</option>
                                        </select>
                                        <small>根据设备码判断即注册时侯的设备码,如果开启新设备则允许新设备登录,关闭则不允许新设备登录也就意味着登录时需传递设备码参数</small>
                                    </div>''':
        '''                                    <div class="col-md-4">
                                        ''' + compact_switch(
            "新设备登录",
            "关闭后，登录必须传递已注册设备码。",
            "new_device_login_switch",
            "$data.login_configuration.new_device_login_switch",
        ) + '''
                                    </div>''',
        '''                                    <div class="col-md-4">
                                        <label for="remote_login" class="form-label">异地登录发送邮件</label>
                                        <select class="form-control" name="remote_login">
                                            <option value="0" {if $data.login_configuration.remote_login==0} selected {/if}>开启</option>
                                            <option value="1" {if $data.login_configuration.remote_login==1} selected {/if}>关闭</option>
                                        </select>
                                    </div>''':
        '''                                    <div class="col-md-4">
                                        ''' + compact_switch(
            "异地登录邮件",
            "异地登录时是否发送邮件提醒。",
            "remote_login",
            "$data.login_configuration.remote_login",
        ) + '''
                                    </div>''',
        '''                                    <div class="col-md-12">
                                        <label for="data_signature" class="form-label">数据签名</label>
                                        <select class="form-control" name="data_signature">
                                            <option value="1" {if $data.security_configuration.data_signature==1} selected {/if}>关闭签名</option>
                                            <option value="0" {if $data.security_configuration.data_signature==0} selected {/if}>开启签名</option>
                                        </select>
                                    </div>''':
        '''                                    <div class="col-md-12">
                                        ''' + compact_switch(
            "数据签名",
            "开启后可有效防止接口数据被篡改。",
            "data_signature",
            "$data.security_configuration.data_signature",
        ) + '''
                                    </div>''',
    }
    for old, new in select_blocks.items():
        source = source.replace(old, new)

    forum_switches = [
        ("发帖开关", "控制用户是否可以发布社区帖子。", "post_switch", "$data.forum_configuration.post_switch"),
        ("评论开关", "控制用户是否可以发表评论。", "comment_switch", "$data.forum_configuration.comment_switch"),
        ("版主删除帖子", "控制版主是否可以删除帖子。", "moderator_delete_post", "$data.forum_configuration.moderator_delete_post"),
        ("版主删除评论", "控制版主是否可以删除评论。", "moderator_delete_comment", "$data.forum_configuration.moderator_delete_comment"),
        ("会员无需付费", "开启后，会员阅读付费内容时无需再次付费。", "members_not_need_pay", "$data.forum_configuration.members_not_need_pay"),
    ]
    for title, desc, name, expr in forum_switches:
        pattern = re.compile(
            r'\s*<div style="margin-top: 1rem;">\s*'
            rf'<span>{re.escape(title)}</span>\s*'
            r'<div class="form-check form-check-inline">\s*'
            rf'<input type="radio" id="{name}_on" value="0" name="{name}" class="form-check-input" {{if {re.escape(expr)}==0}} checked {{/if}}>\s*'
            rf'<label class="form-check-label" for="{name}_on">开启</label>\s*'
            r'</div>\s*'
            r'<div class="form-check form-check-inline">\s*'
            rf'<input type="radio" id="{name}_off" value="1" name="{name}" class="form-check-input" {{if {re.escape(expr)}==1}} checked {{/if}}>\s*'
            rf'<label class="form-check-label" for="{name}_off">关闭</label>\s*'
            r'</div>\s*</div>',
            re.S,
        )
        if pattern.search(source):
            source = pattern.sub(
                "\n                        " + setting_row(title, desc, name, expr, extra_class=f"blin-{name.replace('_', '-')}-card"),
                source,
                count=1,
            )

    old_js = '''    function change_app_switch(type) {
        if (type == 1) {
            $("#app_switch_words").html("开启应用控制后，该应用下的用户可以 <code>可正常使用</code>");
            $("#app_switch").val(0);
            $("#app_closing_prompt_input").hide();
        } else {
            $("#app_switch_words").html("关闭应用控制后，该应用下的用户 <code>不允许任何操作</code>");
            $("#app_switch").val(1);
            $("#app_closing_prompt_input").show();
        }
    }

    function change_increase_decrease(type) {
        if (type == 0) {
            $("#increase_decrease").val(1);
        } else {
            $("#increase_decrease").val(0);
        }
    }

    function change_registration_switch(type) {
        if (type == 1) {
            $("#registration_switch_words").html("开启注册后，该应用可以 <code>正常注册</code>");
            $("#registration_switch1").show();
            $("#registration_switch2").hide();
            $("#registration_switch").val(0);
        } else {
            $("#registration_switch_words").html("关闭注册后，该应用 <code>禁止所有用户注册</code>");
            $("#registration_switch1").hide();
            $("#registration_switch2").show();
            $("#registration_switch").val(1);
        }
    }

    function change_update_userinfo_audit(type) {
        if (type == 0) {
            $("#update_userinfo_audit").val(1);
        } else {
            $("#update_userinfo_audit").val(0);
        }
    }

    function change_sign_switch(type) {
        if (type == 1) {
            $("#sign_switch_words").html("开启签到后，签到接口 <code>可正常使用</code>");
            $("#sign_switch_input").show();
            $("#sign_switch").val(0);
        } else {
            $("#sign_switch_words").html("关闭签到后，签到接口 <code>则将关闭</code>");
            $("#sign_switch_input").hide();
            $("#sign_switch").val(1);
        }
    }

    function change_invitation_switch(type) {
        if (type == 1) {
            $("#invitation_switch_words").html("开启邀请后，填写邀请码接口 <code>可正常使用</code> (以及注册的时候可填写邀请码，不必填选项)");
            $("#invitation_switch_input").show();
            $("#invitation_switch").val(0);
        } else {
            $("#invitation_switch_words").html("关闭邀请后，填写邀请码接口 <code>则将关闭</code> (注册填写邀请码则无效)");
            $("#invitation_switch_input").hide();
            $("#invitation_switch").val(1);
        }
    }

    function change_login_switch(type) {
        if (type == 1) {
            $("#login_switch_words").html("开启登录后，该应用下的用户可以 <code> 使用软件（被禁封的用户除外）</code>");
            $("#login_switch1").show();
            $("#login_switch2").hide();
            $("#login_switch").val(0);
        } else {
            $("#login_switch_words").html("关闭登录后 <code>所有用户</code> 都无法登录该应用了");
            $("#login_switch2").show();
            $("#login_switch1").hide();
            $("#login_switch").val(1);
        }
    }

    function change_security_switch(type) {
        if (type == 1) {
            $("#security_switch_words").html("开启安全配置后，可对应用 <code>数据</code> 进行加密, 防止数据泄露");
            $("#security_switch_input").show();
            $("#security_switch").val(0);
        } else {
            $("#security_switch_words").html("关闭安全配置后，该应用 <code> 数据 </code>将以明文传输，不使用任何安全配置");
            $("#security_switch_input").hide();
            $("#security_switch").val(1);
        }
    }
'''
    new_js = '''    function change_app_switch(value) {
        if (String(value) === "0") {
            $("#app_switch_words").html("开启后，该应用下的用户可以 <code>正常使用</code>");
            $("#app_closing_prompt_input").hide();
        } else {
            $("#app_switch_words").html("关闭后，该应用下的用户 <code>不允许任何操作</code>");
            $("#app_closing_prompt_input").show();
        }
    }

    function change_increase_decrease(value) {}

    function change_registration_switch(value) {
        if (String(value) === "0") {
            $("#registration_switch_words").html("开启后，该应用可以 <code>正常注册</code>");
            $("#registration_switch1").show();
            $("#registration_switch2").hide();
        } else {
            $("#registration_switch_words").html("关闭后，该应用 <code>禁止所有用户注册</code>");
            $("#registration_switch1").hide();
            $("#registration_switch2").show();
        }
    }

    function change_update_userinfo_audit(value) {}

    function change_sign_switch(value) {
        if (String(value) === "0") {
            $("#sign_switch_words").html("开启后，签到接口 <code>可正常使用</code>");
            $("#sign_switch_input").show();
        } else {
            $("#sign_switch_words").html("关闭后，签到接口 <code>不可使用</code>");
            $("#sign_switch_input").hide();
        }
    }

    function change_invitation_switch(value) {
        if (String(value) === "0") {
            $("#invitation_switch_words").html("开启后，邀请码接口和注册邀请码入口 <code>可正常使用</code>");
            $("#invitation_switch_input").show();
        } else {
            $("#invitation_switch_words").html("关闭后，邀请码接口 <code>不可使用</code>");
            $("#invitation_switch_input").hide();
        }
    }

    function change_login_switch(value) {
        if (String(value) === "0") {
            $("#login_switch_words").html("开启后，该应用下的用户可以 <code>正常登录</code>");
            $("#login_switch1").show();
            $("#login_switch2").hide();
        } else {
            $("#login_switch_words").html("关闭后，<code>所有用户</code> 都无法登录该应用");
            $("#login_switch2").show();
            $("#login_switch1").hide();
        }
    }

    function change_security_switch(value) {
        if (String(value) === "0") {
            $("#security_switch_words").html("开启后，可对应用 <code>数据</code> 进行加密和签名保护");
            $("#security_switch_input").show();
        } else {
            $("#security_switch_words").html("关闭后，应用数据将以明文传输，不使用安全配置");
            $("#security_switch_input").hide();
        }
    }
'''
    source = source.replace(old_js, new_js, 1)

    if source != original:
        print("PATCH_APP_EDIT_BACKUP", backup(APP_EDIT, "all_switch_segments"))
        APP_EDIT.write_text(source)
        return True
    return False


def patch_layout() -> bool:
    source = LAYOUT.read_text(errors="ignore")
    original = source
    source = re.sub(
        r"/static/css/modern-admin\.css\?v=\d+",
        "/static/css/modern-admin.css?v=202606140030",
        source,
        count=1,
    )
    if source != original:
        print("PATCH_LAYOUT_BACKUP", backup(LAYOUT, "all_switch_segments"))
        LAYOUT.write_text(source)
        return True
    return False


def patch_css() -> bool:
    source = MODERN_CSS.read_text(errors="ignore")
    original = source
    marker = "/* ===== Admin all switch segment layout ===== */"
    if marker not in source:
        source += r'''

/* ===== Admin all switch segment layout ===== */
.blin-setting-row-compact{
  min-height:130px!important;
  height:100%!important;
  align-items:flex-start!important;
  flex-direction:column!important;
  justify-content:space-between!important;
  gap:12px!important;
  margin-bottom:0!important;
}
.blin-setting-row-compact .blin-segmented-switch{
  width:100%!important;
}
.blin-setting-row-compact .blin-switch-choice{
  flex:1!important;
  min-width:0!important;
  padding-left:10px!important;
  padding-right:10px!important;
}
.admin-app-edit .blin-setting-row code{
  padding:2px 6px!important;
  color:#4338ca!important;
  background:#eef2ff!important;
  border-radius:8px!important;
  font-weight:800!important;
}
.admin-app-edit .blin-setting-row + .blin-setting-row{
  margin-top:12px!important;
}
'''
    if source != original:
        print("PATCH_CSS_BACKUP", backup(MODERN_CSS, "all_switch_segments"))
        MODERN_CSS.write_text(source)
        return True
    return False


def main() -> None:
    changed = False
    for fn in [patch_controller, patch_edit, patch_layout, patch_css]:
        changed = fn() or changed
    print("PATCHED_ADMIN_ALL_SWITCH_SEGMENTS" if changed else "ADMIN_ALL_SWITCH_SEGMENTS_ALREADY_UP_TO_DATE")


if __name__ == "__main__":
    main()
