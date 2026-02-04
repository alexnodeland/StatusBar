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

echo "🔨 Building ${APP_NAME}..."

# Clean
rm -rf "${BUILD_DIR}"
mkdir -p "${MACOS}"

# Compile
swiftc StatusBarApp.swift \
    -o "${MACOS}/${APP_NAME}" \
    -parse-as-library \
    -framework SwiftUI \
    -framework AppKit \
    -target arm64-apple-macosx13.0 \
    -O

# Copy Info.plist
cp Info.plist "${CONTENTS}/Info.plist"

echo "✅ Built successfully: ${APP_BUNDLE}"
echo ""
echo "Run with:  open ${APP_BUNDLE}"
echo "Or:        ${MACOS}/${APP_NAME}"
