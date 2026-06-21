from pathlib import Path


path = Path("/www/wwwroot/blinlin/application/api/controller/Api.php")
text = path.read_text(encoding="utf-8")
start_marker = '            $urlPath = parse_url($avatar, PHP_URL_PATH);'
end_marker = '            $context = stream_context_create(["http"=>["timeout"=>3], "https"=>["timeout"=>3]]);'
start = text.find(start_marker)
end = text.find(end_marker, start)
if start == -1 or end == -1:
    raise SystemExit("avatar url block not found")
replacement = r'''            $urlPath = parse_url($avatar, PHP_URL_PATH);
            if ($urlPath) {
                $local = \think\facade\Env::get("root_path") . "public" . $urlPath;
                if (is_file($local)) {
                    $raw = @file_get_contents($local);
                    if ($raw) return @imagecreatefromstring($raw);
                }
            }
'''
text = text[:start] + replacement + text[end:]
path.write_text(text, encoding="utf-8")
print("fixed avatar url block")
