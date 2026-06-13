#!/usr/bin/env python3
from datetime import datetime
from pathlib import Path


ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"
ADMIN = ROOT / "application/admin/controller/App.php"
EDIT = ROOT / "application/admin/view/app/edit.html"


def backup(path: Path, suffix: str) -> str:
    target = path.with_name(
        f"{path.name}.bak_{suffix}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    target.write_text(path.read_text(errors="ignore"))
    return str(target)


def patch_api() -> bool:
    source = API.read_text(errors="ignore")
    original = source
    marker = '        $result["announcement_configuration"] = $this->app_info["announcement_configuration"];\n'
    if '$result["forum_configuration"] = $this->app_info["forum_configuration"];' not in source:
        source = source.replace(
            marker,
            marker + '        $result["forum_configuration"] = $this->app_info["forum_configuration"];\n',
            1,
        )
    if source != original:
        print("PATCH_API_BACKUP", backup(API, "community_switch_api"))
        API.write_text(source)
        return True
    return False


def patch_admin() -> bool:
    source = ADMIN.read_text(errors="ignore")
    original = source
    source = source.replace(
        '"forum_configuration" => \'{"post_switch":"0","comment_switch":"0","moderator_delete_post":"0","moderator_delete_comment":"0","members_not_need_pay":"0","post_money":"10","post_integral":"0","post_exp":"0","post_vip":"0","comment_money":"10","comment_integral":"0","comment_exp":"0","comment_vip":"0","money_withdrawal_ratio":"100","money_minimum_withdrawal_amount":"100","integral_withdrawal_ratio":"100","integral_minimum_withdrawal_amount":"100","number_text_intercepted":"50","del_post_money":"0","del_post_integral":"0","del_post_exp":"0","del_comment_money":"0","del_comment_integral":"0","del_comment_exp":"0","max_number_post_day":"0","max_number_post_reward":"0","max_number_comment_reward":"0","posting_interval_time":"0","comment_interval_time":"0","transfer_handling_fee":"0","post_tipping_time_limit":"0","comment_tipping_time_limit":"0"}\',',
        '"forum_configuration" => \'{"community_switch":"0","post_switch":"0","comment_switch":"0","moderator_delete_post":"0","moderator_delete_comment":"0","members_not_need_pay":"0","post_money":"10","post_integral":"0","post_exp":"0","post_vip":"0","comment_money":"10","comment_integral":"0","comment_exp":"0","comment_vip":"0","money_withdrawal_ratio":"100","money_minimum_withdrawal_amount":"100","integral_withdrawal_ratio":"100","integral_minimum_withdrawal_amount":"100","number_text_intercepted":"50","del_post_money":"0","del_post_integral":"0","del_post_exp":"0","del_comment_money":"0","del_comment_integral":"0","del_comment_exp":"0","max_number_post_day":"0","max_number_post_reward":"0","max_number_comment_reward":"0","posting_interval_time":"0","comment_interval_time":"0","transfer_handling_fee":"0","post_tipping_time_limit":"0","comment_tipping_time_limit":"0"}\',',
    )
    marker = '                "post_switch" => $data["post_switch"],\n'
    if '"community_switch" => isset($data["community_switch"]) ? 0 : 1,' not in source:
        source = source.replace(
            marker,
            '                "community_switch" => isset($data["community_switch"]) ? 0 : 1,\n'
            + marker,
            1,
        )
    misplaced = (
        '                if (!isset($result["forum_configuration"]["community_switch"])) {\n'
        '                    $result["forum_configuration"]["community_switch"] = 0;\n'
        '                }\n'
    )
    source = source.replace(misplaced, '')
    forum_decode_marker = '                $result["forum_configuration"] = json_decode($result["forum_configuration"], true);\n'
    if '$result["forum_configuration"]["community_switch"] = 0;' not in source:
        source = source.replace(
            forum_decode_marker,
            forum_decode_marker + misplaced,
            1,
        )
    if source != original:
        print("PATCH_ADMIN_BACKUP", backup(ADMIN, "community_switch_admin"))
        ADMIN.write_text(source)
        return True
    return False


def patch_edit() -> bool:
    source = EDIT.read_text(errors="ignore")
    original = source
    source = source.replace(
        "关闭后客户端只显示即时通讯聊天相关入口，首页、发现和帖子相关入口会隐藏。",
        "关闭后客户端隐藏社区首页和帖子相关入口，底部导航显示消息、发现、我的。",
    )
    if "community_switch" not in source:
        source = source.replace(
            '<div class="card-title">论坛配置</div>',
            '<div class="card-title">社区配置</div>',
            1,
        )
        marker = '''                        <div>
                            <span>发帖开关</span>'''
        replacement = '''                        <div>
                            <span>社区模块</span>
                            <div class="form-check form-check-inline">
                                <input type="checkbox" id="community_switch" value="{$data.forum_configuration.community_switch}" name="community_switch" class="form-check-input" {if $data.forum_configuration.community_switch==0} checked {/if}>
                                <label class="form-check-label" for="community_switch">客户端显示社区入口</label>
                            </div>
                            <small>关闭后客户端隐藏社区首页和帖子相关入口，底部导航显示消息、发现、我的。</small>
                        </div>
                        <div style="margin-top: 1rem;">
                            <span>发帖开关</span>'''
        if marker not in source:
            raise SystemExit("EDIT_MARKER_NOT_FOUND")
        source = source.replace(marker, replacement, 1)
    if source != original:
        print("PATCH_EDIT_BACKUP", backup(EDIT, "community_switch_view"))
        EDIT.write_text(source)
        return True
    return False


def main() -> None:
    changed_api = patch_api()
    changed_admin = patch_admin()
    changed_edit = patch_edit()
    changed = changed_api or changed_admin or changed_edit
    print("PATCHED_COMMUNITY_SWITCH" if changed else "COMMUNITY_SWITCH_ALREADY_UP_TO_DATE")


if __name__ == "__main__":
    main()
