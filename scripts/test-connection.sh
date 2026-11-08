#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/freeshow-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library -swift-version 6 -module-cache-path "$test_dir/cache" \
    FreeShowController/Core/*.swift FreeShowController/Core/Networking/*.swift \
    FreeShowController/Services/*.swift FreeShowController/App/AppState.swift \
    Tests/ConnectionTests.swift -o "$test_dir/connection-tests"
"$test_dir/connection-tests"
