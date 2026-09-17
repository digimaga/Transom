#!/usr/bin/env python3
"""Packaging and configuration consistency checks, NOT macOS API type checking."""
from pathlib import Path
import plistlib
import re
import sys

root = Path(__file__).resolve().parent.parent
errors = []
for name, executable in [("Info.plist", "WindowBar"), ("LabInfo.plist", "WindowBarLab")]:
    try:
        with (root / "Resources" / name).open("rb") as handle:
            info = plistlib.load(handle)
        if info.get("CFBundleExecutable") != executable:
            errors.append(f"Unexpected executable in {name}")
        if name == "Info.plist" and info.get("LSUIElement") is not True:
            errors.append("WindowBar must be an accessory app")
    except Exception as error:
        errors.append(f"{name}: {error}")
required = ["Package.swift", "README.md", "AGENTS.md", "docs/HANDOFF.md", "docs/REVIEW.md",
            "docs/ACCEPTANCE.md", "docs/VALIDATION.md", "docs/SOURCES.md", "LICENSE"]
for name in required:
    if not (root / name).is_file(): errors.append(f"Missing file: {name}")
# AX synchronous IPC belongs in Accessibility/, not in AppKit rendering/event callbacks.
for directory in ["App", "Header", "Menu", "WindowServer"]:
    for path in (root / "Sources/WindowBarApp" / directory).glob("*.swift"):
        if re.search(r"\bAXUIElement(?:CopyAttributeValue|PerformAction|SetAttributeValue)\s*\(", path.read_text()):
            errors.append(f"Synchronous AX IPC outside worker boundary: {path.relative_to(root)}")
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print("Source layout and plist checks passed (not an AppKit compiler check).")
