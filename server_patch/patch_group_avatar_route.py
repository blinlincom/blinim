from pathlib import Path


path = Path("/www/wwwroot/blinlin/route/route.php")
bak = path.with_name(path.name + ".bak_group_avatar_route_20260621")
if not bak.exists():
    bak.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")

text = path.read_text(encoding="utf-8")
old = "'join_im_group_by_qr','join_group_by_qr'"
new = "'join_im_group_by_qr','join_group_by_qr','generate_im_group_avatar'"
if new not in text:
    if old not in text:
        raise SystemExit("route marker not found")
    text = text.replace(old, new, 1)
path.write_text(text, encoding="utf-8")
print("patched group avatar route")
