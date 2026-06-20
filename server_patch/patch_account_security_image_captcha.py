#!/usr/bin/env python3
"""Require image captcha before sensitive account verification codes are sent."""

from datetime import datetime
from pathlib import Path
import os
import shutil


ROOT = Path(os.environ.get("BLIN_ROOT", "/www/wwwroot/blinlin"))
API = ROOT / "application/api/controller/Api.php"


def backup(path):
    stamp = datetime.now().strftime("%Y%m%d%H%M%S")
    shutil.copy2(path, path.with_name(f"{path.name}.bak_account_security_captcha_{stamp}"))


def replace_once(text, old, new, label):
    if new in text:
        return text
    if old not in text:
        raise RuntimeError(f"missing block: {label}")
    return text.replace(old, new, 1)


def scoped_replace(text, anchor, old, new, label, start_at=0):
    start = text.find(anchor, start_at)
    if start < 0:
        raise RuntimeError(f"missing anchor: {label}")
    old_pos = text.find(old, start)
    if old_pos >= 0:
        return text[:old_pos] + new + text[old_pos + len(old) :]
    if text.find(new, start) >= 0:
        return text
    if old_pos < 0:
        raise RuntimeError(f"missing block: {label}")
    return text


def main():
    text = API.read_text(encoding="utf-8", errors="ignore")
    before = text

    text = scoped_replace(
        text,
        "public function get_image_verification_code",
        """        if (!in_array($type, [1, 2])) {
            $this->json(0, '请输入正确的type值');
        }
""",
        """        if (!in_array($type, [1, 2, 3])) {
            $this->json(0, '请输入正确的type值');
        }
""",
        "image captcha type list",
    )

    text = replace_once(
        text,
        """        //注册验证码。邮箱/手机号注册发码前也需要图片验证码，避免短信/邮件被刷。
        if ($type == 2) {
            $registerCodeSwitch = intval(isset($this->app_info["registration_configuration"]["registration_code_switch"]) ? $this->app_info["registration_configuration"]["registration_code_switch"] : 0);
            if (in_array($registerCodeSwitch, [1, 2, 3])) {
                return $this->blinCreateImageCaptcha("register");
            }
            $this->json(0, '未开启注册图片验证码');
        }
""",
        """        //注册验证码。邮箱/手机号注册发码前也需要图片验证码，避免短信/邮件被刷。
        if ($type == 2) {
            $registerCodeSwitch = intval(isset($this->app_info["registration_configuration"]["registration_code_switch"]) ? $this->app_info["registration_configuration"]["registration_code_switch"] : 0);
            if (in_array($registerCodeSwitch, [1, 2, 3])) {
                return $this->blinCreateImageCaptcha("register");
            }
            $this->json(0, '未开启注册图片验证码');
        }
        //账号安全验证码：找回登录密码、找回支付密码、绑定/更换邮箱手机号前使用。
        if ($type == 3) {
            return $this->blinCreateImageCaptcha("security");
        }
""",
        "security image captcha endpoint",
    )

    mobile_validation = """                $data = input('');
                $rule = [
                    'mobile|手机号' => 'require|mobile'
                ];
                $validate = new Validate($rule);
                $result = $validate->check($data);
                if (!$result) {
                    throw new \\Exception((string)$validate->getError());
                }
                $user_info = Db::name('user')->where("appid", $this->appid)->where("mobile='{$mobile}'")->find();
"""
    mobile_validation_with_captcha = """                $data = input('');
                $rule = [
                    'mobile|手机号' => 'require|mobile'
                ];
                $validate = new Validate($rule);
                $result = $validate->check($data);
                if (!$result) {
                    throw new \\Exception((string)$validate->getError());
                }
                if (!$this->blinCheckImageCaptcha("security", input("captcha"))) {
                    throw new \\Exception("图片验证码错误");
                }
                $user_info = Db::name('user')->where("appid", $this->appid)->where("mobile='{$mobile}'")->find();
"""
    text = scoped_replace(
        text,
        "            //找回密码",
        mobile_validation,
        mobile_validation_with_captcha,
        "mobile retrieve captcha",
    )
    text = scoped_replace(
        text,
        "            //修改手机号",
        mobile_validation,
        mobile_validation_with_captcha,
        "mobile binding captcha",
    )

    email_retrieve_validation = """                $data = input('');
                $rule = [
                    'username|用户名' => 'require',
                ];
                $validate = new Validate($rule);
                $result = $validate->check($data);
                if (!$result) {
                    throw new \\Exception((string)$validate->getError());
                }
                $username = trim(strval($username));
"""
    email_retrieve_validation_with_captcha = """                $data = input('');
                $rule = [
                    'username|用户名' => 'require',
                ];
                $validate = new Validate($rule);
                $result = $validate->check($data);
                if (!$result) {
                    throw new \\Exception((string)$validate->getError());
                }
                if (!$this->blinCheckImageCaptcha("security", input("captcha"))) {
                    throw new \\Exception("图片验证码错误");
                }
                $username = trim(strval($username));
"""
    email_anchor = text.find("public function get_email_verification_code")
    if email_anchor < 0:
        raise RuntimeError("missing email verification function")
    text = scoped_replace(
        text,
        "            //找回密码",
        email_retrieve_validation,
        email_retrieve_validation_with_captcha,
        "email retrieve captcha",
        start_at=email_anchor,
    )

    email_binding_validation = """                $data = input('');
                $rule = [
                    'email|邮箱' => 'require|email'
                ];
                $validate = new Validate($rule);
                $result = $validate->check($data);
                if (!$result) {
                    throw new \\Exception((string)$validate->getError());
                }
                $email_info = Db::name('user')->where("appid", $this->appid)->where("email='{$email}'")->find();
"""
    email_binding_validation_with_captcha = """                $data = input('');
                $rule = [
                    'email|邮箱' => 'require|email'
                ];
                $validate = new Validate($rule);
                $result = $validate->check($data);
                if (!$result) {
                    throw new \\Exception((string)$validate->getError());
                }
                if (!$this->blinCheckImageCaptcha("security", input("captcha"))) {
                    throw new \\Exception("图片验证码错误");
                }
                $email_info = Db::name('user')->where("appid", $this->appid)->where("email='{$email}'")->find();
"""
    text = scoped_replace(
        text,
        "            //修改绑定邮箱",
        email_binding_validation,
        email_binding_validation_with_captcha,
        "email binding captcha",
    )

    text = replace_once(
        text,
        """        $user = $this->blinPaymentUser();
        $method = strtolower(trim(strval(isset($data["method"]) ? $data["method"] : input("verification_method"))));
        if (!in_array($method, ["mobile", "email"])) $this->json(0, "请选择验证方式");
""",
        """        $user = $this->blinPaymentUser();
        if (!$this->blinCheckImageCaptcha("security", input("captcha"))) {
            $this->json(0, "图片验证码错误");
        }
        $method = strtolower(trim(strval(isset($data["method"]) ? $data["method"] : input("verification_method"))));
        if (!in_array($method, ["mobile", "email"])) $this->json(0, "请选择验证方式");
""",
        "payment password retrieve captcha",
    )

    if text == before:
        print("PATCH_ALREADY_APPLIED")
        return
    backup(API)
    API.write_text(text, encoding="utf-8")
    print("PATCHED_ACCOUNT_SECURITY_IMAGE_CAPTCHA")


if __name__ == "__main__":
    main()
