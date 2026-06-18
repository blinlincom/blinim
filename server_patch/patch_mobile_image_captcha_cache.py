#!/usr/bin/env python3
from pathlib import Path

ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"


def backup(path: Path) -> str:
    dst = path.with_name("Api.php.bak_mobile_captcha_cache_20260618")
    if not dst.exists():
        dst.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
    return str(dst)


HELPER = r'''
    private function blinCreateImageCaptcha($scope)
    {
        $key = $this->blinImageCaptchaKey($scope);
        $chars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
        $code = '';
        for ($i = 0; $i < 4; $i++) {
            $code .= $chars[mt_rand(0, strlen($chars) - 1)];
        }
        Cache::set($key, strtoupper($code), 120);

        $width = 120;
        $height = 42;
        $image = imagecreate($width, $height);
        imagecolorallocate($image, 248, 250, 252);
        $line = imagecolorallocate($image, 203, 213, 225);
        $noise = imagecolorallocate($image, 148, 163, 184);
        $ink = imagecolorallocate($image, 51, 65, 85);
        for ($i = 0; $i < 4; $i++) {
            imageline($image, mt_rand(0, $width), mt_rand(0, $height), mt_rand(0, $width), mt_rand(0, $height), $line);
        }
        for ($i = 0; $i < 60; $i++) {
            imagesetpixel($image, mt_rand(0, $width - 1), mt_rand(0, $height - 1), $noise);
        }
        for ($i = 0; $i < strlen($code); $i++) {
            imagestring($image, 5, 14 + $i * 25 + mt_rand(-2, 2), 12 + mt_rand(-3, 3), $code[$i], $ink);
        }

        ob_start();
        imagepng($image);
        $content = ob_get_clean();
        imagedestroy($image);
        return response($content, 200, ['Content-Length' => strlen($content)])->contentType('image/png');
    }

'''


def main() -> None:
    original = API.read_text(encoding="utf-8")
    source = original

    if "private function blinCreateImageCaptcha($scope)" not in source:
        marker = "    //用户登录\n"
        if marker not in source:
            raise SystemExit("login_marker_not_found")
        source = source.replace(marker, HELPER + marker, 1)

    source = source.replace(
        '''                $key = $this->blinImageCaptchaKey("login");
                $captcha = new Captcha(['expire' => 120]);
                return $captcha->entry($key);
''',
        '''                return $this->blinCreateImageCaptcha("login");
''',
    )
    source = source.replace(
        '''                $key = $this->blinImageCaptchaKey("register");
                $captcha = new Captcha(['expire' => 120]);
                return $captcha->entry($key);
''',
        '''                return $this->blinCreateImageCaptcha("register");
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
