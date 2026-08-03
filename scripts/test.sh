#!/bin/bash
# Run the test suite.
#
# With Command Line Tools only (no Xcode), swift-testing ships as
# Testing.framework outside the default search paths, and the
# Foundation/Testing cross-import overlay fails to resolve — so pass the
# framework paths explicitly and disable cross-import overlays.
set -euo pipefail
cd "$(dirname "$0")/.."

DEV_DIR="$(xcode-select -p)"
FW="$DEV_DIR/Library/Developer/Frameworks"
if [[ "$DEV_DIR" == *CommandLineTools* && -d "$FW/Testing.framework" ]]; then
  exec swift test \
    -Xswiftc -F -Xswiftc "$FW" \
    -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
    -Xlinker -F"$FW" \
    -Xlinker -rpath -Xlinker "$FW" \
    "$@"
fi
exec swift test "$@"
