#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! xcodebuild -version; then
    printf '%s\n' 'Full Xcode with iOS platform support is required.' >&2
    printf '%s\n' 'If installed, set DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer and retry.' >&2
    exit 1
fi
# Pass "platform=iOS Simulator,id=<UDID>" to build for a specific installed simulator.
destination="${1:-generic/platform=iOS Simulator}"
xcodebuild -project FreeShowRemote.xcodeproj \
    -scheme FreeShowRemote -configuration Debug \
    -destination "$destination" \
    -derivedDataPath build/DerivedData \
    -clonedSourcePackagesDirPath build/SourcePackages \
    CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO build
