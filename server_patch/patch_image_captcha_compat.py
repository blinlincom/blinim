#!/usr/bin/env python3
import re
from pathlib import Path

ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"


def backup(path: Path) -> str:
    dst = path.with_name(f"{path.name}.bak_image_captcha_compat_20260617")
    if not dst.exists():
        dst.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
    return str(dst)


HELPERS = r'''
    private function blinImageCaptchaKey($scope)
    {
        $raw = input("captcha_key");
        if ($raw === null || $raw === "") {
            $raw = input("captcha_id");
        }
        if ($raw === null || $raw === "") {
            $raw = input("verify_key");
        }
        if ($raw === null || $raw === "") {
            $raw = input("captchaKey");
        }
        $raw = trim(strval($raw));
        if ($raw !== "" && preg_match('/^[A-Za-z0-9_\-:\.]{6,180}$/', $raw)) {
            return $this->appid . $scope . "_" . $raw;
        }
        return $this->appid . $scope . get_client_ip();
    }

    private function blinCheckImageCaptcha($scope, $captcha)
    {
        $key = $this->blinImageCaptchaKey($scope);
        $captcha = strtoupper(trim(strval($captcha)));
        if ($captcha === "") {
            return false;
        }
        $cacheCode = Cache::get($key);
        if ($cacheCode !== null && $cacheCode !== false && strtoupper(trim(strval($cacheCode))) === $captcha) {
            Cache::rm($key);
            return true;
        }
        try {
            $checker = new Captcha(['expire' => 120]);
            if ($checker->check($captcha, $key)) {
                Cache::rm($key);
                return true;
            }
        } catch (\Exception $e) {}
        Cache::rm($key);
        return false;
    }

'''

HELPER_PATTERN = re.compile(
    r'\n    private function blinImageCaptchaKey\(\$scope\)\n'
    r'    \{.*?\n'
    r'    \}\n\n'
    r'    private function blinCheckImageCaptcha\(\$scope, \$captcha\)\n'
    r'    \{.*?\n'
    r'    \}\n\n',
    re.S,
)


def main() -> None:
    original = API.read_text(encoding="utf-8")
    source = original

    if "private function blinImageCaptchaKey(" in source:
        source = HELPER_PATTERN.sub(HELPERS, source, count=1)
    else:
        marker = "    //用户登录\n"
        if marker not in source:
            raise SystemExit("login_marker_not_found")
        source = source.replace(marker, HELPERS + marker, 1)

    source = source.replace(
        '''        //判断是否开启图片验证码
        if ($this->app_info["login_configuration"]["login_code_switch"] == 1) {
            $captcha_code = Cache::get($this->appid . "login" . get_client_ip());
            if ($captcha_code != $captcha) {
                Cache::rm($this->appid . "login" . get_client_ip());
                $this->json(0, '图片验证码错误');
            }
        }
''',
        '''        //判断是否开启图片验证码
        if ($this->app_info["login_configuration"]["login_code_switch"] == 1) {
            if (!$this->blinCheckImageCaptcha("login", $captcha)) {
                $this->json(0, '图片验证码错误');
            }
        }
''',
    )

    source = source.replace(
        '''        //判断图片验证码是否正确
        if ($this->app_info["login_configuration"]["login_code_switch"] == 1) {
            $captcha_code = Cache::get($this->appid . "login" . get_client_ip());
            if ($captcha_code != $captcha) {
                Cache::rm($this->appid . "login" . get_client_ip());
                $this->json(0, '图片验证码错误');
            }
        }
''',
        '''        //判断图片验证码是否正确
        if ($this->app_info["login_configuration"]["login_code_switch"] == 1) {
            if (!$this->blinCheckImageCaptcha("login", $captcha)) {
                $this->json(0, '图片验证码错误');
            }
        }
''',
    )

    source = source.replace(
        '''            $captcha_code = Cache::get($this->appid . "register" . get_client_ip());
            if ($captcha_code != $captcha) {
                Cache::rm($this->appid . "register" . get_client_ip());
                $this->json(0, '验证码错误');
            }
''',
        '''            if (!$this->blinCheckImageCaptcha("register", $captcha)) {
                $this->json(0, '验证码错误');
            }
''',
    )

    source = source.replace(
        '''                $captcha = new Captcha(['expire' => 120]);
                return $captcha->entry($this->appid . "login" . get_client_ip());
''',
        '''                $key = $this->blinImageCaptchaKey("login");
                $captcha = new Captcha(['expire' => 120]);
                return $captcha->entry($key);
''',
    )

    source = source.replace(
        '''                $captcha = new Captcha(['expire' => 120]);
                return $captcha->entry($this->appid . "register" . get_client_ip());
''',
        '''                $key = $this->blinImageCaptchaKey("register");
                $captcha = new Captcha(['expire' => 120]);
                return $captcha->entry($key);
''',
    )

    if source == original:
        print("NO_CHANGE")
        return
    print(f"BACKUP {backup(API)}")
    API.write_text(source, encoding="utf-8")
    print(f"PATCHED {API}")


if __name__ == "__main__":
    main()
