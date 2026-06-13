#!/usr/bin/env python3
from datetime import datetime
from pathlib import Path


ROOT = Path("/www/wwwroot/blinlin")
INDEX = ROOT / "application/admin/view/app/index.html"
EDIT = ROOT / "application/admin/view/app/edit.html"


def backup(path: Path, suffix: str) -> str:
    target = path.with_name(
        f"{path.name}.bak_{suffix}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    target.write_text(path.read_text(errors="ignore"))
    return str(target)


def main() -> None:
    changed = False

    index = INDEX.read_text(errors="ignore")
    original_index = index
    if "login-policy-btn" not in index:
        index = index.replace(
            '''                "click .edit-btn": function (event, value, row, index) {
                    window.location.href = "{:url('edit')}?appid=" + row.appid
                },''',
            '''                "click .edit-btn": function (event, value, row, index) {
                    window.location.href = "{:url('edit')}?appid=" + row.appid
                },
                "click .login-policy-btn": function (event, value, row, index) {
                    window.location.href = "{:url('edit')}?appid=" + row.appid + "#login-policy"
                },''',
        )
        index = index.replace(
            '''            html += '<a href="#!" class="btn btn-sm btn-default me-1 edit-btn" title="编辑" data-bs-toggle="tooltip"><i class="mdi mdi-pencil"></i></a>';''',
            '''            html += '<a href="#!" class="btn btn-sm btn-default me-1 edit-btn" title="编辑" data-bs-toggle="tooltip"><i class="mdi mdi-pencil"></i></a>';
            html += '<a href="#!" class="btn btn-sm btn-default me-1 login-policy-btn" title="登录策略" data-bs-toggle="tooltip"><i class="mdi mdi-key-variant"></i> 登录策略</a>';''',
        )
    else:
        index = index.replace(
            '<i class="mdi mdi-account-key"></i></a>',
            '<i class="mdi mdi-key-variant"></i> 登录策略</a>',
        )
    if index != original_index:
        print("PATCH_INDEX_BACKUP", backup(INDEX, "login_policy_button"))
        INDEX.write_text(index)
        changed = True

    edit = EDIT.read_text(errors="ignore")
    original_edit = edit
    edit = edit.replace('<div class="card">\n                    <header class="card-header">\n                        <div class="card-title">登录配置</div>',
                        '<div class="card" id="login-policy">\n                    <header class="card-header">\n                        <div class="card-title">登录配置</div>',
                        1)
    if edit != original_edit:
        print("PATCH_EDIT_BACKUP", backup(EDIT, "login_policy_anchor"))
        EDIT.write_text(edit)
        changed = True

    print("PATCHED_LOGIN_POLICY_BUTTON" if changed else "LOGIN_POLICY_BUTTON_ALREADY_UP_TO_DATE")


if __name__ == "__main__":
    main()
