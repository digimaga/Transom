#!/bin/bash
# Creates a local .app without XcodeGen/Homebrew or third-party package dependencies.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script needs macOS and a Swift 6 toolchain (Xcode or Command Line Tools)." >&2
  exit 2
fi
CONFIG=debug
PRODUCT=WindowBar
PLIST=Resources/Info.plist
for argument in "$@"; do
  case "$argument" in
    --release) CONFIG=release ;;
    --debug) CONFIG=debug ;;
    --lab) PRODUCT=WindowBarLab; PLIST=Resources/LabInfo.plist ;;
    *) echo "Usage: bash scripts/build-app.sh [--debug|--release] [--lab]" >&2; exit 2 ;;
  esac
done
xcrun --find swift >/dev/null
xcrun swift --version
ARGS=(-c "$CONFIG" --product "$PRODUCT")
if [[ -n "${ARCH:-}" ]]; then ARGS+=(--arch "$ARCH"); fi
xcrun swift build "${ARGS[@]}"
BIN_PATH="$(xcrun swift build "${ARGS[@]}" --show-bin-path)"
APP="$ROOT/dist/$PRODUCT.app"
STAGING="$ROOT/dist/.${PRODUCT}.staging.app"
mkdir -p "$ROOT/dist"
# Fixed project-owned staging path only. No system apps or user directories are removed.
rm -rf "$STAGING"
mkdir -p "$STAGING/Contents/MacOS"
cp "$BIN_PATH/$PRODUCT" "$STAGING/Contents/MacOS/$PRODUCT"
cp "$PLIST" "$STAGING/Contents/Info.plist"
printf 'APPL????' > "$STAGING/Contents/PkgInfo"
/usr/bin/plutil -lint "$STAGING/Contents/Info.plist"
SIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
SIGN_ARGS=(--force --sign "$SIGN_IDENTITY" --options runtime)
if [[ "$SIGN_IDENTITY" != "-" ]]; then SIGN_ARGS+=(--timestamp); fi
/usr/bin/codesign "${SIGN_ARGS[@]}" "$STAGING"
/usr/bin/codesign --verify --strict --verbose=2 "$STAGING"
# Replacing this fixed output is intentional. Quit any running old build first.
rm -rf "$APP"
mv "$STAGING" "$APP"
echo ""
echo "Built: $APP"
echo "Launch: open \"$APP\""
echo "The ad-hoc signature is for local development, NOT Apple notarization."
