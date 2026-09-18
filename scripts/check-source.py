#!/usr/bin/env python3
"""Packaging and configuration consistency checks, NOT macOS API type checking."""
from pathlib import Path
import plistlib
import re
import sys

root = Path(__file__).resolve().parent.parent
errors = []
for name, executable in [("Info.plist", "Transom"), ("LabInfo.plist", "TransomLab")]:
    try:
        with (root / "Resources" / name).open("rb") as handle:
            info = plistlib.load(handle)
        if info.get("CFBundleExecutable") != executable:
            errors.append(f"Unexpected executable in {name}")
        if name == "Info.plist" and info.get("LSUIElement") is not True:
            errors.append("Transom must be an accessory app")
        if name == "Info.plist" and "en" not in info.get("CFBundleLocalizations", []):
            errors.append("Info.plist must declare en in CFBundleLocalizations")
    except Exception as error:
        errors.append(f"{name}: {error}")
required = ["Package.swift", "README.md", "README.ja.md", "AGENTS.md", "docs/HANDOFF.md", "docs/REVIEW.md",
            "docs/ACCEPTANCE.md", "docs/VALIDATION.md", "docs/SOURCES.md", "LICENSE"]
for name in required:
    if not (root / name).is_file(): errors.append(f"Missing file: {name}")
# AX synchronous IPC belongs in Accessibility/, not in AppKit rendering/event callbacks.
for directory in ["App", "Header", "Menu", "WindowServer"]:
    for path in (root / "Sources/TransomApp" / directory).glob("*.swift"):
        if re.search(r"\bAXUIElement(?:CopyAttributeValue|PerformAction|SetAttributeValue)\s*\(", path.read_text()):
            errors.append(f"Synchronous AX IPC outside worker boundary: {path.relative_to(root)}")
# User-facing Japanese text must go through NSLocalizedString and have an entry in
# en.lproj/Localizable.strings. Raw CJK literals are allowed only in Logger calls or in
# this allowlist of non-displayed strings (e.g. menu-title detection lists).
localized_keys = set()
cjk_literal = re.compile(r'"((?:[^"\\]|\\.)*[ぁ-んァ-ヶー一-龥々〆〤](?:[^"\\]|\\.)*)"')
logger_call = re.compile(r"\bLogger\b|\.(?:info|debug|notice|error|warning|fault)\(")
allowed_raw_cjk = {"アップル"}  # AXMenuStore's Apple-menu detection list, not shown to the user.
for path in (root / "Sources/TransomApp").rglob("*.swift"):
    text = path.read_text()
    localized_keys.update(re.findall(r'NSLocalizedString\(\s*"((?:[^"\\]|\\.)*)"', text))
    for number, line in enumerate(text.splitlines(), 1):
        code = line.split("//", 1)[0]
        if "NSLocalizedString" in code or logger_call.search(code):
            continue
        for literal in cjk_literal.findall(code):
            if literal not in allowed_raw_cjk:
                errors.append(f"Japanese UI text outside NSLocalizedString: {path.relative_to(root)}:{number}")
strings_path = root / "Resources/en.lproj/Localizable.strings"
try:
    english = set(re.findall(r'^\s*"((?:[^"\\]|\\.)*)"\s*=', strings_path.read_text(), re.M))
    for key in sorted(localized_keys - english):
        errors.append(f"Missing English translation in {strings_path.relative_to(root)}: {key}")
except OSError as error:
    errors.append(f"{strings_path.relative_to(root)}: {error}")
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print("Source layout and plist checks passed (not an AppKit compiler check).")
