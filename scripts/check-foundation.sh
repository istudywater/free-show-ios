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
    FreeShowRemote/Core/Networking/*.swift \
    FreeShowRemote/Core/Persistence/*.swift \
    FreeShowRemote/Core/Discovery/*.swift \
    FreeShowRemote/Features/Operator/OperatorStore.swift \
    FreeShowRemote/Services/*.swift \
    FreeShowRemote/App/AppState.swift \
    FreeShowRemote/Features/Scripture/ScriptureState.swift
printf '%s\n' 'Core/service/state checks passed (host SDK; UI requires iPad build).'
