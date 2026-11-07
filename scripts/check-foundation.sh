#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
plutil -lint FreeShowRemote.xcodeproj/project.pbxproj
python3 scripts/check-project.py
module_cache="$(mktemp -d "${TMPDIR:-/tmp}/freeshow-module-cache.XXXXXX")"
trap 'rm -rf "$module_cache"' EXIT
# Host-SDK typecheck only: this does not replace an iPadOS build or simulator launch.
swiftc -typecheck -parse-as-library -swift-version 6 \
    -module-cache-path "$module_cache" \
    FreeShowRemote/Core/*.swift \
    FreeShowRemote/Services/*.swift \
    FreeShowRemote/App/*.swift \
    FreeShowRemote/Features/Foundation/*.swift
printf '%s\n' 'Foundation source checks passed (host SDK; iPad build still required).'
