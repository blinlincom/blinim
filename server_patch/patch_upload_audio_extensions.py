#!/usr/bin/env python3
"""Allow IM voice audio extensions in backend upload config."""
from datetime import datetime
from pathlib import Path


ROOT = Path("/www/wwwroot/blinlin")
UPLOAD_CONFIG = ROOT / "config/upload.php"
AUDIO_EXTENSIONS = ["m4a", "aac", "mp3", "wav", "amr", "3gp", "ogg", "opus"]


def backup(path: Path) -> Path:
    target = path.with_name(
        f"{path.name}.bak_voice_audio_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    target.write_text(path.read_text(errors="ignore"))
    return target


def main() -> None:
    source = UPLOAD_CONFIG.read_text(errors="ignore")
    marker = "'file_extension' => '"
    start = source.find(marker)
    if start == -1:
        raise SystemExit("UPLOAD_EXTENSION_MARKER_NOT_FOUND")
    start += len(marker)
    end = source.find("'", start)
    if end == -1:
        raise SystemExit("UPLOAD_EXTENSION_VALUE_NOT_FOUND")

    current = [item.strip().lower() for item in source[start:end].split(",") if item.strip()]
    merged = current[:]
    for ext in AUDIO_EXTENSIONS:
        if ext not in merged:
            merged.append(ext)

    if merged == current:
        print("ALREADY_PATCHED", UPLOAD_CONFIG)
        return

    updated = source[:start] + ",".join(merged) + source[end:]
    backup_path = backup(UPLOAD_CONFIG)
    UPLOAD_CONFIG.write_text(updated)
    print("PATCHED", UPLOAD_CONFIG)
    print("BACKUP", backup_path)


if __name__ == "__main__":
    main()
