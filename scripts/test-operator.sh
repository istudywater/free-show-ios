#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/freeshow-operator-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library -swift-version 6 -module-cache-path "$test_dir/cache" \
    FreeShowController/Core/*.swift FreeShowController/Core/Networking/*.swift \
    FreeShowController/Core/Persistence/ConnectionPreferences.swift \
    FreeShowController/Services/*.swift FreeShowController/Features/Scripture/ScriptureState.swift \
    FreeShowController/Features/Operator/OperatorStore.swift \
    Tests/OperatorTests.swift -o "$test_dir/operator-tests"
"$test_dir/operator-tests"
