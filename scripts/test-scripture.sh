#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/freeshow-scripture-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library -swift-version 6 -module-cache-path "$test_dir/cache" \
    FreeShowController/Core/*.swift FreeShowController/Core/Networking/*.swift \
    FreeShowController/Services/*.swift FreeShowController/Features/Scripture/ScriptureState.swift \
    Tests/ScriptureTests.swift -o "$test_dir/scripture-tests"
"$test_dir/scripture-tests"
