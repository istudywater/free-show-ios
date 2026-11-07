#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/freeshow-operator-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library -swift-version 6 -module-cache-path "$test_dir/cache" \
    FreeShowRemote/Core/*.swift FreeShowRemote/Core/Networking/*.swift \
    FreeShowRemote/Core/Persistence/ConnectionPreferences.swift \
    FreeShowRemote/Services/*.swift FreeShowRemote/Features/Scripture/ScriptureState.swift \
    FreeShowRemote/Features/Operator/OperatorStore.swift \
    Tests/OperatorTests.swift -o "$test_dir/operator-tests"
"$test_dir/operator-tests"
