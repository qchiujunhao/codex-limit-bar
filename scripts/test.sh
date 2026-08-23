#!/bin/zsh
set -euo pipefail

SCRIPT_DIRECTORY=${0:A:h}
PROJECT_DIRECTORY=${SCRIPT_DIRECTORY:h}
TEST_BUILD_DIRECTORY="${PROJECT_DIRECTORY}/build/tests"
MODULE_CACHE_DIRECTORY="${PROJECT_DIRECTORY}/build/module-cache-tests"

mkdir -p "${TEST_BUILD_DIRECTORY}" "${MODULE_CACHE_DIRECTORY}"

xcrun swiftc \
  -swift-version 5 \
  -warnings-as-errors \
  -module-cache-path "${MODULE_CACHE_DIRECTORY}" \
  "${PROJECT_DIRECTORY}/Sources/Localization.swift" \
  "${PROJECT_DIRECTORY}/Sources/Models.swift" \
  "${PROJECT_DIRECTORY}/Tests/ModelTests.swift" \
  -o "${TEST_BUILD_DIRECTORY}/ModelTests"

"${TEST_BUILD_DIRECTORY}/ModelTests"
