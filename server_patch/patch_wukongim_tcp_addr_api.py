#!/usr/bin/env python3
"""Patch ThinkPHP Api.php get_im_connect_info for WuKongIM Flutter SDK 1.7.9.

Latest Flutter SDK requires IM TCP address (IP:PORT) via Options.getAddr.
This patch adds tcp_addr/addr/im_addr=139.196.166.181:5100 to response data and
keeps business uid/token unchanged. It intentionally does not rely on old ws_addr.
"""
from pathlib import Path
import re

p = Path('/www/wwwroot/blinlin/application/api/controller/Api.php')
s = p.read_text(encoding='utf-8')

# Insert tcp address fields into common get_im_connect_info response arrays.
# Safe strategy: after any ws_addr assignment inside Api.php, add explicit TCP fields
# if not already present. This keeps existing web clients working server-side while
# latest Flutter client only consumes tcp_addr/addr/im_addr.
if "'tcp_addr'" not in s and '"tcp_addr"' not in s:
    s = re.sub(
        r"((['\"]ws_addr['\"]\s*=>\s*[^,\n]+,?))",
        r"\1\n            'tcp_addr' => '139.196.166.181:5100',\n            'addr' => '139.196.166.181:5100',\n            'im_addr' => '139.196.166.181:5100',",
        s,
        count=1,
    )

# If the method did not contain ws_addr in array form, add fields near token/uid response.
if "'tcp_addr'" not in s and '"tcp_addr"' not in s:
    s = re.sub(
        r"((['\"]token['\"]\s*=>\s*\$[^,\n]+,?))",
        r"\1\n            'tcp_addr' => '139.196.166.181:5100',\n            'addr' => '139.196.166.181:5100',\n            'im_addr' => '139.196.166.181:5100',",
        s,
        count=1,
    )

if "'tcp_addr'" not in s and '"tcp_addr"' not in s:
    raise SystemExit('Could not locate get_im_connect_info response insertion point')

p.write_text(s, encoding='utf-8')
print('PATCH_OK tcp_addr=139.196.166.181:5100')
