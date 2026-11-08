#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
plutil -lint FreeShowController.xcodeproj/project.pbxproj
python3 scripts/check-project.py
module_cache="$(mktemp -d "${TMPDIR:-/tmp}/freeshow-module-cache.XXXXXX")"
trap 'rm -rf "$module_cache"' EXIT
# Host-SDK typecheck only: this does not replace an iPadOS build or simulator launch.
swiftc -typecheck -parse-as-library -swift-version 6 \
    -module-cache-path "$module_cache" \
    FreeShowController/Core/*.swift \
    FreeShowController/Core/Networking/*.swift \
    FreeShowController/Core/Persistence/*.swift \
    FreeShowController/Core/Discovery/*.swift \
    FreeShowController/Features/Operator/OperatorStore.swift \
    FreeShowController/Services/*.swift \
    FreeShowController/App/AppState.swift \
    FreeShowController/Features/Scripture/ScriptureState.swift
printf '%s\n' 'Core/service/state checks passed (host SDK; UI requires iPad build).'
