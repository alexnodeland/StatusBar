#!/bin/bash
# build.sh — Compile StatusBarApp into a macOS .app bundle
#
# Usage:
#   chmod +x build.sh
#   ./build.sh
#
# After building, the app will be at ./build/StatusBar.app
# You can double-click it or run: open ./build/StatusBar.app

set -euo pipefail

APP_NAME="StatusBar"
BUILD_DIR="./build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "🔨 Building ${APP_NAME}..."

# Clean
rm -rf "${BUILD_DIR}"
mkdir -p "${MACOS}"
mkdir -p "${RESOURCES}"

# Compile
swiftc StatusBarApp.swift \
    -o "${MACOS}/${APP_NAME}" \
    -parse-as-library \
    -framework SwiftUI \
    -framework AppKit \
    -framework UserNotifications \
    -target arm64-apple-macosx14.0 \
    -O

# Copy Info.plist
cp Info.plist "${CONTENTS}/Info.plist"

# Copy app icon if it exists
if [ -f "${APP_NAME}.icns" ]; then
    cp "${APP_NAME}.icns" "${RESOURCES}/"
fi

# Code sign with entitlements (required for notification permissions)
codesign --force --sign - --entitlements StatusBar.entitlements "${APP_BUNDLE}"

echo "✅ Built successfully: ${APP_BUNDLE}"
echo ""
echo "Run with:  open ${APP_BUNDLE}"
echo "Or:        ${MACOS}/${APP_NAME}"
