#!/bin/bash
# build.sh — Compile StatusBarApp into a macOS .app bundle
#
# Usage:
#   chmod +x build.sh
#   ./build.sh                           # Dev build (arm64 only, fast)
#   ./build.sh --release                 # Universal binary (arm64 + x86_64) + ZIP
#   ./build.sh --release --version v1.0  # Release build with version injected
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

RELEASE=false
VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release)
            RELEASE=true
            shift
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "🔨 Building ${APP_NAME}..."

# Clean
rm -rf "${BUILD_DIR}"
mkdir -p "${MACOS}"
mkdir -p "${RESOURCES}"

SWIFT_FLAGS=(
    StatusBarApp.swift
    -parse-as-library
    -framework SwiftUI
    -framework AppKit
    -framework UserNotifications
    -O
)

if [ "$RELEASE" = true ]; then
    echo "📦 Release build (universal binary)..."

    # Compile arm64
    echo "  Compiling arm64..."
    swiftc "${SWIFT_FLAGS[@]}" \
        -target arm64-apple-macosx14.0 \
        -o "${BUILD_DIR}/${APP_NAME}-arm64"

    # Compile x86_64
    echo "  Compiling x86_64..."
    swiftc "${SWIFT_FLAGS[@]}" \
        -target x86_64-apple-macosx14.0 \
        -o "${BUILD_DIR}/${APP_NAME}-x86_64"

    # Merge into universal binary
    echo "  Creating universal binary..."
    lipo -create \
        "${BUILD_DIR}/${APP_NAME}-arm64" \
        "${BUILD_DIR}/${APP_NAME}-x86_64" \
        -output "${MACOS}/${APP_NAME}"

    # Clean up arch-specific binaries
    rm "${BUILD_DIR}/${APP_NAME}-arm64" "${BUILD_DIR}/${APP_NAME}-x86_64"
else
    # Dev build — arm64 only (fast)
    swiftc "${SWIFT_FLAGS[@]}" \
        -target arm64-apple-macosx14.0 \
        -o "${MACOS}/${APP_NAME}"
fi

# Copy Info.plist
cp Info.plist "${CONTENTS}/Info.plist"

# Inject version into the copied Info.plist (source file untouched)
if [ -n "$VERSION" ]; then
    # Strip leading 'v' if present (v1.0.0 → 1.0.0)
    CLEAN_VERSION="${VERSION#v}"
    echo "  Setting version to ${CLEAN_VERSION}..."
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${CLEAN_VERSION}" "${CONTENTS}/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${CLEAN_VERSION}" "${CONTENTS}/Info.plist"
fi

# Copy app icon if it exists
if [ -f "${APP_NAME}.icns" ]; then
    cp "${APP_NAME}.icns" "${RESOURCES}/"
fi

# Code sign with entitlements (required for notification permissions)
codesign --force --sign - --entitlements StatusBar.entitlements "${APP_BUNDLE}"

echo "✅ Built successfully: ${APP_BUNDLE}"

if [ "$RELEASE" = true ]; then
    lipo -info "${MACOS}/${APP_NAME}"

    # Create ZIP preserving macOS extended attributes and code signatures
    ZIP_NAME="${APP_NAME}-${VERSION:-universal}.zip"
    echo "📦 Creating ${ZIP_NAME}..."
    ditto -c -k --keepParent "${APP_BUNDLE}" "${BUILD_DIR}/${ZIP_NAME}"
    echo "✅ Archive: ${BUILD_DIR}/${ZIP_NAME}"
else
    echo ""
    echo "Run with:  open ${APP_BUNDLE}"
    echo "Or:        ${MACOS}/${APP_NAME}"
fi
