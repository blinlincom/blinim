#!/usr/bin/env python3
"""Compatibility wrapper for the current chat history clear implementation."""

from pathlib import Path
import runpy


patch = Path(__file__).with_name("patch_clear_chat_scope.py")
if not patch.exists():
    raise SystemExit("patch_clear_chat_scope.py not found")
runpy.run_path(str(patch), run_name="__main__")
