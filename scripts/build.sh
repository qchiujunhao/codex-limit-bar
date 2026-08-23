#!/bin/zsh
set -euo pipefail

SCRIPT_DIRECTORY=${0:A:h}
PROJECT_DIRECTORY=${SCRIPT_DIRECTORY:h}
BUILD_DIRECTORY="${PROJECT_DIRECTORY}/build"
DIST_DIRECTORY="${PROJECT_DIRECTORY}/dist"
APP_DIRECTORY="${DIST_DIRECTORY}/Codex Limit Bar.app"
EXECUTABLE_NAME="CodexLimitBar"
MODULE_CACHE_X86="${BUILD_DIRECTORY}/module-cache-x86_64"
MODULE_CACHE_ARM="${BUILD_DIRECTORY}/module-cache-arm64"

mkdir -p \
  "${BUILD_DIRECTORY}/x86_64" \
  "${BUILD_DIRECTORY}/arm64" \
  "${MODULE_CACHE_X86}" \
  "${MODULE_CACHE_ARM}" \
  "${APP_DIRECTORY}/Contents/MacOS" \
  "${APP_DIRECTORY}/Contents/Resources"

SOURCE_FILES=(
  "${PROJECT_DIRECTORY}/Sources/Localization.swift"
  "${PROJECT_DIRECTORY}/Sources/Models.swift"
  "${PROJECT_DIRECTORY}/Sources/CodexRateLimitClient.swift"
  "${PROJECT_DIRECTORY}/Sources/Views.swift"
  "${PROJECT_DIRECTORY}/Sources/AppDelegate.swift"
  "${PROJECT_DIRECTORY}/Sources/main.swift"
)

xcrun swiftc \
  -swift-version 5 \
  -warnings-as-errors \
  -O \
  -module-cache-path "${MODULE_CACHE_X86}" \
  -target x86_64-apple-macosx13.0 \
  -framework AppKit \
  "${SOURCE_FILES[@]}" \
  -o "${BUILD_DIRECTORY}/x86_64/${EXECUTABLE_NAME}"

xcrun swiftc \
  -swift-version 5 \
  -warnings-as-errors \
  -O \
  -module-cache-path "${MODULE_CACHE_ARM}" \
  -target arm64-apple-macosx13.0 \
  -framework AppKit \
  "${SOURCE_FILES[@]}" \
  -o "${BUILD_DIRECTORY}/arm64/${EXECUTABLE_NAME}"

lipo -create \
  "${BUILD_DIRECTORY}/x86_64/${EXECUTABLE_NAME}" \
  "${BUILD_DIRECTORY}/arm64/${EXECUTABLE_NAME}" \
  -output "${APP_DIRECTORY}/Contents/MacOS/${EXECUTABLE_NAME}"

cp "${PROJECT_DIRECTORY}/Info.plist" "${APP_DIRECTORY}/Contents/Info.plist"
chmod 755 "${APP_DIRECTORY}/Contents/MacOS/${EXECUTABLE_NAME}"
plutil -lint "${APP_DIRECTORY}/Contents/Info.plist"
codesign --force --deep --sign - "${APP_DIRECTORY}"
codesign --verify --deep --strict --verbose=2 "${APP_DIRECTORY}"

ZIP_PATH="${DIST_DIRECTORY}/Codex-Limit-Bar.zip"
if [[ -f "${ZIP_PATH}" ]]; then
  rm "${ZIP_PATH}"
fi
ditto -c -k --sequesterRsrc --keepParent "${APP_DIRECTORY}" "${ZIP_PATH}"

echo
lipo -info "${APP_DIRECTORY}/Contents/MacOS/${EXECUTABLE_NAME}"
shasum -a 256 "${ZIP_PATH}"
echo "Built: ${APP_DIRECTORY}"
echo "Archive: ${ZIP_PATH}"
