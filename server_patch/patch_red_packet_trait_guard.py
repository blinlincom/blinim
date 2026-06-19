#!/usr/bin/env python3
"""Block red-packet payload spoofing in the routed IM group trait."""
from datetime import datetime
from pathlib import Path


ROOT = Path("/www/wwwroot/blinlin")
TRAIT = ROOT / "application/api/controller/traits/ImApiTrait.php"


def backup(path: Path, suffix: str) -> str:
    target = path.with_name(
        f"{path.name}.bak_{suffix}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    target.write_text(path.read_text(errors="ignore"))
    return str(target)


GUARD = '''        $rawMsgType = isset($data['msg_type']) ? strval($data['msg_type']) : (isset($_POST['msg_type']) ? strval($_POST['msg_type']) : '');
        if (trim($rawMsgType) === 'red_packet' || preg_match('/"msg_type"\\\\s*:\\\\s*"red_packet"/', strval($payloadRaw))) {
            $this->json(0, '群普通消息接口不能发送红包，请使用群红包接口');
        }
'''


def main() -> None:
    source = TRAIT.read_text(errors="ignore")
    original = source
    if "群普通消息接口不能发送红包，请使用群红包接口" not in source:
        marker = '''        $payloadRaw = isset($data['im_payload']) ? strval($data['im_payload']) : (isset($data['payload']) ? strval($data['payload']) : '');
        $payload = $payloadRaw ? json_decode($payloadRaw, true) : null;
'''
        if marker not in source:
            raise SystemExit("TRAIT_GROUP_PAYLOAD_MARKER_NOT_FOUND")
        source = source.replace(marker, marker + GUARD, 1)
    if source == original:
        print("RED_PACKET_TRAIT_GUARD_ALREADY_PRESENT")
        return
    print("PATCH_ImApiTrait.php_BACKUP", backup(TRAIT, "red_packet_trait_guard"))
    TRAIT.write_text(source)
    print("PATCHED_RED_PACKET_TRAIT_GUARD")


if __name__ == "__main__":
    main()
