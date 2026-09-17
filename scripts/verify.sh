#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
for script in scripts/*.sh; do bash -n "$script"; done
python3 scripts/check-source.py
if [[ "$(uname -s)" == "Darwin" ]]; then
  xcrun swift build --product WindowBar
  xcrun swift build --product WindowBarLab
  # Tests use Swift Testing (Command Line Tools ship Testing.framework but no XCTest).
  # Without Xcode, the default build system does not pass the Testing macro plugin path
  # to the frontend, so it is given explicitly when the plugin directory exists.
  TEST_ARGS=()
  TOOLCHAIN_PLUGINS="$(dirname "$(dirname "$(xcrun --find swift)")")/lib/swift/host/plugins/testing"
  if [[ -d "$TOOLCHAIN_PLUGINS" ]]; then TEST_ARGS+=(-Xswiftc -plugin-path -Xswiftc "$TOOLCHAIN_PLUGINS"); fi
  xcrun swift test "${TEST_ARGS[@]}"
  echo "macOS build and unit tests completed. GUI/AX/WindowServer still require manual tests."
else
  swift test
  while IFS= read -r source; do swiftc -frontend -parse "$source"; done < <(find Sources/WindowBarApp Sources/WindowBarLab -name '*.swift' -print)
  echo "Linux validation: Core unit tests and Swift syntax only. NO macOS type-check/link/GUI test."
fi
