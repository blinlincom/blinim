#!/usr/bin/env python3
"""Make SMS/email verification codes stable across IP/session changes."""

from datetime import datetime
from pathlib import Path
import shutil


ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"


def backup(path: Path) -> None:
    target = path.with_name(
        f"{path.name}.bak_verification_code_scope_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    shutil.copy2(path, target)
    print("BACKUP", target)


def replace_once(source: str, old: str, new: str, marker: str) -> str:
    if new in source:
        return source
    if old not in source:
        raise SystemExit(f"{marker}_NOT_FOUND")
    return source.replace(old, new, 1)


def main() -> None:
    source = API.read_text(encoding="utf-8", errors="ignore")
    original = source

    source = replace_once(
        source,
        '''                $mobile_code_cache = Cache::get($this->appid . "mobile_retrieve" . get_client_ip());
                if ($mobile_code_cache) {
                    if (time() - $mobile_code_cache["time"] < $phone_code_time) {
                        throw new \\Exception($phone_code_interval_time_f . "分钟内只能发送一次验证码");
                    }
                }
                $mobile = input("mobile");
''',
        '''                $mobile = input("mobile");
                $mobile_code_cache = Cache::get($this->appid . "mobile_retrieve" . $mobile);
                if (!$mobile_code_cache) {
                    $mobile_code_cache = Cache::get($this->appid . "mobile_retrieve" . get_client_ip());
                }
                if ($mobile_code_cache) {
                    if (time() - $mobile_code_cache["time"] < $phone_code_interval_time) {
                        throw new \\Exception($phone_code_interval_time_f . "分钟内只能发送一次验证码");
                    }
                }
''',
        "MOBILE_RETRIEVE_SEND_CACHE",
    )

    source = replace_once(
        source,
        '''                        Cache::set($this->appid . "mobile_retrieve" . get_client_ip(), ["code" => $captcha, "mobile" => $mobile, "time" => time()], $phone_code_time);
                        $this->json(1, "发送成功");
''',
        '''                        Cache::set($this->appid . "mobile_retrieve" . $mobile, ["code" => $captcha, "mobile" => $mobile, "time" => time()], $phone_code_time);
                        Cache::set($this->appid . "mobile_retrieve" . get_client_ip(), ["code" => $captcha, "mobile" => $mobile, "time" => time()], $phone_code_time);
                        $this->json(1, "发送成功");
''',
        "MOBILE_RETRIEVE_SEND_SET",
    )

    source = replace_once(
        source,
        '''                $mobile_code_cache = Cache::get($this->appid . "phone_update" . get_client_ip());
                if ($mobile_code_cache) {
                    if (time() - $mobile_code_cache["time"] < $phone_code_time) {
                        throw new \\Exception($phone_code_interval_time_f . "分钟内只能发送一次验证码");
                    }
                }
                $mobile = input("mobile");
''',
        '''                $mobile = input("mobile");
                $mobile_code_cache = Cache::get($this->appid . "phone_update" . $mobile);
                if (!$mobile_code_cache) {
                    $mobile_code_cache = Cache::get($this->appid . "phone_update" . get_client_ip());
                }
                if ($mobile_code_cache) {
                    if (time() - $mobile_code_cache["time"] < $phone_code_interval_time) {
                        throw new \\Exception($phone_code_interval_time_f . "分钟内只能发送一次验证码");
                    }
                }
''',
        "PHONE_UPDATE_SEND_CACHE",
    )

    source = replace_once(
        source,
        '''                        Cache::set($this->appid . "phone_update" . get_client_ip(), ["code" => $captcha, "mobile" => $mobile, "time" => time()], $phone_code_time);
                        $this->json(1, "发送成功");
''',
        '''                        Cache::set($this->appid . "phone_update" . $mobile, ["code" => $captcha, "mobile" => $mobile, "time" => time()], $phone_code_time);
                        Cache::set($this->appid . "phone_update" . get_client_ip(), ["code" => $captcha, "mobile" => $mobile, "time" => time()], $phone_code_time);
                        $this->json(1, "发送成功");
''',
        "PHONE_UPDATE_SEND_SET",
    )

    source = replace_once(
        source,
        '''                $email_retrieve_code_cache = Cache::get($this->appid . "email_retrieve" . get_client_ip());
                if ($email_retrieve_code_cache) {
                    if (time() - $email_retrieve_code_cache["time"] < $email_code_interval_time) {
                        throw new \\Exception("{$email_code_interval_time_f}分钟内只能发送一次验证码");
                    }
                }
                $username = input("username");
''',
        '''                $username = input("username");
                $email_retrieve_code_cache = Cache::get($this->appid . "email_retrieve" . trim(strval($username)));
                if (!$email_retrieve_code_cache) {
                    $email_retrieve_code_cache = Cache::get($this->appid . "email_retrieve" . get_client_ip());
                }
                if ($email_retrieve_code_cache) {
                    if (time() - $email_retrieve_code_cache["time"] < $email_code_interval_time) {
                        throw new \\Exception("{$email_code_interval_time_f}分钟内只能发送一次验证码");
                    }
                }
''',
        "EMAIL_RETRIEVE_SEND_CACHE",
    )

    source = replace_once(
        source,
        '''                    Cache::set($this->appid . "email_retrieve" . get_client_ip(), ["code" => $code, "email" => $email_info["email"], "time" => time()], $email_code_time);
                    $this->json(1, "发送成功");
''',
        '''                    Cache::set($this->appid . "email_retrieve" . $username, ["code" => $code, "email" => $email_info["email"], "time" => time()], $email_code_time);
                    Cache::set($this->appid . "email_retrieve" . $email_info["email"], ["code" => $code, "email" => $email_info["email"], "time" => time()], $email_code_time);
                    Cache::set($this->appid . "email_retrieve" . get_client_ip(), ["code" => $code, "email" => $email_info["email"], "time" => time()], $email_code_time);
                    $this->json(1, "发送成功");
''',
        "EMAIL_RETRIEVE_SEND_SET",
    )

    source = replace_once(
        source,
        '''                $email_update_code_cache = Cache::get($this->appid . "email_update" . get_client_ip());
                if ($email_update_code_cache) {
                    if (time() - $email_update_code_cache["time"] < $email_code_interval_time) {
                        throw new \\Exception("{$email_code_interval_time_f}分钟内只能发送一次验证码");
                    }
                }
                $email = input("email");
''',
        '''                $email = input("email");
                $email_update_code_cache = Cache::get($this->appid . "email_update" . $email);
                if (!$email_update_code_cache) {
                    $email_update_code_cache = Cache::get($this->appid . "email_update" . get_client_ip());
                }
                if ($email_update_code_cache) {
                    if (time() - $email_update_code_cache["time"] < $email_code_interval_time) {
                        throw new \\Exception("{$email_code_interval_time_f}分钟内只能发送一次验证码");
                    }
                }
''',
        "EMAIL_UPDATE_SEND_CACHE",
    )

    source = replace_once(
        source,
        '''                    Cache::set($this->appid . "email_update" . get_client_ip(), ["code" => $code, "email" => $email, "time" => time()], $email_code_time);
                    $this->json(1, "发送成功");
''',
        '''                    Cache::set($this->appid . "email_update" . $email, ["code" => $code, "email" => $email, "time" => time()], $email_code_time);
                    Cache::set($this->appid . "email_update" . get_client_ip(), ["code" => $code, "email" => $email, "time" => time()], $email_code_time);
                    $this->json(1, "发送成功");
''',
        "EMAIL_UPDATE_SEND_SET",
    )

    source = replace_once(
        source,
        '''        if ($type == 1) {
            $retrieve_email_code_cache = Cache::get($this->appid . "email_retrieve" . get_client_ip());
            $email_code_time = $this->blinAppSystemValue("email_code_time", 300);
            if ($retrieve_email_code_cache) {
                if (time() - $retrieve_email_code_cache["time"] > $email_code_time) {
                    $this->json(0, "验证码已过期");
                }
                if ($captcha != $retrieve_email_code_cache["code"]) {
                    $this->json(0, "验证码不正确");
                }
                $userinfo = Db::name("user")->where("email", $retrieve_email_code_cache["email"])->where('appid', $this->appid)->find();
            } else {
                $this->json(0, "请先发送验证码");
            }
        }
''',
        '''        if ($type == 1) {
            $retrieve_email_code_cache = Cache::get($this->appid . "email_retrieve" . $username);
            if (!$retrieve_email_code_cache && isset($userinfo["email"])) {
                $retrieve_email_code_cache = Cache::get($this->appid . "email_retrieve" . $userinfo["email"]);
            }
            if (!$retrieve_email_code_cache) {
                $retrieve_email_code_cache = Cache::get($this->appid . "email_retrieve" . get_client_ip());
            }
            $email_code_time = $this->blinAppSystemValue("email_code_time", 300);
            if ($retrieve_email_code_cache) {
                if (time() - $retrieve_email_code_cache["time"] > $email_code_time) {
                    $this->json(0, "验证码已过期");
                }
                if ($captcha != $retrieve_email_code_cache["code"]) {
                    $this->json(0, "验证码不正确");
                }
                if (isset($userinfo["email"]) && $userinfo["email"] != $retrieve_email_code_cache["email"]) {
                    $this->json(0, "验证码不正确");
                }
            } else {
                $this->json(0, "请先发送验证码");
            }
        }
''',
        "RETRIEVE_PASSWORD_EMAIL_CHECK",
    )

    source = replace_once(
        source,
        '''        if ($type == 2) {
            $mobile_code_cache = Cache::get($this->appid . "mobile_retrieve" . get_client_ip());
            $phone_code_time = $this->blinAppSystemValue("phone_code_time", 300);
            if ($mobile_code_cache) {
                if (time() - $mobile_code_cache["time"] > $phone_code_time) {
                    $this->json(0, "短信验证码已过期");
                }
                if ($captcha != $mobile_code_cache["code"]) {
                    $this->json(0, "短信验证码不正确");
                }
                $userinfo = Db::name("user")->where("mobile", $mobile_code_cache["mobile"])->where('appid', $this->appid)->find();
            } else {
                $this->json(0, "请先发送短信验证码");
            }
        }
''',
        '''        if ($type == 2) {
            $mobile_code_cache = false;
            if (isset($userinfo["mobile"]) && $userinfo["mobile"] !== "") {
                $mobile_code_cache = Cache::get($this->appid . "mobile_retrieve" . $userinfo["mobile"]);
            }
            if (!$mobile_code_cache) {
                $mobile_code_cache = Cache::get($this->appid . "mobile_retrieve" . get_client_ip());
            }
            $phone_code_time = $this->blinAppSystemValue("phone_code_time", 300);
            if ($mobile_code_cache) {
                if (time() - $mobile_code_cache["time"] > $phone_code_time) {
                    $this->json(0, "短信验证码已过期");
                }
                if ($captcha != $mobile_code_cache["code"]) {
                    $this->json(0, "短信验证码不正确");
                }
                if (!isset($userinfo["mobile"]) || $userinfo["mobile"] != $mobile_code_cache["mobile"]) {
                    $this->json(0, "短信验证码不正确");
                }
            } else {
                $this->json(0, "请先发送短信验证码");
            }
        }
''',
        "RETRIEVE_PASSWORD_MOBILE_CHECK",
    )

    source = replace_once(
        source,
        '''        Cache::rm($this->appid . "mobile_retrieve" . get_client_ip());
        Cache::rm($this->appid . "email_retrieve" . get_client_ip());
''',
        '''        if (isset($userinfo["mobile"]) && $userinfo["mobile"] !== "") {
            Cache::rm($this->appid . "mobile_retrieve" . $userinfo["mobile"]);
        }
        if (isset($userinfo["email"]) && $userinfo["email"] !== "") {
            Cache::rm($this->appid . "email_retrieve" . $userinfo["email"]);
        }
        Cache::rm($this->appid . "email_retrieve" . $username);
        Cache::rm($this->appid . "mobile_retrieve" . get_client_ip());
        Cache::rm($this->appid . "email_retrieve" . get_client_ip());
''',
        "RETRIEVE_PASSWORD_CACHE_RM",
    )

    source = replace_once(
        source,
        '''        $email_update_code_cache = Cache::get($this->appid . "email_update" . get_client_ip());
        $email_code_time = $this->blinAppSystemValue("email_code_time", 300);
''',
        '''        $email_update_code_cache = Cache::get($this->appid . "email_update" . $data["email"]);
        if (!$email_update_code_cache) {
            $email_update_code_cache = Cache::get($this->appid . "email_update" . get_client_ip());
        }
        $email_code_time = $this->blinAppSystemValue("email_code_time", 300);
''',
        "MODIFY_EMAIL_CACHE_GET",
    )

    source = replace_once(
        source,
        '''            if ($email_update_code_cache["code"] != $data["code"]) {
                $this->json(0, "验证码错误");
            }
            $user_all_info = $this->user_info;
''',
        '''            if ($email_update_code_cache["code"] != $data["code"]) {
                $this->json(0, "验证码错误");
            }
            if ($email_update_code_cache["email"] != $data["email"]) {
                $this->json(0, "验证码错误");
            }
            $user_all_info = $this->user_info;
''',
        "MODIFY_EMAIL_CACHE_MATCH",
    )

    source = replace_once(
        source,
        '''            Cache::rm($this->appid . "email_update" . get_client_ip());
            $this->json(1, "修改成功");
''',
        '''            Cache::rm($this->appid . "email_update" . $data["email"]);
            Cache::rm($this->appid . "email_update" . get_client_ip());
            $this->json(1, "修改成功");
''',
        "MODIFY_EMAIL_CACHE_RM",
    )

    source = replace_once(
        source,
        '''        $phone_update_code_cache = Cache::get($this->appid . "phone_update" . get_client_ip());
        $phone_code_time = $this->blinAppSystemValue("phone_code_time", 300);
''',
        '''        $phone_update_code_cache = Cache::get($this->appid . "phone_update" . $data["phone"]);
        if (!$phone_update_code_cache) {
            $phone_update_code_cache = Cache::get($this->appid . "phone_update" . get_client_ip());
        }
        $phone_code_time = $this->blinAppSystemValue("phone_code_time", 300);
''',
        "MODIFY_PHONE_CACHE_GET",
    )

    source = replace_once(
        source,
        '''            if ($phone_update_code_cache["code"] != $data["code"]) {
                $this->json(0, "验证码错误");
            }
            $user_all_info = $this->user_info;
''',
        '''            if ($phone_update_code_cache["code"] != $data["code"]) {
                $this->json(0, "验证码错误");
            }
            if ($phone_update_code_cache["mobile"] != $data["phone"]) {
                $this->json(0, "验证码错误");
            }
            $user_all_info = $this->user_info;
''',
        "MODIFY_PHONE_CACHE_MATCH",
    )

    source = replace_once(
        source,
        '''            Cache::rm($this->appid . "phone_update" . get_client_ip());
            $this->json(1, "修改成功");
''',
        '''            Cache::rm($this->appid . "phone_update" . $data["phone"]);
            Cache::rm($this->appid . "phone_update" . get_client_ip());
            $this->json(1, "修改成功");
''',
        "MODIFY_PHONE_CACHE_RM",
    )

    if source == original:
        print("NO_CHANGE", API)
        return
    backup(API)
    API.write_text(source, encoding="utf-8")
    print("PATCHED", API)


if __name__ == "__main__":
    main()
